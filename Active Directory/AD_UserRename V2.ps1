<#
.SYNOPSIS
    Name change for hybrid (on-prem AD + AAD) environment.
    Updates GivenName/Initials/Surname, CN, DisplayName, UPN, SamAccountName,
    primary email, mailNickname, and proxyAddresses for a single user.

    # The user MUST have exchange mailbox setup first or script will error out. The custom mail attributes are REQUIRED!!
    # Script tested and works in Powershell 7 as well #

.NOTES

    Scenarios: Marriage/Divorce, Gender Transition, Cultural/Religious reasons, Adoption, legal name change, etc.

    Immutable identifiers (objectGUID/objectSid on-prem, objectId in AAD) are what keep systems
    linked together — NOT UPN/SamAccountName/email. So this rename is safe for AD, AAD, Exchange,
    OneDrive, SharePoint, Office apps, and folder ACLs.

    Possible impact: third-party apps that key off UPN/email/SAM instead of an immutable ID
    (HR systems like Workday/ADP, DUO/2FA sync providers, custom department apps).

    The script uses [$PSCmdlet.ShouldProcess] for -whatif parameter - this triggers a prompt for user to accept before proceeding with changes..
    if ($PSCmdlet.ShouldProcess($OldUPN, "Update EmailAddress, mailNickname, proxyAddresses"))

    Example:
    Performing the operation "Update EmailAddress, mailNickname, proxyAddresses" on target "pli".
    [Y] Yes  [A] Yes to All  [N] No  [L] No to All  [S] Suspend  [?] Help (default is "Y"): y


.EXAMPLE
    .\AD_Name_Change_Optimized.ps1 -OldUPN "sli" -NewUPN "slee" -Lastname_New "Lee" -Firstname_New "Stephan" -Initial_New "M"

.EXAMPLE
    # Dry run first - shows what would happen, changes nothing
    .\AD_Name_Change_Optimized.ps1 -OldUPN "sli" -NewUPN "slee" -Lastname_New "Lee" -WhatIf
#>

[CmdletBinding(SupportsShouldProcess = $true, ConfirmImpact = 'High')]
param(
    [Parameter(Mandatory)]
    [ValidatePattern('^\S+$')]
    [string]$OldUPN,

    [Parameter(Mandatory)]
    [ValidatePattern('^\S+$')]
    [string]$NewUPN,

    # Blank string is ok for firstname/initial/Lastname, but not for UPN/SAM. If blank, the existing value is kept.
    [Parameter(Mandatory=$false)]
    [string]$Firstname_New =  (Read-Host "Enter [NEW] First Name (Optional)"),

    [Parameter(Mandatory=$false)]
    [string]$Initial_New = (Read-Host "Enter [NEW] Initial (Optional)" ),

    [Parameter(Mandatory=$false)]
    [string]$Lastname_New =(Read-Host "Enter [NEW] Last Name (Optional)"),

    [string]$FundsDomain   = "@red929.com",
    [string]$DefaultDomain = "@red929.mail.onmicrosoft.com"

)

Import-Module ActiveDirectory -ErrorAction Stop

# ###############
# Logging setup
# ###############

# Create the log folder if it doesn't exist, or clean it up if it does.
$LogPath = "C:\Temp\AD_NameChange\"
$TestPath = Test-Path -Path $LogPath
if($TestPath -eq $false ){
    
    Write-Output "##### Creating Log folder #####"
    New-Item -Path $LogPath -ItemType "Directory"
}

if($TestPath -eq $true ){
    Write-Output "##### Cleaning up Log folder #####"
    Remove-Item "$($LogPath)\*" -Recurse -Force -ErrorAction SilentlyContinue
}

# start logging
$LogFile = "$LogPath\AD_NameChange_logs-$(Get-Date -Format 'MMddyyyy-HHmmss').log"
Start-Transcript -Path $LogFile -Force


try {
  
# ###################################################################
# Start Pre-flight validation- validate if there is existing new UPN #
# ###################################################################

    # The user MUST have exchange mailbox setup first or script will error out. The custom mail attributes are REQUIRED!!
    $ADUser = Get-ADUser -Identity $OldUPN -Properties GivenName, Initials, Surname, Name, `
    UserPrincipalName, SamAccountName, EmailAddress, mailNickname, proxyAddresses -ErrorAction Stop

    # If OldUPN not equal to NewUPN, check if NewUPN already exists in AD.
    if ($OldUPN -ne $NewUPN) {

        # Grab details on new UPN
        $conflict = Get-ADUser -Filter "SamAccountName -eq '$NewUPN' -or UserPrincipalName -eq '$NewUPN$FundsDomain'" -ErrorAction SilentlyContinue

        if ($conflict) {
            # If AD already has new UPN, abort before making any changes. This prevents a half-done rename that would leave the user in a broken state.
            throw "NewUPN '$NewUPN' already exists in AD (conflicts with $($conflict.DistinguishedName)). Aborting before any changes were made."
        }
    }
# ###################################################################
# End Pre-flight validation- validate if there is existing new UPN #
# ###################################################################

# ##########################
# Take Snapshot of Old UPN #
# ##########################

# Snapshot "before" state for the report. Grab details on old UPN before any changes are made, so we can report on what changed at the end.
    $OldUPNInfo = $ADUser | Select-Object GivenName, Initials, Surname, Name, UserPrincipalName, `
    SamAccountName, EmailAddress, mailNickname, proxyAddresses

# ############################
# Declare variable for GUID #
# ############################

    # Use the immutable ObjectGUID as -Identity for every subsequent write.
    # This keeps working even after SamAccountName/UPN change mid-script, and avoids the
    # PS7 pipeline-binding issue from piping Get-ADUser into Rename-ADObject/Set-ADUser. Extremely important to use for rename as it avoid dependency on SamAccountName/UPN, which change mid-script.

    # GUID for OLD UPN
    $Identity = $ADUser.ObjectGUID

# ##################################################################################
# Name attributes (GivenName / Initials / Lastname) - Get full name from new values.
# ##################################################################################

    # Grab the new string for each name attribute, or keep the existing value if no new value was provided.
    # This method does not erase any attributes if no values are provided. The existing values are PRESERVED!!
    
    $NameChanged = $Firstname_New -or $Initial_New -or $Lastname_New

    $EffectiveFirst   = if ($Firstname_New) { $Firstname_New } else { $ADUser.GivenName }
    $EffectiveInitial = if ($Initial_New) { $Initial_New }   else { $ADUser.Initials }
    $EffectiveLastname = if ($Lastname_New) { $Lastname_New }  else { $ADUser.Surname }

    # IF ANY NEW VALUES are provided, update the name attributes. Otherwise, keep the existing values.
    if ($NameChanged) {
            
        Write-Output @"
        #############################
        Updating name attribute(s)...
        #############################
"@
        # Assign variables and pass it to hashtable [NameParams]. Cmdlet [Set-ADUser] will use these values to update identity
        $nameParams = @{}
        if ($Firstname_New){ $nameParams['GivenName'] = $Firstname_New }
        if ($Initial_New)  { $nameParams['Initials']  = $Initial_New }
        if ($Lastname_New) { $nameParams['surname']  = $Lastname_New }

        # Update AD attributes with new values
        # Prompt user to confirm changes with $PSCmdlet.ShouldProcess
        if ($PSCmdlet.ShouldProcess($OldUPN, "Execute [Set-ADUser -identity] to update Firstname, initial, Lastname to $(($nameParams.Values))")){

            Set-ADUser -Identity $Identity @nameParams -ErrorAction Stop
        }

    } else {

    Write-Output @"
        ############################################################
        No name changes requested; keeping existing name attributes.
        ############################################################
"@
    }
    
# ######################################################
# Start Update Full Name (for attributes CN and DisplayName)
# ######################################################

    # If initials are not provided (Firstname + Lastname only)
    $FullName = if ([string]::IsNullOrEmpty($EffectiveInitial)) {

        "$EffectiveFirst $EffectiveLastname"

    } else {
    # Combine all the name attributes (Firstname + Initial + Lastname)
        "$EffectiveFirst $EffectiveInitial $EffectiveLastname"

    } 
    #clean up any double space problem
    $Fullnamev2 = $fullname -replace '\s+', ' ' 

 Write-Output @"

    ##########################################################
    Updating [NEW] string for First name, Initial or Last name
    
    Users updated full name is: $Fullnamev2
    ##########################################################
"@
    # Update CN and DisplayName if any of (First, inital, lastname) is provided.
    if ($PSCmdlet.ShouldProcess($OldUPN, "Execute [Rename-ADObject -Identity and] [Set-ADUser -DisplayName] to '$FullNamev2'")) {

    Write-Output @"

    ################################################
    Updating [Fullname] field for user............ "
    ################################################

"@
        Rename-ADObject -Identity $Identity -NewName $FullNamev2 -ErrorAction Stop

    Write-Output @"

    ################################################
    Updating [DisplayName] for user............ 
    ################################################

"@
        Set-ADUser -Identity $Identity -DisplayName $FullNamev2 -ErrorAction Stop
    }

# ######################################################
# End Update Full Name (for attributes CN and DisplayName)
# ######################################################

# ######################################################
# Start Update Email / proxyAddresses
# ######################################################
<# Update proxy addresses. The proxyAddresses attribute in Active Directory is a multi-valued attribute that stores a list of email addresses associated with a user, group, contact, or other mail-enabled object.
    
Normal setup for proxy address:
    #SMTP:sli@32bjfunds.com
    #smtp:sli@32bjfunds.mail.onmicrosoft.com

    SMTP: (uppercase) denotes the primary SMTP address.
    smtp: (lowercase) denotes secondary SMTP addresses.
    X400: denotes X400 addresses.
    Other address types may also be present.
#>
$NewPrimarySmtp = "$NewUPN$FundsDomain"
$NewSecondarySmtp = "$NewUPN$DefaultDomain"
$OldPrimarySmtp = "$OldUPN$FundsDomain"

# The [$PSCmdlet.ShouldProcess] prompts user to accept Yes or NO to proceed with setting the attributes

    if ($PSCmdlet.ShouldProcess($OldUPN, "Execute [Set-ADUser -identity -EmailAddress] to update EmailAddress, mailNickname and proxyAddresses")) {

    Write-Output @"

    ##########################################################################
    Updating EmailAddress, mailNickname and proxyAddresses for user............ 

    New Primary SMTP proxy address = $NewPrimarySmtp 
    New secondary SMTP proxy address = "$NewUPN$DefaultDomain"
    ##########################################################################

"@
        Set-ADUser -Identity $Identity -EmailAddress $NewPrimarySmtp -Replace @{mailNickname = $NewUPN} -ErrorAction Stop

        # Add the new primary SMTP primary email (@Company Domain) and secondary smtp routing address(@Microsoft Default Domain)
        Set-aduser -identity $Identity -Add @{proxyaddresses="SMTP:$NewPrimarySmtp"} -ErrorAction Stop #Required
        Set-aduser -identity $Identity -Add @{proxyaddresses="smtp:$NewSecondarySmtp"}-ErrorAction Stop #Required

        # Remove old SMTP primary email address(@Company Domain) and re-add the old SMTP address as secondary "smtp" addresses
        Set-aduser -identity $Identity -Remove @{proxyaddresses="SMTP:$OldPrimarySmtp"}-ErrorAction Stop #Required
        Set-aduser -identity $Identity -add @{proxyaddresses="smtp:$OldPrimarySmtp"}-ErrorAction Stop # optional
                    
    }

# ######################################################
# End Update Email / proxyAddresses
# ######################################################

# #############################################################################
# Start Update UPN and SamAccountName - do this LAST, exactly like the original
# #############################################################################

    if ($PSCmdlet.ShouldProcess($OldUPN, "Set UserPrincipalName and SamAccountName to '$NewUPN'")) {

        
    Write-Output @"

    ##########################################################################
    Updating UPN (UserPrincipalName) and SAM (SamAccountName) for user............ 

    New UserPrincipalName = $NewPrimarySmtp 
    New SamAccountName = $NewUPN
    ##########################################################################

"@
        Set-ADUser -Identity $Identity -UserPrincipalName $NewPrimarySmtp -ErrorAction Stop

        Set-ADUser -Identity $Identity -SamAccountName $NewUPN -ErrorAction Stop
    }

# #############################################################################
# End Update UPN and SamAccountName - do this LAST, exactly like the original
# #############################################################################

# ################################################
# Start Detail summary of changes (Report before/after)
# ################################################

# If not in whatif mode
    if (-not $WhatIfPreference) {

        $NewUPNInfo = Get-ADUser -Identity $Identity -Properties GivenName, Initials, Surname, Name, `
            UserPrincipalName, SamAccountName, EmailAddress, mailNickname, proxyAddresses |
            Select-Object GivenName, Initials, Surname, Name, UserPrincipalName, SamAccountName, `
                EmailAddress, mailNickname, proxyAddresses

        Write-Output "`nOn-prem name change complete.`n--- BEFORE ---"
        $OldUPNInfo | Format-List | Out-String | Write-Output

        Write-Output "--- AFTER ---"
        $NewUPNInfo | Format-List | Out-String | Write-Output
    }
# ################################################
# End Detail summary of changes (Report before/after)
# ################################################

} #end try for entire script

catch {
    # Terminate script if any errors encountered
    Write-Error "AD name change FAILED and was stopped: $($_.Exception.Message)"
    throw
}
finally {
    # Stop logging
    Stop-Transcript 
}


# ################
# End script
# ################

Write-Warning "`n################ Script complete ################"