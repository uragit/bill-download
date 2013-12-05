#!/usr/bin/ruby

require 'rubygems'
require 'watir-webdriver'
require 'getoptlong'

config_filename='./pge.conf'

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



####################################
####################################


puts progname+' starting'



if (! File.directory?(destdir))
  puts "Can't find temporary directory ("+destdir+").  Exiting.  Perhaps you're running in the wrong directory."
  exit
end



# Let's collect all the files we've already got downloaded (or scanned)
#
existing_pdfs={};
filename_map={};
#
puts 'Listing existing files in download directory:'
Dir.foreach(destdir) { |filename|
  if    (filename =~ /^pge_statement.d(\d+).pdf$/) 
    puts '  Filename: '+filename
    existing_pdfs[Regexp.last_match[1]]=1
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
#profile['download.default_directory'] = '/big/emmerson/junk66'
profile['download.default_directory'] = tempdir
##
##profile = Selenium::WebDriver::Firefox::Profile.new
#profile['browser.download.dir'] = "/big/emmerson/junk66"
#profile['browser.download.folderList'] = 2
#profile['browser.helperApps.neverAsk.saveToDisk'] = "application/pdf"


#browser = Watir::Browser.new :ff
#browser = Watir::Browser.new :firefox
browser = Watir::Browser.new :chrome, :profile => profile
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


#browser.title == 'WATIR: download'

# This is easier then the more complicated main page login.
browser.goto 'https://www.pge.com'


browser.text_field(:id, 'username').set username
browser.text_field(:id, 'password').set password
browser.form(:id, 'login-form').submit


browser.link(:text, 'Billing and Payment Activity').click
sleep(2)


# Grab account info.
# For now, just dealing with the first account, but the presence of a drop-box implies more is possible.
account_number=''
begin
  combo=browser.select_list(:id, "account")
  
  len=combo.options.length
  puts "Listing options in account dropdown box:"
  0.upto(len-1) {
    |i|
    o=combo.options[i]
    puts "  i=#{i.to_s}   text='#{o.text}'"
    account_number=o.text.strip
    break;
  }
end

puts "Account_number ='#{account_number}'"

if (account_number.nil? || account_number=='') 
  puts "Can't get account number from the bills/payment page."
  exit
end



statement_filenames={}
if (download_bills)
  transaction_table=browser.table(:id, "transaction-history-table")
  puts "Table:"
  row_count=0
  transaction_table.rows.each {
    |r|
    row_count += 1

    puts "  Row:"
    r.cells.each {
      |c|
      puts "    Cell:"+c.text
    }
    date=r.cells[0].text
    transaction_type=r.cells[1].text
    amount=r.cells[2].text
    payment_method=r.cells[3].text
    status=r.cells[4].text
    if    (transaction_type=='Payment')
      puts "    It's a payment"
    elsif (transaction_type=='Bill')
      puts "    It's a bill"
    else
      puts "    Unknown transaction type '#{transaction_type}'"
    end
    puts "      Date='#{date}', amount='#{amount}' payment_method='#{payment_method}' status='#{status}'" 

    if (transaction_type=='Bill')
      # Do we already have this statement pdf on disk.
      mm, dd, yy=date.split('/')
      date_fmt="20#{yy}#{mm}#{dd}"
      if (existing_pdfs[date_fmt]==1)
        puts "      We've already got this bill."
      else
        puts "    Download the pdf of the bill"
        link=r.cells[5].link(:text, /Download/)
        puts "      Link text '#{link.text}'"
        puts "      href text '#{link.href.to_s}'"

        # The download link looks something like this.
        # href text 'https://www.pge.com/myenergyweb/appmanager/pge/customer?_nfpb=true&_windowLabel=T100400384957173746564171&wsrp-urlType=blockingAction&wsrp-secureURL=true&wsrp-url=&wsrp-requiresRewrite=false&wsrp-navigationalState=eJyLL07OL0DJFKSDFJFyU8tt4-NSK0pUjV1UjUyN3JLzc8F0QXoqhF*cWQxm5Fam5qUWpVdCZBPTU9Ny8sshUiBTkjJzcuAcJyAnMy89ILEyNzWvxCOzuCS-qFIvq7gAAJirL50&wsrp-interactionState=_action%3D%252Fcom%252Fpge%252Fcsis%252Fmyenergy%252Fpageflows%252Fviewbill%252FfirePDFEvent%26T100400384957173746564171transactionId%3D%26T100400384957173746564171fwString%3DviewBillHistory%26T100400384957173746564171billStatementId%3D704678390191%26T100400384957173746564171docmethod%3Dviewbill%26T100400384957173746564171doctype%3Dpdf&wsrp-mode=&wsrp-windowState='
        # The only part which seems to be unique for each statement is:
        #    'billStatementId%3D704678390191%'
        link.href.to_s =~ /.*billStatementId%3D(\d+)%/
        statement_id=Regexp.last_match[1]
        puts "      billStatementId='#{statement_id}'"

        # Let's decide the filename here.
        statement_filenames[statement_id]="pge_statement.d#{date_fmt}.pdf"

        # Let's download the PDF here.
        link.click
        downloaded_files += 1

      end


    end

  }
end



if (downloaded_files==0) 
  puts 'No new files to download.'

  # ???? Some sanity checks, based on actual date, vs listed html
  # files, vs previously download files.

else
  puts 'Files downloaded: '+downloaded_files.to_s
  puts 'Going to downloads page to confirm saving files:'

  # Pause a bit to make sure everything has finished downloading.
  sleep(5)

  saved_pdf_filename=''

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
        puts "      Saving failed, but not sure what to make of it."
      end
    end
  }

  # And now lets list the links again because we might need to know the filenames.
  sleep(2) # To make sure the document has settled down a bit before we ask for the new links.
  puts 'Listing the links on the downloads page:'
  browser.div(:id, 'downloads-display').links.each { 
    |l|
    
    puts '  download links: '+l.text

    if (l.text =~ /^ViewBill.*\.pdf$/)
      # Next link will give us the extra info we need.
      saved_pdf_filename=l.text
      puts "    Saving filename for next time around the loop '#{saved_pdf_filename}'"
        
    elsif (l.text =~ /.*billStatementId%3D(\d+)%/)
      
      statement_id=Regexp.last_match[1]
      puts "    statement_id='#{statement_id}'"

      if ( (statement_id.nil?) || (statement_id=='') || (saved_pdf_filename=='') )
        puts "HORRIFIC FILE RENAMING PROBLEM.  statement_id='#{statement_id}'"
        # ?????????? Do something terrible.
      else

        puts "  download statement_pdf link (id=#{statement_id}): "+saved_pdf_filename

        newfilename=File.join(destdir, statement_filenames[statement_id])
          
        puts '    Do:    File.rename('+File.join(tempdir, saved_pdf_filename)+', '+newfilename+')'
          
        File.rename(File.join(tempdir, saved_pdf_filename), newfilename)
        # ???? Might be better if moving cross filesystems.  FileUtils.mv(File.join(tempdir, l.text), newfilename)
          
      end

      saved_pdf_filename=''
    else
      saved_pdf_filename=''
    end
  }

  puts "Pausing to let any network/file operations to settle."
  sleep(5)
end


puts "Deleting the temporary directory (#{tempdir})"  # Which should be empty
begin
  Dir.rmdir(tempdir)
rescue
  puts "Warning: problems deleting directory (#{tempdir})."
end

# Audible alert.  Yeah, it's goofy, but handy for testing.  Ditch it if you don't like it.
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




# Logoff.  After sleeping for long enough to show the final state before logoff.
pause_secs=5
puts "Logging off in #{pause_secs.to_s} seconds..."
sleep(pause_secs)
browser.goto 'https://www.pge.com/myenergyweb/appmanager/pge/customer?_nfpb=true&_windowLabel=headerInstance_1&headerInstance_1_actionOverride=%2Fcom%2Fpge%2Fcsis%2Fmyenergy%2Fpageflows%2Fheaderfooter%2FdoLogOut'

sleep(5)
browser.close


exit



