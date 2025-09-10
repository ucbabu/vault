# Outputs for Azure AD HCP SSO Example

# Basic Setup Outputs
output "basic_sso_configuration" {
  description = "Basic SSO configuration details"
  value = {
    application_id    = module.azure_ad_hcp_sso_basic.application_id
    tenant_id        = module.azure_ad_hcp_sso_basic.tenant_id
    issuer_url       = module.azure_ad_hcp_sso_basic.oidc_issuer_url
    test_url         = module.azure_ad_hcp_sso_basic.sso_test_url
  }
}

output "basic_hcp_setup_command" {
  description = "Command to configure HCP SSO for basic setup"
  value       = module.azure_ad_hcp_sso_basic.hcp_sso_setup_command
  sensitive   = true
}

# Advanced Setup Outputs
output "advanced_sso_configuration" {
  description = "Advanced SSO configuration details"
  value = {
    application_id     = module.azure_ad_hcp_sso_advanced.application_id
    groups_created     = length(module.azure_ad_hcp_sso_advanced.created_groups)
    test_users_created = length(module.azure_ad_hcp_sso_advanced.test_users)
    group_mappings     = module.azure_ad_hcp_sso_advanced.hcp_group_mappings
  }
}

output "advanced_test_credentials" {
  description = "Test user credentials for advanced setup"
  value       = module.azure_ad_hcp_sso_advanced.test_user_credentials
  sensitive   = true
}

# Development Setup Outputs
output "dev_sso_configuration" {
  description = "Development SSO configuration details"
  value = {
    application_id = module.azure_ad_hcp_sso_dev.application_id
    test_url       = module.azure_ad_hcp_sso_dev.sso_test_url
  }
}

# Azure Portal URLs for Management
output "azure_portal_urls" {
  description = "Azure Portal URLs for managing applications"
  value = {
    basic_app    = module.azure_ad_hcp_sso_basic.azure_portal_urls
    advanced_app = module.azure_ad_hcp_sso_advanced.azure_portal_urls
    dev_app      = module.azure_ad_hcp_sso_dev.azure_portal_urls
  }
}

# Security Recommendations
output "security_recommendations" {
  description = "Security recommendations for all environments"
  value = {
    production = module.azure_ad_hcp_sso_advanced.security_recommendations
    basic      = module.azure_ad_hcp_sso_basic.security_recommendations
  }
}

# Troubleshooting Information
output "troubleshooting_info" {
  description = "Troubleshooting information for all setups"
  value = {
    basic    = module.azure_ad_hcp_sso_basic.troubleshooting_info
    advanced = module.azure_ad_hcp_sso_advanced.troubleshooting_info
    dev      = module.azure_ad_hcp_sso_dev.troubleshooting_info
  }
}