##############################################################################################
# UploadFilesToStorageAccount.ps1
# Copyright (c) Microsoft Corporation. All rights reserved.
# Licensed under the Apache License.
# Operations :
#
<#
.SYNOPSIS
    Upload files to USer Storage Account's Blob location

.PARAMETER
    <Parameters>

.INPUTS


.NOTES
    Creation Date:
    Purpose/Change:

.EXAMPLE

#>
###############################################################################################

param
(
    $filePaths,
    $destinationStorageAccount,
    $destinationContainer,
    $destinationFolder
)

if (-not (Test-Path -Path Function:\Write-LogInfo)) {
    Get-ChildItem .\Libraries -Recurse | Where-Object { $_.FullName.EndsWith(".psm1") } | ForEach-Object { Import-Module $_.FullName -Force -Global -DisableNameChecking }
}

try {
    $containerName = "$destinationContainer"
    $storageAccountName = $destinationStorageAccount
    $blobContext = New-AzStorageContext -StorageAccountName $storageAccountName -UseConnectedAccount
    $null = New-AzStorageContainer -Name $destinationContainer -Permission Blob -Context $blobContext -ErrorAction SilentlyContinue
    $UploadedFileURLs = @()
    foreach($fileName in $filePaths.Split(",")) {
        if ($destinationFolder) {
            $blobName = "$destinationFolder/$($fileName | Split-Path -Leaf)"
        } else {
            $blobName = "$($fileName | Split-Path -Leaf)"
        }
        $LocalFileProperties = Get-Item -Path $fileName
        Write-LogInfo "Uploading $([math]::Round($LocalFileProperties.Length/1024,2))KB $filename --> $($blobContext.BlobEndPoint)$containerName/$blobName"
        $UploadedFileProperties = Set-AzStorageBlobContent -File $filename -Container $containerName -Blob $blobName -Context $blobContext -Force -ErrorAction Stop
        if ( $LocalFileProperties.Length -eq $UploadedFileProperties.Length ) {
            Write-LogInfo "Succeeded."
            $UploadedFileURLs += "$($blobContext.BlobEndPoint)$containerName/$blobName"
        } else {
            Write-LogErr "Failed."
        }
    }
    return $UploadedFileURLs

} catch {
    $line = $_.InvocationInfo.ScriptLineNumber
    $script_name = ($_.InvocationInfo.ScriptName).Replace($PWD,".")
    $ErrorMessage =  $_.Exception.Message
    Write-LogErr "EXCEPTION : $ErrorMessage"
    Write-LogErr "Source : Line $line in script $script_name."
    Write-LogErr "$($blobContext.BlobEndPoint)$containerName/$blobName : Failed"
}
