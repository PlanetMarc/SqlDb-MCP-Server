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
        Write-Host "Creating/Verifying Azure Key Vault..." -ForegroundColor Yellow
        az keyvault create --name $KeyVaultName `
            --resource-group $ResourceGroupName `
            --location $Location `
            --enable-rbac-authorization false 2>$null

        # 5a. Get current user's object ID and set Key Vault access policy
        Write-Host "Setting Key Vault access policies..." -ForegroundColor Yellow
        $currentUserObjectId = az ad signed-in-user show --query id -o tsv 2>$null

        if ($currentUserObjectId) {
            az keyvault set-policy --name $KeyVaultName `
                --object-id $currentUserObjectId `
                --secret-permissions get list set delete backup restore recover purge 2>$null
        } else {
            Write-Host "Warning: Could not get current user ID. Trying with UPN..." -ForegroundColor Yellow
            $currentUserUpn = az ad signed-in-user show --query userPrincipalName -o tsv 2>$null
            if ($currentUserUpn) {
                az keyvault set-policy --name $KeyVaultName `
                    --upn $currentUserUpn `
                    --secret-permissions get list set delete backup restore recover purge 2>$null
            }
        }

        # Wait for policy propagation
        Write-Host "Waiting for access policy propagation..." -ForegroundColor Yellow
        Start-Sleep -Seconds 10

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
