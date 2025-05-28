# Deploy a test VM with a backup-policy tag for Azure Policy backup testing
# Set this variable to 'daily' or 'hourly' to test the policy
$backupPolicyTagValue = 'daily'  # Change to 'hourly' to test hourly backup

# Configuration
$resourceGroupName = "LibertyMutualDemo"
$location = "centralus"
$vmName = "test-vm-$backupPolicyTagValue-$(Get-Random -Maximum 9999)"
$adminUsername = "testadmin"
$adminPassword = ConvertTo-SecureString "P@ssw0rd1234!" -AsPlainText -Force  # Change in production

# Login to Azure if not already logged in
$context = Get-AzContext
if (-not $context) {
    Connect-AzAccount
}

# Create VM with backup-policy tag
Write-Host "Creating test VM with backup-policy tag: $backupPolicyTagValue"
$vmParams = @{
    ResourceGroupName = $resourceGroupName
    Name = $vmName
    Location = $location
    Size = "Standard_B1s"
    Image = "Win2019Datacenter"
    PublicIpAddressName = "$vmName-ip"
    Credential = New-Object System.Management.Automation.PSCredential ($adminUsername, $adminPassword)
    SecurityGroupName = "$vmName-nsg"
    Tag = @{"backup-policy" = $backupPolicyTagValue}
    AsJob = $true
}

$job = New-AzVm @vmParams

Write-Host "VM creation started in the background. You can check the status with: Get-Job -Id $($job.Id)"
Write-Host "Once the VM is created, the Azure Policy should automatically assign it to the appropriate Recovery Services Vault."
Write-Host "To check if the VM was assigned to the vault, run: ./check_vm_backup_status.ps1 -VmName $vmName"
