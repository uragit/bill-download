#!/usr/bin/ruby
# att_phone_watir.rb -- Downloads monthly statements from att.com, for a single home phone account.


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
#   Big phone companies often have multiple back-end systems which
#   behave differently from each other.   If this code doesn't work
#   there's a good chance that AT&T has got your account on a different
#   system from mine.


# Note:
#
# As a rough standard for my collection of screen-scraping, csv-saving CDR files
# this is the plan for the csv files.
#
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

# Default location for config file.
config_filename='./att.conf'

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

username=cfg['username']
password=cfg['password']
passcode=cfg['passcode']
# Passcode is optional, unless needed for login, then it will fall over at login failure.

# In which timezone do you want times interpreted?
tz=cfg['tz'].nil? ? 'PST8PDT' : cfg['tz']
# If it ends up blank, US times will be be interpeted as machine local time.

# What to do at run time.
download_bills_pdf=cfg['download_bills_pdf'].nil? ? 1 : cfg['download_bills_pdf'].to_i
download_bills_html=cfg['download_bills_html'].nil? ? 1 : cfg['download_bills_html'].to_i
download_usage=cfg['download_usage'].nil? ? 1 : cfg['download_usage'].to_i


####################################
####################################

progname=File.basename($0)

begin
  # Command-line options, will override settings in config file.

  def printusage()
    puts 
    puts "Usage: #{$0} [options]"
    puts "Options:" 
    puts "  --config filename    (configuration file with key=value pairs"
    puts "  --destdir directory  (for final destination of downloading)"
    puts "  --tempdir directory  (for temporary staging)"
    puts "  --username username  (safer to specify in config file)"
    puts "  --password password  (safer to specify in config file)"
    puts "  --passcode passcode  (if needed for login)"
    puts "  --tz timezone        (Timezone for interpreting usage timestamps, default PST8PDT)"
    puts "  --download_bills_pdf"
    puts "  --download_bills_html"
    puts "  --download_usage"
    exit(1)
  end

  opts=GetoptLong.new(
                      ["--help",     "-h",      GetoptLong::NO_ARGUMENT],
                      ["--config",   "-c",      GetoptLong::OPTIONAL_ARGUMENT],
                      ["--destdir",  "-d",      GetoptLong::REQUIRED_ARGUMENT],
                      ["--tempdir",  "-z",      GetoptLong::REQUIRED_ARGUMENT],
                      ["--username", "-u",      GetoptLong::REQUIRED_ARGUMENT],
                      ["--password", "-p",      GetoptLong::REQUIRED_ARGUMENT],
                      ["--passcode",            GetoptLong::REQUIRED_ARGUMENT],
                      ["--timezone",            GetoptLong::REQUIRED_ARGUMENT],
                      ["--download_bills_pdf",  GetoptLong::NO_ARGUMENT],
                      ["--download_bills_html", GetoptLong::NO_ARGUMENT],
                      ["--download_usage",      GetoptLong::NO_ARGUMENT]
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
    when "--timezone"
      timezone = value
    when "--download_bills_pdf"
      download_bills_pdf = 1
    when "--download_bills_html"
      download_bills_html = 1
    when "--download_usage"
      download_usage = 1
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

if (! File.directory?(destdir))
  puts "Can't find destination directory (#{destdir}).  Exiting.  Perhaps you're running in the wrong directory."
  exit
end

####################################
####################################


summary=""

start_time=Time.now
puts       "#{progname} starting: #{start_time}"
summary += "#{progname} started:  #{start_time}\n"



# Let's collect all the files we've already got downloaded (or scanned)
#
existing_files={};
file_rename_lookup={}
#
puts 'Listing existing files in download directory:'
Dir.foreach(destdir) { |filename|
  if    (filename =~ /^att_phone_statement.(\d+).d(\d+)_(\d+).(pdf|html)$/) 
    puts '  Filename: '+filename
    phone_number_key=Regexp.last_match[1]
    date_from_key=Regexp.last_match[2]
    date_to_key=Regexp.last_match[3]
    type_key=Regexp.last_match[4]
    key=phone_number_key+'.'+date_to_key+'.'+type_key
    existing_files[key]=1
  elsif    (filename =~ /^att_phone_statement.(\d+).d(\d+)_(\d+).(voice|text|data)_usage.csv$/) 
    puts '  Filename: '+filename
    phone_number_key=Regexp.last_match[1]
    date_from_key=Regexp.last_match[2]
    date_to_key=Regexp.last_match[3]
    type_key=Regexp.last_match[4]
    existing_files[phone_number_key+'.'+date_to_key+'.'+type_key+'_usage.csv']=1
  elsif    ( (filename =~ /^\.$/) || (filename =~ /^\.\.$/) )
  else
    puts '  Filename (unknown type): '+filename
  end
} 
downloaded_files=0


puts 'Place for temp files: '+tempdir

if (File.directory?(tempdir))
  puts "  Directory exists."
elsif (File.file?(tempdir))
  puts "  Can't use directory (tempdir).  It's a regular file."
else
  puts "  Directory ("+tempdir+") does not exist.  Creating."
  Dir.mkdir(tempdir)
end




## Chrome
##
profile = Selenium::WebDriver::Chrome::Profile.new
profile['download.prompt_for_download'] = false
profile['download.default_directory'] = tempdir
##
##profile = Selenium::WebDriver::Firefox::Profile.new
#profile['browser.download.folderList'] = 2
#profile['browser.helperApps.neverAsk.saveToDisk'] = "application/pdf"


#browser = Watir::Browser.new :ff
#browser = Watir::Browser.new :firefox
browser = Watir::Browser.new :chrome, :profile => profile
#browser = Watir::Browser.new :chrome

mycontainer = Watir::Container



# The view links execute something like this:
#    <a href="javascript:void(0);" class="wt_Body" desturl="/view/viewfullbillPDF.doview" onclick="window.open('/view/viewfullbillPDF.doview?stmtID=20120605|7753295648280|S|P&amp;reportActionEvent=A_VB_VIEW_FULL_BILL_PDF_LINK', 'viewpdf', config='height=600, width=800, toolbar=no, menubar=yes, scrollbars=yes, resizable=yes, location=no, directories=no, status=no'); return false;">PDF</a>
# Trouble is, they count as a bunch of auto downloads in a row, triggering
# chrome's retarded "This site is attempting to download multiple files"
# for which there is no defence.   Might be better to parse out the
# URL and explicitly ask for the PDF files.   Anyway, probably can't test it
# now because I hit the "allow" button, and it probably remembers.
#
# Oh, that's okay, stewardess, I speak 'tard.   Workaround by kludging a direct
# url instead of clicking on their javascript-laden buttons.


def disable_pdf_plugin(browser)

  puts 'Going to about:plugins page (to disable plugins, so PDFs save):'

  # This is much simpler!
  # disable Chrome PDF Viewer
  browser.goto "about:plugins"
  browser.span(:text => "Chrome PDF Viewer").parent.parent.parent.a(:text => "Disable", :class => "disable-group-link").click

end

disable_pdf_plugin(browser)

###############################
###############################



# Window activity seems to trigger some confusing javascript which breaks the login.
puts "Don't resize browser window before login!  (Bad juju!)" 

logging_in=true
attempts=0
while (logging_in)
  attempts += 1
  if (attempts > 3)
    puts "Too many login failures."
    exit
  end

  puts "Attempt #{attempts} at logging in.  Going to login screen."

  browser.goto 'https://www.att.com/olam/loginAction.olamexecute'

  sleep(1)
  puts "Filling in username/password."
  browser.text_field(:name, 'userid').set username
  login_button=browser.input(:title, 'Login')
  #puts "Clicking on login button."
  #login_button.click
  sleep(1)
  browser.text_field(:id, 'password').set password
  sleep(1)
  #
  # Seems to need two of these.  This combo works.  Others don't.  Some others might.
  #login_button.click
  browser.input(:title, 'Login').click
  #browser.input(:class, 'MarTop10').click


  # Due to asshattery they sometimes (ie randomly) pop up a feedback request form, yes before
  # they even get the passcode entered.   We try to check that here.
  if (browser.link(:class, 'fsrDeclineButton').exists?)
    # Click the "No, thanks" button.
    puts "Seems to be a stupid feedback splash presented.  Clicking 'No thanks'."
    browser.link(:class, 'fsrDeclineButton').click
  end

  begin
    if (browser.text_field(:id, 'passcode').exists?)
      if (passcode != '')
        puts "Passcode requested.  Attempting to set passcode."
        browser.text_field(:id, 'passcode').set passcode
        browser.input(:id, 'bt_continue').click
      else
        puts "Passcode needed but not supplied."
        exit
      end
    else
      puts "No passcode request screen."
    end
  rescue
    puts "Well, passcode entry didn't work.  Probably muppetry with a survey overlay."
  end

  sleep(1)  # Maybe it needs to settle.

  # Due to asshattery they sometimes (ie randomly) pop up a feedback request form, yes before
  # they even get the passcode entered.   We try to check that here.
  if (browser.link(:class, 'fsrDeclineButton').exists?)
    # Click the "No, thanks" button.
    puts "Seems to be a stupid feedback splash presented.  Clicking 'No thanks'."
    browser.link(:class, 'fsrDeclineButton').click
  end

  # If it's not asking for a password, we assume we're in.
  if (not browser.text_field(:id, 'password').exists?)
    puts "Can't see a password prompt; assuming login success."
    logging_in=false
  end

end

summary += "Successful login.\n"


if (browser.link(:name, "MyATT_Wireless Services").exists?)
  landline=false
  puts "Looks like it's a wireless account."
else
  landline=true
  puts "Looks like it's a landline account."
end


if (not landline)
  # Grab this from the overview.
  #  Phone number: 'Marmaduke  555-666-3264'
  browser.goto 'https://www.att.com/olam/passthroughAction.myworld?actionType=Manage&gnLinkId=s1001'
  phone_number=browser.div(:class, 'minHt75 PadTop5 MarRight20').h4().text.split(/\s+/).last.gsub(/\D/,'')
  puts "Phone number: '#{phone_number}'"
  # For wireless, could probably just use the login username, in fact it might make more sense.
end

# Pull up a table of billing history (same for landline or mobile)
puts "Going to 'Billing history' page"
if (landline)
  browser.goto 'https://www.att.com/olam/passthroughAction.myworld?actionType=ViewBillHistory&gnLinkId=t1004'
else
  browser.goto 'https://www.att.com/olam/passthroughAction.myworld?actionType=ViewBillHistory&gnLinkId=t1007'
end
sleep(2)


# Grab the account number from the web page.
if (landline)
  account_number=browser.div(:id, 'landing').li(:class, 'account-number').text
else
  account_number=browser.div(:class, 'w436imp PayAllLineitems float-left').p.text.split(/\s+/)[1]
  # <p class="colorGrey font12 botMar3 ">Account: 284372643055</p>
end

if (landline)
  phone_number=account_number[0..9]
end
puts "account_number='#{account_number}', phone_number='#{phone_number}'  "

puts "account_number='#{account_number}', phone_number='#{phone_number}'  "
summary += "Phone number: #{phone_number}\n"


if (not landline)
  # There's an annoying radiobox to select between display formats for list of bills
  # but in fact the html for both types exists, even if they don't both display.
  # Should probably make it display just for easier debugging, ie at least anybody
  # watching the browser can see what the code is seeing.
  browser.radio(:id, 'Table-View').set
end


puts "Processing lines in billing history table:"
statement_url_list=[]
statement_date_list=[]
if (landline)
  mytable=browser.table(:class, 'table tableNoPad')
else
  mytable=browser.div(:id, 'tableView').table()
end
#
statement_count=mytable.rows.length
statement_pdf_save_count=0
voice_usage_save_count  =0
text_usage_save_count   =0
data_usage_save_count   =0
#
mytable.rows.each_with_index {
  |r, i|

  if (i==0) # First line is header info.
    next
  end

  puts "Row(#{i}):"
  #r.cells.each {
  #  |c|
  #  if (c.colspan() != 1)
  #    puts "  (colspan=#{c.colspan()}):#{c.text}"
  #  else
  #    puts "  '#{c.text}'"
  #  end
  #}
  #puts

  if (landline)
    cell_list = r.cells
    bill_period=cell_list[0].text
    #plans_and_service_charges=cell_list[1].text   # (Who cares)
    bill_total=cell_list[2].text
    bill_link = cell_list[3].link(:index, 0)
    
    #puts "  Row(#{i}): bill_period='#{bill_period}' bill_total='#{bill_total}'"
    puts "  bill_period='#{bill_period}' bill_total='#{bill_total}'"

    # Bill_period looks like: 01/06/2012 - 02/05/2012
    fields=bill_period.split(/[ \/\-]+/)
    date_from_string=fields[2]+fields[0]+fields[1]
    date_to_string  =fields[5]+fields[3]+fields[4]
    #fields.each do |f|
    #  puts '  Date field: "'+f+'"'
    #end
    puts '  date_from_string='+date_from_string
    puts '  date_to_string='+date_to_string
    # The end-day of the date range is the billing date on the bill itself.

    # For landline, there's two kinds of bill links, one is 'View', a
    # link to a separate page.  The other, for older bills, is a
    # straightforward link 'PDF' to a pdf file.  (Annoyingly, the PDF
    # link also pops up a window if you click on it.  With a bit of
    # luck, this doesn't break anything in our parsing of the current
    # table.)


    key=phone_number+'.'+date_to_string+'.pdf'
    if (bill_link.text.match(/View/)) 
      if (existing_files[key]==1)
        puts "  It's a 'View' link"
        puts "  Already have this pdf file, with key '#{key}'"
      else
        puts "  It's a 'PDF' link"
        if (download_bills_pdf==1)
          puts "  Don't have this file, with key '#{key}'.  Kludging URL for immediate PDF download."
          
          # Yeah, it's ugly and brittle but so is their stupid website.  Often the 'View'
          # link for older bills takes you to the bill detail page for the most recent statement
          # because the actual one you want doesn't exist.   So we'll just save the grief, at
          # least for PDF statements because we know the URL that would retrieve the PDF (that
          # might otherwise not be retrievable at all.

          browser.goto "https://www.att.com/view/viewfullbillPDF.doview?stmtID=#{date_to_string}|#{account_number}|S|P"
          puts "file_rename_lookup[#{date_to_string}]=att_phone_statement.#{phone_number}.d#{date_from_string}_#{date_to_string}.pdf"
          file_rename_lookup[date_to_string]="att_phone_statement.#{phone_number}.d#{date_from_string}_#{date_to_string}.pdf"
          downloaded_files += 1
        end
      end

      # Now save the info in the link for later processing, if we want html and csv(usage).
      puts "  Saving URL for possible later download of html and csv info."
      ## Save the href for later download.
      statement_url_list.push([bill_link.text, bill_link.href.to_s, date_from_string, date_to_string])

    elsif (bill_link.text.match(/PDF/)) 
      if (existing_files[key]==1)
        puts "  Already have this PDF file, with key '#{key}'"
        # And there's no way to retrieve html or usage for a bill that only had PDF option.
      else
        if (download_bills_pdf==1)
          puts "  Don't have this file, with key '#{key}'.  ATTEMPT IMMEDIATE DOWNLOAD."

          if (false)
            # Just clicking the link tends to trigger the multiple file dialog.
            # So we go for the kludgey hack below.
            bill_link.click
          else
            old_url=bill_link.html
            # The link looks like this.  We want the URL in the onclick.
            #    <a href="javascript:void(0);" class="wt_Body" desturl="/view/viewfullbillPDF.doview" onclick="window.open('/view/viewfullbillPDF.doview?stmtID=20120605|7753295648280|S|P&amp;reportActionEvent=A_VB_VIEW_FULL_BILL_PDF_LINK', 'viewpdf', config='height=600, width=800, toolbar=no, menubar=yes, scrollbars=yes, resizable=yes, location=no, directories=no, status=no'); return false;">PDF</a>
            #
            #puts "  URL: '#{old_url}'"
            old_url =~ /^.*window\.open\(\'([^&]*)&/
            url='https://www.att.com'+Regexp.last_match[1]
            #
            # URL now looks something like this:
            #   'https://www.att.com/view/viewfullbillPDF.doview?stmtID=20131105|7753295648280|S|P'
            # We could have just formatted it ourselves (as we've done elsewhere
            # in the code) instead of parsing it out.  But, uh, well, here we are.
            #
            puts "  URL: '#{url}'"
            browser.goto url
            puts "file_rename_lookup[#{date_to_string}]=att_phone_statement.#{phone_number}.d#{date_from_string}_#{date_to_string}.pdf"
            file_rename_lookup[date_to_string]="att_phone_statement.#{phone_number}.d#{date_from_string}_#{date_to_string}.pdf"
            downloaded_files += 1

          end
        end
      end
    else
      puts "No idea what format this table entry is."
    end

  else
    # Wireless has different table structure. (And link type/behaviours.)

    cell_list = r.cells
    bill_period=cell_list[0].text
    #plans_and_service_charges=cell_list[1].text   # (Who cares)
    bill_total=cell_list[1].text
    if (cell_list[2].colspan() != 1)
      # Colspan=6 means no payment received.  Moves the other columns about a bit.
      # (Contains info about due date, autopay scheduled, etc)
    else
      payment_date    = cell_list[2].text
      payment_amt     = cell_list[3].text
      payment_method  = cell_list[4].text
      payment_autopay = cell_list[5].text
      payment_status  = cell_list[6].text
      payment_conf    = cell_list[7].text

      puts "  Payment_date    = '#{payment_date}'"
      puts "  Payment_amt     = '#{payment_amt}'"
      puts "  Payment_method  = '#{payment_method}'"
      puts "  Payment_autopay = '#{payment_autopay}'"
      puts "  Payment_status  = '#{payment_status}'"
      puts "  Payment_conf    = '#{payment_conf}'"

    end

    # bill_link = cell_list[?].link(:index, 0)
    
    puts "  bill_period='#{bill_period}' bill_total='#{bill_total}'"

    # Bill_period looks like: 01/06/2012 - 02/05/2012
    fields=bill_period.split(/[ \/\-]+/)
    date_from_string=fields[2]+fields[0]+fields[1]
    date_to_string  =fields[5]+fields[3]+fields[4]
    #fields.each do |f|
    #  puts '    Date field: "'+f+'"'
    #end
    puts '    date_from_string='+date_from_string
    puts '    date_to_string='+date_to_string
    # The end-day of the date range is the billing date on the bill itself.

    # For wireless, there's two kinds of bill links for each bill, one
    # is 'Online', which pops up a separate window with an HTML
    # version of the bill.  The other, 'PDF', pops up a separate
    # window which requests the PDF.

    # We're not even going to bother wading through the link clicking and
    # dealing with popups, and chrome complaining about multiple downloads.
    # Figured out the url format that gets called.  We'll just grab the
    # file directly.

    key=phone_number+'.'+date_to_string+'.pdf'
    if (existing_files[key]==1)
      puts "  Already have this pdf file, with key '#{key}'"
    else
      if (download_bills_pdf==1)
        puts "  Don't have this file, with key '#{key}'.  Kludging URL for immediate PDF download."
          
        # Yeah, it's ugly and brittle but so is their stupid website.  Often the 'View'
        # link for older bills takes you to the bill detail page for the most recent statement
        # because the actual one you want doesn't exist.   So we'll just save the grief, at
        # least for PDF statements because we know the URL that would retrieve the PDF (that
        # might otherwise not be retrievable at all.

        browser.goto "https://www.att.com/view/titan_printer_friendly.action?statementID=#{date_to_string}|#{account_number}|T01|W"

        puts "file_rename_lookup[#{date_to_string}]=att_phone_statement.#{phone_number}.d#{date_from_string}_#{date_to_string}.pdf"
        file_rename_lookup[date_to_string]="att_phone_statement.#{phone_number}.d#{date_from_string}_#{date_to_string}.pdf"

        downloaded_files += 1
      end
    end

    statement_date_list.push([date_from_string, date_to_string])
  end

}


# Now let's process the stored list of URLs to grab individual bills.
# (Looks like we could just as easily start at any one of these pages
# and select any bill, but perhaps this is an easier way to get them.)
#
puts""
puts "Processing stored urls for bills:"
# (Only landline accounts will have anything here.)
statement_url_list.reverse_each do |x|
  puts "  Processing stored url"

  # We're reversing this operation:
  #   statement_url_list.push([bill_link.text, bill_link.href.to_s, date_from_string, date_to_string])

  bill_link_text, bill_link_href, date_from_string, date_to_string = x

  puts "    bill_link_text=#{bill_link_text}  date_to_string=#{date_to_string}"

  # Only bother going to the page if we're interested in the html or csv info we'll get.
  if not ( ( download_bills_html==1 && existing_files[phone_number+'.'+date_to_string+'.html'] != 1 ) ||
           ( download_usage==1 && (existing_files[phone_number+'.'+date_to_string+'.voice_usage.csv'] != 1 ) ) )
    puts "    Nothing to retrieve for this bill."
    next
  end

  # Bring up a bill detail main page.
  puts "    Goto bill page: "+bill_link_href
  browser.goto bill_link_href

  # Check to see if we've got the right bill.  Due to some advanced
  # muppetry the bill history lists 'View' links for detailed bill
  # info pages the website can't provide.  We check we're looking at
  # the right bill.  If not, we decline further info extraction for
  # this bill because we've already got the PDF and there simply isn't
  # any html or usage/csv info to get.
  combo=browser.select_list(:name, 'stmtID')
  badpage=false
  combo.selected_options.each {
    |selected|
    puts "    Selected: '#{selected.text}'"
    # Selected: ' September 06, 2012 - October 05, 2012 '
    t=Time.parse(selected.text.split('-')[1].strip)
    puts "    time.parse: "+t.strftime("  %Y%m%d")
    yyyymmdd=t.strftime("%Y%m%d")
    if (yyyymmdd != date_to_string) 
      puts "    WRONG BILL DETAIL PAGE.  DECLINING TO COLLECT PAGE DATA."
      badpage=true
      break
    end
  }
  if (badpage)
    next
  end


  html_filename = File.join(destdir, "att_phone_statement.#{phone_number}.d#{date_from_string}_#{date_to_string}.html")

  # Save a copy of the html if we want it.
  if ( download_bills_html==1 && existing_files[phone_number+'.'+date_to_string+'.html'] != 1 )
    puts "    Saving a HTML version of the bill"
    File.open(html_filename, 'w+b') { |file| file.puts(browser.html) }
  end

  if (download_usage==1 && existing_files[phone_number+'.'+date_to_string+'.voice_usage.csv'] != 1 )
    puts "    Seeing if there is any usage."

    usage_link=browser.link(:text, "Usage details")
    if (not usage_link.exists?)
      puts "    No usage details link.  Nothing to download."
    else
      puts "    There's usage.  Clicking on the usage details link"
      usage_link.click

      # Click 'off' link if it exists, so we get numbers, not translated into names.
      if (browser.link(:name, 'offlink').exists?)
        browser.link(:name, 'offlink').click
      end


      #mytable=browser.div(:id, 'subsections').table(:class, 'table stripe mobileTable')
      mytable=browser.table(:class, 'table stripe mobileTable')

      csv_filename  = File.join(destdir, "att_phone_statement.#{phone_number}.d#{date_from_string}_#{date_to_string}.voice_usage.csv")
      csv_file=File.open(csv_filename, 'w')
    
      fields=['Item_No', 'Date Time', 'Calling TN', 'Called TN', 'Dur(s)', 'Amount', 'Tax', 'Total_amt', 'Rate Type', 'Status', 'Call Type', 'Billed TN', 'Location']
      csv_file.puts fields.join("\t")

      mytable.rows.each_with_index {
        |r, i|

        # First row is a header.
        if (i==0)
          next
        end

        #puts '      ROW'+i.to_s+' N:' + r.cell(:index, 0).text
        #puts '      ROW'+i.to_s+' DATE:' + r.cell(:index, 1).text
        #puts '      ROW'+i.to_s+' TIME:' + r.cell(:index, 2).text
        #puts '      ROW'+i.to_s+' NUMBER:' + r.cell(:index, 3).text
        #puts '      ROW'+i.to_s+' PLACE:' + r.cell(:index, 4).text
        #puts '      ROW'+i.to_s+' MINUTES:' + r.cell(:index, 5).text
        #puts '      ROW'+i.to_s+' AMOUNT:' + r.cell(:index, 6).text
        ##puts '      ROW'+i.to_s+' LD:' + r.cell(:index, 6).text
        ##puts '      ROW'+i.to_s+' FEATURE:' + r.cell(:index, 7).text
        #puts

        n=r.cell(:index, 0).text
        date=r.cell(:index, 1).text.strip
        time=r.cell(:index, 2).text
        tn=r.cell(:index, 3).text.strip.gsub(/\D/, '')
        call_location=r.cell(:index, 4).text.strip
        minutes=r.cell(:index, 5).text.strip
        #airtime=r.cell(:index, 5).text.strip
        #ld=r.cell(:index, 6).text.strip
        #feature=r.cell(:index, 7).text.strip
        amount=r.cell(:index, 6).text.strip

        usage_mm, usage_dd = date.split('/')

        # Figure out what year the usage is (tossers only give mm/dd).
        # YYYYMMDD of the usage must be less than or equal to the YYYYMMDD of the bill.
        # Start by assuming that usage year is same as statement year, and then correct if needed.
        yyyy, mm, dd=date_to_string[0..3],date_to_string[4..5],date_to_string[6..7]
        usage_yyyy=yyyy
        if (date_to_string < usage_yyyy+usage_mm+usage_dd) 
          usage_yyyy = (usage_yyyy.to_i - 1).to_s
        end

        # Throw in a timezone if we have one (and the time doesn't already have one (here it doesn't))
        time_in="#{date}/#{usage_yyyy} #{time}"
        if (tz != '') 
          time_in = time_in+" "+tz
        end
        t=Time.parse(time_in)
        #puts "  time.parse: "+t.strftime("  %Y%m%d %H%M %Z")
        #if (tz != '') 
        #  yyyymmdd_hhmm_tz=t.strftime("%Y-%m-%d %H:%M %Z")
        #else
        #  yyyymmdd_hhmm_tz=t.strftime("%Y-%m-%d %H:%M")
        #end
        #datetime = yyyymmdd_hhmm_tz
        datetime = t.iso8601

        calling_tn=phone_number
        called_tn=tn
        billed_tn=phone_number
        seconds=(minutes.to_i)*60
        rate_type=''
        status=''
        call_type='Voice'
        fields=[n, datetime, calling_tn, called_tn, seconds.to_s, amount, '0.00', amount, rate_type, status, call_type, billed_tn, call_location]
        puts "      "+fields.join(",")
        csv_file.puts fields.join("\t") # Yeah, it's tab-delimited, not CSV.  So sue me.

      }
      csv_file.close
      voice_usage_save_count += 1
    end
  end

end
puts "Done processing stored urls for bills."


# Now let's process the stored list of URLs to grab individual bills.
# (Looks like we could just as easily start at any one of these pages
# and select any bill, but perhaps this is an easier way to get them.)
#
puts""
puts "Processing stored list of bill dates to download for html and/or usage:"
# (Only wireless will have anything here.)
statement_date_list.reverse_each do |x|
  # We're reversing this operation:
  #   statement_date_list.push([date_from_string, date_to_string])
  date_from_string, date_to_string = x

  puts "  Processing stored date: '#{date_from_string} -- #{date_to_string}'"

  html_filename = File.join(destdir, "att_phone_statement.#{phone_number}.d#{date_from_string}_#{date_to_string}.html")

  # Grab the HTML bill if needed.
  if (download_bills_html==1)
    if existing_files[phone_number+'.'+date_to_string+'.html'] == 1
      puts "    Already have HTML copy of this bill."
    else
      # This will bring the HTML bill (it's buried in ajax and popup crap in their links)
      #browser.goto "https://www.att.com/olam/billPrintPreview.myworld?billStatementID=#{date_to_string}|#{account_number}|T01|W"
      browser.goto "https://www.att.com/olam/billPrintPreview.myworld?fromPage=history&billStatementID=#{date_to_string}|#{account_number}|T01|W&reportActionEvent=A_VB_BILL_PRINT"
      
      puts "    Saving a HTML version of the bill ('#{html_filename}')"
      File.open(html_filename, 'w+b') { |file| file.puts(browser.html) }
    end
  end



  ['voice', 'text', 'data'].each_with_index { |usage_type, i|

    # Grab the voice/text/data usage if needed.
    if (download_usage==1)

      if existing_files[phone_number+'.'+date_to_string+'.'+usage_type+'_usage.csv'] == 1
        puts "    Already have CSV #{usage_type} usage of this bill."
      else
        puts "    Fetching #{usage_type} usage info for this bill."

        browser.goto "https://www.att.com/olam/#{['talk', 'text', 'web'][i]}BillUsageDetail.myworld?billStatementID=#{date_to_string}|#{account_number}|T01|W&ctn=#{phone_number}"

        csv_filename  = File.join(destdir, "att_phone_statement.#{phone_number}.d#{date_from_string}_#{date_to_string}.#{usage_type}_usage.csv")
        csv_file=File.open(csv_filename, 'w')

        if    (usage_type=='voice')
          fields=['Item_No', 'Date Time', 'Calling TN', 'Called TN', 'Dur(s)', 'Amount', 'Tax', 'Total_amt', 'Rate Type', 'Status', 'Call Type', 'Billed TN', 'Location']
          no_records_regexp="Looks like you didn\'t make or receive any calls"
          voice_usage_save_count += 1
        elsif (usage_type=='text')
          fields=['Date Time', 'Calling TN', 'Called TN', 'Billed TN', 'Amount', 'Usage type']
          no_records_regexp="You did not send or receive any text messages"
          text_usage_save_count += 1
        elsif (usage_type=='data')
          fields=['Date Time', 'Size', 'Amount']
          no_records_regexp="Looks like you didn\'t use any data during this billing period"
          data_usage_save_count += 1
        else
          puts "Weird error"
          exit
        end

        # Yeah, it's tab-delimited, not CSV.  So sue me.
        csv_file.puts fields.join("\t")

        if ( (browser.div(:class, 'msg box').exists?) && (browser.div(:class, 'msg box').text =~ /#{no_records_regexp}/ ))
          puts "    No #{usage_type} usage on this statement."
        else

          if (usage_type != 'data')
            # We (or at least I) probably want numbers rather than phone-book translation.  (If not, fix the rest of
            # the code that assumes phone numbers are, well, numbers.)  But not applicable for data usage records.
            browser.radio(:id, 'show_numbers').set
          end

          puts "    Usage table for #{usage_type}: #{date_to_string}"
          n=0
          browser.div(:class, 'scroller_tbl').table(:id, 't').rows.each_with_index {
            |r, i|

            #puts "      Row: #{i+1}"
            #r.cells.each {
            #  |c|
            #
            #  puts "        Cell: '#{c.text}'"
            #}

            cell_list = r.cells

            datetime=cell_list[0].text
            # Throw in a timezone if we have one (and the time doesn't already have one (here it doesn't))
            # If no timezone exists, it might get tagged zulu.  Nah, probably whatever localtime is.
            if (tz != '') 
              datetime = datetime+" "+tz
            end
            t=Time.parse(datetime)
            #puts "      time.parse: "+t.strftime("  %Y%m%d %H%M %Z")
            #if (tz != '') 
            #  yyyymmdd_hhmm_tz=t.strftime("%Y-%m-%d %H:%M %Z")
            #else
            #  yyyymmdd_hhmm_tz=t.strftime("%Y-%m-%d %H:%M")
            #end
            #datetime = yyyymmdd_hhmm_tz
            datetime = t.iso8601


            if (usage_type=='voice')
              tn=cell_list[1].text.strip.gsub(/\D/, '')
              tn_class=cell_list[1].div().attribute_value("class")
              #tn_class=cell_list[1].div().class_name  # This would work too, but don't say '.class', get ruby's regular class operator.
              call_location=cell_list[2].text.strip
              rate_type=cell_list[3].text.strip   # Their headings calls it a call type but it looks like a rate type.
              minutes=cell_list[4].text.strip
              amount=cell_list[5].text.strip
              #
              seconds=(minutes.to_i)*60
            elsif (usage_type=='text')
              tn=cell_list[1].text.strip.gsub(/\D/, '')
              tn_class=cell_list[1].div().attribute_value("class")
              #tn_class=cell_list[1].div().class_name  # This would work too, but don't say '.class', get ruby's regular class operator.
              text_usage_type=cell_list[2].text.strip
              amount=cell_list[3].text.strip
            elsif (usage_type=='data')
              size=cell_list[1].text.strip.gsub(/\,/, '')   # Units are KBs, unless otherwise specified.  Ditch commas.
              #blank=cell_list[2].text.strip
              amount=cell_list[3].text.strip
            else
              puts "Weird error"
              exit
            end

            # Figure direction for voice or text.
            if ( (usage_type=='voice') || (usage_type=='text') )
              if (tn_class =~ /^incomingCall/i)
                calling_tn=tn
                called_tn=phone_number
              elsif (tn_class =~ /^outgoingCall/i)
                calling_tn=phone_number
                called_tn=tn
              else
                # No idea what to do here.  We'll assume it's outbound for now.
                calling_tn=phone_number
                called_tn=tn
              end
              billed_tn=phone_number
            end


            if (usage_type=='voice')
              status=''
              call_type='Voice'
              fields=[i+1, datetime, calling_tn, called_tn, seconds.to_s, amount, '0.00', amount, rate_type, status, call_type, billed_tn, call_location]
              puts "      "+fields.join(",")
              csv_file.puts fields.join("\t") # Yeah, it's tab-delimited, not CSV.  So sue me.
            elsif (usage_type=='text')

              # As a rough standard for my collection of screen-scraping, csv-saving CDR files
              # this is the plan for the csv files for text messages.

              # date_time, start time of call (iso.8601, with timezone)
              # From TN (Can be tricky depending on info we can figure out)
              # To TN  (Can be tricky depending on info we can figure out)
              # Billed TN
              # text_usage_type ("Text/instant messaging", "Multimedia messaging")
              # amount       (In $dollars.cents)

              fields=[datetime, calling_tn, called_tn, billed_tn, amount, text_usage_type]
              puts     "      "+fields.join(",")
              csv_file.puts fields.join("\t") # Yeah, it's tab-delimited, not CSV.  So sue me.

            elsif (usage_type=='data')
              fields=[datetime, size, amount]
              puts     "      "+fields.join(",")
              csv_file.puts fields.join("\t") # Yeah, it's tab-delimited, not CSV.  So sue me.
            else
              # It should never get here.
              puts "Weird error"
              exit
            end

          }
          puts "    End of table"
        end
        csv_file.close

      end

    end
  }


end
puts "Done processing dates for bills."


# Here we rename any files downloaded from the web interface (ie named by their end
# but we want to rename to our own scheme, after we've confirmed the download).
#
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
    if (l.text =~ /^ATT_(\d+)_(\d+).pdf$/)
      # 'ATT_8122935627480_20131106.pdf'
      puts "  Found PDF statement file for renaming: #{l.text}"

      account_number_key=Regexp.last_match[1]  # Not used for anything.
      date_key=Regexp.last_match[2]

      puts "date_key='#{date_key}'"
      newfilename = File.join(destdir, file_rename_lookup[date_key])

      #puts "    Do:    File.rename('#{File.join(tempdir, l.text)}', '#{newfilename}')"
      #File.rename(File.join(tempdir, l.text), newfilename)
      puts "    Do:    FileUtils.mv('#{File.join(tempdir, l.text)}', '#{newfilename}')"
      FileUtils.mv(File.join(tempdir, l.text), newfilename)

      statement_pdf_save_count += 1

      
    end

  }

  puts "Pausing to let any network/file operations to settle."
  sleep(5)
end


if (downloaded_files != statement_pdf_save_count)
  #??????????? Raise hell.
end

summary += "PDF statements downloaded:    #{statement_pdf_save_count}/#{statement_count}\n"

summary += "Voice usage files downloaded: #{voice_usage_save_count}/#{statement_count}\n"

if (! landline)
  summary += "Text usage files downloaded:  #{text_usage_save_count}/#{statement_count}\n"
  summary += "Data usage files downloaded:  #{data_usage_save_count}/#{statement_count}\n"
end



puts "Deleting the temporary directory (#{tempdir})"  # Which should be empty
begin
  Dir.rmdir(tempdir)
rescue
  puts "Warning: problems deleting directory (#{tempdir})."
end

# Audible alert.  Yeah, it's goofy, but handy for testing.  Ditch it if you don't like it.
puts "\007"  # Ring a bell.






pause_secs=5

puts progname+' logging off in '+pause_secs.to_s+' seconds...'
sleep(pause_secs)  # To make sure things have settled down.
# Logout page
browser.goto 'https://www.att.com/olam/logout.olamexecute'

puts progname+' Closing browser in '+pause_secs.to_s+' seconds...'
sleep(pause_secs)
browser.close

#??????????? This is optimistic/delusional.  Intend to add some sanity checks later.
summary += "Errors: 0\n"

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

