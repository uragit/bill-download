#!/usr/bin/ruby

require 'rubygems'
require 'watir-webdriver'
require 'getoptlong'
require 'time'

config_filename='./comcast.conf'

####################################
####################################

cfg={}
begin
  file = File.new(config_filename, "r")
  while (line = file.gets)
    line.chomp!
    if (/^\s*\#/ =~ line) 
      next
    end
    parameter, value=line.split(/\s+=\s+/)
    #puts "  parameter: '#{parameter}',  value: '#{value}'"
    if (not parameter.nil?) 
      if (value.nil?)
        value=''
      end
      cfg[parameter.strip]=value.strip
    end
  end
  file.close
rescue => err
  puts "Error reading config file (#{config_filename}) #{err}"
  err
end

username=cfg['username']
password=cfg['password']

if (username.nil? || password.nil?)
  puts "Can't get login credentials from config file."
  exit
end


# Where we're going to collect all the downloaded, renamed files.
destdir=cfg['destdir'].nil? ? "downloads/comcast" : cfg['destdir']

# Where to stash temporary files.  (Note: we'll also append the PID)
tempdir=cfg['tempdir'].nil? ? "downloads/tmp" : cfg['tempdir']
tempdir=tempdir+"."+Process.pid.to_s

# What to do at run time.
download_voicemails=cfg['download_voicemails'].nil? ? 1 : cfg['download_voicemails'].to_i
del_prev_downloaded_voicemails=cfg['del_prev_downloaded_voicemails'].nil? ? 0 : cfg['del_prev_downloaded_voicemails'].to_i
download_bills=cfg['download_bills'].nil? ? 1 : cfg['download_bills'].to_i


####################################
####################################

progname=File.basename($0)


opts=GetoptLong.new(
                    ["--help", "-h", GetoptLong::NO_ARGUMENT],
                    ["--destdir", "-d", GetoptLong::REQUIRED_ARGUMENT],
                    ["--tempdir", "-t", GetoptLong::REQUIRED_ARGUMENT]
                    )

opts.each { |option, value|
		case option
		when "--help"
                  puts "Usage: use it right"
                  exit
		when "--destdir"
                  destdir = value
		when "--tempdir"
                  tempdir = value
		end
}
#   rescue => err
#         puts "#{err.class()}: #{err.message}"
#         puts "Usage: -h -u -i -s filename"
#         exit
 

#puts "Destdir =#{destdir}"
#puts "Tempdir =#{tempdir}"



months={
  'january'   =>  1,
  'february'  =>  2,
  'march'     =>  3,
  'april'     =>  4,
  'may'       =>  5,
  'june'      =>  6,
  'july'      =>  7,
  'august'    =>  8,
  'september' =>  9,
  'october'   => 10,
  'november'  => 11,
  'december'  => 12
}







def format_callerid(caller_number)

  # Likely number formats:
  #   caller_number='+1 613‑914‑6748'   (This is canada, so 'international')
  #   caller_number='+44 166‍1 248783'
  #   caller_number='(417) 800‑2006'
  #   caller_number='(510) 275‑7038'
  #   caller_number='Anonymous'
  #   caller_number='Out Of Area'

  #puts "  Caller_number='#{caller_number}'"

  # Some odd characters in the numbers:
  # '   (   4   0   8   )       3   2   9 342 200 221   8   2   5 342 200 215   3   '
  # For safety we just remove any non-printable characters.
  caller_number=caller_number.scan(/[[:print:]]/).join

  if (/^\+[-\d\s]+$/ =~ caller_number)
    puts "  International number"
    # But if it's +1, we just format it like a US number.
    if (/^\+1\s+[-\d\s]+$/ =~ caller_number)
      puts "  But it's actually a regular north america number."
      caller_number.sub!(/^\+1\s+/, "")
      caller_number.gsub!(/[^\d]/, "")
    else
      caller_number.sub!(/^\+/, "")
    end
  elsif (/^[-\d\s\(\)]+$/ =~ caller_number)
    puts "  Looks like a domestic US number."
    # Pull the spaces out (so they don't get replace with '_' later.
    caller_number.gsub!(/\s/, "")
  elsif ( (/^Anonymous/i =~ caller_number) || (/^Out Of Area/i =~ caller_number))
    # Might as well just use this instead.
    caller_number='0000000000'
  else
    # No idea what might make it this far.
    # Just in case, get rid of anything that might cause trouble.
    # Just leave letters and numbers, and '_'.  (Space would get stripped out later anyway.)
    caller_number.gsub!(/[^\da-zA-Z_]/, "")
  end
  #
  # Some operations we might as well apply to all patters, just in case.
  caller_number.gsub!(/\s/, "_")
  caller_number.gsub!(/[-\(\)]/, "")

  #puts "  Caller_number='#{caller_number}'"

  return(caller_number)
end











puts progname+' starting'



if (! File.directory?(destdir))
  puts 'Destination directory not found ('+destdir+').'
  exit
end



# Let's collect all the files we've already got downloaded (or scanned)
#
existing_pdfs={};
existing_voicemails={};
existing_voice_calls={};
existing_voice_calls_pdf={};
filename_map={};
#
puts 'Listing existing files in download directory:'
Dir.foreach(destdir) { |filename|
  if    (filename =~ /^comcast_statement.d(\d+).pdf$/) 
    #puts '  Filename: '+filename
    existing_pdfs[Regexp.last_match[1]]=1
  elsif (filename =~ /^comcast_statement.voice_calls.d(\d+).html$/) 
    existing_voice_calls[Regexp.last_match[1]]=1
  elsif (filename =~ /^comcast_statement.voice_calls.d(\d+).pdf$/) 
    existing_voice_calls_pdf[Regexp.last_match[1]]=1
  elsif (filename =~ /^voicemail\.(d[\d_A-Z]+\.)[^\.]+\.(from[\d_]+)\..*\.mp3$/) 
    key=Regexp.last_match[1]+Regexp.last_match[2]
    puts "  Existing voicemail file, key is: "+key
    existing_voicemails[key]=1
  end
} 
downloaded_files=0


puts 'Place for temp files: '+tempdir

if (File.directory?(tempdir))
  puts "  Directory exists."
else
  puts "  Directory ("+tempdir+") does not exist.  Creating."
  Dir.mkdir(tempdir)
  # ???????? Fail on errors (if a regular file already exists with the name, etc)
end


## Chrome
##
profile = Selenium::WebDriver::Chrome::Profile.new
profile['download.prompt_for_download'] = false
profile['download.default_directory'] = tempdir
##
##profile = Selenium::WebDriver::Firefox::Profile.new
profile['browser.download.dir'] = tempdir
profile['browser.download.folderList'] = 2
profile['browser.helperApps.neverAsk.saveToDisk'] = "application/pdf"

#browser = Watir::Browser.new :chrome, :switches => %w[--ignore-certificate-errors --disable-popup-blocking --disable-translate]
#browser = Watir::Browser.new :chrome, :switches => %w[--disable-plugins]
#browser = Watir::Browser.new :chrome, :profile => profile
#browser = Watir::Browser.new :chrome
#browser = Watir::Browser.new :chrome,  :profile => profile, :switches => %w[--disable-plugins]
browser = Watir::Browser.new :chrome,  :profile => profile


## Chrome
##
#profile = Selenium::WebDriver::Chrome::Profile.new
#profile['download.prompt_for_download'] = false
#profile['download.default_directory'] = '/big/emmerson/junk66'
##
##profile = Selenium::WebDriver::Firefox::Profile.new
#profile['browser.download.dir'] = "/big/emmerson/junk66"
#profile['browser.download.folderList'] = 2
#profile['browser.helperApps.neverAsk.saveToDisk'] = "application/pdf"


#browser = Watir::Browser.new :ff
#browser = Watir::Browser.new :firefox
#browser = Watir::Browser.new :chrome, :profile => profile

#browser = Watir::Browser.new :chrome

mycontainer = Watir::Container


def disable_pdf_plugin(browser)

  puts 'Going to about:plugins page (to disable plugins, so PDFs save):'

  # This is much simpler!
  # disable Chrome PDF Viewer
  browser.goto "about:plugins"
  browser.span(:text => "Chrome PDF Viewer").parent.parent.parent.a(:text => "Disable", :class => "disable-group-link").click

  #  browser.goto 'about:plugins'
  #  #sleep(1)
  #  browser.links.each { 
  #    |l|
  #
  #    begin
  #      
  #      #puts '  looking for Disable pdf: '+l.text
  #
  #      # Just disable all 'Disable' links.  Saves identifying the right one.
  #      if (l.text =~ /Disable/)
  #        begin
  #          #puts '    Disabling'
  #          l.click
  #          #sleep(1)
  #        rescue
  #          # Sometimes it fails for bizarre reasons.
  #          #puts 'Rescue 1'
  #        end
  #      end
  #    rescue
  #      # This is where it seems to bizarrely fail.  Presumably on 'l.text' or 'l.href.to_s' on some links.
  #      #puts 'Rescue 2'
  #    end
  #  }


end



disable_pdf_plugin(browser)




#browser.title == 'WATIR: Schwab download'

#browser.goto 'http://bit.ly/watir-example'
#browser.goto 'http://bit.ly/watir-example'


puts "Going to login page."

browser.goto 'https://customer.comcast.com/secure/Home.aspx'


puts "  Filling in fields and clicking on sign-in."

browser.text_field(:index, 0).set username
browser.text_field(:index, 1).set password

browser.button(:id, "sign_in").click




voicemail_filenames={}
renamed_mp3s = 0
renamed_voicemail_ids={}
my_tn=""
failed_voicemail_ids=[]


# Might have to pass through more than once; the voicemail download can be a bit dodgy.
tries_left=1
loop_count=0
while (tries_left>0) 
  tries_left -= 1
  loop_count += 1

  if (download_voicemails==1)

    puts "Going to view voicemails."
    browser.goto 'http://vmail.connect.comcast.net/voice/'

    if (loop_count==1) # Only on the first pass
      # Find the phone number.
      number_dropdown=browser.div(:id, "number_switcher")
      #????????????? If the next line fails, we probably didn't get logged in.
      #  /usr/lib64/ruby/gems/1.8/gems/watir-webdriver-0.5.2/lib/watir-webdriver/elements/element.rb:359:in `assert_exists': unable to locate element, using {:tag_name=>"div", :id=>"number_switcher"} (Watir::Exception::UnknownObjectException)
      #
      number_dropdown.buttons.each {
        |b|
        # The first one will have the text of the selected options.
        # Any subsequent ones will have blank text, but contain a div
        # that contains the text.  For now, we're only interested in
        # the first phone number so it will do for now.

        puts "Button!"+b.text
        if (my_tn=="")
          puts "Setting my_tn to '#{b.text}'."
          my_tn=b.text.gsub(/[^\d]/,  "")  # Only the digits.
        end
      }
    end

    message_table=browser.table(:id, "message_list")
    #message_table.rows.each do |r|
    #  puts r.to_s
    #  r.cells.each do |c|
    #    puts "  Cell:"+c.text
    #  end
    #  callerid_name=r.cell(:index, 2).text
    #  callerid_time=r.cell(:index, 3).text
    #  # This time is just the date and doesn't always have the year.  Ignore it.  Grab from the detailed info later.
    #  puts "    Name='"+callerid_name+"'  Time='"+callerid_time+"'"
    #end

    #sleep(2)  # In case it needs some time to settle.

    puts "Let's go through the voicemail."
    # The first time, we just use the index of the voicemail rows.
    if (loop_count==1)
      len=message_table.rows.length
    else
      # Subsequent efforts, we use the list of id's of the failed rows.
      len=failed_voicemail_ids.length
    end

    # Need to store a list of filenames for remapping
    #0.upto(10) {
    0.upto(len - 1) {
      |i|

      if (loop_count==1)
        # Going through the whole list by index.
        puts "Going for message with index #{i.to_s}.  Clicking on the list item."
        voicemail_row=message_table.row(:index, i)
        voicemail_id=voicemail_row.id # This seems to be the only way to relate back to the generated file.
      else
        # Going through previous failures by id.
        voicemail_id=failed_voicemail_ids.shift
        puts "Going for message with id='#{voicemail_id.to_s}'.  Clicking on the list item."
        voicemail_row=message_table.row(:id, voicemail_id)
        
      end

      voicemail_row.click
      

      #sleep(2)  # It needs some time to settle down, or we get random download failures.
      # Without delay, 20% failure.  With one second, 5%.  With two seconds, 0% failure.
      # Hmmm, make it 3.  There's still some errors at 2 seconds.
      # Hmmm, make it 4.  There's still some errors at 3 seconds.
      # Nah, we'll just make multiple passes until we get it right!


      voicemail_div=browser.div(:id, 'vm_message')
      #voicemail_div.buttons.each do |b|
      #  puts "  Button"+b.text
      #end

      # Grab the caller info.
      #voicemail_div.divs.each do |d|
      #  puts "  Div: "+d.to_s
      #end
      name_text=voicemail_div.div(:class, 'name_text').text
      contact_text=voicemail_div.div(:class, 'contact_token').text
      date_text=voicemail_div.div(:class, 'date').text
      location_text=voicemail_div.div(:class, 'location_text').text

      puts "  NAME_TEXT: '"+name_text+"'   CONTACT: '"+contact_text+"'"
      puts "  DATE: '"+date_text+"'  LOCATION: '"+location_text+"'"


      # Contact_text is the number, unless blank, in which case look at name_text for number.
      
      if (contact_text=='')
        caller_number=name_text
        caller_name=""
      else
        caller_number=contact_text
        caller_name=name_text
      end


      caller_number=format_callerid(caller_number)

      # For safety we just have a go at removing all non printable characters.
      caller_name=caller_name.scan(/[[:print:]]/).join
      # Then use '_' instead of whitespace.
      caller_name.gsub!(/\s+/, "_")
      # And use downcase, because we're unix people.
      caller_name.downcase!
      if (caller_name=='') 
        caller_name='no_name'
      end

      # Make the location safe.
      location_text=location_text.scan(/[[:print:]]/).join.downcase.gsub(/\s+/, "_").gsub(/[^\da-zA-Z_]/, "")

      # Looks like this:
      #   date_text looks like this Tuesday  |  October 8, 2013  |  10:49 AM PDT  |  44 seconds
      #   date_text looks like this Tuesday  |  October 8, 2013  |  10:49 AM PDT  |  1 minute 44 seconds
      #   date_text looks like this Tuesday  |  October 8, 2013  |  10:49 AM PDT  |  2 minutes 44 seconds ??
      day, date, time, duration=date_text.split(/\s*\|\s*/)

      t=Time.parse(date+" "+time)
      ##puts t.iso8601
      puts "  time.parse: "+t.strftime("  %Y%m%d %H%M %Z")
      yyyymmdd_hhmm_tz=t.strftime("%Y%m%d_%H%M_%Z")

      duration_words=duration.split(/\s+/)
      if (duration_words.length==4)
        puts "  Duration is mins and seconds"
        duration_secs=duration_words[0].to_i*60 + duration_words[2].to_i
      else
        puts "  Duration is just seconds"
        duration_secs=duration_words[0].to_i
      end


      puts "  Parsed:"
      puts "    caller_number='#{caller_number}'"
      puts "    caller_name='#{caller_name}'"
      puts "    location='#{location_text}'"
      puts "    datestring='#{yyyymmdd_hhmm_tz}'"
      puts "    duration='#{duration_secs}'"
      puts "    voicemail_id='#{voicemail_id}'"


      # Careful, if you change this remember to change pattern when listing existing files.
      filename="voicemail.d#{yyyymmdd_hhmm_tz}.to#{my_tn}.from#{caller_number}.#{caller_name}.#{location_text}.#{duration_secs}secs.mp3"
      puts "    Filename: "+filename

      key ="d#{yyyymmdd_hhmm_tz}.from#{caller_number}"
      puts "    key: "+key


      if (existing_voicemails[key]==1)
        puts "      We've already got this voicemail."
        # Should we delete it from their web server.
        if (del_prev_downloaded_voicemails==1)
          # Click the delete button.
          puts "\007"  # Ring a bell.
          delete_button=voicemail_div.button(:text, 'Delete message')
          puts "      The button:"+delete_button.text
          puts "      Clicking it..."
          delete_button.click
          sleep(5)  # In case it needs some time to settle.
        end
      else
        puts "      We don't already have this file (downloading): "+filename

        download_button=voicemail_div.button(:text, 'Download voicemail')
        puts "      The button:"+download_button.text
        puts "      Clicking it..."
        download_button.click
        #sleep(2)  # In case it needs some time to settle.  Seems to help a good deal.

        # We use the voicemail_id that we grabbed earlier to make sure 
        # we relate their filenames to ours.
        voicemail_filenames[voicemail_id]=filename

        downloaded_files += 1

      end

    }
    if (downloaded_files>0) 
      puts "Pausing after downloading voicemail files to allow downloads to finish."
      sleep(10)
    end
  end


  if ( (download_bills==1) && (loop_count==1) ) # Only doing once.  Seems solid.
    puts "Going to view bills."

    browser.goto 'https://customer.comcast.com/Secure/MyAccount/'

    # Press the 'view more' button to see all available bills.
    # Sometimes this fails because the link isn't visible.
    # ?????????? Would be better to test for existence of element.
    #
    clicked=0
    click_attempts=1
    while (clicked==0) 
      begin
        puts "  Clicking on 'view more'."
        #browser.div(:id, "main_1_pastbills_0_BillHistoryViewMore").link.click
        browser.div(:id, "main_1_billdetails1302_5_BillHistoryViewMore").link.click
        clicked=1
      rescue
        # Turns out this extra jiggery probably wasn't needed.  Fixed by changing the div-id above.
        puts "    Didn't manage to click on the 'view more' link.  Press space to bring into view."
        browser.send_keys :space  # This is a kludgey way to make sure the link is visible
        sleep(1)
        click_attempts += 1
        if (click_attempts > 4)
          puts "Giving up."
          exit
        end
      end
    end




    puts "  Listing bills."

    # Just grabbing the main PDFs of the monthly statements.  This bit is straightforward.
    browser.div(:id, 'past-bills').links.each { 
      |l|
      
      #puts l.href.to_s

      if (l.text =~ /^Billed\s+([a-zA-Z]+)\s+(\d+),\s+(\d+)\s*$/)
        puts '    '+l.text   # Billed January 18, 2013

        # Let's see if we've already got the file.
        mm  =months[Regexp.last_match[1].downcase]
        dd  =Integer(Regexp.last_match[2])
        yyyy=Integer(Regexp.last_match[3])

        key= "%04d%02d%02d" % [ yyyy,mm,dd ]

        puts "      File key="+key

        if (existing_pdfs[key]==1)
          puts "      We've already got this file."
        else
          puts "      We don't already have this file (downloading): "+l.text
          l.click
          downloaded_files += 1

        end
      end
    }


    puts 'Clicking on View Call Details link.'
    # Clicking the link causes javascript to open a new tab, so we goto the href instead of clicking.
    browser.goto(browser.link(:text, /^View call details/).href.to_s)


    puts 'Select_list options: '

    len=browser.select_list(:name, "comboBox").options.length

    0.upto(len-1) {
      |i|
      
      combo=browser.select_list(:name, "comboBox")
      o=combo.options[i]
      edited=o.text.gsub(/\s+/, " ")
      puts '  i='+i.to_s+'    '+o.text+'  '+edited

      # puts "\007"  # Ring a bell.

      if (edited =~ /UnBilled Activity/) 
        puts "    We skip any attempted download of the UnBilled Activity selection"
        next
      end

      #browser.select_list(:name, "comboBox").select(o.text)  # Barfs, because it's not the same select_box after selection

      combo.select(edited)
      i += 1
      sleep(3)  # In case it needs to settle down.

      # If it fits on the page, good, if not, it offers a 'view all' link to click.
      if (browser.link(:text, /^View All/).exists?)
        puts '    Clicking the View All link'
        browser.link(:text, /^View All/).click
        puts '    Done click on View All link.'
        sleep(2)  # In case it needs to settle down.
      else
        puts '    No need to click any View All link (because there isnt one).'
      end

      # Annoyingly, the usage doesn't have day of the month easily accessible.
      # Find it here.
      # (Or could figure it out from the statement dates on the main billing page.)
      #   (If doing that, could skip actually selecting the option on the drop-down.)
      #
      # >Statement Date:</b>&nbsp;<b class="outlinedata">01/18/13</b></td>
      browser.html =~ /Statement Date:<\/b>\&nbsp;<b class="outlinedata">([\d\/]+)<\/b><\/td>/
      datestring=Regexp.last_match[1]
      #
      #
      datestring =~ /^(\d+)\/(\d+)\/(\d+)$/
      mm   = Regexp.last_match[1].to_i
      dd   = Regexp.last_match[2].to_i
      yyyy = Regexp.last_match[3].to_i + 2000
      #
      key= "%04d%02d%02d" % [ yyyy,mm,dd ]
      puts '    Found: "'+datestring+'"   Key: "'+key+'"'

      if (existing_voice_calls[key]==1)
        puts "      We've already got this voice calls html file."
      else
        filename=File.join(destdir, 'comcast_statement.voice_calls.d'+key+'.html')
        puts "      We don't already have this voice calls html file (downloading): "+filename
        File.open(filename, 'w') {|f| f.write(browser.html) }


        # Let's see if we can parse out the call records.
        # (Nah, write a separate parser to pull out the html.)
      end

      # Might as well grab the pdf of the voicecalls while we're here.
      if (existing_voice_calls_pdf[key]==1)
        puts "      We've already got this voice calls pdf file."
      else
        puts "      We don't already have this voice calls pdf file (downloading): "
        browser.link(:text, /^print/).click
        downloaded_files +=1
        # Need to store a mapping from: ComcastMarch_12.pdf -> 20120318
        remap_key= "%04d%02d" % [ yyyy,mm ]
        puts "remap_key='"+remap_key+"'"
        filename_map[remap_key]=key
      end
      
    }
    puts ''

  end




  if (downloaded_files==0) 
    puts 'No new files to download.'

    # ???? Some sanity checks, based on actual date, vs listed html
    # files, vs previously download files.

  else
    puts 'Files downloaded: '+downloaded_files.to_s
    puts 'Going to downloads page to confirm saving files:'

    # Pause a bit to make sure everything has finished downloading.
    # (Otherwise the last voicemail mp3 might not show on the page.  Perhaps PDFs too.)
    sleep(5)

    saved_mp3_filename=''

    browser.goto 'chrome://downloads/'
    browser.div(:id, 'downloads-display').buttons.each { 
      |l|
      puts '  download links: '+l.text
      if l.text =~ /Save/
        puts '    Save the file'
        #puts "\007"  # Ring a bell.
        begin
          l.click
        rescue
          puts "      Saving failed, but that usually happens with mp3 files, with no save button.  No biggie."
        end
      end
    }

    # And now lets list the links again because we might need to know the filenames.
    sleep(2) # To make sure the document has settled down a bit before we ask for the new links.
    puts 'Listing the links on the downloads page:'
    browser.div(:id, 'downloads-display').links.each { 
      |l|
      
      #puts '  download links: '+l.text

      if (loop_count==1)  # Only the voicemail download process is shakey.
        # 2012-07-18_bill.pdf
        # 2012-07-18_bill (4).pdf
        #
        if (l.text =~ /^(\d+)-(\d+)-(\d+)_bill.*\.pdf$/)
          puts '  download statement pdf links: '+l.text

          yyyy = Regexp.last_match[1].to_i
          mm   = Regexp.last_match[2].to_i
          dd   = Regexp.last_match[3].to_i

          key= "%04d%02d%02d" % [ yyyy,mm,dd ]

          # ???? Should make some effort to check that the list of files we
          # tried to download meshes in some way with the ones we see here.
          # Either by name or sequence.  or both.

          newfilename=File.join(destdir, 'comcast_statement.d'+key+'.pdf')

          puts '    File.rename('+File.join(tempdir, l.text)+', '+newfilename+')'
          File.rename(File.join(tempdir, l.text), newfilename)
          
        end
        # ComcastFebruary_12 (1).pdf
        # ComcastMarch_12.pdf
        #
        if (l.text =~ /^Comcast([A-Z][a-z]+)_([\d\s\\(\)]+)\.pdf/)
          puts '  download voice calls pdf links: '+l.text

          month = Regexp.last_match[1].downcase
          mm    = months[month]
          yy    = Regexp.last_match[2]
          # Needs more hacking about, because yy isn't reliable.  May contain extraneous characters.

          puts "    Month="+month+"   yy='"+yy+"'"

          yy =~ /(\d+)[\.\s]*/
          yy_real  =Regexp.last_match[1]
          yyyy = 2000+yy_real.to_i
          
          puts "    Month="+month+"   mm='"+mm.to_s+"'   yy='"+yy+"' yy_real='"+yy_real+"'"

          # Need to store a mapping from: ComcastMarch_12.pdf -> 20120318
          remap_key= "%04d%02d" % [ yyyy,mm ]
          puts "    remap_key='"+remap_key+"'"

          newfilename=File.join(destdir, 'comcast_statement.voice_calls.d'+filename_map[remap_key]+'.pdf')

          puts '    Do:    File.rename('+File.join(tempdir, l.text)+', '+newfilename+')'
          File.rename(File.join(tempdir, l.text), newfilename)

        end
      end


      if (l.text =~ /^cas\d+\.mp3/)
        # Next link will give us the extra info we need.
        saved_mp3_filename=l.text
        puts "  Saving filename for next time around the loop '#{saved_mp3_filename}'"
        
      elsif (l.text =~ /^https:\/\/secure.api.comcast.net\/voicecust\/vm\/platform\/phone\/[\d\.]+\/message\/download\/(\d+)\/mp3\/.*$/)
        
        voicemail_id=Regexp.last_match[1]


        if ( (voicemail_id.nil?) || (voicemail_id=='') || (saved_mp3_filename=='') )
          puts "HORRIFIC FILE RENAMING PROBLEM.  voicemail_id='#{voicemail_id}', renamed_mp3s=#{renamed_mp3s}"
          # ?????????? Do something terrible.
        else

          puts "  download voicemail mp3 link (count=#{renamed_mp3s}, id=#{voicemail_id}): "+saved_mp3_filename

          # Have we already renamed it in a previous pass?
          if (renamed_voicemail_ids[voicemail_id]==1)
            puts "We've already downloaded/renamed this one before"
          else

            newfilename=File.join(destdir, voicemail_filenames[voicemail_id])
            
            puts '    Do:    File.rename('+File.join(tempdir, saved_mp3_filename)+', '+newfilename+')'
            
            File.rename(File.join(tempdir, saved_mp3_filename), newfilename)
            # ???? Might be better if moving cross filesystems.  FileUtils.mv(File.join(tempdir, l.text), newfilename)
            
            renamed_voicemail_ids[voicemail_id]=1
            renamed_mp3s += 1
          end
        end

        saved_mp3_filename=''
      else
        saved_mp3_filename=''
      end
    }
  end

  failed_voicemail_ids=[]
  # Check we downloaded all the voicemail mp3s we were expecting.
  puts "Checking we got all the mp3 files correctly downloaded/renamed."
  voicemail_filenames.keys.each {
    |voicemail_id|

    if (renamed_voicemail_ids.has_key?(voicemail_id) )
      puts "  voicemail_id #{voicemail_id} renamed.  (This is good.)"
    else
      puts "  voicemail_id #{voicemail_id} NOT RENAMED.   ERROR."
      failed_voicemail_ids.push(voicemail_id)
      tries_left=1 # Make it go round again.
    end
  }

  # We keep just a count of the files downloaded in each pass, so reset here.
  downloaded_files=0

end

puts "Deleting the temporary directory (#{tempdir})"  # Which should be empty
begin
  Dir.rmdir(tempdir)
rescue
  puts "Warning: problems deleting directory (#{tempdir})."
end

puts "\007"  # Ring a bell.
sleep(1)
puts "\007"  # Ring a bell.
sleep(1)
puts "\007"  # Ring a bell.
sleep(1)
puts "\007"  # Ring a bell.
sleep(1)
puts "\007"  # Ring a bell.
puts "\007"  # Ring a bell.
puts "\007"  # Ring a bell.
puts "\007"  # Ring a bell.

pause_secs=5
puts progname+' exiting in '+pause_secs.to_s+' seconds...'
#
#
#
sleep(pause_secs)  # To make sure things have settled down.

#
# Logout page
browser.goto 'https://customer.comcast.com/LogOut/logout.aspx'
sleep(pause_secs)

browser.close

puts progname+' ended'

exit



