bill-download
=============

A collection of scripts for automatic download of bills (etc.) from the web.

This project is still under development and any programs are to be regarded as beta, or even alpha, level.  Having said that, everything here worked somewhat reliably in at least one environment at one time.   I plan to add programs as I develop them for automatic downloading of my own account statements from the web.   If you deal with any of the same set of companies then perhaps you'll find the programs useful.   If you try them but they don't quite work for you, let me know and perhaps I can help.

General notes:

  The software was developed on a linux system so it more likely to
  work for you if you have a similar environment.

  Yes, the scripts have a lot of common code.  Perhaps I'll create a
  suitable library for simplicity when I've really figured out all
  that it will need to do.

  The ruby/watir scripts are written to work with chrome.  Chrome
  seems to work better with watir than firefox for controlling how the
  browser downloads file, but there's still a bunch of hoops to jump
  through when trying to track and rename any downloaded files.  If
  anybody has a better way to control how downloaded files are saved
  locally, please let me know!

  If you're doing any problem investigation, debugging or development
  you'll want to have the `firebug` extension for the browser.  It
  allows easy inspection of the html elements to figure out what might
  be going wrong.



Websites for which this project has working programs for downloading bills:


pge.com: (Pacific Gas and Electric, Norther California Utility Company)
------------

pge_watir.rb

pge.conf

Make sure you have ruby, with the watir (`http://watir.com`) drivers.  A working chrome 
brower setup is needed.  Edit pge.conf with your credentials and location of download 
directory.  Run pge_watir.rb and have at it.



comcast.com: (Cable ISP in SF Bay)
------------

comcast_watir.rb

comcast.conf

Make sure you have ruby, with the watir (`http://watir.com`) drivers.  A working chrome 
brower setup is needed.  Edit comcast.conf with your credentials and location of download 
directory.  Run comcast_watir.rb and have at it.



callcentric.com: (USA VOIP provider)
---------------

callcentric_watir.rb

callcentric.conf

Make sure you have ruby, with the watir (`http://watir.com`) drivers.  A working chrome 
brower setup is needed.  Edit callcentric.conf with your credentials and location of download 
directory.  Run callcentric_watir.rb and have at it.



att.com (AT&T USA telco)
-------

att_phone_watir.rb

att.conf

This script can download bill PDFs, bill html files , and usage
records from att.com.

Make sure you have ruby, with the watir (`http://watir.com`) drivers.
A working chrome brower setup is needed.  Edit callcentric.conf with
your credentials and location of download directory.  Run
callcentric_watir.rb and have at it.

This script works for my landline phone and my separate mobile
account.  It's possible that, even if you have an AT&T account, that
your account may be kept on a different billing/web system and so this
script may not work for you.  If you've got AT&T's Uverse service,
it's even less likely to be successful.

