# Azure Deployment Guide for MCP SQL Server

This guide provides step-by-step instructions for deploying your MCP SQL Server to Azure.

## Prerequisites

1. **Azure Account**: Active Azure subscription
2. **Azure CLI**: Install from [here](https://docs.microsoft.com/en-us/cli/azure/install-azure-cli)
3. **Docker Desktop**: Install from [here](https://www.docker.com/products/docker-desktop)
4. **PowerShell 5.1+** (for Windows) or **Bash** (for Linux/Mac)

## Deployment Options

### Option 1: Manual Deployment using PowerShell Script

1. **Create a `.env` file** from the template:
   ```powershell
   Copy-Item .env.example .env
   ```

2. **Edit `.env`** and add your database credentials:
   ```
   DB_USER=UIAdmin
   DB_PASSWORD=your_actual_password
   DB_SERVER=cofdev.database.windows.net
   DB_NAME=Cof
   DB_ENCRYPT=true
   DB_TRUST_CERT=false
   ```

3. **Login to Azure**:
   ```powershell
   az login
   ```

4. **Run the deployment script**:
   ```powershell
   .\deploy-azure.ps1 `
     -ResourceGroupName "cof-mcp-rg" `
     -Location "eastus" `
     -ContainerName "cof-mcp-server"
   ```

### Option 2: GitHub Actions CI/CD

1. **Create GitHub Secrets** in your repository:
   - `AZURE_CREDENTIALS`: Service principal credentials
   - `DB_USER`: Database username
   - `DB_PASSWORD`: Database password
   - `DB_SERVER`: Database server URL
   - `DB_NAME`: Database name
   - `DB_ENCRYPT`: "true" or "false"
   - `DB_TRUST_CERT`: "true" or "false"

2. **Create Azure Service Principal**:
   ```bash
   az ad sp create-for-rbac --name "github-actions-sp" \
     --role contributor \
     --scopes /subscriptions/{subscription-id} \
     --sdk-auth
   ```
   Copy the JSON output to `AZURE_CREDENTIALS` secret.

3. **Push to main branch** to trigger deployment.

### Option 3: Azure Container Apps (Recommended for Production)

1. **Create Container Apps Environment**:
   ```bash
   az containerapp env create \
     --name cof-mcp-env \
     --resource-group cof-mcp-rg \
     --location eastus
   ```

2. **Deploy to Container Apps**:
   ```bash
   az containerapp create \
     --name cof-mcp-app \
     --resource-group cof-mcp-rg \
     --environment cof-mcp-env \
     --image cofmcpregistry.azurecr.io/cof-mcp-server:latest \
     --target-port 3000 \
     --min-replicas 1 \
     --max-replicas 3 \
     --cpu 0.5 \
     --memory 1Gi \
     --secrets db-password=secretvalue \
     --env-vars \
       DB_USER=UIAdmin \
       DB_SERVER=cofdev.database.windows.net \
       DB_NAME=Cof \
       DB_ENCRYPT=true \
       DB_TRUST_CERT=false \
       DB_PASSWORD=secretref:db-password
   ```

## Security Best Practices

1. **Use Azure Key Vault** for storing sensitive credentials:
   ```bash
   # Store secret in Key Vault
   az keyvault secret set \
     --vault-name cof-mcp-keyvault \
     --name db-password \
     --value "your-password"
   
   # Grant access to container
   az keyvault set-policy \
     --name cof-mcp-keyvault \
     --object-id <container-identity-id> \
     --secret-permissions get
   ```

2. **Enable Managed Identity** for the container:
   ```bash
   az container create \
     --assign-identity \
     --role "Key Vault Secrets User" \
     --scope /subscriptions/{sub-id}/resourceGroups/{rg}/providers/Microsoft.KeyVault/vaults/{vault-name}
   ```

3. **Network Security**:
   - Use Azure Private Endpoints for database connections
   - Implement Azure Firewall rules
   - Enable VNet integration for Container Apps

## Monitoring and Logging

1. **Enable Application Insights**:
   ```bash
   az monitor app-insights component create \
     --app cof-mcp-insights \
     --location eastus \
     --resource-group cof-mcp-rg
   ```

2. **View Container Logs**:
   ```bash
   az container logs \
     --resource-group cof-mcp-rg \
     --name cof-mcp-server
   ```

3. **Set up Alerts**:
   ```bash
   az monitor metrics alert create \
     --name high-cpu-alert \
     --resource-group cof-mcp-rg \
     --scopes /subscriptions/{sub-id}/resourceGroups/{rg}/providers/Microsoft.ContainerInstance/containerGroups/{container-name} \
     --condition "avg Percentage CPU > 80" \
     --window-size 5m
   ```

## Scaling Options

### Horizontal Scaling (Container Apps)
```bash
az containerapp update \
  --name cof-mcp-app \
  --resource-group cof-mcp-rg \
  --min-replicas 2 \
  --max-replicas 10 \
  --scale-rule-name cpu-scaling \
  --scale-rule-type cpu \
  --scale-rule-metadata type=Utilization value=70
```

### Vertical Scaling (Container Instances)
```bash
az container create \
  --cpu 2 \
  --memory 4
```

## Cost Optimization

1. **Use Spot Instances** for development:
   ```bash
   az container create \
     --priority Spot \
     --eviction-policy Deallocate
   ```

2. **Auto-shutdown** for non-production:
   ```bash
   az resource update \
     --resource-group cof-mcp-rg \
     --name cof-mcp-server \
     --resource-type Microsoft.ContainerInstance/containerGroups \
     --set properties.restartPolicy=Never
   ```

## Troubleshooting

### Common Issues

1. **Connection Timeout to SQL Server**
   - Check firewall rules on Azure SQL Database
   - Verify container's outbound connectivity
   - Ensure correct connection string format

2. **Container Fails to Start**
   - Check container logs: `az container logs`
   - Verify environment variables are set correctly
   - Ensure Docker image was built successfully

3. **Authentication Failures**
   - Verify Azure credentials are valid
   - Check service principal permissions
   - Ensure Key Vault access policies are configured

### Debug Commands

```bash
# Get container status
az container show \
  --resource-group cof-mcp-rg \
  --name cof-mcp-server \
  --query instanceView.state

# Get detailed events
az container show \
  --resource-group cof-mcp-rg \
  --name cof-mcp-server \
  --query instanceView.events

# Interactive shell (if container supports it)
az container exec \
  --resource-group cof-mcp-rg \
  --name cof-mcp-server \
  --exec-command "/bin/sh"
```

## Clean Up Resources

To remove all deployed resources:

```bash
# Delete resource group (removes all resources within it)
az group delete \
  --name cof-mcp-rg \
  --yes \
  --no-wait
```

## Support

For issues specific to:
- **MCP Protocol**: Check [MCP Documentation](https://github.com/modelcontextprotocol)
- **Azure Services**: Use [Azure Support](https://azure.microsoft.com/support/)
- **This Implementation**: Create an issue in your repository
