# Story 1: Vault Cloud Setup and Configuration Implementation

## Overview

This implementation provides Infrastructure as Code (Terraform) and configuration scripts for setting up HashiCorp Vault Cloud with initial security configuration.

## Implementation Components

### 1. Terraform Infrastructure (`terraform/`)

- **`main.tf`**: Core infrastructure definition
  - HCP Vault cluster provisioning
  - HashiCorp Virtual Network (HVN) setup
  - Optional VPC peering configuration
  - Security group setup

- **`variables.tf`**: Configurable parameters
  - HCP authentication
  - Cluster sizing and networking
  - Security and monitoring settings

- **`outputs.tf`**: Important resource information
  - Vault connection details
  - Environment variables
  - CLI setup commands

- **`terraform.tfvars.example`**: Example configuration values

### 2. Configuration Scripts (`scripts/`)

- **`vault-initial-setup.sh`**: Automated initial configuration
  - Audit logging enablement
  - Initial policies creation
  - Authentication methods setup
  - Secrets engines enablement
  - Security configuration

## Deployment Instructions

### Prerequisites

1. **HCP Account Setup**
   ```bash
   # Create HCP service principal at:
   # https://cloud.hashicorp.com/docs/hcp/admin/service-principals
   ```

2. **Install Required Tools**
   ```bash
   # Install Terraform
   curl -fsSL https://apt.releases.hashicorp.com/gpg | sudo apt-key add -
   sudo apt-add-repository "deb [arch=amd64] https://apt.releases.hashicorp.com $(lsb_release -cs) main"
   sudo apt-get update && sudo apt-get install terraform

   # Install Vault CLI
   sudo apt-get install vault

   # Install jq for JSON processing
   sudo apt-get install jq
   ```

3. **AWS CLI Configuration** (if using VPC peering)
   ```bash
   aws configure
   ```

### Step 1: Infrastructure Deployment

1. **Configure Terraform Variables**
   ```bash
   cd terraform/
   cp terraform.tfvars.example terraform.tfvars
   
   # Edit terraform.tfvars with your values
   nano terraform.tfvars
   ```

2. **Deploy Infrastructure**
   ```bash
   # Initialize Terraform
   terraform init
   
   # Plan deployment
   terraform plan
   
   # Apply configuration
   terraform apply
   ```

3. **Capture Outputs**
   ```bash
   # Get Vault connection information
   terraform output vault_connection_info
   
   # Get admin token (sensitive)
   terraform output -raw vault_admin_token
   
   # Get CLI setup commands
   terraform output -raw vault_cli_setup
   ```

### Step 2: Initial Configuration

1. **Set Environment Variables**
   ```bash
   # Use output from Terraform
   export VAULT_ADDR=$(terraform output -raw vault_public_endpoint_url)
   export VAULT_NAMESPACE=$(terraform output -raw vault_namespace)
   export VAULT_TOKEN=$(terraform output -raw vault_admin_token)
   ```

2. **Run Initial Setup Script**
   ```bash
   cd ../scripts/
   ./vault-initial-setup.sh
   ```

3. **Verify Configuration**
   ```bash
   # Check Vault status
   vault status
   
   # List enabled secrets engines
   vault secrets list
   
   # List authentication methods
   vault auth list
   
   # List policies
   vault policy list
   ```

## Configuration Details

### Terraform Configuration Options

#### Cluster Sizing
```hcl
# Development
vault_tier = "dev"

# Small production
vault_tier = "standard_small"

# Medium production  
vault_tier = "standard_medium"

# Large production
vault_tier = "standard_large"
```

#### Network Configuration
```hcl
# Public endpoint with IP restrictions
public_endpoint_enabled = true
ip_allowlist = [
  {
    cidr        = "203.0.113.0/24"
    description = "Office network"
  }
]

# Private endpoint with VPC peering
enable_vpc_peering = true
vpc_id            = "vpc-12345678"
vpc_cidr_block    = "10.0.0.0/16"
route_table_ids   = ["rtb-12345678"]
```

#### Monitoring Integration
```hcl
# Datadog integration
datadog_api_key = "your-datadog-api-key"
datadog_region  = "US1"
```

### Initial Policies Created

1. **Admin Policy** - Full Vault access
2. **Developer Policy** - Application secrets and limited dynamic credentials
3. **Operator Policy** - Monitoring and maintenance access
4. **CI/CD Policy** - Automated deployment access

### Authentication Methods

- **Userpass** - For testing and initial access
- **Future**: OIDC, AWS IAM, Kubernetes (configure separately)

### Secrets Engines Enabled

- **KV v2** - Static secret storage at `secret/`
- **Database** - Dynamic database credentials
- **Azure** - Dynamic Azure credentials

## Testing the Setup

### 1. Basic Functionality
```bash
# Test admin access
vault status
vault policy list
vault secrets list

# Test secret storage
vault kv put secret/test/example key=value
vault kv get secret/test/example
vault kv delete secret/test/example
```

### 2. Policy Testing
```bash
# Test developer access
vault login -method=userpass username=developer password=developer123
vault kv get secret/dev/shared/info

# Test operator access
vault login -method=userpass username=operator password=operator123
vault read sys/health
```

### 3. Audit Verification
```bash
# Check audit logs (if accessible)
vault audit list
```

## Security Considerations

### 1. Network Security
- **IP Allowlisting**: Restrict public endpoint access
- **VPC Peering**: Use private networking for production
- **TLS**: All communication encrypted in transit

### 2. Authentication
- **Strong Passwords**: Default password policy enforced
- **Multi-Factor**: Consider enabling MFA for admin access
- **Production Auth**: Replace userpass with OIDC/IAM

### 3. Audit and Monitoring
- **Audit Logging**: All API requests logged
- **Metrics Export**: Integrated with monitoring systems
- **Alerting**: Set up alerts for security events

## Troubleshooting

### Common Issues

1. **Terraform Authentication**
   ```bash
   # Verify HCP credentials
   export HCP_CLIENT_ID="your-client-id"
   export HCP_CLIENT_SECRET="your-client-secret"
   ```

2. **Vault Connection**
   ```bash
   # Test connectivity
   curl -k $VAULT_ADDR/v1/sys/health
   
   # Check DNS resolution
   nslookup $(echo $VAULT_ADDR | cut -d'/' -f3)
   ```

3. **Permission Issues**
   ```bash
   # Verify token capabilities
   vault token lookup
   vault token capabilities secret/
   ```

### Cleanup

To remove all resources:
```bash
cd terraform/
terraform destroy
```

## Next Steps

After completing Story 1:

1. **Configure Production Authentication** (OIDC/SAML)
2. **Set up Keystore Management** (Story 2)
3. **Configure Azure Integration** (Story 3)
4. **Set up Database Integration** (Story 4)
5. **Implement Monitoring** (Story 5)
6. **Configure Backup/Recovery** (Story 6)

## Success Criteria Validation

- [x] Vault Cloud instance provisioned with appropriate sizing
- [x] Initial authentication methods configured
- [x] Network security controls implemented
- [x] Admin policies and initial users configured
- [x] Vault cluster properly initialized and unsealed
- [x] SSL/TLS certificates configured (automatic with Vault Cloud)
- [x] Audit logging enabled

This implementation provides a complete foundation for the HashiCorp Vault Cloud onboarding project.