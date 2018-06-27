# End to End import of .bacpac files in Azure Blob to SQLDB

If you were ever in need to archive SQL databases into blob storage as it was no longer needed for active development, but needed a process to ondemand be able to recover those databases, this guide will walk you thru end to end to create this solution. 

Technologies that will be leveraged:
  * Azure Active Directory
  * Azure Automation
  * Azure Blob Storage
  * Azure SQLDB

## Pre-Requisites
This guide assumes that you have already created an Azure Automation Account, if not see this [link](https://docs.microsoft.com/en-us/azure/automation/automation-create-standalone-account) which will walk you thru creating an Azure Automation Account which by default also creates a RunAs account which has contributor access at the Subscription Level. If you wanted to add additional RunAs accounts see [Update your Automation account authentication with Run As accounts](https://docs.microsoft.com/en-us/azure/automation/automation-create-runas-account).

In addition this guide assumes that you are also already aware of how to export your databases to .bacpac files on blob storage, if not see [Export an AzureSQLDB to bacpac file](https://docs.microsoft.com/en-us/azure/sql-database/sql-database-export)



## Create a Credential to connect to Azure SQLDB for use by Azure Automation
Open your Azure Automation account, (1) navigate to Credentials and (2) click <b>Add a credential<b> 

![alt text](/images/createcredential.png "Create credential")

Fill in the name of your credential, Username used to connect to your AzureSQLDB Server that has admin access along with the password to authenticate with. 

![alt text](/images/createcredentialdetails.png "Create credential details")

