#!/usr/bin/ruby

require 'rubygems'
require 'watir-webdriver'
require 'getoptlong'
require 'time'


config_filename='./callcentric.conf'

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



####################################
####################################

####################################
####################################

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

months_abbrev={
  'jan' =>  1,
  'feb' =>  2,
  'mar' =>  3,
  'apr' =>  4,
  'may' =>  5,
  'jun' =>  6,
  'jul' =>  7,
  'aug' =>  8,
  'sep' =>  9,
  'oct' => 10,
  'nov' => 11,
  'dec' => 12
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
existing_cdrs={};
#existing_voice_calls={};
#existing_voice_calls_pdf={};
filename_map={};
#
puts 'Listing existing files in download directory:'
Dir.foreach(destdir) { |filename|
  if    (filename =~ /^callcentric_statement\.d(\d+)\.pdf$/) 
    puts "  Existing PDF statement: '#{filename}'  (Key='#{Regexp.last_match[1]}')"
    existing_pdfs[Regexp.last_match[1]]=1
  elsif    (filename =~ /^callcentric.cdr.d(\d+)_(\d+)\.csv$/) 
    key="#{Regexp.last_match[1]}_#{Regexp.last_match[2]}"
    puts "  Existing CDR file: '#{filename}'  (Key='#{key}')"
    existing_cdrs[key]=1
  #elsif (filename =~ /^comcast_statement.voice_calls.d(\d+).html$/) 
  #  existing_voice_calls[Regexp.last_match[1]]=1
  #elsif (filename =~ /^comcast_statement.voice_calls.d(\d+).pdf$/) 
  #  existing_voice_calls_pdf[Regexp.last_match[1]]=1
  #elsif (filename =~ /^voicemail\.[^\.]+\.(d[\d_A-Z]+\.from\d+)\..*\.mp3$/) 
  #  #puts "  Existing voicemail file: "+Regexp.last_match[1]
  #  existing_voicemails[Regexp.last_match[1]]=1
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

browser.goto 'https://www.callcentric.com/login/'

puts "  Filling in fields and clicking on sign-in."

browser.text_field(:name, 'l_login').set username
browser.text_field(:name, 'l_passwd').set password
browser.button(:class, 'sform').click


# Download the bill statements.
if (true)

  browser.goto 'https://my.callcentric.com/bill_statements.php'

  table=browser.table().table(:index, 2).table()

  html_statement_hrefs=[]
  html_statement_filenames=[]

  puts "Bill Statements Table:"
  table.rows.each {
    |r|

    puts "  Row:"

    r.cells.each {
      |c|


      puts "    Cell: "+c.link(:index, 0).text
      date=c.link(:index, 0).text
      puts "      Splitting date '#{date}'"
      mon, yyyy = date.split(/\s*\,\s*/)
      key=yyyy+"%02d00" % months_abbrev[mon.downcase]
      puts "      key '#{key}'"

      if (existing_pdfs[key]==1)
        puts "      We've already got this file."
        # (And so we assume we also have the matching html file.  ??????? Check?)
      else
        puts "      Clicking the PDF link"
        c.link(:index, 2).click
        downloaded_files += 1

        puts 'HREF: '+c.link(:index, 0).href
        puts 'HREF: '+c.link(:index, 0).href.to_s
        html_statement_hrefs.push(c.link(:index, 0).href)
        html_statement_filenames.push("callcentric_statement.d#{key}.html")
      end

    }

  }
  html_statement_hrefs.each {
    |href|

    filename=html_statement_filenames.shift

    browser.goto href
    File.open(File.join(destdir, filename), 'w+b') { |file| file.puts(browser.html) }


  }

end


# Download the transactions statements.
if (true)
  row_number=0
  fieldnames=[]
  fieldname_index={}

  browser.goto 'https://my.callcentric.com/bill_transactions.php'

  table=browser.table().table(:index, 2).table()

  puts "Transactions Table:"
  table.rows.each {
    |r|

    puts "  Row:"

    fields=[]
    field_index=0
    r.cells.each {
      |c|

      text=c.text
      puts "    Cell: "+text
      
      if (row_number==0) 
        # Table header.
        # date, type, source, amount, tax, total, notes
        fieldname_index[text.downcase]=field_index
        fieldnames.push(text.downcase)
      elsif (row_number==1) 
        # It's just a junk jpg separator line.
      else
        if (field_index==fieldname_index['date'])
          t=Time.parse(text)
          yyyymmdd=t.strftime("%Y%m%d")
          text=yyyymmdd
          # Doh!  Would be better to push into database as is, or a time format..
        end
        # ???? Perhaps also convert '$0.00' into cents.
        fields.push(text)
      end
      field_index += 1

    }
    puts "    Fields: "+fields.join(", ")

    row_number += 1
  }

end


# Download the call history
cdr_filenames=[]
if (true)

  browser.goto 'https://my.callcentric.com/call_history.php'

  table=browser.table().table(:index, 2).table()

  puts "Call history:"

  # Can only pull 3 months at a time, but we'll just grab a month at a time.
  # (And a maximum of 18 months old.)
  time=Time.now()

  # Figure out date ranges for call records
  yyyy=time.year    # => Year of the date 
  mm=time.month   # => Month of the date (1 to 12)
  dd=time.day     # => Day of the date (1 to 31 )
  orig_yyyy = yyyy
  orig_mm = mm

  puts "Today is #{"%04d%02d%02d" % [yyyy, mm, dd]}"

  # Let's wind back 17 months (as far back as we can search for a whole month in callcentric).
  dd=1
  mm -= 17
  while (mm < 1)
    mm += 12
    yyyy -= 1
  end

  puts "Earliest date to search is #{"%04d%02d%02d" % [yyyy, mm, dd]}"

  puts "So, date ranges to look for:"
  while (not ( (yyyy == orig_yyyy) && (mm == orig_mm))) # Wind forward a month at a time (but not to current month).
    from_date_form = "%02d/%02d/%04d" % [mm, 01, yyyy]
    from_date      = "%04d%02d%02d" % [yyyy, mm, 01]
    # Then find the last day of the month.
    mm += 1
    if (mm==13)
      mm=1
      yyyy += 1
    end
    time=Time.utc(yyyy,mm,1,0,0,1) - 3600 # Two hours earlier (ie the last of the previous month.)
    to_date_form = "%02d/%02d/%04d" % [time.month, time.day, time.year]
    to_date      = "%04d%02d%02d" % [time.year, time.month, time.day]
    # Interestingly, after all this guff, their actual internal code uses the last day of the month
    # to forward to midnight of the next day so that the date query works like a human would expect.

    puts "    Looking for records from #{from_date} to #{to_date}"

    key="#{from_date}_#{to_date}"

    puts "    key=#{key}"

    if (existing_cdrs[key]==1)
      puts "      We've already got this file."
    else
      puts "      We should get this file"

      table.text_field(:name, 'from_date').set from_date_form
      table.text_field(:name, 'to_date'  ).set to_date_form
      browser.checkbox(:name, 'save_csv').set  # Opposite of 'set' is 'clear'
      browser.button(:name, 'submit').click

      # See if I can read any error message.  First row of the table.  Has error if there is one.
      maybe_error_msg=table.row().cell().text
      # From date:  (If no error)
      # Error - You cannot search for a period more than three month
      # Error - To date is BEFORE From date
      # Error - You cannot search backwards more than 18 months
      if (/^Error/i =~ maybe_error_msg) 
        puts "ERROR detected: '#{maybe_error_msg}'"
        puts "\007"  # Ring a bell.
      else

        # Their saved filenames look like: "cdr_20131201183308.csv" (It's the UTC datetime of the download).
        # Doesn't help us much.
        filename="callcentric.cdr.d#{from_date}_#{to_date}.csv"
        # Can't figure a proper mapping for their filename format, so just storing a list of our filenames.
        cdr_filenames.push(filename)
        # With more complexity, we could look at their saved filename and be safer.?????
        downloaded_files += 1

        # Because of the timestamp in their returned filename, we sleep for a second
        # to be on the safe side, to ensure uniqueness of the filename.
        sleep(1)
      end

    end
    


  end

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

  browser.goto 'chrome://downloads/'
  browser.div(:id, 'downloads-display').buttons.each { 
    |l|
    puts '  pre-save download links: '+l.text
    if l.text =~ /Save/
      puts '    Save the file'
      #puts "\007"  # Ring a bell.
      begin
        l.click
      rescue
        puts "    Saving failed, but that usually happens with csv files, with no save button."
        #????? Count we have the same number of failures as we have csv files.
      end
    end
  }

  # And now lets list the links again because we might need to know the filenames.
  sleep(2) # To make sure the document has settled down a bit before we ask for the new links.
  puts 'Listing the links on the downloads page:'
  browser.div(:id, 'downloads-display').links.each { 
    |l|
    
    puts '  post-save download links: '+l.text



    # invoice-201211-2158.pdf  (invoice-YYYYMM-????.pdf)
    #
    if (l.text =~ /^invoice-(\d\d\d\d)(\d\d)-\d+\.pdf$/)
      puts '  downloaded statement pdf links: '+l.text

      yyyy = Regexp.last_match[1].to_i
      mm   = Regexp.last_match[2].to_i
      #dd   = Regexp.last_match[3].to_i

      key= "%04d%02d" % [ yyyy,mm ]

      # ???? Should make some effort to check that the list of files we
      # tried to download meshes in some way with the ones we see here.
      # Either by name or sequence.  or both.

      newfilename=File.join(destdir, 'callcentric_statement.d'+key+'00.pdf')

      puts '    File.rename('+File.join(tempdir, l.text)+', '+newfilename+')'
      File.rename(File.join(tempdir, l.text), newfilename)
      
    end

    # Call records
    # cdr_20131201184331.csv  (cdr_YYYYMMDDHHMMSS.csv, utc time of *download*)
    #
    # Next link is: https://my.callcentric.com/save_calls.php?cdr_start_date=1383264000&cdr_end_date=1385856000&d=91ce653c6a9cf7267e057fcda790b2cf&c=5b72e4dc592b77abae83d89d667c85cc&id=17772715269
    # (Contains the date range of the call record search.)
    # Could use this to more safely rename the files.
    #
    #
    if (l.text =~ /^cdr_\d+\.csv$/)
      puts '  downloaded call records csv links: '+l.text



      # Don't have a proper mapping but we have a list of desired filenames.
      # (Might be nice to do some sanity check at least on the number of files we've got!)
      # ??????????????????
      # This is more or less essential.  Unreliable is bad.
      # (Even if we have to look in the files to check the contents!)

      # 'pop' because the files end up listed in reverse order in the download page.
      newfilename=File.join(destdir, cdr_filenames.pop)

      puts '    Do:    File.rename('+File.join(tempdir, l.text)+', '+newfilename+')'
      File.rename(File.join(tempdir, l.text), newfilename)
      # ???? Might be better if moving cross filesystems.  FileUtils.mv(File.join(tempdir, l.text), newfilename)

    end




  }
end

puts "Deleting the temporary directory (#{tempdir})"  # Which should be empty
begin
  Dir.rmdir(tempdir)
rescue
  puts "Warning: problems deleting directory (#{tempdir})."
end

puts "\007"  # Ring a bell.

pause_secs=5
puts progname+' exiting in '+pause_secs.to_s+' seconds...'
#
#
#
sleep(pause_secs)  # To make sure things have settled down.

#
# Logout page
browser.goto 'https://www.callcentric.com/logout.php'
sleep(5)


browser.close


puts progname+' ended'

exit



