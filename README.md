# crude-GDDynDNS
Powershell script to dynamically update GoDaddy DNS.

This is a very crude way to update GoDaddy DNS, with changes to GoDaddy site it is likely this script will no longer function. This was created on a win7 box with PS version 3.8.0.129, and has not been tested elsewhere.

That being said it works...

Instructions:

  1. Create a work directory (currently root of c:)
  2. Create a subfolder named updated
  3. Create a file in the work directory with the name of the IP you will be monitoring, make sure it is wrapped with ~'s. example: ~1.1.1.2~
  4. Update the username and password within the script with GoDaddy info
  5. Schedule to run at an interval of your choice
