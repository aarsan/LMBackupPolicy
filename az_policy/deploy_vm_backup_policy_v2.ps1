# Define variables
$policyName = "Liberty Mutual VM Backup Policy V2"
$policyDescription = "Automatically configures backup for VMs tagged with 'backup-policy' to the appropriate Recovery Services Vault with the correct policy"
$policyDefinitionPath = ".\liberty_mutual_vm_backup_policy_v2.json"
$resourceGroupName = "LibertyMutualDemo"
$subscriptionId = (Get-AzContext).Subscription.Id
$assignmentName = "LibertyMutualVMBackupPolicy-$(Get-Random -Maximum 99999)"

# Check if user is logged in to Azure
$context = Get-AzContext
if (-not $context) {
    Write-Host "You are not logged in to Azure. Please login first."
    Connect-AzAccount
}

# Set the subscription context
Set-AzContext -SubscriptionId $subscriptionId

# Create a new policy definition
Write-Host "Creating policy definition '$policyName'..."
try {
    # Read the policy definition from the file
    $policyContent = Get-Content -Path $policyDefinitionPath -Raw
    
    # Create a new policy definition
    $definition = New-AzPolicyDefinition -Name $policyName -DisplayName $policyName -Description $policyDescription -Policy $policyContent -Mode Indexed
    Write-Host "Policy definition created successfully:"
    $definition | Format-List Name, ResourceId
} catch {
    Write-Error "Failed to create policy definition: $_"
    exit
}

# Check if Recovery Services Vaults exist
$dailyVault = Get-AzRecoveryServicesVault -ResourceGroupName $resourceGroupName -Name "lm-daily" -ErrorAction SilentlyContinue
$hourlyVault = Get-AzRecoveryServicesVault -ResourceGroupName $resourceGroupName -Name "lm-hourly" -ErrorAction SilentlyContinue

if (-not $dailyVault) {
    Write-Error "Recovery Services Vault 'lm-daily' not found in resource group '$resourceGroupName'. Please create it first."
    exit
}

if (-not $hourlyVault) {
    Write-Error "Recovery Services Vault 'lm-hourly' not found in resource group '$resourceGroupName'. Please create it first."
    exit
}

# Check if backup policies exist in both vaults
Set-AzRecoveryServicesVaultContext -Vault $dailyVault
$dailyPolicy = Get-AzRecoveryServicesBackupProtectionPolicy -Name "EnhancedPolicy-Daily" -ErrorAction SilentlyContinue

Set-AzRecoveryServicesVaultContext -Vault $hourlyVault
$hourlyPolicy = Get-AzRecoveryServicesBackupProtectionPolicy -Name "EnhancedPolicy-Hourly" -ErrorAction SilentlyContinue

if (-not $dailyPolicy) {
    Write-Error "Backup policy 'EnhancedPolicy-Daily' not found in vault 'lm-daily'. Please create it first."
    exit
}

if (-not $hourlyPolicy) {
    Write-Error "Backup policy 'EnhancedPolicy-Hourly' not found in vault 'lm-hourly'. Please create it first."
    exit
}

# Check if policy is already assigned to the resource group
$scope = "/subscriptions/$subscriptionId/resourceGroups/$resourceGroupName"
$existingAssignment = Get-AzPolicyAssignment -Scope $scope | 
    Where-Object { $_.Name -eq $assignmentName }

if ($existingAssignment) {
    Write-Host "Policy is already assigned to resource group '$resourceGroupName'. Removing old assignment..."
    Remove-AzPolicyAssignment -Id $existingAssignment.Id -Confirm:$false
    Write-Host "Waiting 30 seconds to ensure assignment is fully removed..."
    Start-Sleep -Seconds 30
}

# Assign policy to the resource group
Write-Host "Assigning policy to resource group '$resourceGroupName' with system-assigned managed identity..."
if (-not $definition -or -not $definition.Id) {
    Write-Error "Policy definition creation failed or Id is missing."
    exit
}
$assignment = New-AzPolicyAssignment -Name $assignmentName `
    -DisplayName "Liberty Mutual VM Backup Policy V2" `
    -PolicyDefinition $definition `
    -Scope $scope `
    -IdentityType SystemAssigned `
    -Location (Get-AzResourceGroup -Name $resourceGroupName).Location

# Wait for the managed identity to be created and available in Azure AD
$maxAttempts = 20
$attempt = 0
$principalId = $null
Write-Host "Initial assignment identity: $($assignment.Identity.PrincipalId)"

# Longer wait time and better error handling
while ($attempt -lt $maxAttempts) {
    Write-Host "Waiting for managed identity to be provisioned... (Attempt $($attempt+1)/$maxAttempts)"
    Start-Sleep -Seconds 10
    try {
        $assignment = Get-AzPolicyAssignment -Name $assignmentName -Scope $scope -ErrorAction Stop
        if ($assignment.Identity -and $assignment.Identity.PrincipalId) {
            $principalId = $assignment.Identity.PrincipalId
            Write-Host "Managed identity created with principal ID: $principalId"
            break
        }
    } catch {
        Write-Host "Error retrieving policy assignment: $_"
    }
    $attempt++
}
$principalId = $assignment.Identity.PrincipalId

if ($principalId) {
    Write-Host "Assigning Contributor and Backup Operator roles to the policy assignment's managed identity..."
    $roleDefinitionIds = @(
        (Get-AzRoleDefinition -Name "Contributor").Id,
        (Get-AzRoleDefinition -Name "Backup Operator").Id
    )
    foreach ($roleDefinitionId in $roleDefinitionIds) {
        New-AzRoleAssignment -ObjectId $principalId `
            -Scope "/subscriptions/$subscriptionId/resourceGroups/$resourceGroupName" `
            -RoleDefinitionId $roleDefinitionId -ErrorAction SilentlyContinue
    }
    # Also assign to both vaults
    $vaultNames = @("lm-daily", "lm-hourly")
    foreach ($vaultName in $vaultNames) {
        $vault = Get-AzRecoveryServicesVault -ResourceGroupName $resourceGroupName -Name $vaultName -ErrorAction SilentlyContinue
        if ($vault) {
            foreach ($roleDefinitionId in $roleDefinitionIds) {
                New-AzRoleAssignment -ObjectId $principalId `
                    -Scope $vault.Id `
                    -RoleDefinitionId $roleDefinitionId -ErrorAction SilentlyContinue
            }
        }
    }
} else {
    Write-Error "Managed identity was NOT created after waiting. Please check the policy assignment in the Azure Portal and try again with a new assignment name if needed."
    exit
}

Write-Host "Policy deployment complete. New VMs created with backup-policy tag 'daily' will be backed up to lm-daily vault using EnhancedPolicy-Daily."
Write-Host "VMs with backup-policy tag 'hourly' will be backed up to lm-hourly vault using EnhancedPolicy-Hourly."
Write-Host "The policy will automatically apply to any VMs with the appropriate tags."
