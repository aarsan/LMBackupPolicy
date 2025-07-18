# Transfer VM Backup Between Recovery Services Vaults
# This script disconnects a VM from one Recovery Services Vault and connects it to another

param(
    [Parameter(Mandatory=$true)]
    [string]$VmName,
    
    [Parameter(Mandatory=$true)]
    [string]$SourceVaultName,
    
    [Parameter(Mandatory=$true)]
    [string]$TargetVaultName,
    
    [Parameter(Mandatory=$false)]
    [string]$ResourceGroupName = "LibertyMutualDemo",
    
    [Parameter(Mandatory=$false)]
    [string]$TargetPolicyName,
    
    [Parameter(Mandatory=$false)]
    [switch]$Force
)

# Configuration
$location = "centralus"

# Login to Azure if not already logged in
$context = Get-AzContext
if (-not $context) {
    Write-Host "Please log in to Azure first"
    Connect-AzAccount
}

Write-Host "=============================================" -ForegroundColor Cyan
Write-Host "VM Backup Transfer Script" -ForegroundColor Cyan
Write-Host "VM: $VmName" -ForegroundColor Yellow
Write-Host "Source Vault: $SourceVaultName" -ForegroundColor Yellow
Write-Host "Target Vault: $TargetVaultName" -ForegroundColor Yellow
Write-Host "=============================================" -ForegroundColor Cyan

# Get the VM to ensure it exists
Write-Host "DEBUG: Looking for VM '$VmName' in resource group '$ResourceGroupName'" -ForegroundColor Magenta
Write-Host "DEBUG: VM name length: $($VmName.Length)" -ForegroundColor Magenta
Write-Host "DEBUG: Resource group name length: $($ResourceGroupName.Length)" -ForegroundColor Magenta

$vm = Get-AzVM -ResourceGroupName $ResourceGroupName -Name $VmName -ErrorAction SilentlyContinue
if (-not $vm) {
    Write-Host "DEBUG: Available VMs in resource group '$ResourceGroupName':" -ForegroundColor Magenta
    Get-AzVM -ResourceGroupName $ResourceGroupName -ErrorAction SilentlyContinue | ForEach-Object { 
        Write-Host "  - '$($_.Name)' (length: $($_.Name.Length))" -ForegroundColor Magenta 
    }
    Write-Error "VM '$VmName' not found in resource group '$ResourceGroupName'"
    exit 1
}

# Get the source vault
$sourceVault = Get-AzRecoveryServicesVault -ResourceGroupName $ResourceGroupName -Name $SourceVaultName -ErrorAction SilentlyContinue
if (-not $sourceVault) {
    Write-Error "Source vault '$SourceVaultName' not found in resource group '$ResourceGroupName'"
    exit 1
}

# Get the target vault
$targetVault = Get-AzRecoveryServicesVault -ResourceGroupName $ResourceGroupName -Name $TargetVaultName -ErrorAction SilentlyContinue
if (-not $targetVault) {
    Write-Error "Target vault '$TargetVaultName' not found in resource group '$ResourceGroupName'"
    exit 1
}

# Step 1: Check if VM is currently protected in the source vault
Write-Host "`n1. Checking current backup status in source vault..." -ForegroundColor Green
Set-AzRecoveryServicesVaultContext -Vault $sourceVault

$sourceContainer = Get-AzRecoveryServicesBackupContainer -ContainerType AzureVM -FriendlyName $VmName -ErrorAction SilentlyContinue
if (-not $sourceContainer.Status -eq "Registered") {
    Write-Warning "VM '$VmName' is not registered in source vault '$SourceVaultName'"
    Write-Host "Checking if it's already in the target vault..."
    
    # Check target vault
    Set-AzRecoveryServicesVaultContext -Vault $targetVault
    $targetContainer = Get-AzRecoveryServicesBackupContainer -ContainerType AzureVM -FriendlyName $VmName -ErrorAction SilentlyContinue
    if ($targetContainer.Status -eq "Registered") {
        $targetBackupItem = Get-AzRecoveryServicesBackupItem -Container $targetContainer -WorkloadType AzureVM -ErrorAction SilentlyContinue
        if ($targetBackupItem) {
            Write-Host "VM is already protected in target vault '$TargetVaultName' with policy '$($targetBackupItem.ProtectionPolicyName)'" -ForegroundColor Green
            exit 0
        }
    }
    
    Write-Host "VM is not protected in any vault. Proceeding to enable protection in target vault..." -ForegroundColor Yellow
    $skipDisableProtection = $true
} else {
    $sourceBackupItem = Get-AzRecoveryServicesBackupItem -Container $sourceContainer -WorkloadType AzureVM -ErrorAction SilentlyContinue
    if ($sourceBackupItem) {
        Write-Host "VM is currently protected in source vault with policy: $($sourceBackupItem.ProtectionPolicyName)" -ForegroundColor White
        $skipDisableProtection = $false
    } else {
        Write-Warning "VM container found but no backup item. This might indicate a partial configuration."
        $skipDisableProtection = $true
    }
}

# Step 2: Disable protection in source vault (if needed)
if (-not $skipDisableProtection) {
    Write-Host "`n2. Disabling backup protection in source vault..." -ForegroundColor Green
    
    if (-not $Force) {
        $confirm = Read-Host "Are you sure you want to disable backup protection for VM '$VmName' in vault '$SourceVaultName'? (y/N)"
        if ($confirm -ne 'y' -and $confirm -ne 'Y') {
            Write-Host "Operation cancelled by user." -ForegroundColor Yellow
            exit 0
        }
    }
    
    try {
        Set-AzRecoveryServicesVaultContext -Vault $sourceVault
        
        # Disable protection but retain backup data
        Write-Host "Disabling protection while retaining backup data..." -ForegroundColor Yellow
        Disable-AzRecoveryServicesBackupProtection -Item $sourceBackupItem -Force
        
        Write-Host "Backup protection disabled successfully in source vault." -ForegroundColor Green
        
        # Wait a moment for the operation to complete
        Write-Host "Waiting 30 seconds for the disable operation to complete..." -ForegroundColor Yellow
        Start-Sleep -Seconds 30
        
    } catch {
        Write-Error "Failed to disable backup protection in source vault: $_"
        exit 1
    }
} else {
    Write-Host "`n2. Skipping disable protection (VM not currently protected)" -ForegroundColor Yellow
}

# Step 3: Get target backup policy
Write-Host "`n3. Setting up target vault configuration..." -ForegroundColor Green
Set-AzRecoveryServicesVaultContext -Vault $targetVault

if ($TargetPolicyName) {
    $targetPolicy = Get-AzRecoveryServicesBackupProtectionPolicy -Name $TargetPolicyName -ErrorAction SilentlyContinue
    if (-not $targetPolicy) {
        Write-Error "Target backup policy '$TargetPolicyName' not found in vault '$TargetVaultName'"
        exit 1
    }
} else {
    # Try to get a default policy
    $targetPolicy = Get-AzRecoveryServicesBackupProtectionPolicy | Where-Object { $_.Name -eq "DefaultPolicy" -or $_.Name -like "*Enhanced*" } | Select-Object -First 1
    if (-not $targetPolicy) {
        Write-Error "No suitable backup policy found in target vault '$TargetVaultName'. Please specify -TargetPolicyName parameter."
        exit 1
    }
}

Write-Host "Using target policy: $($targetPolicy.Name)" -ForegroundColor White

# Step 4: Enable protection in target vault
Write-Host "`n4. Enabling backup protection in target vault..." -ForegroundColor Green

try {
    # Enable backup protection
    Write-Host "Enabling backup protection for VM '$VmName' with policy '$($targetPolicy.Name)'..." -ForegroundColor Yellow
    
    Enable-AzRecoveryServicesBackupProtection -Policy $targetPolicy -Name $VmName -ResourceGroupName $ResourceGroupName
    
    Write-Host "Backup protection enabled successfully in target vault!" -ForegroundColor Green
    
    # Wait for the operation to complete
    Write-Host "Waiting 60 seconds for the enable operation to complete..." -ForegroundColor Yellow
    Start-Sleep -Seconds 60
    
} catch {
    Write-Error "Failed to enable backup protection in target vault: $_"
    Write-Host "You may need to manually enable protection in the Azure Portal." -ForegroundColor Yellow
    exit 1
}

# Step 5: Verify the transfer
Write-Host "`n5. Verifying the backup transfer..." -ForegroundColor Green

Set-AzRecoveryServicesVaultContext -Vault $targetVault
$newContainer = Get-AzRecoveryServicesBackupContainer -ContainerType AzureVM -FriendlyName $VmName -ErrorAction SilentlyContinue

if ($newContainer.Status -eq "Registered") {
    $newBackupItem = Get-AzRecoveryServicesBackupItem -Container $newContainer -WorkloadType AzureVM -ErrorAction SilentlyContinue
    if ($newBackupItem) {
        Write-Host "✓ SUCCESS: VM backup successfully transferred!" -ForegroundColor Green
        Write-Host "  VM: $VmName" -ForegroundColor White
        Write-Host "  Target Vault: $TargetVaultName" -ForegroundColor White
        Write-Host "  Policy: $($newBackupItem.ProtectionPolicyName)" -ForegroundColor White
        Write-Host "  Protection Status: $($newBackupItem.ProtectionStatus)" -ForegroundColor White
    } else {
        Write-Warning "VM container found in target vault but no backup item detected yet. This may take some time to appear."
    }
} else {
    Write-Warning "VM not yet registered in target vault. This may take some time to appear in the portal."
}

Write-Host "`n=============================================" -ForegroundColor Cyan
Write-Host "Transfer operation completed!" -ForegroundColor Cyan
Write-Host "Note: It may take up to 30 minutes for the VM to appear" -ForegroundColor Yellow
Write-Host "in the target vault's protected items list." -ForegroundColor Yellow
Write-Host "=============================================" -ForegroundColor Cyan
