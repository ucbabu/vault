# Example: Azure AD HCP Organization SSO Setup with Terraform
# This example demonstrates how to use the azure-ad-hcp-sso module

terraform {
  required_version = ">= 1.0"
  required_providers {
    azuread = {
      source  = "hashicorp/azuread"
      version = "~> 2.47"
    }
    hcp = {
      source  = "hashicorp/hcp"
      version = "~> 0.78"
    }
  }
}

# Configure Azure AD Provider
provider "azuread" {
  tenant_id = var.azure_tenant_id
}

# Configure HCP Provider
provider "hcp" {
  client_id     = var.hcp_client_id
  client_secret = var.hcp_client_secret
}

# Example 1: Basic Azure AD HCP SSO Setup
module "azure_ad_hcp_sso_basic" {
  source = "../../modules/azure-ad-hcp-sso"

  # Basic Configuration
  application_name      = "HashiCorp Cloud Platform - Production"
  hcp_organization_id   = var.hcp_organization_id
  environment          = "prod"

  # Enable group creation and claims
  create_groups        = true
  enable_group_claims  = true

  # Security settings
  auto_grant_consent   = false  # Require manual admin consent for production
  jit_provisioning    = true
  enforce_sso         = false   # Set to true after testing

  tags = {
    Environment = "production"
    Project     = "vault-cloud-onboarding"
    Owner       = "platform-team"
    ManagedBy   = "terraform"
  }
}

# Example 2: Advanced Azure AD HCP SSO Setup with Custom Groups
module "azure_ad_hcp_sso_advanced" {
  source = "../../modules/azure-ad-hcp-sso"

  # Advanced Configuration
  application_name      = "HashiCorp Cloud Platform - Advanced"
  hcp_organization_id   = var.hcp_organization_id
  environment          = "prod"

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
    "HCP-Vault-PowerUsers" = {
      role     = "Admin"
      projects = ["vault-development", "vault-staging"]
    }
  }

  # Test users for validation
  create_test_users = true
  test_users = {
    "sso-test-admin" = {
      display_name = "SSO Test Administrator"
      groups       = ["HCP-Platform-Admins"]
    }
    "sso-test-developer" = {
      display_name = "SSO Test Developer"
      groups       = ["HCP-Vault-Developers", "HCP-Data-Engineers"]
    }
    "sso-test-auditor" = {
      display_name = "SSO Test Auditor"
      groups       = ["HCP-Security-Team", "HCP-Compliance-Team"]
    }
  }

  # Security and compliance settings
  token_lifetime_policies = {
    access_token_lifetime  = "PT30M"   # 30 minutes for high security
    id_token_lifetime      = "PT30M"   # 30 minutes
    refresh_token_lifetime = "P7D"     # 7 days
  }

  # Session controls
  session_controls = {
    sign_in_frequency_enabled = true
    sign_in_frequency_value   = 4
    sign_in_frequency_type    = "Hours"
  }

  # Feature flags
  feature_flags = {
    enable_risk_based_policies    = true
    enable_session_management     = true
    enable_certificate_auth       = false
    enable_device_compliance      = true
    enable_location_based_access  = false
  }

  # Monitoring and notifications
  notification_settings = {
    enabled                     = true
    notify_on_config_changes    = true
    notify_on_auth_failures     = true
    notification_email          = "platform-team@company.com"
    auth_failure_threshold      = 3
  }

  tags = {
    Environment = "production"
    Project     = "vault-cloud-onboarding"
    Owner       = "platform-team"
    ManagedBy   = "terraform"
    Compliance  = "required"
  }
}

# Example 3: Development Environment Setup
module "azure_ad_hcp_sso_dev" {
  source = "../../modules/azure-ad-hcp-sso"

  # Development Configuration
  application_name      = "HashiCorp Cloud Platform - Development"
  hcp_organization_id   = var.hcp_organization_id_dev
  environment          = "dev"

  # Relaxed settings for development
  auto_grant_consent   = true   # Auto-consent for development
  jit_provisioning    = true
  enforce_sso         = false

  # Create test users for development
  create_test_users = true
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

  # Simplified token policies for development
  token_lifetime_policies = {
    access_token_lifetime  = "PT8H"    # 8 hours for development
    id_token_lifetime      = "PT8H"    # 8 hours
    refresh_token_lifetime = "P30D"    # 30 days
  }

  tags = {
    Environment = "development"
    Project     = "vault-cloud-onboarding"
    Owner       = "development-team"
    ManagedBy   = "terraform"
  }
}

# Data sources for additional configuration
data "azuread_domains" "tenant_domains" {}

data "azuread_client_config" "current" {}

# Local values for common configuration
locals {
  common_tags = {
    Project     = "vault-cloud-onboarding"
    ManagedBy   = "terraform"
    CreatedBy   = data.azuread_client_config.current.object_id
    CreatedDate = timestamp()
  }
}