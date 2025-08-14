# Script to Configure Azure Key Vault RBAC Permissions
# This script assigns the necessary RBAC roles for Key Vault access

param(
    [Parameter(Mandatory=$true)]
    [string]$KeyVaultName,
    
    [Parameter(Mandatory=$true)]
    [string]$ResourceGroupName,
    
    [Parameter(Mandatory=$false)]
    [string]$UserObjectId = "",
    
    [Parameter(Mandatory=$false)]
    [string]$UserPrincipalName = ""
)

Write-Host "==================================================" -ForegroundColor Cyan
Write-Host "Azure Key Vault RBAC Configuration Script" -ForegroundColor Cyan
Write-Host "==================================================" -ForegroundColor Cyan
Write-Host ""

# Check if logged in to Azure
Write-Host "Checking Azure login status..." -ForegroundColor Yellow
$account = az account show 2>$null
if ($LASTEXITCODE -ne 0) {
    Write-Host "Error: Not logged in to Azure. Please run 'az login' first." -ForegroundColor Red
    exit 1
}

$currentAccount = az account show --query "{Name:name, Id:id}" -o json | ConvertFrom-Json
Write-Host "Using subscription: $($currentAccount.Name)" -ForegroundColor Green
Write-Host ""

# Get Key Vault details
Write-Host "Getting Key Vault information..." -ForegroundColor Yellow
$keyVaultId = az keyvault show --name $KeyVaultName --resource-group $ResourceGroupName --query id -o tsv 2>$null

if (-not $keyVaultId) {
    Write-Host "Error: Key Vault '$KeyVaultName' not found in resource group '$ResourceGroupName'." -ForegroundColor Red
    
    # List available Key Vaults
    Write-Host "`nAvailable Key Vaults in subscription:" -ForegroundColor Yellow
    az keyvault list --query "[].{Name:name, ResourceGroup:resourceGroup}" -o table
    exit 1
}

Write-Host "Found Key Vault: $KeyVaultName" -ForegroundColor Green
Write-Host "Resource ID: $keyVaultId" -ForegroundColor DarkGray
Write-Host ""

# Check if Key Vault is using RBAC
Write-Host "Checking Key Vault authorization mode..." -ForegroundColor Yellow
$enableRbac = az keyvault show --name $KeyVaultName --resource-group $ResourceGroupName --query "properties.enableRbacAuthorization" -o tsv

if ($enableRbac -eq "false") {
    Write-Host "Key Vault is currently using Access Policies (not RBAC)." -ForegroundColor Yellow
    Write-Host "Do you want to switch to RBAC authorization? (y/n): " -NoNewline -ForegroundColor Yellow
    $switchToRbac = Read-Host
    
    if ($switchToRbac -eq 'y' -or $switchToRbac -eq 'Y') {
        Write-Host "Switching Key Vault to RBAC authorization..." -ForegroundColor Yellow
        az keyvault update --name $KeyVaultName --resource-group $ResourceGroupName --enable-rbac-authorization true
        
        if ($LASTEXITCODE -eq 0) {
            Write-Host "Successfully switched to RBAC authorization." -ForegroundColor Green
        } else {
            Write-Host "Error: Failed to switch to RBAC authorization." -ForegroundColor Red
            exit 1
        }
    } else {
        Write-Host "Keeping Access Policies mode. Exiting..." -ForegroundColor Yellow
        exit 0
    }
} else {
    Write-Host "Key Vault is already using RBAC authorization." -ForegroundColor Green
}
Write-Host ""

# Get user information
if (-not $UserObjectId -and -not $UserPrincipalName) {
    Write-Host "No user specified. Using current logged-in user..." -ForegroundColor Yellow
    $UserObjectId = az ad signed-in-user show --query id -o tsv 2>$null
    $userInfo = az ad signed-in-user show --query "{DisplayName:displayName, UPN:userPrincipalName, ObjectId:id}" -o json | ConvertFrom-Json
    
    if (-not $UserObjectId) {
        Write-Host "Error: Could not get current user information." -ForegroundColor Red
        exit 1
    }
    
    Write-Host "Current user: $($userInfo.DisplayName)" -ForegroundColor Cyan
    Write-Host "UPN: $($userInfo.UPN)" -ForegroundColor DarkGray
    Write-Host "Object ID: $($userInfo.ObjectId)" -ForegroundColor DarkGray
} elseif ($UserPrincipalName) {
    Write-Host "Getting user information for: $UserPrincipalName" -ForegroundColor Yellow
    $UserObjectId = az ad user show --id $UserPrincipalName --query id -o tsv
    
    if (-not $UserObjectId) {
        Write-Host "Error: User '$UserPrincipalName' not found." -ForegroundColor Red
        exit 1
    }
}
Write-Host ""

# List of roles to assign
$roles = @(
    @{
        Name = "Key Vault Secrets Officer"
        Description = "Perform any action on the secrets of a key vault, except manage permissions"
    },
    @{
        Name = "Key Vault Reader"
        Description = "Read metadata of key vaults and its certificates, keys, and secrets"
    }
)

Write-Host "Assigning RBAC roles..." -ForegroundColor Yellow
Write-Host "----------------------------------------" -ForegroundColor DarkGray

foreach ($role in $roles) {
    Write-Host "`nAssigning role: $($role.Name)" -ForegroundColor Cyan
    Write-Host "Description: $($role.Description)" -ForegroundColor DarkGray
    
    # Check if role assignment already exists
    $existingAssignment = az role assignment list --assignee $UserObjectId --scope $keyVaultId --role "$($role.Name)" --query "[0].id" -o tsv 2>$null
    
    if ($existingAssignment) {
        Write-Host "Role already assigned" -ForegroundColor Green
    } else {
        # Create role assignment
        $assignmentResult = az role assignment create --role "$($role.Name)" --assignee $UserObjectId --scope $keyVaultId 2>&1
        
        if ($LASTEXITCODE -eq 0) {
            Write-Host "Role assigned successfully" -ForegroundColor Green
        } else {
            Write-Host "Failed to assign role" -ForegroundColor Red
            Write-Host "Error: $assignmentResult" -ForegroundColor Red
        }
    }
}

Write-Host ""
Write-Host "----------------------------------------" -ForegroundColor DarkGray
Write-Host ""

# Display current role assignments
Write-Host "Current role assignments for this Key Vault:" -ForegroundColor Yellow
az role assignment list --scope $keyVaultId --query "[].{Principal:principalName, Role:roleDefinitionName}" -o table

Write-Host ""
Write-Host "==================================================" -ForegroundColor Cyan
Write-Host "RBAC Configuration Complete!" -ForegroundColor Green
Write-Host "==================================================" -ForegroundColor Cyan
Write-Host ""
Write-Host "You can now perform the following operations:" -ForegroundColor Yellow
Write-Host "  - Create, read, update, and delete secrets" -ForegroundColor White
Write-Host "  - List all secrets in the Key Vault" -ForegroundColor White
Write-Host "  - Backup and restore secrets" -ForegroundColor White
Write-Host "  - Read Key Vault metadata" -ForegroundColor White
Write-Host ""
Write-Host "Note: RBAC changes may take up to 30 seconds to propagate." -ForegroundColor Yellow

# Test access (optional)
Write-Host ""
Write-Host "Would you like to test secret access? (y/n): " -NoNewline -ForegroundColor Yellow
$testAccess = Read-Host

if ($testAccess -eq 'y' -or $testAccess -eq 'Y') {
    Write-Host ""
    Write-Host "Testing secret access..." -ForegroundColor Yellow
    
    # Try to list secrets
    Write-Host "Attempting to list secrets..." -ForegroundColor Cyan
    $secrets = az keyvault secret list --vault-name $KeyVaultName --query "[].name" -o json 2>&1
    
    if ($LASTEXITCODE -eq 0) {
        Write-Host "Successfully listed secrets" -ForegroundColor Green
        $secretCount = ($secrets | ConvertFrom-Json).Count
        Write-Host "  Found $secretCount secret(s) in the vault" -ForegroundColor DarkGray
    } else {
        Write-Host "Failed to list secrets" -ForegroundColor Red
        Write-Host "  This might be due to RBAC propagation delay. Try again in 30 seconds." -ForegroundColor Yellow
    }
    
    # Try to create a test secret
    Write-Host ""
    Write-Host "Attempting to create a test secret..." -ForegroundColor Cyan
    $testSecretName = "rbac-test-$(Get-Random -Maximum 9999)"
    $testResult = az keyvault secret set --vault-name $KeyVaultName --name $testSecretName --value "test-value" 2>&1
    
    if ($LASTEXITCODE -eq 0) {
        Write-Host "Successfully created test secret: $testSecretName" -ForegroundColor Green
        
        # Clean up test secret
        Write-Host "  Cleaning up test secret..." -ForegroundColor DarkGray
        az keyvault secret delete --vault-name $KeyVaultName --name $testSecretName 2>$null
        Write-Host "  Test secret deleted" -ForegroundColor DarkGray
    } else {
        Write-Host "Failed to create test secret" -ForegroundColor Red
        Write-Host "  Error: $testResult" -ForegroundColor Red
        Write-Host "  This might be due to RBAC propagation delay. Try again in 30 seconds." -ForegroundColor Yellow
    }
}

Write-Host ""
Write-Host "Script completed!" -ForegroundColor Green
