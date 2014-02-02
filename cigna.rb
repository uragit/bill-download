#!/usr/bin/ruby
# cigna.rb -- Downloads medical claims (etc) documents from mycigna.com.
#   ./cigna.rb --config cigna.conf



# Notes:
#
#   To run:
#
#   Claims have a one-to-one relationship with EOBs (Explanation of Benefits).
#     For each file there will be (eg):
#       cigna.u07812345.medical_claim_9681123456789.d20130823.explanation_of_benefits.pdf
#       cigna.u07812345.medical_claim_9681123456789.d20130823.claim_details.FRED.QUEST_DIAG.csv
#       cigna.u07812345.medical_claim_9681123456789.d20130823.claim_details.FRED.QUEST_DIAG.html
#
#   The code won't re-download the .pdf files.  It also assumes that
#   the info in the .csv and .html files doesn't change once they've
#   been seen, so it also won't overwrite them.  This is probably a
#   good assumption but it's hard to know for sure
#
#   Database creation:
#     See notes in cigna.sql
#
#   Disclaimer:
#     This code worked for me, at least once, on a particular account on
#     a particular computer.   Maybe it will work for you.  If not, then
#     maybe it will almost work, and maybe that's better than nothing.
#     Maybe it's not.   
#
#     It's a work in progress and could probably use some improvement.
#     (I'm new to Ruby and it probably shows.)
#     If it breaks, you get to keep both pieces.



# Add an error test if we don't see a prescriptions table.

#????????
#
# Check that the order of claim summary is the order we pull the details.
#
# Also pull health statements (of which I don't have any).  Can't test.


#???????? Pull account_name from the website.
#  Or just ditch the whole thing.  Doesn't seem to have much relevance.
#  Or just leave it as a hardcoded thing in config, to use in filenames.
#
# Optional account_name, used for identifying files.  Hmmm??????? But not put into database entries.








# Define a method to execute blocks without warnings.
def silently(&block)
  warn_level = $VERBOSE
  $VERBOSE = nil
  result = block.call
  $VERBOSE = warn_level
  result
end

silently {
  require 'rubygems'
  require 'watir-webdriver'
  require 'getoptlong'
  require 'time'
  require 'dbi'
  #require 'mysql'
  #require 'dbd-mysql'
  require 'fileutils'
}

config_filename='./cigna.conf'

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
      # Decide whether we're dealing with a string or a number.
      value=value.strip
      #if (value =~ /^\d+$/)
      #  value=value.to_i
      #elsif (value =~ /^\"([^\"]*)\"$/)
      #  # If they really want a string, they can put quotes around it.
      #  value = Regexp.last_match[1]
      #end
      cfg[parameter.strip]=value
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
account_name=cfg['account_name']

# Database credentials for database for claims, claims details, and prescription claims.
db_username = cfg['db_username']
db_password = cfg['db_password']
db_connect  = cfg['db_connect' ].nil? ? "DBI:Mysql:cigna:localhost" : cfg['db_connect']

download_eobs          = cfg['download_eobs'].nil?          ? 1 : cfg['download_eobs'].to_i
download_claims        = cfg['download_claims'].nil?        ? 1 : cfg['download_claims'].to_i
download_prescriptions = cfg['download_prescriptions'].nil? ? 1 : cfg['download_prescriptions'].to_i


debug      = cfg['debug'].nil?  ? 0 : cfg['download_cdrs'].to_i


# Not a command-line option.  Just code it here.
#csv_separator=", "
csv_separator="\t"  # Yeah, so it's not really a csv.  So sue me.


####################################
####################################

progname=File.basename($0)


begin
  # Command-line options, will override settings in config file.


  def printusage()
    puts 
    puts "Usage: #{$0} [options]"
    puts "Options:" 
    puts "  --config|-c filename            (configuration file with key=value pairs)"
    puts "  --destdir|-d directory          (for final destination of downloading)"
    puts "  --tempdir|-t directory          (for temporary staging)"
    puts "  --username|-u username          (safer to specify in config file)"
    puts "  --password|-p password          (safer to specify in config file)"
    puts "  --account_name account-name     (safer to specify in config file)"
    puts "  --db_username username          (safer to specify in config file)"
    puts "  --db_password password          (safer to specify in config file)"
    puts "  --db_connect DB-connect-string  (safer to specify in config file)"
    puts "  --download_eobs"
    puts "  --download_claims"
    puts "  --download_prescriptions"
    puts "  --debug                         (output some debugging info.)"
    exit(1)
  end

  opts=GetoptLong.new(
                      ["--help",     "-h",         GetoptLong::NO_ARGUMENT],
                      ["--config",   "-c",         GetoptLong::OPTIONAL_ARGUMENT],
                      ["--destdir",  "-d",         GetoptLong::REQUIRED_ARGUMENT],
                      ["--tempdir",  "-t",         GetoptLong::REQUIRED_ARGUMENT],
                      ["--username", "-u",         GetoptLong::REQUIRED_ARGUMENT],
                      ["--password", "-p",         GetoptLong::REQUIRED_ARGUMENT],
                      ["--account_name",           GetoptLong::REQUIRED_ARGUMENT],
                      ["--db_username",            GetoptLong::REQUIRED_ARGUMENT],
                      ["--db_password",            GetoptLong::REQUIRED_ARGUMENT],
                      ["--db_connect",             GetoptLong::REQUIRED_ARGUMENT],
                      ["--download_eobs",          GetoptLong::NO_ARGUMENT],
                      ["--download_claims",        GetoptLong::NO_ARGUMENT],
                      ["--download_prescriptions", GetoptLong::NO_ARGUMENT],
                      ["--debug",                  GetoptLong::NO_ARGUMENT]
                    )

  opts.each { |option, value|
    case option
    when "--help"
      printusage()
    when "--config"
      # Nothing to do.  Handled earlier.
    when "--destdir"
      destdir = value
    when "--tempdir"
      tempdir = value
    when "--username"
      username = value
    when "--password"
      password = value
    when "--account_name"
      account_name = value
    when "--db_username"
      db_username = value
    when "--db_password"
      db_password = value
    when "--db_connect"
      db_connect = value
    when "--download_eobs"
      download_eobs = 1
    when "--download_claims"
      download_claims = 1
    when "--download_prescriptions"
      download_prescriptions = 1
    when "--debug"
      debug = 1
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

if (username.nil? || password.nil? || account_name.nil?)
  puts "Can't get login credentials from config file."
  exit
end

need_db=false
if (download_claims==1 || download_prescriptions==1)
  need_db=true

  if (db_username.nil? || db_password.nil? || db_connect.nil?)
    puts "Can't get db login credentials from config file."
    exit
  end
end


# Add PID to tempdir pathname.
tempdir=tempdir+"."+Process.pid.to_s

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


def dollars2cents(dollars_in)
  # '$1,234.56' -> 123456
  cents_out=0

  #puts "dollars_in='#{dollars_in}'"

  if (dollars_in.gsub(/[\$\,\s]/,'') =~ /^(\d+)\.(\d\d)$/)
    dollars = Regexp.last_match[1].to_i
    cents   = Regexp.last_match[2].to_i
    cents_out = dollars*100 + cents
  else
    STDERR.puts "Odd money format '#{dollars_in}'"
    # Give more info in error!  ?????????.  Dump the stack, throw an error, etc.
    exit
  end
  #puts "cents_out='#{cents_out}'"
  return(cents_out)

end



####################################
####################################


summary=""

start_time=Time.now
puts       "#{progname} starting: #{start_time}"
summary += "#{progname} started:  #{start_time}\n"




if (! File.directory?(destdir))
  puts "Can't find destination directory ("+destdir+").  Exiting.  Perhaps you're running in the wrong directory."
  exit
end


puts 'Place for temp files: '+tempdir

if (File.directory?(tempdir))
  puts "  Directory exists."
else
  puts "  Directory ("+tempdir+") does not exist.  Creating."
  Dir.mkdir(tempdir)
  # ????? Fail on errors (if a regular file already exists with the name, etc)
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

#mycontainer = Watir::Container

# It would be nice to be able to set a size for the window.   Don't know how to do this in chrome.
# (It seems chrome doesn't like the main window being resized.)
#browser.window.resize_to(700, 900)
#browser.driver.manage.window.resize_to(700,900)
#
#browser.window.resize_to(800, 600)
#browser.driver.manage.window.resize_to(700,800)
#browser.execute_script('window.resizeTo(500,500)')
#browser.execute_script('resizeTo(500,500)')
#browser.execute_script 'resizeTo(600,500)'


disable_pdf_plugin(browser)


if (debug==1)
  puts "Destdir =#{destdir}"
  puts "Tempdir =#{tempdir}"
end



puts 'Writing temporary files to: '+tempdir

if (File.directory?(tempdir))
  puts "  Directory exists."
else
  puts "  Directory (#{tempdir}) does not exist.  Creating."
  begin
    Dir.mkdir(tempdir)
  rescue
    STDERR.puts "Can't create directory (#{tempdir})."
    exit
  end
end



if (need_db)
  begin
    # connect to the MySQL server
    puts "Connecting to database server."
    dbh = DBI.connect(db_connect, db_username, db_password)
    # get server version string and display it
    #row = dbh.select_one("SELECT VERSION()")
    #puts "Server version: " + row[0]
  rescue DBI::DatabaseError => e
    puts "An error occurred"
    puts "Error code: #{e.err}"
    puts "Error message: #{e.errstr}"
  ensure
    # disconnect from server
    #puts 'Disconnect'
    #dbh.disconnect if dbh
  end
  #
  dbh.do("use cigna;")
end






# Let's list all the files we've already got downloaded (or scanned)
#
existing_eob_pdfs={}   # We keep particular track of PDFs, but in this case probably unecessary.
existing_files={}
#
puts 'Listing existing files in download directory:'
Dir.foreach(destdir) { |filename|
  existing_files[filename]=1   # This will catch the .csv and .html files.
  if    (filename =~ /^.*.pdf$/) 
    puts '  PDF Filename: '+filename
    existing_eob_pdfs[filename]=1
  else
    puts '  Filename: '+filename
  end
} 
total_new_files = 0
downloaded_files=0
eob_count=0
claim_count=0
claim_detail_count=0
eob_pdf_save_count=0
claim_detail_html_save_count=0
claim_detail_csv_save_count=0
claim_detail_line_items_save_count = 0
prescription_db_save_count = 0
claim_summary_db_save_count = 0
claim_detail_db_save_count = 0
prescription_total = 0
new_filenames = []

downloaded_pdf_files=0
# For renaming downloaded files afterwards.
link2filename_map={}



# Window activity seems to trigger some confusing javascript which breaks the login.
puts "Don't resize window before login!" 


# Okay, let's start the show.

puts "Going to login page."
browser.goto 'https://my.cigna.com/web/public/guest'
#sleep(1)


browser.text_field(:name, 'username').set username
browser.text_field(:name, 'password').set password
browser.form(:id, 'userForm').submit


# Yay, we're logged in, or should be.
# Uh, perhaps check login actually worked????
puts       "Successful login.\n"
summary += "Successful login.\n"
sleep(1)


# Grab EOB PDFs
if (download_eobs==1)
  # They splash some stupid javascript bumf at login so we manually go here.
  puts 'Going to claims page.'
  browser.goto 'https://my.cigna.com/web/secure/my/claims?WT.ac=mycigna_12820|claims'
  sleep(1)

  # Then click this.  Hey, they just changed it overnight from 'View all EOBs' to 'All EOBs'
  # It seems to vary from time to time.
  #browser.link(:text, 'View all EOBs').click
  #browser.link(:text, /All EOBs/).click
  browser.link(:text, /All EOBs/i).click
  # Looks like they only show them going back a year.  (ie that's all that's available.)

  puts 'Looking for table.'
  if (debug==1) 
    browser.tables.each {
      |table|

      puts '  This is a table.'

      table.rows.each {
        |row|

        puts '    This is a row.'

        row.cells.each {
          |cell|

          puts '      This is a cell: "'+cell.text.to_s+'"'
        }
      }
    }
  end

  browser.tables.each {
    |table|

    puts 'This is a table.'

    
    if (table.caption.exists?)
      puts 'Caption: '+table.caption.text.to_s
    else
      # The table we're interested in has a caption.  The others not so much.
      next
    end

    table.rows.each_with_index {
      |row, i|

      if (row.cells[0].text == '') 
        next
      end

      # Temp to speed things up while testing.
      #if (i > 3) 
      #  next
      #end

      puts "  This is a row(#{i})."

      row.cells.each_with_index {
        |cell, j|

        puts "    This is a cell(#{j}): '"+cell.text.to_s+"'"

      }

      if (i==0)
        puts "This is the row with the table headings."
        # So this field doesn't appear!?  Typically when accessing it manually.  Odd.  We check.
        puts "  Checking that row.cells[3].text=='Reference'..."
        if (row.cells[3].text=='Reference') 
          puts "    It's good."
        else
          puts "    row.cells[3].text=='"+row.cells[3].text+"'"
        end
        #
      elsif (row.cells[1].text =~ /(\d+)\/(\d+)\/(\d+)/) # It's the 2nd field we want.
        mm   = Regexp.last_match[1].to_i
        dd   = Regexp.last_match[2].to_i
        yyyy = Regexp.last_match[3].to_i

        date_key = "%04d%02d%02d" % [ yyyy,mm,dd ]
        puts "      Reckon the service date is #{date_key}"    

        processed_date=row.cells[0].text
        service_date=row.cells[1].text
        patient=row.cells[2].text
        reference=row.cells[3].text
        eob_type=row.cells[4].text.gsub(/\s/, '_').downcase

        pdf_link=row.cells[5].link
        puts "      Link: "+pdf_link.href.to_s

        eob_count += 1

        # EOB, explanation_of_benefits
        # "cigna.u00000000.medical_claim_51234567890.explanation_of_benefits.d20130212.pdf"
        eob_filename="cigna.#{account_name}.#{eob_type}_#{reference}.d#{date_key}.explanation_of_benefits.pdf"
        new_href_text=pdf_link.href.to_s

        if (existing_eob_pdfs[eob_filename]==1)
          puts "      We've already got this file #{eob_filename}."
        else
          puts "      We don't already have this file (downloading): "+eob_filename
          link2filename_map[new_href_text]=eob_filename

          pdf_link.click
          # It opens a new (blank) window but it doesn't seem to harm out execution
          # of the existing loop.
          downloaded_pdf_files += 1
          
        end

      else
        puts "Not sure what to make of this row.  We ignore it."
      end


    }
  }
end
# End of grabbing the Explanation of Benefits PDFs (if we're grabbing them).



# Now grab the html info for the claims.  (And parse the html into csv)
if (download_claims==1)
  # They splash some stupid javascript bumf at login so we manually go here.
  puts 'Going to claims page.'
  browser.goto 'https://my.cigna.com/web/secure/my/claims?WT.ac=mycigna_12820|claims'
  sleep(1)

  # Then click on.  Hey, they just changed it overnight from 'View all Claims' to 'All Claims'
  #   (In fact, it seems to vary from day to day.)
  #browser.link(:text, 'View all Claims').click
  #browser.link(:text, /All Claims/).click
  browser.link(:text, /All Claims/i).click
  # Looks like they only show them going back a year.  (ie that's all that's available.)


  puts 'Looking for table.'
  if (debug==1) 
    browser.tables.each { |table|
      puts '  This is a table.'
      table.rows.each {|row|
        puts '    This is a row.'
        row.cells.each { |cell|
          puts '      This is a cell: "'+cell.text.to_s+'"'
        }
      }
    }
  end

  table_n=0
  claim_filename_list=[]
  claim_args_list_of_lists=[]
  #
  claim_id, service_date, provided_by, provided_for, claim_status, 
  amount_billed, what_your_plan_paid, my_account_paid, what_i_owe = nil, nil, nil, nil, nil, nil, nil, nil, nil, 
  #
  browser.tables.each {
    |table|

    puts 'This is a table. (Claims.)'

    if (table.caption.exists?)
      #puts 'Caption: '+table.caption.text.to_s
    else
      #puts "  Table doesn't have a caption."
    end

    if (table_n > 0)
      puts "  Skipping table."
      next
    end
    table_n += 1

    table.rows.each_with_index {
      |row, i|

      if (row.cells[0].text == '') 
        next
      end

      # Temp to speed things up.
      #if (i > 3) 
      #  next
      #end

      puts "  This is a row(#{i}) (claims)."

      row.cells.each_with_index {
        |cell, j|
        puts "    This is a cell(#{j}). '"+cell.text.to_s+"'"
      }

      if (i==0)
        puts "  This is the row with the table headings."
      elsif (row.cells[0].text =~ /(\d+)\/(\d+)\/(\d+)/)
        mm   = Regexp.last_match[1].to_i
        dd   = Regexp.last_match[2].to_i
        yyyy = Regexp.last_match[3].to_i

        date_key = "%04d%02d%02d" % [ yyyy,mm,dd ]
        puts "      Reckon the date is #{date_key}"    

        claim_count += 1

        service_date=row.cells[0].text.to_s
        provided_by=row.cells[1].text.to_s.gsub(/\s+/, '_')
        provided_for=row.cells[2].text.to_s.gsub(/\s+/, '_') # Martin
        claim_status=row.cells[3].text.to_s # Paid/Processed/others?  (Probably changes with time)
        amount_billed=row.cells[4].text.to_s
        what_your_plan_paid=row.cells[5].text.to_s  # Might change over time.?
        my_account_paid=row.cells[6].text.to_s  # '--'   Might change over time.?
        what_i_owe=row.cells[7].text.to_s # Might change over time.?
        #
        # Funnily enough, I think they stash the real link in the 'name' field.
        #puts "Link: "+row.cells[8].link.name
        #browser.goto "https://mycigna.com"+row.cells[8].link.name
        # Yeah, but it just times out.  Time for Plan B.
        # Can just not the info we need here, such as the claim filename for html.
        # And then click to the first claim, and then move through using the 'next'
        # links.

        # Don't include any dull fields, or ones that might change over time.
        #
        # Don't hardcode 'medical_claim'?  Borrow the info from the pdf list?
        #   Actually, I think it can only be a medical claim because there is a separate
        #   area for prescription claims.  Stet.
        #
        # "cigna.u00000000.medical_claim_56412345678.explanation_of_benefits.d20130212.pdf"
        #eob_filename= "cigna.#{account_name}.#{eob_type}_#{reference}.explanation_of_benefits.d#{date_key}.pdf"
        #
        # We swap out the XXreferenceXX later when we pull it from the html.
        # (Could also have assumed the eobs were listed in the same order and have already pulled it.)
        claim_filename="cigna.#{account_name}.medical_claim_XXreferenceXX.d#{date_key}.claim_details.#{provided_for}.#{provided_by}.html"

        #
        puts "      Reckon filename is #{claim_filename}"

        claim_filename_list.push(claim_filename)
        # Need to remember the list of args for the sql insert for the claims table.
        claim_args_list_of_lists.push([nil, date_key, provided_by, provided_for, claim_status, amount_billed, what_your_plan_paid, my_account_paid, what_i_owe])

      else
        puts "Not sure what to make of this row. (Claims).  Ignoring it."
      end

    }
  }

  puts ''

  i=0
  puts 'Grabbing the individual claim details.'
  #
  claims_select_sth=nil
  claims_insert_sth=nil
  claim_details_select_sth=nil
  claim_details_insert_sth=nil
  #
  #
  claim_filename_list.each {
    |claim_filename|
    claim_args_list=claim_args_list_of_lists.shift

    puts "  Starting with file number #{i}, before editing: "+claim_filename

    if (i==0) 
      puts "    Clicking on the first claim link."
      #browser.link(:text, 'View Details').click
      browser.link(:text, 'Details').click
    else
      puts "    Clicking on the next(#{i}) claim link."
      # Hey, they just changed it overnight from 'Next Claim >' to 'Next >'
      #browser.link(:text, /^Next Claim/).click
      browser.link(:text, /^Next /).click
    end

    # We have to troll through the html to find the claim reference number.
    if (browser.html =~ /<h3>Claim # (\d+)<\/h3>/)
      claim_id = Regexp.last_match[1]
      puts "    Claim reference=#{claim_id}."

      claim_filename.gsub!(/XXreferenceXX/, claim_id)
    else
      puts "    Can't find claim reference for this claim."
      error_filename=File.join(tempdir, "claim_id#{i}.html")
      File.open(error_filename, 'w+b') { |file| file.puts(browser.html) }
      STDERR.puts "Can't find claim reference in html page.  Writing to '#{error_filename}'."
      exit
    end

    i += 1


    if (true)
      puts "    Processing entry for 'claims' table."
      # If we don't have it in the database, throw it in.
      #
      if (! claims_select_sth)
        claims_select_sth = dbh.prepare("SELECT * FROM claims WHERE claim_id=?")
      end
      claims_select_sth.execute(claim_id)
      # ????? Should perhaps check for errors here.
      row_count=0
      while db_row = claims_select_sth.fetch do
        puts "      DBI: "+db_row.join(", ")+"\n"
        row_count+=1
      end
      puts "      Rows returned (claims, for claim_id=#{claim_id})=#{row_count}"
      #
      if (row_count==0)
        if (! claims_insert_sth)
          claims_insert_sth = dbh.prepare("INSERT INTO claims (
                    claim_id, service_date, provided_by, provided_for, claim_status,
                    amount_billed, what_your_plan_paid, my_account_paid, what_i_owe)
                  VALUES
                    (?,?,?,?,?,?,?,?,?) ")
        end
        claim_args_list[0]=claim_id
        #claim_insert_sth.execute(claim_id, service_date, provided_by, provided_for, claim_status,
        #                         amount_billed, what_your_plan_paid, my_account_paid, what_i_owe)
        puts "      Inserting row (claims, for claim_id=#{claim_id})"
        claims_insert_sth.execute(*claim_args_list)
        claim_summary_db_save_count += 1
        # ????? Should perhaps check for errors here.
      end
    end


    # Now we have the full filename, based on the claim reference number
    # we can actually see if we've already got the html and csv files
    # downloaded.
    if (existing_files.has_key?(claim_filename))
      # For a quick insanity check, do we also have the csv file (should have, if we have html)
      if (existing_files.has_key?(claim_filename.gsub(/\.html$/, '.csv')))
        puts "  We've already got this file (#{claim_filename})."
        puts "    Also skipping the .csv file collection."
        next
      else
        puts "  We've already got this file (#{claim_filename}), but still need the .csv file.  Getting."
      end
    else
      # The whole page has a bunch of junk so we just file the relevant div.
      #File.open(File.join(destdir, claim_filename), 'w+b') { |file| file.puts(browser.html) }
      File.open(File.join(destdir, claim_filename), 'w+b') { |file| file.puts(browser.div(:id, 'main-contentWrapper').html) }

      claim_detail_html_save_count += 1
      new_filenames.push(File.join(destdir, claim_filename))
      total_new_files += 1

    end
    #



    # Now pull the info from the html, for storing in a database.
    column_index={}
    print "Parsing through the html to extract claim detail info."
    #
    claim_csv_filename=claim_filename.gsub(/\.html$/, '.csv')
    #
    # ??????? If the code blows up after csv creation, but before it's finished
    # it will look bogus, and likely prevent writing records to the claims_detail and/or claims database.
    #
    File.open(File.join(destdir, claim_csv_filename), 'w+b') { |file|
      browser.div(:id, 'main-contentWrapper').tables.each_with_index {
        |table, table_n|

        # There seems to be only one table in this subset of html.
        puts "  This is a table (#{table_n})."
        
        discount_column_missing=0
        table.rows.each_with_index {
          |row, row_n|

          puts "    This is a row (#{row_n})."
          # This is putting things in a strange order.???? Get it inside the loop.

          if (table_n==0) # Should perhaps also parse out the notes in the other table, but it's probably not coherent enough to use.
            if (row_n==0) 
              puts "      It's the header row."
              # Check it's what we expect to see.
              k=0
              column_names=[]
              row.cells.each {
                |cellx|
                column_name=cellx.text.downcase.gsub(/[^a-z\s]/,'').gsub(/\s+/,'_')
                puts "        Storing column_name(#{column_name}) index(#{k})"
                column_index[column_name]=k
                column_names.push(column_name)

                # Check for any extra column names we weren't expecting????

                k += 1
              }
              
              if (! column_index.has_key?('discount'))
                puts "        No 'Discount' column.  Adding it to the csv header anyway."
                # Just before the 'amount_not_covered' field.
                column_names[column_index['amount_not_covered'],0]='discount'
              end

              # Split the service_date_type into two different columns.
              # (Make sure it's done after the 'discount' field jiggery.
              column_names[0,1]=['service_date', 'service_type']
              

              file.puts(column_names.join(csv_separator)+"\n")

            elsif (row.cells[0].text != 'TOTALS')
              puts "      It's a data row."
              claim_detail_count += 1
              cells=row.cells

              # Can be all sorts of crap in service_date_type
              #   0000000   0   8   /   2   3   /   2   0   1   2   ,     342 200 242    (<-----------)
              #   0000020   L   A   B   O   R   A   T   O   R   Y   ,       $   9   3   .
              service_date_type      = cells[column_index['service_date_type']].text.gsub(/[\s\n\342\200\242]+/, ' ')
              amount_billed          = dollars2cents(cells[column_index['amount_billed']].text)
              discount=''
              if (column_index.has_key?('discount'))
                discount             = dollars2cents(cells[column_index['discount']].text)
              else
                discount             = 0
              end
              amount_not_covered     = dollars2cents(cells[column_index['amount_not_covered']].text)
              covered_amount         = dollars2cents(cells[column_index['covered_amount']].text)
              copay_deductible       = dollars2cents(cells[column_index['copay_deductible']].text)
              what_your_plan_paid_pc = cells[column_index['what_your_plan_paid']].text.gsub(/\s+=\s+.+$/,'')
              what_your_plan_paid    = dollars2cents(cells[column_index['what_your_plan_paid']].text.gsub(/^[\d\.]+%\s+=\s+/,''))
              coinsurance            = dollars2cents(cells[column_index['coinsurance']].text)
              what_i_owe             = dollars2cents(cells[column_index['what_i_owe']].text)
              see_notes              = cells[column_index['see_notes']].text

              # what_your_plan_paid looks something like this: "0% = $0.00"
              # Just going to store the dollars, ditch the percentage.

              puts "        Splitting service_date_type ('#{service_date_type}')."
              #if (service_date_type =~ /^([\d\/]+)\s+(\S.*)$/)
              # Have to Also remove some dodgy, non-printable crap: 
              if (service_date_type =~ /^([\d\/]+)[\s]+(\S.*)$/)
                #????? Check that these get allocated.
                #
                service_date = Regexp.last_match[1]
                service_type = Regexp.last_match[2]

                if (service_date =~ /^(\d\d)\/(\d\d)\/(\d\d\d\d)$/) # Rely on them keeping this rigid format.
                  mm   = Regexp.last_match[1]
                  dd   = Regexp.last_match[2]
                  yyyy = Regexp.last_match[3]
                  service_date=yyyy+mm+dd
                else
                  STDERR.puts "Unknown date format: '#{service_date}'."
                  exit
                end

                puts "          service_date='#{service_date}'"
                puts "          service_type='#{service_type}'"
              end

              fields=[
                      service_date,
                      service_type,
                      amount_billed,
                      discount,  # We write it even if the column wasn't present.
                      amount_not_covered,
                      covered_amount,
                      copay_deductible,
                      what_your_plan_paid_pc,
                      what_your_plan_paid,
                      coinsurance,
                      what_i_owe,
                      see_notes
                     ].map{|x| x.gsub(/\t/, ' ') }   # Strip any tabs (it's out separator)
              joined_line=fields.map{|x| x.gsub(/\t/, ' ') }.join(csv_separator)

              puts "        Line: '#{joined_line}'"
              #
              file.puts(joined_line+"\n")
              claim_detail_line_items_save_count += 1

              # Let's also write it to the database here.  (If it's not already there.)

              if (true)
                puts "        Processing entry for 'claim_details' table."
                # If we don't have it in the database, throw it in.
                #
                if (! claim_details_select_sth)
                  claim_details_select_sth = dbh.prepare("SELECT * FROM claim_details WHERE 
                                        claim_id=?
                                    AND service_date=?
                                    AND service_type=?
                                    AND amount_billed=?
                                    AND discount=?
                                    AND amount_not_covered=?
                                    AND covered_amount=?
                                    AND copay_deductible=?
                                    AND what_your_plan_paid_pc=?
                                    AND what_your_plan_paid=?
                                    AND coinsurance=?
                                    AND what_i_owe=?
                                    AND see_notes =?                       
                                   ")
                end
                claim_details_select_sth.execute(
                                                 claim_id, service_date, service_type, 
                                                 amount_billed, discount, amount_not_covered, covered_amount,
                                                 copay_deductible, what_your_plan_paid_pc, what_your_plan_paid, coinsurance, what_i_owe,
                                                 see_notes
                                                 )
                # ??? Should perhaps check for errors here.
                row_count=0
                while db_row = claim_details_select_sth.fetch do
                  puts "          DBI: "+db_row.join(", ")+"\n"
                  row_count+=1
                end
                puts "          Rows returned (claim_details, for claim_id=#{claim_id})=#{row_count}"
                #
                if (row_count==0)
                  if (! claim_details_insert_sth)
                    claim_details_insert_sth = dbh.prepare("INSERT INTO claim_details (
                                           claim_id, service_date, service_type, 
                                           amount_billed, discount, amount_not_covered, covered_amount,
                                           copay_deductible, what_your_plan_paid_pc, what_your_plan_paid, coinsurance, what_i_owe,
                                           see_notes
                                           )
                  VALUES
                    (?,?,?,?,?,?,?,?,?,?,?,?,?) ")
                  end
                  puts "      Inserting row (claim_details, for claim_id=#{claim_id})"
                  claim_details_insert_sth.execute(
                                                   claim_id, service_date, service_type, 
                                                   amount_billed, discount, amount_not_covered, covered_amount,
                                                   copay_deductible, what_your_plan_paid_pc, what_your_plan_paid, coinsurance, what_i_owe,
                                                   see_notes
                                                   )
                  claim_detail_db_save_count += 1
                else
                puts "          No need to insert this data into database (already exists)"
                end
              end



            elsif
              puts "      It's the 'totals' row.  We just ignore it."
              # We just ignore it.
            end
          end
          row.cells.each_with_index {
            |cell, cell_n|
            
            puts "      This is a cell (#{cell_n}): '"+cell.text.to_s.gsub(/\n/, ' ')+"'"
          }

        }
      }

    }
    claim_detail_csv_save_count += 1
    new_filenames.push(File.join(destdir, claim_csv_filename))
    total_new_files += 1

  }

  if (claims_select_sth) # If the pdf and csv files already exist, we assume DB has entries, so no selects done.
    claims_select_sth.finish
  end
  if (claims_insert_sth) # If nothing got inserted, this never got defined.
    claims_insert_sth.finish
  end
  if (claim_details_select_sth) # If the pdf and csv files already exist, we assume DB has entries, so no selects done.
    claim_details_select_sth.finish
  end
  if (claim_details_insert_sth) # If nothing got inserted, this never got defined.
    claim_details_insert_sth.finish
  end

end
# End of grabbing the the html info for the claims.




# Grab the prescriptions info.
#
if (download_prescriptions==1)
  # They splash some stupid javascript bumf at login so we manually go here.
  puts 'Going to prescriptions page.'
  browser.goto 'https://my.cigna.com/web/secure/my/claims?WT.ac=mycigna_12820|claims'
  sleep(1)

  # Then click on.
  puts 'Selecting prescription link.'
  browser.link(:text, /Prescription/i).click
  sleep(1)

  # Bizarrely, there's another link to jump through.
  puts 'Selecting the (other) prescription link.'
  # Hmmm, seems it might be either 'Prescription Claims' or 'View Prescription Claims'
  #browser.link(:text, /^Prescription Claims$/).click
  browser.link(:text, /Prescription Claims$/).click
  sleep(1)


  # ??? There might be a table per patient, or perhaps they just have columns within a single table.
  # I can't test for this as I only have a single-patient account to look at.
  # For now, just proceed optimistically.


  # The list of prescriptions seems to default to the last 30 days.  We select
  # 'Last 365 Days' instead.
  browser.input(:id, 'pharmacyDateRange_display').click
  browser.link(:text, 'Last 365 Days').click
  browser.button(:text, 'Find Pharmacy Claims').click


  prescriptions_select_sth=nil
  prescriptions_insert_sth=nil

  sleep(3)  # See if this fixes the weirdness.
  # The weirdness is that the next couple of blocks don't seem to work
  # reliably, but if they're not there, then the 3rd block won't work either.

  # This doesn't find the prescription table.
  # table id='medicalclaimtable'
  if (false)
    puts "medicalclaimtable"
    browser.table(:id, 'medicalclaimtable').rows.each_with_index {
      |row, i|

      puts "    This is a row (#{i})."

      row.cells.each_with_index {
        |cell, j|

        puts "      This is a cell (#{j}): '"+cell.text.gsub(/\n/, ' ')+"'"
      }
    }
    puts "medicalclaimtable (end)"
  end

  # None of these find the prescription table either.
  if (false) 
    puts 'Looking for tables (prescriptions).'

    #mydiv=browser.div(:id, "pharmacyFormContainer")
    mydiv=browser.div(:class, "claim-summary")
    #mydiv=browser.div(:id, "pres")
    #mydiv=browser

    mydiv.tables.each_with_index {
      |table, table_n|

      puts "  This is a table (#{table_n})."

      table.rows.each_with_index {
        |row, i|

        puts "    This is a row (#{i})."

        row.cells.each_with_index {
          |cell, j|

          #puts "      This is a cell (#{j}): '"+cell.text.gsub(/\n/, ' ')+"'"
          puts "      This is a cell (#{j}): '"+cell.text+"'"

        }

      }
    }
    puts 'Done looking for tables (prescriptions).'
  end


  # Bizarrely, this manages to find the prescriptions table.  God know why.
  #
  puts 'Going through all tables (prescriptions).'
  browser.tables.each_with_index {
    |table, table_n|

    puts "  This is a table (#{table_n})."

    if (table_n==0) 
      ##puts 'Table head: '+table.thead.text
      #puts "    Skipping the first table.  Data is in the 2nd one."
      #next
    end
    if (table_n > 1) 
      #puts "    Skipping tables past 2nd one."
      ## In theory could pull the notes key, but it's not a very usable format.
      #next
    end
    if (table_n != 4) 
      #puts 'Table head: '+table.thead.text
      puts "    Skipping all but table 4."
      next
    end

    puts "    This is the prescription table (we hope)."
    puts "      table id='#{table.id}'"
    puts "      table class='#{table.class}'"
    
    #if (table.caption.exists?)
    #  puts 'Caption: '+table.caption.text.to_s
    #else
    #  # The table we're interested in has a caption.  The others not so much.
    #  #next
    #end

    table.rows.each_with_index {
      |row, i|

      #if (row.cells[0].text == '') 
      #  next
      #end

      # Temp to speed things up.
      #if (i > 3) 
      #  #next
      #end

      puts "    This is a row(#{i}) (prescriptions)."

      row.cells.each_with_index {
        |cell, j|

        puts "      This is a cell(#{j}). '"+cell.text.gsub(/\n/, ' ')+"'"

      }

      if (i==0)
        puts "    This (preceding row) is the row with the table headings."
      elsif (row.cells[0].text =='TOTALS')
        puts "    This (preceding row) is a totals row, presumably the last in the table."
      elsif (row.cells[0].text =~ /(\d+)\/(\d+)\/(\d+)/)
        mm   = Regexp.last_match[1].to_i
        dd   = Regexp.last_match[2].to_i
        yyyy = Regexp.last_match[3].to_i

        prescription_total += 1

        date_key = "%04d%02d%02d" % [ yyyy,mm,dd ]
        puts "      Reckon the date is #{date_key}"    

        # NOTE!  The rx number is not unique as it's also used for subsequent refills!
        #   fill_date.rx_number combined should be unique.
        fill_date     = row.cells[0].text
        rx_number     = row.cells[1].text
        drug_name     = row.cells[2].text.gsub(/\n/, ' ')  # Needed
        pharmacy_name = row.cells[3].text.gsub(/\n/, ' ')  # In case it's needed.
        prescriber    = row.cells[4].text.gsub(/\n/, ' ')  # In case it's needed.
        provided_for  = row.cells[5].text.gsub(/\n/, ' ')  # In case it's needed.
        customer_cost = dollars2cents(row.cells[6].text)

        # These used to be supplied in previous versions of the web page.
        total_cost=nil
        plan_cost=nil
        # Although we do now have the extra 'provided_for' field.  (eg 'FRED')
        #    ALTER TABLE prescriptions ADD provided_for VARCHAR(40) AFTER prescriber;

        fill_date = date_key

        joined=[fill_date, rx_number, drug_name, pharmacy_name, prescriber, provided_for, total_cost, plan_cost, customer_cost].join(", ")

        puts "    "+joined

        if (! prescriptions_select_sth)
          prescriptions_select_sth = dbh.prepare("SELECT * FROM prescriptions WHERE fill_date=? AND rx_number=?")
        end
        prescriptions_select_sth.execute(fill_date, rx_number)
        # ??? Should perhaps check for errors here.
        row_count=0
        while db_row = prescriptions_select_sth.fetch do
          puts "    DBI: "+db_row.join(", ")+"\n"
          row_count+=1
        end
        puts "    Rows returned (prescriptions)=#{row_count}"
        #
        if (row_count==0)
          if (! prescriptions_insert_sth)
            prescriptions_insert_sth = dbh.prepare("INSERT INTO prescriptions (
                    fill_date, rx_number, drug_name, pharmacy_name, prescriber,
                    total_cost, plan_cost, customer_cost)
                  VALUES
                    (?,?,?,?,?,?,?,?) ")
          end
          puts "      Inserting row (prescriptions, for fill_date=#{fill_date}, rx_number=#{rx_number})"
          prescriptions_insert_sth.execute(fill_date, rx_number, drug_name, pharmacy_name, prescriber, total_cost, plan_cost, customer_cost)
          # ??? Should perhaps check for errors here.
          prescription_db_save_count += 1
        end


        
      else
        puts "    Not sure what to make of this row (prescriptions).  Ignoring it."
      end

    }
  }
  if (prescriptions_insert_sth) # If nothing got inserted, this never got defined.
    prescriptions_insert_sth.finish
  end
end
# End of grabbing the Prescription details (if we're grabbing them).


puts ""
puts "Entering section for confirming/renaming downloaded PDFs."
renamed_files=0
if (downloaded_pdf_files==0) 
  puts 'No new pdf files to (confirm) download (and rename).'

  # ???? Some sanity checks, based on actual date, vs listed html
  # files, vs previously download files.

else
  puts 'Files downloaded: '+downloaded_pdf_files.to_s
  puts 'Going to downloads page to confirm saving files if needed:'

  browser.goto 'chrome://downloads/'
  sleep(2) # To make sure the document has settled down a bit before we ask for the new links.

  # Needed?  Yes.  The PDF files don't save themselves.
  if (true) 
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
    
    puts '  download links: '+l.text+' ='+l.href.to_s


    if ( (link2filename_map[l.href.to_s]) && (renamed_links[l.href.to_s] != 1) )

      oldfilename=File.join(tempdir, previous_link_text)
      newfilename=File.join(destdir, link2filename_map[l.href.to_s])

      puts "  We've got a match for this link.(#{newfilename})"
      puts '    download statement pdf links: '+l.text

      puts "    File.rename('#{oldfilename}', '#{newfilename}')"
      File.rename(oldfilename, newfilename)
      
      renamed_links[l.href.to_s]=1
      renamed_files += 1
      eob_pdf_save_count += 1
      total_new_files += 1
      new_filenames.push(newfilename)

    end
    previous_link_text=l.text   # Dodgy way of figuring out the filename.

  }
end


puts "Done downloading and renaming."
puts "  downloaded_pdf_files=#{downloaded_pdf_files.to_s}"
puts "  renamed_files=#{renamed_files.to_s}"
#
if (downloaded_pdf_files != renamed_files)
  STDERR.puts "ERROR: downloaded_pdf_files count(#{downloaded_pdf_files}) not equal renamed_files count (#{renamed_files})."
  exit
end


summary += "PDF EOBs downloaded:  #{eob_pdf_save_count}/#{eob_count}\n"
summary += "HTML claim detail (summary) pages downloaded: #{claim_detail_html_save_count}/#{claim_count}\n"
summary += "CSV claim detail (summary) files downloaded:  #{claim_detail_csv_save_count}/#{claim_count}\n"
summary += "CSV claim detail line-items saved:            #{claim_detail_line_items_save_count}/#{claim_detail_count}\n"
summary += "Claim detail (summary) saved to database:     #{claim_summary_db_save_count}/#{claim_count}\n"
summary += "Claim details saved to database:              #{claim_detail_db_save_count}/#{claim_detail_count}\n"
summary += "Prescriptions saved to database:              #{prescription_db_save_count}/#{prescription_total}\n"

#??????? This is optimistic/delusional.  Intend to add some sanity checks later.
summary += "Errors:                                       0\n"

summary += "Total number of new files downloaded:         #{total_new_files}\n"
summary += "(Claim details only examined if a new claim is found)\n"

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


if (dbh)
  puts "Disconnecting from database."
  dbh.disconnect
end


pause_secs=5

puts progname+' logging off in '+pause_secs.to_s+' seconds...'
sleep(pause_secs)  # To make sure things have settled down.
# Logout page
browser.goto('https://my.cigna.com/web/public/logout')


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





