#!/usr/bin/ruby
# nvenergy_watir1.rb --config nvenergy.conf



# ???????
#
# NOTE: probably only works for northern nevada accounts.
# 
# Should also grab the service summary and the usage detail (including
# the csv, which only goes back about 3-4 months)
# 
# Have option to save in a single directory or a tree, based on account-name.
# (And an option to automatically create the directory if needed)


require 'rubygems'
require 'watir-webdriver'
require 'getoptlong'
require 'time'
require 'fileutils'

config_filename='./nvenergy.conf'

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
# ??????? Old style had subdirs for multiple accounts.   New, we'll just flatten on disk.
# Most people will just have a single account so flat is fine.
Dir.foreach(destdir) { |filename|
  if    (filename =~ /^([^\.]+)\.nvenergy\.statement\.d(\d+)\.pdf$/) 
    puts '  Statement filename: '+filename
    file_account_name=Regexp.last_match[1]
    date_key=Regexp.last_match[2]
    existing_pdfs["statement.#{file_account_name}.#{date_key}"]=1
  else
    puts '  Filename: '+filename
  end
} 
statement_count=0
statement_pdf_save_count=0
new_filenames = []



puts 'Going to login page'

browser.goto 'https://www.nvenergy.com/myaccount/index.cfm'
puts 'Attempting login'
browser.text_field(:id, 'username').set username
browser.text_field(:id, 'password').set password
browser.radio(:id, 'northern').set

#browser.select_list(:index, 0).select 'Accounts Summary'  # It's the text, not the name.  Could probably use :id instead.

browser.button(:id, "sign-in").click

#browser.execute_script("submitLogin()")

# Yay, we're logged in, or should be.
# Uh, perhaps check login actually worked????
puts       "Successful login.\n"
summary += "Successful login.\n"
sleep(5)



total_new_files = 0
processed_all_accounts=false
account_numbers_processed={}
account_name=''
downloaded_files=0
if (download_bills==1) 
  puts "Looking for statements to download."
  downloaded_files=0

  while (! processed_all_accounts) 
    account_name=''

    # We're probably already here but we go here to make sure.
    puts "Going to accounts page."
    browser.goto "https://myaccountnnv.nvenergy.com/crmprdsp/P_TEMPLATE_R?PAGE_NAME=UWZPZLIS"


    # This doesn't seem to work.
    #browser.execute_script("javascript:forward_call('15-573845-547332','573845')")
    # P_Strl=15-573845-547332


    # Neither does this
    # Bogus because it's got hardcoded stuff in there!
    # Nah, bogus because the javascript in the frame relies on other frames!
    #puts 'Just goto the framset.'
    #Something like this:
    #browser.goto 'https://myaccountnnv.nvenergy.com/crmprdsp/p_uwzpzlis_R?accountnbr=10-008465757-src2846363&userid=JOEBLOW'


    # We just dig through the framesets and find it.
    #
    #puts 'Frames'
    myframeset=browser.frameset(:index, 0).frameset(:index,0).frameset(:index,0)
    myframe=myframeset.frame(:index, 1)
    mytable=myframe.table(:index, 2)
    #puts 'frameset: '+myframeset.to_s
    #puts 'frame: '+myframe.to_s




    mytable.rows.each_with_index { 
      |r, i|

      address=''
      account_number=''
      account_link=nil

      r.cells.each_with_index { 
        |c, j|

        l = c.link
        if (l.exists?)
          puts "  Link(#{i},#{j}): '#{l.text}'"

          # The table has a bunch of rows.  In a row with an actual account link,
          # the address will be the 2nd link
          if (j==1)
            puts "    It's an address/account link."
            address=l.text
            account_link=l
          elsif (j==2)
            puts "    It's an account_number link."
            account_number=l.text
          end

        end
      }

      if (address != '')
        puts "  Account address=#{address}"
        puts "  Account number=#{account_number}"

        if (account_numbers_processed[account_number])
          puts "    Already processed this account."
        else
          # Make a note so we don't process it twice.
          account_numbers_processed[account_number]=true


          # Let's see if we've got a mapping for the account_name
          puts "    Looking for an account-name remap."
          # Set a default first.
          account_name=account_number
          #
          namemaps.each {
            |namemap|

            puts "    Testing against #{namemap[0]}"
            if (namemap[1] =~ address)
              puts "      It's a match.  Remap account name to #{namemap[0]}"
              account_name=namemap[0]
            end

          }

          # Remove it from the hash, so it hits on the next one next time.??????

          puts "Selecting account '#{account_name}'"
          account_link.click
          # This should go back to the account-page, but better to use the name of the clickable link 'List All Accounts'
          # https://myaccountnnv.nvenergy.com/crmprdsp/P_TEMPLATE_R?PAGE_NAME=UWZPZLIS

        end

      end
    }

    # If we didn't find anything more to process, we're all done.
    if (account_name=='')
      puts 'No remaining accounts to process.'
      processed_all_accounts=true
      next # Which should actually terminate the loop.
    end


    # Now that we've selected the account, this might take us there.
    # Nope, it doesn't.  Yeah, it does, but it needs a delay for the page to load first!
    #
    puts "Sleeping to allow the screen to load..."
    # Make it more robust.  Take out the delay!  Test for the account loading.  
    sleep 20  # Yeah, it can take a while.  It's got some goofy javascript stuff.
    puts "Done sleeping.  Going to statement history."
    browser.goto 'https://www.energyguide.com/customercare/ssch.ashx?referrerid=100&RedirectUrl=BillHistoryRes.aspx'

    # Might also need to hit the 'View All' button on the table
    # Or perhaps the links are all there, all the time.
    puts 'Executing setShowAll function'
    browser.execute_script("javascript:setShowAll();")

    mytable2=browser.table(:id, 'objUCBHDataView_tblBH')

    old_text=''
    #
    i=0
    puts "Listing links on statement page:"
    mytable2.links.each { 
      |l|

      my_href = l.href.to_s

      puts '  Link: '+l.text

      if (l.text =~ /View My Bill/)
        i=i+1
        statement_count += 1

        # Previous link would be something like: "7/19/2011".  Use it to test/rename the files.
        datestring=old_text
        # Parse it up.
        fields=datestring.split(/\//)
        # It saves to something like: NVEnergy_Bill_07192011.pdf
        # Should rename to account_name.nvenergy.20110719.pdf
        # Start by figuring out the date format.
        # 
        old_style_date=("%02d%02d%04d" % [fields[0].to_i, fields[1].to_i, fields[2].to_i])
        new_style_date=("%04d%02d%02d" % [fields[2].to_i, fields[0].to_i, fields[1].to_i])
        #
        date_key=new_style_date

        old_filename='NVEnergy_Bill_'+old_style_date+'.pdf'
        new_filename="#{account_name}.nvenergy.statement.d#{new_style_date}.pdf"

        if (existing_pdfs["statement.#{account_name}.#{date_key}"]==1)
          puts "    We've already got this one."
        else
          puts "    About to click the link to download "+datestring+" as "+old_filename+" (to rename later: "+new_filename+')'
          l.click

          downloaded_files += 1

        end
      end
      old_text=l.text
    }

    puts "Finished downloading any statements for account '#{account_name}'."



    # Here we rename any files downloaded from the web interface (ie named by their end
    # but we want to rename to our own scheme, after we've confirmed the download).
    #
    # (We do it once round each loop to avoid possible filename clashes if we have
    # more than one address/account.)
    if (downloaded_files==0) 
      puts 'No new files to rename/download from browser.'

      # ???? Should do some sanity checks, based on actual date, vs listed html
      # files, vs previously download files.
    else
      puts 'Files downloaded in browser: '+downloaded_files.to_s
      puts 'Going to browser downloads page to confirm saving files:'

      # Pause a bit to make sure everything has finished downloading.
      sleep(5)

      browser.goto 'chrome://downloads/'
      browser.div(:id, 'downloads-display').buttons.each { 
        |l|
        puts '  download links: '+l.text
        if l.text =~ /Save/
          puts '    Save the file'
          begin
            l.click
          rescue
            puts "      Saving failed, but not sure what to make of it."
          end
        end
      }

      # And now lets list the links again because we might need to know the filenames.
      sleep(2) # To make sure the document has settled down a bit before we ask for the new links.
      puts 'Listing the links on the downloads page:'
      browser.div(:id, 'downloads-display').links.each { 
        |l|

        #puts "  Link text: '#{l.text}'"
        if (l.text =~ /^NVEnergy_Bill_(\d\d\d\d)(\d\d\d\d)\.pdf$/)
          # 'NVEnergy_Bill_12172013.pdf'
          old_filename=l.text
          puts "  Found PDF statement file for renaming: #{old_filename}"

          # Swap the mmddyyyy into yyyymmdd
          date_key=Regexp.last_match[2]+Regexp.last_match[1]
          #puts "date_key='#{date_key}'"

          new_filename="#{account_name}.nvenergy.statement.d#{date_key}.pdf"
          new_filenames.push(File.join(destdir, new_filename))

          puts "    Do:    FileUtils.mv('#{File.join(tempdir, old_filename)}', '#{File.join(destdir, new_filename)}')"
          FileUtils.mv(File.join(tempdir, old_filename), File.join(destdir, new_filename))

          statement_pdf_save_count += 1
          total_new_files += 1
          
        end


      }

      # We need to clear the links, in case we've got another account/address to download
      # (And we need to avoid clashes in the original filename downloads.)
      sleep(1)
      browser.link(:id, 'clear-all').click

      puts "Pausing to let any network/file operations settle."
      sleep(5)
    end

  end

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
browser.goto 'https://myaccountnnv.nvenergy.com/crmprdsp/P_LOGOUT_R'

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




