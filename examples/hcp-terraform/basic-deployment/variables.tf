# Variables for HCP Terraform with Vault Dynamic Azure Credentials

# Vault Configuration
variable "vault_addr" {
  description = "Vault server address"
  type        = string
  # Set via HCP Terraform workspace environment variable: VAULT_ADDR
}

variable "vault_namespace" {
  description = "Vault namespace"
  type        = string
  default     = "admin"
  # Set via HCP Terraform workspace environment variable: VAULT_NAMESPACE
}

variable "vault_azure_role" {
  description = "Vault Azure role name for dynamic credentials"
  type        = string
  default     = "hcp-terraform"
  # Set via HCP Terraform workspace environment variable: VAULT_AZURE_ROLE
}

# Azure Configuration
variable "azure_subscription_id" {
  description = "Azure subscription ID"
  type        = string
  # Set via HCP Terraform workspace environment variable: ARM_SUBSCRIPTION_ID
}

variable "azure_tenant_id" {
  description = "Azure tenant ID"
  type        = string
  # Set via HCP Terraform workspace environment variable: ARM_TENANT_ID
}

variable "azure_region" {
  description = "Azure region for resource deployment"
  type        = string
  default     = "East US"
  
  validation {
    condition = contains([
      "East US", "East US 2", "West US", "West US 2", "West US 3",
      "Central US", "North Central US", "South Central US",
      "West Central US", "Canada Central", "Canada East",
      "North Europe", "West Europe", "UK South", "UK West",
      "France Central", "Germany West Central", "Switzerland North",
      "Norway East", "Sweden Central"
    ], var.azure_region)
    error_message = "Azure region must be a valid Azure region."
  }
}

# Project Configuration
variable "project_name" {
  description = "Project name for resource naming (lowercase, no spaces)"
  type        = string
  default     = "vaultdemo"
  
  validation {
    condition     = can(regex("^[a-z0-9]+$", var.project_name))
    error_message = "Project name must contain only lowercase letters and numbers."
  }
}

variable "environment" {
  description = "Environment name (dev, staging, prod)"
  type        = string
  default     = "dev"
  
  validation {
    condition     = contains(["dev", "staging", "prod"], var.environment)
    error_message = "Environment must be one of: dev, staging, prod."
  }
}

variable "team_name" {
  description = "Team or owner name for resource tagging"
  type        = string
  default     = "platform-engineering"
}

# Storage Account Configuration
variable "storage_account_tier" {
  description = "Storage account tier (Standard or Premium)"
  type        = string
  default     = "Standard"
  
  validation {
    condition     = contains(["Standard", "Premium"], var.storage_account_tier)
    error_message = "Storage account tier must be either Standard or Premium."
  }
}

variable "storage_replication_type" {
  description = "Storage account replication type"
  type        = string
  default     = "LRS"
  
  validation {
    condition = contains([
      "LRS", "GRS", "RAGRS", "ZRS", "GZRS", "RAGZRS"
    ], var.storage_replication_type)
    error_message = "Storage replication type must be one of: LRS, GRS, RAGRS, ZRS, GZRS, RAGZRS."
  }
}

# Optional Components
variable "create_key_vault" {
  description = "Whether to create an Azure Key Vault"
  type        = bool
  default     = false
}

# Resource Naming Configuration
variable "resource_name_prefix" {
  description = "Prefix for all resource names"
  type        = string
  default     = ""
}

variable "resource_name_suffix" {
  description = "Suffix for all resource names"
  type        = string
  default     = ""
}

# Tags Configuration
variable "additional_tags" {
  description = "Additional tags to apply to all resources"
  type        = map(string)
  default     = {}
}

# Network Configuration (for future expansion)
variable "enable_private_endpoints" {
  description = "Enable private endpoints for Azure services"
  type        = bool
  default     = false
}

variable "allowed_ip_ranges" {
  description = "IP ranges allowed to access Azure services"
  type        = list(string)
  default     = []
}

# Monitoring Configuration
variable "enable_monitoring" {
  description = "Enable Azure Monitor and Log Analytics"
  type        = bool
  default     = false
}

# Security Configuration
variable "enable_advanced_threat_protection" {
  description = "Enable Advanced Threat Protection for storage account"
  type        = bool
  default     = false
}

variable "enable_https_traffic_only" {
  description = "Force HTTPS traffic only for storage account"
  type        = bool
  default     = true
}