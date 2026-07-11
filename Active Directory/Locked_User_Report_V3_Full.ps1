#################################################################################################################
<# 
.SYNOPSIS
The script was created in order to get more details on where lockout was coming from in AD domain environment.

The script below review details on Event Log ID: 4740/4625 in order to generate a csv report of lockout details for single or multiple users.
It generates total lockout and login attempt count.
It also shows badPwdCount, LastBadPasswordAttempt, AccountLockoutTime and locked status.
It uses the Get-Winevent "-FilterXPath" cmdlet to parse events

Event Log 4740 and 4625 are NOT replicated across all Domain controllers so the script parse through all DC for events.
    ** An Event 4625 is written exclusively to the Security log of the specific Domain Controller that handled and rejected the authentication request.
    ** Event ID 4740 is almost always logged on the PDC Emulator, regardless of which DC handled the original bad password entries but thats not always the case.

 <#
.EXAMPLE
    .\Locked_User_Report_V3_Full.ps1 -User jdoe
.EXAMPLE
    .\Locked_User_Report_V3_Full.ps1 -User "sli,kim" -LockOutReport "C:\user\desktop\report.csv" -hours 6
.EXAMPLE
    .\Locked_User_Report_V3_Full.ps1
    (will prompt: "Please submit UPN for user to look up. List single/multiple users. Separate by comma if looking up a batch. (Ex: Jdoe,sli,tjohnson) "


######################################

** Modify report output location or timeframe for event inside the script or when invoking script.
** Default time is within 24 hour timespan from current time.

    [String]$LockOutReport = "C:\Temp\lockout\Locked_User_Report-$RunDate.csv",
    [int]$Hours = 24

######################################
Example Output:
######################################

Do you want to lookup lockout details for a single user? (Y/N): y
Enter the user's UPN (UserPrincipalName) name: sli
Verifying if user exist in AD : sli
Generating lockout report for user: sli
Querying 2 DCs across 1 domain(s) for user [sli].
WARNING: Invoking scriptblock on domain controller: [DC]
WARNING: Invoking scriptblock on domain controller: [DC-2]                                                              
                                                                                                                        
        ------------------
        [Lookup Complete]
        ------------------
        Appending data for user [sli] to the following file located [C:\Temp\lockout\Locked_User_Report-07-10-2026.csv].
                  
"Name","badPwdCount","LastBadPasswordAttempt","AccountLockoutTime","LockedOut","LockOutCount","LoginAttemptCount","CallerComputer","Event_Source","Security_Identifier","FromDate","EndDate"
"Steven li-PERM","0","5/28/2026 11:34:26 AM",,"False","0","0",,"DC-2","S-1-5-21-596721672-634940382-747895073-1104","7/10/2026 3:43:12 PM","7/10/2026 3:43:12 PM"
"Steven li-PERM","0","7/6/2026 11:27:29 AM",,"False","0","0",,"DC","S-1-5-21-596721672-634940382-747895073-1104","7/10/2026 3:43:13 PM","7/10/2026 3:43:13 PM"

######################################

######################################
.Notes
# Invoke-command still outputs [PSComputerName] and [PSShowComputerName] and [RunspaceID] because it returns which computer executed the remote command on.
# --To disable this use "Invoke-command [-hidecomputername] parameter" or "Invoke-command -scriptblock {xxxx}| Select-Object * -exclude RunspaceID, PSComputerName, PSShowComputerName"

# Export-csv shows the correct date under "LastBadPasswordAttempt" and "AccountLockoutTime" but in excel, it shows 24 hour format.
# -- issue with excel showing date. No issue when opened with notepad or google sheet

# Insert additional psobject within existing psobject: "$CSVNames | select-object *, @{Name='Time';Expression={Get-Date}}"

# Dont use SID to filter events like 4625 ("-UserID=<SID>)") - logs shows NULL SID; error shows "Get-WinEvent: No events were found that match the specified selection criteria."
# Best way to filter lockout events is to use "Username" with "-Data" key-value pair. For ex: "Get-WinEvent -FilterHashtable @{Data="Username"}"" 

# Homelab- two DC- DC DOES NOT replicate 4625 or 4740 logs. The source workstation will log 4625. If there is no lockout attempts on DC, it means it recorded on caller Computer
# Windows Login screen does not log 4625, only 4740 locked.

# -FilterHashTable sometimes will leave a user out from its query. Same goes for -FilterXpath. Various DC uses a different Targetusername (UPN or SAM). Some events have NULL SID

# Script DOES NOT detect failed attempts if <Targetusername> is not $SAM or $UPN. User could enter wrong SAM name and will get logged

# Optional - Parse just primary DC with $PDC = (Get-AdDomain).PDCEmulator

# CallerComputer = $Event4740.Properties[1].Value # cause issue with output. Did not output from all DC. Instead, create a variable for "$Event4740.Properties[1].Value"

# Performance varies depending on size of organization. Single user in homelab with two DC takes around 10 seconds
######################################

#>

#######################
# Declare parameter
#######################
[CmdletBinding()]
param(
    [string]$User,

    $RunDate = (Get-Date).ToString("MM-dd-yyyy"),
    [String]$LockOutReport = "C:\Temp\lockout\Locked_User_Report-$RunDate.csv",

    [int]$Hours = 24
)

#######################
# Declare Function
#######################
function GetADModule { 
    
# Check if AD module is loaded -
    $AD_Module = get-module -Name activedirectory

    # If module is not loaded - try import it 
    if(-not $AD_Module){
        
        Write-Output "Attempting to import Active Directory module.......`n"
        import-module activedirectory -Force 

        # Check module post import
        $AD_Module_Check = get-module -Name activedirectory

        # Module path
        $Path = (Get-Module -ListAvailable activedirectory).path
        if(Test-Path -path $Path){  
            Write-Output "Imported active directory module from:`n$path.......`n"
        }
        
        # If importing module fails - install it then import it
        if(-not $AD_Module_Check){
        
        # Install the windows feature
            Write-Output "##### Installing RSAT AD and import AD module #####`n"
            Install-WindowsFeature -Name “RSAT-AD-PowerShell” -IncludeAllSubFeature #For Windows Server

        # Import the module
            Write-Output "`nImporting Active Directory module.......`n"
            import-module activedirectory -Force

        # Check for imported module
            if(get-module -Name activedirectory){

            Write-Warning "`n##### Actived directory module is installed and imported successfully #####`n"
                
        # Module path
            $Path = (Get-Module -ListAvailable activedirectory).path
            Write-Output "`nImported Active Directory module from:`n$path.......`n"                

            }else{

            Write-Warning "`n##### Active Directory module is NOT installed #####`n"

            }
        }
    }
} # End function [GetADModule]

function UserLookup {


#######################
# Import Module
#######################
GetADModule

# ###############################################################
# correctly-scoped forest-wide DC list - verify DC availability
# ###############################################################
$Domains = (Get-ADForest).Domains
$DomainControllers = foreach ($domain in $Domains) {
    Get-ADDomainController -Filter * -Server $domain | Select-Object -ExpandProperty Name
}
$DomainControllers = $DomainControllers | Sort-Object -Unique
Write-Output "Querying $($DomainControllers.Count) DCs across $($Domains.Count) domain(s) for user [$User]."

#####################

# Query information from each DC thats under $DomainController.
$data = foreach($DC in $DomainControllers){

    Invoke-Command -ComputerName $DC -ScriptBlock {

        Write-Warning "Invoking scriptblock on domain controller: [$using:DC]"

        # Variable declare:
        $GetUser = Get-ADUser -Identity $using:user -Properties * | Select-Object Name,badPwdCount,LastBadPasswordAttempt,AccountLockoutTime,LockedOut,SID,SamAccountName,UserPrincipalName
        $SAM = $getuser.SamAccountName
        $UPN = $GetUser.UserPrincipalName

           # Use UserPrincipalName and SAM for event 4625 to return more accurate results as TargetUserName in XML view is different for each DC.
           $Event4625_UPN = Get-WinEvent -LogName security -FilterXPath "Event[System[Provider[@Name='Microsoft-Windows-Security-Auditing'] and EventID=4625 and TimeCreated[timediff(@SystemTime) <= 86400000 ]] and EventData[Data[@Name='TargetUsername']='$($UPN)']]"
           $Event4625_SAM = Get-WinEvent -LogName security -FilterXPath "Event[System[Provider[@Name='Microsoft-Windows-Security-Auditing'] and EventID=4625 and TimeCreated[timediff(@SystemTime) <= 86400000 ]] and EventData[Data[@Name='TargetUsername']='$($SAM)']]"

           # Log lockout attempts with only SAM. Result is consistent across multiple DC
           $Event4740 = Get-WinEvent -LogName security -FilterXPath "Event[System[Provider[@Name='Microsoft-Windows-Security-Auditing'] and EventID=4740 and TimeCreated[timediff(@SystemTime) <= 86400000 ]] and EventData[Data[@Name='TargetUsername']='$($SAM)']]"
           # Create callerComputer variable for 4740 and append it into $info pscustomobject
           $callercomputer = $Event4740.Properties[1].Value


           $info = [PSCustomObject]@{
           Name = $getuser.Name
           badPwdCount = $getuser.badPwdCount
           LastBadPasswordAttempt = $GetUser.LastBadPasswordAttempt
           AccountLockoutTime = $getuser.AccountLockoutTime

           LockedOut = $GetUser.LockedOut
           LockOutCount = $Event4740.Count
           LoginAttemptCount = ($Event4625_UPN.Count) + ($Event4625_SAM.count)
           CallerComputer = $callercomputer

           Event_Source = Get-ADDomainController | Select-Object Name -ExpandProperty Name   
           Security_Identifier= ($GetUser.SID).Value
           FromDate = (Get-date).Addhours(-$Hours)
           EndDate = (Get-Date)
           }
           #Return $info
           $info

            }  -ErrorAction SilentlyContinue | Select-Object * -exclude RunspaceID, PSComputerName, PSShowComputerName

        } # end foreach DC

        # export report to csv with current date and Hour and minute.
        $Data | Export-Csv -Path $LockOutReport -Append -Force -NoTypeInformation

    } # End Function [UserLookup]


############### Start script  ##############

#######################
# Verify user input
######################
# check if parameter is submitted - if its not submitted, prompt for user details.

if ([string]::IsNullOrWhiteSpace($User)) {

$options = $true
while ($options){

    $SingleLookup = Read-Host -Prompt "Do you want to lookup lockout details for a single user? (Y/N)"

    ########################
    # If user selects Y/Yes
    ########################
    if($SingleLookup -match "^(Y|Yes)$") {

        $User = Read-Host -Prompt "Enter the user's UPN (UserPrincipalName) name"

        try {
             # 1. Verify if user is in AD
            Write-Output "Verifying if user exist in AD : $User"
            $GetADuser= Get-ADUser -Identity $User -ErrorAction stop

            #2. If user is in AD - proceed with generating report
            Write-Output "Generating lockout report for user: $User"

            # start lookup
            UserLookup
        
        }
        catch {
            Write-Warning "Could not resolve '$User': $($_.Exception.Message)"
        }

        # Break loop
        Write-Output @"

        ------------------
        [Lookup Complete]
        ------------------
        Appending data for user [$user] to the following file located [$LockOutReport].

"@
        break
    }# End IF single lookup match Y/(Yes)

#IF first option is No - start option for multi user lookup

    ########################
    # If user selects N/No
    ########################
    if($SingleLookup -match "^(N|no)$") {

    ###### Fall back to multi user lookup ######
     $MultiLookup = Read-Host -Prompt "Do you want to lookup lockout details for multiple user? (Y/N)"

        ########################
        # If user selects Y/Yes
        ########################
        if($MultiLookup -match "^(Y|Yes)$") {

        $MultiLookup = Read-Host -Prompt "Enter the user's UPN (UserPrincipalName) name. Separate them by comma with no space. (Ex: Tsmith,SLi,KGreen)"
        
        # Once users are provided - split them into single item
        $MultiUser = $MultiLookup -split ',\s*' | Where-Object { $_ } | ForEach-Object { $_.Trim() }

  
        foreach($User in $MultiUser){
           
        try {
            # 1. Verify if user is in AD
            Write-Output "`nVerifying if user exist in AD : $User"
            $GetADuser = Get-ADUser -Identity $User -ErrorAction stop
        
            # 2. If user is in AD - proceed with generating report
            Write-Output "Generating lockout report for user: $User"
            # start lookup
            UserLookup
            
        }catch {
            Write-Warning "Could not resolve '$User': $($_.Exception.Message)"
            continue
        }# end try/catch
    }# end foreach

        # Break loop
        Write-Output @"

        ------------------
        [Lookup Complete]
        ------------------
        Appending data for user [$user] to the following file located [$LockOutReport].


"@
        break

        }# End if multi lookup match Y/Yes

        ########################
        # If user selects N/No
        ########################
        if($MultiLookup -match "^(n|no)$") {
            
            Write-Warning "`nScript only allows lookup option for single or multiple users.....Closing....`n"
            break
        }

    }# If singlelookup eq NO

# If user inputs anything other than Y/N - output warning....
 Write-Warning "Please input only Y(yes)/N(no) - double check for typo."

}

}# End parameter input check


#####################################
# Verify user input (Parameters only)
#####################################

# If -user parameter is submitted when script is invoked

if($PSBoundParameters.ContainsKey('User')){

    Write-Warning "The user parameter was explicitly provided! Value: [$User]. Executing script........"

    Write-Output "The current user to look up lockout details is: [$User]"
    Write-Output "The current LockOutReport parameter Value: [$LockOutReport]"
    Write-Output "The current hours parameter Value: [$hours]"
     
        # Once users are provided - split them into single item. Assume that input is multiple string.
        $DataSet = $user -split ',\s*' | Where-Object { $_ } | ForEach-Object { $_.Trim() }

     
    foreach($User in $DataSet){

        try {

            # 1. Verify if user is in AD
            Write-Output "`nVerifying if user exist in AD : $User"
            $GetADuser = Get-ADUser -Identity $User -ErrorAction stop
        
            # 2. If user is in AD - proceed with generating report
            Write-Output "Generating lockout report for user: $User"
            Write-Output "The current user is $user. Appending data to user report under $LockOutReport"

            # start lookup
            UserLookup
                
            }catch{

            # IF user cannot be found - catch error but do not terminate loop yet. Continue until dataset is exhausted.
            Write-Warning "Could not resolve '$User': $($_.Exception.Message)"
            continue

            }# End catch
    }# End Foreach user in dataset
}# End if ($user) parameter exist


############### end script  ##############


