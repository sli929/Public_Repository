
################################################
# Part 1: Start DCA uninstallation #
################################################

####################################################
<#
Script will remove per user install of DCA only if user is logged into device.
If its a device install DCA - user does not need to be logged in.

Script finds all uninstall strings on device and trigger removal with its GUID
Then verification check starts after removal process to make sure all versions of DCA are removed from the device.

*Notes:
    All log files will be under [\DCA\Uninstall] folder
    If removal fails for DCA v1.4 and below - it does not impact performance application. The latest version will load for the user as system install.
    In the past, DCA was wrapped as MSIX available only for user provisioned installations. There were updates done beyond V1.4 that wrapped the install with MSI installer allowing for system provison rollout.
    The removal process will handle both MSIX and MSI installations to ensure complete uninstallation of DCA from the device.
#>

####################################################

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

if($TestPath -eq $true ){
    Write-Output "##### Cleaning up folder for uninstallation logs #####"
    Remove-Item "$($LogPath)\*" -Recurse -Force -ErrorAction SilentlyContinue
}

# start logging
$LogFile = "$LogPath\DCA_Removal_logs-$(Get-Date -Format 'MMddyyyy-HHmmss').log"
Start-Transcript -Path $LogFile -Force


####################################################
##### Start Application Removal #####
####################################################

####### Remove all versions of DCA - [current and existing] ####### 

$AppName = "Desktop companion application for Dynamics"
$AppInfo = Get-ItemProperty HKLM:\Software\Microsoft\Windows\CurrentVersion\Uninstall\* , HKLM:\Software\Wow6432Node\Microsoft\Windows\CurrentVersion\Uninstall\* | Select-Object DisplayName, UninstallString, DisplayVersion | where-object {$_.DisplayName -like "*$AppName*"}

# Find all the uninstall strings matching application name. Trigger uninstall for all.
foreach($item in $AppInfo){

try{
    $GUID = [regex]::Match($item.UninstallString, '\{.*?\}').Value
    $version = $item.DisplayVersion

    Write-Output "`n### DCA Version $($item.DisplayName) detected.... Current Version: $Version .....Starting removal process with uninstall $GUID ###"
    $Uninstall_Parameter = "/qn /norestart /X$($GUID) /L*v $LogPath\DCA_Version_$($version)_Uninstall.log /qn"
    Start-Process "msiexec.exe" -ArgumentList "$Uninstall_Parameter" -wait -Verbose
}catch{

    # get terminating error
    Write-Output $_.Exception
    Write-Error 66
    }

}# End foreach

# Append reboot file
if($AppInfo){

    Write-Output "`nDCA installation detected, recording status to C:\windows\temp\ folder with file: [Reboot_DCA]`n "
    Remove-Item -Path "$env:WINDIR\Temp\DCA\Reboot_DCA" -Force -ErrorAction SilentlyContinue
    New-item -Path "$env:WINDIR\Temp\DCA" -Name "Reboot_DCA" -ItemType File -Force

}


####### Remove existing DCA MSIX installations ####### 
Get-AppxPackage -all *Microsoft.Dynamics.DesktopCompanionApp* | Remove-AppxPackage -AllUsers


####################################################
##### End Application Removal #####
####################################################

# Reboot device post removal (Continue with Part 2_DCA_VerifyRemoval)

# end logging
Stop-Transcript

