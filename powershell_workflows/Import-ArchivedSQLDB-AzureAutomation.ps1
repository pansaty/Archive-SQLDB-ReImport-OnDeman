<#
    .DESCRIPTION
        An example runbook which take a list of SQL Databases that are exported to blob storage and restore them.
        This will minimize spend for non production environments that do not need to be running 24/7

    .NOTES
        AUTHOR: Pankaj Satyaketu
        LASTEDIT: Jun 22, 2018
#>

workflow Import-ArchivedSQLDB
{
    	inlineScript {
        ##### BEGIN VARIABLE CONFIGURATION #####
        $connectionName = "AzureRunAsConnection" 
        $LogicalSQLServer =  'pankajtsp'
        $StorageAccountName = 'pankajcsa'
        $container ='sqlbackups'
        $folder = 'sqldbexports'
        $Databases = 'MyDemoDB','dsmeta', 'sqldwtest' # comma seperated list of databases to archive
        $ExportJobTimeOut = 14400 # 4Hours. Keep checking status of database export for up to 4 hours before throwing in the towel. Databsae will not be put on list to be deleted
        $SleepTimer = 30 #how long to sleep before checking export status again
        #Below variables needed for New-AzureRmSqlDatabaseImport
        $Edition = 'Basic'
        $ServiceObjectiveName = 'Basic' # see: https://docs.microsoft.com/en-us/sql/relational-databases/system-catalog-views/sys-database-service-objectives-azure-sql-database?view=azuresqldb-current
        $DatabaseMaxSizeBytes = '410000000'
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

        #1. Loop thru databases, check file path for files with that name, get the latest bacpac, restore
        $ImportRequestStatuses = @() # Empty array to hold Import Jobs
        #Confirm databases are online
        foreach ($database in $Databases)
        {
            "Looking for bacpac of $database in http://$StorageAccountName.blob.core.windows.net/$container/"
            $storageContext = New-AzureStorageContext -StorageAccountName $StorageAccountName -StorageAccountKey $StorageAccountKey.Value -ErrorAction Stop 
            $blobs = Get-AzureStorageBlob -Context $storageContext -Container $container -ErrorAction Stop | where-object {$_.Name -like "$folder/$database*"}
            $LastExportDateTime = $blobs | Measure-Object -Property LastModified -Maximum
            $blob = $blobs | ?{$_.LastModified -eq $LastExportDateTime.Maximum} | select Name
            If($blob)
            {
                "found $($blob.Name) for $database. Initiating Import"
                 $StorageUri = "http://$StorageAccountName.blob.core.windows.net/$container/$($blob.Name)"
                 If ($DBStatus){"$database already exists on $LogicalSQLServer skipping..."}
                 Else
                 {
                    $ImportRequestStatus = New-AzureRmSqlDatabaseImport -ResourceGroupName $SQLServer.ResourceGroupName -ServerName $LogicalSQLServer -DatabaseName $database -StorageKeytype StorageAccessKey -StorageKey $StorageAccountKey.Value -StorageUri $StorageUri -AdministratorLogin $SQLCredential.UserName -AdministratorLoginPassword $SQLCredential.Password -Edition $edition -ServiceObjectiveName $ServiceObjectiveName -DatabaseMaxSizeBytes $DatabaseMaxSizeBytes
                    $ImportRequestStatuses +=$ImportRequestStatus
                 }
            } 
            else {"No bacpacs for $database found"}
        }

        foreach ($ImportRequestStatus in $ImportRequestStatuses)
        {
            $error.clear()
            $status = $null
            $TimeToNap = 0
            While ($status.Status -ne 'Succeeded' -and $TimeToNap -lt $ExportJobTimeOut)
            { 
                $status = Get-AzureRmSqlDatabaseImportExportStatus $ImportRequestStatus.OperationStatusLink
                If ($error.Count -gt 0) 
                {
                    $TimeToNap = $ExportJobTimeOut #Pull the ripcord
                    "Failed to Import: $($ImportRequestStatus.DatabaseName)"
                }
                "zzzzz: $TimeToNap (s)"
                start-sleep -Seconds $SleepTimer
                $TimeToNap = $TimeToNap + $SleepTimer
                #if database export job succeeded, add to delete list
                "Current import status of $($ImportRequestStatus.DatabaseName): $($status.Status)"
            }
        }
    }
}

#2. Check for list of datbases provided vs what was imported and fail if mismatch