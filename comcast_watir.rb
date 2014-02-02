#!/usr/bin/ruby



# Converting the CDR data into a standard format for various automation scripts.
#   n, the nth call in this
#   date_time, start time of call (iso.8601, with timezone)
#   Calling TN (Can be tricky depending on info we can figure out)
#   Called TN  (Can be tricky depending on info we can figure out)
#   Call duration (in seconds)
#   amount       (In $dollars.cents, so tax can be a fraction if needed.)
#   tax          (In $dollars.cents, so tax can be a fraction if needed.)
#   total_amount (In $dollars.cents, so tax can be a fraction if needed.)
#   Rate type (RM45, or whatever the heck)
#   Call status (completed, for example, or whatever the heck)
#   Call type (voice, SMS, etc)
#   Billed TN
#   Location (Could be to or from, depending on call in or out of the number we own)

require 'rubygems'
require 'watir-webdriver'
require 'getoptlong'
require 'time'
require 'fileutils'

config_filename='./comcast.conf'

####################################
####################################

# Normally the command-line options are read after the config file
# so the command-line options can override the config file settings.
# Except for the '--config filename' setting which we'll need to know
# now.

ARGV.each_with_index { |arg, i|
  if ( (arg=='--config') || (arg=='-c') )
    config_filename=ARGV[i+1]
  end
}


cfg={}
begin
  file = File.new(config_filename, "r")
  while (line = file.gets)
    line.chomp!
    if (/^\s*\#/ =~ line) 
      next
    end
    parameter, value=line.split(/\s*=\s*/)
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

# Where we're going to collect all the downloaded, renamed files.
destdir=cfg['destdir'].nil? ? "downloads" : cfg['destdir']

# Where to stash temporary files.  (Note: we'll also append the PID)
tempdir=cfg['tempdir'].nil? ? "downloads/tmp" : cfg['tempdir']

username=cfg['username']
password=cfg['password']

# In which timezone do you want times interpreted?
timezone=cfg['timezone'].nil? ? 'PST8PDT' : cfg['timezone']
# If it ends up blank, US times will be be interpeted as machine local time.

# What to do at run time.
download_bills      = cfg['download_bills'].nil? ? 1 : cfg['download_bills'].to_i
download_voicemails = cfg['download_voicemails'].nil? ? 1 : cfg['download_voicemails'].to_i
del_prev_downloaded_voicemails = cfg['del_prev_downloaded_voicemails'].nil? ? 1 : cfg['del_prev_downloaded_voicemails'].to_i


####################################
####################################

progname=File.basename($0)


begin
  # Command-line options, will override settings in config file.

  def printusage()
    puts 
    puts "Usage: #{$0} [options]"
    puts "Options:" 
    puts "  --config|-c filename    (configuration file with key=value pairs"
    puts "  --destdir|-d directory  (for final destination of downloading)"
    puts "  --tempdir|-t directory  (for temporary staging)"
    puts "  --username|-u username  (safer to specify in config file)"
    puts "  --password|-p password  (safer to specify in config file)"
    puts "  --timezone timezone        (Timezone for interpreting usage timestamps, default PST8PDT)"
    puts "  --download_bills"
    puts "  --download_voicemails"
    exit(1)
  end

  opts=GetoptLong.new(
                      ["--help",     "-h",      GetoptLong::NO_ARGUMENT],
                      ["--config",   "-c",      GetoptLong::OPTIONAL_ARGUMENT],
                      ["--destdir",  "-d",      GetoptLong::REQUIRED_ARGUMENT],
                      ["--tempdir",  "-t",      GetoptLong::REQUIRED_ARGUMENT],
                      ["--username", "-u",      GetoptLong::REQUIRED_ARGUMENT],
                      ["--password", "-p",      GetoptLong::REQUIRED_ARGUMENT],
                      ["--timezone",            GetoptLong::REQUIRED_ARGUMENT],
                      ["--download_bills",      GetoptLong::NO_ARGUMENT],
                      ["--download_voicemails", GetoptLong::NO_ARGUMENT]
                    )

  opts.each { |option, value|
    case option
    when "--help"
      printusage()
    when "--destdir"
      destdir = value
    when "--config"
      # Nothing to do.  Handled earlier.
    when "--tempdir"
      tempdir = value
    when "--username"
      username = value
    when "--password"
      password = value
    when "--timezone"
      timezone = value
    when "--download_bills"
      download_bills = 1
    when "--download_voicemails"
      download_voicemail = 1
    else
      puts "Hmmm: option='#{option}'  value='#{value}'"
    end
  }
  if ARGV.length !=0
    ARGV.each { |arg|
      puts "Extra arg supplied: '#{arg}'"
    }
    printusage()  # Will exit
  end

rescue => err
  puts "#{err.class()}: #{err.message}"
  printusage()  # Will exit
end

####################################
####################################

# Sanity check some of the args from config file and/or command line.

if (username.nil? || password.nil?)
  puts "Can't get login credentials from config file."
  exit
end

# Add PID to tempdir pathname.
tempdir=tempdir+"."+Process.pid.to_s

puts 'Place for temp files: '+tempdir

if (File.directory?(tempdir))
  puts "  Directory exists."
else
  puts "  Directory ("+tempdir+") does not exist.  Creating."
  Dir.mkdir(tempdir)
  # ????? Fail on errors (if a regular file already exists with the name, etc)
end


if (! File.directory?(destdir))
  puts "Can't find destination directory (#{destdir}).  Exiting.  Perhaps you're running in the wrong directory."
  exit
end



####################################
####################################

def bell()
  # Ring a terminal bell, but only if we don't have stdout piped.
  # (It would make more sense to figure out if we're in a terminal, perhaps)
  if (File.pipe?($stdout) )
    # Don't ring a bell; probably sending output to /usr/bin/mail or similar.
  else
    puts "\007"  # Ring a bell.
  end
end


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
  #   caller_number='+1 613‑555‑6748'   (This is canada, so 'international')
  #   caller_number='+44 181‍1 555783'
  #   caller_number='(417) 555‑2006'
  #   caller_number='(510) 555‑7038'
  #   caller_number='Anonymous'
  #   caller_number='Out Of Area'

  #puts "  Caller_number='#{caller_number}'"

  # Some odd characters in the numbers:
  # '   (   4   0   8   )       5   5   5 342 200 221   1   2   5 342 200 215   7   '
  # For safety we just remove any non-printable characters.
  # (This has probably already been cleaned up by the time it gets here.)
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





####################################
####################################




# Trying to fix:
#/var/lib/gems/1.8/gems/selenium-webdriver-2.31.0/lib/selenium/webdriver/remote/capabilities.rb:141:in `json_create': undefined method `downcase' for nil:NilClass (NoMethodError)
#
#cap = Selenium::WebDriver::Remote::Capabilities.linux
#cap['acceptSslCerts'] = true
#driver = Selenium::WebDriver.for :linux, :desired_capabilities => cap


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
#profile['download.default_directory'] = "/home/download"
##
##profile = Selenium::WebDriver::Firefox::Profile.new
#profile['browser.download.dir'] = "/home/download"
#profile['browser.download.folderList'] = 2
#profile['browser.helperApps.neverAsk.saveToDisk'] = "application/pdf"


#browser = Watir::Browser.new :ff
#browser = Watir::Browser.new :firefox
#browser = Watir::Browser.new :chrome, :profile => profile

#browser = Watir::Browser.new :chrome

mycontainer = Watir::Container


disable_pdf_plugin(browser)



summary=""

start_time=Time.now
puts       "#{progname} starting: #{start_time}"
summary += "#{progname} started:  #{start_time}\n"



#############################################
#      End of the (mostly) boilerplate      #
#############################################




# Let's collect all the files we've already got downloaded (or scanned)
#
existing_pdfs={};
existing_voicemails={};
existing_voice_calls_html={};
existing_voice_calls_csv={};
existing_voice_calls_pdf={};
filename_map={};
#
puts 'Listing existing files in download directory:'
Dir.foreach(destdir) { |filename|
  if    (filename =~ /^comcast_statement.d(\d+).pdf$/) 
    #puts '  Filename: '+filename
    existing_pdfs[Regexp.last_match[1]]=1
  elsif (filename =~ /^comcast_statement.voice_calls.d(\d+).html$/) 
    existing_voice_calls_html[Regexp.last_match[1]]=1
  elsif (filename =~ /^comcast_statement.voice_calls.d(\d+).csv$/) 
    existing_voice_calls_csv[Regexp.last_match[1]]=1
  elsif (filename =~ /^comcast_statement.voice_calls.d(\d+).pdf$/) 
    existing_voice_calls_pdf[Regexp.last_match[1]]=1
  elsif (filename =~ /^voicemail\.(d[\d_A-Z]+\.)[^\.]+\.(from[\d_]+)\..*\.mp3$/) 
    key=Regexp.last_match[1]+Regexp.last_match[2]
    puts "  Existing voicemail file, key is: "+key
    existing_voicemails[key]=1
  end
} 
downloaded_files=0



#browser.title == 'WATIR: download'

#browser.goto 'http://bit.ly/watir-example'


logging_in=true
attempts=0
while (logging_in)

  attempts += 1
  if (attempts > 3)
    puts "Too many login failures."
    #bell()  # Ring a bell.
    exit
  end
  
  puts "Attempt #{attempts} at logging in.  Going to login screen."

  begin
    browser.goto 'https://customer.comcast.com/secure/Home.aspx'


    puts "  Filling in fields and clicking on sign-in."

    browser.text_field(:index, 0).set username
    browser.text_field(:index, 1).set password

    browser.button(:id, "sign_in").click
    # Their stupid overlay causes things to timeout here, because, despite successful login, the page never loads
    # On the other hand, sometimes, the page loads despite the overlay, and everything is fine.

    puts "  Clicked on sign_in button."

    if (browser.div(:class, 'overlay-content').link().exists?)
      puts "  Stupid overlay detected, but the login click returned without timeout, and it means login was successful."
    end

    # Optimistic????? Test
    logging_in=false

  rescue Exception => e
    puts "  Something went wrong:"+e.message
    if (e.message=='execution expired')
      puts "  Execution expired, probably due to their stupid overlay"

      # "Activate Now" overlay muppetry.
      #bell()  # Ring a bell.
      #sleep(15)
      if (browser.div(:class, 'overlay-content').link().exists?)
        puts "  Stupid overlay detected, but at least it means login was successful."
        # Could also just ignore it, as we are in fact logged in now.
        #browser.div(:class, 'overlay-content').link().click
        # In fact, don't want to click it.  Don't want to activate.
      end

      # Optimistic????? Test
      logging_in=false
    end
  end

end


summary += "Successful login.\n"

voicemail_filenames={}
renamed_mp3s = 0
total_voicemails = 0
deleted_voicemails = 0
renamed_voicemail_ids={}
my_tn=""
failed_voicemail_ids=[]

total_statements = 0
renamed_statement_pdfs = 0
renamed_voice_usage_pdfs = 0
voice_usage_htmls = 0
voice_usage_csvs = 0
total_new_files = 0
new_filenames = []



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
      # If there's more than one number on the account, there'll be a drop-down menu
      number_text=''
      if (browser.div(:id, "number_switcher").exists?)
        number_dropdown=browser.div(:id, "number_switcher")
        #????? If the next line fails, we probably didn't get logged in.
        #  /usr/lib64/ruby/gems/1.8/gems/watir-webdriver-0.5.2/lib/watir-webdriver/elements/element.rb:359:in `assert_exists': unable to locate element, using {:tag_name=>"div", :id=>"number_switcher"} (Watir::Exception::UnknownObjectException)
        #
        number_dropdown.buttons.each {
          |b|
          # The first one will have the text of the selected options.
          # Any subsequent ones will have blank text, but contain a div
          # that contains the text.  For now, we're only interested in
          # the first phone number so it will do for now.
          number_text=b.text
        }
      else
        # There's just a single phone number on the account.
        number_text=browser.div(:id, "single_number").text
      end

      # '   (   4   0   8   )       5   5   5 342 200 221   1   2   5 342 200 215   7   '
      # For safety we just remove any non-printable characters.
      #
      number_text=number_text.scan(/[[:print:]]/).join
      puts "Number!"+number_text
      if (my_tn=="")
        puts "Setting my_tn to '#{number_text}'."
        my_tn=number_text.gsub(/[^\d]/,  "")  # Only the digits.
      end
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
    # The first time, we run through the list of voicemails to get the element
    # id of each voicemail row.
    all_voicemail_ids=[]
    if (loop_count==1)
      len=message_table.rows.length

      0.upto(len - 1) {
        |i|

        voicemail_row=message_table.row(:index, i)

        if (i==0) 
          puts "This is the first message."
          puts "Cell: #{voicemail_row.cell(:index, 0).text}"
          if (voicemail_row.cell(:index, 0).text =~ /You have no voicemail messages/)
            puts "No voicemail messages."
            tries_left=0  # To get out of the outer loop too.  On first loop, no voicemail to get; no need to loop.
            len=0
            break
          end
        end

        voicemail_id=voicemail_row.id # This seems to be the only way to relate back to the generated file.
        all_voicemail_ids.push(voicemail_id)
      }
      total_voicemails=len

    else
      # Subsequent efforts, we use the list of id's of the failed rows.
      len=failed_voicemail_ids.length
    end

    # Need to store a list of filenames for remapping
    0.upto(len - 1) {
      |i|

      puts ""
      if (loop_count==1)
        # Going through the whole list by index.
        voicemail_id=all_voicemail_ids[i]
        puts "Going for message with index #{i.to_s}, voicemail_id=#{voicemail_id}.  Clicking on the list item."
        #voicemail_id=voicemail_row.id # This seems to be the only way to relate back to the generated file.
      else
        # Going through previous failures by id.
        puts "Going for message with id='#{voicemail_id.to_s}'.  Clicking on the list item."
        voicemail_id=failed_voicemail_ids.shift
        
      end

      voicemail_row=message_table.row(:id, voicemail_id)
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
      #
      # Some odd characters in the name or contact (if there's a number, not a name here):
      # '   (   4   0   8   )       5   5   5 342 200 221   1   2   5 342 200 215   7   '
      # For safety we just remove any non-printable characters.
      name_text=voicemail_div.div(:class, 'name_text').text.scan(/[[:print:]]/).join
      contact_text=voicemail_div.div(:class, 'contact_token').text.scan(/[[:print:]]/).join
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
          bell()  # Ring a bell.
          delete_button=voicemail_div.button(:text, 'Delete message')
          puts "      The button:"+delete_button.text
          puts "      Clicking it..."
          deleted_voicemails += 1
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
    # ?????? Would be better to test for existence of element.
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
          #bell()  # Ring a bell.
          exit
        end
      end
    end




    puts "  Listing bills."

    # Just grabbing the main PDFs of the monthly statements.  This bit is straightforward.
    
    browser.div(:id, 'past-bills').links.each { 
      |l|
      total_statements += 1
      
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

      #bell()  # Ring a bell.

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

      if (existing_voice_calls_html[key]==1)
        puts "      We've already got this voice usage html file."
      else
        filename=File.join(destdir, 'comcast_statement.voice_calls.d'+key+'.html')
        puts "      We don't already have this voice calls html file (downloading): "+filename
        File.open(filename, 'w') {|f| f.write(browser.html) }
        voice_usage_htmls += 1
        total_new_files += 1
        new_filenames.push(filename)
      end

      if (existing_voice_calls_csv[key]==1)
        puts "      We've already got this voice usage csv file."
      else
        csv_filename=File.join(destdir, 'comcast_statement.voice_calls.d'+key+'.csv')
        csv_file=File.open(csv_filename, 'w')

        # Hmmm, no names/id.  Should probably scan all the tables to find one
        # that looks like the usage table.
        usage_table=browser.table().table(:index, 5)

        puts "Parsing call-record table:"
        n=0;
        phone_number=''
        table_header_found=false
        usage_table.rows.each_with_index {
          |r, i|


          #puts "  Row#{i}:"
          r.cells.each {
            |c|

            #puts "    '#{c.text.strip}'"
          }

          if ( (r.cells[0].text.strip == 'Date') &&  (r.cells[1].text.strip == 'Time') )
            #puts "  This is the table header."
            table_header_found=true  #?????? Use this for confirming we've got the right table.
            # ['Date', 'Time', 'Place', 'Number', 'Minutes', '', '', 'Amount']
          elsif (r.cells[0].text.strip=='')
            #puts "  This is a line with empty first field."
          elsif (r.cells[0].text.strip =~ /^Call Details/i)
            #puts "  This is the Call Details line."
            # Which is also a good way to know we've got the right table.
            # Also a good place to know what our phone number is!
            #   'Call Details for (508) 555-1234'
            # If multiple lines, could have multiple tables, or just rows like this.  Not sure.
            r.cells[0].text.strip =~ /^Call Details for ([-\d \(\)]+)/i
            phone_number = Regexp.last_match[1].gsub(/\D/, '')
            puts "    Phone number is: '#{phone_number}'"
          elsif (r.cells[0].text.strip =~ /^Total/i)
            #puts "  This is a total line."
          elsif (r.cells[0].text.strip =~ /^[\d\/]+$/i)
            #puts "  This is a usage line."
            cell_list = r.cells

            date=cell_list[0].text.strip
            time=cell_list[1].text.strip
            datetime=date+" "+time

            # Throw in a timezone if we have one (and the time doesn't already have one (here it doesn't))
            # If no timezone exists, it might get tagged zulu.  Nah, probably whatever localtime is.
            if (timezone != '') 
              datetime = datetime+" "+timezone
            end
            t=Time.parse(datetime)
            #puts "      time.parse: "+t.strftime("  %Y%m%d %H%M %Z")
            #if (timezone != '') 
            #  yyyymmdd_hhmm_tz=t.strftime("%Y-%m-%d %H:%M %Z")
            #else
            #  yyyymmdd_hhmm_tz=t.strftime("%Y-%m-%d %H:%M")
            #end
            #datetime = yyyymmdd_hhmm_tz
            datetime = t.iso8601

            call_location=cell_list[2].text.strip
            tn=cell_list[3].text.strip.gsub(/\D/, '')
            minutes=cell_list[4].text.strip
            # Then two empty fields.
            amount=cell_list[7].text.strip

            n += 1
            seconds=(minutes.to_i)*60
            rate_type=''
            status=''
            call_type='voice'
            billed_tn=phone_number
            calling_tn=phone_number
            called_tn=tn

            fields=[n, datetime, calling_tn, called_tn, seconds.to_s, amount, '0.00', amount, rate_type, status, call_type, billed_tn, call_location]
            puts "      "+fields.join(",")
            csv_file.puts fields.join("\t") # Yeah, it's tab-delimited, not CSV.  So sue me.

          else
            #?????? Perhaps handle better.
            puts "Unknown type of row in usage table."
            exit
          end

        }
        csv_file.close
        voice_usage_csvs += 1
        total_new_files += 1
        new_filenames.push(filename)

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
        #bell()  # Ring a bell.
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

          #puts '    File.rename('+File.join(tempdir, l.text)+', '+newfilename+')'
          #File.rename(File.join(tempdir, l.text), newfilename)
          puts "    Do:    FileUtils.mv('#{File.join(tempdir, l.text)}', '#{newfilename}')"
          FileUtils.mv(File.join(tempdir, l.text), newfilename)

          renamed_statement_pdfs += 1
          total_new_files += 1
          new_filenames.push(newfilename)
          
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

          #puts '    Do:    File.rename('+File.join(tempdir, l.text)+', '+newfilename+')'
          #File.rename(File.join(tempdir, l.text), newfilename)
          puts "    Do:    FileUtils.mv('#{File.join(tempdir, l.text)}', '#{newfilename}')"
          FileUtils.mv(File.join(tempdir, l.text), newfilename)

          renamed_voice_usage_pdfs += 1
          total_new_files += 1
          new_filenames.push(newfilename)

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
          # ?????? Do something terrible.
        else

          puts "  download voicemail mp3 link (count=#{renamed_mp3s}, id=#{voicemail_id}): "+saved_mp3_filename

          # Have we already renamed it in a previous pass?
          if (renamed_voicemail_ids[voicemail_id]==1)
            puts "We've already downloaded/renamed this one before"
          else

            newfilename=File.join(destdir, voicemail_filenames[voicemail_id])
            
            #puts '    Do:    File.rename('+File.join(tempdir, saved_mp3_filename)+', '+newfilename+')'
            #File.rename(File.join(tempdir, saved_mp3_filename), newfilename)
            puts "    Do:    FileUtils.mv('#{File.join(tempdir, saved_mp3_filename)}', '#{newfilename}')"
            FileUtils.mv(File.join(tempdir, saved_mp3_filename), newfilename)

            renamed_voicemail_ids[voicemail_id]=1
            renamed_mp3s += 1
            total_new_files += 1
            new_filenames.push(newfilename)
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

  puts "Pausing to let any network/file operations to settle."
  sleep(5)
end


if (download_voicemails==1)
  summary += "Voicemail mp3 files downloaded:       #{renamed_mp3s}/#{total_voicemails}\n"
  if (del_prev_downloaded_voicemails==1)
    summary += "Voicemails deleted:                   #{deleted_voicemails}/#{total_voicemails}\n"
  end
else
  summary += "download_voicemail option not set.\n"
end

if (download_bills==1)
  summary += "Statement PDFs downloaded:            #{renamed_statement_pdfs}/#{total_statements}\n"
  summary += "Voice usage PDFs downloaded:          #{renamed_voice_usage_pdfs}/#{total_statements}\n"
  summary += "Voice usage CSVs downloaded:          #{voice_usage_csvs}/#{total_statements}\n"
  summary += "Voice usage HTMLs downloaded:         #{voice_usage_htmls}/#{total_statements}\n"
else
  summary += "Download_bills option not set.\n"
end

#?????? This is optimistic.
summary += "Errors:                               0\n"

summary += "Total number of new files downloaded: #{total_new_files}\n"

new_filenames.each {
  |filename|

  summary += "New file: #{filename}\n"
}

puts "Deleting the temporary directory (#{tempdir})"  # Which should be empty
begin
  Dir.rmdir(tempdir)
rescue
  puts "Warning: problems deleting directory (#{tempdir})."
end

# Audible alert.  Yeah, it's goofy, but handy for testing.  Ditch it if you don't like it.
bell()  # Ring a bell.



pause_secs=4
puts progname+' Logging off in '+pause_secs.to_s+' seconds...'
#
#
#
sleep(pause_secs)  # To make sure things have settled down.

#
# Logout page
browser.goto 'https://customer.comcast.com/LogOut/logout.aspx'
sleep(pause_secs)



puts progname+' Closing browser in '+pause_secs.to_s+' seconds...'
sleep(pause_secs)
browser.close



end_time=Time.now
puts       "#{progname} ending: #{end_time}"
summary += "#{progname} ended:  #{end_time}\n"


# Print the summary string we've been building up.
puts "\n"
puts "####SUMMARY####\n"
puts "\n"
puts summary
puts "\n"


__END__
