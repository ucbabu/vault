# Azure Dynamic Key Rotation with HashiCorp Vault

## Table of Contents

1. [Overview](#overview)
2. [Prerequisites](#prerequisites)
3. [Azure Secrets Engine Setup](#azure-secrets-engine-setup)
4. [Dynamic Credential Management](#dynamic-credential-management)
5. [Application Integration](#application-integration)
6. [Monitoring and Best Practices](#monitoring-and-best-practices)

## Overview

Azure dynamic key rotation with HashiCorp Vault generates short-lived Azure credentials on-demand, eliminating static service principal secrets and reducing security risks.

### Key Benefits
- **Enhanced Security**: Short-lived credentials (minutes to hours)
- **Zero Static Storage**: No credentials stored in applications
- **Automatic Rotation**: Credentials expire and rotate automatically
- **Complete Audit Trail**: Full visibility into credential usage

## Prerequisites

### Azure Requirements
- Azure subscription with admin access
- Service principal for Vault with these permissions:
  ```json
  {
    "permissions": [
      "Microsoft.Authorization/roleAssignments/*",
      "Microsoft.Authorization/roleDefinitions/read",
      "Microsoft.Resources/subscriptions/resourceGroups/read"
    ]
  }
  ```

### Vault Requirements
- Vault cluster with admin access
- Network connectivity to Azure APIs

## Azure Secrets Engine Setup

### 1. Enable and Configure

```bash
# Enable Azure secrets engine
vault secrets enable azure

# Configure Azure connection
vault write azure/config \
    subscription_id="12345678-1234-1234-1234-123456789012" \
    tenant_id="87654321-4321-4321-4321-210987654321" \
    client_id="vault-service-principal-id" \
    client_secret="vault-sp-secret" \
    environment="AzurePublicCloud"

# Verify configuration
vault read azure/config
```

### 2. Create Azure Roles

```bash
# Read-only role for monitoring
vault write azure/roles/readonly \
    azure_roles='[
        {
            "role_name": "Reader",
            "scope": "/subscriptions/12345678-1234-1234-1234-123456789012/resourceGroups/my-rg"
        }
    ]' \
    ttl="1h" \
    max_ttl="24h"

# Storage administrator role
vault write azure/roles/storage-admin \
    azure_roles='[
        {
            "role_name": "Storage Account Contributor",
            "scope": "/subscriptions/12345678-1234-1234-1234-123456789012/resourceGroups/storage-rg"
        }
    ]' \
    ttl="30m" \
    max_ttl="2h"

# Application deployment role
vault write azure/roles/app-deployer \
    azure_roles='[
        {
            "role_name": "Contributor",
            "scope": "/subscriptions/12345678-1234-1234-1234-123456789012/resourceGroups/app-rg"
        }
    ]' \
    ttl="4h" \
    max_ttl="12h"
```

## Dynamic Credential Management

### 1. Generate Credentials

```bash
# Generate credentials for specific role
vault read azure/creds/readonly

# Example output:
# Key                Value
# ---                -----
# lease_id           azure/creds/readonly/abc123
# lease_duration     3600
# lease_renewable    true
# client_id          generated-client-id
# client_secret      generated-client-secret

# Store in variables for scripting
AZURE_CREDS=$(vault read -format=json azure/creds/readonly)
CLIENT_ID=$(echo $AZURE_CREDS | jq -r '.data.client_id')
CLIENT_SECRET=$(echo $AZURE_CREDS | jq -r '.data.client_secret')
LEASE_ID=$(echo $AZURE_CREDS | jq -r '.lease_id')
```

### 2. Lease Management

```bash
# Renew lease
vault lease renew $LEASE_ID

# Renew with specific duration
vault lease renew -increment=3600 $LEASE_ID

# Revoke credentials early
vault lease revoke $LEASE_ID

# List active leases
vault list sys/leases/lookup/azure/creds/readonly
```

## Application Integration

### 1. Python Example

```python
import hvac
from azure.identity import ClientSecretCredential
from azure.mgmt.resource import ResourceManagementClient

class AzureVaultClient:
    def __init__(self, vault_url, vault_token, subscription_id, tenant_id):
        self.vault_client = hvac.Client(url=vault_url, token=vault_token)
        self.subscription_id = subscription_id
        self.tenant_id = tenant_id
        
    def get_azure_credentials(self, role_name):
        """Get fresh Azure credentials from Vault"""
        response = self.vault_client.read(f'azure/creds/{role_name}')
        return {
            'client_id': response['data']['client_id'],
            'client_secret': response['data']['client_secret'],
            'lease_id': response['lease_id']
        }
    
    def get_resource_client(self, role_name):
        """Get authenticated Azure Resource Management client"""
        creds = self.get_azure_credentials(role_name)
        credential = ClientSecretCredential(
            tenant_id=self.tenant_id,
            client_id=creds['client_id'],
            client_secret=creds['client_secret']
        )
        return ResourceManagementClient(credential, self.subscription_id)

# Usage
vault_client = AzureVaultClient(
    vault_url="https://vault.example.com:8200",
    vault_token="vault-token",
    subscription_id="12345678-1234-1234-1234-123456789012",
    tenant_id="87654321-4321-4321-4321-210987654321"
)

# Get authenticated Azure client
azure_client = vault_client.get_resource_client('readonly')

# Use Azure client
for rg in azure_client.resource_groups.list():
    print(f"Resource Group: {rg.name}")
```

### 2. Shell Script Integration

```bash
#!/bin/bash
# azure-deploy.sh

# Function to get Azure credentials
get_azure_creds() {
    local role_name=$1
    vault read -format=json azure/creds/$role_name
}

# Function to authenticate with Azure CLI
azure_login_with_vault() {
    local role_name=$1
    local creds=$(get_azure_creds $role_name)
    
    local client_id=$(echo $creds | jq -r '.data.client_id')
    local client_secret=$(echo $creds | jq -r '.data.client_secret')
    local lease_id=$(echo $creds | jq -r '.lease_id')
    
    # Login to Azure CLI
    az login --service-principal \
        --username $client_id \
        --password $client_secret \
        --tenant $AZURE_TENANT_ID
    
    echo $lease_id  # Return lease ID for cleanup
}

# Main deployment script
LEASE_ID=$(azure_login_with_vault "app-deployer")

# Perform deployment operations
az deployment group create \
    --resource-group my-app-rg \
    --template-file deploy.bicep \
    --parameters @parameters.json

# Cleanup - revoke credentials
vault lease revoke $LEASE_ID
```

### 3. Kubernetes Integration

```yaml
apiVersion: apps/v1
kind: Deployment
metadata:
  name: azure-app
spec:
  template:
    metadata:
      annotations:
        vault.hashicorp.com/agent-inject: "true"
        vault.hashicorp.com/role: "azure-app"
        vault.hashicorp.com/agent-inject-secret-azure: "azure/creds/readonly"
        vault.hashicorp.com/agent-inject-template-azure: |
          {{- with secret "azure/creds/readonly" -}}
          export AZURE_CLIENT_ID="{{ .Data.client_id }}"
          export AZURE_CLIENT_SECRET="{{ .Data.client_secret }}"
          export AZURE_TENANT_ID="87654321-4321-4321-4321-210987654321"
          export AZURE_SUBSCRIPTION_ID="12345678-1234-1234-1234-123456789012"
          {{- end }}
    spec:
      containers:
      - name: app
        image: myapp:latest
        command: ["/bin/sh"]
        args: ["-c", "source /vault/secrets/azure && exec myapp"]
```

## Monitoring and Best Practices

### 1. Monitoring and Alerting

```bash
# Monitor credential generation
vault read sys/metrics | grep azure

# Check active leases
vault list sys/leases/lookup/azure/creds

# Audit credential usage
jq 'select(.request.path | contains("azure/creds"))' /vault/logs/audit.log
```

### 2. Best Practices

#### Security
- **Use shortest practical TTLs** (30 minutes to 4 hours typical)
- **Scope roles to minimum required resources**
- **Implement proper Vault authentication** (OIDC, IAM)
- **Enable comprehensive audit logging**

#### Operations
- **Automate credential renewal** in applications
- **Implement graceful failure handling** for Vault API calls
- **Monitor Azure API rate limits** and quotas
- **Use consistent naming conventions** for roles

#### Application Design
- **Cache credentials within lease duration** only
- **Implement background renewal** for long-running processes
- **Use circuit breakers** for Vault connectivity
- **Handle credential rotation gracefully**

### 3. Troubleshooting

```bash
# Common issues and solutions

# Permission denied
vault read azure/roles/readonly  # Check role configuration
az role assignment list --assignee <vault-sp-id>  # Verify Azure permissions

# Credential generation failures
vault read azure/config  # Verify connection settings
export VAULT_LOG_LEVEL=debug  # Enable debug logging

# Lease management issues
vault lease lookup $LEASE_ID  # Check lease status
vault lease revoke -force $LEASE_ID  # Force revoke if stuck
```

### 4. Common Role Patterns

```bash
# Multi-resource role
vault write azure/roles/full-stack \
    azure_roles='[
        {
            "role_name": "Contributor",
            "scope": "/subscriptions/.../resourceGroups/app-rg"
        },
        {
            "role_name": "Storage Account Key Operator Service Role",
            "scope": "/subscriptions/.../resourceGroups/storage-rg"
        }
    ]' \
    ttl="2h" \
    max_ttl="8h"

# Emergency access role
vault write azure/roles/emergency \
    azure_roles='[
        {
            "role_name": "Contributor",
            "scope": "/subscriptions/12345678-1234-1234-1234-123456789012"
        }
    ]' \
    ttl="15m" \
    max_ttl="1h"

# Monitoring role
vault write azure/roles/monitoring \
    azure_roles='[
        {
            "role_name": "Monitoring Reader",
            "scope": "/subscriptions/12345678-1234-1234-1234-123456789012"
        }
    ]' \
    ttl="24h" \
    max_ttl="72h"
```

---

*This guide provides essential implementation details for Azure dynamic key rotation with HashiCorp Vault. For advanced scenarios and additional integrations, refer to the HashiCorp Vault and Azure documentation.*