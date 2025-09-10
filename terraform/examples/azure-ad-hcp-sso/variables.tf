# Variables for Azure AD HCP SSO Example

variable "azure_tenant_id" {
  description = "Azure AD Tenant ID"
  type        = string
}

variable "hcp_client_id" {
  description = "HCP Client ID for authentication"
  type        = string
  sensitive   = true
}

variable "hcp_client_secret" {
  description = "HCP Client Secret for authentication"
  type        = string
  sensitive   = true
}

variable "hcp_organization_id" {
  description = "HCP Organization ID for production"
  type        = string
}

variable "hcp_organization_id_dev" {
  description = "HCP Organization ID for development"
  type        = string
  default     = ""
}

variable "environment" {
  description = "Environment name"
  type        = string
  default     = "prod"
}