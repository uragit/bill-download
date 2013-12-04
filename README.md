bill-download
=============

A collection of scripts for automatic download of bills (etc.) from the web.

This project is still under development and any programs are to be regarded as beta, or even alpha, level.  Having said that, everything here worked somewhat reliably in at least one environment at one time.   I plan to add programs as I develop them for automatic downloading of my own account statements from the web.   If you deal with any of the same set of companies then perhaps you'll find the programs useful.   If you try them but they don't quite work for you, let me know and perhaps I can help.

General notes:

  The software was developed on a linux system so it more likely to work for you if you have a similar environment.

Websites for which this project has working programs for downloading bills:

comcast.com: (Cable ISP in SF Bay)
------------

comcast_watir.rb
comcast.conf

Make sure you have ruby, with the watir (`http://watir.com`) drivers.  A working chrome 
brower setup is needed.  Edit comcast.conf with your credentials and location of download 
directory.  Run comcast_watir.rb and have at it.


