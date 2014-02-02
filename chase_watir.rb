#!/usr/bin/ruby
#   chase_watir.rb -config configfile



require 'rubygems'
require 'watir-webdriver'
require 'getoptlong'
# open-uri allows opening a uri like a file.  Very handy in this context.
require 'open-uri'
require 'time'
require 'fileutils'


config_filename='./chase.conf'

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
destdir=cfg['destdir'].nil? ? "downloads/att" : cfg['destdir']

# Where to stash temporary files.  (Note: we'll also append the PID)
tempdir=cfg['tempdir'].nil? ? "downloads/tmp" : cfg['tempdir']


# We've actually already got these from some earlier goofiness.
#username=cfg['username']
#password=cfg['password']

# Identifier for this credit card.  Used in filenames of downloaded statements.
# Default is 'creditcard'.  
cardname      = cfg['cardname'].nil? ? "creditcard" : cfg['cardname']


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
    exit(1)
  end

  opts=GetoptLong.new(
                      ["--help",     "-h",      GetoptLong::NO_ARGUMENT],
                      ["--config",   "-c",      GetoptLong::OPTIONAL_ARGUMENT],
                      ["--destdir",  "-d",      GetoptLong::REQUIRED_ARGUMENT],
                      ["--tempdir",  "-t",      GetoptLong::REQUIRED_ARGUMENT],
                      ["--username", "-u",      GetoptLong::REQUIRED_ARGUMENT],
                      ["--password", "-p",      GetoptLong::REQUIRED_ARGUMENT]
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
    when "--passcode"
      passcode = value
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
end

if (! File.directory?(destdir))
  puts "Can't find destination directory (#{destdir}).  Exiting.  Perhaps you're running in the wrong directory."
  exit
end


####################################
####################################

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



def download_uri(uri, filename)

  File.open(filename, 'wb') do |f|
    f.write open(uri).read
  end

  return(1) # Not sure what else to send back. ????
end



####################################
####################################


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


# Tell it to disable pdf view.
disable_pdf_plugin(browser)


#browser.title == 'WATIR: Creditcard download'

#browser.goto 'http://bit.ly/watir-example'
#browser.goto 'http://bit.ly/watir-example'





summary=""

start_time=Time.now
puts       "#{progname} starting: #{start_time}"
summary += "#{progname} started:  #{start_time}\n"



#############################################
#      End of the (mostly) boilerplate      #
#############################################



# Let's collect all the files we've already got downloaded (or scanned)
#
existing_pdf={};
#
puts 'Listing existing files in download directory:'
Dir.foreach(destdir) { |filename|
  if    (filename =~ /^#{cardname}_statement.d(\d+).pdf$/) 
    # cardname_statement.d20071105.pdf
    key=Regexp.last_match[1]
    puts "  Key=#{key},   Filename="+filename
    existing_pdf[filename]=1
  elsif (filename =~ /^#{cardname}_statement.d(\d+).summary.pdf$/) 
    # cardname_statement.d2011.summary.pdf
    key=Regexp.last_match[1]
    puts "  Key=#{key},       Filename="+filename
    existing_pdf[filename]=1
  end
} 
downloaded_files=0






puts "Going to login page."

browser.goto 'https://chaseonline.chase.com/Logon.aspx'

puts "  Filling in fields and clicking on sign-in."

browser.text_field(:id, 'UserID').set username
browser.text_field(:id, 'Password').set password

browser.button(:id, "logon").click

# Let it settle a bit.
sleep(5)


# The next line seems to sometimes end up with:
#   /usr/lib64/ruby/1.8/timeout.rb:60:in `rbuf_fill': execution expired (Timeout::Error)
begin
  if (browser.link(:id, 'logoffbutton').exists?)
    puts "There's a login button, which means we've logged in."
  else
    puts "There's NO login button."
    exit;
  end
rescue => err
  puts "Error looking for login button (after login): #{err}"
  html_filename=File.join(tempdir, "error.junk.html")
  puts "Saving browser html as #{html_filename}"
  File.open(html_filename, 'w+b') { |file| file.puts(browser.html) }
  err
  exit;
end

puts       "Successful login.\n"
summary += "Successful login.\n"




puts "Going to view statements."

tries=0;
while (1)
  begin
    tries += 1

    puts "  Clicking on 'See statements'."
    browser.link(:text, /See statements/).click
    #   href="https://stmts.chase.com/stmtslist"
    break # ie if the click worked we get out of the loop
  rescue => err
    # Their server can be stupidly slow.  Try again to see if the link appears.
    puts "Rescue."
    if (tries > 5) 
      puts "Can't find the 'See statements' link."
      puts "Error: #{err}"
      exit
    end
  end
end

sleep(3)


pdf_links_to_toggle=[]
pdf_urls_to_download=[]
pdf_urls_seen={}
downloaded_pdf_files=0
total_pdfs = 0
renamed_pdfs = 0
total_new_files = 0
new_filenames = []
#
# Go through twice, toggling the undisplayed year links.
1.upto(2) { |pass|
  puts "Going through pass #{pass} of extracting info from statement list."

  browser.div(:id, 'StatementPanel').links.each { 
    |l|

    puts "  Link text: '#{l.text}'"
    puts "    URL: '#{l.href.to_s}'"

    url_to_add=0
    if (l.text =~ /^20\d{2}$/)
      if (pass==1) 
        puts "    It's a link for a year section .  Save for later toggle."
      else
        puts "    It's a year for a year section.  (Previously processed.)"
      end
      pdf_links_to_toggle.push(l)
    elsif (l.text =~ /^([A-Z][a-z]+)\s+(\d+)\,\s+(\d{4})/)
      # February 05, 2013

      #javascript:bolPopupURLClose('/stmt/StatementContainer?AccountId=837462117&OptionId=7384756364&EligibleForPaperless=True&Hash=385754636363');
      #javascript:bolPopupURLClose('/stmt/StatementContainer?AccountId=837462117&OptionId=7384756364&EligibleForPaperless=True&Hash=-d736121322');

      mm    = months[Regexp.last_match[1].downcase].to_i
      dd    = Regexp.last_match[2].to_i
      yyyy  = Regexp.last_match[3].to_i

      key= "%04d%02d%02d" % [ yyyy,mm,dd ]
      newfilename=cardname+'_statement.d'+key+'.pdf'
      puts "    key=#{key}, newfilename=#{newfilename}"
      url_to_add=1
      total_pdfs += 1
    elsif (l.text =~ /^(\d{4}) Year End Summary/)
      # 2012 Year End Summary
      yyyy  = Regexp.last_match[1]

      key=yyyy
      newfilename=cardname+'_statement.d'+yyyy+'.summary.pdf'

      url_to_add=1
      total_pdfs += 1
    end
    # Not sure what else we might get
    # 'Order a different statement online' is perhaps the only non downloadable beastie.
    # Perhaps we just look at the href and figure it out.

    if (url_to_add==1)
      if (existing_pdf[newfilename] == 1)
        puts '    Already got this file.'
      else
        puts '    Need to download this file.'
        if (l.href.to_s =~ /^javascript\:bolPopupURLClose\(\'([^']+)\'\)\;/)
          url='https://stmts.chase.com'+Regexp.last_match[1]
          puts "    URL: '"+url+"'"
          # Need to edit the link to something more like this.
          #  /stmt/StatementPdf?AccountId=837462117&OptionId=7384756364&EligibleForPaperless=True&Hash=-d736121322
          # Bummer, doesn't actually skip the download screen but at least the URLs will match.
          puts "    Editing the link for direct PDF download."
          url.gsub!(/StatementContainer/, "StatementPdf")
          puts "    URL: '"+url+"'"
          if (! pdf_urls_seen[url]) 
            # Save them here, for downloading later.
            pdf_urls_to_download.push(url)
            pdf_urls_seen[url]=newfilename
          end
        end
      end
    end

  }

  # Toggle the links between first and 2nd pass.
  if (pass==1) 
    puts 'Toggling all display/hidden years...'
    browser.div(:id, 'StatementPanel').links.each { 
      |l|

      #???? Uh, we made a list of them we're not using...  Do it one way or the other.

      if (l.text =~ /^20\d{2}$/)
        puts "  It's a year section.  Clicking it to toggle."
        # l.wd.location_once_scrolled_into_view # The googles, they do nothing.
        browser.send_keys :space  # This is a kludgey way to make sure the link is visible.
        # Otherwise the click fails!  Can't find a better way but this seems to work.
        sleep(2)
        l.click
        sleep(4) # To let things settle down after clicking.
      end
    }
    puts 'Toggled.'
  end

}


# Let's try downloading a bunch of stuff.
puts ''

i=0
puts 'Processing list of PDF URLs to download.'
pdf_urls_to_download.each_with_index {
  |url, i|

  puts "  Going for: #{url}"

  # This doesn't work.  Got to do it the hard way.
  #download_uri(url, "junk.#{downloaded_pdf_files}.pdf")

  browser.goto(url) 

  downloaded_pdf_files += 1

  sleep(3)
}

puts ''


browser_pdf_filenames=[]
new_pdf_filenames={}
#
if (downloaded_pdf_files==0) 
  puts "No new files to download."
else
  puts "Files downloaded: #{downloaded_pdf_files}"
  puts 'Going to downloads page to confirm saving files:'

  browser.goto 'chrome://downloads/'
  browser.div(:id, 'downloads-display').buttons.each { 
    |l|
    #puts '  download links: '+l.text
    if l.text =~ /Save/
      puts '  Saving a file on downloads page.'
      l.click
    end
  }

  # And now lets list the links again because we might need to know the filenames.
  sleep(2) # To make sure the document has settled down a bit before we ask for the new links.
  puts 'Saving done.  Now re-processing the links on the downloads page:'
  #
  status = :looking_for_pdf_filename
  browser_pdf_filename=''
  browser.div(:id, 'downloads-display').links.each { 
    |l|
    
    puts '  Download links: '+l.text

    # StatementPdf.pdf
    # StatementPdf (1).pdf
    # StatementPdf (2).pdf


    if ( (l.text =~ /^StatementPdf.pdf$/) || (l.text =~ /^StatementPdf \(\d+\).pdf$/) )
      # The filename we grab here, but we save it to correlate with the url link that follows.
      puts '    Statement pdf filename: '+l.text

      browser_pdf_filename=l.text
      if (status != :looking_for_pdf_filename)
        # BLOW UP????
        puts 'Yikes!'
        exit
      end
      status = :looking_for_pdf_link
      
    elsif (l.text =~ /^https:\/\/stmts.chase.com\/stmt\/StatementPdf/)
      puts '    Statement pdf link: '+l.text
      if (status != :looking_for_pdf_link)
        # BLOW UP????
        puts 'Yikes!'
        exit
      end
      newfilename=pdf_urls_seen[l.text]

      if ((newfilename.nil?) || (newfilename==""))
        # Crash if it can't find a match.
        puts 'Yikes!'
        exit
      end

      # Now we can map the filename to the new filename
      # StatementPdf (12).pdf -> cardname_statement.d20120808.pdf
      puts "    Map: '#{browser_pdf_filename}' -> '#{newfilename}'"
      browser_pdf_filenames.push(browser_pdf_filename)
      new_pdf_filenames[browser_pdf_filename]=newfilename

      status = :looking_for_pdf_filename
    else
      # Check status isn't looking_for_pdf_link.  Blow up if it is.
      puts '    Extraneous link (probably not a problem): '+l.text
    end

  }

  # If all is well...

  puts ''
  puts 'Ready to rename files:'
  browser_pdf_filenames.each { |old_filename|

    new_filename=new_pdf_filenames[old_filename]

    puts "  filename: #{old_filename} -> #{new_filename}"

    old_filename2=File.join(tempdir, old_filename)
    new_filename2=File.join(destdir, new_filename)

    puts "    Do:    FileUtils.mv('#{old_filename2}', '#{new_filename2}')"
    FileUtils.mv(old_filename2, new_filename2)

    new_filenames.push(new_filename2)
    renamed_pdfs += 1
    total_new_files += 1
  }

end

sleep(1)

summary += "Statement/summary PDF files downloaded: #{renamed_pdfs}/#{total_pdfs}\n"

#???? This is optimistic.  Put in some actual checks.
summary += "Errors:                                 0\n"

summary += "Total number of new files downloaded:   #{total_new_files}\n"

new_filenames.each {
  |filename|

  summary += "New file: #{filename}\n"

}

puts "Deleting the temporary directory (#{tempdir})"  # Which should be empty
begin
  Dir.rmdir(tempdir);
rescue Exception => e  
  puts "Warning: problems deleting directory (#{tempdir})."
  puts e.message  
  puts e.backtrace.inspect 
end


# Audible alert.  Yeah, it's goofy, but handy for testing.  Ditch it if you don't like it.
bell()  # Ring a bell.



pause_secs=4
puts progname+' logging off in '+pause_secs.to_s+' seconds...'
#
#
#
sleep(pause_secs)  # To make sure things have settled down.
#
# Logout page
browser.goto 'https://chaseonline.chase.com/secure/LogOff.aspx'


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
