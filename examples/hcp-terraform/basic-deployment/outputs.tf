# Outputs for HCP Terraform with Vault Dynamic Azure Credentials

# Resource Information
output "resource_group_name" {
  description = "Name of the created resource group"
  value       = azurerm_resource_group.main.name
}

output "resource_group_id" {
  description = "ID of the created resource group"
  value       = azurerm_resource_group.main.id
}

output "resource_group_location" {
  description = "Location of the created resource group"
  value       = azurerm_resource_group.main.location
}

# Storage Account Information
output "storage_account_name" {
  description = "Name of the created storage account"
  value       = azurerm_storage_account.main.name
}

output "storage_account_id" {
  description = "ID of the created storage account"
  value       = azurerm_storage_account.main.id
}

output "storage_account_primary_endpoint" {
  description = "Primary blob endpoint of the storage account"
  value       = azurerm_storage_account.main.primary_blob_endpoint
}

output "storage_account_primary_access_key" {
  description = "Primary access key for the storage account"
  value       = azurerm_storage_account.main.primary_access_key
  sensitive   = true
}

output "storage_container_name" {
  description = "Name of the created storage container"
  value       = azurerm_storage_container.main.name
}

# Key Vault Information (if created)
output "key_vault_name" {
  description = "Name of the created Key Vault"
  value       = var.create_key_vault ? azurerm_key_vault.main[0].name : null
}

output "key_vault_id" {
  description = "ID of the created Key Vault"
  value       = var.create_key_vault ? azurerm_key_vault.main[0].id : null
}

output "key_vault_uri" {
  description = "URI of the created Key Vault"
  value       = var.create_key_vault ? azurerm_key_vault.main[0].vault_uri : null
}

# Vault Credential Information
output "vault_credentials_info" {
  description = "Information about Vault credentials used (sensitive)"
  value = {
    client_id       = data.vault_generic_secret.azure_creds.data["client_id"]
    lease_id        = data.vault_generic_secret.azure_creds.lease_id
    lease_duration  = data.vault_generic_secret.azure_creds.lease_duration
    lease_renewable = data.vault_generic_secret.azure_creds.lease_renewable
    vault_role      = var.vault_azure_role
  }
  sensitive = true
}

# Deployment Information
output "deployment_info" {
  description = "Information about the deployment"
  value = {
    environment         = var.environment
    project_name        = var.project_name
    team_name          = var.team_name
    azure_region       = var.azure_region
    managed_by         = "HCP-Terraform"
    credential_source  = "Vault-Dynamic"
    deployment_time    = timestamp()
  }
}

# Resource URLs and Connection Strings
output "resource_urls" {
  description = "URLs for accessing deployed resources"
  value = {
    storage_account_url = "https://portal.azure.com/#@${var.azure_tenant_id}/resource${azurerm_storage_account.main.id}"
    resource_group_url  = "https://portal.azure.com/#@${var.azure_tenant_id}/resource${azurerm_resource_group.main.id}"
    key_vault_url      = var.create_key_vault ? "https://portal.azure.com/#@${var.azure_tenant_id}/resource${azurerm_key_vault.main[0].id}" : null
  }
}

# Connection Information for Applications
output "connection_info" {
  description = "Connection information for applications"
  value = {
    storage_account_name = azurerm_storage_account.main.name
    storage_container    = azurerm_storage_container.main.name
    blob_endpoint       = azurerm_storage_account.main.primary_blob_endpoint
    key_vault_uri       = var.create_key_vault ? azurerm_key_vault.main[0].vault_uri : null
  }
}

# Security Information
output "security_info" {
  description = "Security configuration information"
  value = {
    storage_https_only           = azurerm_storage_account.main.enable_https_traffic_only
    storage_min_tls_version     = azurerm_storage_account.main.min_tls_version
    storage_public_access       = azurerm_storage_account.main.allow_nested_items_to_be_public
    key_vault_created          = var.create_key_vault
    private_endpoints_enabled  = var.enable_private_endpoints
  }
}

# Cost Estimation Information
output "cost_estimation" {
  description = "Cost estimation information"
  value = {
    storage_tier          = var.storage_account_tier
    storage_replication   = var.storage_replication_type
    azure_region         = var.azure_region
    estimated_monthly_cost = "Contact Azure Cost Management for detailed estimates"
    cost_optimization_tips = [
      "Consider lifecycle management policies for blob storage",
      "Use appropriate storage tier based on access patterns",
      "Monitor and optimize data transfer costs",
      "Implement proper retention policies"
    ]
  }
}

# Monitoring and Management
output "management_info" {
  description = "Management and monitoring information"
  value = {
    resource_group_tags = azurerm_resource_group.main.tags
    monitoring_enabled  = var.enable_monitoring
    threat_protection   = var.enable_advanced_threat_protection
    backup_configured   = "Configure Azure Backup as needed"
    disaster_recovery   = "Configure geo-replication based on requirements"
  }
}

# Next Steps and Recommendations
output "next_steps" {
  description = "Recommended next steps"
  value = [
    "Configure Azure Monitor and Log Analytics if needed",
    "Set up backup policies for critical data",
    "Implement proper RBAC for resource access",
    "Configure network security groups if required",
    "Review and optimize resource costs",
    "Set up alerting for resource health and performance",
    "Implement proper lifecycle management for storage",
    "Configure disaster recovery as needed"
  ]
}