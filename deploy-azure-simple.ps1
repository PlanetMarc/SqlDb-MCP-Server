# Simple Azure Deployment Script for MCP SQL Server (No Key Vault)
# Prerequisites: Azure CLI installed and logged in

param(
    [Parameter(Mandatory=$true)]
    [string]$ResourceGroupName,
    
    [Parameter(Mandatory=$true)]
    [string]$Location,
    
    [Parameter(Mandatory=$true)]
    [string]$ContainerName,
    
    [Parameter(Mandatory=$false)]
    [string]$RegistryName = "cofmcpregistry"
)

Write-Host "Starting simplified Azure deployment for MCP SQL Server..." -ForegroundColor Green
Write-Host "This script will deploy without Azure Key Vault for simplicity." -ForegroundColor Cyan

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
Write-Host "`nCreating/Verifying Resource Group..." -ForegroundColor Yellow
az group create --name $ResourceGroupName --location $Location

# 2. Create Azure Container Registry if it doesn't exist
Write-Host "`nCreating/Verifying Azure Container Registry..." -ForegroundColor Yellow
az acr create --resource-group $ResourceGroupName `
    --name $RegistryName `
    --sku Basic `
    --admin-enabled true

# 3. Get ACR credentials
Write-Host "`nGetting ACR credentials..." -ForegroundColor Yellow
$acrCredentials = az acr credential show --name $RegistryName --query "{username:username, password:passwords[0].value}" | ConvertFrom-Json
$acrLoginServer = az acr show --name $RegistryName --query loginServer -o tsv

if (-not $acrLoginServer) {
    Write-Host "Error: Could not get ACR login server. Please check if the registry was created successfully." -ForegroundColor Red
    exit 1
}

# 4. Build and push Docker image
Write-Host "`nBuilding Docker image..." -ForegroundColor Yellow
docker build -t "${ContainerName}:latest" .

if ($LASTEXITCODE -ne 0) {
    Write-Host "Error: Docker build failed. Please check your Dockerfile and ensure Docker is running." -ForegroundColor Red
    exit 1
}

Write-Host "Tagging image for ACR..." -ForegroundColor Yellow
docker tag "${ContainerName}:latest" "${acrLoginServer}/${ContainerName}:latest"

Write-Host "Logging into ACR..." -ForegroundColor Yellow
docker login $acrLoginServer -u $acrCredentials.username -p $acrCredentials.password

Write-Host "Pushing image to ACR..." -ForegroundColor Yellow
docker push "${acrLoginServer}/${ContainerName}:latest"

if ($LASTEXITCODE -ne 0) {
    Write-Host "Error: Failed to push image to ACR. Please check your network connection and ACR credentials." -ForegroundColor Red
    exit 1
}

# 5. Read environment variables from .env file
Write-Host "`nReading configuration from .env file..." -ForegroundColor Yellow

if (-not (Test-Path ".env")) {
    Write-Host "Error: .env file not found. Please create it from .env.example and configure your database settings." -ForegroundColor Red
    exit 1
}

$envVars = @{}
Get-Content ".env" | ForEach-Object {
    if ($_ -match "^([^#][^=]+)=(.*)$") {
        $key = $matches[1].Trim()
        $value = $matches[2].Trim()
        $envVars[$key] = $value
    }
}

# Validate required environment variables
$requiredVars = @("DB_USER", "DB_PASSWORD", "DB_SERVER", "DB_NAME")
foreach ($var in $requiredVars) {
    if (-not $envVars.ContainsKey($var) -or [string]::IsNullOrEmpty($envVars[$var])) {
        Write-Host "Error: Required environment variable $var is not set in .env file." -ForegroundColor Red
        exit 1
    }
}

# Set defaults for optional variables
if (-not $envVars.ContainsKey("DB_ENCRYPT")) { $envVars["DB_ENCRYPT"] = "true" }
if (-not $envVars.ContainsKey("DB_TRUST_CERT")) { $envVars["DB_TRUST_CERT"] = "false" }

Write-Host "Configuration loaded successfully." -ForegroundColor Green

# 6. Deploy container instance
Write-Host "`nCreating Azure Container Instance..." -ForegroundColor Yellow
Write-Host "  Container Name: $ContainerName" -ForegroundColor Cyan
Write-Host "  Database Server: $($envVars['DB_SERVER'])" -ForegroundColor Cyan
Write-Host "  Database Name: $($envVars['DB_NAME'])" -ForegroundColor Cyan

az container create `
    --resource-group $ResourceGroupName `
    --name $ContainerName `
    --image "${acrLoginServer}/${ContainerName}:latest" `
    --registry-login-server $acrLoginServer `
    --registry-username $acrCredentials.username `
    --registry-password $acrCredentials.password `
    --cpu 1 `
    --memory 1 `
    --restart-policy OnFailure `
    --environment-variables `
        DB_USER=$($envVars['DB_USER']) `
        DB_SERVER=$($envVars['DB_SERVER']) `
        DB_NAME=$($envVars['DB_NAME']) `
        DB_ENCRYPT=$($envVars['DB_ENCRYPT']) `
        DB_TRUST_CERT=$($envVars['DB_TRUST_CERT']) `
    --secure-environment-variables `
        DB_PASSWORD=$($envVars['DB_PASSWORD'])

if ($LASTEXITCODE -ne 0) {
    Write-Host "Error: Failed to create container instance. Please check the error message above." -ForegroundColor Red
    exit 1
}

Write-Host "`nDeployment complete!" -ForegroundColor Green
Write-Host "Container Instance Name: $ContainerName" -ForegroundColor Cyan
Write-Host "Resource Group: $ResourceGroupName" -ForegroundColor Cyan

# 7. Wait for container to start
Write-Host "`nWaiting for container to start..." -ForegroundColor Yellow
Start-Sleep -Seconds 10

# 8. Get container status
Write-Host "`nContainer Status:" -ForegroundColor Yellow
$containerStatus = az container show --resource-group $ResourceGroupName --name $ContainerName --query "{Status:instanceView.state, ProvisioningState:provisioningState}" -o json | ConvertFrom-Json
Write-Host "  Status: $($containerStatus.Status)" -ForegroundColor Cyan
Write-Host "  Provisioning State: $($containerStatus.ProvisioningState)" -ForegroundColor Cyan

# 9. Get container logs
Write-Host "`nContainer Logs (last 20 lines):" -ForegroundColor Yellow
az container logs --resource-group $ResourceGroupName --name $ContainerName --tail 20

# 10. Instructions for next steps
Write-Host "`n========================================" -ForegroundColor Green
Write-Host "Deployment Summary" -ForegroundColor Green
Write-Host "========================================" -ForegroundColor Green
Write-Host "Resource Group: $ResourceGroupName" -ForegroundColor Cyan
Write-Host "Container Name: $ContainerName" -ForegroundColor Cyan
Write-Host "Container Registry: $acrLoginServer" -ForegroundColor Cyan
Write-Host ""
Write-Host "Useful Commands:" -ForegroundColor Yellow
Write-Host "  View logs:    az container logs --resource-group $ResourceGroupName --name $ContainerName" -ForegroundColor White
Write-Host "  Get status:   az container show --resource-group $ResourceGroupName --name $ContainerName --query instanceView.state" -ForegroundColor White
Write-Host "  Restart:      az container restart --resource-group $ResourceGroupName --name $ContainerName" -ForegroundColor White
Write-Host "  Delete:       az container delete --resource-group $ResourceGroupName --name $ContainerName --yes" -ForegroundColor White
Write-Host ""
Write-Host "For production deployments, consider using Azure Key Vault for secure credential storage." -ForegroundColor Yellow
