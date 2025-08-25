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