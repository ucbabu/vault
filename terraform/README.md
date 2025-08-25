# HashiCorp Vault Cloud on Azure - Terraform Configuration

This Terraform configuration deploys HashiCorp Vault Cloud (HCP Vault) on Azure with optional VNet peering for private network access.

## Architecture Overview

```
┌─────────────────────────────────────────────────────────┐
│                    Azure Cloud                         │
│                                                         │
│  ┌─────────────────────────────────────────────────────┤
│  │              HashiCorp Cloud Platform               │
│  │                                                     │
│  │  ┌─────────────────┐    ┌─────────────────────────┐ │
│  │  │       HVN       │    │    Vault Cluster       │ │
│  │  │  172.25.16.0/20 │◄──►│   vault-production      │ │
│  │  └─────────────────┘    └─────────────────────────┘ │
│  └─────────────────────────────────────────────────────┤
│                                                         │
│  ┌─────────────────────────────────────────────────────┤
│  │              Your Azure Subscription                │
│  │                                                     │
│  │  ┌─────────────────┐    ┌─────────────────────────┐ │
│  │  │   Resource      │    │        VNet             │ │
│  │  │     Group       │    │     10.0.0.0/16        │ │
│  │  │                 │    │                         │ │
│  │  └─────────────────┘    └─────────────────────────┘ │
│  │                                   │                 │
│  │  ┌─────────────────────────────────┼───────────────┐ │
│  │  │       Network Security Group    │               │ │
│  │  │     - Allow 8200/tcp to HVN     │               │ │
│  │  │     - Allow 443/tcp outbound    │               │ │
│  │  └─────────────────────────────────┼───────────────┘ │
│  └─────────────────────────────────────┼─────────────────┘
│                                        │
│                    VNet Peering        │
│                    (Optional)          │
└────────────────────────────────────────┘
```

## Features

- **HashiCorp Virtual Network (HVN)**: Dedicated network for Vault cluster
- **Vault Cluster**: Managed Vault cluster with configurable tiers
- **Azure VNet Peering**: Optional private network connectivity
- **Network Security Groups**: Secure access controls
- **Public Endpoint**: Optional public access with IP allowlisting
- **Monitoring Integration**: Optional Datadog integration
- **Auto-generated Admin Token**: For initial cluster configuration

## Prerequisites

### Required Tools

- [Terraform](https://www.terraform.io/downloads.html) >= 1.0
- [Azure CLI](https://docs.microsoft.com/en-us/cli/azure/install-azure-cli) >= 2.40
- [HashiCorp Cloud Platform (HCP) Account](https://cloud.hashicorp.com/)

### Azure Requirements

- Azure subscription with Contributor access
- Azure CLI authenticated: `az login`
- Service Principal with appropriate permissions (optional, for CI/CD)

### HCP Requirements

- HCP organization created
- Service Principal created in HCP Console
- Required permissions: Vault Admin, Network Admin

## Quick Start

### 1. Clone and Setup

```bash
# Navigate to terraform directory
cd terraform/

# Copy example variables
cp terraform.tfvars.example terraform.tfvars
```

### 2. Configure Variables

Edit `terraform.tfvars` with your specific values:

```hcl
# HCP Authentication
hcp_client_id     = "your-hcp-service-principal-id"
hcp_client_secret = "your-hcp-service-principal-secret"

# Azure Configuration
azure_subscription_id = "12345678-1234-1234-1234-123456789012"
azure_tenant_id       = "87654321-4321-4321-4321-210987654321"
azure_region          = "East US"

# Vault Configuration
vault_cluster_id = "vault-production"
vault_tier       = "standard_small"

# Network Configuration
hvn_id         = "vault-hvn"
hvn_cidr_block = "172.25.16.0/20"

# Optional: Enable VNet peering
enable_vnet_peering      = true
vnet_name                = "your-existing-vnet"
vnet_resource_group_name = "your-vnet-resource-group"
vnet_cidr_block          = "10.0.0.0/16"
```

### 3. Deploy Infrastructure

```bash
# Initialize Terraform
terraform init

# Review the deployment plan
terraform plan

# Deploy the infrastructure
terraform apply
```

### 4. Access Vault

```bash
# Get Vault URL and admin token
export VAULT_ADDR=$(terraform output -raw vault_public_endpoint_url)
export VAULT_TOKEN=$(terraform output -raw vault_admin_token)
export VAULT_NAMESPACE=$(terraform output -raw vault_namespace)

# Verify Vault access
vault status
```

## Configuration Options

### Vault Cluster Tiers

| Tier | Description | Use Case |
|------|-------------|----------|
| `dev` | Development | Testing and development |
| `starter_small` | Production starter | Small production workloads |
| `standard_small` | Standard small | Small to medium production |
| `standard_medium` | Standard medium | Medium production workloads |
| `standard_large` | Standard large | Large production workloads |
| `plus_small` | Plus small | Enhanced features, small scale |
| `plus_medium` | Plus medium | Enhanced features, medium scale |
| `plus_large` | Plus large | Enhanced features, large scale |

### Network Configuration

#### Public Endpoint with IP Allowlisting

```hcl
public_endpoint_enabled = true
ip_allowlist = [
  {
    cidr        = "203.0.113.0/24"
    description = "Office network"
  },
  {
    cidr        = "198.51.100.0/24"
    description = "Production environment"
  }
]
```

#### Private Network with VNet Peering

```hcl
enable_vnet_peering      = true
vnet_name                = "production-vnet"
vnet_resource_group_name = "networking-rg"
vnet_cidr_block          = "10.0.0.0/16"
```

### Monitoring Integration

```hcl
datadog_api_key = "your-datadog-api-key"
datadog_region  = "US1"  # US1, US3, US5, EU1, AP1, GOV
```

## Security Considerations

### Network Security

1. **Use Private Endpoints**: Enable VNet peering for private access
2. **IP Allowlisting**: Restrict public endpoint access to known IPs
3. **Network Security Groups**: Additional layer of network security
4. **TLS Encryption**: All communication encrypted in transit

### Access Control

1. **Admin Token**: Rotate the initial admin token after setup
2. **Service Principals**: Use least-privilege HCP service principals
3. **Azure RBAC**: Follow Azure role-based access control principles
4. **Vault Policies**: Implement least-privilege Vault policies

### Secrets Management

1. **Terraform State**: Store state securely (Azure Storage with encryption)
2. **Variables**: Use Azure Key Vault for sensitive variables
3. **Service Principals**: Rotate HCP service principal credentials regularly

## Outputs

The Terraform configuration provides these outputs:

| Output | Description |
|--------|-------------|
| `vault_public_endpoint_url` | Public Vault URL |
| `vault_private_endpoint_url` | Private Vault URL (if peering enabled) |
| `vault_admin_token` | Initial admin token (sensitive) |
| `vault_namespace` | Default Vault namespace |
| `hvn_id` | HashiCorp Virtual Network ID |
| `azure_peering_connection_id` | VNet peering connection ID |
| `vault_client_nsg_id` | Network security group ID |

## Maintenance

### Backup and Recovery

```bash
# Vault snapshots are automatically managed by HCP
# Monitor backup status in HCP Console
```

### Updates

```bash
# Update Terraform configuration
terraform plan
terraform apply

# Vault updates are managed by HashiCorp
# Monitor update status in HCP Console
```

### Monitoring

- **HCP Console**: Monitor cluster health and metrics
- **Datadog Integration**: Detailed metrics and alerting
- **Azure Monitor**: Azure resource monitoring

## Troubleshooting

### Common Issues

1. **Authentication Failed**
   ```bash
   # Verify HCP service principal
   export HCP_CLIENT_ID="your-client-id"
   export HCP_CLIENT_SECRET="your-client-secret"
   ```

2. **VNet Peering Failed**
   ```bash
   # Check Azure permissions
   az account show
   az role assignment list --assignee $(az account show --query user.name -o tsv)
   ```

3. **Network Connectivity**
   ```bash
   # Test network connectivity
   nslookup your-vault-cluster.vault.hashicorp.cloud
   telnet your-vault-cluster.vault.hashicorp.cloud 8200
   ```

### Getting Help

- [HCP Vault Documentation](https://cloud.hashicorp.com/docs/vault)
- [Terraform Azure Provider Documentation](https://registry.terraform.io/providers/hashicorp/azurerm/latest/docs)
- [HashiCorp Support](https://support.hashicorp.com/)

## Clean Up

```bash
# Destroy all resources
terraform destroy

# Confirm destruction
# This will permanently delete your Vault cluster and all data
```

## Next Steps

After deployment, consider:

1. **Configure Authentication Methods**: Set up Azure AD, OIDC, or other auth methods
2. **Set up Secret Engines**: Enable KV, database, Azure secrets engines
3. **Create Policies**: Implement least-privilege access policies
4. **Application Integration**: Connect applications using Vault SDKs
5. **Monitoring Setup**: Configure comprehensive monitoring and alerting

For detailed implementation guides, see the documentation in the `docs/` directory.