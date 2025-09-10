# Outputs for Azure AD HCP Organization SSO Terraform Module

# Azure AD Application Information
output "application_id" {
  description = "Azure AD Application (Client) ID"
  value       = azuread_application.hcp_sso.application_id
}

output "application_object_id" {
  description = "Azure AD Application Object ID"
  value       = azuread_application.hcp_sso.object_id
}

output "application_name" {
  description = "Azure AD Application Display Name"
  value       = azuread_application.hcp_sso.display_name
}

output "client_secret" {
  description = "Azure AD Application Client Secret"
  value       = azuread_application_password.hcp_sso.value
  sensitive   = true
}

output "client_secret_id" {
  description = "Azure AD Application Client Secret ID"
  value       = azuread_application_password.hcp_sso.key_id
}

output "client_secret_expiry" {
  description = "Azure AD Application Client Secret Expiry Date"
  value       = azuread_application_password.hcp_sso.end_date
}

# Service Principal Information
output "service_principal_id" {
  description = "Azure AD Service Principal Object ID"
  value       = azuread_service_principal.hcp_sso.object_id
}

output "service_principal_app_id" {
  description = "Azure AD Service Principal Application ID"
  value       = azuread_service_principal.hcp_sso.application_id
}

# OIDC Configuration
output "oidc_issuer_url" {
  description = "OIDC Issuer URL for HCP SSO configuration"
  value       = local.issuer_url
}

output "oidc_discovery_url" {
  description = "OIDC Discovery URL"
  value       = "${local.issuer_url}/.well-known/openid_configuration"
}

output "redirect_uri" {
  description = "Configured redirect URI"
  value       = local.redirect_uri
}

output "logout_url" {
  description = "Configured logout URL"
  value       = local.logout_url
}

# Tenant Information
output "tenant_id" {
  description = "Azure AD Tenant ID"
  value       = data.azuread_client_config.current.tenant_id
}

output "primary_domain" {
  description = "Primary verified domain for the tenant"
  value       = local.primary_domain
}

output "all_domains" {
  description = "All verified domains in the tenant"
  value       = [for domain in data.azuread_domains.tenant_domains.domains : domain.domain_name if domain.is_verified]
}

# Azure AD Groups
output "created_groups" {
  description = "Azure AD groups created for HCP access"
  value = var.create_groups ? {
    for group_name, group in azuread_group.hcp_groups : group_name => {
      object_id    = group.object_id
      display_name = group.display_name
      description  = group.description
      role         = local.all_groups[group_name].role
      projects     = local.all_groups[group_name].projects
    }
  } : {}
}

output "group_object_ids" {
  description = "Object IDs of created Azure AD groups"
  value = var.create_groups ? {
    for group_name, group in azuread_group.hcp_groups : group_name => group.object_id
  } : {}
}

# Group Mappings for HCP Configuration
output "hcp_group_mappings" {
  description = "Group mappings formatted for HCP SSO configuration"
  value = var.create_groups ? [
    for group_name, config in local.all_groups : {
      azure_group_name = group_name
      azure_group_id   = azuread_group.hcp_groups[group_name].object_id
      hcp_role         = config.role
      hcp_projects     = config.projects
      mapping_string   = "${group_name}:${config.role}:${join(",", config.projects)}"
    }
  ] : []
}

# Test Users (if created)
output "test_users" {
  description = "Test users created for SSO validation"
  value = var.create_test_users ? {
    for user_name, user in azuread_user.test_users : user_name => {
      object_id           = user.object_id
      user_principal_name = user.user_principal_name
      display_name        = user.display_name
      groups              = var.test_users[user_name].groups
    }
  } : {}
  sensitive = true
}

output "test_user_credentials" {
  description = "Test user credentials (for initial setup only)"
  value = var.create_test_users ? {
    password = random_password.test_user_password[0].result
    users    = [for user_name, user in azuread_user.test_users : user.user_principal_name]
  } : null
  sensitive = true
}

# HCP SSO Configuration Commands
output "hcp_sso_setup_command" {
  description = "Command to configure HCP Organization SSO using the automation script"
  value = <<-EOT
./scripts/hcp-org-sso-setup.sh oidc \
  --name "Azure AD" \
  --org-id "${var.hcp_organization_id}" \
  --oidc-issuer "${local.issuer_url}" \
  --oidc-client-id "${azuread_application.hcp_sso.application_id}" \
  --oidc-secret "${azuread_application_password.hcp_sso.value}" \
  ${join(" \\\n  ", [for mapping in (var.create_groups ? [
    for group_name, config in local.all_groups : 
    "--group-mapping \"${group_name}:${config.role}:${join(",", config.projects)}\""
  ] : [])]) } \
  --jit-provisioning
EOT
  sensitive = true
}

output "hcp_sso_configuration" {
  description = "HCP SSO configuration in JSON format"
  value = {
    provider_type    = "oidc"
    provider_name    = "Azure AD"
    issuer_url      = local.issuer_url
    client_id       = azuread_application.hcp_sso.application_id
    client_secret   = azuread_application_password.hcp_sso.value
    scopes          = ["openid", "profile", "email", "groups"]
    claim_mappings = {
      user_id = "sub"
      email   = "email"
      name    = "name"
      groups  = "groups"
    }
    jit_provisioning = var.jit_provisioning
    enforce_sso     = var.enforce_sso
  }
  sensitive = true
}

# URLs and Endpoints
output "sso_test_url" {
  description = "URL to test SSO login (replace {org-id} with actual HCP organization ID)"
  value       = "https://portal.cloud.hashicorp.com/sign-in/sso?organization_id=${var.hcp_organization_id != "" ? var.hcp_organization_id : "{org-id}"}"
}

output "azure_portal_urls" {
  description = "Useful Azure Portal URLs for managing the application"
  value = {
    application_overview = "https://portal.azure.com/#view/Microsoft_AAD_RegisteredApps/ApplicationMenuBlade/~/Overview/appId/${azuread_application.hcp_sso.application_id}"
    enterprise_app      = "https://portal.azure.com/#view/Microsoft_AAD_IAM/StartboardApplicationsMenuBlade/~/AppAppsPreview"
    groups_management   = "https://portal.azure.com/#view/Microsoft_AAD_IAM/GroupsManagementMenuBlade/~/AllGroups"
    conditional_access  = "https://portal.azure.com/#view/Microsoft_AAD_IAM/ConditionalAccessBlade/~/Policies"
  }
}

# Configuration Validation
output "configuration_summary" {
  description = "Summary of the SSO configuration"
  value = {
    application_configured  = true
    groups_created         = var.create_groups ? length(local.all_groups) : 0
    test_users_created     = var.create_test_users ? length(var.test_users) : 0
    group_claims_enabled   = var.enable_group_claims
    auto_consent_granted   = var.auto_grant_consent
    hcp_sso_configured     = var.configure_hcp_sso
    environment           = var.environment
  }
}

# Security and Compliance
output "security_recommendations" {
  description = "Security recommendations for the SSO setup"
  value = [
    "Enable conditional access policies for enhanced security",
    "Configure MFA requirements for admin groups",
    "Regularly review and audit group memberships",
    "Monitor sign-in logs for suspicious activity",
    "Set up alerts for authentication failures",
    var.auto_grant_consent ? "Review and validate granted permissions" : "Grant admin consent for the application",
    "Consider enabling device compliance requirements",
    "Implement session controls and sign-in frequency policies"
  ]
}

# Backup and Recovery Information
output "backup_information" {
  description = "Information for backup and recovery procedures"
  value = {
    application_id     = azuread_application.hcp_sso.application_id
    tenant_id         = data.azuread_client_config.current.tenant_id
    configuration_date = timestamp()
    secret_expiry     = azuread_application_password.hcp_sso.end_date
    groups_created    = var.create_groups ? keys(local.all_groups) : []
    module_version    = "1.0.0"
  }
}

# Troubleshooting Information
output "troubleshooting_info" {
  description = "Information for troubleshooting SSO issues"
  value = {
    oidc_endpoints = {
      discovery    = "${local.issuer_url}/.well-known/openid_configuration"
      authorization = "https://login.microsoftonline.com/${data.azuread_client_config.current.tenant_id}/oauth2/v2.0/authorize"
      token        = "https://login.microsoftonline.com/${data.azuread_client_config.current.tenant_id}/oauth2/v2.0/token"
      userinfo     = "https://graph.microsoft.com/oidc/userinfo"
    }
    test_commands = [
      "curl -s '${local.issuer_url}/.well-known/openid_configuration' | jq .",
      "az ad app show --id ${azuread_application.hcp_sso.application_id}",
      "az ad signed-in-user get-member-groups --query 'value[].displayName'"
    ]
  }
}