# Azure Deployment Script for MCP SQL Server
# Prerequisites: Azure CLI installed and logged in

param(
    [Parameter(Mandatory=$true)]
    [string]$ResourceGroupName,
    
    [Parameter(Mandatory=$true)]
    [string]$Location,
    
    [Parameter(Mandatory=$true)]
    [string]$ContainerName,
    
    [Parameter(Mandatory=$false)]
    [string]$RegistryName = "cofmcpregistry",
    
    [Parameter(Mandatory=$false)]
    [string]$KeyVaultName = "cof-mcp-keyvault",
    
    [Parameter(Mandatory=$false)]
    [switch]$SkipKeyVault = $false
)

Write-Host "Starting Azure deployment for MCP SQL Server..." -ForegroundColor Green

# 0. Check and select Azure subscription
Write-Host "`nChecking Azure subscriptions..." -ForegroundColor Yellow

# Get all subscriptions
$subscriptions = az account list --query "[].{Name:name, Id:id, IsDefault:isDefault}" -o json | ConvertFrom-Json

if ($subscriptions.Count -eq 0) {
    Write-Host "Error: No Azure subscriptions found. Please run 'az login' first." -ForegroundColor Red
    exit 1
}

# Display current subscription
$currentSub = $subscriptions | Where-Object { $_.IsDefault -eq $true }
Write-Host "`nCurrent subscription: " -NoNewline -ForegroundColor Cyan
Write-Host "$($currentSub.Name) ($($currentSub.Id))" -ForegroundColor White

# Ask if user wants to change subscription
if ($subscriptions.Count -gt 1) {
    Write-Host "`nAvailable subscriptions:" -ForegroundColor Yellow
    for ($i = 0; $i -lt $subscriptions.Count; $i++) {
        $sub = $subscriptions[$i]
        $prefix = if ($sub.IsDefault) { "*" } else { " " }
        Write-Host "$prefix [$i] $($sub.Name)" -ForegroundColor White
    }
    
    Write-Host "`nDo you want to use the current subscription? (Y/n): " -NoNewline -ForegroundColor Yellow
    $useCurrentSub = Read-Host
    
    if ($useCurrentSub -eq 'n' -or $useCurrentSub -eq 'N') {
        Write-Host "Select subscription number: " -NoNewline -ForegroundColor Yellow
        $subIndex = Read-Host
        
        if ($subIndex -match '^\d+$' -and [int]$subIndex -ge 0 -and [int]$subIndex -lt $subscriptions.Count) {
            $selectedSub = $subscriptions[[int]$subIndex]
            Write-Host "Switching to subscription: $($selectedSub.Name)" -ForegroundColor Cyan
            az account set --subscription $selectedSub.Id
            
            if ($LASTEXITCODE -ne 0) {
                Write-Host "Error: Failed to switch subscription." -ForegroundColor Red
                exit 1
            }
            Write-Host "Subscription switched successfully." -ForegroundColor Green
        } else {
            Write-Host "Invalid selection. Using current subscription." -ForegroundColor Yellow
        }
    }
} else {
    Write-Host "Only one subscription available. Proceeding with: $($currentSub.Name)" -ForegroundColor Green
}

Write-Host "`n----------------------------------------" -ForegroundColor DarkGray

# 1. Create Resource Group if it doesn't exist
Write-Host "Creating/Verifying Resource Group..." -ForegroundColor Yellow
az group create --name $ResourceGroupName --location $Location

# 2. Create Azure Container Registry if it doesn't exist
Write-Host "Creating/Verifying Azure Container Registry..." -ForegroundColor Yellow
az acr create --resource-group $ResourceGroupName `
    --name $RegistryName `
    --sku Basic `
    --admin-enabled true

# 3. Get ACR credentials
$acrCredentials = az acr credential show --name $RegistryName --query "{username:username, password:passwords[0].value}" | ConvertFrom-Json
$acrLoginServer = az acr show --name $RegistryName --query loginServer -o tsv

# 4. Build and push Docker image
Write-Host "Building Docker image..." -ForegroundColor Yellow
docker build -t "${ContainerName}:latest" .

Write-Host "Tagging image for ACR..." -ForegroundColor Yellow
docker tag "${ContainerName}:latest" "${acrLoginServer}/${ContainerName}:latest"

Write-Host "Logging into ACR..." -ForegroundColor Yellow
docker login $acrLoginServer -u $acrCredentials.username -p $acrCredentials.password

Write-Host "Pushing image to ACR..." -ForegroundColor Yellow
docker push "${acrLoginServer}/${ContainerName}:latest"

# 5. Handle Key Vault (optional)
if (-not $SkipKeyVault) {
    try {
        Write-Host "Creating/Verifying Azure Key Vault with RBAC..." -ForegroundColor Yellow
        
        # Create Key Vault with RBAC authorization enabled
        $kvCreateResult = az keyvault create --name $KeyVaultName `
            --resource-group $ResourceGroupName `
            --location $Location `
            --enable-rbac-authorization true 2>&1
        
        if ($LASTEXITCODE -ne 0) {
            Write-Host "Note: Key Vault may already exist. Continuing..." -ForegroundColor Yellow
        }

        # 5a. Get current user's object ID for RBAC role assignment
        Write-Host "Getting user information for RBAC assignment..." -ForegroundColor Yellow
        $currentUserObjectId = az ad signed-in-user show --query id -o tsv 2>$null
        
        if (-not $currentUserObjectId) {
            Write-Host "Error: Could not get current user ID for RBAC assignment." -ForegroundColor Red
            Write-Host "Attempting to continue without Key Vault..." -ForegroundColor Yellow
            $SkipKeyVault = $true
        } else {
            # Get the Key Vault resource ID
            $keyVaultId = az keyvault show --name $KeyVaultName --resource-group $ResourceGroupName --query id -o tsv
            
            if ($keyVaultId) {
                # Assign "Key Vault Secrets Officer" role to current user
                Write-Host "Assigning 'Key Vault Secrets Officer' role to current user..." -ForegroundColor Yellow
                
                # The role definition ID for "Key Vault Secrets Officer" is b86a8fe4-44ce-4948-aee5-eccb2c155cd7
                $roleAssignmentResult = az role assignment create `
                    --role "Key Vault Secrets Officer" `
                    --assignee $currentUserObjectId `
                    --scope $keyVaultId 2>&1
                
                if ($LASTEXITCODE -eq 0) {
                    Write-Host "RBAC role 'Key Vault Secrets Officer' assigned successfully." -ForegroundColor Green
                } else {
                    # Check if role assignment already exists
                    if ($roleAssignmentResult -like "*already exists*") {
                        Write-Host "Role assignment already exists. Continuing..." -ForegroundColor Yellow
                    } else {
                        Write-Host "Warning: Could not assign RBAC role. Error: $roleAssignmentResult" -ForegroundColor Yellow
                    }
                }
                
                # Also assign "Key Vault Reader" role for listing operations
                Write-Host "Assigning 'Key Vault Reader' role for read operations..." -ForegroundColor Yellow
                $readerRoleResult = az role assignment create `
                    --role "Key Vault Reader" `
                    --assignee $currentUserObjectId `
                    --scope $keyVaultId 2>&1
                
                if ($LASTEXITCODE -eq 0) {
                    Write-Host "RBAC role 'Key Vault Reader' assigned successfully." -ForegroundColor Green
                } else {
                    if ($readerRoleResult -like "*already exists*") {
                        Write-Host "Reader role assignment already exists. Continuing..." -ForegroundColor Yellow
                    }
                }
            } else {
                Write-Host "Error: Could not get Key Vault resource ID." -ForegroundColor Red
                $SkipKeyVault = $true
            }
        }

        # Wait for RBAC propagation
        Write-Host "Waiting for RBAC role propagation (this may take up to 30 seconds)..." -ForegroundColor Yellow
        Start-Sleep -Seconds 30

        # 6. Store database credentials in Key Vault
        Write-Host "Storing secrets in Key Vault..." -ForegroundColor Yellow
        Write-Host "Please enter database password:" -ForegroundColor Cyan
        $dbPassword = Read-Host -AsSecureString
        $dbPasswordPlain = [Runtime.InteropServices.Marshal]::PtrToStringAuto([Runtime.InteropServices.Marshal]::SecureStringToBSTR($dbPassword))

        $secretResult = az keyvault secret set --vault-name $KeyVaultName `
            --name "db-password" `
            --value $dbPasswordPlain 2>&1
        
        if ($LASTEXITCODE -ne 0) {
            Write-Host "Warning: Could not store secret in Key Vault. Continuing without Key Vault." -ForegroundColor Yellow
            Write-Host "Error details: $secretResult" -ForegroundColor Red
        } else {
            Write-Host "Secret stored successfully in Key Vault." -ForegroundColor Green
        }
    }
    catch {
        Write-Host "Warning: Key Vault operations failed. Continuing without Key Vault." -ForegroundColor Yellow
        Write-Host "Error: $_" -ForegroundColor Red
    }
} else {
    Write-Host "Skipping Key Vault creation (using -SkipKeyVault flag)" -ForegroundColor Yellow
    Write-Host "Please enter database password:" -ForegroundColor Cyan
    $dbPassword = Read-Host -AsSecureString
    $dbPasswordPlain = [Runtime.InteropServices.Marshal]::PtrToStringAuto([Runtime.InteropServices.Marshal]::SecureStringToBSTR($dbPassword))
}

# 7. Create Azure Container Instance
Write-Host "Creating Azure Container Instance..." -ForegroundColor Yellow

# Read environment variables from .env file if it exists
if (Test-Path ".env") {
    Get-Content ".env" | ForEach-Object {
        if ($_ -match "^([^=]+)=(.*)$") {
            $key = $matches[1]
            $value = $matches[2]
            if ($key -ne "DB_PASSWORD") {
                Set-Variable -Name $key -Value $value
            }
        }
    }
}

# Deploy container instance
az container create `
    --resource-group $ResourceGroupName `
    --name $ContainerName `
    --image "${acrLoginServer}/${ContainerName}:latest" `
    --registry-login-server $acrLoginServer `
    --registry-username $acrCredentials.username `
    --registry-password $acrCredentials.password `
    --cpu 1 `
    --memory 1 `
    --os-type Linux `
    --restart-policy OnFailure `
    --environment-variables `
        DB_USER=$DB_USER `
        DB_SERVER=$DB_SERVER `
        DB_NAME=$DB_NAME `
        DB_ENCRYPT=$DB_ENCRYPT `
        DB_TRUST_CERT=$DB_TRUST_CERT `
    --secure-environment-variables `
        DB_PASSWORD=$dbPasswordPlain

Write-Host "Deployment complete!" -ForegroundColor Green
Write-Host "Container Instance Name: $ContainerName" -ForegroundColor Cyan
Write-Host "Resource Group: $ResourceGroupName" -ForegroundColor Cyan

# 8. Get container logs (optional)
Write-Host "`nWould you like to view container logs? (y/n)" -ForegroundColor Yellow
$viewLogs = Read-Host
if ($viewLogs -eq 'y') {
    az container logs --resource-group $ResourceGroupName --name $ContainerName
}

# 9. Get container details
Write-Host "`nContainer Details:" -ForegroundColor Yellow
az container show --resource-group $ResourceGroupName --name $ContainerName --query "{Status:instanceView.state, IP:ipAddress.ip}" -o table
