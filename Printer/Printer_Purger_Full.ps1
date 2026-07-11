<#
.SYNOPSIS
The following script is designed to remove a specific printer and its associated driver from a Windows system. The script performs the following steps:

The script is intended to resolve issues relating to Fiery Essential Driver replacing newer Microsoft Visual C++ runtime libraries with an older version, causing issues with application dependencies. 

Source:
https://help.fiery.com/fierydriverwin/45265167_FieryEssentialDriverCRN_Win_Fiery.pdf

1. Checks if the printer with the name exists on the system.
    If name exist, remove printer.
        If removal fails - try again by restarting printer spooler then remove again.
        Verify if removal success/fail

2. Checks if the printer driver with the name exists on the system.
    If print driver exist, remove driver.
        If removal fails - try again by restarting printer spooler then remove again.
        Verify if removal success/fail

4. Checks if the printer INF with the name exists on the system.
    If print INF exist, remove it from driver store.
        Verify if removal success/fail

3. If none of the items exist, end script

*************************************************************
.NOTES
Wildcard can be used:
    PrinterPurge -PrinterName "mail-color-01" -DriverName "*Xerox EX*" -INFFile "*\oemsetupen.inf" -Verbose

Script works for removing a single or multiple [printer, driver or inf file]. All parameters are optional.
User can remove [Printer OR Driver OR inf file]. User can also remove all of the items if parameters are provided.
Script works for FULL purge or PARTIAL purge.

*************************************************************
.EXAMPLE
    # Printer only
        PrinterPurge  -PrinterName "printer*"
    # Driver only
        PrinterPurge  -DriverName "generic*"
    # INF File only
        PrinterPurge   -INFFile "*\oemsetupen.inf"
    # printer/driver (wildcard)
         PrinterPurge -PrinterName "mail-color*" -DriverName "*generic*" 
    # Printer/driver/INF (ALL)
         PrinterPurge -PrinterName "mail-color*" -DriverName "*Xerox EX*" -INFFile " *\oemsetupen.inf"

*************************************************************
Visual workflow chart:
https://gemini.google.com/share/ca66cd14529a

##############################################
Code Logic:

if(printer or driver exist){

	if(printer name exist){

        remove printer
	    Verify removal is success/fail
		if failed - start remeditation

	if(driver name exist){

	    remove driver
	    Verify removal is success/fail
		if failed - start remeditation


	if(Driver INF file exist in driver store){
	
		remove drive from driver store
		Verify removal is success/fail
	    }
    }
}
}else{

	Do something if both printer/driver cannot be found..

	if(INF file parameter exist){
		Delete the file from driver store
		if(Deletion fails){restart print spooler}
		}
    }

##############################################
 Notes:
    To perform a clean removal and to release dependency in order to avoid removal errors:

    * Delete the printer
    
    * Remove the driver from the print server properties

    * Purge the driver package from the system's Driver Store [C:\Windows\System32\DriverStore]

    * It is strongly recommended to execute in sequential order to avoid errors like:
            Driver package uninstalled.
            Failed to delete driver package: One or more devices are presently installed using the specified INF.

    * Example of a call to function
        PrinterPurge -PrinterName "mail-color-01" -DriverName "Xerox EX-i C9065-70 Printer 2.0" -InfFile "oemsetupen.inf" -Verbose

*****************

#>
####################################
function PrinterPurge {
    Param(
    [CmdletBinding()]
    [parameter()]
    [string] $PrinterName,
    [parameter()]
    [string] $DriverName,
    [parameter()]
    [string] $INFFile
    )

# Declare nested function


Function RemovePrinter {
   
    # Gather initial matching printers
    $FoundPrinters = Get-Printer | Where-Object { $_.Name -like "$PrinterName" }
    $PrinterList = $FoundPrinters.Name

    if ($PrinterList) {
        Write-Output "Located the following matching printer queues:"
        $PrinterList | ForEach-Object { Write-Output " - $_" }
        
        $FailureDetected = $false

        # Loop through each unique printer cleanly
        foreach ($SinglePrinter in $PrinterList) {
            Write-Output "`n##### Attempting to remove printer: $SinglePrinter ..........#####" 

            # Clear out error variable from any previous loops
            $PrinterErrorMSG = $null
            Remove-Printer -Name $SinglePrinter -Verbose -ErrorVariable PrinterErrorMSG -ErrorAction SilentlyContinue
            Start-Sleep -Seconds 3

            # Verification Re-query for THIS SPECIFIC printer
            $CheckPrinter = Get-Printer | Where-Object { $_.Name -eq $SinglePrinter }

            if (-not $CheckPrinter) {
                Write-Output "*********** Printer '$SinglePrinter' removed successfully ***********"
            } 
            else {
                # Remediation Sequence if the printer object is still locked/present
                Write-Warning "!!!!! Printer removal for '$SinglePrinter' failed. Queue is currently locked. !!!!!"
                if ($PrinterErrorMSG) { Write-Output "Error Data: $PrinterErrorMSG" }
                 
                Write-Output "`n~~~~~ Executing Print Spooler remediation procedure ~~~~~~~`n"
                Write-Output "Stopping Print Spooler service to release locks..."
                Stop-Service -Name "Spooler" -Force -Verbose
                Start-Sleep -Seconds 3

                # Attempt removal while spooler is dead (Windows will process queue deletes upon startup)
                Write-Output "Re-attempting deletion of '$SinglePrinter' while spooler is offline..."
                Remove-Printer -Name $SinglePrinter -ErrorAction SilentlyContinue
                Start-Sleep -Seconds 2

                Write-Output "Restarting Print Spooler service..."
                Start-Service -Name "Spooler" -Verbose
                Start-Sleep -Seconds 5

                # Final Re-query for this specific queue item
                $FinalCheck = Get-Printer | Where-Object { $_.Name -eq $SinglePrinter }
                if ($FinalCheck) {
                    Write-Error "Print removal process failed for '$SinglePrinter'. Queue remains present."
                    $FailureDetected = $true
                } else {
                    Write-Output "*********** Remediation Successful: Printer '$SinglePrinter' completely removed. ***********"
                }
            }
        } # End foreach

        # Final exit summary for deployment platforms
        if ($FailureDetected) {
            Write-Output "`n[ERROR] One or more printer queues failed to uninstall cleanly."
            exit 66
        } else {
            Write-Output "`n*********** ALL TARGET PRINTER QUEUES PURGED SUCCESSFULLY ***********`n"
        }

    } else {
        Write-Warning "~~~~ Printer matching '$PrinterName' not found or already removed. Proceeding to driver removal steps... ~~~~~"
    }
} # End Function [RemovePrinter]


Function RemovePrinterDriver {

    # Gather matching printer drivers registered to the print subsystem
    $FoundDrivers = Get-PrinterDriver | Where-Object { $_.Name -like "$DriverName" }
    $DriverList = $FoundDrivers.Name

    if ($DriverList) {
        Write-Output "Located the following matching printer drivers to unregister:"
        $DriverList | ForEach-Object { Write-Output " - $_" }
        
        $FailureDetected = $false

        # Process each individual driver from the clean array
        foreach ($SingleDriver in $DriverList) {
            Write-Output "`n##### Attempting to remove printer driver: $SingleDriver ..........#####" 
            
            $PrinterDriverErrorMSG = $null
            Remove-PrinterDriver -Name $SingleDriver -Verbose -ErrorVariable PrinterDriverErrorMSG -ErrorAction SilentlyContinue
            Start-Sleep -Seconds 3

            # Verification Re-query for THIS SPECIFIC driver object
            $CheckDriver = Get-PrinterDriver | Where-Object { $_.Name -eq $SingleDriver }

            if (-not $CheckDriver) {
                Write-Output "*********** Printer driver '$SingleDriver' removed successfully ***********"
            } 
            else {
                # Remediation Sequence: Triggered if the driver remains locked by active system spooler processes
                Write-Warning "!!!!! Printer driver removal failed. The driver '$SingleDriver' is currently locked. !!!!!"
                if ($PrinterDriverErrorMSG) { Write-Output "Error Log Data: $PrinterDriverErrorMSG" }
   
                Write-Output "`n~~~~~~~ Executing Print Spooler remediation procedure ~~~~~~~`n"
                Write-Output "Stopping Print Spooler service to release driver subsystem hooks..."
                Stop-Service -Name "Spooler" -Force -Verbose
                Start-Sleep -Seconds 3

                # Attempt driver deletion while the print environment handles are dropped
                Write-Output "Re-attempting deletion of '$SingleDriver' while spooler infrastructure is offline..."
                Remove-PrinterDriver -Name $SingleDriver -ErrorAction SilentlyContinue
                Start-Sleep -Seconds 2

                Write-Output "Restarting Print Spooler service..."
                Start-Service -Name "Spooler" -Verbose
                Start-Sleep -Seconds 5

                # Final verification query for this loop target
                $FinalCheck = Get-PrinterDriver | Where-Object { $_.Name -eq $SingleDriver }
                if ($FinalCheck) {
                    Write-Error "Print driver removal process failed for '$SingleDriver'. Registry handle remains present."
                    $FailureDetected = $true
                } else {
                    Write-Output "*********** Remediation Successful: Driver '$SingleDriver' fully unrooted. ***********"
                }
            }
        } # End foreach

        # Final exit evaluations for execution tracking
        if ($FailureDetected) {
            Write-Output "`n[ERROR] One or more driver objects could not be successfully dropped."
            exit 66
        } else {
            Write-Output "`n*********** ALL TARGET PRINTER DRIVERS PURGED SUCCESSFULLY ***********`n"
        }

    } else {
        Write-Warning "~~~~ Printer Driver matching '$DriverName' not found or already removed. Script complete. ~~~~~"
    }
} #End function [RemovePrinterDriver]


Function RemoveINF_File {
 
    try {   
        # Start removal of driver from driver store (C:\Windows\System32\DriverStore\FileRepository)
        Write-Output "Searching for driver packages matching pattern: $INFFile"
        
        # Gather initial drivers matching target
        $File = Get-WindowsDriver -Online | Where-Object { $_.OriginalFileName -like "$INFFile" } 
        
        if (-not $file) {
            Write-Warning "~~~~~~ Skipping removal. No INF files matching '$INFFile' located in the driver store. ~~~~~~"
            return
        }

        Write-Output "Located the following matching driver packages:"
        $File | Select-Object Driver, ProviderName, OriginalFileName | Out-String | Write-Output

        # Extract only the unique published names (e.g., oem11.inf)
        $DriverINF_Names = $file.Driver

        # Track if anything failed to ensure correct final reporting
        $FailureDetected = $false

        foreach ($item in $DriverINF_Names) {
            Write-Warning "~~~~~~~ Initiating uninstallation for INF: $item ~~~~~~~"
            pnputil /delete-driver $item /uninstall /force

            # Individual Verification Check
            Start-Sleep -Seconds 2
            $CheckDrive = Get-WindowsDriver -Online | Where-Object { $_.Driver -eq $item }

            # Remediation Workflow if individual driver is still locked
            if ($CheckDrive) {
                Write-Warning "!!! Driver package $item remains locked. Executing print spooler remediation procedure... !!!"
                
                Write-Output "Stopping Print Spooler service..."
                Stop-Service -Name "Spooler" -Force -Verbose
                Start-Sleep -Seconds 2

                Write-Output "Attempting forced removal of $item while spooler is stopped..."
                pnputil /delete-driver $item /uninstall /force
                
                Write-Output "Restarting Print Spooler service..."
                Start-Service -Name "Spooler" -Verbose
                Start-Sleep -Seconds 3

                # Final Recheck for this specific item
                $FinalCheck = Get-WindowsDriver -Online | Where-Object { $_.Driver -eq $item }
                if ($FinalCheck) {
                    Write-Error "Forced uninstallation failed. Driver package $item is still present."
                    $FailureDetected = $true
                } else {
                    Write-Output "*********** Remediation Successful: Driver package $item fully purged. ***********"
                }
            } else {
                Write-Output "*********** Driver package $item removed successfully on first attempt. ***********"
            }
        }

        # Final Summary evaluation for deployment returns
        if ($FailureDetected) {
            Write-Output "Print driver INF removal process completed with errors. Please review log entries."
            exit 66
        } else {
            Write-Output "`n*********** ALL TARGET PRINTER DRIVER INFs PURGED SUCCESSFULLY ***********`n"
        }

    } catch {
        Write-Output "A critical terminating exception occurred during execution:"
        Write-Output $_.Exception.Message
        exit 66
    }
}# End function - [RemoveINF_File]


####################################
# Start removal
####################################
try{ 


$Printer = Get-Printer | Select-Object Name | where-object Name -like "$PrinterName"
$PrinterName1 = $printer.Name

$Driver = get-printerdriver | Select-Object Name | where-object Name -like "$DriverName"
$DriverName1 = $Driver.Name

# If printer or driver is present - remove it
if($printerName1 -or $DriverName1){

    ##### Start Printer removal #####
    RemovePrinter

    ##### Start Printer driver removal #####
    RemovePrinterDriver

    ##### Start Printer driver removal v2 #####
    RemoveINF_File

}else{

# If printer AND print driver does not exist....start removal of INF file by calling function [RemoveINF_File]

    Write-Warning "~~~~ Printer and Printer driver does not exist ~~~~ Please verify name and try again.....Detecting if INF File is provided...."

    # IF INFFile parameter is declared - start remove INF function
    if($INFFile){

        RemoveINF_File 
    }


}# End parent IF/ELSE condition on [Printer or driver exist]  

}catch{
    # get terminating error
    Write-Output $_.Exception.Message
    Write-Error 66
    # stop script
    throw $_.Exception
    
    }
}# End function


####################################
# End removal
####################################


# Invoke function
PrinterPurge -PrinterName "mail-color-01*" -DriverName "*Xerox EX*" -INFFile "*\oemsetupen.inf" -Verbose
