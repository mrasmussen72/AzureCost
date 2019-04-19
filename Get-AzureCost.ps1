#region Comments
#########################################################################
# Get cost of Azure object
#
#endregion 


####GlobalVariables#######################################################
[hashtable]$global:Allresources = @{}   # used so we only call get resources in Azure once, save list globally for use later
[bool]$global:FirstRun = $true          # Leave default, if the global list hasn't been populated, populate it once

#region Functions - Add your own functions here.  Leave AzureLogin as-is
####Functions#############################################################
function AzureLogin
{
    [cmdletbinding()]
    Param
    (
        [Parameter(Mandatory=$false)]
        [bool] $RunPasswordPrompt = $false,
        [Parameter(Mandatory=$false)]
        [string] $SecurePasswordLocation,
        [Parameter(Mandatory=$false)]
        [string] $LoginName,
        [Parameter(Mandatory=$false)]
        [bool] $AzureForGov = $false,
        [Parameter(Mandatory=$false)]
        [bool] $ConnectToAzureAd = $false
    )

    try 
    {
        $success = $false
        
        if(!($SecurePasswordLocation -match '(\w)[.](\w)') )
        {
            write-host "Encrypted password file ends in a directory, this needs to end in a filename.  Exiting..."
            return false # could make success false
        }
        if($RunPasswordPrompt)
        {
            #if fails return false
            Read-Host -Prompt "Enter your password for $($LoginName)" -assecurestring | convertfrom-securestring | out-file $SecurePasswordLocation
        }
        else 
        {
            #no prompt, does the password file exist
            if(!(Test-Path $SecurePasswordLocation))
            {
                write-host "There isn't a password file in the location you specified $($SecurePasswordLocation)."
                Read-host "Password file not found, Enter your password" -assecurestring | convertfrom-securestring | out-file $SecurePasswordLocation
                #return false if fail 
                if(!(Test-Path -Path $SecurePasswordLocation)){return Write-Host "Path doesn't exist: $($SecurePasswordLocation)"; $false}
            } 
        }
        try 
        {
            $password = Get-Content $SecurePasswordLocation | ConvertTo-SecureString
            $cred = new-object -typename System.Management.Automation.PSCredential -argumentlist $LoginName, $password 
            $success = $true
        }
        catch {$success = $false}
        try 
        {
            if($success)
            {
                #connect AD or Az
                if($ConnectToAzureAd)
                {
                    if($AzureForGov){Connect-AzureAD -Credential $cred -EnvironmentName AzureUSGovernment | Out-Null}
                    else{Connect-AzureAD -Credential $cred | Out-Null}
                    $context = Get-AzureADUser -Top 1
                    if($context){$success = $true}   
                    else{$success = $false}
                }
                else 
                {
                    if($AzureForGov){Connect-AzAccount -Credential $cred -EnvironmentName AzureUSGovernment | Out-Null}
                    else{Connect-AzAccount -Credential $cred | Out-Null}
                    $context = Get-AzContext
                    if($context.Subscription.Name){$success = $true}
                    else{$success = $false}
                }
                if(!($success))
                {
                  # error logging into account or user doesn't have subscription rights, exit
                  $success = $false
                  throw "Failed to login, exiting..."
                  #exit
                }   
            }
        }
        catch{$success = $false} 
    }
    catch {$success = $false}
    return $success
}

Function GetAzureIDValue
{
    [cmdletbinding()]
    Param (
    [string]$Name,
    [string]$IDPayload
    )
    $returnValue = ""
    $IDPayloadJSON = ""
    try 
    {
        if(($Name -and $IDPayload) -or ($IDPayload.ToLower() -eq "null"))
        {
            if($IDPayload -match '[{}]' )
            {
                $IDPayloadJSON = ConvertFrom-Json -InputObject $IDPayload
                $fullText = $IDPayloadJSON[0]
                $returnValue = GetAzureIDValue -IDPayload $fullText.ID -Name $Name
                return $returnValue
            }
            $nameValCollection = $IDPayload.Split('/')
            # could add a $test + 1 to get the next value of the array, which would be what we want.  No need to loop
            #$test = $nameValCollection.IndexOf($Name)
            $i = 0
            for($x=0;$x -le $nameValCollection.Count;$x++)
            {
                try
                {
                    if($nameValCollection[$x].ToLower().Equals($Name.ToLower()))
                    {
                        $returnValue = $nameValCollection[$x+1]
                        break
                    }
                }
                catch 
                {
                    #something went wrong
                    $temp = $_.Exception.Message
                }
            }
        }
    }
    catch 
    {
        $temp = $_.Exception.Message
    }
    return $returnValue
}
function Get-AllResources
{
    [cmdletbinding()]
    param(
    [dateTime] $startDate,
    [dateTime] $endDate,
    [string] $resourceGroupsName
    )

    $retVal
    try
    {

        if($resourceGroupsName)
        {
            $retVal = (Get-AzConsumptionUsageDetail -StartDate $startDate -EndDate $endDate -ResourceGroup $resourceGroupsName -IncludeMeterDetails $true - )
            #Get-AzConsumptionUsageDetail -
        }
        else 
        {
            #$retVal = (Get-AzConsumptionUsageDetail -StartDate $startDate -EndDate $endDate)
            $retVal = Get-AzConsumptionUsageDetail -Expand "MeterDetails" -StartDate $startDate -EndDate $endDate
        }
    }
    catch
    {
        $temp = $_.Exception.Message

    }
    return $retVal
}
function GetCostByDays
{
    [cmdletbinding()]
    param(
    [int] $NumberOfDaysBack,
    [string] $ResourceGroupName,
    [bool] $UseAllResourceGroups
    )
    #$objectList = New-Object System.Collections.ArrayList
    #$resourceGroupList = New-Object System.Collections.ArrayList
    $NumberOfDaysBack = $NumberOfDaysBack * -1
    $startDate = [datetime]::Today.AddDays($NumberOfDaysBack).ToString('MM/dd/yyy')
    $endDate = [datetime]::Today.ToString('MM/dd/yyy')
    $totalCost = 0.0

    #first run get all resources in question, susequent run loop through the full list and get values
    if($global:FirstRun)
    {
        #populate global list - might be too many in some environments, have to test
        $global:FirstRun = $false
        $resources = Get-AllResources -StartDate $startDate -EndDate $endDate

        foreach($resource in $resources)
        {
            try 
            {
                if($resource)
                {
                    if(!($global:Allresources.Contains($resource.Id)))
                    {
                        $global:Allresources.Add($resource.Id,$resource)
                        #potentially do the work below in this loop
                    }

                }
            }
            catch 
            {
                $temp = $_.Exception.Message
                continue
            }
        }   
    }

    if($UseAllResourceGroups)
    {
        #check the list is populated
        # add up all costs and give total
        foreach($key in $global:Allresources.Keys)
        {
            $item = $global:Allresources[$key]
            $totalCost = $totalCost + $item.PretaxCost
        }
    }
    else 
    {
        # get only a particular resource group's total 
        foreach($key in $global:Allresources.Keys)
        {
            $item = $global:Allresources[$key]
            $localResourceGroupName = GetAzureIDValue -Name "resourceGroups" -IDPayload $item.InstanceId
            if($localResourceGroupName.Equals($ResourceGroupName))
            {
                $totalCost = $totalCost + $item.PretaxCost
            }

            #$name = $global:Allresources[$key]
            #$totalCost = $totalCost + $item.PretaxCost
        }  
    }
    return $totalCost
}

#endregion

####Begin Code - enter your code in the if statement below####
#Variables - Add your values for the variables here, you can't leave the values blank
[string]    $LoginName =                   ""           #Azure username, something@something.onmicrosoft.com 
[string]    $SecurePasswordLocation =      ""           #Path and filename for the secure password file c:\Whatever\securePassword.txt
[string]    $LogFileNameAndPath =          ""           #If $enabledLogFile is true, the script will write to a log file in this path.  Include FileName, example c:\whatever\file.log
[bool]      $RunPasswordPrompt =           $false        #Uses Read-Host to prompt the user at the command prompt to enter password.  this will create the text file in $SecurePasswordLocation.
[bool]      $AzureForGovernment =          $false       #set to $true if running cmdlets against Microsoft azure for government
[bool]      $EnableLogFile =               $false       #If enabled a log file will be written to $LogFileNameAndPath.
[bool]      $ConnectToAzureAd =            $false       #This will connect using Connect-AzureAd instead of Connect-AzAccount
[bool]      $GetCostAllResources =         $true   #Gets the cost of ALL objects in ALL resource groups
[int]       $numOfDays =                   30      # How far to calculate cost.  Value here is number of days in the past
[decimal]   $total =                       0.0     # Used to calculate total cost, should leave default
try 
{
    
    $success = $success = AzureLogin -RunPasswordPrompt $RunPasswordPrompt -SecurePasswordLocation $SecurePasswordLocation -LoginName $LoginName -AzureForGov $AzureForGovernment -ConnectToAzureAd $ConnectToAzureAd
    if($success)
    {
        if($EnableLogFile){Write-Logging -Message "Login Succeeded" -LogFileNameAndPath $LogFileNameAndPath | Out-Null}
        #Login Successful
        Write-Host "Login Succeeded"
 
        if($ConnectToAzureAd)
        {
            #run commands from AzureAd for example Get-AzureAdUser###########################
        }
        else 
        {
            #run commands against Azure, such as Get-AzVm####################################
            "Starting calculations..."
            $resourceGroups = Get-AzResourceGroup
            "Cost calcualted from $($numOfDays) day(s) ago to today  `r`n"
            foreach($resourceGroup in $resourceGroups)
            {
                $total = $total + (GetCostByDays $numOfDays -UseAllResourceGroups $false -ResourceGroupName $resourceGroup.ResourceGroupName)
                $resourceGroup.ResourceGroupName + " = `t" + "{0:C}" -f $total
                $total = 0.0
            }

            if($GetCostAllResources)
            {
                $AllGroupsCost = GetCostByDays -NumberOfDaysBack 23 -UseAllResourceGroups $true
                "Cost of all resource groups: " + "{0:C}" -f $AllGroupsCost + "`r`n"
            }

            #End Azure cmdlets #######################################################
        }
    }
    else 
    {
        #Login Failed 
        Write-Host "Login Failed or No Access"
        if($EnableLogFile){Write-Logging -Message "Login Failed or No Access" -LogFileNameAndPath $LogFileNameAndPath | Out-Null}
    }
}
catch 
{
    #Login Failed with Error
    $_.Exception.Message
}