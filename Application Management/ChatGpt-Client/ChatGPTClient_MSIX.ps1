<#
 Offline install for chatgpt client MSIX package
 https://learn.chatgpt.com/docs/enterprise/windows-deployment?deployment=other
 
Troubleshoot:
Remove-AppxPackage: The 'Remove-AppxPackage' command was found in the module 'Appx', but the module could not be loaded due to the following error: [Operation is not supported on this platform. (0x80131539)]
    Run terminal as admin to remove it for all users - "Remove-AppxPackage -Package "OpenAI.Codex_26.930.3748.0_x64__2p2nqsd0c76g0" -allusers"


Append "-logpath" to add-AppxProvisionedPackage for troubleshooting and debugging. All logs will be saved to %WINDIR%\Logs\Dism\dism.log by default. Default log level is 3 (3 = Errors, warnings, and information)

#>
####################################################

####################################################
##### Start Logging #####
####################################################
# Clean up existing log folder and establish logging
# All codex installation component into OpenAICodex\Install folder.

$LogPath = "C:\Temp\OpenAICodex\Install"
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
$LogFile = "$LogPath\OpenAICodex_PS_Install_logs-$(Get-Date -Format 'MMddyyyy-HHmmss').log"
Start-Transcript -Path $LogFile -Force


####################################################
##### Start Gathering the necessary files to prep for installation #####
####################################################

############# Start download of chatgpt codex MSIX and license XML#############

Try{
    # Start-bitstransfer works well for bigger files
    $DownloadURL_MSIX = "https://persistent.oaistatic.com/codex-app-prod/ChatGPT-x64.msix"
    $FilePath_MSIX = "$LogPath\ChatGPT-x64.msix"

    $DownloadURL_XML = "https://persistent.oaistatic.com/codex-app-prod/ChatGPT-License.xml"
    $FilePath_XML = "$LogPath\ChatGPT-License.xml"
    
    Write-Output "`nStart download of ChatGPT-x64 MSIX with Start-BitsTransfer`n"
    Start-BitsTransfer -Source $DownloadURL_MSIX -Destination $FilePath_MSIX -Verbose -Description "ChatGPT MSIX" -ErrorAction stop

    Write-Output "`nStart download of offline license with Start-BitsTransfer`n"
    Start-BitsTransfer -Source $DownloadURL_XML -Destination $FilePath_XML -Verbose -Description "ChatGPT License" -ErrorAction stop

        
    }catch{
        # If terminating error occurs, catch message. Fall back and re try
        Write-Output "Error: $($_.Exception.Message)"
    
        Write-Output "`n##### Falling back to download with Invoke-webRequest for MSIX #####"
        Invoke-WebRequest -Uri $DownloadURL_MSIX -OutFile $FilePath_MSIX -Verbose

        Write-Output "`n##### Falling back to download with Invoke-webRequest for offline license #####"
        Invoke-WebRequest -Uri $DownloadURL_XML -OutFile $FilePath_XML -Verbose
    }
    
    ##### Post Download #####
    # Verify if file is there in the folder
    
    if(test-path $FilePath_MSIX){
        Write-Output "`nChatGPT MSIX download complete....File saved to $FilePath_MSI`n" 
    
        
    }else{
        write-error "`n!! $FilePath_MSIX MSIX NOT found !! ....Exiting script`n"
        Stop-Transcript #End logging
        Exit 66 #close script
    
    } #End If statement
      
    if(test-path $FilePath_XML){
        Write-Output "`nChatGPT License download complete....File saved to $FilePath_XML`n" 
    
        
    }else{
        write-error "`n!! $FilePath_XML License NOT found !! ....Exiting script`n"
        Stop-Transcript #End logging
        Exit 66 #close script
    
    } #End If statement 

############# End download of ChatGPT-x64 MSIX and license XML #############
####################################################
##### End Gathering the necessary files to prep for installation #####
####################################################


####################################################
##### Start ChatGPT-x64 installation #####
####################################################
$MSIXPath = "$LogPath\ChatGPT-x64.msix"

# Verify if file is there in the folder.
if(test-path $MSIXPath){

  Write-Output "`nChatGPT-x64.msix found....Executing Installation`n" 

# execute MSI command line installation with license file
Add-AppxProvisionedPackage -Online -PackagePath "$LogPath\ChatGPT-x64.msix" -LicensePath "$LogPath\ChatGPT-License.xml"  -LogPath "$LogPath\OpenAICodex_Install.log" -Verbose -Regions all

  # Verify that codex is installed
  $Codex_Details = Get-AppxProvisionedPackage -Online | Where-Object {$_.DisplayName -like "*openai.codex*"}

  
  If ($Codex_Details){
    Write-Output "`n##### OpenAI.Codex is installed #####`n$($Codex_Details | Out-String)"
          }else{
            Write-Output "`n##### OpenAI.Codex is NOT installed #####`n"
                  }
                # End nested if statement 

}else{

    Write-Output "`n!! $MSIXPath NOT found !! ....Exiting script`n"
    Stop-Transcript #End logging
    Exit 66 #close script

} # End If statement

####################################################
##### End ChatGPT-x64 installation #####
####################################################

####################################################
##### End OpenAI.Codex install#####
####################################################

# End logging
Stop-Transcript

