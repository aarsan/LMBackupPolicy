# Set the context
$vaultName = "lm-vault"
$resourceGroupName = "LibertyMutualDemo"
$vmName = "backup-client"
# $currentPolicyName = "EnhancedPolicy"
# $newPolicyName = "WebServerPolicyv2"
$newPolicyName = "EnhancedPolicy"

# Get the Recovery Services vault
$vault = Get-AzRecoveryServicesVault -Name $vaultName -ResourceGroupName $resourceGroupName

# Set the Recovery Services vault context
Set-AzRecoveryServicesVaultContext -Vault $vault

# Get the current backup policy
# $currentPolicy = Get-AzRecoveryServicesBackupProtectionPolicy -Name $currentPolicyName
# Get the new backup policy
$newPolicy = Get-AzRecoveryServicesBackupProtectionPolicy -Name $newPolicyName

# Get the backup item for the VM
# $namedContainer = Get-AzRecoveryServicesBackupContainer -ContainerType AzureVM -FriendlyName $vmName
$backupItem = Get-AzRecoveryServicesBackupItem -BackupManagementType AzureVM -WorkloadType AzureVM -Name $vmName

Write-Host "VM Name: $vmName"
Write-Host "Current Policy Name: $($backupItem.ProtectionPolicyName)"

# Change the backup policy
# Write-Host "Changing backup policy from $($backupItem.ProtectionPolicyName) to $newPolicyName"
# Enable-AzRecoveryServicesBackupProtection -Item $backupItem -Policy $newPolicy

