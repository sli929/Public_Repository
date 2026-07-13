<######################################################################
Part 3: Cleanup 
Post Windows 11 IPU, the last part includes cleanup post deployment.

Notes:
This script is intended ONLY for Dell and Lenovo system

# Part 3 script - cleanup & modifications
# Get windows OS version
# Resume Bitlocker, check windows update service
# Remove reg key New-ItemProperty -Path "HKLM:\Software\Microsoft\Windows\CurrentVersion\WindowsUpdate\Orchestrator\" -Name "InstallAtShutdown" -PropertyType "Dword" -Value "1"
# Mounted ISO are removed post reboot
# Modifications includes - reinstall snipping tool

######################################################################>
# Start logging
# Command start time: 20250405141035  = 2025-04-05 2:10pm Format:YYYY-MM-DD HH MM SS
Start-Transcript -Path "C:\Temp\Win11_IPU\Log\Part_3-Win11_IPU_CleanUp_Logs_Explicit.txt" -Force -IncludeInvocationHeader

$LogPath = "C:\temp\Win11_IPU\Log"
$Log = "Part_3_CleanUp_Logs.txt"
$AllError = "Part_3_CleanUp_Errors.txt"

######################################################################
try{
# Obtain the OS version post install
<#
ProductName        : Windows 11 Pro
DisplayVersion     : 23H2
CurrentBuildNumber : 19045
#>

$OSInfo = Get-CimInstance -ClassName Win32_OperatingSystem | Select-Object Version, Caption
$Version = Get-ItemProperty "HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion\"  'DisplayVersion'

#If OS equals windows 11, success. Else, setup failed.
if($OSInfo.Caption -match "Microsoft Windows 10"){
    
    Write-Output "In place upgrade failed, please review logs at 'C:\temp\Win11_IPU\Log' and try to re run script" 
    Write-Output "Current Operating System Information:`nCurrent OS: $($OSInfo.Caption)`nVersion: $($Version.DisplayVersion)`nBuild: $($OSInfo.Version)"  


}elseif($OSInfo.Caption -match "Microsoft Windows 11"){

    Write-Output "`n########## In place upgrade success! ..... Starting IPU Clean up..... ##########`n" 
    Write-Output "Current Operating System Information:`nCurrent OS: $($OSInfo.Caption)`nVersion: $($Version.DisplayVersion)`nBuild: $($OSInfo.Version)"  
}

######################################################################
##### Start cleanup #####
Write-Output "`n########## Starting Windows 11 IPU cleanup.....##########`n"

##### Resume Bitlocker #####

# If bitlocker is off, turn it on. If device not NOT have bitlocker on before, triggering "Resume-Bitlocker" will end in error prompt if device was not encrypted in first place.
# A second condition must be checked off for devices that was previously encrypted but protection suspended.
# Following Scriptblock detect is bitlocker is suspened, if drive was previously encrypted and percentage of encryption. IF drive was previously encrypted, resume encryption

$BitlockerStatus = (Get-BitLockerVolume -MountPoint "C:").ProtectionStatus
$BitlockerVolumeStatus = (Get-BitLockerVolume -MountPoint "C:").VolumeStatus
$BitlockerPercentage = (Get-BitLockerVolume -MountPoint "C:").EncryptionPercentage

        
      if($BitlockerStatus -match "OFF" -and $BitlockerVolumeStatus -eq "FullyEncrypted" -or $BitlockerPercentage -gt "1" ){

            Resume-BitLocker -MountPoint C:

            Write-Output "Resuming bitlocker on C: ....."

        }

##### Start windows update service #####
Write-Output "`n########## Start windows update service.....##########`n" 

start-Service -Name "wuauserv" -Verbose
$WindowsUpdateStatus = Get-Service -Name "wuauserv" -Verbose

Write-Output "`nWindows Update service status:$($WindowsUpdateStatus|out-string)" 

##### Remove Registry Key #####
# Remove "InstallAtShutdown" Reg value
Write-Output "`n########## Removing 'InstallAtShutdown' registry key ##########`n" 
Remove-ItemProperty  -Path "HKLM:\Software\Microsoft\Windows\CurrentVersion\WindowsUpdate\Orchestrator\" -Name "InstallAtShutdown" -Verbose -erroraction silentlycontinue

$OrchestratorValue = Get-ItemProperty "HKLM:\Software\Microsoft\Windows\CurrentVersion\WindowsUpdate\Orchestrator\" 

if ($OrchestratorValue -cmatch "InstallAtShutdown"){

    Write-Output "InstallAtShutdown registry value is present. Removal unsuccessful" 

}else{
    Write-Output "Registry Value 'InstallAtShutdown' is not present. Removal successful! " 
}

##### Remove ISO Folder #####
# If OS is windows 11- remove folder, else keep it
$ISOPath = "C:\temp\Win11_IPU\ISO"
if($OSInfo.Caption -match "Microsoft Windows 11"){

    Write-Output "`nCleaning up ISO Folder located at C:\temp\Win11_IPU\ISO .........." 
    Remove-Item -Path $ISOPath -Force -Recurse -ErrorAction SilentlyContinue

}elseif($OSInfo.Caption -match "Microsoft Windows 10"){

    Write-Output "`nCurrent OS is: $($OSInfo.Caption | out-string).....Skipping clean up of ISO folder" 

}

# Verify item removal
$ISOPathVerify = Get-ChildItem $ISOPath -ErrorAction SilentlyContinue
if($ISOPathVerify){

    Write-Output "`nCleaning up ISO Folder located at C:\temp\Win11_IPU\ISO failed.........." 

}else{

    Write-Output "`nCleaning up ISO Folder located at C:\temp\Win11_IPU\ISO success........." 

}

######################################################################
#Catch any non terminating errors for this entire scriptblock
}catch{
    Write-Output "$($_.Exception.Message)" 
       }# end catch

Write-Output "`n########## Windows 11 IPU Cleanup Complete ##########`n"
######################################################################
##### Start Windows 11 Post IPU changes #####

Write-Output "`n########## Start Windows 11 Post IPU changes ##########`n"


# Windows 11 changes - -Snipping Tool and Snip and Sketch have been merged into a single experience keeping the familiar Snipping Tool name.
# Issue: Snipping tool does not show up post windows 11 IPU, reinstall it. It is most likly missing due to failed merged between "snip and sketch (win 11)" with "Snipping tool (win 10)"

# Use get-AppxPackage to reinstall snip it. Pick one that works.
# The -UseWinPS parameter with Import-Module Appx is used to force the Appx module to run in the Windows PowerShell compatibility session when you are in PowerShell 7.
try{
    Import-Module Appx  
    Import-Module Appx -UseWinPS   # -UseWinPS may error out
    
}catch{

    Write-Output "$($_.Exception.Message)" 

}

try{
# start snipping tool appx installation:

$SnipTool = Get-AppxPackage *ScreenSketch*
# If device contains screensketch
if($sniptool.name -contains "Microsoft.ScreenSketch"){

    Write-Output "`nSnipping tool/ScreenSketch is already present on device as appx package.....Skipping installation`n"

#else if device does not have it installed, install it
}elseif($null -eq $sniptool.name ){

    Write-Output "`nSnipping tool/ScreenSketch not found under appx packages......Starting installation for all users`n"
    Get-AppxPackage -Allusers *Microsoft.ScreenSketch*| foreach {Add-AppxPackage -register “$($_.InstallLocation)\appxmanifest.xml” -DisableDevelopmentMode}

    # Verify installation:
    $SnipTool = Get-AppxPackage *ScreenSketch*

        if($sniptool.name -contains "Microsoft.ScreenSketch"){
            Write-Output "`nInstallation of Snipping tool/ScreenSketch completed successfully`n"
        }else{
            Write-Output "`nInstallation of Snipping tool/ScreenSketch failed.....skipping`n"

        }

    }# End installation
}catch{

    Write-Output "$($_.Exception.Message)" 
}

###### End Post Win11 IPU Modifications ######

######################################################################
# Display and log all errors from script
$Error | Out-File -FilePath "$($LogPath)\$AllError" -Append

# End logging
Stop-Transcript

######################################################################
# End of Windows 11 IPU script