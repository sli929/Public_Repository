<#
.SYNOPSIS
    Get list of of enabled AD users by Site and Department, across one or more Site OUs.

    ###################
    Modify OU selection here from [Ordered Dictionary].

    System.Collections.Specialized.OrderedDictionary]$Sites = ([ordered]@{
        'Boston'   = "OU=Boston,OU=Users and Computers,DC=Red929,DC=com"
        'New York' = "OU=New_York_city,OU=Users and Computers,DC=Red929,DC=com"
    }),

    ###################
    
.EXAMPLE
    .\Get-Active-User_Dept.ps1

.EXAMPLE
    .\Get-Active-User_Dept.ps1 -OutputPath "C:\temp\Get-Users-Dept.csv" -Append

    *******************
    Result:

    Name             Department             Site
    ----             ----------             ----
    Steven li        Health Fund            Boston
    Homerr lee       Health Fund            Boston
    Otis li - EX     Health Fund            Boston

    *******************
#>

#######################
# Declare parameters
#######################
[CmdletBinding()]
param(
    # Map [Site name] to [container OU holding that site's department OUs] using [Ordered Dictionary] as opposed to hashtable.
        # Example: California = "OU=Cali,OU=Users,DC=red929,DC=com"

    # Add more sites here to scan for additional users. Grab value of site by using [$sites.value]
    [System.Collections.Specialized.OrderedDictionary]$Sites = ([ordered]@{

        'Boston'   = "OU=Boston,OU=Users and Computers,DC=Red929,DC=com"
        'New York' = "OU=New_York_city,OU=Users and Computers,DC=Red929,DC=com"

    }),

    [string]$OutputPath = "C:\temp\Get-Users-Dept.csv",
    [switch]$Append
)

#######################
# Import module
#######################
Import-Module ActiveDirectory -ErrorAction Stop

########################
# Get users from each OU
########################

# Iteriate through all the sites listed in parameter field
# Example - city, states, territory, etc...
$Info = foreach ($Site in $Sites.GetEnumerator()) {

    # Grab all the department from site OU by changing searchscope
    # Ex: Grab all OU one level above - IT, accounting, member service dept, etc..
    $DepartmentOUs = Get-ADOrganizationalUnit -Filter * -SearchBase $Site.Value -SearchScope OneLevel -ErrorAction Stop

    # Grab all the active users under the department OU
    foreach ($OU in $DepartmentOUs) {

        # Grab enabled users server
        $Users = Get-ADUser -Filter {Enabled -eq $true} -SearchBase $OU.DistinguishedName -ErrorAction SilentlyContinue

        foreach ($user in $Users) {
            [PSCustomObject]@{
                Name       = $user.Name
                Department = $OU.Name   # already known from the loop -- no DN regex needed
                Site       = $Site.Key
            }
        } #foreach User
    } # foreach dept
} #end foreach site loop

$Info | Format-Table -AutoSize

$ExportParams = @{
    Path              = $OutputPath
    NoTypeInformation = $true
    Force             = $true
}
if ($Append) { $ExportParams['Append'] = $true }

$Info | Export-Csv @ExportParams
Write-Output "Exported $($Info.Count) enabled users across $($Sites.Count) site(s) to $OutputPath"