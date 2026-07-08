<#

The following script finds and repair Microsoft Visual C++ Redistributable for computer with a mismatch version of MSVCP140.dll.
The root cause of msvcp140.dll rollback appears to come from fiery printer driver.

The following script can gather details on crashes related to crashes caused by MSVCP140 rollback.

##########################################

MSVCP140.dll is a "library" file that contains a set of instructions and routines that other programs need to run correctly on Windows.
It is a core component of the Microsoft Visual C++ Redistributable for Visual Studio 2015–2022.

🔍 What does it actually do?
When developers write software using the C++ programming language in Microsoft Visual Studio, they often use "pre-made" blocks of code to handle basic tasks (like processing data or managing memory).
Instead of including those blocks of code inside every single application, Microsoft puts them in a shared file—the MSVCP140.dll.
	• MS = Microsoft
	• VC = Visual C++
	• P = Part of the C++ Standard Library
140 = Version 14.0 (which covers Visual Studio 2015 through 2022)

##########################################

What happens if the version of MSVCP140.dll is different from the version thats installed?
    Application may fail to open with the following error on event viewer:
    
    Faulting application name: AzureMonitorAgentService.exe, version: 47.1.6.0, time stamp: 0x68c31afd
    Faulting module name: MSVCP140.dll, version: 14.50.35719.0, time stamp: 0x5a39fef7
    Exception code: 0xc0000005
    Fault offset: 0x000000000001b93c
    Faulting process id: 0x4430
    Faulting application start time: 0x1DC6F7244684F2A
    Faulting application path: C:\Program Files\Azure Monitor Agent\Service\AzureMonitorAgentService.exe
    Faulting module path: C:\WINDOWS\SYSTEM32\MSVCP140.dll
    Report Id: ff361e42-e2d6-446e-b2ac-1b91f925635d
    Faulting package full name: 
    Faulting package-relative application ID: 

    Faulting application name: ksmNotifier.exe, version: 8.15.0.0, time stamp: 0x682c4361
    Faulting module name: MSVCP140.dll, version: 14.13.26020.0, time stamp: 0x5a39fef7
    Exception code: 0xc0000005
    Fault offset: 0x000000000001b93c
    Faulting process id: 0x0x1060
    Faulting application start time: 0x0x1DC67B0837C3C5D
    Faulting application path: C:\Program Files\Common Files\Omnissa\KSM Notifier\ksmNotifier.exe
    Faulting module path: C:\windows\SYSTEM32\MSVCP140.dll
    Report Id: dc237273-84e2-4b16-8c27-4a961fd7cea5
    Faulting package full name: 
    Faulting package-relative application ID:

    Faulting application name: OUTLOOK.EXE, version: 16.0.19231.20156, time stamp: 0x68d9c586
    Faulting module name: MSVCP140.dll, version: 14.13.26020.0, time stamp: 0x5a39fef7
    Exception code: 0xc0000005
    Fault offset: 0x000000000001b93c
    Faulting process id: 0x0x773C
    Faulting application start time: 0x0x1DC37BEDE835A1F
    Faulting application path: C:\Program Files\Microsoft Office\root\Office16\OUTLOOK.EXE
    Faulting module path: C:\windows\SYSTEM32\MSVCP140.dll
    Report Id: ae1592c2-5afb-42b8-a18c-61f687dc65dd
    Faulting package full name: 
    Faulting package-relative application ID: 


#>
##########################################
 # In order to determine if the machine encounters any problems with MSVCP140.dll which impact application launch, a scan for event 1000 in event viewer is the most reliable way.

# Retrieve information from event viewer:

# Get event ID 1000 information from "Application" folder
# Search for event 1000 that matches keyword "MSVCP140.DLL", once found, expand details. Only pull 5 event with most recent timeframe
$MSVCP140_Log = Get-winevent -LogName "Application" -FilterXPath "*[System[EventID=1000]]" -MaxEvents 5 | Where-Object {$_.Message -match 'MSVCP1400.dll'} | Select-Object -ExpandProperty Message -ErrorAction SilentlyContinue


#If the faulting module is found under event 1000 - trigger the following:
if($MSVCP140_Log){
    
    ####################################################
    # Establish log folder and logging
    Write-Output "##### Creating Log folder #####"

    $LogPath = "C:\Temp\MSVCP"
    $TestPath = Test-Path -Path $LogPath
    if($TestPath -eq $false ){
        New-Item -Path $LogPath -ItemType "Directory"
    }
    # start logging
    $LogFile = "$LogPath\MSVCP_logs-$(Get-Date -Format 'MMddyyyy-HHmmss').log"
    Start-Transcript -Path $LogFile -Force
    ####################################################

    Write-Warning "Event 1000 found for MSVCP140.DLL causing application to hang......."
    Write-Output "`n####################`n"
    $MSVCP140_Log
    Write-Output "`n####################`n"
    

    # Check the version of MSVCP140.dll, MSVCP140.dll_1, MSVCP140.dll_2
    $DLLVersion  = (Get-Item -Path "C:\Windows\System32\MSVCP140.dll").VersionInfo.FileVersion
    $DLLVersion_1  = (Get-Item -path "C:\Windows\System32\MSVCP140_1.dll").VersionInfo.FileVersion
    $DLLVersion_2 = (Get-Item -Path "C:\Windows\System32\MSVCP140_2.dll").VersionInfo.FileVersion

    # output result
    Write-Output "The current version of .DLL files for MSVCP140:`n MSVCP140.DLL = $DLLVersion`n MSVCP140_1.DLL = $DLLVersion_1`n MSVCP140_2.DLL = $DLLVersion_2`n"
    

    ####################################################
    ##### Start Microsoft visual c++  repair #####
    ####################################################

        Write-Output "`n########## Deploying Microsoft Visual C++ Redistributable repair....... ##########`n"
        Install-PackageProvider -Name NuGet -Confirm:$false -Force -ErrorAction SilentlyContinue
        Install-Module -Name VcRedist -Confirm:$false -Force 
        Import-Module VcRedist

        # Retrieve package and save it to $logpath
        Get-VcList | Save-VcRedist -Path "$LogPath"

        Start-Sleep 10

        ### Start repair ###
        # Locate the .exe within the folder for x64 install.
        $x64Exe = Get-ChildItem -Path $LogPath -Include *.exe -Recurse | Where-Object Name -Match "x64"
        $command = "/repair /quiet /norestart /log $logpath\MSVCP_Repair.log"
        Start-Process -FilePath "$($x64exe.FullName)" -ArgumentList $command -Wait
        
        ### Confirm installation ###
        $vc_redist_installed = Get-ItemProperty HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall\* |
        Where-Object {$_.DisplayName -like "Microsoft Visual C++*"} |
        Select-Object DisplayName, DisplayVersion

        Write-Output "########## Microsoft Visual C++ Redistributable(s) are installed: ##########"
        $vc_redist_installed | Format-Table -AutoSize

    ####################################################
    ##### End Microsoft visual c++ repair #####
    ####################################################

    ### Recheck the version of MSVCP140.DLL ###
    $DLLVersion  = (Get-Item -Path "C:\Windows\System32\MSVCP140.dll").VersionInfo.FileVersion
    $DLLVersion_1  = (Get-Item -path "C:\Windows\System32\MSVCP140_1.dll").VersionInfo.FileVersion
    $DLLVersion_2 = (Get-Item -Path "C:\Windows\System32\MSVCP140_2.dll").VersionInfo.FileVersion

    # output result
    Write-Output "##### Post Changes #####`n The current version of .DLL files for MSVCP140:`n MSVCP140.DLL = $DLLVersion`n MSVCP140_1.DLL = $DLLVersion_1`n MSVCP140_2.DLL = $DLLVersion_2`n"

    #end logging
    Stop-Transcript

    #Grab transcript and clean up the header.
    $Log = Get-ChildItem -Path "$LogPath" | Where-Object Name -Match "MSVCP_logs-" -ErrorAction SilentlyContinue
    # Requires the full path. Use "fullname" properties
    (get-content $Log.FullName -ReadCount 3 | select -skip 6) | set-Content -Path "$($Log.fullname)" -Force -ErrorAction SilentlyContinue

}








