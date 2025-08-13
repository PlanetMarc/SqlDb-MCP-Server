# SQL Server MCP Server

A Model Context Protocol (MCP) server implementation that provides secure access to SQL Server databases. This server enables AI assistants and other MCP clients to query and interact with SQL Server databases through a standardized interface.

## Overview

This MCP server acts as a bridge between MCP clients (like Claude Desktop or other AI assistants) and your SQL Server database, providing controlled access to execute queries and retrieve schema information. It implements the MCP protocol over stdio communication, making it suitable for integration with various AI tools and applications.

## Features

### Tools

The server exposes two primary tools for database interaction:

#### 1. `execute_query`
- **Description**: Execute any SQL query on the connected database
- **Input**: SQL query string
- **Output**: Query results in JSON format
- **Use Cases**: 
  - Data retrieval (SELECT statements)
  - Data manipulation (INSERT, UPDATE, DELETE)
  - Stored procedure execution
  - Complex joins and aggregations

#### 2. `get_schema_info`
- **Description**: Retrieve comprehensive database schema information
- **Input**: None required
- **Output**: List of all tables and stored procedures in JSON format
- **Use Cases**:
  - Database exploration
  - Understanding table structures
  - Discovering available stored procedures
  - Schema documentation

## Prerequisites

- Node.js 20 or higher
- npm 7 or higher
- Access to a SQL Server database (Azure SQL, SQL Server, or SQL Server Express)
- Docker Desktop (for containerized deployment)
- Azure CLI (for Azure deployment)

## Configuration

### Environment Variables

The server requires the following environment variables for database connection. Create a `.env` file in the project root:

```bash
# Copy the example file
cp .env.example .env
```

Edit `.env` with your database credentials:

```env
# Database Configuration
DB_USER=your_database_username
DB_PASSWORD=your_database_password
DB_SERVER=your_server.database.windows.net
DB_NAME=your_database_name
DB_ENCRYPT=true                    # Use encryption (recommended for Azure SQL)
DB_TRUST_CERT=false                 # Don't trust self-signed certificates
```

### Security Notes

- **Never commit `.env` files** to version control
- Use Azure Key Vault or similar services for production deployments
- Consider using Managed Identity for Azure deployments
- Implement proper firewall rules for database access

## Development

Install dependencies:
```bash
npm install
```

Build the server:
```bash
npm run build
```

For development with auto-rebuild:
```bash
npm run watch
```

## Build and Testing

### Local Build

1. Install dependencies and build:
```bash
npm install
npm run build
```

2. Test the build:
```bash
node build/index.js
```

### Docker Build

1. Build the Docker image:
```bash
docker build -t sql-server-mcp:latest .
```

2. Test with Docker Compose:
```bash
docker-compose up
```

## Deployment

### Local Installation (Visual Studio Code)

To use with Visual Studio Code and MCP-enabled extensions:

1. **Install Roo Cline Extension** (or another MCP-compatible extension):
   - Open VS Code
   - Go to Extensions (Ctrl+Shift+X)
   - Search for "Roo Cline" or your preferred MCP client extension
   - Click Install

2. **Configure MCP Server in VS Code settings**:

   Open VS Code settings (`settings.json`):
   - Press `Ctrl+Shift+P` (or `Cmd+Shift+P` on Mac)
   - Type "Preferences: Open Settings (JSON)"
   - Add the MCP server configuration:

```json
{
  "roo-cline.mcpServers": {
    "sql-server": {
      "command": "node",
      "args": ["C:/path/to/sql-server-mcp/build/index.js"],
      "env": {
        "DB_USER": "your_username",
        "DB_PASSWORD": "your_password",
        "DB_SERVER": "your_server.database.windows.net",
        "DB_NAME": "your_database",
        "DB_ENCRYPT": "true",
        "DB_TRUST_CERT": "false"
      }
    }
  }
}
```

3. **Alternative: Use workspace-specific configuration**:
   
   Create `.vscode/settings.json` in your workspace root:

```json
{
  "roo-cline.mcpServers": {
    "sql-server": {
      "command": "node",
      "args": ["${workspaceFolder}/sql-server-mcp/build/index.js"],
      "env": {
        "DB_USER": "${env:DB_USER}",
        "DB_PASSWORD": "${env:DB_PASSWORD}",
        "DB_SERVER": "${env:DB_SERVER}",
        "DB_NAME": "${env:DB_NAME}",
        "DB_ENCRYPT": "true",
        "DB_TRUST_CERT": "false"
      }
    }
  }
}
```

**Note**: The exact configuration key (e.g., `roo-cline.mcpServers`) may vary depending on your MCP client extension. Consult your extension's documentation for the correct configuration format.

### Azure Deployment

This project includes comprehensive Azure deployment support with multiple options:

#### Option 1: Quick Deployment Script

Use the included PowerShell script for automated deployment:

```powershell
# Login to Azure
az login

# Run deployment script
.\deploy-azure.ps1 `
  -ResourceGroupName "mcp-sql-rg" `
  -Location "eastus" `
  -ContainerName "mcp-sql-server"
```

#### Option 2: GitHub Actions CI/CD

1. Fork this repository
2. Set up GitHub Secrets:
   - `AZURE_CREDENTIALS` - Service principal JSON
   - `DB_USER` - Database username
   - `DB_PASSWORD` - Database password
   - `DB_SERVER` - Server URL
   - `DB_NAME` - Database name
   - `DB_ENCRYPT` - "true" or "false"
   - `DB_TRUST_CERT` - "true" or "false"

3. Push to main branch to trigger deployment

#### Option 3: Manual Azure Container Instance

```bash
# Create resource group
az group create --name mcp-sql-rg --location eastus

# Create container registry
az acr create --resource-group mcp-sql-rg --name mcpsqlregistry --sku Basic

# Build and push image
az acr build --registry mcpsqlregistry --image mcp-sql-server:latest .

# Deploy container instance
az container create \
  --resource-group mcp-sql-rg \
  --name mcp-sql-server \
  --image mcpsqlregistry.azurecr.io/mcp-sql-server:latest \
  --cpu 1 --memory 1 \
  --environment-variables \
    DB_USER=$DB_USER \
    DB_SERVER=$DB_SERVER \
    DB_NAME=$DB_NAME \
    DB_ENCRYPT=true \
    DB_TRUST_CERT=false \
  --secure-environment-variables \
    DB_PASSWORD=$DB_PASSWORD
```

For detailed deployment instructions, see [DEPLOYMENT.md](DEPLOYMENT.md).

## Debugging

### MCP Inspector

Use the MCP Inspector for interactive debugging:

```bash
npm run inspector
```

This will start the inspector and provide a URL to access debugging tools in your browser.

### Container Logs

For containerized deployments:

```bash
# Docker
docker logs <container-id>

# Azure Container Instance
az container logs --resource-group mcp-sql-rg --name mcp-sql-server
```

## Troubleshooting

### Common Issues

1. **Connection Timeout**
   - Check firewall rules on SQL Server
   - Verify connection string format
   - Ensure database server is accessible from deployment environment

2. **Authentication Failed**
   - Verify credentials in `.env` file
   - Check SQL Server authentication mode
   - Ensure user has necessary permissions

3. **Build Errors**
   - Ensure Node.js 20+ is installed
   - Delete `node_modules` and run `npm install` again
   - Check TypeScript compilation errors with `npm run build`

## Security Best Practices

1. **Credential Management**
   - Use environment variables, never hardcode credentials
   - Implement Azure Key Vault for production
   - Use Managed Identity when possible

2. **Network Security**
   - Configure firewall rules restrictively
   - Use Private Endpoints for Azure SQL
   - Implement VNet integration for containers

3. **Access Control**
   - Use least-privilege database accounts
   - Implement row-level security where needed
   - Audit database access regularly

## License

MIT

## Support

For issues and questions:
- MCP Protocol: [MCP Documentation](https://github.com/modelcontextprotocol)
- Azure Support: [Azure Documentation](https://docs.microsoft.com/azure)
- This Implementation: Create an issue in this repository
