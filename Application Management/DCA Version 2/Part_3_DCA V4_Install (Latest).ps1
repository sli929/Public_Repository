################################################
# Part 3: Start DCA installation #
################################################

####################################################
<# The following script contains the following:

##### Part 1:  DCA-Prerequisite and browser extension setup #####

It entails the following:
    - Installs prerequisite for DCA - Microsoft visual c++ 2015-2022 (latest version)
    - Downloads DCA MSI and DCA shortcut to c:\temp\DCA\Install.
        DCA client is pulled from "https://aka.ms/dca-installer" so version will always be the latest.
    - Installs and configure DCA extension for Edge browser
    - Copy DCA shortcut to start up folder for ALL users [C:\ProgramData\Microsoft\Windows\Start Menu\Programs\Startup]
    - Disable Auto Update for DCA using registry
    
  Notes:
    When extension gets installed, edge browser needs to be closed and re opened to initalize the extension.
    DCA shortcut is pulled from shell:Appsfolder. No need to reference windowsapp folder directly.
    Shortcut should work for any version of DCA

##### Part 2:  DCA Install #####

It entails the following:
    - Installs DCA (Desktop companion application for Dynamics 365 Contact Center) have it available to all users that log into device.
    - Detect and verify if DCA is installed. Provides version and install date
    - The script triggers the DCA shortcut. Once process starts, DCA will install and start up for current user logged in

    - DCA is a MSIX app that cannot be run as SYSTEM or ADMIN. However, it can be installed as ADMIN account and provisioned to all users.
    - Per-system context for MSIX apps means the app is "provisioned" for all users so that once a user logs in, the app is installed for them as per-user from the "provisioned" install.
    - MSIX apps are configured to be sandboxed and run as per user. The user can reset, repair or remove the app without account escalation.

  Notes:
  Folder for ALL USERS - [C:\Program Files\msdyn-companionapp-nh]
  DCA MSIX source:"C:\Program Files\WindowsApps\Microsoft.Dynamics.DesktopCompanionApp_1.1.25168.2_x64__8wekyb3d8bbwe"

  **********
  ** User does not need to be logged in for script to run **
  **********
    
#>
####################################################

####################################################
##### Start Logging #####
####################################################
# Clean up existing DCA folder and establish logging
# All DCA installation component into DCA\Install folder.

$LogPath = "C:\Temp\DCA\Install"
$TestPath = Test-Path -Path $LogPath
if($TestPath -eq $false ){
    
    Write-Output "##### Creating Log folder #####"
    New-Item -Path $LogPath -ItemType "Directory"
}

if($TestPath -eq $true ){
    Write-Output "##### Cleaning up Log folder for reinstallation/update #####"
    Remove-Item "$($LogPath)\*" -Recurse -Force -ErrorAction SilentlyContinue
}

# start logging
$LogFile = "$LogPath\DCA_PS_Install_logs-$(Get-Date -Format 'MMddyyyy-HHmmss').log"
Start-Transcript -Path $LogFile -Force


####################################################
##### Start Microsoft visual c++ detection and installation #####
####################################################
# Detect if device has Microsoft visual c++ (2015-2022) installed

# Look for [string: Version] under registry to determine if Microsoft visual c++ redistribution is installed.
# The version number is 14.0 for Visual Studio 2015, 2017, 2019, and 2022 
$VersionBuild = Get-ItemProperty HKLM:\SOFTWARE\Wow6432Node\Microsoft\VisualStudio\14.0\VC\Runtimes\X64

    Write-Output "`n ##### Microsoft Visual C++ Redistributable 2015-2022 (x64) is installed. Current version is $($VersionBuild.version) #####`n"

    Write-Output "`n########## Starting installation of latest version of MSVC++ Redistributable ##########`n"
    Install-PackageProvider -Name NuGet -Confirm:$false -Force
    Install-Module -Name VcRedist -Confirm:$false -Force
    Import-Module VcRedist
    Install-VcRedist -VcList (Get-VcList | Save-VcRedist -Path "$LogPath") -Silent

    Start-Sleep 20
    
    # Confirm installation
    $vc_redist_installed = Get-ItemProperty HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall\* |
    Where-Object {$_.DisplayName -like "Microsoft Visual C++*"} |
    Select-Object DisplayName, DisplayVersion

    Write-Output "Microsoft Visual C++ Redistributable(s) are installed:"

    $vc_redist_installed | Format-Table -AutoSize


####################################################
##### End Microsoft visual c++ detection and installation #####
####################################################


####################################################
##### Start Gathering the necessary files to prep for installation #####
####################################################
# Download both shortcut and MSI file for DCA

############# Start download of DCA shortcut #############
# If invoke-webrequest times out and fails, fall back to start-bitsTransfer to pull again with a different link

Write-Output "`n##### Start download of DCA Shortcut.....#####`n" 

Try{
    # Fetch the raw file shortcut from  Github public repository
    $DownloadURL_Shortcut = "https://github.com/sli929/Public_Repository/blob/main/Application%20Management/DCA%20Version%202/Shortcut/Microsoft%20Dynamic%20Companion%20App.lnk?raw=true"
    $FilePath_Shortcut = "$LogPath\Microsoft Dynamic Companion App.lnk"
    Write-Output "`nStart download of DCA MSI with Invoke-WebRequest`n"
    $ProgressPreference = 'SilentlyContinue'
    Invoke-WebRequest -Uri $DownloadURL_Shortcut -OutFile $FilePath_Shortcut -Verbose 
    
    }catch{
        # If terminating error occurs, catch message. Fall back and re try a different link with start-bitstransfer
        Write-Output "Error: $($_.Exception.Message)"
        $DownloadURL_Shortcut2 = "https://github.com/sli929/Public_Repository/blob/main/Application%20Management/DCA%20Version%202/Shortcut/Microsoft%20Dynamic%20Companion%20App.lnk?raw=true"
        Write-Output "`n##### Falling back to download with Start-BitsTransfer #####"
        Start-BitsTransfer -Source $DownloadURL_Shortcut2 -Destination $FilePath_Shortcut -Verbose -Description "DCA shortcut"
    
    }
    
    ##### Post Download #####
    # Verify if file is there in the folder
    
    if(test-path $FilePath_Shortcut){
        Write-Output "`nDCA shortcut download complete....File saved to $FilePath_Shortcut`n" 
    
        
    }else{
        write-error "`n!! $FilePath_Shortcut shortcut NOT found !! ....Exiting script`n"
        Stop-Transcript #End logging
        Exit 66 #close script
    
    } #End If statement - test-path $FilePath_Shortcut
    
############# End download of DCA shortcut #############
    

############# Start download of DCA MSI #############
# If invoke-webrequest times out and fails, fall back to start-bitsTransfer to pull again with a different link

Try{
    # Start-bitstransfer works well for bigger files
    $DownloadURL_MSI = "https://aka.ms/dca-installer"
    $FilePath_MSI = "$LogPath\Microsoft.Dynamics.CompanionApp.Installer.MSI"

    Write-Output "`n##### Falling back to download with Invoke-webRequest #####"
    $ProgressPreference = 'SilentlyContinue'
    Invoke-WebRequest -Uri $DownloadURL_MSI -OutFile $FilePath_MSI -Verbose 
    
        
    }catch{
        # If terminating error occurs, catch message. Fall back and re try
        Write-Output "Error: $($_.Exception.Message)"
    
        Write-Output "`nStart download of DCA shortcut with Start-BitsTransfert`n"
        Start-BitsTransfer -Source $DownloadURL_MSI -Destination $FilePath_MSI -Verbose -Description "DCA MSI"

    
    }
    
    
    ##### Post Download #####
    # Verify if file is there in the folder
    
    if(test-path $FilePath_MSI){
        Write-Output "`nDCA MSI download complete....File saved to $FilePath_MSI`n" 
    
        
    }else{
        write-error "`n!! $FilePath_MSI MSI NOT found !! ....Exiting script`n"
        Stop-Transcript #End logging
        Exit 66 #close script
    
    } #End If statement - test-path $FilePath_MSI
    
############# End download of DCA MSI #############
    
    
####################################################
##### End Gathering the necessary files to prep for installation #####
####################################################


####################################################
##### Start Configuration of Edge Browser Extension #####
####################################################
<# The following configurations entails:
Force install DCA extension (User cannot remove)
Force Pin Extension (User cannot unpin)

Create new key under HKEY_LOCAL_MACHINE\SOFTWARE\Policies\Microsoft\Edge\
Value of key will be: ExtensionInstallForcelist
detect if path exist, if not, create key #>

$ExtensionInstallKey = "HKLM:\Software\Policies\microsoft\edge\ExtensionInstallForcelist"
$TestPath_ExtensionInstallForcelist = test-path -path $ExtensionInstallKey 

if(-not($TestPath_ExtensionInstallForcelist)){
    
Write-Output "`n##### Start Configuration of Edge Browser Extension: Install DCA extension #####`n"
Write-Output "....Creating ExtensionInstallForcelist reg key...."

New-Item -Path $ExtensionInstallKey -force

# Add the string: "1" ; value: ifonlckhhfkfainkbngfbjhodbkeafbg;https://edge.microsoft.com/extensionwebstorebase/v1/crx to ExtensionInstallForcelist key
# If string already exist, the string below detects it and creates another string with value of +1.
# Credit: https://www.reddit.com/r/PowerShell/comments/f5w7t0/checking_if_a_registry_key_entry_exists/

$Global:Extensions = "1","ifonlckhhfkfainkbngfbjhodbkeafbg;https://edge.microsoft.com/extensionwebstorebase/v1/crx"
$Global:RegPath =  "HKLM:\Software\Policies\microsoft\edge\ExtensionInstallForcelist"

Function Get-RegKeyContent
    { 
    $Global:ExtensionValues = @()
    $Global:RegKeyContent = Get-ItemProperty -Path $RegPath | Get-Member -ErrorAction SilentlyContinue
    
    ForEach ($Item in $RegKeyContent)
        { If ( ($Item.MemberType -eq "NoteProperty") -and ($Item.Name -match '[0-99]') ) { $Global:ExtensionValues += $Item } }
    }

ForEach ($Extension in $Extensions)
    {
    Get-RegKeyContent
    If ($ExtensionValues -match $Extension) { }
    Else
        {
        $NewValue = ( ($ExtensionValues.Name | Measure-Object -Maximum).Maximum + 1 )
        New-ItemProperty -Path $RegPath -Name $NewValue -Value $Extension -PropertyType String -Force
        }
    }

}


# Once extension is installed, force it to be pinned
# Under HKEY_LOCAL_MACHINE\SOFTWARE\Policies\Microsoft\Edge\ , add the key "ExtensionSettings" 

$ExtensionSettingsKey = "HKLM:\SOFTWARE\Policies\Microsoft\Edge\ExtensionSettings\"
$TestPath_ExtensionSettings = test-path -path $ExtensionSettingsKey

if(-not($TestPath_ExtensionSettings)){

    Write-Output "`n##### Start Configuration of Edge Browser Extension: Force Pin Extension #####`n"
    Write-Output "....Creating ExtensionSettings reg key...."
    New-Item -Path $ExtensionSettingsKey -force

    # Create second key "ifonlckhhfkfainkbngfbjhodbkeafbg" under HKEY_LOCAL_MACHINE\SOFTWARE\Policies\Microsoft\Edge\ 
    New-item -Path "$($ExtensionSettingsKey)ifonlckhhfkfainkbngfbjhodbkeafbg" -Force -ErrorAction SilentlyContinue

    # add String: Toolbar_state value: force_shown under "ifonlckhhfkfainkbngfbjhodbkeafbg" key
    # String is case sensitive
    New-ItemProperty -Path "$($ExtensionSettingsKey)ifonlckhhfkfainkbngfbjhodbkeafbg" -Name "toolbar_state" -Value "force_shown" -PropertyType String -Force -ErrorAction SilentlyContinue

}

####################################################
##### End Configuration of Edge Browser Extension #####
####################################################

####################################################
##### Start copy of DCA shortcut to startup folder #####
####################################################

# Target the start up folder for ALL users. If a second user logs into the computer, they get DCA.
# This assumes that ALL users for that device will be using DCA, which may be the case in the future.

$AllUser_Startup = "C:\ProgramData\Microsoft\Windows\Start Menu\Programs\Startup"

Write-Output "`n##### Start Copy of DCA shortcut to startup folder for all users [$AllUser_Startup] #####`n"

Copy-Item -Path $FilePath_Shortcut -Destination "$AllUser_Startup" -Force -Verbose

####################################################
##### End copy of DCA shortcut to startup folder #####
####################################################

####################################################
##### Start configuration of [Disable auto update] #####
####################################################

$DCA_Update_Key = "HKLM:\Software\Microsoft\msdyn-companionapp\"
$TestPath_DCA_Update = test-path -path $DCA_Update_Key

if(-not($TestPath_DCA_Update)){
    Write-Output "`n ##### Disabling updates for DCA ##### `n"
    
 New-item -Path "HKLM:\Software\Microsoft\msdyn-companionapp\" -ErrorAction SilentlyContinue
 New-ItemProperty -Path "HKLM:\Software\Microsoft\msdyn-companionapp\" -Name "DisableUserUpdates" -Value "1" -PropertyType String -ErrorAction SilentlyContinue
}
####################################################
##### End configuration of [Disable auto update] #####
####################################################
<# 

Start Part 2: DCA Install

#>
####################################################


####################################################
##### Start DCA installation #####
####################################################
$MSIPath = "$LogPath\Microsoft.Dynamics.CompanionApp.Installer.MSI"

# Verify if file is there in the folder.
if(test-path $MSIPath){

  Write-Output "`nMicrosoft.Dynamics.CompanionApp.Installer.MSI found....Executing Installation`n" 

  # start installation by calling msiexec to trigger msi with custom parameters.
  $DCA_Install_Argument = "/i $MSIPath ALLUSERS=1 REBOOT=ReallySuppress /L*v $LogPath\DCA_App_Install.log /qn"

  Start-Process "msiexec.exe" -ArgumentList "$DCA_Install_Argument" -wait -Verbose

  # Verify that DCA is installed
  $DCA_Details = Get-ItemProperty HKLM:\Software\Microsoft\Windows\CurrentVersion\Uninstall\* , HKLM:\Software\Wow6432Node\Microsoft\Windows\CurrentVersion\Uninstall\* | Select-Object DisplayName, DisplayVersion, Publisher, InstallDate | Where-Object DisplayName -match "Desktop companion application"
  
  If ($DCA_Details){
    Write-Output "`n##### DCA is installed #####`n$($DCA_Details | Out-String)"
          }else{
            Write-Output "`n##### DCA is NOT installed #####`n"
                  }
                # End nested if statement 

}else{

    Write-Output "`n!! $MSIPath NOT found !! ....Exiting script`n"
    Stop-Transcript #End logging
    Exit 66 #close script

} # End If statement

####################################################
##### End DCA installation #####
####################################################

####################################################
##### Check DCA installation status code #####
####################################################

$errorstatus = Select-String -Path "$($LogPath)\DCA_App_Install.log"  -Pattern "error status:" | Out-String

if($errorstatus -match "error status: 0"){
    Write-Output "`n##### DCA installation is successful #####`n"
    Write-Output " ~~~~~~~~~~~~ "
    $errorstatus
    Write-Output " ~~~~~~~~~~~~ "

    # If install is successful, create file under %temp% to record it and delete "DCA_Install_Fail"
    Write-Output "`nInstallation is successful, recording status to C:\windows\temp\ folder with file: [DCA_Install_Success]`n "
    Remove-Item -Path "$env:WINDIR\Temp\DCA\DCA_Install_Fail" -Force -ErrorAction SilentlyContinue
    New-item -Path "$env:WINDIR\Temp\DCA" -Name "DCA_Install_Success" -ItemType File -Force

    
    Write-Output "~~~~~ DCA will start up when user sign in ~~~~~~"

}else{
    Write-Error "`n##### DCA installation is NOT successful. Please check if current installation is preventing new install. #####`n"
    Write-Output " ~~~~~~~~~~~~ "
    $errorstatus
    Write-Output " ~~~~~~~~~~~~ "
    
    # If install fails - remove the success file, create "DCA_Install_fail" file
    Write-Output "`nInstallation is unsuccessful, recording status to C:\windows\temp\ folder with file: [DCA_Install_Fail]`n "
    Remove-Item -Path "$env:WINDIR\Temp\DCA\DCA_Install_Success" -Force -ErrorAction SilentlyContinue
    New-item -Path "$env:WINDIR\Temp\DCA" -Name "DCA_Install_Fail" -ItemType File -Force -ErrorAction SilentlyContinue
    # terminate script
    exit 66
}

####################################################
##### End DCA status check #####
####################################################


####################################################
##### End DCA install#####
####################################################

# End logging
Stop-Transcript

