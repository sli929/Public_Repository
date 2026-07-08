<#
The following script is intended for Azure monitor agent client install.

Part 1: Clean up existing Azure Monitor agent. Remove application if detected. 

Part 2: Start installation of the latest Azure monitor agent application.
        The url to invoke is "https://go.microsoft.com/fwlink/?linkid=2192409". This pulls the LATEST version!

Part 3: Implement scheduled task to only send logs during specific hours.
        Monday through Saturday
        Start: 7 AM
        Stop: 8:30 PM

###############################
Notes:
**  This script has no version control as the latest version will be installed

**  User does not need to be logged in for script to run

**  Removes all remains of existing AMA before starting installation of latest version
    **** If service is still present post removal - the device needs to reboot to finalize uninstallation ****
    ** If AMA service is not found - proceed with installation

**  Script finds all uninstall strings on device and trigger removal with its GUID
    Then verification check starts after removal process to make sure all versions are removed from the device.

#>

# Declare parameters for scheduled task creation
param(
    [string]$ServiceName        = "AzureMonitorAgent",
    [string[]]$Days             = @("Monday","Tuesday","Wednesday","Thursday","Friday","Saturday"),
    [datetime]$StartTime        = "07:00am",
    [datetime]$StopTime         = "08:30pm",
    [int]$ExecutionLimitHrs     = 2,
    [int]$RestartCount          = 3,
    [int]$RestartIntervalMin    = 15
)

####################################################
##### Start Logging #####
####################################################
# Establish log folder and logging

$LogPath = "C:\Temp\AMA\"
$LogPath_Uninstall = "$($LogPath)Uninstall"
$LogPath_Install =  "$($LogPath)Install"


# If AMA folder exist - purge all items in it. Then recreate the folders.
if(Test-Path -path $LogPath){
    Write-Output "##### Cleaning up folder for uninstallation and installation logs #####"

    Remove-Item "$($LogPath)\*" -Recurse -Force -ErrorAction SilentlyContinue -Verbose

    Write-Output "`n##### AMA folder already exist....... recreating Uninstall and Install folders #####"
  
    New-Item -Path $LogPath_Uninstall -ItemType "Directory" -force
    New-Item -Path $LogPath_Install -ItemType "Directory" -force

}else{
# If AMA folder does not exist, recreate folder structure
    Write-Output "`n##### AMA folder does not exist....... recreating AMA, Uninstall and Install folders #####"

    New-Item -Path $LogPath -ItemType "Directory"
    New-Item -Path $LogPath_Uninstall -ItemType "Directory"
    New-Item -Path $LogPath_Install -ItemType "Directory"

}

# start logging
$LogFile = "$LogPath\AMA-PSsession-$(Get-Date -Format 'MMddyyyy-HHmmss').log"
Start-Transcript -Path $LogFile -Force


##########################
### Declare variable
##########################
# declare shared variable
$script:Errorcounter = 0

##########################
### Declare function
##########################
function AMA_StatusCode_Check_Uninstall {

    # Grab the child logs
    $Uninstall_Logs = Get-ChildItem -Path $LogPath_Uninstall -Filter "*_Uninstall.log"
    
    foreach($item in $Uninstall_Logs){
    
        # Obtain the error log name first
        $LogName = $item.name
    
        # Grab version number
        $AMA_Version = [regex]::Match($LogName, '\d+(\.\d+)+').Value
    
        # Grab status code string from the error log
        $errorstatus = Select-String -Path "$LogPath_Uninstall\$LogName"  -Pattern "error status:" | Out-String
    
        
        if($errorstatus -match "error status: 0"){
            Write-Warning "`n##### AMA uninstallation is successful for Azure monitor agent version $AMA_Version #####`n"
            Write-Output " ~~~~~~~~~~~~~~ Start Status message for $AMA_version ~~~~~~~~~~~~~~ "
            $errorstatus
            Write-Output " ~~~~~~~~~~~~~~ End Status message for $AMA_version ~~~~~~~~~~~~~~ "
        
        }else{
            Write-Error "`n##### AMA uninstallation is NOT successful for Azure monitor agent version $AMA_version. Please check if any conflict in existing package... #####`n"
            Write-Output " ~~~~~~~~~~~~~~ Start Status message for $AMA_version ~~~~~~~~~~~~~~ "
            $errorstatus
            Write-Output " ~~~~~~~~~~~~~~ End Status message for $AMA_version ~~~~~~~~~~~~~~ "
            $script:ErrorCounter++
            
            Write-Warning "Status Error Counter is: $script:ErrorCounter"

            }
        }# end for each loop

    }# End Function [AMA_StatusCode_Check_Uninstall]

function AMA_StatusCode_Check_install {

    # Grab the child logs
    $install_Logs = Get-ChildItem -Path $LogPath_install -Filter "*_install.log"
    
    foreach($item in $install_Logs){
    
        # Obtain the error log name first
        $LogName = $item.name

        # Grab status code/version info string from the log
        $Install_Details = Select-String -Path "$Logpath_install\$LogName"  -Pattern "error status:" | Out-String
        $Pattern = "Product Version:\s*(?<Version>[\d\.]+)"

        if ($Install_Details -match $Pattern) {
            # Access the extracted value directly by its named group key
            $Version = $Matches['Version']
            Write-Output "Extracted Version: $Version"
        }

        if($Install_Details -match "error status: 0"){
            Write-Warning "`n##### AMA installation is successful for Azure monitor agent version $Version #####`n"
            Write-Output " ~~~~~~~~~~~~~~ Start Status message ~~~~~~~~~~~~~~ "
            $Install_Details
            Write-Output " ~~~~~~~~~~~~~~ End Status message ~~~~~~~~~~~~~~ "
        
        }else{
            Write-Error "`n##### AMA installation is NOT successful for Azure monitor agent version $Version. Please check if any conflict in existing package... #####`n"
            Write-Output " ~~~~~~~~~~~~~~ Start Status message ~~~~~~~~~~~~~~ "
            $Install_Details
            Write-Output " ~~~~~~~~~~~~~~ End Status message ~~~~~~~~~~~~~~ "
            $script:ErrorCounter++
            
            Write-Warning "Status Error Counter is: $script:ErrorCounter"

            }
        }# end for each loop

    }# End Function [AMA_StatusCode_Check_Install]
    
function AMA_Folder_Removal {

        ###########################
        # Remove folder spawn by AMA installation
        ###########################
        
        # AMA installation folder: "C:\Program Files\Azure Monitor Agent\"
        $AMA_Install_Folder = "C:\Program Files\Azure Monitor Agent\" 
        
        # Verify folder path
        if(-not (Test-Path "$AMA_Install_Folder") ){
            
            Write-Warning "~~~~~~ AMA installation folder [C:\Program Files\Azure Monitor Agent\] not detected ~~~~~~`n"
        }
        
        # If path detected - remove directory
        if(Test-Path "$AMA_Install_Folder"){
        
            Write-Warning "~~~~~ [$AMA_Install_Folder] folder detected ~~~~~`n"
        
            Get-ChildItem "C:\Program Files\"  |  Where-Object { $_.Name -match 'Azure Monitor Agent'} | Remove-Item -Force -Verbose -Recurse
        
                # Verify removal
                $AMA_Install_Folder_Test = Test-Path -Path "C:\Program Files\Azure Monitor Agent\"
        
                if($AMA_Install_Folder_Test -eq $false){
                
                Write-Warning "`n~~~~~ The following folder [C:\Program Files\Azure Monitor Agent\] is removed successfully ~~~~~`n"
            
                }else{
                    Write-Warning "!!! Removal of folder [$AMA_Install_Folder] failed. Please try again !!!"
                }
        }# End If
        
        ###########################
        # AMA data folder: C:\Resources\Azure Monitor Agent\
       
        $AMA_Data_Folder = "C:\Resources\Azure Monitor Agent\"
        
        # Verify path of folder
        if(-not (test-path "$AMA_Data_Folder") ){
            
            Write-Warning "~~~~~~ AMA Data folder [C:\Resources\Azure Monitor Agent\] not detected ~~~~~~`n"
        }
        
        # If path detected - remove directory
        
        if(test-path "$AMA_Data_Folder"){
        
            Write-Warning "~~~~~ $AMA_Data_Folder folder detected ~~~~~`n"
        
            Get-ChildItem "C:\Resources\"  |  Where-Object { $_.Name -match 'Azure Monitor Agent'} | Remove-Item -Force -Verbose -Recurse
        
                # Verify removal
                $AMA_Data_Folder_Test = Test-Path -Path $AMA_Data_Folder
        
                if($AMA_Data_Folder_Test -eq $false ){
                
                Write-Warning "`n~~~~~ The following folder [C:\Resources\Azure Monitor Agent\] is removed successfully ~~~~~`n"
            
                }else{
                    Write-Warning "!!! Removal of folder [$AMA_Data_Folder] failed. Please try again !!!"
                }
        }#End If
        
        ###########################
} # End function [AMA_Folder_Removal]

function AMA_Removal{
            ####### Remove all versions of AMA - [current and existing] ####### 

            $AppName = "Azure monitor agent"
            $AppInfo = Get-ItemProperty HKLM:\Software\Microsoft\Windows\CurrentVersion\Uninstall\* ,HKLM:\Software\Wow6432Node\Microsoft\Windows\CurrentVersion\Uninstall\* | Select-Object DisplayName, UninstallString, DisplayVersion | where-object {$_.DisplayName -like "*$AppName*"}

            # Find all the uninstall strings matching application name. Trigger uninstall for all.
            foreach($item in $AppInfo){

                try{
                    # Remove via GUID
                    $GUID = [regex]::Match($item.UninstallString, '\{.*?\}').Value
                    $version = $item.DisplayVersion
                        
                    Write-Output "`n### Azure monitor Agent Version $($item.DisplayName) detected.... Current Version: $Version .....Starting removal process with uninstall $GUID ###"
                    $Uninstall_Parameter = "/qn /norestart /X$($GUID) /L*v $LogPath_Uninstall\AMA_Version_$($version)_Uninstall.log /qn"
                    Start-Process "msiexec.exe" -ArgumentList "$Uninstall_Parameter" -wait -Verbose
                        
                }catch{
                        # get terminating error
                        Write-Warning "A critical terminating exception occurred during execution:"
                        Write-Output $_.exception.message
                        exit 66
                    } # End catch - nested try [app GUID removal]
                }# End foreach
}

####################################################
##### Part 1: Start Application Removal #####
####################################################

Write-Output "#####################`
Starting AMA removal`
#####################"

try{

## Declare service/processes
$AMA_Service = Get-Service -Name AzureMonitorAgent -ErrorAction SilentlyContinue

# If AMA service exist - proceed to stop service and uninstall application.
if($AMA_Service){

    Write-Warning "Azure monitor agent service detected.....Stopping service............"
    Stop-Service -Name ($AMA_Service.Name) -Force -Verbose -ErrorAction SilentlyContinue
 
# IF service has stopped
    if ((Get-Service AzureMonitorAgent).Status -eq "Stopped") {
        Write-Output "AzureMonitorAgent service stopped successfully ------> Passed"
        # start removal
        AMA_Removal
    }else{
        # If service is NOT stopped - attempt uninstallation anyway
        write-warning "UNABLE TO STOP AZURE MONITOR AGENT SERVICE!! ------> Failed. Attempting uninstallation anyway......"
        AMA_Removal    
    }

        }else{
            # Service not found  Attempt installation
            Write-Warning "###### Azure monitor service not found........ Proceeding with installation......... ######`n"
            
        }

    }catch{
        Write-Warning "A critical terminating exception occurred during execution:"
        Write-Output $_.Exception.Message
        exit 66
    } #End catch - first try [stop-service]

####################################
# Post application removal
####################################

# Start status code check
AMA_StatusCode_Check_Uninstall

# If all the uninstall logs status code exit with status code: 0 - uninstallation is successfully - proceed with file clean up
# The uninstallation process already removes the associated files/folders if working properly. However, there is no risk to rerun it again.
if($script:Errorcounter -eq 0){

    Write-Output "`n######## Starting AMA file cleanup ########`n"
    AMA_Folder_Removal

}else{

    Write-Output "`n######## Status code ErrorCounter: $script:Errorcounter ########"
    Write-Output "`n######## Skipping file cleanup ########`n"
    Write-Warning "Encountered status code error during uninstallation......Terminating script....."
    Exit 66
}

####################################################
##### End Application Removal #####
####################################################



####################################################
##### Part 2: Start Application Installation #####
####################################################


    ####################################################
    # Start Microsoft visual c++ detection and installation
    ####################################################

    # Detect if device has Microsoft visual c++ (2015-2022) installed

    # Look for [string: Version] under registry to determine if Microsoft visual c++ redistribution is installed.
    # Version check is for is 14.0 for Visual Studio 2015, 2017, 2019, and 2022 (Modern bundles only)

    # 64 bit install on a 64 bit system
    $VersionBuildx64 = Get-ItemProperty HKLM:\SOFTWARE\Microsoft\VisualStudio\14.0\VC\Runtimes\X64 -ErrorAction SilentlyContinue
    # 32 bit install
    $VersionBuildx86 = Get-ItemProperty HKLM:\SOFTWARE\Wow6432Node\Microsoft\VisualStudio\14.0\VC\Runtimes\X86 -ErrorAction SilentlyContinue


    if($VersionBuildx64 -and $VersionBuildx86){

    Write-Warning "Microsoft Visual C++ Redistributable is already installed:`n
    #####################################################
    x64bit Microsoft visual c++ current version is $($VersionBuildx64.version)
    x86bit Microsoft visual c++ current version is $($VersionBuildx86.version)
    #####################################################
    
    "

    }else{

    Write-Output @"
    #####################################################################
    Starting installation of latest version of MSVC++ Redistributable
    #####################################################################
"@
    Write-Output "Enforcing TLS 1.2 for secure web requests..." 
    [Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12

    Install-PackageProvider -Name NuGet -Confirm:$false -Force
    Install-Module -Name VcRedist -Confirm:$false -Force
    Import-Module VcRedist
    Install-VcRedist -VcList (Get-VcList | Save-VcRedist -Path "$LogPath_install") -Silent

    Start-Sleep 20
    
    # Confirm installation
    $vc_redist_installed = Get-ItemProperty HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall\* |
    Where-Object {$_.DisplayName -like "Microsoft Visual C++*"} |
    Select-Object DisplayName, DisplayVersion

    Write-Output "Microsoft Visual C++ Redistributable(s) are installed:"

    $vc_redist_installed | Format-Table -AutoSize
    }

    ####### End Microsoft visual c++ detection and installation ######

    ########################################################################
    ##### Start Gathering the necessary files to prep for installation #####
    ########################################################################

    Write-Output @"

    #####################################################################
    Grabbing the latest version of azure monitor agent MSI file for install
    #####################################################################
    
"@

    Try{
        # Invoke-webrequest
        # Will install latest AMA version
        $DownloadURL_MSI = "https://go.microsoft.com/fwlink/?linkid=2192409"
        $FilePath_MSI = "$LogPath_install\AzureMonitorAgentClientSetup.msi"
        Write-Output "`nStart download of AMA MSI with Invoke-WebRequest`n"
        Invoke-WebRequest -Uri $DownloadURL_MSI -OutFile $FilePath_MSI -Verbose
        
        }catch{
            # If terminating error occurs, catch message. Fall back and re try a different link with start-bitstransfer
            Write-Output "Error: $($_.Exception.Message)"
            Write-Output "`n##### Falling back to download with Start-BitsTransfer #####"
            Start-BitsTransfer -Source $DownloadURL_MSI -Destination $FilePath_MSI -Verbose -Description "AMA MSI Installer"
        
        }

        ##### Post Download #####
        # Verify if file is there in the folder
        
        if(test-path $FilePath_MSI){
            Write-Output "`nDownload of AMA installer complete....File saved to $FilePath_MSI`n" 
        
            
        }else{
            write-error "`n!! $FilePath_MSI shortcut NOT found !! ....Exiting script`n"
            Stop-Transcript #End logging
            Exit 66 #close script
        
        } #End If statement
        
    ############# End download of AMA MSI installer #############
    

    ####################################################
    ############### Start AMA installation #############
    ####################################################

    Write-Output @"
    ######################################
    Start Azure monitor agent installation 
    ######################################
"@
    # Verify if file is there in the folder.
    if(test-path $FilePath_MSI){

    Write-Output "`nAzure monitor agent installer MSI found....Executing Installation`n" 

    # start installation by calling msiexec to trigger msi with custom parameters.
    $AMA_Install_Argument = "/i $FilePath_MSI ALLUSERS=1 /qn /norestart /L*v $LogPath_install\AMA_APP_Install.log /qn"

    Start-Process "msiexec.exe" -ArgumentList "$AMA_Install_Argument" -wait -Verbose

    # Verify that AMA is installed
    $AMA_Details = Get-ItemProperty HKLM:\Software\Microsoft\Windows\CurrentVersion\Uninstall\* , HKLM:\Software\Wow6432Node\Microsoft\Windows\CurrentVersion\Uninstall\* | Select-Object DisplayName, DisplayVersion, Publisher, InstallDate | Where-Object DisplayName -match "Azure Monitor Agent"
    
    If ($AMA_Details){
        Write-Output "`n##### Azure monitor agent is installed #####`n$($AMA_Details | Out-String)"
            }else{
                Write-Output "`n##### Azure monitor agent is NOT installed #####`n"
                    }
                    # End nested if statement 

    }else{

        Write-Output "`n!! $FilePath_MSI NOT found !! ....Exiting script`n"
        Stop-Transcript #End logging
        Exit 66 #close script

    } # End If statement

    ############# End Installation of AMA #############

####################################################
##### Part 2: End Application Installation #####
####################################################

####################################
# Post application install
####################################

###### Start status code check ######
AMA_StatusCode_Check_install

# If all the install logs status code exit with status code: 0 - installation is successfully - proceed with script
if($script:Errorcounter -eq 0){

Write-Output @"

#####################################################################
Azure Monitor Agent Installation Successful!

#####################################################################
Application : $($AMA_Details.DisplayName)
Version     : $($AMA_Details.DisplayVersion)
Publisher   : $($AMA_Details.Publisher)
InstallDate : $($AMA_Details.InstallDate)
#####################################################################

"@


}else{

    Write-Output "`n######## Status code ErrorCounter: $script:Errorcounter ########"
    Write-Warning "Encountered status code error during installation......Terminating script....."
    Exit 66
}

###### Check if service is running ######

## Declare service/processes
$AMA_Service = Get-Service -Name AzureMonitorAgent -ErrorAction SilentlyContinue

#  If azure monitor agent service exist
if($AMA_Service){

    Write-Warning "Azure monitor agent service detected.....checking service............"

# Verify that the service is running
    if ((Get-Service AzureMonitorAgent).Status -eq "Running") {

        Write-Output "AzureMonitorAgent service running successfully ------> Passed"
            
    }else{

        Write-Output "AzureMonitorAgent service is currently not running ......Attempt service startup........"
        Start-Service -Name AzureMonitorAgent -Verbose -PassThru

        if ((Get-Service AzureMonitorAgent).Status -eq "Running") {

            Write-Output "Attempt successfully - AzureMonitorAgent service running successfully ------> Passed"

        }else{

Write-Warning @"

#####################################################################
!! Azure Monitor Agent Service is not running post installation !!

Please restart the device and check again
#####################################################################

"@

        }
    }
}# End IF


####################################################
##### Part 3: Start scheduled task deployment #####
####################################################
<#
    Creates two scheduled tasks:
      - StartAzureMonitorAgent : starts the AMA service Mon-Sat at 7:00 AM
      - StopAzureMonitorAgent  : stops the AMA service Mon-Sat at 8:30 PM
    Both tasks run as SYSTEM, wake the computer if needed, retry on failure (3x / 15 min),
    and are capped at a 2-hour execution window.

    Must be run with administrative privileges.
#>

$ErrorActionPreference = 'Stop'

function New-AMAScheduledTask {
    param(
        [Parameter(Mandatory)][string]$TaskName,
        [Parameter(Mandatory)][ValidateSet("start","stop")][string]$Action,
        [Parameter(Mandatory)][datetime]$Time,
        [Parameter(Mandatory)][string[]]$Days,
        [Parameter(Mandatory)][string]$ServiceName,
        [Parameter(Mandatory)][int]$ExecutionLimitHrs,
        [Parameter(Mandatory)][int]$RestartCount,
        [Parameter(Mandatory)][int]$RestartIntervalMin
    )

    Write-Warning "`n#####################################################################`n!! Creating scheduled task [$TaskName] !!`n#####################################################################`n"

    $taskAction = New-ScheduledTaskAction -Execute "C:\Windows\System32\cmd.exe" `
        -Argument "/c net $Action $ServiceName"

    $taskTrigger = New-ScheduledTaskTrigger -Weekly -DaysOfWeek $Days -At $Time

    $principal = New-ScheduledTaskPrincipal -UserId "SYSTEM" -LogonType ServiceAccount -RunLevel Highest

    # Core Settings:
    #   1. Wake computer to run task
    #   2. Run as soon as possible if missed
    #   3. Stop if it runs longer than $ExecutionLimitHrs
    #   4. Retry on failure: $RestartCount attempts, every $RestartIntervalMin minutes
    $settings = New-ScheduledTaskSettingsSet `
        -ExecutionTimeLimit (New-TimeSpan -Hours $ExecutionLimitHrs) `
        -WakeToRun `
        -DontStopIfGoingOnBatteries `
        -AllowStartIfOnBatteries `
        -StartWhenAvailable `
        -RestartCount $RestartCount `
        -RestartInterval (New-TimeSpan -Minutes $RestartIntervalMin)

    $description = "Runs {0} at {1} with wake, missed-start recovery, failure retries, and a {2}-hour limit. Task to {3} the {4} service." -f `
        ($Days -join '-'), $Time.ToString("h:mmtt"), $ExecutionLimitHrs, $Action, $ServiceName

    Register-ScheduledTask -TaskName $TaskName -Action $taskAction -Trigger $taskTrigger `
        -Settings $settings -Principal $principal -Description $description -Force

    Write-Output "`nTask [$TaskName] registered successfully.`n"
}

####################################################
##### Part 3: Start scheduled task deployment #####
####################################################

# Confirm the target service actually exists 
if (-not (Get-Service -Name $ServiceName -ErrorAction SilentlyContinue)) {
    Write-Output "Service '$ServiceName' was not found on this machine."
}

try {

    New-AMAScheduledTask -TaskName "StartAzureMonitorAgent" -Action "start" -Time $StartTime `
        -Days $Days -ServiceName $ServiceName -ExecutionLimitHrs $ExecutionLimitHrs `
        -RestartCount $RestartCount -RestartIntervalMin $RestartIntervalMin

    New-AMAScheduledTask -TaskName "StopAzureMonitorAgent" -Action "stop" -Time $StopTime `
        -Days $Days -ServiceName $ServiceName -ExecutionLimitHrs $ExecutionLimitHrs `
        -RestartCount $RestartCount -RestartIntervalMin $RestartIntervalMin

    ########################################
    ############ Modify service ############
    ########################################

    Write-Warning "`n#####################################################################`n!! Setting $ServiceName service startup to Manual !!`n#####################################################################`n"

    Set-Service -Name $ServiceName -StartupType Manual -Verbose -ErrorAction SilentlyContinue

}
catch {
    Write-Output "!!! Scheduled task deployment encountered an error !!!"
    Write-Error -Message $_.Exception.Message
    throw
}


####################################################
##### End script #####
####################################################

Write-Output @"

#################################
        Script Complete
#################################

"@

# end logging
Stop-Transcript

