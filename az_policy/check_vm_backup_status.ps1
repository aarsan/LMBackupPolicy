
param(
    [Parameter(Mandatory=$false)]
    [string]$VmName,
    
    [Parameter(Mandatory=$false)]
    [string]$ResourceGroupName = "LibertyMutualDemo"
)

# Configuration
$dailyVaultName = "lm-daily"
$hourlyVaultName = "lm-hourly"
$dailyPolicyName = "EnhancedPolicy-Daily"
$hourlyPolicyName = "EnhancedPolicy-Hourly"

# Login to Azure if not already logged in
$context = Get-AzContext
if (-not $context) {
    Connect-AzAccount
}

# Get all VMs if no specific name is provided
if (-not $VmName) {
    $vms = Get-AzVM -ResourceGroupName $ResourceGroupName
} else {
    $vms = Get-AzVM -ResourceGroupName $ResourceGroupName -Name $VmName
    
    if (-not $vms) {
        Write-Error "VM '$VmName' not found in resource group '$ResourceGroupName'."
        exit
    }
}

foreach ($vm in $vms) {
    $vmName = $vm.Name
    
    # Check the backup policy tag
    $backupPolicyTag = $vm.Tags["backup-policy"]
    Write-Host "`n===============================================" -ForegroundColor Cyan
    Write-Host "VM: $vmName" -ForegroundColor Cyan
    Write-Host "backup-policy tag: $backupPolicyTag" -ForegroundColor Yellow
    
    # If no backup-policy tag exists, skip
    if (-not $backupPolicyTag) {
        Write-Host "No backup-policy tag found. This VM won't be backed up by the policy." -ForegroundColor Gray
        continue
    }

    # Expected vault based on tag
    $expectedVault = if ($backupPolicyTag -eq "daily") { $dailyVaultName } else { $hourlyVaultName }
    $expectedPolicy = if ($backupPolicyTag -eq "daily") { $dailyPolicyName } else { $hourlyPolicyName }
    Write-Host "Expected vault: $expectedVault" -ForegroundColor Yellow
    Write-Host "Expected policy: $expectedPolicy" -ForegroundColor Yellow

    # Check both vaults for the VM
    $dailyVault = Get-AzRecoveryServicesVault -ResourceGroupName $ResourceGroupName -Name $dailyVaultName -ErrorAction SilentlyContinue
    $hourlyVault = Get-AzRecoveryServicesVault -ResourceGroupName $ResourceGroupName -Name $hourlyVaultName -ErrorAction SilentlyContinue

    $foundInDailyVault = $false
    $foundInHourlyVault = $false
    $dailyPolicyFound = $null
    $hourlyPolicyFound = $null

    if ($dailyVault) {
        Set-AzRecoveryServicesVaultContext -Vault $dailyVault
        $container = Get-AzRecoveryServicesBackupContainer -ContainerType AzureVM -Status Registered -FriendlyName $vmName -ErrorAction SilentlyContinue
        if ($container) {
            $backupItem = Get-AzRecoveryServicesBackupItem -Container $container -WorkloadType AzureVM -ErrorAction SilentlyContinue
            if ($backupItem) {
                $foundInDailyVault = $true
                $dailyPolicyFound = $backupItem.ProtectionPolicyName
                Write-Host "Found in daily vault ($dailyVaultName)" -ForegroundColor Green
                Write-Host "  Backup Policy: $($backupItem.ProtectionPolicyName)" -ForegroundColor White
                Write-Host "  Protection Status: $($backupItem.ProtectionStatus)" -ForegroundColor White
                Write-Host "  Last Backup Status: $($backupItem.LastBackupStatus)" -ForegroundColor White
            }
        }
    }

    if ($hourlyVault) {
        Set-AzRecoveryServicesVaultContext -Vault $hourlyVault
        $container = Get-AzRecoveryServicesBackupContainer -ContainerType AzureVM -Status Registered -FriendlyName $vmName -ErrorAction SilentlyContinue
        if ($container) {
            $backupItem = Get-AzRecoveryServicesBackupItem -Container $container -WorkloadType AzureVM -ErrorAction SilentlyContinue
            if ($backupItem) {
                $foundInHourlyVault = $true
                $hourlyPolicyFound = $backupItem.ProtectionPolicyName
                Write-Host "Found in hourly vault ($hourlyVaultName)" -ForegroundColor Green
                Write-Host "  Backup Policy: $($backupItem.ProtectionPolicyName)" -ForegroundColor White
                Write-Host "  Protection Status: $($backupItem.ProtectionStatus)" -ForegroundColor White
                Write-Host "  Last Backup Status: $($backupItem.LastBackupStatus)" -ForegroundColor White
            }
        }
    }

    if (-not ($foundInDailyVault -or $foundInHourlyVault)) {
        Write-Host "VM is not registered in any vault yet." -ForegroundColor Red
        Write-Host "  This could be because:" -ForegroundColor Yellow
        Write-Host "  1. The policy may still be processing (can take up to 30 minutes)" -ForegroundColor Yellow
        Write-Host "  2. The policy assignment might have failed" -ForegroundColor Yellow
        Write-Host "  3. The managed identity might not have proper permissions" -ForegroundColor Yellow
        Write-Host "You can check the policy assignment status in the Azure Portal:" -ForegroundColor Gray
        Write-Host "  1. Go to the LibertyMutualDemo resource group" -ForegroundColor Gray
        Write-Host "  2. Click on 'Policies' in the left navigation" -ForegroundColor Gray
        Write-Host "  3. Look for 'Liberty Mutual VM Backup Policy' assignment and check its compliance state" -ForegroundColor Gray
    } else {
        # Check correct vault
        $correctVault = if ($backupPolicyTag -eq "daily" -and $foundInDailyVault) { $true } 
                        elseif ($backupPolicyTag -eq "hourly" -and $foundInHourlyVault) { $true } 
                        else { $false }
                        
        # Check correct policy
        $correctPolicy = if ($backupPolicyTag -eq "daily" -and $dailyPolicyFound -eq $dailyPolicyName) { $true }
                        elseif ($backupPolicyTag -eq "hourly" -and $hourlyPolicyFound -eq $hourlyPolicyName) { $true }
                        else { $false }
        
        if ($correctVault -and $correctPolicy) {
            Write-Host "✓ SUCCESS: VM is correctly protected with the appropriate vault and policy based on its tag." -ForegroundColor Green
        } else {
            if (-not $correctVault) {
                Write-Host "✗ WARNING: VM is assigned to a vault that doesn't match its tag." -ForegroundColor Red
            }
            if (-not $correctPolicy) {
                Write-Host "✗ WARNING: VM is using the wrong backup policy." -ForegroundColor Red
                Write-Host "  Expected: $expectedPolicy" -ForegroundColor Yellow
                Write-Host "  Actual: $(if ($backupPolicyTag -eq 'daily') { $dailyPolicyFound } else { $hourlyPolicyFound })" -ForegroundColor Yellow
            }
        }
    }
}
