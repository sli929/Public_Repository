<# The following script is intended for SQL express installation 2022 or 2025 with custom named instance.

# Requirement:
SQL Express 2022 or 2025 installed

# It does the following:

    1. Create "SQLExpressGroup" local group and add current user.
    2. Use module dbatools to assign the current users "DBCreator" role directly.
    3. Use module dbatools to assign the "SQLExpressGroup" group "DBCreator" role directly.

    The dbcreator fixed server-level role gives a user or a service account the power to manage the lifecycle of databases across an entire SQL Server instance, without making them a full sysadmin.
    It is a powerful mid-tier role commonly assigned to application installation accounts, CI/CD deployment pipelines, or developers who need to spin up and tear down testing environments on demand.


    ** For error on dbatools-
    Failure | An existing connection was forcibly closed by the remote host.
    Use PS version 5.1
#>


##########################################################
# Option 1:
# The following creates the "SQLExpressGroup" group and add the current user.
# Role assignment is done via the configuration .ini file

# Create local security group for SQLExpressGroup rights- intended for SQL express installations

# Create
New-LocalGroup -Name "SQLExpressGroup" -Description "Local group created for SQL express installation" -Confirm:$false -Verbose

# Add current user to group; command works well if only one user is active for that current device

# Get user logged into device
$Domain = $env:USERDOMAIN
$Query = query user /server:$server
$CurrentUser = $Query -replace '\s{2,}', ',' -replace '>','' | ConvertFrom-Csv
$FullName = "$Domain\$($CurrentUser.username)"


Add-LocalGroupMember -Group "SQLExpressGroup" -Member "$FullName" -Verbose 


########################################
# Option 2:
# The following directly assigns a USER the "DBCreator" role for local SQL instance. Intended for sql express installations

# Check if module is loaded -
$dbatools = get-module -Name dbatools

# If module is not loaded - try import it 
if(-not $dbatools){
    
    Write-Output "Attempting to import dbatools module.......`n"
    import-module dbatools -Force 

    # Check module post import
    $dbatools_Check = get-module -Name dbatools

    # Module path
    $Path = (Get-Module -ListAvailable dbatools).path
    if(Test-Path -path $Path){  
        Write-Output "Imported dbatools from:`n$path.......`n"
    }
    
    # If importing module fails - install it then import it
    if(-not $dbatools_Check){
    
    # Install the module - per user install 
        Write-Output "`n####### Installing dbatools modules #######`n"
        Install-Module -Name dbatools -scope CurrentUser -Force

    # Import the module
        Write-Output "`nImporting dbatools module.......`n"
        import-module dbatools -Force

    # Check for imported module
        if(get-module -Name dbatools){

        Write-Warning "`n##### dbatools module is installed and imported successfully #####`n"
            
    # Module path
        $Path = (Get-Module -ListAvailable dbatools).path
        Write-Output "`nImported dbatools from:`n$path.......`n"                

        }else{

        Write-Warning "`n##### dbatools module is NOT installed #####`n"

        }
    }
}


#######################################
##### Role assignment #####
#######################################
$servername = $env:COMPUTERNAME
$instance2022 = "SQLEXPRESS2022"
$Instance2025 = "SQLEXPRESS2025"
$role = "DBCreator"

###############
# Verify Connection
$Connect_Instance_2025 = Test-DbaInstanceName -SqlInstance "$Servername\$Instance2025"
$Connect_Instance_2022 = Test-DbaInstanceName -SqlInstance "$Servername\$Instance2022"

# Trust cert
Set-DbatoolsConfig -FullName sql.connection.trustcert -Value $true -Register

# Get user logged into device
$Domain = $env:USERDOMAIN
$Query = query user /server:$server
$CurrentUser = $Query -replace '\s{2,}', ',' -replace '>','' | ConvertFrom-Csv
$FullName = "$Domain\$($CurrentUser.username)"

###############

try{
# IF instance SQL instance 2022 exist -
if($Connect_Instance_2022){

# Create the db object 
New-DbaLogin -SqlInstance "$Servername\$instance2022" -Login "$FullName"
New-DbaLogin -SqlInstance "$Servername\$instance2022" -Login "$servername\SQLExpressGroup"

# Add user to SQL server role role (IF user is signed in)
Add-DbaServerRoleMember -SqlInstance "$Servername\$instance2022" -Login "$FullName" -ServerRole $role -Confirm:$false -Verbose

# Add custom group to SQL server role  (Option 2 if no current user signed in)
Add-DbaServerRoleMember -SqlInstance "$Servername\$instance2022" -Login "$servername\SQLExpressGroup" -ServerRole $role -Confirm:$false -Verbose

# Verify
Write-Output "`n######## The following members part of role: $Role for instance $instance2022 are: ########`n"
Get-DbaServerRoleMember -SqlInstance "$Servername\$instance2022" -ServerRole $role  -verbose
}
}catch{

    Write-Output "$($_.Exception.Message)"
    Write-Output "`n######## $instance2022 DOES NOT EXIST ########`n"

}

try{
# IF instance SQL instance 2025 exist -
if($Connect_Instance_2025){

# Create the db object 
New-DbaLogin -SqlInstance "$Servername\$Instance2025" -Login "$FullName"
New-DbaLogin -SqlInstance "$Servername\$Instance2025" -Login "$servername\SQLExpressGroup"

# Add user to SQL server role role (IF user is signed in)
Add-DbaServerRoleMember -SqlInstance "$Servername\$instance2025" -Login "$FullName" -ServerRole $role -Confirm:$false -Verbose

# Add custom group to SQL server role  (Option 2 if no current user signed in)
Add-DbaServerRoleMember -SqlInstance "$Servername\$instance2025" -Login "$servername\SQLExpressGroup" -ServerRole $role -Confirm:$false -Verbose

# Verify
Write-Output "`n######## The following members part of role: $Role for instance $instance2025 are: ###########`n"
Get-DbaServerRoleMember -SqlInstance "$Servername\$instance2025" -ServerRole $role  -verbose
}
}catch{
    
    Write-Output "$($_.Exception.Message)"
    Write-Output "`n######## $instance2025 DOES NOT EXIST ########`n"

}
