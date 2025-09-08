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