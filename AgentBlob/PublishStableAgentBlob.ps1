Param(
    [Parameter(Mandatory=$true)]
    [string]$ArtifactsDirectory
)

$ErrorActionPreference = "Stop"

Import-Module AzureRM

$RESOURCE_GROUP_NAME = "dcos-prod-cdn"
$STORAGE_ACCOUNT_NAME = "dcosprodcdn"
$CONTAINER_NAME = "dcos-windows"
$CDN_PROFILE_NAME = "dcos-prod-mirror"


function New-AzureRmSession {
    try {
        $subscription = Get-AzureRmSubscription
    } catch {
        $subscription = $null
    }
    if($subscription) {
        # Disconnect any account if it's logged
        Remove-AzureRmAccount -Confirm:$false
    }
    if(!$env:CLIENT_ID) {
        Throw "ERROR: CLIENT_ID is not set"
    }
    if(!$env:CLIENT_SECRET) {
        Throw "ERROR: CLIENT_SECRET is not set"
    }
    if(!$env:TENANT_ID) {
        Throw "ERROR: TENANT_ID is not set"
    }
    $securePass = ConvertTo-SecureString $env:CLIENT_SECRET -AsPlainText -Force
    $cred = New-Object System.Management.Automation.PSCredential -ArgumentList $env:CLIENT_ID, $securePass
    Connect-AzureRmAccount -Credential $cred -ServicePrincipal -TenantId $env:TENANT_ID
}

function Publish-BuildArtifacts {
    if(!(Test-Path $ArtifactsDirectory)) {
        Throw "The artifacts directory doesn't exist"
    }
    if((Get-ChildItem $ArtifactsDirectory).Count -eq 0) {
        Throw "The artifacts directory is empty"
    }
    $key = Get-AzureRmStorageAccountKey -ResourceGroupName $RESOURCE_GROUP_NAME -Name $STORAGE_ACCOUNT_NAME | `
           Where-Object { $_.Permissions -eq "Full" } | Select-Object -First 1
    if(!$key) {
        Throw "Cannot find a storage account key with full permissions"
    }
    $context = New-AzureStorageContext -StorageAccountName $STORAGE_ACCOUNT_NAME -StorageAccountKey $key.Value
    $fileNames = @("7z1801-x64.msi", "DCOSWindowsAgentSetup.ps1", "windowsAgentBlob.zip")
    $blobBaseDir = "1-11-2"
    foreach($fileName in $fileNames) {
        $file = Join-Path $ArtifactsDirectory $fileName
        if(!(Test-Path $file)) {
            Throw "Cannot find the file $fileName into the artifacts directory"
        }
        Write-Output "Uploading $fileName to the Azure storage account blob: ${blobBaseDir}/${fileName}"
        Set-AzureStorageBlobContent -Container $CONTAINER_NAME -Blob "${blobBaseDir}/${fileName}" -File $file `
                                    -Context $context -Confirm:$false -Force
    }
    Write-Output "Purging the CDN cached assets"
    Get-AzureRmCdnEndpoint -ResourceGroupName $RESOURCE_GROUP_NAME -ProfileName $CDN_PROFILE_NAME | `
    Unpublish-AzureRmCdnEndpointContent -PurgeContent '/*'
    Write-Output "Finished publishing the Windows agent blob to the Azure CDN storage account"
}


try {
    New-AzureRmSession
    Publish-BuildArtifacts
} catch {
    Write-Output $_.ToString()
    Write-Output $_.ScriptStackTrace
    exit 1
} finally {
    Remove-AzureRmAccount -Confirm:$false
}
exit 0
