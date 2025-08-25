# Variables for HashiCorp Vault Cloud Terraform configuration

# HCP Configuration
variable "hcp_client_id" {
  description = "HCP client ID for authentication"
  type        = string
  sensitive   = true
}

variable "hcp_client_secret" {
  description = "HCP client secret for authentication"
  type        = string
  sensitive   = true
}

# Azure Configuration
variable "azure_subscription_id" {
  description = "Azure subscription ID"
  type        = string
}

variable "azure_tenant_id" {
  description = "Azure tenant ID"
  type        = string
}

variable "azure_region" {
  description = "Azure region for resources"
  type        = string
  default     = "East US"
}

# HVN Configuration
variable "hvn_id" {
  description = "HashiCorp Virtual Network ID"
  type        = string
  default     = "vault-hvn"
}

variable "hvn_cidr_block" {
  description = "CIDR block for HashiCorp Virtual Network"
  type        = string
  default     = "172.25.16.0/20"
}

# Vault Cluster Configuration
variable "vault_cluster_id" {
  description = "Vault cluster identifier"
  type        = string
  default     = "vault-production"
}

variable "vault_tier" {
  description = "Vault cluster tier (dev, starter_small, standard_small, standard_medium, standard_large, plus_small, plus_medium, plus_large)"
  type        = string
  default     = "standard_small"
  
  validation {
    condition = contains([
      "dev",
      "starter_small",
      "standard_small",
      "standard_medium", 
      "standard_large",
      "plus_small",
      "plus_medium",
      "plus_large"
    ], var.vault_tier)
    error_message = "Vault tier must be one of: dev, starter_small, standard_small, standard_medium, standard_large, plus_small, plus_medium, plus_large."
  }
}

variable "public_endpoint_enabled" {
  description = "Enable public endpoint for Vault cluster"
  type        = bool
  default     = true
}

# IP Allowlist Configuration
variable "ip_allowlist" {
  description = "List of IP CIDR blocks allowed to access Vault public endpoint"
  type = list(object({
    cidr        = string
    description = string
  }))
  default = []
}

# VNet Peering Configuration
variable "enable_vnet_peering" {
  description = "Enable VNet peering between HVN and Azure VNet"
  type        = bool
  default     = false
}

variable "vnet_name" {
  description = "Azure VNet name for peering (required if enable_vnet_peering is true)"
  type        = string
  default     = ""
}

variable "vnet_resource_group_name" {
  description = "Azure resource group name containing the VNet"
  type        = string
  default     = ""
}

variable "vnet_cidr_block" {
  description = "CIDR block of the Azure VNet for routing"
  type        = string
  default     = ""
}

# Monitoring Configuration
variable "datadog_api_key" {
  description = "Datadog API key for metrics and audit log export"
  type        = string
  default     = ""
  sensitive   = true
}

variable "datadog_region" {
  description = "Datadog region (US1, US3, US5, EU1, AP1, GOV)"
  type        = string
  default     = "US1"
  
  validation {
    condition     = contains(["US1", "US3", "US5", "EU1", "AP1", "GOV"], var.datadog_region)
    error_message = "Datadog region must be one of: US1, US3, US5, EU1, AP1, GOV."
  }
}

# General Configuration
variable "environment" {
  description = "Environment name (dev, staging, prod)"
  type        = string
  default     = "prod"
  
  validation {
    condition     = contains(["dev", "staging", "prod"], var.environment)
    error_message = "Environment must be one of: dev, staging, prod."
  }
}

variable "owner" {
  description = "Owner or team responsible for the resources"
  type        = string
  default     = "platform-engineering"
}

# Tags
variable "additional_tags" {
  description = "Additional tags to apply to all resources"
  type        = map(string)
  default     = {}
}