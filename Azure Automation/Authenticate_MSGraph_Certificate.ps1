<#
.SYNOPSIS
Authenticate with Certificate-Based Authentication (CBA) to Microsoft Graph for Hybrid Worker Groups.
- Script is not for azure runbook

.DESCRIPTION
    Checks local machine cert store for required certificate. If missing, retrieves it from
    Azure Key Vault directly in-memory, imports it to Cert:\LocalMachine\My, and authenticates via Connect-MgGraph.

.NOTES

***** Requires Interactive Login ONCE *****
# Requirements:
	1. The app is already registered
	2. API permissions configure
	3. Key vault created with new certificate
    4. Certificate uploaded to app (AzMsGraph) in azure portal

-----------------------------------

The following modules are required for certificate authentication:
Microsoft.Graph.Authentication
Az.Accounts
Az.KeyVault

Troubleshoot:
# Remove module
get-module -Name Microsoft.Graph.Authentication |Uninstall-Module -Force

# Removing module directory
Remove-Item -Path "C:\Program Files\PowerShell\Modules" -Recurse -Force

Requires -Version 5.1
#>

#########################################################
                # Set Variables #
#########################################################

$TenantID = "xxxxxxxxxxxxxxxxxxxxxxxxxxxxxxx"
$Subscription = "xxxxxxxxxxxxxxxxxxxxxxxxxxxxxxx"
$AppID = "xxxxxxxxxxxxxxxxxxxxxxxxxxxxxxx"
$vaultname = "Az-KeyVault-Red929"
$certname = "Az-Cert-929"
$Cert_Subject= "CN=Red929.com"

#####################################################
            # Declare Functions #  
#####################################################

#Install module if not available
function Module_Install {

    [CmdletBinding()]
    param (
        [Parameter(Mandatory = $true)]
        [string]$ModuleName
    )

# Check if module is loaded -
     $Module = get-module -Name $ModuleName

    # If module is not loaded - try import it 
    if(-not $Module){
        
        Write-Warning "Attempting to import $ModuleName module.......`n"
        import-module $ModuleName -Force 

        # Check module post import
        $Module_Check = get-module -Name $ModuleName

        # Module path
        $Path = (Get-Module -ListAvailable $ModuleName).path
        if(Test-Path -path $Path){  
            Write-Output "Imported $ModuleName from:`n$path.......`n"
        }
        
        # If importing module fails - install it then import it
        if(-not $Module_Check){
        
        # Install the module
            Write-Output "`n####### Installing $ModuleName #######`n"
            Install-Module -Name $ModuleName -Repository PSGallery -Force -AllowClobber -Scope AllUsers

        # Import the module
            Write-Output "`nImporting $ModuleName module.......`n"
            import-module $ModuleName -Force

        # Check for imported module
            if(get-module -Name $ModuleName){

            Write-Warning "`n##### $ModuleName module is installed and imported successfully #####`n"
                
        # Module path
            $Path = (Get-Module -ListAvailable $ModuleName).path
            Write-Output "`nImported $ModuleName from:`n$path.......`n"                

            }else{

            Write-Warning "`n##### $ModuleName module is NOT installed #####`n"

            }
        }
    }
}# End function [Module_Install]

#########################################################
            # Start Install modules #
#########################################################

# Get NuGet if not available
        $Nuget = Get-PackageProvider NuGet
        if (-not $Nuget) {

            Write-Output "`n ####### Installing provider NuGet #######`n"
            Install-PackageProvider -Name NuGet -Confirm:$false -Force -ErrorAction SilentlyContinue
        }

# Install Required Modules
$RequiredModules = @('Microsoft.Graph.Authentication', 'Az.Accounts', 'Az.KeyVault')
foreach ($module in $RequiredModules) {

    Module_Install -ModuleName $module
}

#########################################################
                #  certificate check #
#########################################################

# Check if cert if present and loaded on local machine personal store.
Write-Output "`nVerifying if certificate is present on Cert:\LocalMachine\My....`n"
$cert_check = Get-ChildItem Cert:\LocalMachine\My -Recurse | where {$_.Subject –like "$cert_subject"}

#########################################################
    # Start - Connect to Azure vault to get certificate #
#########################################################

# If the cert does NOT exist - connect to azure to retrieve it from key vault
if(-not $cert_check){

# Connect to azure first. ##### Interactive login REQUIRED FOR FIRST TIME sign on #####

    Connect-AzAccount -Tenant $TenantID -Subscription $Subscription

    # Directly import into machine store from memory (without creating a temporary disk file)
    $CertificateSecret = Get-AzKeyVaultSecret -VaultName $vaultname -Name $certname -AsPlainText
    $CertificateBytes  = [System.Convert]::FromBase64String($CertificateSecret)

    $flags = [System.Security.Cryptography.X509Certificates.X509KeyStorageFlags]::MachineKeySet -bor `
            [System.Security.Cryptography.X509Certificates.X509KeyStorageFlags]::PersistKeySet

    $cert = New-Object System.Security.Cryptography.X509Certificates.X509Certificate2($CertificateBytes, "", $flags)

    $store = New-Object System.Security.Cryptography.X509Certificates.X509Store("My", "LocalMachine")
    $store.Open([System.Security.Cryptography.X509Certificates.OpenFlags]::ReadWrite)
    $store.Add($cert)
    $store.Close()

}

#########################################################
    # End - Connect to Azure vault to get certificate #
#########################################################

#########################################################
    # Start - Connect to Microsoft Graph (CBA) #
#########################################################

$Cert_Thumbprint = (Get-ChildItem Cert:\LocalMachine\My -Recurse | where {$_.Subject –like "$cert_subject"}).Thumbprint

# If Cert just got imported - proceed to connect with thumbprint
if($Cert_Thumbprint){
        
    Write-Warning "`n##### Import of certificate from key vault successful #####`n"

    Write-Output "`n##### Connecting to Microsoft Graph with the thumbprint #####`n"
    Connect-MgGraph -TenantId $tenantid -ClientId $appid -CertificateThumbprint $Cert_Thumbprint

# If cert already exist in store - use it to authenticate
}elseif($cert_check){

    $Cert_Thumbprint = (Get-ChildItem Cert:\LocalMachine\My -Recurse | where {$_.Subject –like "$cert_subject"}).Thumbprint

    Write-Warning "`n##### Certificate is already imported into the store.... Connecting to Microsoft Graph with the thumbprint #####`n"
    Connect-MgGraph -TenantId $tenantid -ClientId $appid -CertificateThumbprint $Cert_Thumbprint
     
}else{
    Write-Error "#### Import of certificate from azure vault failed... please try again! #### "
}

#########################################################
    # End - Connect to Microsoft Graph (CBA) #
#########################################################