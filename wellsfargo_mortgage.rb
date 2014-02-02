#!/usr/bin/ruby
# wellsfargo_mortgage.rb --config wellsfargo_mortgage.conf


# ????????
#
# Need option to save in a single directory or a tree, based on account-name.
#   (And an option to automatically create the directory if needed)


require 'rubygems'
require 'watir-webdriver'
require 'getoptlong'
require 'time'
require 'fileutils'


config_filename='./wellsfargo_mortgage.conf'

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
download_bills      = cfg['download_bills'].nil? ? 1 : cfg['download_bills'].to_i


# We maintain a list of account-name maps.
# (If there aren't any configured, that's fine; the (rather-long)
# account_number will be used by default.)
namemaps=[]
cfg.keys.each {
  |key|
  if (key =~ /^accountname(\d+)$/)
    #puts "  Key(value)=#{key}(#{cfg[key]})"
    fields=cfg[key].split(/\s+/, 2)
    namemaps.push([fields[0], Regexp.new(fields[1])])
  end
}

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
    exit(1)
  end

  opts=GetoptLong.new(
                      ["--help",     "-h",      GetoptLong::NO_ARGUMENT],
                      ["--config",   "-c",      GetoptLong::OPTIONAL_ARGUMENT],
                      ["--destdir",  "-d",      GetoptLong::REQUIRED_ARGUMENT],
                      ["--tempdir",  "-t",      GetoptLong::REQUIRED_ARGUMENT],
                      ["--username", "-u",      GetoptLong::REQUIRED_ARGUMENT],
                      ["--password", "-p",      GetoptLong::REQUIRED_ARGUMENT],
                      ["--download_bills",      GetoptLong::NO_ARGUMENT]
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
#
puts "Listing existing files in download directory: #{destdir}"
# ???????? Old style had subdirs for multiple accounts.   New, we'll just flatten on disk.
# Most people will just have a single account so flat is fine.
Dir.foreach(destdir) { |filename|
  if    (filename =~ /^wellsfargo\.mortgage\.([^\.]+)\.statement\.d(\d+)\.pdf$/) 
    puts "  Statement filename: '#{filename}'"
    file_account_name=Regexp.last_match[1]
    date_key=Regexp.last_match[2]
    key="statement.#{file_account_name}.#{date_key}"
    #puts "    Key='#{key}'"
    existing_pdfs[key]=1
  else
    puts "  Filename: '#{filename}'"
  end
} 
statement_count=0
statement_pdf_save_count=0
new_filenames = []



puts 'Going to login page'

browser.goto 'https://online.wellsfargo.com/login'


puts "  Filling in fields and clicking on sign-in."

sleep(1)
browser.text_field(:id, 'username').set username
sleep(1)
browser.text_field(:id, 'password').set password
sleep(1)

browser.input(:name, "continue").click

# Yay, we're logged in, or should be.
# Uh, perhaps check login actually worked????
puts       "Successful login.\n"
summary += "Successful login.\n"
sleep(2)



puts "Explicitly going to account summary."


browser.goto 'https://online.wellsfargo.com/das/channel/accountSummary'


sleep(2)


puts "Listing accounts."

account_names=Array.new
mortgage_links_map={}
browser.table(:id, 'loan').links.each {
  |l|

  #puts "  Account link: '#{l.text}'    href='#{l.href.to_s}'"
  puts "  Account link: '#{l.text}'"

  if (l.text =~ /^MORTGAGE (XXXXXX\d\d\d\d)/)
    account_name = Regexp.last_match[1]
    puts "    It's a mortgage, account #{account_name}."
    # Remap the account.
    puts "    Looking for an account-name remap."
    #
    namemaps.each {
      |namemap|

      puts "    Testing against #{namemap[0]}"
      if (namemap[1] =~ l.text)
        puts "      It's a match.  Remap account name to #{namemap[0]}"
        account_name=namemap[0]
      end
      
    }

    puts "      Remapped: #{account_name}."

    puts "        storing: mortgage_links_map[#{account_name}]=l   href="+l.href.to_s
    mortgage_links_map[account_name]=l.href.to_s
    account_names.push(account_name)
  end
}

sleep(1)


total_new_files = 0
downloaded_pdf_files=0
# For renaming files afterwards.
link2filename_map={}
#
if (download_bills==1)
  puts 'Looping through accounts.'
  account_names.each {
    |account_name|

    puts "Selecting an account (#{account_name})."

    #browser.link(:text, /^MORTGAGE XXXXXX7463/).click
    href_s=mortgage_links_map[account_name]
    puts "  Link='#{href_s}'"
    browser.goto(href_s)

    sleep(1)

    puts "Selecting 'Online Statements'."

    browser.link(:text, /^Online Statements/).click

    sleep(2)

    # Get the list of years with available statements.
    yearlinks=[]
    #
    puts "Listing links in formSectionHead:"
    browser.div(:class, 'formSectionHead').links.each {
      |l|

      puts "  Link '#{l.text}'"
      #if (l.text =~ /^\d\d\d\d$/)
      yearlinks.unshift(l.text)
      #end
    }


    #['2012', '2013', '2014'].each {
    yearlinks.each {
      |year|


      puts "Selecting statements for a particular year (#{year}), for account #{account_name}."
      browser.link(:text, year).click

      sleep(2)

      puts "Listing statements."


      if (! browser.table(:id, 'listOfStatements').exists?)
        puts "  No statements for this year (#{year})"
      else
        browser.table(:id, 'listOfStatements').links.each { 
          |l|
          if (l.text=='')
            # The blank ones don't seem to be interesting.
            next
          end
          
          #puts "  Statement link: '#{l.text}'    href='#{l.href.to_s}'"
          puts "  Statement link: '#{l.text}'"

          if (l.text =~ /^Statement\s+(\d+)\/(\d+)\/(\d+)\s.*$/)
            puts '    Match:'+l.text   # Statement 10/04/12 (117K, PDF)

            statement_count += 1

            # Let's see if we've already got the file.
            #mm  =Integer(Regexp.last_match[1])
            #dd  =Integer(Regexp.last_match[2])
            #yy  =Integer(Regexp.last_match[3])
            #yyyy=2000+yy
            #date_key= "%04d%02d%02d" % [ yyyy,mm,dd ]
            #
            mm  =Regexp.last_match[1]
            dd  =Regexp.last_match[2]
            yy  =Regexp.last_match[3]

            date_key= '20'+yy+mm+dd


            key="statement.#{account_name}.#{date_key}"
            puts "      File key="+key

            if (existing_pdfs[key]==1)
              puts "      We've already got this file."
            else
              puts "      We don't already have this file (downloading): "+l.text

              l.click
              # This downloads a PDF file but names as "session[ (n)].cgi"
              # It will all be renamed and sorted out later.
              # Note: unlike .pdf files, they've downloaded so don't need confirming.
              #
              # They've got some stupid cgi crap in the link.  We need to move it.
              if (l.href.to_s =~ /^https.*(https.*)$/)
                new_href_text = Regexp.last_match[1]
                
                puts "Going for: "+new_href_text
                
                # Then need to fix a bunch of escaped stupdity.
                new_href_text.gsub!(/%3A/, ":")
                new_href_text.gsub!(/%2F/, "/")
                new_href_text.gsub!(/%3F/, "?")
                new_href_text.gsub!(/%3D/, "=")

                # Also need to skip everything past sessargs
                new_href_text.gsub!(/&link_name.*$/, "")
                
                puts "After editing: "+new_href_text
              end
              puts "New map key: '#{new_href_text}'"
              
              filename="wellsfargo.mortgage.#{account_name}.statement.d#{date_key}.pdf"
              link2filename_map[new_href_text]=filename

              downloaded_pdf_files += 1

            end
          end
        }
      end
    }

  }
end

renamed_files=0
if (downloaded_pdf_files==0) 
  puts 'No new files to download.'
else
  puts 'Files downloaded: '+downloaded_pdf_files.to_s
  puts 'Going to downloads page to confirm saving files if needed:'

  browser.goto 'chrome://downloads/'
  sleep(2) # To make sure the document has settled down a bit before we ask for the new links.

  if (false)
    puts "Confirming any downloads pending..."
    browser.div(:id, 'downloads-display').buttons.each { 
      |l|
      #puts '  download links: '+l.text
      if (l.text =~ /^Save/)
        puts '    Save the file'
        l.click
      end
    }
    puts "Confirmation done."
    sleep(2) # To make sure the document has settled down a bit before we ask for the new links.
  end

  # And now lets list links again because we might need to know the filenames.
  puts 'Listing the links on the downloads page:'
  previous_link_text=''
  renamed_links={}
  browser.div(:id, 'downloads-display').links.each { 
    |l|

    # Ignore some obvious crud.
    if ( (l.text=='Remove from list') || (l.text=='') )
      next
    end
    
    puts "  Link: '#{l.text}' = '#{l.href.to_s}'"


    if ( (link2filename_map[l.href.to_s]) && (renamed_links[l.href.to_s] != 1) )

      oldfilename=File.join(tempdir, previous_link_text)
      newfilename=File.join(destdir, link2filename_map[l.href.to_s])
      new_filenames.push(File.join(destdir, newfilename))

      puts "  We've got a match for this link.(#{newfilename})"
      puts '    download statement pdf links: '+l.text

      puts "    File.rename('#{oldfilename}', '#{newfilename}')"
      File.rename(oldfilename, newfilename)
      

      renamed_links[l.href.to_s]=1

      renamed_files += 1
      total_new_files += 1
      statement_pdf_save_count += 1

    end
    previous_link_text=l.text   # Dodgy way of figuring out the filename.

  }
  # ????? Should check that we got everything we expected
end


summary += "PDF statements downloaded:            #{statement_pdf_save_count}/#{statement_count}\n"

#?????? This is optimistic/delusional.  Intend to add some sanity checks later.
summary += "Errors:                               0\n"

summary += "Total number of new files downloaded: #{total_new_files}\n"

new_filenames.each {
  |filename|

  summary += "New file: #{filename}\n"

}


puts "Deleting the temporary directory (#{tempdir})"  # Which should be empty
begin
  Dir.rmdir(tempdir);
rescue
  puts "Warning: problems deleting directory (#{tempdir})."
end


# Audible alert.  Yeah, it's goofy, but handy for testing.  Ditch it if you don't like it.
bell()  # Ring a bell.

puts 'Done downloading and renaming.'
puts '  downloaded_pdf_files='+downloaded_pdf_files.to_s
puts '  renamed_files='+renamed_files.to_s


pause_secs=5

puts progname+' logging off in '+pause_secs.to_s+' seconds...'
sleep(pause_secs)  # To make sure things have settled down.
# Logout page
browser.goto 'https://online.wellsfargo.com/das/channel/signoff'

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




