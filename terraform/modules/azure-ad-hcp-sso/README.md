# Azure AD HCP Organization SSO Terraform Module

This Terraform module automates the complete setup of Azure AD (Entra ID) integration with HashiCorp Cloud Platform (HCP) Organization SSO. It creates and configures the Azure AD application, security groups, and provides the necessary configuration for HCP SSO setup.

## Table of Contents

1. [Features](#features)
2. [Prerequisites](#prerequisites)
3. [Usage](#usage)
4. [Examples](#examples)
5. [Inputs](#inputs)
6. [Outputs](#outputs)
7. [Security Considerations](#security-considerations)
8. [Troubleshooting](#troubleshooting)

## Features

- ✅ **Azure AD Application Creation**: Automatically creates and configures Azure AD application for HCP SSO
- ✅ **Security Groups Management**: Creates Azure AD security groups with proper role mappings
- ✅ **OIDC Configuration**: Configures OIDC settings including claims and scopes
- ✅ **Client Secret Management**: Manages client secrets with automatic rotation
- ✅ **Group Claims**: Enables group claims in ID tokens for role-based access
- ✅ **Test Users**: Optional creation of test users for SSO validation
- ✅ **Comprehensive Outputs**: Provides all necessary information for HCP configuration
- ✅ **Security Best Practices**: Implements Azure AD security recommendations

## Prerequisites

- **Terraform** >= 1.0
- **Azure CLI** installed and authenticated
- **Azure AD Global Administrator** or **Application Administrator** role
- **HCP Organization Owner** or **Admin** role (for HCP configuration)
- **Azure AD Tenant** with verified domain

### Required Terraform Providers

```hcl
terraform {
  required_providers {
    azuread = {
      source  = "hashicorp/azuread"
      version = "~> 2.47"
    }
    hcp = {
      source  = "hashicorp/hcp"
      version = "~> 0.78"
    }
    random = {
      source  = "hashicorp/random"
      version = "~> 3.5"
    }
    time = {
      source  = "hashicorp/time"
      version = "~> 0.9"
    }
  }
}
```

## Usage

### Basic Usage

```hcl
module "azure_ad_hcp_sso" {
  source = "./modules/azure-ad-hcp-sso"

  # Basic Configuration
  application_name    = "HashiCorp Cloud Platform"
  hcp_organization_id = "your-hcp-org-id"
  environment        = "prod"

  # Enable default groups and claims
  create_groups       = true
  enable_group_claims = true
  jit_provisioning   = true

  tags = {
    Environment = "production"
    Project     = "vault-cloud-onboarding"
    ManagedBy   = "terraform"
  }
}
```

### Configure HCP SSO After Module Creation

```bash
# Use the output command to configure HCP SSO
terraform output -raw hcp_sso_setup_command | bash
```

### Manual HCP Configuration

```bash
# Alternative: Use individual outputs for manual configuration
export AZURE_TENANT_ID=$(terraform output -raw tenant_id)
export CLIENT_ID=$(terraform output -raw application_id)
export CLIENT_SECRET=$(terraform output -raw client_secret)
export ISSUER_URL=$(terraform output -raw oidc_issuer_url)

./scripts/hcp-org-sso-setup.sh oidc \
  --name "Azure AD" \
  --org-id "your-hcp-org-id" \
  --oidc-issuer "$ISSUER_URL" \
  --oidc-client-id "$CLIENT_ID" \
  --oidc-secret "$CLIENT_SECRET" \
  --jit-provisioning
```

## Examples

### Production Environment with Custom Groups

```hcl
module "azure_ad_hcp_sso_prod" {
  source = "./modules/azure-ad-hcp-sso"

  application_name    = "HashiCorp Cloud Platform - Production"
  hcp_organization_id = "your-prod-org-id"
  environment        = "prod"

  # Custom groups in addition to defaults
  additional_groups = {
    "HCP-Data-Engineers" = {
      role     = "Contributor"
      projects = ["vault-data", "vault-analytics"]
    }
    "HCP-Compliance-Team" = {
      role     = "Viewer"  
      projects = ["*"]
    }
  }

  # Security settings for production
  auto_grant_consent = false  # Require manual consent
  enforce_sso       = true   # Enforce SSO after testing

  # Token lifetime policies
  token_lifetime_policies = {
    access_token_lifetime  = "PT1H"    # 1 hour
    id_token_lifetime      = "PT1H"    # 1 hour
    refresh_token_lifetime = "P7D"     # 7 days
  }

  tags = {
    Environment = "production"
    Compliance  = "required"
    ManagedBy   = "terraform"
  }
}
```

### Development Environment with Test Users

```hcl
module "azure_ad_hcp_sso_dev" {
  source = "./modules/azure-ad-hcp-sso"

  application_name    = "HashiCorp Cloud Platform - Development"
  hcp_organization_id = "your-dev-org-id"
  environment        = "dev"

  # Development-friendly settings
  auto_grant_consent = true   # Auto-consent for development
  create_test_users = true   # Create test users

  test_users = {
    "dev-admin" = {
      display_name = "Development Admin"
      groups       = ["HCP-Platform-Admins"]
    }
    "dev-user" = {
      display_name = "Development User"
      groups       = ["HCP-Vault-Developers"]
    }
  }

  tags = {
    Environment = "development"
    ManagedBy   = "terraform"
  }
}
```

For more examples, see the [examples directory](examples/).

## Default Azure AD Groups

The module creates the following Azure AD security groups by default:

| Group Name | HCP Role | Default Projects | Description |
|------------|----------|------------------|-------------|
| `HCP-Platform-Admins` | Admin | `*` (all) | Full platform administration |
| `HCP-Vault-Admins` | Admin | `vault-production`, `vault-staging` | Vault administration |
| `HCP-Vault-Operators` | Contributor | `vault-production`, `vault-staging` | Vault operations |
| `HCP-Vault-Developers` | Contributor | `vault-development`, `vault-staging` | Vault development |
| `HCP-Security-Team` | Viewer | `*` (all) | Security audit and compliance |

## Inputs

| Name | Description | Type | Default | Required |
|------|-------------|------|---------|:--------:|
| `application_name` | Name of the Azure AD application | `string` | `"HashiCorp Cloud Platform"` | no |
| `hcp_organization_id` | HCP Organization ID | `string` | `""` | no |
| `environment` | Environment name (dev, staging, prod) | `string` | `"dev"` | no |
| `create_groups` | Create Azure AD security groups | `bool` | `true` | no |
| `enable_group_claims` | Enable group claims in ID token | `bool` | `true` | no |
| `jit_provisioning` | Enable Just-In-Time user provisioning | `bool` | `true` | no |
| `enforce_sso` | Enforce SSO for all users | `bool` | `false` | no |
| `auto_grant_consent` | Automatically grant admin consent | `bool` | `false` | no |
| `create_test_users` | Create test users for validation | `bool` | `false` | no |
| `additional_groups` | Additional groups beyond defaults | `map(object)` | `{}` | no |
| `client_secret_rotation_years` | Years before client secret rotation | `number` | `2` | no |
| `tags` | Tags to apply to resources | `map(string)` | `{}` | no |

For complete input documentation, see [variables.tf](variables.tf).

## Outputs

| Name | Description | Sensitive |
|------|-------------|:---------:|
| `application_id` | Azure AD Application (Client) ID | no |
| `client_secret` | Azure AD Application Client Secret | yes |
| `oidc_issuer_url` | OIDC Issuer URL for HCP configuration | no |
| `tenant_id` | Azure AD Tenant ID | no |
| `created_groups` | Information about created Azure AD groups | no |
| `hcp_sso_setup_command` | Complete command for HCP SSO setup | yes |
| `sso_test_url` | URL to test SSO login | no |
| `security_recommendations` | Security recommendations | no |

For complete output documentation, see [outputs.tf](outputs.tf).

## Security Considerations

### Authentication and Authorization

1. **Client Secret Management**
   - Client secrets are automatically rotated based on `client_secret_rotation_years`
   - Secrets are marked as sensitive in Terraform state
   - Use Azure Key Vault for additional secret protection in production

2. **Group-Based Access Control**
   - Implement principle of least privilege
   - Regularly review group memberships
   - Use separate groups for different environments

3. **Token Lifetime Policies**
   - Configure appropriate token lifetimes for your security requirements
   - Shorter lifetimes increase security but may impact user experience
   - Consider conditional access policies for enhanced security

### Production Recommendations

```hcl
# Recommended production settings
module "azure_ad_hcp_sso_secure" {
  source = "./modules/azure-ad-hcp-sso"

  # Security settings
  auto_grant_consent = false  # Require manual review
  enforce_sso       = true   # After testing
  
  # Short token lifetimes
  token_lifetime_policies = {
    access_token_lifetime  = "PT30M"  # 30 minutes
    id_token_lifetime      = "PT30M"  # 30 minutes
    refresh_token_lifetime = "P7D"    # 7 days
  }

  # Enable session controls
  session_controls = {
    sign_in_frequency_enabled = true
    sign_in_frequency_value   = 4
    sign_in_frequency_type    = "Hours"
  }
}
```

## Troubleshooting

### Common Issues

#### 1. Insufficient Azure AD Permissions
```bash
# Error: Insufficient privileges to complete the operation
# Solution: Ensure you have Global Administrator or Application Administrator role
az role assignment list --assignee $(az account show --query user.name -o tsv) --all
```

#### 2. Group Claims Not Received
```bash
# Verify group claims configuration
terraform output troubleshooting_info
curl -s "$(terraform output -raw oidc_discovery_url)" | jq .
```

#### 3. HCP SSO Configuration Issues
```bash
# Test OIDC endpoints
terraform output -raw oidc_issuer_url
curl -s "$(terraform output -raw oidc_discovery_url)" | jq '.issuer'

# Verify client credentials
az ad app show --id $(terraform output -raw application_id)
```

### Validation Commands

```bash
# Test Azure AD configuration
terraform output troubleshooting_info

# Validate OIDC discovery
curl -s "$(terraform output -raw oidc_discovery_url)" | jq .

# Check group memberships
az ad signed-in-user get-member-groups --query "value[].displayName"

# Test SSO login (replace with actual org ID)
echo "Test SSO at: $(terraform output -raw sso_test_url)"
```

### Recovery Procedures

1. **Client Secret Rotation**
   ```bash
   # Force client secret rotation
   terraform apply -replace="module.azure_ad_hcp_sso.time_rotating.secret_rotation"
   ```

2. **Application Recovery**
   ```bash
   # Import existing application
   terraform import module.azure_ad_hcp_sso.azuread_application.hcp_sso <application-id>
   ```

## Migration from Manual Setup

If you have an existing manual Azure AD application:

1. **Import existing resources**:
   ```bash
   terraform import module.azure_ad_hcp_sso.azuread_application.hcp_sso <application-id>
   terraform import module.azure_ad_hcp_sso.azuread_service_principal.hcp_sso <service-principal-id>
   ```

2. **Update configuration** to match your existing setup

3. **Plan and apply** to bring under Terraform management

## Contributing

1. Follow the existing code style and conventions
2. Update documentation for any new features
3. Add examples for new functionality
4. Test changes in a development environment first

## Support

- **Module Issues**: Create an issue in this repository
- **Azure AD Documentation**: [Azure AD Application Registration](https://docs.microsoft.com/en-us/azure/active-directory/develop/quickstart-register-app)
- **HCP Documentation**: [HCP SSO Configuration](https://cloud.hashicorp.com/docs/hcp/admin/sso)
- **Terraform Provider**: [Azure AD Provider Documentation](https://registry.terraform.io/providers/hashicorp/azuread/latest/docs)