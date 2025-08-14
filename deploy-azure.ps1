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
    [string]$KeyVaultName = "cof-mcp-keyvault"
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

# 5. Create Azure Key Vault for secrets
Write-Host "Creating/Verifying Azure Key Vault..." -ForegroundColor Yellow
az keyvault create --name $KeyVaultName `
    --resource-group $ResourceGroupName `
    --location $Location

# 6. Store database credentials in Key Vault
Write-Host "Storing secrets in Key Vault..." -ForegroundColor Yellow
Write-Host "Please enter database password:" -ForegroundColor Cyan
$dbPassword = Read-Host -AsSecureString
$dbPasswordPlain = [Runtime.InteropServices.Marshal]::PtrToStringAuto([Runtime.InteropServices.Marshal]::SecureStringToBSTR($dbPassword))

az keyvault secret set --vault-name $KeyVaultName `
    --name "db-password" `
    --value $dbPasswordPlain

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
