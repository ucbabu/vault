# Basic Azure Deployment with HCP Terraform and Vault

terraform {
  required_version = ">= 1.0"
  required_providers {
    vault = {
      source  = "hashicorp/vault"
      version = "~> 3.0"
    }
    azurerm = {
      source  = "hashicorp/azurerm"
      version = "~> 3.0"
    }
  }
}

# Configure Vault provider with JWT authentication
provider "vault" {
  address   = var.vault_addr
  namespace = var.vault_namespace
  
  # HCP Terraform will automatically provide JWT token
  auth_login_jwt {
    role  = "hcp-terraform-azure"
    mount = "hcp_terraform"
  }
}

# Get dynamic Azure credentials from Vault
data "vault_generic_secret" "azure_creds" {
  path = "azure/creds/${var.vault_azure_role}"
}

# Configure Azure provider with dynamic credentials
provider "azurerm" {
  features {
    resource_group {
      prevent_deletion_if_contains_resources = false
    }
  }
  
  subscription_id = var.azure_subscription_id
  tenant_id       = var.azure_tenant_id
  client_id       = data.vault_generic_secret.azure_creds.data["client_id"]
  client_secret   = data.vault_generic_secret.azure_creds.data["client_secret"]
}

# Create a resource group
resource "azurerm_resource_group" "main" {
  name     = "${var.project_name}-${var.environment}-rg"
  location = var.azure_region
  
  tags = local.common_tags
}

# Create a storage account
resource "azurerm_storage_account" "main" {
  name                     = "${var.project_name}${var.environment}storage"
  resource_group_name      = azurerm_resource_group.main.name
  location                = azurerm_resource_group.main.location
  account_tier            = var.storage_account_tier
  account_replication_type = var.storage_replication_type
  
  # Security configurations
  min_tls_version                = "TLS1_2"
  allow_nested_items_to_be_public = false
  
  blob_properties {
    versioning_enabled       = true
    change_feed_enabled     = true
    delete_retention_policy {
      days = 7
    }
    container_delete_retention_policy {
      days = 7
    }
  }
  
  tags = local.common_tags
}

# Create a storage container
resource "azurerm_storage_container" "main" {
  name                  = "${var.project_name}-${var.environment}-container"
  storage_account_name  = azurerm_storage_account.main.name
  container_access_type = "private"
}

# Optional: Create a Key Vault for additional secrets
resource "azurerm_key_vault" "main" {
  count = var.create_key_vault ? 1 : 0
  
  name                = "${var.project_name}-${var.environment}-kv"
  location            = azurerm_resource_group.main.location
  resource_group_name = azurerm_resource_group.main.name
  tenant_id           = var.azure_tenant_id
  
  sku_name = "standard"
  
  # Key Vault access policy for the dynamic service principal
  access_policy {
    tenant_id = var.azure_tenant_id
    object_id = data.azurerm_client_config.current.object_id
    
    key_permissions = [
      "Get",
      "List",
      "Create",
      "Delete",
      "Update",
    ]
    
    secret_permissions = [
      "Get",
      "List",
      "Set",
      "Delete",
    ]
  }
  
  tags = local.common_tags
}

# Get current client configuration for Key Vault access
data "azurerm_client_config" "current" {}

# Local values for common configurations
locals {
  common_tags = {
    Environment       = var.environment
    Project          = var.project_name
    ManagedBy        = "HCP-Terraform"
    CredentialSource = "Vault-Dynamic"
    Owner            = var.team_name
    CreatedBy        = "Terraform"
    CreatedAt        = timestamp()
  }
}

# Example secret in Key Vault (if created)
resource "azurerm_key_vault_secret" "example" {
  count = var.create_key_vault ? 1 : 0
  
  name         = "example-secret"
  value        = "This is a secret managed by HCP Terraform with Vault credentials"
  key_vault_id = azurerm_key_vault.main[0].id
  
  tags = local.common_tags
}