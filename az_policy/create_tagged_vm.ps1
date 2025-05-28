# This script creates a simple VM with backup-policy tag to test the policy
param(
    [Parameter(Mandatory=$false)]
    [ValidateSet("daily", "hourly")]
    [string]$BackupTag = "daily"
)

# Configuration
$resourceGroupName = "LibertyMutualDemo"
$location = "centralus"
$vmName = "testvm-$((Get-Random -Maximum 99999))"
$adminUsername = "adminuser"
$adminPassword = "P@ssw0rd1234!" # Change in production

# Login to Azure if not already logged in
$context = Get-AzContext
if (-not $context) {
    Connect-AzAccount
}

Write-Host "Creating test VM '$vmName' with backup-policy tag: $BackupTag"

# Create a resource group if it doesn't exist
$rg = Get-AzResourceGroup -Name $resourceGroupName -ErrorAction SilentlyContinue
if (-not $rg) {
    New-AzResourceGroup -Name $resourceGroupName -Location $location
}

# Create a simple VM with the specified tag
$securePassword = ConvertTo-SecureString $adminPassword -AsPlainText -Force

# Create a VM configuration 
$vmConfig = New-AzVMConfig -VMName $vmName -VMSize "Standard_B1s" -Tags @{"backup-policy" = $BackupTag}

# Add a Windows OS 
$vmConfig = Set-AzVMOperatingSystem -VM $vmConfig -Windows -ComputerName $vmName -Credential (New-Object System.Management.Automation.PSCredential ($adminUsername, $securePassword)) -ProvisionVMAgent -EnableAutoUpdate

# Add an image
$vmConfig = Set-AzVMSourceImage -VM $vmConfig -PublisherName "MicrosoftWindowsServer" -Offer "WindowsServer" -Skus "2019-Datacenter" -Version "latest"

# Create VM with all the settings
$vm = New-AzVM -ResourceGroupName $resourceGroupName -Location $location -VM $vmConfig -AsJob

Write-Host "VM creation started in background (Job ID: $($vm.Id))"
Write-Host "Use Get-Job -Id $($vm.Id) to check status"
Write-Host "Once the VM is created, the Azure Policy should configure backup automatically based on the tag."
Write-Host "To check if the VM was assigned to the correct vault, run: .\check_vm_backup_status.ps1 -VmName $vmName"
