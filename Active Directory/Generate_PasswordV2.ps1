<#
The following function generates random password string that meets the requirement of domain password policy.
All values are unique

*Removed " and ' from special characters (kept a safe, commonly-accepted set — swap in whatever your AD complexity policy specifically allows).

#####################
# Example call
New-RandomPassword -Server 'red929.com'

# Exmaple call with additional length
New-RandomPassword -Server 'red929.com' -ExtraLength 4
#####################

#>

function New-RandomPassword {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $false)]
        [string]$Server,

        # Characters added on top of the domain's MinPasswordLength. Optional - use parameter when calling to add additional characters.
        [Parameter(Mandatory = $false)]
        [int]$ExtraLength = 0
    )

# Grab domain password policy
    try {
        $passwordPolicy = Get-ADDefaultDomainPasswordPolicy -Server $Server -ErrorAction Stop
    }
    catch {
        throw "Unable to retrieve password policy from '$Server': $_"
    }

# Determine number of string required plus extra characters if parameters [Extralength] is used.
    $baseLength  = ($passwordPolicy.MinPasswordLength)
    $totalLength = $baseLength + $ExtraLength

# Determine what type of characters to add to array
# Character pools. Special set avoids quote/apostrophe/backtick which can
# break CSV, JSON, connection strings, or shells if the password lands there.
    $upperSet   = [char[]](65..90)
    $lowerSet   = [char[]](97..122)
    $numberSet  = [char[]](48..57)
    $specialSet = '!@#$%^&*-_+='.ToCharArray()

    $allChars = $upperSet + $lowerSet + $numberSet + $specialSet

# Generate at least a random upper + lower case value as well as number and special character.
    # Guarantee at least one char from each required category
    $required = @(
        ($upperSet   | Get-Random)
        ($lowerSet   | Get-Random)
        ($numberSet  | Get-Random)
        ($specialSet | Get-Random)
    )

# Fill the rest WITH repetition allowed (true random draw, not a no-repeat sample)
    $fillCount = $totalLength - $required.Count
    if ($fillCount -lt 0) {

        throw "ExtraLength combination is shorter than the 4 required character categories."
    }
    $filler = 1..$fillCount | ForEach-Object { $allChars | Get-Random }

    # Combine and shuffle (Fisher-Yates style via random sort key) so the
    # required chars aren't predictably clustered at the end
    $passwordChars = $required + $filler
    $shuffled = $passwordChars | Sort-Object { Get-Random }

    return -join $shuffled

}# End function

# Example call
New-RandomPassword -Server 'red929.com'

# Exmaple call with additional length
New-RandomPassword -Server 'red929.com' -ExtraLength 4
