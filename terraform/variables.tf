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

variable "hcp_organization_id" {
  description = "HCP Organization ID for SSO configuration"
  type        = string
  default     = ""
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

# HCP Organization SSO Configuration
variable "enable_hcp_sso" {
  description = "Enable Azure AD HCP Organization SSO setup"
  type        = bool
  default     = false
}

variable "hcp_sso_create_groups" {
  description = "Create Azure AD security groups for HCP access"
  type        = bool
  default     = true
}

variable "hcp_sso_enable_group_claims" {
  description = "Enable group claims in Azure AD ID tokens"
  type        = bool
  default     = true
}

variable "hcp_sso_jit_provisioning" {
  description = "Enable Just-In-Time user provisioning in HCP"
  type        = bool
  default     = true
}

variable "hcp_sso_enforce_sso" {
  description = "Enforce SSO for all HCP organization users"
  type        = bool
  default     = false
}

variable "hcp_sso_auto_grant_consent" {
  description = "Automatically grant admin consent for Azure AD application"
  type        = bool
  default     = false
}

variable "hcp_sso_create_test_users" {
  description = "Create test users for SSO validation (non-production only)"
  type        = bool
  default     = false
}

variable "hcp_sso_additional_groups" {
  description = "Additional Azure AD groups beyond defaults"
  type = map(object({
    role     = string
    projects = list(string)
  }))
  default = {}
}

variable "hcp_sso_test_users" {
  description = "Test users for SSO validation"
  type = map(object({
    display_name = string
    groups       = list(string)
  }))
  default = {
    "sso-test-admin" = {
      display_name = "SSO Test Administrator"
      groups       = ["HCP-Platform-Admins"]
    }
    "sso-test-user" = {
      display_name = "SSO Test User"
      groups       = ["HCP-Vault-Developers"]
    }
  }
}

variable "hcp_sso_token_lifetime_policies" {
  description = "Token lifetime policies for HCP SSO"
  type = object({
    access_token_lifetime  = string
    id_token_lifetime      = string
    refresh_token_lifetime = string
  })
  default = {
    access_token_lifetime  = "PT1H"   # 1 hour
    id_token_lifetime      = "PT1H"   # 1 hour
    refresh_token_lifetime = "P14D"   # 14 days
  }
}