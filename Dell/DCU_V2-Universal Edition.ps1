<#

*** This script installs Dell Command Update (latest version) via the third-party Dell-EMPS module ***

    The script contains the following:

* Verifies the device is a Dell before doing anything else (was documented but not actually enforced)
* Installs the latest Dell Command Update using the Dell-EMPS module (Universal edition - does not install Classic version)
* Imports a custom XML config into DCU
* Once the XML import succeeds, silently executes install of BIOS, firmware, driver, application updates

#>

[CmdletBinding()]
param(
    [string]$LogPath          = "C:\Temp\DCU-Log",
    [string]$EMPSScriptShare  = "$LogPath\Dell-EMPS.ps1",
    [string]$DCUConfigShare   = "$LogPath\DCU-XML.xml",
    [string]$ApplyUpdateLog   = "$LogPath\Dell-DCULog-EXE-BIOS.log"
)

###########################################
########### Establish Logging ############
###########################################

Write-Output "##### Creating Log folder #####"
if (-not (Test-Path -Path $LogPath)) {
    New-Item -Path $LogPath -ItemType Directory -Force | Out-Null
}

$LogFile = "$LogPath\Dell-DCU-Client-$(Get-Date -Format 'MMddyyyy-HHmmss').log"
Start-Transcript -Path $LogFile -Force


try {

    ###########################################
    ########### Dell model gate ###############
    ###########################################

    Write-Output "`n##### Verifying device manufacturer #####`n"
    $Manufacturer = (Get-CimInstance -ClassName Win32_ComputerSystem -ErrorAction Stop).Manufacturer
    if ($Manufacturer -notmatch 'Dell') {
        throw "Device manufacturer is '$Manufacturer', not Dell -- aborting DCU install."
    }
    Write-Output "Manufacturer confirmed: $Manufacturer"

    ###########################################
    ########### Start DCU installation #######
    ###########################################

    # Requires .NET Framework 4.8 (preinstalled with Windows 11)
    # Credit to https://github.com/gwblok/garytown/blob/master/hardware/Dell/CommandUpdate/EMPS/Dell-EMPS.ps1

    Write-Output "`n##### Copying Dell-EMPS script from share #####`n"
    try {
        Copy-Item -Path $EMPSScriptShare -Destination $LogPath -Force -ErrorAction Stop
    }
    catch {
        throw "Failed to copy Dell-EMPS.ps1 from '$EMPSScriptShare': $($_.Exception.Message)"
    }

    $ScriptPath = Join-Path $LogPath (Split-Path $EMPSScriptShare -Leaf)
    if (-not (Test-Path $ScriptPath)) {
        throw "Dell-EMPS.ps1 was not found at '$ScriptPath' after copy."
    }

    Write-Output "`n##### Importing module for Dell-EMPS script #####`n"
    try {
        Import-Module $ScriptPath -Force -ErrorAction Stop
    }
    catch {
        throw "Failed to import Dell-EMPS module: $($_.Exception.Message)"
    }

    # Get-DellDeviceDetails:
    #    - Retrieves details of the Dell device like model, systemID.
    #    - Supports filtering by systemID and model name
    Write-Output "`n##### Retrieving Details on Dell device #####`n"
    Get-DellDeviceDetails

    # Install-DCU:
    #    - Downloads and installs the latest version of Dell Command Update (DCU) for the system.
    #    - Checks for the latest DCU version available for the system model.
    #    - Downloads the DCU installer and installs it silently.
    Write-Output "`n##### Installing Dell Command Update #####`n"
    Install-DCU

    # Poll instead of a blind 20s sleep -- installers can legitimately take
    # longer under load, and a fixed sleep either wastes time or isn't enough.
    Write-Output "`n##### Verifying DCU installation #####`n"
    $DCU_Details = $null
    $MaxWaitSeconds = 120
    $Elapsed = 0
    do {
        $DCU_Details = Get-ItemProperty `
            HKLM:\Software\Microsoft\Windows\CurrentVersion\Uninstall\*, `
            HKLM:\Software\Wow6432Node\Microsoft\Windows\CurrentVersion\Uninstall\* `
            -ErrorAction SilentlyContinue |
            Select-Object DisplayName, DisplayVersion, Publisher, InstallDate |
            Where-Object DisplayName -match "Dell Command"

        if (-not $DCU_Details) {
            Start-Sleep -Seconds 5
            $Elapsed += 5
        }
    } while (-not $DCU_Details -and $Elapsed -lt $MaxWaitSeconds)

    if ($DCU_Details) {
        Write-Output "`n##### DCU is installed #####`n$($DCU_Details | Out-String)"
    }
    else {
        throw "DCU was not detected in the registry after waiting $MaxWaitSeconds seconds -- aborting before XML import/apply steps."
    }

    ########### End DCU installation ###########

    ###########################################
    ###### Start importing XML settings #######
    ###########################################

    # Resolve dcu-cli.exe dynamically -- DCU installs to Program Files (x86)
    # on nearly all builds, but pin down whichever actually exists rather
    # than hardcoding and failing silently on a path mismatch.

    $DcuCliCandidates = @(

        "C:\Program Files (x86)\Dell\CommandUpdate\dcu-cli.exe",
        "C:\Program Files\Dell\CommandUpdate\dcu-cli.exe"
    )
    $DcuCliPath = $DcuCliCandidates | Where-Object { Test-Path $_ } | Select-Object -First 1
    if (-not $DcuCliPath) {
        throw "dcu-cli.exe not found in any expected install location."
    }
    Write-Output "Using dcu-cli.exe at: $DcuCliPath"

    Write-Output "`n##### Copying DCU XML config from share #####`n"
    try {
        Copy-Item -Path $DCUConfigShare -Destination $LogPath -Force -ErrorAction Stop
    }
    catch {
        throw "Failed to copy DCU-XML.xml from '$DCUConfigShare': $($_.Exception.Message)"
    }

    $XmlPath = Join-Path $LogPath (Split-Path $DCUConfigShare -Leaf)
    if (-not (Test-Path $XmlPath)) {
        throw "DCU-XML.xml was not found at '$XmlPath' after copy."
    }

    Write-Output "`n##### Importing XML settings into DCU #####`n"
    $ImportArgs = "/configure -importSettings=`"$XmlPath`""
    $ImportProc = Start-Process -FilePath $DcuCliPath -ArgumentList $ImportArgs -Wait -PassThru -NoNewWindow
    if ($ImportProc.ExitCode -ne 0) {
        throw "dcu-cli.exe XML import failed with exit code $($ImportProc.ExitCode)."
    }
    Write-Output "XML settings imported successfully."

    ###### End XML import ######

    ###########################################
    ###### Apply updates (silent) #############
    ###########################################

    # Machine must be on AC power to perform a BIOS update.
    # Reboot is left disabled 
    if (-not (Test-Path (Split-Path $ApplyUpdateLog))) {
        New-Item -Path (Split-Path $ApplyUpdateLog) -ItemType Directory -Force | Out-Null
    }

    Write-Output "`n##### Applying BIOS/firmware/driver/application updates #####`n"
    $ApplyArgs = "/applyupdates -updatetype=bios,firmware,driver,application -reboot=disable -forceUpdate=enable -outputlog=`"$ApplyUpdateLog`""
    $ApplyProc = Start-Process -FilePath $DcuCliPath -ArgumentList $ApplyArgs -Wait -PassThru -NoNewWindow

    # dcu-cli exit codes: 0 = success, 1 = reboot required, 5 = no updates
    # found -- treat those three as non-fatal; anything else is a real failure.
    switch ($ApplyProc.ExitCode) {
        0 { Write-Output "Updates applied successfully." }
        1 { Write-Output "Updates applied successfully -- reboot required." }
        5 { Write-Output "No applicable updates were found." }
        default { Write-Warning "dcu-cli.exe apply step returned exit code $($ApplyProc.ExitCode) -- check $ApplyUpdateLog for details." }
    }

    ###### End silent execution of Dell Command Update ######

}
catch {
    Write-Warning "##### DCU deployment failed: $($_.Exception.Message) #####"
}
finally {
    ########### Stop logging ###########
    Stop-Transcript
}