# Copyright (c) Microsoft Corporation
# Description: This script collect all distro images from all Azure regions

param
(
	[String] $ClientId,
	[String] $ClientSecret,
	[String] $TenantId,
	[String] $SubscriptionId,
	[String] $DatabaseServer,
	[String] $DatabaseUser,
	[String] $DatabasePassword,
	[String] $DatabaseName,
	[String] $Location,
	[String] $Publisher,
	[string] $LogFileName = "GetAllLinuxDistros.log",
	[string] $TableName = "AzureMarketplaceDistroInfo",
	[string] $ResultFolder = "DistroResults"
)

function Update-DeletedImages($Date, $Location, $Publisher, $DatabaseServer, $DatabaseUser, $DatabasePassword, $DatabaseName) {
	$server = $DatabaseServer
	$dbuser = $DatabaseUser
	$dbpassword = $DatabasePassword
	$database = $DatabaseName

	# Query if the image exists in the database
	$sqlQuery = "SELECT ID from $TableName where LastCheckedDate < '$Date' and IsAvailable = 1 and Location='$Location' and Publisher='$Publisher'"

	$connectionString = "Server=$server;uid=$dbuser; pwd=$dbpassword;Database=$database;Encrypt=yes;TrustServerCertificate=no;Connection Timeout=30;"
	$connection = New-Object System.Data.SqlClient.SqlConnection
	$connection.ConnectionString = $connectionString
	$connection.Open()
	$command = $connection.CreateCommand()
	$command.CommandText = $SQLQuery
	$reader = $command.ExecuteReader()
	# For every available image not updated, mark it as deleted
	$sqlQuery = ""
	while ($reader.Read()) {
		$id = $reader.GetValue($reader.GetOrdinal("ID"))
		$sqlQuery += "Update $tableName Set LastCheckedDate='$date', IsAvailable=0, DeletedOn='$date' where ID=$id;"
		$count++
		if ($count -ge 20) {
			Upload-TestResultToDatabase -SQLQuery $sqlQuery.Trim(";") -DatabaseName $database -DatabasePassword $dbpassword -DatabaseServer $server -DatabaseUser $dbuser
			$sqlQuery = ""
			$count = 0
		}
	}
	if ($sqlQuery) {
		Upload-TestResultToDatabase -SQLQuery $sqlQuery.Trim(";") -DatabaseName $database -DatabasePassword $dbpassword -DatabaseServer $server -DatabaseUser $dbuser
	}
}

function Update-DatabaseRecord($Publisher, $Offer, $Sku, $Version, $Date, $Location, $DatabaseServer, $DatabaseUser, $DatabasePassword, $DatabaseName) {
	$server = $DatabaseServer
	$dbuser = $DatabaseUser
	$dbpassword = $DatabasePassword
	$database = $DatabaseName
	
	# Query if the image exists in the database
	$sqlQuery = "SELECT ID from $TableName where Location='$Location' and FullName= '$Publisher $Offer $Sku $Version'"

	$connectionString = "Server=$server;uid=$dbuser; pwd=$dbpassword;Database=$database;Encrypt=yes;TrustServerCertificate=no;Connection Timeout=30;"
	$connection = New-Object System.Data.SqlClient.SqlConnection
	$connection.ConnectionString = $connectionString
	$connection.Open()
	$command = $connection.CreateCommand()
	$command.CommandText = $SQLQuery
	$reader = $command.ExecuteReader()
	# If the record exists, update the LastCheckedDate
	if ($reader.Read()) {
		$id = $reader.GetValue($reader.GetOrdinal("ID"))
		$sqlQuery = "Update $tableName Set LastCheckedDate='$date', IsAvailable=1 where ID=$id"
	# If the record doesn't exist, insert a new record
	} else {
		$distroName = "$Publisher $Offer $Sku $Version"
		$sqlQuery = "INSERT INTO $tableName (LastCheckedDate, Location, Publisher, Offer, SKU, Version, FullName, AvailableOn, IsAvailable) VALUES
			('$Date', '$Location', '$Publisher', '$Offer', '$Sku', '$Version', '$distroName', '$Date', 1)"
	}
	Upload-TestResultToDatabase -SQLQuery $sqlQuery -DatabaseName $database -DatabasePassword $dbpassword -DatabaseServer $server -DatabaseUser $dbuser
}

$LogFileName = "GetAllLinuxDistros-$($Location.Replace(',','-')).log"
#Load libraries
if (!$global:LogFileName) {
	Set-Variable -Name LogFileName -Value $LogFileName -Scope Global -Force
}
Get-ChildItem .\Libraries -Recurse | Where-Object { $_.FullName.EndsWith(".psm1") } | ForEach-Object { Import-Module $_.FullName -Force -Global -DisableNameChecking }

$RegionArrayInScope = $Location.Trim(", ").Split(",").Trim()
$PublisherArrayInScope = $Publisher.Trim(", ").Split(",").Trim()

# this should be {westus2 -> {Publisher -> {Offer -> {SKU -> {Version -> "Gallery ARM Image Name"}}}}}
$RegionDistros = @{}
# this should be {"Gallery ARM Image Name" -> ("westus2","eastus2")}
$DistroRegions = @{}

Write-Host "Login to Azure"
Connect-AzAccount -ServicePrincipal -Credential (New-Object System.Management.Automation.PSCredential ($ClientId, (ConvertTo-SecureString $ClientSecret -AsPlainText -Force))) -Tenant $TenantId
Set-AzContext -SubscriptionId $SubscriptionId
Write-Host "Set current SubscriptionId as $SubscriptionId"

$date = (Get-Date).ToUniversalTime()
$sqlQuery = ""
$count = 0
$allRegions = Get-AzLocation | select -ExpandProperty Location | where {!$RegionArrayInScope -or ($RegionArrayInScope -contains $_)}
# EUAP regions are not returned by Get-AzLocation
if ($RegionArrayInScope -imatch "euap") {
	$allRegions += ($RegionArrayInScope -imatch "euap")
}
foreach ($locName in $allRegions) {
	Write-Host "processing $locName"
	if (!$RegionDistros.$locName) {
		$RegionDistros["$locName"] = @{}
	}
	$allRegionPublishers = Get-AzVMImagePublisher -Location $locName | Select -ExpandProperty PublisherName | where {(!$PublisherArrayInScope -or ($PublisherArrayInScope -contains $_))}
	foreach ($pubName in $allRegionPublishers) {
		Write-Host "processing $locName $pubName"
		if (!$RegionDistros.$locName.$pubName) {
			$RegionDistros["$locName"]["$pubName"] = @{}
		}
		$allRegionPublisherOffers = Get-AzVMImageOffer -Location $locName -PublisherName $pubName | Select -ExpandProperty Offer
		foreach ($offerName in $allRegionPublisherOffers) {
			Write-Host "processing $locName $pubName $offerName"
			if (!$RegionDistros.$locName.$pubName.$offerName) {
				$RegionDistros["$locName"]["$pubName"]["$offerName"] = @{}
			}
			$allRegionPublisherOfferSkus = Get-AzVMImageSku -Location $locName -PublisherName $pubName -Offer $offerName | Select -ExpandProperty Skus
			foreach ($skuName in $allRegionPublisherOfferSkus) {
				Write-Host "processing $locName $pubName $offerName $skuName"
				if (!$RegionDistros.$locName.$pubName.$skuName) {
					$RegionDistros["$locName"]["$pubName"]["$skuName"] = @{}
				}
				$allRegionPublisherVersions = Get-AzVMImage -Location $locName -PublisherName $pubName -Offer $offerName -Sku $skuName | Select -ExpandProperty Version
				foreach ($skuVersion in $allRegionPublisherVersions) {
					Write-Host "processing $locName $pubName $offerName $skuName $skuVersion"
					$image = Get-AzVMImage -Location $locName -PublisherName $pubName -Offer $offerName -Sku $skuName -Version $skuVersion
					$distroName = "$pubName $offerName $skuName $skuVersion"
					if (!$RegionDistros.$locName.$pubName.$skuName.$skuVersion) {
						$RegionDistros["$locName"]["$pubName"]["$skuName"]["$skuVersion"] = $distroName
					}
					if ($image.OSDiskImage.OperatingSystem -eq "Linux") {
						Update-DatabaseRecord -Publisher $pubName -Offer $offerName -Sku $skuName -Version $skuVersion -Date $date -Location $locName -DatabaseName $DatabaseName -DatabasePassword $DatabasePassword -DatabaseServer $DatabaseServer -DatabaseUser $DatabaseUser

						if (!$DistroRegions.$distroName) {
							$DistroRegions["$distroName"] = [System.Collections.ArrayList]@()
						}
						if ($DistroRegions.$distroName -notcontains $locName) {
							$null = $DistroRegions.$distroName.Add($locName)
						}
					}
				}
			}
		}
		Update-DeletedImages -Date $date -Location $locName -Publisher $pubName -DatabaseName $DatabaseName -DatabasePassword $DatabasePassword -DatabaseServer $DatabaseServer -DatabaseUser $DatabaseUser
	}
}

if (!(Test-Path $ResultFolder))
{
	New-Item -Path $ResultFolder -ItemType Directory -Force | Out-Null
}

$count = $DistroRegions.Keys.Count
$allRegions | % {
	$loc = $_
	$RegionDistros.GetEnumerator() | where-object {$_.Name -imatch "^$loc"} | sort Name | Select-Object @{l="Location";e={$_.Name.Trim()}} | out-file -FilePath "$ResultFolder/${loc}_Distros.txt"
}
$Path = "$ResultFolder/AllLinuxDistros_" + (Get-Date).ToString("yyyyMMdd_hhmmss") + ".csv" 
$DistroRegions.GetEnumerator() | sort Name | Select-Object Name, @{l = "Location"; e = { $_.Value } } | Export-Csv -Path $Path -NoTypeInformation -Force
Write-Host "Total Distro collected: $count"