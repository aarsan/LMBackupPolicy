# This script creates a test VM with a backup-policy tag to test the policy

# Configuration
$resourceGroupName = "LibertyMutualDemo"
$location = "centralus"
$vmName = "server01-$((Get-Random -Maximum 99999))"
$adminUsername = "testadmin"
$adminPassword = ConvertTo-SecureString "P@ssw0rd1234!" -AsPlainText -Force  # Change in production
$backupTag = "daily" # Change to 'hourly' to test the other policy

# Login to Azure if not already logged in
$context = Get-AzContext
if (-not $context) {
    Connect-AzAccount
}

# Create VM with backup-policy tag
Write-Host "Creating test VM with backup-policy tag: $backupTag"
$vm = New-AzVm -ResourceGroupName $resourceGroupName `
    -Name $vmName `
    -Location $location `
    -Image "Win2019Datacenter" `
    -AdminUsername $adminUsername `
    -AdminPassword $adminPassword `
    -Tag @{"backup-policy" = $backupTag}

Write-Host "VM creation complete. Once the VM is created, the Azure Policy should automatically assign it to the appropriate Recovery Services Vault."
Write-Host "To check if the VM was assigned to the vault, run: ./check_vm_backup_status.ps1 -VmName $vmName"
