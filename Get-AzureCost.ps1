#region Comments
#########################################################################
# Get cost of Azure object
#
#endregion 


####GlobalVariables#######################################################
[hashtable]$global:Allresources = @{}   # used so we only call get resources in Azure once, save list globally for use later
[bool]$global:FirstRun = $true          # Leave default, if the global list hasn't been populated, populate it once

#region Functions - Add your own functions here.  Leave Login-Azure as-is
####Functions#############################################################
function AzureLogin
{
    [cmdletbinding()]
    Param
    (
        [Parameter(Mandatory=$false)]
        [bool]
        $RunPasswordPrompt = $false,
        [Parameter(Mandatory=$false)]
        [string]
        $SecurePasswordLocation,
        [Parameter(Mandatory=$false)]
        [string]
        $LoginName
    )

    $success = $false
    if($RunPasswordPrompt)
    {
        #don't need to test for the password file, the file will be created if prompted
        Read-host "Enter your password (Username:$($LoginName))" -assecurestring | convertfrom-securestring | out-file $SecurePasswordLocation
    }
    else 
    {
        if(!(Test-Path -Path $SecurePasswordLocation))
        {
            $enterPassword = Read-Host -Prompt "There isn't a password file in the location you specified ($SecurePasswordLocation).  Do you want to enter a password now? (Enter Yes to enter a password)"
            if($enterPassword.ToLower().Equals("yes"))
            {
                Read-host "Enter your password" -assecurestring | convertfrom-securestring | out-file $SecurePasswordLocation
            }
            else 
            {
                #answered something other than yes to prompt, no password file, exit
                $success = $false
    
            }
        } 
    }
    $password = Get-Content $SecurePasswordLocation | ConvertTo-SecureString
    $cred = new-object -typename System.Management.Automation.PSCredential -argumentlist $LoginName, $password
    
    try 
    {
        #$subscription = Connect-AzureRmAccount -Credential $cred 
        $subscription = Connect-AzAccount -Credential $cred
        if(!($subscription))
        {
            # error logging into account, exit
            #Write-Host "Could not log into account, exiting"
            $success = $false
            throw "Failed to login, exiting..."
            #exit
        }
        else 
        {
            $success = $true      
        }
    }
    catch 
    {
        #Write-Host "Could not log into account, exiting"
        $success = $false
        #throw "Failed to login, exiting..."
        #exit   
    }
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
    if(($Name -and $IDPayload) -or ($IDPayload.ToLower() -eq "null"))
    {
        if($IDPayload -match '[{}]' )
        {
            $IDPayloadJSON = ConvertFrom-Json -InputObject $IDPayload
            $fullText = $IDPayloadJSON[0]
            $returnValue = Get-AzureIDValue -IDPayload $fullText.ID -Name $Name
            return $returnValue
        }
        $nameValCollection = $IDPayload.Split('/')
        # could add a $test + 1 to get the next value of the array, which would be what we want.  No need to loop
        #$test = $nameValCollection.IndexOf($Name)
        for($x=0;$x -le $nameValCollection.Count;$x++)
        {
            try
            {
                if($nameValCollection[$x].Equals($Name))
                {
                    $returnValue = $nameValCollection[$x+1]
                    break
                }
            }
            catch 
            {
                #something went wrong
            }
        }
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
    if($resourceGroupsName)
    {
        $retVal = (Get-AzConsumptionUsageDetail -StartDate $startDate -EndDate $endDate -ResourceGroup $resourceGroupsName)
    }
    else 
    {
        $retVal = (Get-AzConsumptionUsageDetail -StartDate $startDate -EndDate $endDate)
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
        #populate global list
        $global:FirstRun = $false
        $resources = Get-AllResources -StartDate $startDate -EndDate $endDate
            
        foreach($resource in $resources)
        {
            if($resource)
            {
                $global:Allresources.Add($resource.Id,$resource)
                #potentially do the work below in this loop
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

####Begin Code - enter your code in the if statement below
#Variables - Add your values for the variables here, you can't leave the values blank
[string]    $LoginName =                   ""      #Azure username, something@something.onmicrosoft.com 
[string]    $SecurePasswordLocation =      ""      #Path and filename for the secure password file c:\Whatever\securePassword.txt
[bool]      $RunPasswordPrompt =           $true   #Uses Read-Host to prompt the user at the command prompt to enter password.  this will create the text file in $SecurePasswordLocation.
[bool]      $GetCostAllResources =         $true   #Gets the cost of ALL objects in ALL resource groups
[int]       $numOfDays =                   23      # How far to calculate cost.  Value here is number of days in the past
[decimal]   $total =                       0.0     # Used to calculate total cost, should leave default
try 
{
    
    if(AzureLogin -RunPasswordPrompt $RunPasswordPrompt -SecurePasswordLocation $SecurePasswordLocation -LoginName $LoginName)
    {
        #Login Successful
        #Add your Azure cmdlets here ###########################################
        
        $resourceGroups = Get-AzResourceGroup
        foreach($resourceGroup in $resourceGroups)
        {
            $total = $total + (GetCostByDays $numOfDays -UseAllResourceGroups $false -ResourceGroupName $resourceGroup.ResourceGroupName)
            $resourceGroup.ResourceGroupName + " = `t" + "{0:C}" -f $total
            $total = 0.0
        }

        if($GetCostAllResources)
        {
            $AllGroupsCost = GetCostByDays -NumberOfDaysBack 23 -UseAllResourceGroups $true
            "Cost of all resource groups: " + "{0:C}" -f $AllGroupsCost
        }
    }
    else 
    {
        #Login Failed 
        Write-Host "Login failed"
    }
}
catch 
{
    #Login Failed with Error
    $_.Exception.Message
}