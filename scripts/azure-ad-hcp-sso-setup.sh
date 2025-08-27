#!/bin/bash

# Azure AD HCP Organization SSO Setup Script
# Automates the complete Azure AD and HCP Organization SSO configuration

set -euo pipefail

# Script information
readonly SCRIPT_NAME="azure-ad-hcp-sso-setup.sh"
readonly SCRIPT_VERSION="1.0.0"
readonly SCRIPT_DESCRIPTION="Automate Azure AD and HCP Organization SSO setup"

# Colors for output
readonly RED='\033[0;31m'
readonly GREEN='\033[0;32m'
readonly YELLOW='\033[1;33m'
readonly BLUE='\033[0;34m'
readonly PURPLE='\033[0;35m'
readonly CYAN='\033[0;36m'
readonly NC='\033[0m' # No Color

# Global variables
HCP_ORG_ID=""
AZURE_TENANT_ID=""
APP_NAME="HashiCorp Cloud Platform"
APP_CLIENT_ID=""
APP_CLIENT_SECRET=""
DRY_RUN=false
VERBOSE=false
SKIP_AZURE_SETUP=false
SKIP_HCP_SETUP=false
CONFIG_FILE=""

# Azure AD Groups
declare -a AZURE_GROUPS=(
    "HCP-Platform-Admins"
    "HCP-Vault-Admins"
    "HCP-Vault-Operators"
    "HCP-Vault-Developers"
    "HCP-Security-Team"
)

# Group to HCP role mappings
declare -A GROUP_MAPPINGS=(
    ["HCP-Platform-Admins"]="Admin:*"
    ["HCP-Vault-Admins"]="Admin:vault-production,vault-staging"
    ["HCP-Vault-Operators"]="Contributor:vault-production,vault-staging"
    ["HCP-Vault-Developers"]="Contributor:vault-development,vault-staging"
    ["HCP-Security-Team"]="Viewer:*"
)

# Logging functions
log_info() {
    echo -e "${BLUE}[INFO]${NC} $1" >&2
}

log_success() {
    echo -e "${GREEN}[SUCCESS]${NC} $1" >&2
}

log_warning() {
    echo -e "${YELLOW}[WARNING]${NC} $1" >&2
}

log_error() {
    echo -e "${RED}[ERROR]${NC} $1" >&2
}

log_debug() {
    if [[ "$VERBOSE" == true ]]; then
        echo -e "${PURPLE}[DEBUG]${NC} $1" >&2
    fi
}

log_step() {
    echo -e "${CYAN}[STEP]${NC} $1" >&2
}

# Usage information
usage() {
    cat << EOF
Usage: $0 [OPTIONS]

Automate Azure AD and HCP Organization SSO configuration.

OPTIONS:
    --hcp-org-id        HCP Organization ID (required)
    --azure-tenant-id   Azure Tenant ID (required)
    --app-name          Azure AD application name (default: "HashiCorp Cloud Platform")
    --app-client-id     Existing Azure AD application client ID (optional)
    --config            Configuration file path
    --skip-azure        Skip Azure AD application setup
    --skip-hcp          Skip HCP Organization configuration
    --dry-run           Show what would be done without making changes
    -v, --verbose       Enable verbose logging
    -h, --help          Show this help message

EXAMPLES:
    # Complete setup
    $0 --hcp-org-id "org-abc123" --azure-tenant-id "tenant-xyz789"

    # Use existing Azure AD app
    $0 --hcp-org-id "org-abc123" --azure-tenant-id "tenant-xyz789" \\
       --app-client-id "existing-client-id" --skip-azure

    # Dry run to preview changes
    $0 --hcp-org-id "org-abc123" --azure-tenant-id "tenant-xyz789" --dry-run

PREREQUISITES:
    - Azure CLI installed and authenticated (az login)
    - HCP CLI installed and authenticated (hcp auth login)
    - Azure AD Global Administrator or Application Administrator role
    - HCP Organization Owner or Admin role

EOF
}

# Parse command line arguments
parse_args() {
    while [[ $# -gt 0 ]]; do
        case $1 in
            --hcp-org-id)
                HCP_ORG_ID="$2"
                shift 2
                ;;
            --azure-tenant-id)
                AZURE_TENANT_ID="$2"
                shift 2
                ;;
            --app-name)
                APP_NAME="$2"
                shift 2
                ;;
            --app-client-id)
                APP_CLIENT_ID="$2"
                SKIP_AZURE_SETUP=true
                shift 2
                ;;
            --config)
                CONFIG_FILE="$2"
                shift 2
                ;;
            --skip-azure)
                SKIP_AZURE_SETUP=true
                shift
                ;;
            --skip-hcp)
                SKIP_HCP_SETUP=true
                shift
                ;;
            --dry-run)
                DRY_RUN=true
                shift
                ;;
            -v|--verbose)
                VERBOSE=true
                shift
                ;;
            -h|--help)
                usage
                exit 0
                ;;
            -*)
                log_error "Unknown option: $1"
                usage
                exit 1
                ;;
            *)
                log_error "Unexpected argument: $1"
                usage
                exit 1
                ;;
        esac
    done

    # Load configuration file if provided
    if [[ -n "$CONFIG_FILE" ]]; then
        load_config_file "$CONFIG_FILE"
    fi

    # Validate required arguments
    if [[ -z "$HCP_ORG_ID" ]]; then
        log_error "HCP Organization ID is required"
        usage
        exit 1
    fi

    if [[ -z "$AZURE_TENANT_ID" ]]; then
        log_error "Azure Tenant ID is required"
        usage
        exit 1
    fi
}

# Load configuration from file
load_config_file() {
    local config_file="$1"
    
    if [[ ! -f "$config_file" ]]; then
        log_error "Configuration file not found: $config_file"
        exit 1
    fi

    log_info "Loading configuration from: $config_file"
    
    # Simple key=value parser
    while IFS='=' read -r key value; do
        [[ "$key" =~ ^[[:space:]]*# ]] && continue
        [[ -z "$key" ]] && continue
        
        value=$(echo "$value" | sed 's/^["'\'']//' | sed 's/["'\'']$//')
        
        case "$key" in
            hcp_org_id) HCP_ORG_ID="$value" ;;
            azure_tenant_id) AZURE_TENANT_ID="$value" ;;
            app_name) APP_NAME="$value" ;;
            app_client_id) APP_CLIENT_ID="$value" ;;
        esac
    done < "$config_file"
}

# Check prerequisites
check_prerequisites() {
    log_step "Checking prerequisites"
    
    # Check Azure CLI
    if ! command -v az &> /dev/null; then
        log_error "Azure CLI not found. Install from: https://docs.microsoft.com/en-us/cli/azure/install-azure-cli"
        exit 1
    fi
    
    # Check Azure authentication
    if ! az account show &> /dev/null; then
        log_error "Azure CLI not authenticated. Run 'az login' first"
        exit 1
    fi
    
    # Verify tenant ID matches
    local current_tenant
    current_tenant=$(az account show --query tenantId -o tsv)
    if [[ "$current_tenant" != "$AZURE_TENANT_ID" ]]; then
        log_warning "Current Azure tenant ($current_tenant) differs from specified ($AZURE_TENANT_ID)"
        log_info "Switching to specified tenant..."
        az account set --tenant "$AZURE_TENANT_ID"
    fi
    
    # Check HCP CLI
    if ! command -v hcp &> /dev/null; then
        log_error "HCP CLI not found. Install from: https://developer.hashicorp.com/hcp/docs/cli"
        exit 1
    fi
    
    # Check HCP authentication
    if ! hcp auth whoami &> /dev/null; then
        log_error "HCP CLI not authenticated. Run 'hcp auth login' first"
        exit 1
    fi
    
    # Validate HCP organization access
    if ! hcp organizations read "$HCP_ORG_ID" &> /dev/null; then
        log_error "Cannot access HCP organization: $HCP_ORG_ID"
        exit 1
    fi
    
    log_success "Prerequisites check passed"
}

# Create Azure AD application
create_azure_ad_app() {
    if [[ "$SKIP_AZURE_SETUP" == true ]]; then
        log_info "Skipping Azure AD application setup"
        return
    fi
    
    log_step "Creating Azure AD application: $APP_NAME"
    
    if [[ "$DRY_RUN" == true ]]; then
        log_info "DRY RUN: Would create Azure AD application '$APP_NAME'"
        APP_CLIENT_ID="dry-run-client-id"
        APP_CLIENT_SECRET="dry-run-client-secret"
        return
    fi
    
    # Check if application already exists
    local existing_app_id
    existing_app_id=$(az ad app list --display-name "$APP_NAME" --query "[0].appId" -o tsv 2>/dev/null || true)
    
    if [[ -n "$existing_app_id" && "$existing_app_id" != "null" ]]; then
        log_warning "Application '$APP_NAME' already exists with ID: $existing_app_id"
        APP_CLIENT_ID="$existing_app_id"
    else
        # Create new application
        local app_result
        app_result=$(az ad app create \
            --display-name "$APP_NAME" \
            --web-redirect-uris "https://auth.hashicorp.com/login/callback" \
            --sign-in-audience "AzureADMyOrg" \
            --query "{appId: appId, objectId: id}" -o json)
        
        APP_CLIENT_ID=$(echo "$app_result" | jq -r '.appId')
        local app_object_id
        app_object_id=$(echo "$app_result" | jq -r '.objectId')
        
        log_success "Created Azure AD application with ID: $APP_CLIENT_ID"
        
        # Configure optional claims for groups
        az ad app update --id "$APP_CLIENT_ID" --optional-claims '{
            "idToken": [
                {
                    "name": "groups",
                    "source": "user",
                    "essential": false,
                    "additionalProperties": ["emit_as_roles"]
                },
                {
                    "name": "email",
                    "source": "user",
                    "essential": true
                }
            ]
        }'
        
        log_success "Configured optional claims for groups and email"
    fi
    
    # Generate client secret
    local secret_result
    secret_result=$(az ad app credential reset \
        --id "$APP_CLIENT_ID" \
        --display-name "HCP SSO Secret" \
        --years 2 \
        --query password -o tsv)
    
    APP_CLIENT_SECRET="$secret_result"
    log_success "Generated client secret"
    
    # Grant Microsoft Graph permissions
    az ad app permission add \
        --id "$APP_CLIENT_ID" \
        --api 00000003-0000-0000-c000-000000000000 \
        --api-permissions e1fe6dd8-ba31-4d61-89e7-88639da4683d=Scope
    
    # Grant admin consent
    az ad app permission admin-consent --id "$APP_CLIENT_ID"
    log_success "Granted Microsoft Graph permissions"
}

# Create Azure AD groups
create_azure_ad_groups() {
    if [[ "$SKIP_AZURE_SETUP" == true ]]; then
        log_info "Skipping Azure AD groups setup"
        return
    fi
    
    log_step "Creating Azure AD security groups"
    
    for group_name in "${AZURE_GROUPS[@]}"; do
        if [[ "$DRY_RUN" == true ]]; then
            log_info "DRY RUN: Would create group '$group_name'"
            continue
        fi
        
        # Check if group already exists
        local existing_group_id
        existing_group_id=$(az ad group list --display-name "$group_name" --query "[0].id" -o tsv 2>/dev/null || true)
        
        if [[ -n "$existing_group_id" && "$existing_group_id" != "null" ]]; then
            log_info "Group '$group_name' already exists with ID: $existing_group_id"
        else
            # Create new group
            local mail_nickname
            mail_nickname=$(echo "$group_name" | tr '[:upper:]' '[:lower:]' | tr '-' '_')
            
            local group_id
            group_id=$(az ad group create \
                --display-name "$group_name" \
                --mail-nickname "$mail_nickname" \
                --query id -o tsv)
            
            log_success "Created group '$group_name' with ID: $group_id"
        fi
    done
}

# Configure HCP Organization SSO
configure_hcp_sso() {
    if [[ "$SKIP_HCP_SETUP" == true ]]; then
        log_info "Skipping HCP Organization SSO configuration"
        return
    fi
    
    log_step "Configuring HCP Organization SSO"
    
    local issuer_url="https://login.microsoftonline.com/${AZURE_TENANT_ID}/v2.0"
    
    if [[ "$DRY_RUN" == true ]]; then
        log_info "DRY RUN: Would configure HCP SSO with:"
        log_info "  Issuer URL: $issuer_url"
        log_info "  Client ID: $APP_CLIENT_ID"
        log_info "  Organization: $HCP_ORG_ID"
        return
    fi
    
    # Use the existing HCP SSO setup script
    local script_path
    script_path="$(dirname "$0")/hcp-org-sso-setup.sh"
    
    if [[ ! -f "$script_path" ]]; then
        log_error "HCP SSO setup script not found: $script_path"
        exit 1
    fi
    
    # Build group mapping arguments
    local group_args=()
    for group_name in "${!GROUP_MAPPINGS[@]}"; do
        group_args+=(--group-mapping "${group_name}:${GROUP_MAPPINGS[$group_name]}")
    done
    
    # Execute HCP SSO configuration
    bash "$script_path" oidc \
        --name "Azure AD" \
        --org-id "$HCP_ORG_ID" \
        --oidc-issuer "$issuer_url" \
        --oidc-client-id "$APP_CLIENT_ID" \
        --oidc-secret "$APP_CLIENT_SECRET" \
        "${group_args[@]}" \
        --jit-provisioning
    
    log_success "HCP Organization SSO configured successfully"
}

# Test configuration
test_configuration() {
    log_step "Testing SSO configuration"
    
    # Test Azure AD OIDC endpoints
    local discovery_url="https://login.microsoftonline.com/${AZURE_TENANT_ID}/v2.0/.well-known/openid_configuration"
    
    if curl -s --fail --max-time 10 "$discovery_url" > /dev/null; then
        log_success "Azure AD OIDC discovery endpoint accessible"
    else
        log_error "Azure AD OIDC discovery endpoint not accessible"
        return 1
    fi
    
    # Test HCP SSO URL
    local hcp_sso_url="https://portal.cloud.hashicorp.com/sign-in/sso?organization_id=$HCP_ORG_ID"
    log_info "Test SSO login at: $hcp_sso_url"
    
    # Validate Azure AD groups
    log_info "Validating Azure AD groups:"
    for group_name in "${AZURE_GROUPS[@]}"; do
        local group_id
        group_id=$(az ad group list --display-name "$group_name" --query "[0].id" -o tsv 2>/dev/null || true)
        if [[ -n "$group_id" && "$group_id" != "null" ]]; then
            log_success "  ✓ $group_name (ID: $group_id)"
        else
            log_warning "  ✗ $group_name (not found)"
        fi
    done
}

# Generate summary report
generate_summary() {
    log_step "Generating configuration summary"
    
    cat << EOF

${GREEN}===============================================${NC}
${GREEN}  Azure AD HCP Organization SSO Setup        ${NC}
${GREEN}===============================================${NC}

${BLUE}Configuration Details:${NC}
- HCP Organization ID: ${HCP_ORG_ID}
- Azure Tenant ID: ${AZURE_TENANT_ID}
- Application Name: ${APP_NAME}
- Application Client ID: ${APP_CLIENT_ID}

${BLUE}Azure AD Configuration:${NC}
- OIDC Issuer: https://login.microsoftonline.com/${AZURE_TENANT_ID}/v2.0
- Redirect URI: https://auth.hashicorp.com/login/callback
- Groups Configured: ${#AZURE_GROUPS[@]} groups

${BLUE}HCP Group Mappings:${NC}
EOF

    for group_name in "${!GROUP_MAPPINGS[@]}"; do
        echo "- $group_name → ${GROUP_MAPPINGS[$group_name]}"
    done

    cat << EOF

${BLUE}Next Steps:${NC}
1. Test SSO login: https://portal.cloud.hashicorp.com/sign-in/sso?organization_id=$HCP_ORG_ID
2. Add users to Azure AD groups
3. Configure Vault namespace authentication
4. Set up team onboarding automation
5. Configure monitoring and alerting

${BLUE}User Management:${NC}
# Add users to Azure AD groups
az ad group member add --group "HCP-Vault-Admins" --member-id <user-object-id>

${BLUE}Team Onboarding:${NC}
# Onboard teams with Azure AD SSO
./scripts/team-onboarding.sh team-alpha \\
    --oidc \\
    --oidc-url "https://login.microsoftonline.com/${AZURE_TENANT_ID}/v2.0" \\
    --oidc-client-id "vault-team-client" \\
    --oidc-secret "vault-team-secret"

EOF

    if [[ "$DRY_RUN" == true ]]; then
        echo -e "${YELLOW}Note: This was a dry run. No actual changes were made.${NC}"
        echo
    fi
}

# Main execution function
main() {
    echo -e "${CYAN}${SCRIPT_NAME} v${SCRIPT_VERSION}${NC}"
    echo -e "${CYAN}${SCRIPT_DESCRIPTION}${NC}"
    echo

    parse_args "$@"
    check_prerequisites
    create_azure_ad_app
    create_azure_ad_groups
    configure_hcp_sso
    test_configuration
    generate_summary
    
    log_success "Azure AD HCP Organization SSO setup completed successfully!"
}

# Script entry point
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    main "$@"
fi