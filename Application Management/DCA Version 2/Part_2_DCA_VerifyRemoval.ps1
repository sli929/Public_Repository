################################################
# Part 2: Start DCA application verification #
################################################

<#
Part 2 of DCA script- meant to be run post reboot after part 1.
Script will verify if application is still installed post removal.

If app is still present, remove it from control panel by removing uninstall string from registry.
Installation might be orphaned.

*Notes:
    All log files will be under [\DCA\Uninstall] folder
    If removal fails for DCA v1.4 and below - it does not impact performance application. The latest version will load for the user as system install.
#>


####################################################
##### Start Logging #####
####################################################
# Establish log folder and logging

$LogPath = "C:\Temp\DCA\Uninstall"
$TestPath = Test-Path -Path $LogPath
if($TestPath -eq $false ){
    
    Write-Output "##### Creating Log folder #####"
    New-Item -Path $LogPath -ItemType "Directory"
}

# start logging
$LogFile = "$LogPath\DCA_Verification_logs-$(Get-Date -Format 'MMddyyyy-HHmmss').log"
Start-Transcript -Path $LogFile -Force


####################################################
##### Start Application verification #####
####################################################
# Requery application

$AppName = "Desktop companion application for Dynamics"
$AppInfo = Get-ItemProperty HKLM:\Software\Microsoft\Windows\CurrentVersion\Uninstall\* , HKLM:\Software\Wow6432Node\Microsoft\Windows\CurrentVersion\Uninstall\* | Select-Object DisplayName, UninstallString, DisplayVersion, pspath | where-object {$_.DisplayName -like "*$AppName*"}

try{
# If app exist - 
if($AppInfo){
    foreach($item in $AppInfo){

              
        ####################################
        # Start clean up scriptblock
        ####################################
 
        # Declare variable            
        $GUID = [regex]::Match($AppInfo.UninstallString, '\{.*?\}').Value
        $version = $item.DisplayVersion
        $PSpath = ([regex]::Match($item.pspath,'HKEY_.*')).Value

        Write-warning "`n### Application $($item.DisplayName) is still installed. Current version: $Version.... ###"
        Write-Warning "`nCurrent registry key location is: $PSpath`n"
        Write-Output "`nStarting clean up process....`n"

        Remove-Item -Path "HKLM:\Software\Microsoft\Windows\CurrentVersion\Uninstall\$GUID" -Force -Verbose -ErrorAction SilentlyContinue
        Remove-Item -path "HKLM:\Software\Wow6432Node\Microsoft\Windows\CurrentVersion\Uninstall\$GUID" -Force -Verbose -ErrorAction SilentlyContinue
        Start-Sleep -Seconds 5

        # Double-check execution success
        if (-not (Test-Path "HKLM:\Software\Microsoft\Windows\CurrentVersion\Uninstall\$GUID") -and ("HKLM:\Software\Microsoft\Windows\CurrentVersion\Uninstall\$GUID")) {

            Write-Output "Registry key successfully deleted."
        }else {
            Write-Output "Target registry key still exist...."
                }
            
    }# for each
}else{

    # If string does not exist, all versions of DCA have been removed from the device
    Write-Output "### All applications have been successfully removed ###"

    }
}catch{

    # get terminating error
    Write-Output $_.Exception
    write-error 66

}
    

###### End script ######

# End logging
Stop-Transcript