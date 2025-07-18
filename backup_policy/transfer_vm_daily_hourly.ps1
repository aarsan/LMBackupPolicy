# Transfer VM Between Liberty Mutual Daily and Hourly Backup Vaults
# This script transfers VMs between lm-daily and lm-hourly vaults based on their backup-policy tag

param(
    [Parameter(Mandatory=$true)]
    [string]$VmName,
    
    [Parameter(Mandatory=$false)]
    [string]$ResourceGroupName = "LibertyMutualDemo",
    
    [Parameter(Mandatory=$false)]
    [ValidateSet("daily", "hourly")]
    [string]$NewBackupSchedule,
    
    [Parameter(Mandatory=$false)]
    [switch]$Force
)

# Configuration
$dailyVaultName = "lm-daily"
$hourlyVaultName = "lm-hourly"
$dailyPolicyName = "EnhancedPolicy-Daily"
$hourlyPolicyName = "EnhancedPolicy-Hourly"

# Login to Azure if not already logged in
$context = Get-AzContext
if (-not $context) {
    Write-Host "Please log in to Azure first"
    Connect-AzAccount
}

Write-Host "=============================================" -ForegroundColor Cyan
Write-Host "Liberty Mutual VM Backup Transfer" -ForegroundColor Cyan
Write-Host "VM: $VmName" -ForegroundColor Yellow
Write-Host "=============================================" -ForegroundColor Cyan

# Get the VM and check its current backup-policy tag
$vm = Get-AzVM -ResourceGroupName $ResourceGroupName -Name $VmName -ErrorAction SilentlyContinue
if (-not $vm) {
    Write-Error "VM '$VmName' not found in resource group '$ResourceGroupName'"
    exit 1
}

$currentBackupTag = $vm.Tags["backup-policy"]
Write-Host "Current backup-policy tag: $currentBackupTag" -ForegroundColor Yellow

# Determine target schedule if not specified
if (-not $NewBackupSchedule) {
    if ($currentBackupTag -eq "daily") {
        $NewBackupSchedule = "hourly"
    } elseif ($currentBackupTag -eq "hourly") {
        $NewBackupSchedule = "daily"
    } else {
        Write-Error "VM does not have a valid backup-policy tag (daily/hourly). Current tag: '$currentBackupTag'"
        exit 1
    }
}

# Determine source and target vaults
if ($currentBackupTag -eq "daily") {
    $sourceVaultName = $dailyVaultName
    $sourcePolicyName = $dailyPolicyName
} elseif ($currentBackupTag -eq "hourly") {
    $sourceVaultName = $hourlyVaultName
    $sourcePolicyName = $hourlyPolicyName
} else {
    $sourceVaultName = $null
    $sourcePolicyName = $null
}

if ($NewBackupSchedule -eq "daily") {
    $targetVaultName = $dailyVaultName
    $targetPolicyName = $dailyPolicyName
} else {
    $targetVaultName = $hourlyVaultName
    $targetPolicyName = $hourlyPolicyName
}

Write-Host "Transfer plan:" -ForegroundColor Green
Write-Host "  From: $sourceVaultName ($sourcePolicyName)" -ForegroundColor White
Write-Host "  To: $targetVaultName ($targetPolicyName)" -ForegroundColor White
Write-Host "  New tag value: $NewBackupSchedule" -ForegroundColor White

# Confirm the operation
if (-not $Force) {
    $confirm = Read-Host "`nProceed with transfer? (y/N)"
    if ($confirm -ne 'y' -and $confirm -ne 'Y') {
        Write-Host "Operation cancelled by user." -ForegroundColor Yellow
        exit 0
    }
}

# Get vaults
$sourceVault = Get-AzRecoveryServicesVault -ResourceGroupName $ResourceGroupName -Name $sourceVaultName -ErrorAction SilentlyContinue
$targetVault = Get-AzRecoveryServicesVault -ResourceGroupName $ResourceGroupName -Name $targetVaultName -ErrorAction SilentlyContinue

if (-not $targetVault) {
    Write-Error "Target vault '$targetVaultName' not found"
    exit 1
}

# Step 1: Check current protection status
Write-Host "`n1. Checking current backup protection..." -ForegroundColor Green

$currentlyProtected = $false
$sourceBackupItem = $null

if ($sourceVault) {
    Set-AzRecoveryServicesVaultContext -Vault $sourceVault
    $sourceContainer = Get-AzRecoveryServicesBackupContainer -ContainerType AzureVM -Status Registered -FriendlyName $VmName -ErrorAction SilentlyContinue
    if ($sourceContainer) {
        $sourceBackupItem = Get-AzRecoveryServicesBackupItem -Container $sourceContainer -WorkloadType AzureVM -ErrorAction SilentlyContinue
        if ($sourceBackupItem) {
            $currentlyProtected = $true
            Write-Host "VM is currently protected in $sourceVaultName with policy: $($sourceBackupItem.ProtectionPolicyName)" -ForegroundColor White
        }
    }
}

if (-not $currentlyProtected) {
    Write-Host "VM is not currently protected in the expected vault. Checking both vaults..." -ForegroundColor Yellow
    
    # Check both vaults to see where the VM might be
    foreach ($vaultName in @($dailyVaultName, $hourlyVaultName)) {
        $vault = Get-AzRecoveryServicesVault -ResourceGroupName $ResourceGroupName -Name $vaultName -ErrorAction SilentlyContinue
        if ($vault) {
            Set-AzRecoveryServicesVaultContext -Vault $vault
            $container = Get-AzRecoveryServicesBackupContainer -ContainerType AzureVM -Status Registered -FriendlyName $VmName -ErrorAction SilentlyContinue
            if ($container) {
                $backupItem = Get-AzRecoveryServicesBackupItem -Container $container -WorkloadType AzureVM -ErrorAction SilentlyContinue
                if ($backupItem) {
                    Write-Host "Found VM protected in $vaultName with policy: $($backupItem.ProtectionPolicyName)" -ForegroundColor White
                    $sourceVault = $vault
                    $sourceVaultName = $vaultName
                    $sourceBackupItem = $backupItem
                    $currentlyProtected = $true
                    break
                }
            }
        }
    }
}

# Step 2: Disable protection in source vault (if protected)
if ($currentlyProtected -and $sourceVault.Name -ne $targetVault.Name) {
    Write-Host "`n2. Disabling protection in source vault ($sourceVaultName)..." -ForegroundColor Green
    
    try {
        Set-AzRecoveryServicesVaultContext -Vault $sourceVault
        Disable-AzRecoveryServicesBackupProtection -Item $sourceBackupItem -RetainRecoveryPoints -Force
        Write-Host "Protection disabled successfully" -ForegroundColor Green
        
        # Wait for operation to complete
        Start-Sleep -Seconds 30
    } catch {
        Write-Error "Failed to disable protection: $_"
        exit 1
    }
} elseif ($currentlyProtected -and $sourceVault.Name -eq $targetVault.Name) {
    Write-Host "`n2. VM is already in the target vault. Checking policy..." -ForegroundColor Yellow
    if ($sourceBackupItem.ProtectionPolicyName -eq $targetPolicyName) {
        Write-Host "VM is already using the correct policy. Only updating the tag." -ForegroundColor Green
        $skipProtectionSetup = $true
    } else {
        Write-Host "VM is in the correct vault but using wrong policy. Will update policy." -ForegroundColor Yellow
    }
} else {
    Write-Host "`n2. VM is not currently protected. Will enable protection." -ForegroundColor Yellow
}

# Step 3: Enable protection in target vault or update policy
if (-not $skipProtectionSetup) {
    Write-Host "`n3. Setting up protection in target vault ($targetVaultName)..." -ForegroundColor Green
    
    Set-AzRecoveryServicesVaultContext -Vault $targetVault
    $targetPolicy = Get-AzRecoveryServicesBackupProtectionPolicy -Name $targetPolicyName -ErrorAction SilentlyContinue
    
    if (-not $targetPolicy) {
        Write-Error "Target policy '$targetPolicyName' not found in vault '$targetVaultName'"
        exit 1
    }
    
    try {
        if ($currentlyProtected -and $sourceVault.Name -eq $targetVault.Name) {
            # Just update the policy within the same vault
            Write-Host "Updating backup policy to $targetPolicyName..." -ForegroundColor Yellow
            Enable-AzRecoveryServicesBackupProtection -Item $sourceBackupItem -Policy $targetPolicy
        } else {
            # Enable protection from scratch
            Write-Host "Enabling backup protection with policy $targetPolicyName..." -ForegroundColor Yellow
            Enable-AzRecoveryServicesBackupProtection -Policy $targetPolicy -Name $VmName -ResourceGroupName $ResourceGroupName
        }
        
        Write-Host "Protection configuration updated successfully!" -ForegroundColor Green
        Start-Sleep -Seconds 60
        
    } catch {
        Write-Error "Failed to configure protection: $_"
        exit 1
    }
} else {
    Write-Host "`n3. Skipping protection setup (already correctly configured)" -ForegroundColor Yellow
}

# Step 4: Update the VM's backup-policy tag
Write-Host "`n4. Updating VM's backup-policy tag to '$NewBackupSchedule'..." -ForegroundColor Green

try {
    $tags = $vm.Tags
    if (-not $tags) {
        $tags = @{}
    }
    $tags["backup-policy"] = $NewBackupSchedule
    
    Update-AzVM -ResourceGroupName $ResourceGroupName -VM $vm -Tag $tags
    Write-Host "VM tag updated successfully!" -ForegroundColor Green
    
} catch {
    Write-Warning "Failed to update VM tag: $_"
    Write-Host "Please manually update the backup-policy tag to '$NewBackupSchedule' in the Azure Portal" -ForegroundColor Yellow
}

# Step 5: Verify the final configuration
Write-Host "`n5. Verifying final configuration..." -ForegroundColor Green

Set-AzRecoveryServicesVaultContext -Vault $targetVault
$finalContainer = Get-AzRecoveryServicesBackupContainer -ContainerType AzureVM -Status Registered -FriendlyName $VmName -ErrorAction SilentlyContinue

if ($finalContainer) {
    $finalBackupItem = Get-AzRecoveryServicesBackupItem -Container $finalContainer -WorkloadType AzureVM -ErrorAction SilentlyContinue
    if ($finalBackupItem) {
        Write-Host "✓ SUCCESS: VM backup transfer completed!" -ForegroundColor Green
        Write-Host "  VM: $VmName" -ForegroundColor White
        Write-Host "  Vault: $targetVaultName" -ForegroundColor White
        Write-Host "  Policy: $($finalBackupItem.ProtectionPolicyName)" -ForegroundColor White
        Write-Host "  Protection Status: $($finalBackupItem.ProtectionStatus)" -ForegroundColor White
        Write-Host "  New backup-policy tag: $NewBackupSchedule" -ForegroundColor White
    } else {
        Write-Warning "VM container found but backup item not yet visible. This may take some time."
    }
} else {
    Write-Warning "VM not yet visible in target vault. Configuration may still be processing."
}

Write-Host "`n=============================================" -ForegroundColor Cyan
Write-Host "Transfer operation completed!" -ForegroundColor Cyan
Write-Host "Note: It may take up to 30 minutes for changes" -ForegroundColor Yellow
Write-Host "to be fully reflected in the Azure Portal." -ForegroundColor Yellow
Write-Host "=============================================" -ForegroundColor Cyan
