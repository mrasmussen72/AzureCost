# AzureCost
Cost of objects in resource groups

Run the script with the following parameters

$LoginName =                   ""      #Azure username, something@something.onmicrosoft.com 
$SecurePasswordLocation =      ""      #Path and filename for the secure password file c:\Whatever\securePassword.txt
$RunPasswordPrompt =           $true   #Uses Read-Host to prompt the user at the command prompt to enter password.  this will create the  text file in $SecurePasswordLocation.
$GetCostAllResources =         $true   #Gets the cost of ALL objects in ALL resource groups
$numOfDays =                   1      # How far to calculate cost.  Value here is number of days in the past
$total =                       0.0     # Used to calculate total cost, should leave default

Change the above values in the script and run.  This section is located toward the bottom (under the functions) in the script.

$SecurePasswordLocation.  this is looking for a filename, not just a path.  If the file doesn't exist, you will be prompted to 
enter your password.  if the path doesn't lead to a file, this might cause an error

$RunPasswordPrompt - this switch will prompt you for a password and write it to disk regardless of what is already on disk
$GetCostOfAllResources will list the cost of ALL of your resources
$numOfDays - the number od days in the past to calculate from
$total - internal variables used to hold the running total
