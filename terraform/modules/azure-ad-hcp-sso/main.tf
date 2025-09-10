# Azure AD HCP Organization SSO Terraform Module
# This module configures Azure AD application and HCP Organization SSO integration

terraform {
  required_version = ">= 1.0"
  required_providers {
    azuread = {
      source  = "hashicorp/azuread"
      version = "~> 2.47"
    }
    hcp = {
      source  = "hashicorp/hcp"
      version = "~> 0.78"
    }
    random = {
      source  = "hashicorp/random"
      version = "~> 3.5"
    }
    time = {
      source  = "hashicorp/time"
      version = "~> 0.9"
    }
  }
}

# Data sources
data "azuread_client_config" "current" {}
data "azuread_domains" "tenant_domains" {}

# Get the primary verified domain
locals {
  primary_domain = [
    for domain in data.azuread_domains.tenant_domains.domains :
    domain.domain_name if domain.is_default
  ][0]
  
  # OIDC configuration
  issuer_url = "https://login.microsoftonline.com/${data.azuread_client_config.current.tenant_id}/v2.0"
  redirect_uri = "https://auth.hashicorp.com/login/callback"
  logout_url = "https://auth.hashicorp.com/logout"
  
  # Group mappings with default values
  default_group_mappings = {
    "HCP-Platform-Admins"  = { role = "Admin", projects = ["*"] }
    "HCP-Vault-Admins"     = { role = "Admin", projects = ["vault-production", "vault-staging"] }
    "HCP-Vault-Operators"  = { role = "Contributor", projects = ["vault-production", "vault-staging"] }
    "HCP-Vault-Developers" = { role = "Contributor", projects = ["vault-development", "vault-staging"] }
    "HCP-Security-Team"    = { role = "Viewer", projects = ["*"] }
  }
  
  # Merge user-defined groups with defaults
  all_groups = merge(local.default_group_mappings, var.additional_groups)
}

# Create Azure AD Application
resource "azuread_application" "hcp_sso" {
  display_name     = var.application_name
  sign_in_audience = "AzureADMyOrg"
  owners           = [data.azuread_client_config.current.object_id]

  # Configure redirect URIs
  web {
    redirect_uris = [local.redirect_uri]
    logout_url    = local.logout_url
    
    implicit_grant {
      id_token_issuance_enabled = true
    }
  }

  # Configure API permissions
  required_resource_access {
    resource_app_id = "00000003-0000-0000-c000-000000000000" # Microsoft Graph

    resource_access {
      id   = "e1fe6dd8-ba31-4d61-89e7-88639da4683d" # User.Read
      type = "Scope"
    }

    dynamic "resource_access" {
      for_each = var.enable_group_claims ? [1] : []
      content {
        id   = "7427e0e9-2fba-42fe-b0c0-848c9e6a8182" # offline_access
        type = "Scope"
      }
    }
  }

  # Configure optional claims for groups and email
  optional_claims {
    id_token {
      name      = "email"
      source    = "user"
      essential = true
    }

    dynamic "id_token" {
      for_each = var.enable_group_claims ? [1] : []
      content {
        name                  = "groups"
        source                = "user"
        essential             = false
        additional_properties = ["emit_as_roles"]
      }
    }
  }

  tags = var.tags
}

# Create service principal for the application
resource "azuread_service_principal" "hcp_sso" {
  application_id               = azuread_application.hcp_sso.application_id
  app_role_assignment_required = false
  owners                       = [data.azuread_client_config.current.object_id]

  tags = var.tags
}

# Generate client secret
resource "time_rotating" "secret_rotation" {
  rotation_years = var.client_secret_rotation_years
}

resource "azuread_application_password" "hcp_sso" {
  application_object_id = azuread_application.hcp_sso.object_id
  display_name          = "HCP SSO Secret"
  
  rotate_when_changed = {
    rotation = time_rotating.secret_rotation.id
  }
}

# Grant admin consent for the application
resource "azuread_service_principal_delegated_permission_grant" "hcp_sso" {
  count = var.auto_grant_consent ? 1 : 0

  service_principal_object_id          = azuread_service_principal.hcp_sso.object_id
  resource_service_principal_object_id = data.azuread_service_principal.microsoft_graph.object_id
  claim_values                         = ["User.Read"]
}

# Microsoft Graph service principal
data "azuread_service_principal" "microsoft_graph" {
  application_id = "00000003-0000-0000-c000-000000000000"
}

# Create Azure AD security groups
resource "azuread_group" "hcp_groups" {
  for_each = var.create_groups ? local.all_groups : {}

  display_name     = each.key
  description      = "HCP ${each.value.role} access for projects: ${join(", ", each.value.projects)}"
  security_enabled = true
  mail_enabled     = false
  owners           = [data.azuread_client_config.current.object_id]

  lifecycle {
    ignore_changes = [members]
  }
}

# Configure HCP Organization SSO (if HCP provider is configured)
resource "hcp_organization_iam_policy" "sso_policy" {
  count = var.configure_hcp_sso ? 1 : 0

  # Note: This is a placeholder - actual HCP SSO configuration may require
  # different resources depending on HCP provider capabilities
  
  # For now, we'll output the configuration that needs to be applied manually
  # or through HCP CLI/API
}

# Random password for demonstration/testing
resource "random_password" "test_user_password" {
  count   = var.create_test_users ? 1 : 0
  length  = 16
  special = true
}

# Test users (optional, for validation)
resource "azuread_user" "test_users" {
  for_each = var.create_test_users ? var.test_users : {}

  user_principal_name = "${each.key}@${local.primary_domain}"
  display_name        = each.value.display_name
  mail_nickname       = each.key
  password            = random_password.test_user_password[0].result
  
  lifecycle {
    ignore_changes = [password]
  }
}

# Add test users to groups
resource "azuread_group_member" "test_user_memberships" {
  for_each = var.create_test_users ? {
    for membership in flatten([
      for user_key, user_config in var.test_users : [
        for group in user_config.groups : {
          user_key  = user_key
          group_key = group
          key       = "${user_key}-${group}"
        }
      ]
    ]) : membership.key => membership
  } : {}

  group_object_id  = azuread_group.hcp_groups[each.value.group_key].object_id
  member_object_id = azuread_user.test_users[each.value.user_key].object_id
}