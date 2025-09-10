# Variables for Azure AD HCP Organization SSO Terraform Module

# Azure AD Application Configuration
variable "application_name" {
  description = "Name of the Azure AD application for HCP SSO"
  type        = string
  default     = "HashiCorp Cloud Platform"
}

variable "client_secret_rotation_years" {
  description = "Number of years before client secret rotation"
  type        = number
  default     = 2
  
  validation {
    condition     = var.client_secret_rotation_years >= 1 && var.client_secret_rotation_years <= 3
    error_message = "Client secret rotation must be between 1 and 3 years."
  }
}

variable "auto_grant_consent" {
  description = "Automatically grant admin consent for the application"
  type        = bool
  default     = false
}

variable "enable_group_claims" {
  description = "Enable group claims in the ID token"
  type        = bool
  default     = true
}

# HCP Organization Configuration
variable "hcp_organization_id" {
  description = "HCP Organization ID"
  type        = string
  default     = ""
}

variable "configure_hcp_sso" {
  description = "Configure HCP Organization SSO (requires HCP provider configuration)"
  type        = bool
  default     = false
}

variable "jit_provisioning" {
  description = "Enable Just-In-Time user provisioning"
  type        = bool
  default     = true
}

variable "enforce_sso" {
  description = "Enforce SSO for all organization users"
  type        = bool
  default     = false
}

# Group Management
variable "create_groups" {
  description = "Create Azure AD security groups for HCP access"
  type        = bool
  default     = true
}

variable "additional_groups" {
  description = "Additional Azure AD groups to create beyond the defaults"
  type = map(object({
    role     = string       # Admin, Contributor, or Viewer
    projects = list(string) # List of HCP projects or ["*"] for all
  }))
  default = {}
  
  validation {
    condition = alltrue([
      for group in var.additional_groups : 
      contains(["Admin", "Contributor", "Viewer"], group.role)
    ])
    error_message = "Group role must be one of: Admin, Contributor, Viewer."
  }
}

# Test Users (for validation and testing)
variable "create_test_users" {
  description = "Create test users for SSO validation"
  type        = bool
  default     = false
}

variable "test_users" {
  description = "Test users to create for SSO validation"
  type = map(object({
    display_name = string
    groups       = list(string)
  }))
  default = {
    "test-admin" = {
      display_name = "Test Admin User"
      groups       = ["HCP-Platform-Admins"]
    }
    "test-developer" = {
      display_name = "Test Developer User"
      groups       = ["HCP-Vault-Developers"]
    }
  }
}

# Conditional Access and Security
variable "conditional_access_policies" {
  description = "Conditional access policies to apply to the application"
  type = list(object({
    name                    = string
    state                   = string # enabled, disabled, enabledForReportingButNotEnforced
    require_mfa            = bool
    require_compliant_device = bool
    allowed_locations      = list(string)
    blocked_locations      = list(string)
  }))
  default = []
}

variable "session_controls" {
  description = "Session controls for the application"
  type = object({
    sign_in_frequency_enabled = bool
    sign_in_frequency_value   = number
    sign_in_frequency_type    = string # Days or Hours
  })
  default = {
    sign_in_frequency_enabled = false
    sign_in_frequency_value   = 8
    sign_in_frequency_type    = "Hours"
  }
}

# Application Permissions
variable "additional_api_permissions" {
  description = "Additional API permissions for the application"
  type = list(object({
    resource_app_id = string
    resource_access = list(object({
      id   = string
      type = string # Scope or Role
    }))
  }))
  default = []
}

# Token Configuration
variable "token_lifetime_policies" {
  description = "Token lifetime policies for the application"
  type = object({
    access_token_lifetime  = string # ISO 8601 duration format
    id_token_lifetime      = string # ISO 8601 duration format
    refresh_token_lifetime = string # ISO 8601 duration format
  })
  default = {
    access_token_lifetime  = "PT1H"    # 1 hour
    id_token_lifetime      = "PT1H"    # 1 hour
    refresh_token_lifetime = "P14D"    # 14 days
  }
}

# Monitoring and Auditing
variable "enable_audit_logs" {
  description = "Enable audit logging for the application"
  type        = bool
  default     = true
}

variable "log_analytics_workspace_id" {
  description = "Log Analytics workspace ID for audit logs"
  type        = string
  default     = ""
}

# Backup and Recovery
variable "backup_configuration" {
  description = "Configuration backup settings"
  type = object({
    enabled           = bool
    retention_days    = number
    storage_account   = string
    container_name    = string
  })
  default = {
    enabled           = false
    retention_days    = 90
    storage_account   = ""
    container_name    = "hcp-sso-backups"
  }
}

# Notification Settings
variable "notification_settings" {
  description = "Notification settings for SSO events"
  type = object({
    enabled                     = bool
    notify_on_config_changes    = bool
    notify_on_auth_failures     = bool
    notification_email          = string
    auth_failure_threshold      = number
  })
  default = {
    enabled                     = false
    notify_on_config_changes    = true
    notify_on_auth_failures     = true
    notification_email          = ""
    auth_failure_threshold      = 5
  }
}

# Environment and Tagging
variable "environment" {
  description = "Environment name (dev, staging, prod)"
  type        = string
  default     = "dev"
  
  validation {
    condition     = contains(["dev", "staging", "prod"], var.environment)
    error_message = "Environment must be one of: dev, staging, prod."
  }
}

variable "tags" {
  description = "Tags to apply to Azure resources"
  type        = map(string)
  default = {
    Project     = "vault-cloud-onboarding"
    Component   = "hcp-sso"
    ManagedBy   = "terraform"
  }
}

# Feature Flags
variable "feature_flags" {
  description = "Feature flags for enabling/disabling specific functionality"
  type = object({
    enable_risk_based_policies    = bool
    enable_session_management     = bool
    enable_certificate_auth       = bool
    enable_device_compliance      = bool
    enable_location_based_access  = bool
  })
  default = {
    enable_risk_based_policies    = false
    enable_session_management     = true
    enable_certificate_auth       = false
    enable_device_compliance      = false
    enable_location_based_access  = false
  }
}

# Advanced Configuration
variable "advanced_settings" {
  description = "Advanced configuration settings"
  type = object({
    token_version               = string # v1.0 or v2.0
    access_token_acceptance     = string # mappedClaims, requiredClaims
    saml_token_version          = string # 1.1 or 2.0
    include_externally_authenticated_upn = bool
    include_externally_authenticated_upn_without_hash = bool
  })
  default = {
    token_version               = "v2.0"
    access_token_acceptance     = "mappedClaims"
    saml_token_version          = "2.0"
    include_externally_authenticated_upn = false
    include_externally_authenticated_upn_without_hash = false
  }
}

# Deployment Configuration
variable "deployment_settings" {
  description = "Deployment-specific settings"
  type = object({
    create_in_stages           = bool
    validate_before_apply      = bool
    enable_rollback_capability = bool
    deployment_timeout_minutes = number
  })
  default = {
    create_in_stages           = true
    validate_before_apply      = true
    enable_rollback_capability = true
    deployment_timeout_minutes = 30
  }
}