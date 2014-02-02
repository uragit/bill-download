#!/usr/bin/ruby
# callcentric_watir1.rb --config callcentric.conf

# Disclaimer:
#   This code worked for me, at least once, on a particular account on
#   a particular computer.   Maybe it will work for you.  If not, then
#   maybe it will almost work, and maybe that's better than nothing.
#   Maybe it's not.   
#
#   It's a work in progress and could probably use some improvement.
#   (I'm new to Ruby and it probably shows.)
#   If it breaks, you get to keep both pieces.
#   


require 'rubygems'
require 'watir-webdriver'
require 'getoptlong'
require 'time'
require 'fileutils'


config_filename='./callcentric.conf'

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


# What to do at run time.
download_bills     = cfg['download_bills'].nil? ? 1 : cfg['download_bills'].to_i
download_cdrs      = cfg['download_cdrs'].nil?  ? 1 : cfg['download_cdrs'].to_i


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
    puts "  --download_bills"
    puts "  --download_cdrs"
    exit(1)
  end

  opts=GetoptLong.new(
                      ["--help",     "-h",      GetoptLong::NO_ARGUMENT],
                      ["--config",   "-c",      GetoptLong::OPTIONAL_ARGUMENT],
                      ["--destdir",  "-d",      GetoptLong::REQUIRED_ARGUMENT],
                      ["--tempdir",  "-t",      GetoptLong::REQUIRED_ARGUMENT],
                      ["--username", "-u",      GetoptLong::REQUIRED_ARGUMENT],
                      ["--password", "-p",      GetoptLong::REQUIRED_ARGUMENT],
                      ["--download_bills",      GetoptLong::NO_ARGUMENT],
                      ["--download_cdrs",       GetoptLong::NO_ARGUMENT]
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
    when "--download_bills"
      download_bills = 1
    when "--download_cdrs"
      download_cdrs = 1
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
  # ???? Fail on errors (if a regular file already exists with the name, etc)
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



####################################
####################################




if (! File.directory?(destdir))
  puts "Can't find destination directory ("+destdir+").  Exiting.  Perhaps you're running in the wrong directory."
  exit
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
##
##profile = Selenium::WebDriver::Firefox::Profile.new
#profile['browser.download.folderList'] = 2
#profile['browser.helperApps.neverAsk.saveToDisk'] = "application/pdf"


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
total_new_files = 0
new_filenames = []
downloaded_files=0
statement_count=0
statement_pdf_save_count=0
statement_html_save_count=0
call_record_csv_save_count = 0



puts "Going to login page."

browser.goto 'https://www.callcentric.com/login/'

puts "  Filling in fields and clicking on sign-in."

browser.text_field(:name, 'l_login').set username
browser.text_field(:name, 'l_passwd').set password
browser.button(:class, 'sform').click


# Yay, we're logged in, or should be.
# Uh, perhaps check login actually worked???
puts       "Successful login.\n"
summary += "Successful login.\n"
sleep(2)



# Download the bill statements.
if (download_bills==1)

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

      statement_count += 1

      if (existing_pdfs[key]==1)
        puts "      We've already got this file."
        # (And so we assume we also have the matching html file.  ???? Check?)
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
    newfilename=File.join(destdir, filename)

    browser.goto href
    File.open(newfilename, 'w+b') { |file| file.puts(browser.html) }

    statement_html_save_count += 1
    total_new_files += 1
    new_filenames.push(newfilename)
  }

end


# Download the transactions statements.
#?????? Not sure what we should do with these.
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
if (download_cdrs==1)

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
  puts 'No new files to download/rename.'
else
  puts 'Files downloaded (for renameing): '+downloaded_files.to_s
  puts 'Going to downloads page to confirm saving files:'

  # Pause a bit to make sure everything has finished downloading.
  # (Otherwise the last voicemail mp3 might not show on the page.  Perhaps PDFs too.)
  sleep(5)

  browser.goto 'chrome://downloads/'
  browser.div(:id, 'downloads-display').buttons.each { 
    |l|
    puts '  Pre-save download links: '+l.text
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
    
    puts '  Post-save download links: '+l.text



    # invoice-201211-2158.pdf  (invoice-YYYYMM-xxxx.pdf)
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
      
      statement_pdf_save_count += 1
      total_new_files += 1
      new_filenames.push(newfilename)

    end

    # Call records
    # cdr_20131201184331.csv  (cdr_YYYYMMDDHHMMSS.csv, utc time of *download*)
    #
    # Next link is: https://my.callcentric.com/save_calls.php?cdr_start_date=1383264000&cdr_end_date=1385856000&d=91ce6790b2cf&c=5b72e4dc592b77ac85cc&id=17771234567
    # (Contains the date range of the call record search.)
    # Could use this to more safely rename the files.
    #
    #
    if (l.text =~ /^cdr_\d+\.csv$/)
      puts '  downloaded call records csv links: '+l.text

      # Don't have a proper mapping but we have a list of desired filenames.
      # (Might be nice to do some sanity check at least on the number of files we've got!)
      # ????????
      # This is more or less essential.  Unreliable is bad.
      # (Even if we have to look in the files to check the contents!)

      # 'pop' because the files end up listed in reverse order in the download page.
      newfilename=File.join(destdir, cdr_filenames.pop)

      puts '    Do:    File.rename('+File.join(tempdir, l.text)+', '+newfilename+')'
      FileUtils.mv(File.join(tempdir, l.text), newfilename)

      call_record_csv_save_count += 1
      total_new_files += 1
      new_filenames.push(newfilename)
    end




  }
end


summary += "PDF statements downloaded:            #{statement_pdf_save_count}/#{statement_count}\n"
summary += "HTML statements downloaded:           #{statement_html_save_count}/#{statement_count}\n"
summary += "CSV CDR files downloaded:             #{call_record_csv_save_count}\n"


#??????? This is optimistic/delusional.  Intend to add some sanity checks later.
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


pause_secs=5

puts progname+' logging off in '+pause_secs.to_s+' seconds...'
sleep(pause_secs)  # To make sure things have settled down.
# Logout page
browser.goto 'https://www.callcentric.com/logout.php'

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









