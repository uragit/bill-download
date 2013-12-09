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

require 'rubygems'
require 'watir-webdriver'
require 'getoptlong'
require 'time'

config_filename='./att.conf'

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

username=cfg['username']
password=cfg['password']
passcode=cfg['passcode']

# Passcode is optional, unless needed for login, then it will fall over at login failure.
if (username.nil? || password.nil?)
  puts "Can't get login credentials from config file."
  exit
end


# Where we're going to collect all the downloaded, renamed files.
destdir=cfg['destdir'].nil? ? "downloads/att" : cfg['destdir']

# Where to stash temporary files.  (Note: we'll also append the PID)
tempdir=cfg['tempdir'].nil? ? "downloads/tmp" : cfg['tempdir']
tempdir=tempdir+"."+Process.pid.to_s

# What to do at run time.
download_bills_pdf=cfg['download_bills_pdf'].nil? ? 1 : cfg['download_bills_pdf'].to_i
download_bills_html=cfg['download_bills_html'].nil? ? 1 : cfg['download_bills_html'].to_i
download_usage=cfg['download_usage'].nil? ? 1 : cfg['download_usage'].to_i

# In which timezone do you want times interpreted?
tz=cfg['tz'].nil? ? 'PST8PDT' : cfg['tz']

# Probably better to pull these from the webpage itself.
phone_number=cfg['phone_number']

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
existing_htmls={};
existing_csvs={};
filename_map={};
#
puts 'Listing existing files in download directory:'
Dir.foreach(destdir) { |filename|
  # Combine all three types into a single one with merged key.????????????
  if    (filename =~ /^att_phone_statement.(\d+).d(\d+).pdf$/) 
    puts '  Filename: '+filename
    phone_number_key=Regexp.last_match[1]
    date_key=Regexp.last_match[2]
    key=phone_number_key+'.'+date_key
    existing_pdfs[key]=1
  elsif    (filename =~ /^att_phone_statement.(\d+).d(\d+).html$/) 
    puts '  Filename: '+filename
    phone_number_key=Regexp.last_match[1]
    date_key=Regexp.last_match[2]
    existing_htmls[phone_number_key+'.'+date_key]=1
  elsif    (filename =~ /^att_phone_statement.(\d+).d(\d+).csv$/) 
    puts '  Filename: '+filename
    phone_number_key=Regexp.last_match[1]
    date_key=Regexp.last_match[2]
    existing_csvs[phone_number_key+'.'+date_key]=1
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
# No idea if the next line will work.
profile['content_settings.pattern_pairs.*,*.multiple-automatic-downloads'] = 1
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


# To disable the retarded "This site is attempting to download multiple files" problem.
# Try some of these options.  But I don't know how they relate to ruby/watir.

#chrome options: { "profile.content_settings.pattern_pairs.,.multiple-automatic-downloads", 1 }

#options.prefs = new Dictionary<string, object>
#{
#	{ "profile.content_settings.pattern_pairs.*.multiple-automatic-downloads", 1 }
#};

# Here's an actual code fragment.  See attempt above to make it work.
# case Browser.Chrome:
#   var options = new ChromeOptionsWithPrefs();
#   options.AddArguments("start-maximized");
#   options.AddArguments("disable-extensions");
#   options.prefs = new Dictionary<string, object>
#     {
#       { "download.default_directory", resultPath },
#       { "download.directory_upgrade", true },
#       { "download.prompt_for_download", true },
#       { "profile.content_settings.pattern_pairs.*,*.multiple-automatic-downloads", 1 }
#     };



# The view links execute something like this:
#    <a href="javascript:void(0);" class="wt_Body" desturl="/view/viewfullbillPDF.doview" onclick="window.open('/view/viewfullbillPDF.doview?stmtID=20120605|7753295648280|S|P&amp;reportActionEvent=A_VB_VIEW_FULL_BILL_PDF_LINK', 'viewpdf', config='height=600, width=800, toolbar=no, menubar=yes, scrollbars=yes, resizable=yes, location=no, directories=no, status=no'); return false;">PDF</a>
# Trouble is, they count as a bunch of auto downloads in a row, triggering
# chrome's retarded "This site is attempting to download multiple files"
# for which there is no defence.   Might be better to parse out the
# URL and explicitly ask for the PDF files.   Anyway, probably can't test it
# now because I hit the "allow" button, and it probably remembers.
#
# Oh, that's okay, stewardess, I speak 'tard.





def disable_pdf_plugin(browser)

  puts 'Going to about:plugins page (to disable plugins, so PDFs save):'

  # This is much simpler!
  # disable Chrome PDF Viewer
  browser.goto "about:plugins"
  browser.span(:text => "Chrome PDF Viewer").parent.parent.parent.a(:text => "Disable", :class => "disable-group-link").click

end

disable_pdf_plugin(browser)


# Window activity seems to trigger some confusing javascript which breaks the login.
puts "Don't resize window before login!" 

browser.goto 'https://www.att.com/olam/loginAction.olamexecute'

browser.text_field(:name, 'userid').set username
login_button=browser.input(:title, 'Login')
login_button.click
sleep(1)
browser.text_field(:id, 'password').set password
sleep(1)
#
# Seems to need two of these.  This combo works.  Others don't.  Some others might.
#login_button.click
browser.input(:title, 'Login').click
#browser.input(:class, 'MarTop10').click

if (passcode != '')
  # If we have a passcode, we assume it's because it's asked for here.

  browser.text_field(:id, 'passcode').set passcode
  browser.input(:id, 'bt_continue').click
end

sleep(2)

# Pull up a table of billing history (same for landline or mobile)
puts "Going to 'Billing history' page"
browser.goto 'https://www.att.com/olam/passthroughAction.myworld?actionType=ViewBillHistory&gnLinkId=t1004'
sleep(2)


# Grab the account number from the web page.
account_number=browser.div(:id, 'landing').li(:class, 'account-number').text
# ?????????? If this line screws up, you probably didn't login.  Go back and try again.
# ??????????? Catch the actual occurrence and figure what to look for.


phone_number=account_number[0..9]
puts "account_number='#{account_number}', phone_number='#{phone_number}'  "


puts "Processing lines in billing history table:"
i=0
statement_url_list=[]
mytable=browser.table(:class, 'table tableNoPad')
mytable.rows.each {
  |r|
  i += 1

  if (i==1) # First line is header info.
    next
  end

  cell_list = r.cells
  bill_period=cell_list[0].text
  #plans_and_service_charges=cell_list[1].text   # (Who cares)
  total_amount_due=cell_list[2].text
  bill_link = cell_list[3].link(:index, 0)
  
  puts "Row(#{i}): bill_period='#{bill_period}' total_amount_due='#{total_amount_due}'"

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

  puts '  total amount due '#{c_total_amount_due.text}'"

  # There's two kinds of bill links, one is 'View', a link to a separate page.
  # The other, for older bills, is a straightforward link 'PDF' to a pdf file.
  # (Annoyingly, the PDF link also pops up a window if you click on it.  With
  # a bit of luck, this doesn't break anything in our parsing of the current table.)


  key=phone_number+'.'+date_to_string
  if (bill_link.text.match(/View/)) 
    if (existing_pdfs[key]==1)
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
        downloaded_files += 1
      end
    end

    # Now save the info in the link for later processing, if we want html and csv(usage).
    puts "  Saving URL for possible later download of html and csv info."
    ## Save the href for later download.
    statement_url_list.push([bill_link.text, bill_link.href.to_s, date_to_string])

  elsif (bill_link.text.match(/PDF/)) 
    if (existing_pdfs[key]==1)
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
          puts "URL: '#{old_url}'"
          old_url =~ /^.*window\.open\(\'([^&]*)&/
          url='https://www.att.com'+Regexp.last_match[1]
          #
          # URL now looks something like this:
          #   'https://www.att.com/view/viewfullbillPDF.doview?stmtID=20131105|7753295648280|S|P'
          # We could have just formatted it ourselves (as we've done elsewhere
          # in the code) instead of parsing it out.  But, uh, well, here we are.
          #
          puts "URL: '#{url}'"
          browser.goto url
          downloaded_files += 1

        end
      end
    end
  end

}


# Now let's process the stored list of URLs to grab individual bills.
# (Looks like we could just as easily start at any one of these pages
# and select any bill, but perhaps this is an easier way to get them.)
#
puts
puts "Processing stored urls for bills:"
statement_url_list.reverse_each do |x|
  puts "  Processing stored url"

  # We're reversing this operation:
  #   statement_url_list.push([bill_link.text, bill_link.href.to_s, date_to_string])

  bill_link_text, bill_link_href, date_to_string = x

  puts "    bill_link_text=#{bill_link_text}  date_to_string=#{date_to_string}"

  # Only bother going to the page if we're interested in the html or csv info we'll get.
  if not ( ( download_bills_html==1 && existing_htmls[phone_number+'.'+date_to_string] != 1 ) ||
           ( download_usage==1      && existing_csvs[phone_number+'.'+date_to_string] != 1 ) )
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
    puts "    SELECTED: '#{selected.text}'"
    # SELECTED: ' September 06, 2012 - October 05, 2012 '
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


  html_filename = File.join(destdir, "att_phone_statement.#{phone_number}.d#{date_to_string}.html")
  csv_filename  = File.join(destdir, "att_phone_statement.#{phone_number}.d#{date_to_string}.csv")

  # Save a copy of the html if we want it.
  # But only if we want it.????????????????????
  if ( download_bills_html==1 && existing_htmls[phone_number+'.'+date_to_string] != 1 )
    puts "    Saving a HTML version of the bill"
    File.open(html_filename, 'w+b') { |file| file.puts(browser.html) }
  end

  if (download_usage==1 && existing_csvs[phone_number+'.'+date_to_string] != 1 )
    puts "    Seeing if there is any usage."

    usage_link=browser.link(:text, "Usage details")
    if (not usage_link.exists?)
      puts "    No usage details link.  Nothing to download."
    else
      puts "    There's usage.  Clicking on the usage details link"
      usage_link.click
      #mytable=browser.div(:id, 'subsections').table(:class, 'table stripe mobileTable')
      mytable=browser.table(:class, 'table stripe mobileTable')

      csv_file=File.open(csv_filename, 'w')
    
      csv_file.puts 'Item_No, Date Time, Place Called, Number, Minutes, Amount'
      #csv_file.puts 'Item_No, Date Time, Place Called, Number, Code, Minutes, Amount, AirtimeCharge, OtherCharge'

      i=0
      mytable.rows.each {
        |r|

        i=i+1

        # First row is a header.
        if (i==1)
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
        place_called=r.cell(:index, 4).text.strip
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
        if (tz != '') 
          yyyymmdd_hhmm_tz=t.strftime("%Y-%m-%d %H:%M %Z")
        else
          yyyymmdd_hhmm_tz=t.strftime("%Y-%m-%d %H:%M")
        end
        datetime = yyyymmdd_hhmm_tz

        puts          "      "+[n, datetime, place_called, tn, minutes, amount].join(',')
        csv_file.puts          [n, datetime, place_called, tn, minutes, amount].join(',')

      }
      csv_file.close
    end
  end

end
puts "Done processing stored urls for bills."


if (downloaded_files==0) 
  puts 'No new files to rename/download from browser.'

  # ???? Some sanity checks, based on actual date, vs listed html
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
      # 'ATT_7753295648280_20131105.pdf'
      puts "  Found PDF statement file for renaming: #{l.text}"

      phone_number_key=Regexp.last_match[1]
      date_key=Regexp.last_match[2]

      newfilename = File.join(destdir, "att_phone_statement.#{phone_number}.d#{date_key}.pdf")
      
      puts "    Do:    File.rename(#{File.join(tempdir, l.text)}', '#{newfilename})"
      File.rename(File.join(tempdir, l.text), newfilename)

      # ???? Might be better if moving cross filesystems.  
      # FileUtils.mv(File.join(tempdir, l.text), newfilename)
      
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


pause_secs=5
# Audible alert.  Yeah, it's goofy, but handy for testing.  Ditch it if you don't like it.
puts "\007"  # Ring a bell.
puts progname+' exiting in '+pause_secs.to_s+' seconds...'
sleep(pause_secs)  # To make sure things have settled down.

# Logout page
browser.goto 'https://www.att.com/olam/logout.olamexecute'
sleep(pause_secs)

browser.close

puts progname+' ended'


__END__

