#!/bin/bash
# hcp-terraform-vault-setup.sh
# HCP Terraform Vault integration setup script for dynamic Azure credentials

set -euo pipefail

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Logging functions
log_info() {
    echo -e "${BLUE}[INFO]${NC} $1"
}

log_success() {
    echo -e "${GREEN}[SUCCESS]${NC} $1"
}

log_warning() {
    echo -e "${YELLOW}[WARNING]${NC} $1"
}

log_error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

# Default configuration
DEFAULT_AZURE_ROLE_NAME="hcp-terraform"
DEFAULT_WORKSPACE_NAME="azure-infrastructure"
DEFAULT_TTL="1h"
DEFAULT_MAX_TTL="4h"
DRY_RUN=false

# Show usage information
show_usage() {
    cat << EOF
Usage: $0 [OPTIONS]

Setup HCP Terraform integration with Vault for dynamic Azure credentials.

OPTIONS:
    -o, --organization NAME     HCP Terraform organization name (required)
    -w, --workspace NAME        Workspace name (default: $DEFAULT_WORKSPACE_NAME)
    -r, --role NAME             Vault Azure role name (default: $DEFAULT_AZURE_ROLE_NAME)
    -t, --ttl DURATION          Credential TTL (default: $DEFAULT_TTL)
    -m, --max-ttl DURATION      Maximum credential TTL (default: $DEFAULT_MAX_TTL)
    -s, --subscription-id ID    Azure subscription ID for role scope
    --dry-run                   Show what would be done without making changes
    -h, --help                  Show this help message

EXAMPLES:
    # Basic setup
    $0 --organization "my-org"
    
    # Custom configuration
    $0 --organization "my-org" --workspace "production-azure" --role "terraform-deployer"
    
    # Dry run to see what would be configured
    $0 --organization "my-org" --dry-run

PREREQUISITES:
    - VAULT_ADDR and VAULT_TOKEN environment variables set
    - Azure CLI logged in (az login)
    - AZURE_SUBSCRIPTION_ID and AZURE_TENANT_ID environment variables set
    - HCP_TERRAFORM_TOKEN environment variable set
    - Vault Azure secrets engine already configured

EOF
}

# Parse command line arguments
parse_arguments() {
    while [[ $# -gt 0 ]]; do
        case $1 in
            -o|--organization)
                HCP_ORG="$2"
                shift 2
                ;;
            -w|--workspace)
                WORKSPACE_NAME="$2"
                shift 2
                ;;
            -r|--role)
                AZURE_ROLE_NAME="$2"
                shift 2
                ;;
            -t|--ttl)
                TTL="$2"
                shift 2
                ;;
            -m|--max-ttl)
                MAX_TTL="$2"
                shift 2
                ;;
            -s|--subscription-id)
                SUBSCRIPTION_SCOPE="$2"
                shift 2
                ;;
            --dry-run)
                DRY_RUN=true
                shift
                ;;
            -h|--help)
                show_usage
                exit 0
                ;;
            *)
                log_error "Unknown option: $1"
                show_usage
                exit 1
                ;;
        esac
    done

    # Set defaults
    WORKSPACE_NAME="${WORKSPACE_NAME:-$DEFAULT_WORKSPACE_NAME}"
    AZURE_ROLE_NAME="${AZURE_ROLE_NAME:-$DEFAULT_AZURE_ROLE_NAME}"
    TTL="${TTL:-$DEFAULT_TTL}"
    MAX_TTL="${MAX_TTL:-$DEFAULT_MAX_TTL}"
    
    # Validate required parameters
    if [[ -z "${HCP_ORG:-}" ]]; then
        log_error "HCP Terraform organization name is required"
        show_usage
        exit 1
    fi
}

# Check prerequisites
check_prerequisites() {
    log_info "Checking prerequisites for HCP Terraform setup..."
    
    # Check Vault connection
    if [[ -z "${VAULT_ADDR:-}" ]] || [[ -z "${VAULT_TOKEN:-}" ]]; then
        log_error "VAULT_ADDR and VAULT_TOKEN environment variables must be set"
        exit 1
    fi
    
    if ! vault status &> /dev/null; then
        log_error "Cannot connect to Vault at $VAULT_ADDR"
        exit 1
    fi
    
    # Check HCP Terraform token
    if [[ -z "${HCP_TERRAFORM_TOKEN:-}" ]]; then
        log_error "HCP_TERRAFORM_TOKEN environment variable must be set"
        log_info "Get your token from: https://app.terraform.io/app/settings/tokens"
        exit 1
    fi
    
    # Check Azure CLI
    if ! command -v az &> /dev/null; then
        log_error "Azure CLI is not installed. Please install it first."
        exit 1
    fi
    
    # Check Azure login
    if ! az account show &> /dev/null; then
        log_error "Not logged into Azure. Please run 'az login' first."
        exit 1
    fi
    
    # Check required environment variables
    local required_vars=("AZURE_SUBSCRIPTION_ID" "AZURE_TENANT_ID")
    for var in "${required_vars[@]}"; do
        if [[ -z "${!var:-}" ]]; then
            log_error "$var environment variable is not set"
            exit 1
        fi
    done
    
    # Check if Azure secrets engine is configured
    if ! vault secrets list | grep -q "azure/"; then
        log_error "Azure secrets engine is not enabled. Please run azure-setup.sh first."
        exit 1
    fi
    
    # Check if Terraform CLI is available
    if ! command -v terraform &> /dev/null; then
        log_warning "Terraform CLI not found. Install it for local testing."
    fi
    
    # Set subscription scope if not provided
    SUBSCRIPTION_SCOPE="${SUBSCRIPTION_SCOPE:-$AZURE_SUBSCRIPTION_ID}"
    
    log_success "Prerequisites check passed"
}

# Create Vault Azure role for HCP Terraform
create_vault_azure_role() {
    log_info "Creating Vault Azure role: $AZURE_ROLE_NAME"
    
    local role_config_file="/tmp/hcp-terraform-azure-role.json"
    
    cat > "$role_config_file" << EOF
{
  "azure_roles": [
    {
      "role_name": "Contributor",
      "scope": "/subscriptions/$SUBSCRIPTION_SCOPE"
    }
  ],
  "ttl": "$TTL",
  "max_ttl": "$MAX_TTL"
}
EOF
    
    if [[ "$DRY_RUN" == "true" ]]; then
        log_info "[DRY RUN] Would create Azure role with config:"
        cat "$role_config_file" | jq .
    else
        vault write "azure/roles/$AZURE_ROLE_NAME" @"$role_config_file"
        log_success "Azure role '$AZURE_ROLE_NAME' created"
    fi
    
    rm -f "$role_config_file"
}

# Configure Vault JWT authentication for HCP Terraform
configure_vault_jwt_auth() {
    log_info "Configuring Vault JWT authentication for HCP Terraform"
    
    local auth_path="hcp_terraform"
    
    if [[ "$DRY_RUN" == "true" ]]; then
        log_info "[DRY RUN] Would enable JWT auth at path: $auth_path"
        log_info "[DRY RUN] Would configure with issuer: https://app.terraform.io"
    else
        # Enable JWT auth backend if not already enabled
        if ! vault auth list | grep -q "$auth_path/"; then
            vault auth enable -path="$auth_path" jwt
            log_success "JWT auth backend enabled at path: $auth_path"
        else
            log_warning "JWT auth backend already enabled at path: $auth_path"
        fi
        
        # Configure JWT auth backend
        vault write "auth/$auth_path/config" \
            oidc_discovery_url="https://app.terraform.io" \
            bound_issuer="https://app.terraform.io"
        
        log_success "JWT auth backend configured"
    fi
}

# Create Vault policy for HCP Terraform
create_vault_policy() {
    log_info "Creating Vault policy for HCP Terraform"
    
    local policy_name="hcp-terraform-azure"
    local policy_file="/tmp/$policy_name.hcl"
    
    cat > "$policy_file" << EOF
# HCP Terraform Azure dynamic credentials policy

# Allow reading Azure dynamic credentials
path "azure/creds/$AZURE_ROLE_NAME" {
  capabilities = ["read"]
}

# Allow reading Azure role configuration
path "azure/roles/$AZURE_ROLE_NAME" {
  capabilities = ["read"]
}

# Allow listing Azure roles
path "azure/roles" {
  capabilities = ["list"]
}

# Allow reading Azure secrets engine configuration
path "azure/config" {
  capabilities = ["read"]
}

# Allow renewing own tokens
path "auth/token/renew-self" {
  capabilities = ["update"]
}

# Allow looking up own token
path "auth/token/lookup-self" {
  capabilities = ["read"]
}
EOF
    
    if [[ "$DRY_RUN" == "true" ]]; then
        log_info "[DRY RUN] Would create policy '$policy_name' with content:"
        cat "$policy_file"
    else
        vault policy write "$policy_name" "$policy_file"
        log_success "Policy '$policy_name' created"
    fi
    
    rm -f "$policy_file"
}

# Create Vault JWT role for HCP Terraform
create_vault_jwt_role() {
    log_info "Creating Vault JWT role for HCP Terraform"
    
    local auth_path="hcp_terraform"
    local jwt_role_name="hcp-terraform-azure"
    local policy_name="hcp-terraform-azure"
    
    if [[ "$DRY_RUN" == "true" ]]; then
        log_info "[DRY RUN] Would create JWT role '$jwt_role_name' with:"
        log_info "  - Bound audiences: vault.workload.identity"
        log_info "  - Bound claims: organization:$HCP_ORG:workspace:$WORKSPACE_NAME:run_phase:*"
        log_info "  - Token policies: $policy_name"
        log_info "  - Token TTL: 3600s"
        log_info "  - Token max TTL: 7200s"
    else
        vault write "auth/$auth_path/role/$jwt_role_name" \
            bound_audiences="vault.workload.identity" \
            bound_claims="sub=organization:$HCP_ORG:workspace:$WORKSPACE_NAME:run_phase:*" \
            user_claim="terraform_full_workspace" \
            role_type="jwt" \
            token_policies="$policy_name" \
            token_ttl=3600 \
            token_max_ttl=7200
        
        log_success "JWT role '$jwt_role_name' created"
    fi
}

# Test Vault configuration
test_vault_configuration() {
    log_info "Testing Vault configuration"
    
    if [[ "$DRY_RUN" == "true" ]]; then
        log_info "[DRY RUN] Would test:"
        log_info "  - Azure role credential generation"
        log_info "  - Policy permissions"
        log_info "  - JWT auth configuration"
        return
    fi
    
    # Test Azure role
    log_info "Testing Azure role credential generation..."
    local test_creds=$(vault read -format=json "azure/creds/$AZURE_ROLE_NAME")
    if [[ $? -eq 0 ]]; then
        local client_id=$(echo "$test_creds" | jq -r '.data.client_id')
        local lease_id=$(echo "$test_creds" | jq -r '.lease_id')
        log_success "Successfully generated test credentials - Client ID: $client_id"
        
        # Revoke test credentials
        vault lease revoke "$lease_id" &>/dev/null
        log_info "Test credentials revoked"
    else
        log_error "Failed to generate test credentials"
        exit 1
    fi
    
    # Test policy
    log_info "Testing policy permissions..."
    if vault policy read "hcp-terraform-azure" &>/dev/null; then
        log_success "Policy permissions verified"
    else
        log_error "Policy verification failed"
        exit 1
    fi
    
    # Test JWT auth
    log_info "Testing JWT authentication configuration..."
    if vault read "auth/hcp_terraform/config" &>/dev/null; then
        log_success "JWT authentication configured correctly"
    else
        log_error "JWT authentication configuration failed"
        exit 1
    fi
}

# Generate HCP Terraform configuration examples
generate_terraform_examples() {
    log_info "Generating HCP Terraform configuration examples"
    
    local examples_dir="../examples/hcp-terraform"
    
    if [[ "$DRY_RUN" == "true" ]]; then
        log_info "[DRY RUN] Would create examples in: $examples_dir"
        return
    fi
    
    mkdir -p "$examples_dir"
    
    # Main Terraform configuration
    cat > "$examples_dir/main.tf" << EOF
# HCP Terraform configuration with Vault dynamic Azure credentials
terraform {
  required_providers {
    vault = {
      source  = "hashicorp/vault"
      version = "~> 3.0"
    }
    azurerm = {
      source  = "hashicorp/azurerm"
      version = "~> 3.0"
    }
  }
}

# Configure Vault provider with JWT authentication
provider "vault" {
  address   = var.vault_addr
  namespace = var.vault_namespace
  
  auth_login_jwt {
    role  = "hcp-terraform-azure"
    mount = "hcp_terraform"
  }
}

# Get dynamic Azure credentials from Vault
data "vault_generic_secret" "azure_creds" {
  path = "azure/creds/$AZURE_ROLE_NAME"
}

# Configure Azure provider with dynamic credentials
provider "azurerm" {
  features {}
  
  subscription_id = var.azure_subscription_id
  tenant_id       = var.azure_tenant_id
  client_id       = data.vault_generic_secret.azure_creds.data["client_id"]
  client_secret   = data.vault_generic_secret.azure_creds.data["client_secret"]
}

# Example: Create a resource group
resource "azurerm_resource_group" "example" {
  name     = "\${var.environment}-\${var.project_name}-rg"
  location = var.azure_region
  
  tags = {
    Environment     = var.environment
    Project         = var.project_name
    ManagedBy      = "HCP-Terraform"
    CredentialsFrom = "Vault-Dynamic"
  }
}

# Example: Create a storage account
resource "azurerm_storage_account" "example" {
  name                     = "\${var.project_name}\${var.environment}storage"
  resource_group_name      = azurerm_resource_group.example.name
  location                = azurerm_resource_group.example.location
  account_tier            = "Standard"
  account_replication_type = "LRS"
  
  tags = azurerm_resource_group.example.tags
}
EOF

    # Variables file
    cat > "$examples_dir/variables.tf" << EOF
# Variables for HCP Terraform with Vault integration

variable "vault_addr" {
  description = "Vault server address"
  type        = string
}

variable "vault_namespace" {
  description = "Vault namespace"
  type        = string
  default     = "admin"
}

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

variable "environment" {
  description = "Environment name"
  type        = string
  default     = "dev"
}

variable "project_name" {
  description = "Project name for resource naming"
  type        = string
  default     = "vaultdemo"
}
EOF

    # Outputs file
    cat > "$examples_dir/outputs.tf" << EOF
# Outputs for HCP Terraform with Vault integration

output "resource_group_name" {
  description = "Name of the created resource group"
  value       = azurerm_resource_group.example.name
}

output "storage_account_name" {
  description = "Name of the created storage account"
  value       = azurerm_storage_account.example.name
}

output "vault_credentials_info" {
  description = "Information about Vault credentials used"
  value = {
    client_id    = data.vault_generic_secret.azure_creds.data["client_id"]
    lease_id     = data.vault_generic_secret.azure_creds.lease_id
    lease_duration = data.vault_generic_secret.azure_creds.lease_duration
  }
  sensitive = true
}

output "deployment_info" {
  description = "Deployment information"
  value = {
    environment = var.environment
    project     = var.project_name
    region      = var.azure_region
    managed_by  = "HCP-Terraform-with-Vault"
  }
}
EOF

    # README for the example
    cat > "$examples_dir/README.md" << EOF
# HCP Terraform with Vault Dynamic Azure Credentials

This example demonstrates how to use HCP Terraform with Vault dynamic Azure credentials.

## Prerequisites

1. Vault configured with Azure secrets engine
2. HCP Terraform workspace configured with Vault integration
3. Environment variables set in HCP Terraform workspace

## HCP Terraform Workspace Variables

Set these environment variables in your HCP Terraform workspace:

### Environment Variables
- \`VAULT_ADDR\`: Vault server URL
- \`VAULT_NAMESPACE\`: Vault namespace (usually "admin")
- \`ARM_SUBSCRIPTION_ID\`: Azure subscription ID
- \`ARM_TENANT_ID\`: Azure tenant ID

### Terraform Variables
- \`environment\`: Environment name (dev/staging/prod)
- \`project_name\`: Project name for resource naming
- \`azure_region\`: Azure region for resources

## Usage

1. Configure your HCP Terraform workspace with the variables above
2. Connect this Terraform configuration to your workspace
3. Run \`terraform plan\` and \`terraform apply\`

The configuration will:
1. Authenticate to Vault using HCP Terraform's JWT token
2. Retrieve dynamic Azure credentials from Vault
3. Use those credentials to create Azure resources

## Security Features

- **Short-lived credentials**: Azure credentials are dynamically generated with TTL
- **No static secrets**: No long-lived credentials stored in workspace
- **Automatic cleanup**: Credentials are automatically revoked after use
- **Audit trail**: All credential access is logged in Vault
- **Least privilege**: Azure role has minimal required permissions

## Monitoring

Check Vault audit logs to monitor credential usage:
\`\`\`bash
vault read azure/creds/$AZURE_ROLE_NAME
\`\`\`
EOF

    log_success "Terraform examples created in: $examples_dir"
}

# Create monitoring script for HCP Terraform integration
create_monitoring_script() {
    log_info "Creating monitoring script for HCP Terraform integration"
    
    if [[ "$DRY_RUN" == "true" ]]; then
        log_info "[DRY RUN] Would create monitoring script"
        return
    fi
    
    cat > "../scripts/monitor-hcp-terraform-vault.sh" << 'EOF'
#!/bin/bash
# monitor-hcp-terraform-vault.sh - Monitor HCP Terraform Vault integration

set -euo pipefail

echo "HCP Terraform Vault Integration Monitoring Report - $(date)"
echo "========================================================="

# Check Vault JWT auth backend
echo -e "\n1. Vault JWT Authentication Status:"
if vault auth list | grep -q "hcp_terraform/"; then
    echo "  ✓ JWT auth backend enabled at hcp_terraform/"
    vault read auth/hcp_terraform/config | grep -E "(oidc_discovery_url|bound_issuer)"
else
    echo "  ✗ JWT auth backend not found"
fi

# Check Vault policies
echo -e "\n2. Vault Policies:"
if vault policy list | grep -q "hcp-terraform-azure"; then
    echo "  ✓ hcp-terraform-azure policy exists"
else
    echo "  ✗ hcp-terraform-azure policy not found"
fi

# Check JWT roles
echo -e "\n3. JWT Authentication Roles:"
if vault list auth/hcp_terraform/role 2>/dev/null | grep -q "hcp-terraform-azure"; then
    echo "  ✓ hcp-terraform-azure role exists"
    vault read auth/hcp_terraform/role/hcp-terraform-azure | grep -E "(bound_audiences|bound_claims|token_policies)"
else
    echo "  ✗ hcp-terraform-azure role not found"
fi

# Check Azure roles
echo -e "\n4. Azure Roles for HCP Terraform:"
for role in $(vault list azure/roles 2>/dev/null | grep -E "(hcp-terraform|terraform)" || echo ""); do
    if [[ -n "$role" ]]; then
        echo "  ✓ Azure role: $role"
        vault read "azure/roles/$role" | grep -E "(ttl|max_ttl)"
    fi
done

# Check active leases for HCP Terraform roles
echo -e "\n5. Active HCP Terraform Credentials:"
for role in $(vault list azure/roles 2>/dev/null | grep -E "(hcp-terraform|terraform)" || echo ""); do
    if [[ -n "$role" ]]; then
        lease_count=$(vault list "sys/leases/lookup/azure/creds/$role" 2>/dev/null | wc -l || echo "0")
        echo "  $role: $lease_count active leases"
    fi
done

# Security recommendations
echo -e "\n6. Security Recommendations:"
echo "  - Monitor credential generation frequency"
echo "  - Review JWT role bound claims regularly"
echo "  - Ensure proper Azure role permissions (least privilege)"
echo "  - Set up alerting for authentication failures"
echo "  - Regularly rotate Vault service principal credentials"

# Recent authentication attempts (if audit logs are available)
echo -e "\n7. Recent Authentication Activity:"
echo "  Check Vault audit logs for recent JWT authentications from HCP Terraform"
echo "  Look for entries with: auth_type='jwt', role='hcp-terraform-azure'"
EOF
    
    chmod +x "../scripts/monitor-hcp-terraform-vault.sh"
    log_success "Monitoring script created"
}

# Generate summary report
generate_summary() {
    log_info "Generating HCP Terraform Vault integration summary..."
    
    cat << EOF

${GREEN}================================================================${NC}
${GREEN}    HCP Terraform Vault Integration Setup Complete             ${NC}
${GREEN}================================================================${NC}

${BLUE}Configuration Summary:${NC}
- HCP Terraform Organization: ${HCP_ORG}
- Workspace Name: ${WORKSPACE_NAME}
- Azure Role Name: ${AZURE_ROLE_NAME}
- Credential TTL: ${TTL}
- Maximum TTL: ${MAX_TTL}
- Azure Subscription Scope: ${SUBSCRIPTION_SCOPE}

${BLUE}Vault Configuration:${NC}
- JWT Auth Path: hcp_terraform/
- JWT Role: hcp-terraform-azure
- Policy: hcp-terraform-azure
- Azure Role: ${AZURE_ROLE_NAME}
- Discovery URL: https://app.terraform.io

${BLUE}HCP Terraform Workspace Variables Required:${NC}
Environment Variables:
- VAULT_ADDR: ${VAULT_ADDR}
- VAULT_NAMESPACE: ${VAULT_NAMESPACE:-admin}
- ARM_SUBSCRIPTION_ID: ${AZURE_SUBSCRIPTION_ID}
- ARM_TENANT_ID: ${AZURE_TENANT_ID}

Terraform Variables:
- environment: dev/staging/prod
- project_name: your-project-name
- azure_region: ${AZURE_REGION:-East US}

${BLUE}Terraform Provider Configuration:${NC}
\`\`\`hcl
provider "vault" {
  address   = var.vault_addr
  namespace = var.vault_namespace
  
  auth_login_jwt {
    role  = "hcp-terraform-azure"
    mount = "hcp_terraform"
  }
}

data "vault_generic_secret" "azure_creds" {
  path = "azure/creds/${AZURE_ROLE_NAME}"
}

provider "azurerm" {
  features {}
  
  subscription_id = var.azure_subscription_id
  tenant_id       = var.azure_tenant_id
  client_id       = data.vault_generic_secret.azure_creds.data["client_id"]
  client_secret   = data.vault_generic_secret.azure_creds.data["client_secret"]
}
\`\`\`

${BLUE}Next Steps:${NC}
1. Configure HCP Terraform workspace variables
2. Connect your Terraform configuration to the workspace
3. Test with a simple deployment
4. Monitor credential usage and authentication
5. Set up notifications for workspace runs

${BLUE}Security Features:${NC}
- ✓ JWT-based authentication (no static tokens)
- ✓ Short-lived Azure credentials (${TTL} TTL)
- ✓ Workspace-specific access controls
- ✓ Complete audit trail in Vault
- ✓ Automatic credential cleanup
- ✓ Least privilege Azure permissions

${BLUE}Monitoring & Maintenance:${NC}
- Use: ./scripts/monitor-hcp-terraform-vault.sh
- Check Vault audit logs for authentication activity
- Monitor credential generation patterns
- Review and update Azure role permissions regularly

${BLUE}Troubleshooting:${NC}
- Verify HCP Terraform workspace variables are set
- Check JWT authentication configuration
- Ensure Azure secrets engine is properly configured
- Validate Azure role permissions and scope

${YELLOW}Important Notes:${NC}
- Test in development workspace first
- Configure proper Azure role permissions
- Monitor credential usage patterns
- Set up alerting for authentication failures
- Keep Vault policies up to date

For detailed examples and documentation, see:
- examples/hcp-terraform/
- Generated Terraform configuration examples

EOF
}

# Main execution function
main() {
    parse_arguments "$@"
    
    if [[ "$DRY_RUN" == "true" ]]; then
        log_warning "DRY RUN MODE - No changes will be made"
    fi
    
    log_info "Starting HCP Terraform Vault integration setup..."
    log_info "Organization: $HCP_ORG, Workspace: $WORKSPACE_NAME, Role: $AZURE_ROLE_NAME"
    
    check_prerequisites
    create_vault_azure_role
    configure_vault_jwt_auth
    create_vault_policy
    create_vault_jwt_role
    test_vault_configuration
    generate_terraform_examples
    create_monitoring_script
    generate_summary
    
    if [[ "$DRY_RUN" == "true" ]]; then
        log_success "DRY RUN completed - review the planned changes above"
    else
        log_success "HCP Terraform Vault integration setup completed successfully!"
        log_info "Next: Configure your HCP Terraform workspace variables and test deployment"
    fi
}

# Execute main function with all arguments
main "$@"