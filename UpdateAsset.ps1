#After building InventoryComputer and included new custom fieldsets, I realized I needed to grab the new fieldsets from the existing computers
#Create an Personal Token for SnipeIT: https://snipe-it.readme.io/reference#generating-api-tokens
#I got a Whoops Something Went Wrong before following this: https://snipe-it.readme.io/docs/common-issues#section-error-creating-api-token-trying-to-get-property-of-non-object-clientrepositoryphp81
$apikey=""
$url="" 

$macaddressField = "_snipeit_mac_address_1"
$processorField = "_snipeit_processor_2"
$memoryField = "_snipeit_memory_3"
$osField = "_snipeit_os_4"
$storageField = "_snipeit_storage_5"

#Get Snazy2000's Powershell module for Snipe-IT https://github.com/snazy2000/SnipeitPS
#This requires allowing modules from PSGallery
if (Get-Module -ListAvailable -Name SnipeitPS ) {
    Write-Output "Snipe-IT Module Installed, proceeding..."
}
else {
    Write-Output "Snipe-IT Module not found, installing..."
    Install-Module SnipeitPS
}

Import-Module SnipeitPS

#Set URL and API key so we don't have state it repeatedly
Set-Info -URL $url -apikey $apikey

#Get WMI Information
Write-Output "Getting Computer System Information via WMI"
Get-WmiObject -Class Win32_ComputerSystem
Get-WmiObject -Class Win32_Bios
Get-WmiObject -Class Win32_Processor
Get-WmiObject -Class Win32_DiskDrive -Filter "DeviceID = '\\\\.\\PHYSICALDRIVE0'"
Get-WmiObject -Class Win32_OperatingSystem | select Caption, BuildNumber,OSArchitecture
$wmiComputerSystem = Get-WmiObject -Class Win32_ComputerSystem
$wmiBios = Get-WmiObject -Class Win32_Bios
$wmiProcessor = Get-WmiObject -Class Win32_Processor
$wmiDisks = Get-WmiObject -Class Win32_DiskDrive | select model, @{Name="GB"; Expression={[math]::round($_.size/1GB)}}
$wmiNetwork = Get-WmiObject -Class Win32_NetworkAdapterConfiguration
$wmiOS = Get-WmiObject -Class Win32_OperatingSystem | select Caption, BuildNumber,OSArchitecture
$computerName = $wmiComputerSystem.Name

#Check if Asset already exists. If so update the asset with a maintenance of computer reimage
Write-Output "Searching for Existing Asset $computerName"
$asset = Get-Asset -search $computerName
if(([string]::IsNullOrEmpty($asset))){
    Write-Output "Asset $computerName does not exist! exiting"
}
else {
    $assetID = $asset.id
    $assetTag = $asset.asset_tag
    $modelID = $asset.model.id
    $statusID = $asset.status_label.id
    Write-Output "Asset $computerName found! Updating custom fields..."
    $memoryAmount = [math]::Round($wmiComputerSystem.TotalPhysicalMemory/1GB)
    $update = Set-Asset  -id $assetID -customfields @{$macaddressField = $wmiNetwork.MACAddress[1]; $processorField = $wmiProcessor.Name; $memoryField = "$($memoryAmount)GB"; $osField = $wmiOS.Caption; $storageField = "$($wmiDisks.model + " " + $wmiDisks.GB)GB"}
    Write-Output "Asset $computerName updated!"
    Write-Output $update
}