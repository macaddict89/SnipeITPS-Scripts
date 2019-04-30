#Get and create Manufacturer/Model/Asset for Computer for Snipe-IT Assement Management Tool
#ideally run after computer is reimaged, joined to domain
#This script is designed to be run in a powershell window or through PDQ Deploy's Powershell wrapper.
#kudos to u/iamkilo for the jumping off point https://www.reddit.com/r/sysadmin/comments/bf3web/snipe_it_powershell_automation/

#Create an Personal Token for SnipeIT: https://snipe-it.readme.io/reference#generating-api-tokens
#I got a Whoops Something Went Wrong before following this: https://snipe-it.readme.io/docs/common-issues#section-error-creating-api-token-trying-to-get-property-of-non-object-clientrepositoryphp81
$apikey=""
$url="" 

#When creating a computer model I want to add some custom fields/fieldsets which are different between Laptop and Desktop Workstations.
#To use something else, change the variable below to the ID of the fieldset you have created in SnipeIT
$desktopFieldsetID =  "1"
$laptopFieldsetID = "1"

#Status Label to set the asset when completed.
#maybe parameterize this stuff
$statusID = "2"

#Supplier ID for reimage maintenance if existing computer
#maybe parameterize this stuff
$supplierID = ""

$laptopCatID = ""
$desktopCatID = ""

#Remove if you have no custom fields/fieldsets you want to use
#First field for wired MAC Addresses
$macaddressField = "_snipeit_mac_address_1"
$processorField = "_snipeit_processor_2"
$memoryField = "_snipeit_memory_3"
$osField = "_snipeit_os_4"
$storageField = "_snipeit_storage_5"
$mac2Field = "_snipeit_mac_address_2_6"

$Today = Get-Date -Format "yyyy-MM-dd"
$maintTitle = "Computer Reimage"

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
$nics = Get-NetAdapter -Physical
$wmiOS = Get-WmiObject -Class Win32_OperatingSystem | select Caption, BuildNumber,OSArchitecture
$computerName = $wmiComputerSystem.Name
$wired = $nics | where PhysicalMediaType -eq "802.3"
$wiredMAC = $wired.MacAddress
$wiredMacFormatted = $wiredMAC -replace "-",":"
if ($wmiComputerSystem.PCSystemTypeEx -eq 2) {
    $wireless = $nics | where PhysicalMediaType -like "*802.11*"
    $wirelessMAC = $wireless.MacAddress
    $wirelessMacFormatted = $wirelessMAC -replace "-",":"  }

#Check if Asset already exists. If so update the asset with a maintenance of computer reimage
Write-Output "Searching for Existing Asset $computerName"
$asset = Get-Asset -search $computerName
if(([string]::IsNullOrEmpty($asset))){
    Write-Output "$computerName does not exist! Creating Asset..."

    #Grab manufacturer and make sure it exists. 
    #  Probably easier to change manufacturer in SnipeIT to what is output in WMI than do convoluted searches based on partial information
    #Save manufacturer ID for if we need to create a model
    $manufacturer = $wmiComputerSystem.Manufacturer
    Write-Output "Checking for Manufacturer $manufacturer"

    $manufacturerExists = Get-Manufacturer | Where-Object {$_.name -like $manufacturer}
    if(([string]::IsNullOrEmpty($manufacturerExists))){
        Write-Output "Manufacturer $manufacturer not found, creating..."
        $newManufacturer = New-Manufacturer -Name $manufacturer
        $manufacturerID = $newManufacturer.id
        #You may want to add more details to a newly created item
        Write-Output "New Manufacturer $manufacturer created. Check $url/manufacturers/$manufacturerID to ensure all necessary information is populated"
    }
    else {
        $manufacturerID = $manufacturerExists.id
        Write-Output "Manufacturer $manufacturer exists, proceeding..."
    }

    #Grab model and make sure it exists
    $model = $wmiComputerSystem.Model
    Write-Output "Checking for Model $model"

    #Couldn't get Where-Object to consistently behave; results were missing a laptop model I was testing that I knew existed
    #Even searching for the ID number came up with nothing.
    $modelExists = Get-Model -search $model
    if(([string]::IsNullOrEmpty($modelExists))){
        Write-Output "Model $model not found, creating..."
        #Need to set the category ID (Laptop or Desktop) so we can create the Model.
        if ($wmiComputerSystem.PCSystemTypeEx -eq 2) {$categoryID = $laptopCatID
        Write-Output "Computer detected to be Laptop"
        $model = New-Model -Name $model -category_id $categoryID -manufacturer_id $manufacturerID -fieldset_id $laptopFieldsetID }
        if ($wmiComputerSystem.PCSystemTypeEx -eq 1) {$categoryID = $desktopCatID
        Write-Output "Computer detected to be Desktop"
        $model = New-Model -Name $model -category_id $categoryID -manufacturer_id $manufacturerID -fieldset_id $desktopFieldsetID }
        $modelID = $model.id
        #You may want to add more details to a newly created item
        Write-Output "New Model $model.name created. Check $url/models/$modelID to ensure Depreciation and EOL Months information gets populated" 
    }
    else {
        $modelID = $modelExists.id
        Write-Output "Model $model exists, proceeding..."
    }

    #finally, create the asset
    Write-Output "Creating Asset $computerName..."
    $memoryAmount = [math]::Round($wmiComputerSystem.TotalPhysicalMemory/1GB)
    #change or remove custom fields if not being used for your deployment
    #Allowing for more custom fields for a laptop if necessary; does not need to be split if not using additional fields
    # for laptops e.g. wireless mac address
    if ($wmiComputerSystem.PCSystemTypeEx -eq 2) { $asset = New-Asset -Name $computerName -Status_id $statusID -Model_id $modelID -customfields @{"serial" = $wmiBios.SerialNumber; $macaddressField = $wiredMacFormatted; $processorField = $wmiProcessor.Name; $memoryField = "$($memoryAmount)GB"; $osField = $wmiOS.Caption; $storageField = "$($wmiDisks.model + " " + $wmiDisks.GB)GB"; $mac2Field = $wirelessMacFormatted} }
    else { $asset = New-Asset -Name $computerName -Status_id $statusID -Model_id $modelID -customfields @{"serial" = $wmiBios.SerialNumber; $macaddressField = $wiredMacFormatted; $processorField = $wmiProcessor.Name; $memoryField = "$($memoryAmount)GB"; $osField = $wmiOS.Caption; $storageField = "$($wmiDisks.model + " " + $wmiDisks.GB)GB"} }
    $tag = $asset.asset_tag
    $assetID = $asset.id
    Write-Output "Asset $computerName ($tag) created. Please visit $url/hardware/$assetID and update additional fields"
    Write-Output $asset
    Write-Output "Creating Reimage Maintenance for Asset $computerName..."
    New-AssetMaintenance -asset_id $assetID -supplier_id $supplierID -asset_maintenance_type "Maintenance" -title $maintTitle -start_date $Today -completion_Date $Today
 
}
#Asset exists.  Create a reimage maintenance item and update the custom fields if desired
else {
    $assetID = $asset.id
    $memoryAmount = [math]::Round($wmiComputerSystem.TotalPhysicalMemory/1GB)
    Write-Output "Asset $computerName ($tag) exists. Creating Reimage maintenance"
    if ($wmiComputerSystem.PCSystemTypeEx -eq 2) { Set-Asset -id $assetID -Name $asset.name -Model_id $asset.model.id -Status_id $statusID -customfields @{$macaddressField = $wiredMacFormatted ; $processorField = $wmiProcessor.Name; $memoryField = "$($memoryAmount)GB"; $osField = $wmiOS.Caption; $storageField = "$($wmiDisks.model + " " + $wmiDisks.GB)GB"; $mac2Field = $wirelessMacFormatted} }
    else { Set-Asset -id $assetID -Name $asset.name -Model_id $asset.model.id -Status_id $statusID -customfields @{$macaddressField = $wiredMacFormatted; $processorField = $wmiProcessor.Name; $memoryField = "$($memoryAmount)GB"; $osField = $wmiOS.Caption; $storageField = "$($wmiDisks.model + " " + $wmiDisks.GB)GB"} }
    New-AssetMaintenance -asset_id $assetID -supplier_id $supplierID -asset_maintenance_type "Maintenance" -title $maintTitle -start_date $Today -completion_Date $Today
}