# This script creates the daily and hourly backup policies in their respective vaults using ARM templates

# Configuration
$resourceGroupName = "LibertyMutualDemo"
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
$rg = Get-AzResourceGroup -Name $resourceGroupName -ErrorAction SilentlyContinue
if (-not $rg) {
    Write-Host "Creating resource group $resourceGroupName..."
    New-AzResourceGroup -Name $resourceGroupName -Location $location
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
$dailyVault = Ensure-RecoveryServicesVault -VaultName $dailyVaultName -ResourceGroupName $resourceGroupName -Location $location
$hourlyVault = Ensure-RecoveryServicesVault -VaultName $hourlyVaultName -ResourceGroupName $resourceGroupName -Location $location

# Function to deploy a backup policy using ARM template
function Deploy-BackupPolicy {
    param (
        [string]$VaultName,
        [string]$PolicyName,
        [string]$ResourceGroupName,
        [string]$ScheduleFrequency, # "Daily" or "Hourly"
        [int]$RetentionDays,
        [int]$HourlyInterval = 4 # Only used if ScheduleFrequency is "Hourly"
    )
    
    Write-Host "Creating backup policy $PolicyName in vault $VaultName using ARM template..."

    # Create unique deployment name
    $deploymentName = "$PolicyName-$(Get-Random -Maximum 99999)"

    # Create ARM template parameter object
    $templateParams = @{
        vaultName = $VaultName
        backupManagementType = "AzureIaasVM"
        policyName = $PolicyName
        policyType = "V2"
        instantRpRetentionRangeInDays = 2
        timeZone = "UTC"
    }

    # Set up schedule based on frequency
    if ($ScheduleFrequency -eq "Hourly") {
        $templateParams.schedule = @{
            schedulePolicyType = "SimpleSchedulePolicyV2"
            scheduleRunFrequency = "Hourly"
            hourlySchedule = @{
                interval = $HourlyInterval
                scheduleWindowStartTime = (Get-Date).ToString("yyyy-MM-ddT08:00:00.000Z")
                scheduleWindowDuration = 10
            }
            dailySchedule = $null
            weeklySchedule = $null
        }
    } else {
        $templateParams.schedule = @{
            schedulePolicyType = "SimpleSchedulePolicyV2"
            scheduleRunFrequency = "Daily"
            hourlySchedule = $null
            dailySchedule = @{
                scheduleRunTimes = @(
                    (Get-Date).ToString("yyyy-MM-ddT01:00:00.000Z")
                )
            }
            weeklySchedule = $null
        }
    }

    # Set up retention policy
    $templateParams.retention = @{
        retentionPolicyType = "LongTermRetentionPolicy"
        dailySchedule = @{
            retentionTimes = @(
                (Get-Date).ToString("yyyy-MM-ddT01:00:00.000Z")
            )
            retentionDuration = @{
                count = $RetentionDays
                durationType = "Days"
            }
        }
        weeklySchedule = $null
        monthlySchedule = $null
        yearlySchedule = $null
    }

    # Set up instant RP and tiering policy
    $templateParams.instantRPDetails = @{
        azureBackupRGNamePrefix = "abrg"
    }
    $templateParams.tieringPolicy = @{
        tieringEnabled = $false
    }

    # Create ARM template
    $template = @{
        '$schema' = "https://schema.management.azure.com/schemas/2019-04-01/deploymentTemplate.json#"
        contentVersion = "1.0.0.0"
        parameters = @{
            vaultName = @{ type = "string" }
            backupManagementType = @{ type = "string" }
            policyName = @{ type = "string" }
            policyType = @{ type = "string" }
            instantRpRetentionRangeInDays = @{ type = "int" }
            schedule = @{ type = "object" }
            timeZone = @{ type = "string" }
            retention = @{ type = "object" }
            instantRPDetails = @{ type = "object" }
            tieringPolicy = @{ type = "object" }
        }
        resources = @(
            @{
                type = "Microsoft.RecoveryServices/vaults/backupPolicies"
                apiVersion = "2021-12-01"
                name = "[concat(parameters('vaultName'), '/', parameters('policyName'))]"
                properties = @{
                    backupManagementType = "[parameters('backupManagementType')]"
                    policyType = "[parameters('policyType')]"
                    instantRpRetentionRangeInDays = "[parameters('instantRpRetentionRangeInDays')]"
                    schedulePolicy = "[parameters('schedule')]"
                    timeZone = "[parameters('timeZone')]"
                    retentionPolicy = "[parameters('retention')]"
                    instantRPDetails = "[parameters('instantRPDetails')]"
                    tieringPolicy = "[parameters('tieringPolicy')]"
                }
            }
        )
    }

    # Convert to JSON
    $templateJson = $template | ConvertTo-Json -Depth 10
    $templateParamsJson = $templateParams | ConvertTo-Json -Depth 10

    # Save to temporary files
    $templateFile = [System.IO.Path]::GetTempFileName()
    $templateParamsFile = [System.IO.Path]::GetTempFileName()
    $templateJson | Out-File -FilePath $templateFile -Force
    $templateParamsJson | Out-File -FilePath $templateParamsFile -Force

    try {
        # Deploy the template
        New-AzResourceGroupDeployment -Name $deploymentName `
            -ResourceGroupName $ResourceGroupName `
            -TemplateFile $templateFile `
            -TemplateParameterFile $templateParamsFile `
            -Mode Incremental `
            -Force
        
        Write-Host "Successfully created backup policy $PolicyName in vault $VaultName" -ForegroundColor Green
    }
    catch {
        Write-Error "Failed to create backup policy: $_"
    }
    finally {
        # Clean up temporary files
        Remove-Item -Path $templateFile -Force -ErrorAction SilentlyContinue
        Remove-Item -Path $templateParamsFile -Force -ErrorAction SilentlyContinue
    }
}

# Deploy the backup policies
Deploy-BackupPolicy -VaultName $dailyVaultName -PolicyName $dailyPolicyName -ResourceGroupName $resourceGroupName -ScheduleFrequency "Daily" -RetentionDays 30
Deploy-BackupPolicy -VaultName $hourlyVaultName -PolicyName $hourlyPolicyName -ResourceGroupName $resourceGroupName -ScheduleFrequency "Hourly" -RetentionDays 7 -HourlyInterval 1

Write-Host "Backup policy creation process completed." -ForegroundColor Green
Write-Host "- $dailyPolicyName in $dailyVaultName vault (Daily with 30-day retention)"
Write-Host "- $hourlyPolicyName in $hourlyVaultName vault (Hourly with 7-day retention)"
