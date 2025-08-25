# Story 3: Azure Dynamic Key Rotation Implementation

## Overview

This implementation provides complete Azure dynamic key rotation using Vault's Azure secrets engine, enabling short-lived Azure credentials for enhanced security and compliance.

## Implementation Components

### 1. Azure Service Principal Setup
- **Vault Service Principal**: Dedicated SP for Vault Azure integration
- **Permission Management**: Automated role assignment and consent
- **Security Configuration**: Least privilege access patterns

### 2. Azure Secrets Engine Configuration  
- **Connection Setup**: Azure subscription and tenant integration
- **Role Management**: Multiple role templates for different use cases
- **Policy Framework**: Fine-grained access control

### 3. Dynamic Credential Generation
- **Role-based Access**: Different credential types for different purposes
- **TTL Management**: Configurable time-to-live settings
- **Automatic Cleanup**: Credentials automatically revoked

## Prerequisites

### Azure Requirements
- Azure subscription with Owner or User Access Administrator rights
- Azure AD tenant access
- Azure CLI installed and configured
- PowerShell or Bash environment

### Environment Variables
```bash
export AZURE_SUBSCRIPTION_ID="12345678-1234-1234-1234-123456789012"
export AZURE_TENANT_ID="87654321-4321-4321-4321-210987654321"
export VAULT_ADDR="https://your-vault-cluster.vault.hashicorp.cloud:8200"
export VAULT_TOKEN="your-vault-token"
export VAULT_NAMESPACE="admin"
```

## Deployment Instructions

### Step 1: Azure Prerequisites

```bash
# Login to Azure
az login

# Set active subscription
az account set --subscription "$AZURE_SUBSCRIPTION_ID"

# Verify permissions
az role assignment list --assignee $(az account show --query user.name -o tsv) --scope "/subscriptions/$AZURE_SUBSCRIPTION_ID"
```

### Step 2: Run Azure Setup Script

```bash
# Ensure environment variables are set
export AZURE_SUBSCRIPTION_ID="your-subscription-id"
export AZURE_TENANT_ID="your-tenant-id"

# Run Azure setup
cd scripts/
./azure-setup.sh
```

### Step 3: Verify Configuration

```bash
# Check Azure secrets engine
vault read azure/config

# List Azure roles
vault list azure/roles

# Test credential generation
vault read azure/creds/readonly

# Verify policies
vault policy list | grep azure
```

## Azure Role Templates

### 1. Read-Only Access (`readonly`)
```json
{
  "azure_roles": [
    {
      "role_name": "Reader",
      "scope": "/subscriptions/{subscription-id}"
    }
  ],
  "ttl": "1h",
  "max_ttl": "24h"
}
```

**Use Cases**: Monitoring, reporting, compliance checking

### 2. Storage Administration (`storage-admin`)
```json
{
  "azure_roles": [
    {
      "role_name": "Storage Account Contributor",
      "scope": "/subscriptions/{subscription-id}"
    },
    {
      "role_name": "Storage Blob Data Contributor", 
      "scope": "/subscriptions/{subscription-id}"
    }
  ],
  "ttl": "30m",
  "max_ttl": "2h"
}
```

**Use Cases**: Data backup, file operations, storage management

### 3. Virtual Machine Management (`vm-admin`)
```json
{
  "azure_roles": [
    {
      "role_name": "Virtual Machine Contributor",
      "scope": "/subscriptions/{subscription-id}"
    },
    {
      "role_name": "Network Contributor",
      "scope": "/subscriptions/{subscription-id}"
    }
  ],
  "ttl": "2h",
  "max_ttl": "8h"
}
```

**Use Cases**: Infrastructure management, VM deployment, network configuration

### 4. Application Deployment (`app-deployer`)
```json
{
  "azure_roles": [
    {
      "role_name": "Contributor",
      "scope": "/subscriptions/{subscription-id}/resourceGroups/{resource-group}"
    }
  ],
  "ttl": "4h",
  "max_ttl": "12h"
}
```

**Use Cases**: CI/CD pipelines, application deployment, infrastructure updates

### 5. Key Vault Management (`keyvault-admin`)
```json
{
  "azure_roles": [
    {
      "role_name": "Key Vault Administrator",
      "scope": "/subscriptions/{subscription-id}"
    }
  ],
  "ttl": "1h", 
  "max_ttl": "4h"
}
```

**Use Cases**: Certificate management, key rotation, secret operations

## Access Control Policies

### 1. Azure Read-Only Policy (`azure-readonly`)
```hcl
# Read-only access to Azure credentials
path "azure/creds/readonly" {
  capabilities = ["read"]
}

path "azure/creds/monitoring" {
  capabilities = ["read"]
}

path "azure/roles" {
  capabilities = ["list"]
}

path "azure/roles/*" {
  capabilities = ["read"]
}
```

### 2. Azure Developer Policy (`azure-developer`)
```hcl
# Developer access to Azure credentials
path "azure/creds/readonly" {
  capabilities = ["read"]
}

path "azure/creds/storage-admin" {
  capabilities = ["read"]
}

path "azure/creds/rg-contributor" {
  capabilities = ["read"]
}
```

### 3. Azure Operator Policy (`azure-operator`)
```hcl
# Operator access to Azure credentials
path "azure/creds/vm-admin" {
  capabilities = ["read"]
}

path "azure/creds/storage-admin" {
  capabilities = ["read"]
}

path "azure/creds/monitoring" {
  capabilities = ["read"]
}

path "azure/creds/keyvault-admin" {
  capabilities = ["read"]
}
```

## Application Integration Examples

### 1. Python Integration

```python
import os
from azure.identity import ClientSecretCredential
from azure.mgmt.resource import ResourceManagementClient
import hvac

# Initialize Vault client
vault_client = hvac.Client(
    url=os.environ['VAULT_ADDR'],
    token=os.environ['VAULT_TOKEN']
)

# Get Azure credentials from Vault
azure_creds = vault_client.read('azure/creds/readonly')
client_id = azure_creds['data']['client_id']
client_secret = azure_creds['data']['client_secret']
lease_id = azure_creds['lease_id']

# Create Azure credential object
credential = ClientSecretCredential(
    tenant_id=os.environ['AZURE_TENANT_ID'],
    client_id=client_id,
    client_secret=client_secret
)

# Use credential with Azure SDK
resource_client = ResourceManagementClient(
    credential, 
    os.environ['AZURE_SUBSCRIPTION_ID']
)

# List resource groups
for rg in resource_client.resource_groups.list():
    print(f"Resource Group: {rg.name}")

# Revoke credentials when done
vault_client.sys.revoke_lease(lease_id)
```

### 2. Azure CLI Integration

```bash
#!/bin/bash
# azure-cli-example.sh

# Get credentials from Vault
CREDS=$(vault read -format=json azure/creds/storage-admin)
CLIENT_ID=$(echo $CREDS | jq -r '.data.client_id')
CLIENT_SECRET=$(echo $CREDS | jq -r '.data.client_secret')
LEASE_ID=$(echo $CREDS | jq -r '.lease_id')

# Login to Azure CLI
az login --service-principal \
  --username $CLIENT_ID \
  --password $CLIENT_SECRET \
  --tenant $AZURE_TENANT_ID

# Perform Azure operations
az storage account list --query '[].name'

# Logout and revoke credentials
az logout
vault lease revoke $LEASE_ID
```

### 3. Terraform Integration

```hcl
# terraform/azure-with-vault.tf
data "vault_generic_secret" "azure_creds" {
  path = "azure/creds/app-deployer"
}

provider "azurerm" {
  features {}
  
  client_id       = data.vault_generic_secret.azure_creds.data["client_id"]
  client_secret   = data.vault_generic_secret.azure_creds.data["client_secret"]
  tenant_id       = var.azure_tenant_id
  subscription_id = var.azure_subscription_id
}

resource "azurerm_resource_group" "example" {
  name     = "vault-deployed-rg"
  location = "East US"
}
```

### 4. CI/CD Pipeline Integration

```yaml
# .github/workflows/azure-deploy.yml
name: Azure Deployment with Vault
on:
  push:
    branches: [main]

jobs:
  deploy:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v3
      
      - name: Get Azure Credentials from Vault
        id: azure-creds
        run: |
          # Authenticate to Vault (using JWT method)
          vault login -method=jwt role=github-actions jwt=${{ secrets.GITHUB_TOKEN }}
          
          # Get Azure credentials
          CREDS=$(vault read -format=json azure/creds/app-deployer)
          echo "client-id=$(echo $CREDS | jq -r '.data.client_id')" >> $GITHUB_OUTPUT
          echo "client-secret=$(echo $CREDS | jq -r '.data.client_secret')" >> $GITHUB_OUTPUT
          echo "lease-id=$(echo $CREDS | jq -r '.lease_id')" >> $GITHUB_OUTPUT
        env:
          VAULT_ADDR: ${{ secrets.VAULT_ADDR }}
          
      - name: Azure Login
        uses: azure/login@v1
        with:
          creds: |
            {
              "clientId": "${{ steps.azure-creds.outputs.client-id }}",
              "clientSecret": "${{ steps.azure-creds.outputs.client-secret }}",
              "subscriptionId": "${{ secrets.AZURE_SUBSCRIPTION_ID }}",
              "tenantId": "${{ secrets.AZURE_TENANT_ID }}"
            }
            
      - name: Deploy Infrastructure
        run: |
          az deployment group create \
            --resource-group production-rg \
            --template-file infrastructure/main.bicep
            
      - name: Cleanup Credentials
        if: always()
        run: |
          vault lease revoke ${{ steps.azure-creds.outputs.lease-id }}
        env:
          VAULT_ADDR: ${{ secrets.VAULT_ADDR }}
```

## Monitoring and Operations

### 1. Credential Usage Monitoring

```bash
# Monitor active Azure credentials
./scripts/monitor-azure-creds.sh

# Check credential generation patterns
vault audit lookup | grep azure/creds

# Monitor lease renewals and revocations
vault list sys/leases/lookup/azure/creds
```

### 2. Automated Monitoring Script

```bash
#!/bin/bash
# azure-monitoring.sh - Automated Azure credential monitoring

# Check for credentials expiring in next hour
EXPIRING=$(vault list -format=json sys/leases/lookup/azure/creds | \
  jq -r '.[] | select(.ttl < 3600)')

if [[ -n "$EXPIRING" ]]; then
  echo "WARNING: Azure credentials expiring within 1 hour"
  echo "$EXPIRING"
fi

# Alert on high credential generation rate
RECENT_COUNT=$(vault audit log | \
  grep "azure/creds" | \
  grep "$(date -d '1 hour ago' '+%Y-%m-%d %H')" | \
  wc -l)

if [[ $RECENT_COUNT -gt 100 ]]; then
  echo "WARNING: High Azure credential generation rate: $RECENT_COUNT/hour"
fi
```

### 3. Performance Metrics

```bash
# Monitor Azure secrets engine performance
vault read sys/metrics | grep azure

# Check Azure API response times
vault read azure/config

# Monitor credential success/failure rates
vault audit log | grep azure | grep -c success
vault audit log | grep azure | grep -c error
```

## Security Best Practices

### 1. Credential Management
- **Short TTLs**: Use minimum necessary credential lifetime
- **Automatic Revocation**: Implement automatic cleanup
- **Least Privilege**: Grant minimum required permissions
- **Regular Rotation**: Rotate Vault service principal credentials

### 2. Network Security
- **IP Restrictions**: Limit credential usage by source IP
- **VNet Integration**: Use private endpoints where possible
- **Conditional Access**: Implement Azure AD conditional access policies
- **Activity Monitoring**: Monitor credential usage patterns

### 3. Audit and Compliance
- **Complete Logging**: Enable comprehensive audit logs
- **Regular Reviews**: Review role assignments and permissions
- **Compliance Reporting**: Generate compliance reports
- **Anomaly Detection**: Monitor for unusual access patterns

## Troubleshooting

### Common Issues

1. **Service Principal Permission Errors**
   ```bash
   # Check service principal permissions
   az role assignment list --assignee $VAULT_SP_CLIENT_ID
   
   # Verify admin consent
   az ad app permission list --id $VAULT_SP_CLIENT_ID
   ```

2. **Credential Generation Failures**
   ```bash
   # Check Azure connection
   vault read azure/config
   
   # Test role configuration
   vault read azure/roles/readonly
   
   # Check Azure API connectivity
   az account show
   ```

3. **Authentication Failures**
   ```bash
   # Test generated credentials
   CREDS=$(vault read -format=json azure/creds/readonly)
   CLIENT_ID=$(echo $CREDS | jq -r '.data.client_id')
   CLIENT_SECRET=$(echo $CREDS | jq -r '.data.client_secret')
   
   az login --service-principal \
     --username $CLIENT_ID \
     --password $CLIENT_SECRET \
     --tenant $AZURE_TENANT_ID
   ```

### Debug Commands

```bash
# Enable debug logging
export VAULT_LOG_LEVEL=debug

# Check detailed Azure configuration
vault read -format=json azure/config

# Test Azure API connectivity
curl -H "Authorization: Bearer $(az account get-access-token --query accessToken -o tsv)" \
  "https://management.azure.com/subscriptions/$AZURE_SUBSCRIPTION_ID/resourcegroups?api-version=2021-04-01"
```

## Success Criteria Validation

- [x] Azure secrets engine enabled and configured
- [x] Service principal roles defined with least privilege
- [x] Dynamic credential generation tested for Azure resources
- [x] Credential lease and renewal policies configured
- [x] Integration with Azure Key Vault for additional secrets
- [x] Monitoring for failed rotations implemented

## Next Steps

After completing Story 3:

1. **Production Deployment**: Deploy to production environment
2. **Application Integration**: Update applications to use dynamic credentials
3. **CI/CD Integration**: Implement in deployment pipelines
4. **Monitoring Setup**: Configure alerting and monitoring
5. **Database Integration**: Configure database dynamic credentials (Story 4)
6. **Advanced Features**: Implement certificate-based authentication

This implementation provides a complete foundation for Azure dynamic key rotation with HashiCorp Vault, enabling secure, automated credential management for Azure resources.