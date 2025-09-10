# Terraform configuration for HashiCorp Vault Cloud setup
terraform {
  required_version = ">= 1.0"
  required_providers {
    hcp = {
      source  = "hashicorp/hcp"
      version = "~> 0.78"
    }
    azurerm = {
      source  = "hashicorp/azurerm"
      version = "~> 3.0"
    }
    azuread = {
      source  = "hashicorp/azuread"
      version = "~> 2.47"
    }
    tfe = {
      source  = "hashicorp/tfe"
      version = "~> 0.50"
    }
    vault = {
      source  = "hashicorp/vault"
      version = "~> 3.0"
    }
  }
}

# Configure HCP provider
provider "hcp" {
  client_id     = var.hcp_client_id
  client_secret = var.hcp_client_secret
}

# Configure Azure provider for networking
provider "azurerm" {
  features {}
  subscription_id = var.azure_subscription_id
  tenant_id       = var.azure_tenant_id
}

# Configure Azure AD provider for SSO
provider "azuread" {
  tenant_id = var.azure_tenant_id
}

# Configure HCP Terraform provider
provider "tfe" {
  token = var.hcp_terraform_token
}

# Configure Vault provider (conditionally configured)
provider "vault" {
  address   = hcp_vault_cluster.main.vault_public_endpoint_url
  namespace = hcp_vault_cluster.main.namespace
  token     = hcp_vault_cluster_admin_token.admin_token.token
}

# Create HashiCorp Virtual Network (HVN)
resource "hcp_hvn" "vault_hvn" {
  hvn_id         = var.hvn_id
  cloud_provider = "azure"
  region         = var.azure_region
  cidr_block     = var.hvn_cidr_block
}

# Create Vault cluster
resource "hcp_vault_cluster" "main" {
  cluster_id      = var.vault_cluster_id
  hvn_id          = hcp_hvn.vault_hvn.hvn_id
  tier            = var.vault_tier
  public_endpoint = var.public_endpoint_enabled

  # Configure metrics export
  dynamic "metrics_config" {
    for_each = var.datadog_api_key != "" ? [1] : []
    content {
      datadog_api_key = var.datadog_api_key
      datadog_region  = var.datadog_region
    }
  }

  # Configure audit log export
  dynamic "audit_log_config" {
    for_each = var.datadog_api_key != "" ? [1] : []
    content {
      datadog_api_key = var.datadog_api_key
      datadog_region  = var.datadog_region
    }
  }

  # Configure IP allowlist for public endpoint
  dynamic "ip_allowlist" {
    for_each = var.ip_allowlist
    content {
      address     = ip_allowlist.value.cidr
      description = ip_allowlist.value.description
    }
  }
}

# Create Azure resource group for networking (optional)
resource "azurerm_resource_group" "vault_networking" {
  count = var.enable_vnet_peering ? 1 : 0
  
  name     = "${var.vault_cluster_id}-networking-rg"
  location = var.azure_region

  tags = merge(var.additional_tags, {
    Environment = var.environment
    Project     = "vault-cloud-onboarding"
    Owner       = var.owner
  })
}

# Create VNet peering connection (optional)
resource "hcp_azure_peering_connection" "vault_peering" {
  count = var.enable_vnet_peering ? 1 : 0

  hvn_link                 = hcp_hvn.vault_hvn.self_link
  peering_id               = "${var.vault_cluster_id}-peering"
  peer_vnet_name           = var.vnet_name
  peer_subscription_id     = var.azure_subscription_id
  peer_tenant_id           = var.azure_tenant_id
  peer_resource_group_name = var.vnet_resource_group_name
  peer_vnet_region         = var.azure_region
}

# Create HVN route for VNet peering
resource "hcp_hvn_route" "vault_peering_route" {
  count = var.enable_vnet_peering ? 1 : 0

  hvn_link         = hcp_hvn.vault_hvn.self_link
  hvn_route_id     = "${var.vault_cluster_id}-peering-route"
  destination_cidr = var.vnet_cidr_block
  target_link      = hcp_azure_peering_connection.vault_peering[0].self_link
}

# Generate admin token
resource "hcp_vault_cluster_admin_token" "admin_token" {
  cluster_id = hcp_vault_cluster.main.cluster_id
}

# Create network security group for Vault access (if VNet peering enabled)
resource "azurerm_network_security_group" "vault_client" {
  count = var.enable_vnet_peering ? 1 : 0

  name                = "${var.vault_cluster_id}-client-nsg"
  location            = var.azure_region
  resource_group_name = azurerm_resource_group.vault_networking[0].name

  # Outbound to Vault cluster
  security_rule {
    name                       = "AllowVaultHTTPS"
    priority                   = 1001
    direction                  = "Outbound"
    access                     = "Allow"
    protocol                   = "Tcp"
    source_port_range          = "*"
    destination_port_range     = "8200"
    source_address_prefix      = "*"
    destination_address_prefix = hcp_hvn.vault_hvn.cidr_block
    description                = "HTTPS to Vault cluster"
  }

  # Outbound HTTPS for general internet access
  security_rule {
    name                       = "AllowHTTPSOutbound"
    priority                   = 1002
    direction                  = "Outbound"
    access                     = "Allow"
    protocol                   = "Tcp"
    source_port_range          = "*"
    destination_port_range     = "443"
    source_address_prefix      = "*"
    destination_address_prefix = "Internet"
    description                = "HTTPS outbound"
  }

  tags = merge(var.additional_tags, {
    Name        = "${var.vault_cluster_id}-client-nsg"
    Environment = var.environment
    Project     = "vault-cloud-onboarding"
  })
}

# Data source to get current Azure client configuration
data "azurerm_client_config" "current" {}

# Data source to get available Azure locations
data "azurerm_locations" "available" {}

# Optional: Azure AD HCP Organization SSO Setup
module "azure_ad_hcp_sso" {
  count  = var.enable_hcp_sso ? 1 : 0
  source = "./modules/azure-ad-hcp-sso"

  # Basic configuration
  application_name    = "${var.vault_cluster_id}-hcp-sso"
  hcp_organization_id = var.hcp_organization_id
  environment        = var.environment

  # SSO settings
  create_groups       = var.hcp_sso_create_groups
  enable_group_claims = var.hcp_sso_enable_group_claims
  jit_provisioning   = var.hcp_sso_jit_provisioning
  enforce_sso        = var.hcp_sso_enforce_sso
  auto_grant_consent = var.hcp_sso_auto_grant_consent

  # Additional groups (if specified)
  additional_groups = var.hcp_sso_additional_groups

  # Test users for development/staging
  create_test_users = var.environment != "prod" ? var.hcp_sso_create_test_users : false
  test_users       = var.hcp_sso_test_users

  # Token lifetime policies
  token_lifetime_policies = var.hcp_sso_token_lifetime_policies

  # Tags
  tags = merge(var.additional_tags, {
    Environment = var.environment
    Project     = "vault-cloud-onboarding"
    Owner       = var.owner
    Component   = "hcp-sso"
  })
}

# HCP Terraform Organization (Data source)
data "tfe_organization" "main" {
  count = var.enable_hcp_terraform ? 1 : 0
  name  = var.hcp_terraform_organization
}

# Create HCP Terraform workspace for Azure infrastructure
resource "tfe_workspace" "azure_infrastructure" {
  count = var.enable_hcp_terraform ? 1 : 0
  
  name              = var.hcp_terraform_workspace_name
  organization      = var.hcp_terraform_organization
  description       = "Azure infrastructure managed with dynamic Vault credentials"
  auto_apply        = var.hcp_terraform_auto_apply
  execution_mode    = "remote"
  terraform_version = var.hcp_terraform_version
  
  # Enable Vault integration
  global_remote_state = false
  
  # Working directory for modular configurations
  working_directory = var.hcp_terraform_working_directory
  
  # File triggers (if specified)
  dynamic "file_triggers_enabled" {
    for_each = var.hcp_terraform_file_triggers_enabled ? [1] : []
    content {
      enabled = true
    }
  }
  
  # VCS repository configuration (if specified)
  dynamic "vcs_repo" {
    for_each = var.hcp_terraform_vcs_repo != null ? [var.hcp_terraform_vcs_repo] : []
    content {
      identifier     = vcs_repo.value.identifier
      branch         = vcs_repo.value.branch
      oauth_token_id = vcs_repo.value.oauth_token_id
    }
  }
  
  tag_names = concat([
    "vault-integration",
    "azure-dynamic-credentials",
    var.environment
  ], var.hcp_terraform_additional_tags)
}

# Configure Vault authentication for HCP Terraform workspace
resource "vault_jwt_auth_backend" "hcp_terraform" {
  count = var.enable_hcp_terraform ? 1 : 0
  
  description  = "JWT auth backend for HCP Terraform"
  path         = "hcp_terraform"
  oidc_discovery_url = "https://app.terraform.io"
  bound_issuer = "https://app.terraform.io"
}

# Create Vault policy for HCP Terraform Azure credentials
resource "vault_policy" "hcp_terraform_azure" {
  count = var.enable_hcp_terraform ? 1 : 0
  
  name = "hcp-terraform-azure"
  
  policy = <<EOF
# Allow HCP Terraform to read Azure dynamic credentials
path "azure/creds/${var.vault_azure_role_name}" {
  capabilities = ["read"]
}

# Allow reading Azure role configuration
path "azure/roles/${var.vault_azure_role_name}" {
  capabilities = ["read"]
}

# Allow listing Azure roles
path "azure/roles" {
  capabilities = ["list"]
}

# Allow reading Azure secrets engine configuration
path "azure/config" {
  capabilities = ["read"]
}
EOF
}

# Create Vault role for HCP Terraform authentication
resource "vault_jwt_auth_backend_role" "hcp_terraform" {
  count = var.enable_hcp_terraform ? 1 : 0
  
  backend         = vault_jwt_auth_backend.hcp_terraform[0].path
  role_name       = "hcp-terraform-azure"
  token_policies  = [vault_policy.hcp_terraform_azure[0].name]
  
  bound_audiences = ["vault.workload.identity"]
  bound_claims = {
    sub = "organization:${var.hcp_terraform_organization}:workspace:${var.hcp_terraform_workspace_name}:run_phase:*"
  }
  
  user_claim      = "terraform_full_workspace"
  role_type       = "jwt"
  token_ttl       = 3600  # 1 hour
  token_max_ttl   = 7200  # 2 hours
}

# Configure HCP Terraform workspace variables for Vault integration
resource "tfe_variable" "vault_addr" {
  count = var.enable_hcp_terraform ? 1 : 0
  
  key          = "VAULT_ADDR"
  value        = hcp_vault_cluster.main.vault_public_endpoint_url
  category     = "env"
  workspace_id = tfe_workspace.azure_infrastructure[0].id
  description  = "Vault server URL for dynamic credentials"
}

resource "tfe_variable" "vault_namespace" {
  count = var.enable_hcp_terraform ? 1 : 0
  
  key          = "VAULT_NAMESPACE"
  value        = hcp_vault_cluster.main.namespace
  category     = "env"
  workspace_id = tfe_workspace.azure_infrastructure[0].id
  description  = "Vault namespace for dynamic credentials"
}

resource "tfe_variable" "azure_subscription_id" {
  count = var.enable_hcp_terraform ? 1 : 0
  
  key          = "ARM_SUBSCRIPTION_ID"
  value        = var.azure_subscription_id
  category     = "env"
  workspace_id = tfe_workspace.azure_infrastructure[0].id
  description  = "Azure subscription ID for Terraform"
}

resource "tfe_variable" "azure_tenant_id" {
  count = var.enable_hcp_terraform ? 1 : 0
  
  key          = "ARM_TENANT_ID"
  value        = var.azure_tenant_id
  category     = "env"
  workspace_id = tfe_workspace.azure_infrastructure[0].id
  description  = "Azure tenant ID for Terraform"
}

# Azure role name for dynamic credentials
resource "tfe_variable" "vault_azure_role" {
  count = var.enable_hcp_terraform ? 1 : 0
  
  key          = "VAULT_AZURE_ROLE"
  value        = var.vault_azure_role_name
  category     = "env"
  workspace_id = tfe_workspace.azure_infrastructure[0].id
  description  = "Vault Azure role for dynamic credentials"
}

# Terraform variables for workspace configuration
resource "tfe_variable" "environment" {
  count = var.enable_hcp_terraform ? 1 : 0
  
  key          = "environment"
  value        = var.environment
  category     = "terraform"
  workspace_id = tfe_workspace.azure_infrastructure[0].id
  description  = "Environment name for resource tagging"
}

resource "tfe_variable" "azure_region" {
  count = var.enable_hcp_terraform ? 1 : 0
  
  key          = "azure_region"
  value        = var.azure_region
  category     = "terraform"
  workspace_id = tfe_workspace.azure_infrastructure[0].id
  description  = "Azure region for resource deployment"
}

# Optional: Configure notification for workspace runs
resource "tfe_notification_configuration" "vault_integration" {
  count = var.enable_hcp_terraform && var.hcp_terraform_notification_webhook != "" ? 1 : 0
  
  name             = "vault-credential-notification"
  enabled          = true
  destination_type = "generic"
  triggers         = ["run:created", "run:planning", "run:needs_attention", "run:applying", "run:completed", "run:errored"]
  url              = var.hcp_terraform_notification_webhook
  workspace_id     = tfe_workspace.azure_infrastructure[0].id
}