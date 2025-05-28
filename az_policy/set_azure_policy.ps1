$policyName = "Configure backup on virtual machines with a given tag to a new recovery services vault with a given policy"

# Previous assignment ID (for reference)
$assignment_id = "/subscriptions/edfeee88-1f3d-413a-b4d6-884d1f694077/resourcegroups/libertymutualdemo/providers/microsoft.authorization/policyassignments/2ab9c41d62fd4703b06a6a85"

# Call the deployment script
Write-Host "Deploying Liberty Mutual VM backup policy..."
& .\deploy_vm_backup_policy.ps1