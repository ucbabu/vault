# Outputs for HashiCorp Vault Cloud on Azure

# Vault Cluster Information
output "vault_cluster_id" {
  description = "ID of the Vault cluster"
  value       = hcp_vault_cluster.main.cluster_id
}

output "vault_public_endpoint_url" {
  description = "Public endpoint URL for Vault cluster"
  value       = hcp_vault_cluster.main.vault_public_endpoint_url
}

output "vault_private_endpoint_url" {
  description = "Private endpoint URL for Vault cluster"
  value       = hcp_vault_cluster.main.vault_private_endpoint_url
}

output "vault_admin_token" {
  description = "Admin token for Vault cluster (sensitive)"
  value       = hcp_vault_cluster_admin_token.admin_token.token
  sensitive   = true
}

output "vault_namespace" {
  description = "Default namespace for Vault cluster"
  value       = hcp_vault_cluster.main.namespace
}

# HVN Information
output "hvn_id" {
  description = "ID of the HashiCorp Virtual Network"
  value       = hcp_hvn.vault_hvn.hvn_id
}

output "hvn_cidr_block" {
  description = "CIDR block of the HashiCorp Virtual Network"
  value       = hcp_hvn.vault_hvn.cidr_block
}

output "hvn_region" {
  description = "Azure region of the HashiCorp Virtual Network"
  value       = hcp_hvn.vault_hvn.region
}

output "hvn_self_link" {
  description = "Self link of the HashiCorp Virtual Network"
  value       = hcp_hvn.vault_hvn.self_link
}

# Azure Peering Information (if enabled)
output "azure_peering_connection_id" {
  description = "ID of the Azure VNet peering connection"
  value       = var.enable_vnet_peering ? hcp_azure_peering_connection.vault_peering[0].peering_id : null
}

output "azure_peering_status" {
  description = "Status of the Azure VNet peering connection"
  value       = var.enable_vnet_peering ? hcp_azure_peering_connection.vault_peering[0].state : null
}

# Network Security Group Information (if created)
output "vault_client_nsg_id" {
  description = "ID of the network security group for Vault client access"
  value       = var.enable_vnet_peering ? azurerm_network_security_group.vault_client[0].id : null
}

output "vault_client_nsg_name" {
  description = "Name of the network security group for Vault client access"
  value       = var.enable_vnet_peering ? azurerm_network_security_group.vault_client[0].name : null
}

# Azure Resource Group Information (if created)
output "azure_resource_group_name" {
  description = "Name of the Azure resource group created for networking"
  value       = var.enable_vnet_peering ? azurerm_resource_group.vault_networking[0].name : null
}

output "azure_resource_group_location" {
  description = "Location of the Azure resource group created for networking"
  value       = var.enable_vnet_peering ? azurerm_resource_group.vault_networking[0].location : null
}

# Current Azure Configuration
output "current_azure_subscription_id" {
  description = "Current Azure subscription ID"
  value       = data.azurerm_client_config.current.subscription_id
}

output "current_azure_tenant_id" {
  description = "Current Azure tenant ID"
  value       = data.azurerm_client_config.current.tenant_id
}

# Connection Information for Applications
output "vault_connection_info" {
  description = "Connection information for applications"
  value = {
    vault_url       = hcp_vault_cluster.main.vault_public_endpoint_url
    vault_namespace = hcp_vault_cluster.main.namespace
    hvn_cidr       = hcp_hvn.vault_hvn.cidr_block
    azure_region   = var.azure_region
  }
}

# Environment Information
output "deployment_environment" {
  description = "Deployment environment"
  value = {
    environment    = var.environment
    cluster_tier   = var.vault_tier
    azure_region   = var.azure_region
    public_endpoint = var.public_endpoint_enabled
    vnet_peering   = var.enable_vnet_peering
  }
}

# HCP Organization SSO Outputs
output "hcp_sso_enabled" {
  description = "Whether HCP SSO is enabled"
  value       = var.enable_hcp_sso
}

output "hcp_sso_application_id" {
  description = "Azure AD Application ID for HCP SSO"
  value       = var.enable_hcp_sso ? module.azure_ad_hcp_sso[0].application_id : null
}

output "hcp_sso_tenant_id" {
  description = "Azure AD Tenant ID"
  value       = var.enable_hcp_sso ? module.azure_ad_hcp_sso[0].tenant_id : null
}

output "hcp_sso_issuer_url" {
  description = "OIDC Issuer URL for HCP SSO"
  value       = var.enable_hcp_sso ? module.azure_ad_hcp_sso[0].oidc_issuer_url : null
}

output "hcp_sso_test_url" {
  description = "URL to test HCP SSO login"
  value       = var.enable_hcp_sso ? module.azure_ad_hcp_sso[0].sso_test_url : null
}

output "hcp_sso_setup_command" {
  description = "Command to complete HCP SSO configuration"
  value       = var.enable_hcp_sso ? module.azure_ad_hcp_sso[0].hcp_sso_setup_command : null
  sensitive   = true
}

output "hcp_sso_created_groups" {
  description = "Azure AD groups created for HCP access"
  value       = var.enable_hcp_sso ? module.azure_ad_hcp_sso[0].created_groups : {}
}

output "hcp_sso_azure_portal_urls" {
  description = "Azure Portal URLs for managing HCP SSO"
  value       = var.enable_hcp_sso ? module.azure_ad_hcp_sso[0].azure_portal_urls : {}
}

# HCP Terraform Integration Outputs
output "hcp_terraform_enabled" {
  description = "Whether HCP Terraform integration is enabled"
  value       = var.enable_hcp_terraform
}

output "hcp_terraform_workspace_id" {
  description = "ID of the created HCP Terraform workspace"
  value       = var.enable_hcp_terraform ? tfe_workspace.azure_infrastructure[0].id : null
}

output "hcp_terraform_workspace_name" {
  description = "Name of the created HCP Terraform workspace"
  value       = var.enable_hcp_terraform ? tfe_workspace.azure_infrastructure[0].name : null
}

output "hcp_terraform_workspace_url" {
  description = "URL to access the HCP Terraform workspace"
  value       = var.enable_hcp_terraform ? "https://app.terraform.io/app/${var.hcp_terraform_organization}/workspaces/${tfe_workspace.azure_infrastructure[0].name}" : null
}

output "vault_jwt_auth_path" {
  description = "Vault JWT authentication path for HCP Terraform"
  value       = var.enable_hcp_terraform ? vault_jwt_auth_backend.hcp_terraform[0].path : null
}

output "vault_jwt_auth_role" {
  description = "Vault JWT authentication role for HCP Terraform"
  value       = var.enable_hcp_terraform ? vault_jwt_auth_backend_role.hcp_terraform[0].role_name : null
}

output "vault_azure_role_name" {
  description = "Vault Azure role name for HCP Terraform dynamic credentials"
  value       = var.enable_hcp_terraform ? var.vault_azure_role_name : null
}

output "vault_policy_name" {
  description = "Vault policy name for HCP Terraform access"
  value       = var.enable_hcp_terraform ? vault_policy.hcp_terraform_azure[0].name : null
}

# HCP Terraform Configuration Summary
output "hcp_terraform_configuration" {
  description = "Complete HCP Terraform configuration summary"
  value = var.enable_hcp_terraform ? {
    organization       = var.hcp_terraform_organization
    workspace_name     = tfe_workspace.azure_infrastructure[0].name
    workspace_id       = tfe_workspace.azure_infrastructure[0].id
    workspace_url      = "https://app.terraform.io/app/${var.hcp_terraform_organization}/workspaces/${tfe_workspace.azure_infrastructure[0].name}"
    vault_auth_path    = vault_jwt_auth_backend.hcp_terraform[0].path
    vault_auth_role    = vault_jwt_auth_backend_role.hcp_terraform[0].role_name
    vault_policy       = vault_policy.hcp_terraform_azure[0].name
    azure_role_name    = var.vault_azure_role_name
    auto_apply_enabled = var.hcp_terraform_auto_apply
    terraform_version  = var.hcp_terraform_version
  } : null
}

# Dynamic Credentials Setup Instructions
output "hcp_terraform_setup_instructions" {
  description = "Instructions for using dynamic Azure credentials in HCP Terraform"
  value = var.enable_hcp_terraform ? {
    vault_configuration = {
      vault_addr      = hcp_vault_cluster.main.vault_public_endpoint_url
      vault_namespace = hcp_vault_cluster.main.namespace
      auth_path       = vault_jwt_auth_backend.hcp_terraform[0].path
      auth_role       = vault_jwt_auth_backend_role.hcp_terraform[0].role_name
      azure_role      = var.vault_azure_role_name
    }
    terraform_configuration = {
      provider_config = <<-EOT
      terraform {
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
      
      # Configure Vault provider
      provider "vault" {
        address   = "${hcp_vault_cluster.main.vault_public_endpoint_url}"
        namespace = "${hcp_vault_cluster.main.namespace}"
        
        auth_login_jwt {
          role = "${vault_jwt_auth_backend_role.hcp_terraform[0].role_name}"
          mount = "${vault_jwt_auth_backend.hcp_terraform[0].path}"
        }
      }
      
      # Get dynamic Azure credentials from Vault
      data "vault_generic_secret" "azure_creds" {
        path = "azure/creds/${var.vault_azure_role_name}"
      }
      
      # Configure Azure provider with dynamic credentials
      provider "azurerm" {
        features {}
        
        subscription_id = "${var.azure_subscription_id}"
        tenant_id       = "${var.azure_tenant_id}"
        client_id       = data.vault_generic_secret.azure_creds.data["client_id"]
        client_secret   = data.vault_generic_secret.azure_creds.data["client_secret"]
      }
      EOT
    }
    workspace_variables = {
      VAULT_ADDR      = hcp_vault_cluster.main.vault_public_endpoint_url
      VAULT_NAMESPACE = hcp_vault_cluster.main.namespace
      ARM_SUBSCRIPTION_ID = var.azure_subscription_id
      ARM_TENANT_ID      = var.azure_tenant_id
      VAULT_AZURE_ROLE   = var.vault_azure_role_name
    }
  } : null
  sensitive = true
}