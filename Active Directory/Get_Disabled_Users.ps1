<#
.SYNOPSIS
    Audit report: disabled AD users (with a Title, i.e. real people not service/shared/room
    accounts) under a given OU, with their most recent logon time across the domain.

    
    ###########
    Modify OU path under parameter:

    [string]$OUPath = "DC=Red929,DC=com",
    ###########

.NOTES
    Intended for AD cleanup/audit of terminated employees.

.EXAMPLE
    # Fast (default): single query, uses replicated lastLogonTimestamp (~14 day accuracy)
    .\Disabled_Users_Audit_Optimized.ps1

.EXAMPLE
    # Exact last logon across every DC (slower, same technique as the original script's intent)
    .\Get_Disabled_Users.ps1 -Precise

.EXAMPLE
    .\Get_Disabled_Users.ps1 -OUPath "OU=Users,DC=red929,DC=com" -OutputPath "C:\temp\disabled.csv"

    ************************
    Results:
    Name        Email              Last_Logon
    ----        -----              ----------
    xo x smith3 xsmith3@red929.com Never
    tommy pank2 tpank4@red929.com  Never
    thomas hank thank4@red929.com  Never
#>

######################
# Declare parameter #
######################
[CmdletBinding()]
param(
    [string]$OUPath = "DC=Red929,DC=com",
    [string]$OutputPath = "C:\temp\disabled_Users_Domain_Wide_V2.csv",

    # Exact per-DC lastLogon lookup instead of the fast replicated timestamp. Slower on large orgs.
    [switch]$Precise
)

######################
# Import module  #
######################
Import-Module ActiveDirectory -ErrorAction Stop

######################
# Declare function #
######################
<# 
Bulk-friendly version of the original Get-LastLogon: accepts AD user objects (not strings),
so callers can pipe ALL users in at once and the DC list is only fetched once (begin block
runs once per pipeline, not once per user like the original's per-user function calls did). 
#>
function Get-LastLogon {
    [CmdletBinding()]
    param(
        [Parameter(ValueFromPipeline, Mandatory)]
        [Microsoft.ActiveDirectory.Management.ADUser[]]$Identity
    )

    begin {
        $DCList = (Get-ADDomainController -Filter *).Name
        Write-Output "Enumerated $($DCList.Count) domain controllers (once)."
    }

    process {
        # Iterate per User
        foreach ($user in $Identity) {
            $newest = 0

            foreach ($DC in $DCList) {

                # Grab each user and search for lastlogon across ALL reachable DC
                $acct = Get-ADUser -Identity $user.DistinguishedName -Properties lastLogon -Server $DC -ErrorAction SilentlyContinue

                if ($acct -and $acct.lastLogon -gt $newest) {
                    $newest = $acct.lastLogon
                }
            }#End foreach ($DC in $DCList)

            [PSCustomObject]@{
                DistinguishedName = $user.DistinguishedName
                # Compare the raw filetime integer to 0 -- NOT a converted date's .Year -- so
                # this is correct regardless of the server's local time zone.
                LastLogon = 
                if($newest -eq 0) { "Never" } else { [datetime]::FromFileTime($newest) }
            }
        }# End foreach ($user in $Identity)
    } # end process
}# end function Get-LastLogon

# #############################################################################################
# Pull only disabled users with title attribute
# Exclude service account since [PasswordNeverExpires] option is always $false for normal domain users
# ############################################################################################

$RequiredProps = @('Name', 'EmailAddress', 'Enabled', 'PasswordNeverExpires', 'Title', 'DistinguishedName')
if (-not $Precise) { $RequiredProps += 'lastLogonTimestamp' }

$Users = Get-ADUser -SearchBase $OUPath -Properties $RequiredProps -Filter {
    (Enabled -eq $false) -and (PasswordNeverExpires -eq $false) -and (Title -like '*')
}

Write-Output "Found $($Users.Count) disabled users with a Title under $OUPath."

# ###############################
# Resolve last logon per user
# ###############################

if ($Precise) {
    Write-Verbose "Precise mode: querying every DC for every user (slower)."
    $LogonLookup = @{}
    $Users | Get-LastLogon | ForEach-Object { $LogonLookup[$_.DistinguishedName] = $_.LastLogon }
}

$Data = foreach ($user in $Users) {

    $LastLogon = if ($Precise) {
        $LogonLookup[$user.DistinguishedName]
    }
    elseif ($user.lastLogonTimestamp -and $user.lastLogonTimestamp -gt 0) {
        [datetime]::FromFileTime($user.lastLogonTimestamp)
    }
    else {
        "Never"
    }

    [PSCustomObject]@{
        Name       = $user.Name
        Email      = $user.EmailAddress
        Last_Logon = $LastLogon
    }
}

$Data | Export-Csv -Path $OutputPath -NoTypeInformation -Force
Write-Output "Exported $($Data.Count) rows to $OutputPath"