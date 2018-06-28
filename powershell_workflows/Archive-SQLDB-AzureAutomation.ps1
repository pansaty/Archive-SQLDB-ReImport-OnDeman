<#
    .DESCRIPTION
        An example runbook which take a list of SQL Databases and export to blob storage after which it will delete that database.
        This will minimize spend for non production environments that do not need to be running 24/7

    .NOTES
        AUTHOR: Pankaj Satyaketu
        LASTEDIT: Jun 22, 2018
#>

workflow Archive-SQLDB
{
    	inlineScript {
        ##### BEGIN VARIABLE CONFIGURATION #####
        $connectionName = "AzureRunAsConnection" 
        $LogicalSQLServer =  'pankajtsp'
        $StorageAccountName = 'pankajcsa'
        $container ='sqlbackups/sqldbexports'
        $Databases = 'MyDemoDB','dsmeta', 'sqldwtest' # comma seperated list of databases to archive
        $ExportJobTimeOut = 14400 # 4Hours. Keep checking status of database export for up to 4 hours before throwing in the towel. Databsae will not be put on list to be deleted
        $SleepTimer = 30 #how long to sleep before checking export status again
        $deletedatabases = $true # variable to control whether databases are removed after succcessfully exporting
        ##### END VARIABLE CONFIGURATION #####

        
        #Login into Azure Subscription
		try
		{
    		# Get the connection "AzureRunAsConnection "
    		$servicePrincipalConnection=Get-AutomationConnection -Name $connectionName         
		
    		"Logging in to Azure..."
    		Add-AzureRmAccount `
        -ServicePrincipal `
        -TenantId $servicePrincipalConnection.TenantId `
        -ApplicationId $servicePrincipalConnection.ApplicationId `
        -CertificateThumbprint $servicePrincipalConnection.CertificateThumbprint 
		}
		catch {
    		if (!$servicePrincipalConnection)
    		{
        		$ErrorMessage = "Connection $connectionName not found."
        		throw $ErrorMessage
    		} else{
        		Write-Error -Message $_.Exception
        		throw $_.Exception
    		}
		}
        
		$SQLCredential = Get-AutomationPSCredential -Name 'PankajTSP-SQLAdmin'
        #$SQLCredential = Get-Credential    
        
 		$SQLServer = Get-AzureRmResource | Where-Object ResourceType -EQ "Microsoft.Sql/servers" |  ? {$_.name -eq $LogicalSQLServer}
        $StorageAccount = Get-AzureRmResource | Where-Object ResourceType -EQ "Microsoft.Storage/storageAccounts" |  ? {$_.name -eq $StorageAccountName}
        $StorageAccountKey = Get-AzureRmStorageAccountKey -ResourceGroupName $StorageAccount.ResourceGroupName -name $StorageAccountName | ? {$_.KeyName -eq 'key1'}

        $ConfirmedDatabases = @() # Empty array to hold confirmed databases
        #Confirm databases are online
        foreach ($database in $Databases)
        {
            "Inspecting: $database"
            $DBStatus = Get-AzureRmSqlDatabase -ResourceGroupName $SQLServer.ResourceGroupName -ServerName $LogicalSQLServer -DatabaseName $database |  Select Status
            If ($DBStatus.Status -eq 'Online') {$ConfirmedDatabases += $database}

        }
        
        #Export the databases
        $ExportRequestStatuses =@()
        foreach ($database in $ConfirmedDatabases)
        {
           $filedatetime = get-date -Format FileDateTime
           $StorageUri = "http://$StorageAccountName.blob.core.windows.net/$container/$database`_$filedatetime.bacpac"
           $ExportRequestStatus = New-AzureRmSqlDatabaseExport -ResourceGroupName $SQLServer.ResourceGroupName -ServerName $LogicalSQLServer -DatabaseName $database -StorageKeytype StorageAccessKey -StorageKey $StorageAccountKey.Value -StorageUri $StorageUri -AdministratorLogin $SQLCredential.UserName -AdministratorLoginPassword $SQLCredential.Password 
           $ExportRequestStatuses +=$ExportRequestStatus
        }
        
        #Confirm that the export Jobs succeeded
        $DatabasesToDelete = @()
        foreach ($ExportRequestStatus in $ExportRequestStatuses)
        {
            $error.clear()
            $status = $null
            $TimeToNap = 0
            While ($status.Status -ne 'Succeeded' -and $TimeToNap -lt $ExportJobTimeOut)
            { 
                $status = Get-AzureRmSqlDatabaseImportExportStatus $ExportRequestStatus.OperationStatusLink
                If ($error.Count -gt 0) 
                {
                    $TimeToNap = $ExportJobTimeOut #Pull the ripcord
                }
                "zzzzz: $TimeToNap (s)"
                start-sleep -Seconds $SleepTimer
                $TimeToNap = $TimeToNap + $SleepTimer
                #if database export job succeeded, add to delete list
                If ($status.Status -eq 'Succeeded') {$DatabasesToDelete += $ExportRequestStatus.DatabaseName.ToString()}
                "Current export status of $($ExportRequestStatus.DatabaseName): $($status.Status)"
            }
        }

        #Let's delete the databases
        $database = $null
        if ($deletedatabases)
        {
            foreach ($database in $DatabasesToDelete)
            {
               "dropping: $database"
                  Remove-AzureRMSQLDatabase -ResourceGroupName $SQLServer.ResourceGroupName -ServerName $LogicalSQLServer -DatabaseName $database -Force
            }
        }
    }    
}