# This script creates simple backup policies in the recovery services vaults
param(
    [Parameter(Mandatory=$false)]
    [string]$ResourceGroupName = "LibertyMutualDemo"
)

# Configuration
$dailyVaultName = "lm-daily"
$hourlyVaultName = "lm-hourly"
$dailyPolicyName = "EnhancedPolicy-Daily" 
$hourlyPolicyName = "EnhancedPolicy-Hourly"
$location = "centralus"  # Change to your preferred location

# Login to Azure if not already logged in
$context = Get-AzContext
if (-not $context) {
    Write-Host "Please log in to Azure first"
    Connect-AzAccount
}

# Ensure resource group exists
$rg = Get-AzResourceGroup -Name $ResourceGroupName -ErrorAction SilentlyContinue
if (-not $rg) {
    Write-Host "Creating resource group $ResourceGroupName..."
    New-AzResourceGroup -Name $ResourceGroupName -Location $location
}

# Function to create Recovery Services Vault if it doesn't exist
function Ensure-RecoveryServicesVault {
    param (
        [string]$VaultName,
        [string]$ResourceGroupName,
        [string]$Location
    )
    
    $vault = Get-AzRecoveryServicesVault -ResourceGroupName $ResourceGroupName -Name $VaultName -ErrorAction SilentlyContinue
    if (-not $vault) {
        Write-Host "Creating Recovery Services Vault $VaultName..."
        $vault = New-AzRecoveryServicesVault -Name $VaultName -ResourceGroupName $ResourceGroupName -Location $Location
    } else {
        Write-Host "Recovery Services Vault $VaultName already exists"
    }
    
    return $vault
}

# Create/ensure vaults exist
$dailyVault = Ensure-RecoveryServicesVault -VaultName $dailyVaultName -ResourceGroupName $ResourceGroupName -Location $location
$hourlyVault = Ensure-RecoveryServicesVault -VaultName $hourlyVaultName -ResourceGroupName $ResourceGroupName -Location $location

# Function to create default backup policy - this uses the default enhanced policy settings
function Create-DefaultBackupPolicy {
    param (
        $Vault,
        [string]$PolicyName
    )
    
    # Set vault context
    Set-AzRecoveryServicesVaultContext -Vault $Vault
    
    # Check if policy already exists
    $policy = Get-AzRecoveryServicesBackupProtectionPolicy -Name $PolicyName -ErrorAction SilentlyContinue
    
    if ($policy) {
        Write-Host "Policy $PolicyName already exists in vault $($Vault.Name)"
        return $policy
    }
    
    Write-Host "Creating backup policy $PolicyName in vault $($Vault.Name)..."
    
    # Create a basic backup policy using the Enhanced policy as template
    $enhancedPolicy = Get-AzRecoveryServicesBackupProtectionPolicy | Where-Object { $_.Name -eq "EnhancedPolicy" -or $_.Name -eq "DefaultPolicy" } | Select-Object -First 1
    
    if ($enhancedPolicy) {
        # Clone the enhanced policy with a new name
        $command = "az backup policy create --name '$PolicyName' --policy '$($enhancedPolicy.Name)' --resource-group '$ResourceGroupName' --vault-name '$($Vault.Name)'"
        Write-Host "Running command: $command"
        Invoke-Expression $command
        Write-Host "Successfully created backup policy $PolicyName in vault $($Vault.Name)" -ForegroundColor Green
    }
    else {
        Write-Host "Could not find EnhancedPolicy or DefaultPolicy in vault $($Vault.Name)" -ForegroundColor Yellow
        Write-Host "Please create the backup policies manually in the Azure Portal"
    }
}

# Create backup policies
Create-DefaultBackupPolicy -Vault $dailyVault -PolicyName $dailyPolicyName
Create-DefaultBackupPolicy -Vault $hourlyVault -PolicyName $hourlyPolicyName

Write-Host "`nNext steps:" -ForegroundColor Cyan
Write-Host "1. Now that the policies are created, continue with deploying the Azure Policy"
Write-Host "2. Run: cd ..\az_policy && .\deploy_vm_backup_policy.ps1"
Write-Host "3. Create test VMs with tags: .\create_tagged_vm.ps1 -BackupTag 'daily'"
Write-Host "4. Check backup status: .\check_vm_backup_status.ps1"
