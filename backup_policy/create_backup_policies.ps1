# This script creates the daily and hourly backup policies in their respective vaults
param(
    [Parameter(Mandatory=$false)]
    [string]$ResourceGroupName = "LibertyMutualDemo"
)

# Configuration
$dailyVaultName = "lm-daily"
$hourlyVaultName = "lm-hourly"
$dailyPolicyName = "EnhancedPolicy-Daily"
$hourlyPolicyName = "EnhancedPolicy-Hourly"
$location = "centralus" # Change to your preferred location

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

# Function to create backup policy
function Create-BackupPolicy {
    param (
        $Vault,
        [string]$PolicyName,
        [int]$RetentionDays,
        [bool]$IsHourly = $false
    )
    
    Set-AzRecoveryServicesVaultContext -Vault $Vault
    
    # Check if policy already exists
    $policy = Get-AzRecoveryServicesBackupProtectionPolicy -Name $PolicyName -ErrorAction SilentlyContinue
    if ($policy) {
        Write-Host "Policy $PolicyName already exists in vault $($Vault.Name)"
        return $policy
    }
    
    Write-Host "Creating backup policy $PolicyName in vault $($Vault.Name)..."
    
    # Create schedule and retention policy
    $scheduleTime = Get-Date -Hour 0 -Minute 0 -Second 0
    $timeZone = [System.TimeZoneInfo]::Local.Id
    
    if ($IsHourly) {
        # Create hourly schedule policy with 1 hour frequency
        $schedule = New-AzRecoveryServicesBackupSchedulePolicyObject -WorkloadType AzureVM `
            -ScheduleRunFrequency Hourly `
            -ScheduleRunTimes $scheduleTime `
            -ScheduleInterval 1 `
            -ScheduleRunTimeZone $timeZone
    } else {
        # Create daily schedule policy
        $schedule = New-AzRecoveryServicesBackupSchedulePolicyObject -WorkloadType AzureVM `
            -ScheduleRunFrequency Daily `
            -ScheduleRunTimes $scheduleTime `
            -ScheduleRunTimeZone $timeZone
    }
    
    # Create retention policy
    $retentionPolicy = New-AzRecoveryServicesBackupRetentionPolicyObject -WorkloadType AzureVM `
        -RetentionDailyCount $RetentionDays
    
    # Create and return the backup policy
    return New-AzRecoveryServicesBackupProtectionPolicy `
        -Name $PolicyName `
        -WorkloadType AzureVM `
        -RetentionPolicy $retentionPolicy `
        -SchedulePolicy $schedule
}

# Create backup policies
$dailyBackupPolicy = Create-BackupPolicy -Vault $dailyVault -PolicyName $dailyPolicyName -RetentionDays 30 -IsHourly $false
$hourlyBackupPolicy = Create-BackupPolicy -Vault $hourlyVault -PolicyName $hourlyPolicyName -RetentionDays 7 -IsHourly $true

Write-Host "Backup policies have been created:"
Write-Host "- $dailyPolicyName in $dailyVaultName vault"
Write-Host "- $hourlyPolicyName in $hourlyVaultName vault"
