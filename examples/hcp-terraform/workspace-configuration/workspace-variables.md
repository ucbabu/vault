# HCP Terraform Workspace Configuration for Vault Integration

This document provides detailed instructions for configuring your HCP Terraform workspace to use Vault dynamic Azure credentials.

## Prerequisites

Before configuring your workspace, ensure you have:

1. **Vault Setup Complete**:
   - Vault cluster with Azure secrets engine enabled
   - JWT authentication configured for HCP Terraform
   - Azure role created for dynamic credentials
   - Run: `./scripts/hcp-terraform-vault-setup.sh --organization "your-org"`

2. **HCP Terraform Access**:
   - HCP Terraform organization with workspace creation permissions
   - API token with appropriate permissions

3. **Azure Configuration**:
   - Azure subscription ID and tenant ID
   - Service principal configured in Vault for Azure integration

## Workspace Variables Configuration

### Required Environment Variables

Set these environment variables in your HCP Terraform workspace:

| Variable Name | Value | Description | Example |
|---------------|-------|-------------|---------|
| `VAULT_ADDR` | `https://your-vault-cluster.vault.hashicorp.cloud:8200` | Vault server address | Required for Vault authentication |
| `VAULT_NAMESPACE` | `admin` | Vault namespace | Usually "admin" for HCP Vault |
| `ARM_SUBSCRIPTION_ID` | `12345678-1234-1234-1234-123456789012` | Azure subscription ID | Required for Azure provider |
| `ARM_TENANT_ID` | `87654321-4321-4321-4321-210987654321` | Azure tenant ID | Required for Azure provider |

### Optional Environment Variables

| Variable Name | Value | Description | Example |
|---------------|-------|-------------|---------|
| `VAULT_AZURE_ROLE` | `hcp-terraform` | Vault Azure role name | Defaults to "hcp-terraform" |
| `TF_LOG` | `DEBUG` | Terraform log level | For troubleshooting |
| `VAULT_LOG_LEVEL` | `INFO` | Vault log level | For troubleshooting |

### Terraform Variables

Configure these Terraform variables in your workspace:

| Variable Name | Type | Default | Description | Example |
|---------------|------|---------|-------------|---------|
| `environment` | `string` | `"dev"` | Environment name | `"dev"`, `"staging"`, `"prod"` |
| `project_name` | `string` | `"vaultdemo"` | Project name for resources | `"myproject"` |
| `azure_region` | `string` | `"East US"` | Azure region | `"West US 2"` |
| `team_name` | `string` | `"platform-engineering"` | Team/owner name | `"devops-team"` |
| `storage_account_tier` | `string` | `"Standard"` | Storage tier | `"Standard"` or `"Premium"` |
| `storage_replication_type` | `string` | `"LRS"` | Storage replication | `"LRS"`, `"GRS"`, `"ZRS"` |
| `create_key_vault` | `bool` | `false` | Create Azure Key Vault | `true` or `false` |

## Step-by-Step Workspace Configuration

### Step 1: Create Workspace

1. Log in to [HCP Terraform](https://app.terraform.io/)
2. Navigate to your organization
3. Click "New Workspace"
4. Choose workspace type:
   - **Version Control**: Connect to your Git repository
   - **CLI-driven**: For local development and testing
   - **API-driven**: For programmatic workspace management

### Step 2: Configure Workspace Settings

1. **General Settings**:
   ```
   Workspace Name: azure-infrastructure-dev
   Description: Azure infrastructure with Vault dynamic credentials
   Execution Mode: Remote
   Terraform Version: ~> 1.6.0
   ```

2. **VCS Settings** (if using version control):
   ```
   Repository: your-org/terraform-azure-infrastructure
   Branch: main
   Working Directory: (leave empty or specify subdirectory)
   ```

### Step 3: Set Environment Variables

Navigate to `Variables` tab and add environment variables:

```bash
# Vault Configuration
VAULT_ADDR = "https://vault-cluster-public-vault-abc123.hashicorp.cloud:8200"
VAULT_NAMESPACE = "admin"

# Azure Configuration  
ARM_SUBSCRIPTION_ID = "12345678-1234-1234-1234-123456789012"
ARM_TENANT_ID = "87654321-4321-4321-4321-210987654321"

# Optional: Vault Azure Role
VAULT_AZURE_ROLE = "hcp-terraform"
```

**Important**: Mark all variables as **Environment Variables** and mark sensitive ones as **Sensitive**.

### Step 4: Set Terraform Variables

Add Terraform variables in the same `Variables` tab:

```hcl
# Project Configuration
environment = "dev"
project_name = "myproject"
team_name = "platform-engineering"

# Azure Configuration
azure_region = "East US"

# Storage Configuration
storage_account_tier = "Standard"
storage_replication_type = "LRS"

# Optional Components
create_key_vault = false
enable_monitoring = false
```

### Step 5: Configure Notifications (Optional)

1. Go to `Settings` > `Notifications`
2. Add webhook or email notifications for:
   - Run needs attention
   - Run completed
   - Run errored
   - Run applying

### Step 6: Set Run Triggers (Optional)

1. Go to `Settings` > `Run Triggers`
2. Configure automatic runs on:
   - VCS changes
   - Schedule (for drift detection)
   - Triggered by other workspaces

## Workspace Types and Use Cases

### Development Workspace

```hcl
# Terraform Variables
environment = "dev"
project_name = "myproject"
azure_region = "East US"
storage_account_tier = "Standard"
storage_replication_type = "LRS"
create_key_vault = false
enable_monitoring = false
```

**Use Case**: Development and testing of infrastructure changes.

### Staging Workspace

```hcl
# Terraform Variables
environment = "staging"
project_name = "myproject"
azure_region = "East US 2"
storage_account_tier = "Standard" 
storage_replication_type = "GRS"
create_key_vault = true
enable_monitoring = true
```

**Use Case**: Pre-production testing and validation.

### Production Workspace

```hcl
# Terraform Variables
environment = "prod"
project_name = "myproject"
azure_region = "West US 2"
storage_account_tier = "Premium"
storage_replication_type = "GZRS"
create_key_vault = true
enable_monitoring = true
enable_advanced_threat_protection = true
```

**Use Case**: Production infrastructure deployment.

## Security Best Practices

### Environment Variable Security

1. **Mark Sensitive Variables**: Always mark sensitive variables appropriately
2. **Use Least Privilege**: Configure Vault roles with minimal required permissions
3. **Regular Rotation**: Rotate Vault service principal credentials regularly
4. **Audit Access**: Monitor workspace access and variable changes

### Workspace Access Control

1. **Team Permissions**:
   ```
   Admin: Full workspace management
   Write: Plan and apply permissions
   Read: View-only access
   ```

2. **API Token Scope**: Use workspace-specific tokens when possible

### Network Security

1. **Private Endpoints**: Use private endpoints for Vault access where possible
2. **IP Restrictions**: Configure IP allowlists for workspace access
3. **VPC/VNet Integration**: Use network peering for secure connectivity

## Troubleshooting

### Common Issues

1. **Vault Authentication Failed**:
   ```
   Error: failed to login to Vault: unable to complete JWT authentication
   ```
   
   **Solutions**:
   - Verify `VAULT_ADDR` and `VAULT_NAMESPACE` are correct
   - Check JWT role configuration in Vault
   - Ensure workspace name matches bound claims

2. **Azure Provider Authentication Failed**:
   ```
   Error: building AzureRM Client: obtain subscription() from Azure CLI
   ```
   
   **Solutions**:
   - Verify `ARM_SUBSCRIPTION_ID` and `ARM_TENANT_ID` are correct
   - Check Azure secrets engine configuration
   - Test credential generation manually in Vault

3. **Permission Denied Errors**:
   ```
   Error: authorization failed: this request requires "Microsoft.Resources/resourceGroups/write"
   ```
   
   **Solutions**:
   - Review Azure role permissions in Vault
   - Check subscription-level access
   - Verify resource group creation permissions

### Debugging Steps

1. **Enable Debug Logging**:
   ```bash
   TF_LOG = "DEBUG"
   VAULT_LOG_LEVEL = "DEBUG"
   ```

2. **Test Vault Connection**:
   - Use Vault CLI to test authentication
   - Verify Azure credential generation manually

3. **Check Workspace Runs**:
   - Review run logs in HCP Terraform UI
   - Check plan output for credential retrieval

### Getting Help

1. **HCP Terraform Support**:
   - [Support Portal](https://support.hashicorp.com/)
   - [Documentation](https://developer.hashicorp.com/terraform/cloud-docs)

2. **Vault Support**:
   - [Vault Documentation](https://www.vaultproject.io/docs)
   - [Community Forum](https://discuss.hashicorp.com/c/vault)

3. **Azure Support**:
   - [Azure Documentation](https://docs.microsoft.com/en-us/azure/)
   - [Azure Support Center](https://azure.microsoft.com/en-us/support/)

## Monitoring and Maintenance

### Regular Tasks

1. **Weekly**:
   - Review workspace run history
   - Check for failed authentications
   - Monitor credential generation patterns

2. **Monthly**:
   - Review and update Terraform variables
   - Check for Terraform provider updates
   - Validate Azure role permissions

3. **Quarterly**:
   - Rotate Vault service principal credentials
   - Review workspace access permissions
   - Update Terraform version

### Monitoring Dashboards

Create monitoring dashboards for:
- Workspace run success rates
- Vault authentication metrics
- Azure resource costs
- Security alerts and violations

## Cost Optimization

### Cost Management Tips

1. **Resource Tagging**: Ensure all resources are properly tagged for cost allocation
2. **Environment Sizing**: Use appropriate resource sizes for each environment
3. **Cleanup Automation**: Implement automatic cleanup for development resources
4. **Cost Alerts**: Set up Azure cost alerts and budgets

### Example Cost Tags

```hcl
tags = {
  Environment = var.environment
  Project = var.project_name
  Owner = var.team_name
  CostCenter = "Engineering"
  ManagedBy = "HCP-Terraform"
  CreatedAt = timestamp()
}
```

This configuration ensures proper cost tracking and resource management across all environments.