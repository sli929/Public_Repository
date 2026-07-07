# Install latest version of citrix workspace client with the following arguments:

# Powershell
# Save download file to c:\windows\temp\
$Url = "https://downloadplugins.citrix.com/Windows/CitrixWorkspaceApp.exe"
$Target = "$env:SystemRoot\Temp\CitrixWorkspaceApp.exe"
$argument = "/silent STORE0=`"Red929;https://Red929.company.com;ON;Red929`" /NoReboot EnableCEIP=False "
# require User logged in
invoke-webrequest -Uri $Url -OutFile $Target  -Verbose
# User not logged in - Invoke-WebRequest -Uri $Url -OutFile $Target -Verbose
start-sleep -seconds 5


# Execute .exe
start-process -PassThru -FilePath $Target -ArgumentList $argument | Wait-Process -verbose

#Copy over shortcut
$Public_Desktop = [Environment]::GetFolderPath("CommonDesktopDirectory")
Copy-Item "C:\ProgramData\Microsoft\Windows\Start Menu\Programs\Citrix Workspace.lnk"  -Destination "$Public_Desktop"

<# Troubleshooting:
Start-process keeps running and does not terminate when post installation of citrix is complete...
PS will not continue due to existing child processes for citrix workspace.

When using the -Wait parameter, Start-Process waits for the process tree (the process and all its descendants) to exit before returning control. 
This is different than the behavior of the Wait-Process cmdlet, which only waits for the specified processes to exit.

To resolve this issue, pipe the command over to "wait-process"
#>


<# Removal
$Target1 = "$env:SystemRoot\Temp\CitrixWorkspaceApp.exe"
$Arguments1 = '/Uninstall'
# Execute install of .exe
Start-Process -FilePath $Target1 -ArgumentList $Arguments1 -Wait -Verbose
#>
