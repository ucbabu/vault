#!/bin/bash

# HCP Organization SSO Setup Script
# This script automates the configuration of Single Sign-On (SSO) for HashiCorp Cloud Platform Organization

set -euo pipefail

# Script information
readonly SCRIPT_NAME="hcp-org-sso-setup.sh"
readonly SCRIPT_VERSION="1.0.0"
readonly SCRIPT_DESCRIPTION="Automate HCP Organization SSO configuration"

# Colors for output
readonly RED='\033[0;31m'
readonly GREEN='\033[0;32m'
readonly YELLOW='\033[1;33m'
readonly BLUE='\033[0;34m'
readonly PURPLE='\033[0;35m'
readonly CYAN='\033[0;36m'
readonly NC='\033[0m' # No Color

# Global variables
PROVIDER_TYPE=""
PROVIDER_NAME=""
DRY_RUN=false
VERBOSE=false
CONFIG_FILE=""
ORGANIZATION_ID=""
TEST_MODE=false
BACKUP_CONFIG=true

# OIDC specific variables
OIDC_ISSUER_URL=""
OIDC_CLIENT_ID=""
OIDC_CLIENT_SECRET=""
OIDC_SCOPES="openid profile email groups"

# SAML specific variables
SAML_SSO_URL=""
SAML_ENTITY_ID=""
SAML_CERTIFICATE=""

# Group mapping variables
declare -A GROUP_MAPPINGS
JIT_PROVISIONING=true
ENFORCE_SSO=false

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
Usage: $0 [OPTIONS] PROVIDER_TYPE

Automate HCP Organization SSO configuration for centralized authentication.

ARGUMENTS:
    PROVIDER_TYPE       Type of identity provider (oidc|saml)

OPTIONS:
    -n, --name          Provider name (e.g., "Azure AD", "Okta")
    -o, --org-id        HCP Organization ID
    -c, --config        Configuration file path
    --dry-run           Show what would be done without making changes
    --test              Run in test mode with validation only
    --no-backup         Skip configuration backup
    -v, --verbose       Enable verbose logging
    -h, --help          Show this help message

OIDC OPTIONS:
    --oidc-issuer       OIDC issuer URL
    --oidc-client-id    OIDC client ID
    --oidc-secret       OIDC client secret
    --oidc-scopes       OIDC scopes (default: "openid profile email groups")

SAML OPTIONS:
    --saml-sso-url      SAML SSO URL
    --saml-entity-id    SAML entity ID
    --saml-cert         SAML certificate file path

GROUP MAPPING OPTIONS:
    --group-mapping     Group mapping in format "idp_group:hcp_role:projects"
    --jit-provisioning  Enable Just-In-Time user provisioning (default: true)
    --enforce-sso       Enforce SSO for all users (default: false)

EXAMPLES:
    # OIDC with Azure AD
    $0 oidc --name "Azure AD" --org-id "org-123" \\
       --oidc-issuer "https://login.microsoftonline.com/tenant-id/v2.0" \\
       --oidc-client-id "client-id" --oidc-secret "client-secret"

    # SAML with Okta
    $0 saml --name "Okta SAML" --org-id "org-123" \\
       --saml-sso-url "https://company.okta.com/app/sso/saml" \\
       --saml-entity-id "http://www.okta.com/entity-id"

    # Using configuration file
    $0 oidc --config sso-config.yaml --dry-run

PREREQUISITES:
    - HCP Organization Owner or Admin role
    - HCP CLI configured and authenticated
    - Identity provider application configured
    - Network connectivity to identity provider

EOF
}

# Parse command line arguments
parse_args() {
    while [[ $# -gt 0 ]]; do
        case $1 in
            -n|--name)
                PROVIDER_NAME="$2"
                shift 2
                ;;
            -o|--org-id)
                ORGANIZATION_ID="$2"
                shift 2
                ;;
            -c|--config)
                CONFIG_FILE="$2"
                shift 2
                ;;
            --oidc-issuer)
                OIDC_ISSUER_URL="$2"
                shift 2
                ;;
            --oidc-client-id)
                OIDC_CLIENT_ID="$2"
                shift 2
                ;;
            --oidc-secret)
                OIDC_CLIENT_SECRET="$2"
                shift 2
                ;;
            --oidc-scopes)
                OIDC_SCOPES="$2"
                shift 2
                ;;
            --saml-sso-url)
                SAML_SSO_URL="$2"
                shift 2
                ;;
            --saml-entity-id)
                SAML_ENTITY_ID="$2"
                shift 2
                ;;
            --saml-cert)
                SAML_CERTIFICATE="$2"
                shift 2
                ;;
            --group-mapping)
                parse_group_mapping "$2"
                shift 2
                ;;
            --jit-provisioning)
                JIT_PROVISIONING=true
                shift
                ;;
            --enforce-sso)
                ENFORCE_SSO=true
                shift
                ;;
            --dry-run)
                DRY_RUN=true
                shift
                ;;
            --test)
                TEST_MODE=true
                shift
                ;;
            --no-backup)
                BACKUP_CONFIG=false
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
                if [[ -z "$PROVIDER_TYPE" ]]; then
                    PROVIDER_TYPE="$1"
                else
                    log_error "Too many arguments"
                    usage
                    exit 1
                fi
                shift
                ;;
        esac
    done

    # Validate required arguments
    if [[ -z "$PROVIDER_TYPE" ]]; then
        log_error "Provider type is required"
        usage
        exit 1
    fi

    if [[ "$PROVIDER_TYPE" != "oidc" && "$PROVIDER_TYPE" != "saml" ]]; then
        log_error "Provider type must be 'oidc' or 'saml'"
        exit 1
    fi

    # Load configuration file if provided
    if [[ -n "$CONFIG_FILE" ]]; then
        load_config_file "$CONFIG_FILE"
    fi

    # Validate provider-specific requirements
    validate_provider_config
}

# Parse group mapping
parse_group_mapping() {
    local mapping="$1"
    if [[ "$mapping" =~ ^([^:]+):([^:]+):(.+)$ ]]; then
        local idp_group="${BASH_REMATCH[1]}"
        local hcp_role="${BASH_REMATCH[2]}"
        local projects="${BASH_REMATCH[3]}"
        GROUP_MAPPINGS["$idp_group"]="$hcp_role:$projects"
        log_debug "Added group mapping: $idp_group -> $hcp_role ($projects)"
    else
        log_error "Invalid group mapping format: $mapping"
        log_error "Expected format: idp_group:hcp_role:projects"
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
    
    # Parse YAML configuration file
    if command -v yq &> /dev/null; then
        parse_yaml_config "$config_file"
    else
        log_warning "yq not found, attempting manual parsing"
        parse_simple_config "$config_file"
    fi
}

# Parse YAML configuration using yq
parse_yaml_config() {
    local config_file="$1"
    
    PROVIDER_NAME=$(yq eval '.provider.name // ""' "$config_file")
    ORGANIZATION_ID=$(yq eval '.organization.id // ""' "$config_file")
    
    if [[ "$PROVIDER_TYPE" == "oidc" ]]; then
        OIDC_ISSUER_URL=$(yq eval '.oidc.issuer_url // ""' "$config_file")
        OIDC_CLIENT_ID=$(yq eval '.oidc.client_id // ""' "$config_file")
        OIDC_CLIENT_SECRET=$(yq eval '.oidc.client_secret // ""' "$config_file")
        OIDC_SCOPES=$(yq eval '.oidc.scopes // "openid profile email groups"' "$config_file")
    elif [[ "$PROVIDER_TYPE" == "saml" ]]; then
        SAML_SSO_URL=$(yq eval '.saml.sso_url // ""' "$config_file")
        SAML_ENTITY_ID=$(yq eval '.saml.entity_id // ""' "$config_file")
        SAML_CERTIFICATE=$(yq eval '.saml.certificate_file // ""' "$config_file")
    fi
    
    JIT_PROVISIONING=$(yq eval '.jit_provisioning // true' "$config_file")
    ENFORCE_SSO=$(yq eval '.enforce_sso // false' "$config_file")
}

# Simple configuration parser for key=value format
parse_simple_config() {
    local config_file="$1"
    
    while IFS='=' read -r key value; do
        # Skip comments and empty lines
        [[ "$key" =~ ^[[:space:]]*# ]] && continue
        [[ -z "$key" ]] && continue
        
        # Remove quotes from value
        value=$(echo "$value" | sed 's/^["'\'']//' | sed 's/["'\'']$//')
        
        case "$key" in
            provider_name) PROVIDER_NAME="$value" ;;
            organization_id) ORGANIZATION_ID="$value" ;;
            oidc_issuer_url) OIDC_ISSUER_URL="$value" ;;
            oidc_client_id) OIDC_CLIENT_ID="$value" ;;
            oidc_client_secret) OIDC_CLIENT_SECRET="$value" ;;
            oidc_scopes) OIDC_SCOPES="$value" ;;
            saml_sso_url) SAML_SSO_URL="$value" ;;
            saml_entity_id) SAML_ENTITY_ID="$value" ;;
            saml_certificate) SAML_CERTIFICATE="$value" ;;
            jit_provisioning) JIT_PROVISIONING="$value" ;;
            enforce_sso) ENFORCE_SSO="$value" ;;
        esac
    done < "$config_file"
}

# Validate provider-specific configuration
validate_provider_config() {
    log_step "Validating configuration"
    
    if [[ -z "$PROVIDER_NAME" ]]; then
        log_error "Provider name is required"
        exit 1
    fi
    
    if [[ -z "$ORGANIZATION_ID" ]]; then
        log_error "Organization ID is required"
        exit 1
    fi
    
    if [[ "$PROVIDER_TYPE" == "oidc" ]]; then
        validate_oidc_config
    elif [[ "$PROVIDER_TYPE" == "saml" ]]; then
        validate_saml_config
    fi
    
    log_success "Configuration validation passed"
}

# Validate OIDC configuration
validate_oidc_config() {
    local required_vars=("OIDC_ISSUER_URL" "OIDC_CLIENT_ID" "OIDC_CLIENT_SECRET")
    
    for var in "${required_vars[@]}"; do
        if [[ -z "${!var}" ]]; then
            log_error "OIDC configuration missing: $var"
            exit 1
        fi
    done
    
    # Validate OIDC issuer URL format
    if [[ ! "$OIDC_ISSUER_URL" =~ ^https:// ]]; then
        log_error "OIDC issuer URL must use HTTPS"
        exit 1
    fi
}

# Validate SAML configuration
validate_saml_config() {
    local required_vars=("SAML_SSO_URL" "SAML_ENTITY_ID")
    
    for var in "${required_vars[@]}"; do
        if [[ -z "${!var}" ]]; then
            log_error "SAML configuration missing: $var"
            exit 1
        fi
    done
    
    # Validate SAML certificate file if provided
    if [[ -n "$SAML_CERTIFICATE" && ! -f "$SAML_CERTIFICATE" ]]; then
        log_error "SAML certificate file not found: $SAML_CERTIFICATE"
        exit 1
    fi
}

# Check prerequisites
check_prerequisites() {
    log_step "Checking prerequisites"
    
    # Check HCP CLI
    if ! command -v hcp &> /dev/null; then
        log_error "HCP CLI not found. Please install from: https://developer.hashicorp.com/hcp/docs/cli"
        exit 1
    fi
    
    # Check HCP authentication
    if ! hcp auth whoami &> /dev/null; then
        log_error "HCP CLI not authenticated. Run 'hcp auth login' first"
        exit 1
    fi
    
    # Check organization access
    if ! hcp organizations list &> /dev/null; then
        log_error "Unable to list HCP organizations. Check your permissions"
        exit 1
    fi
    
    # Validate organization ID
    if ! hcp organizations read "$ORGANIZATION_ID" &> /dev/null; then
        log_error "Organization not found or access denied: $ORGANIZATION_ID"
        exit 1
    fi
    
    # Check required tools
    local tools=("curl" "jq")
    for tool in "${tools[@]}"; do
        if ! command -v "$tool" &> /dev/null; then
            log_error "Required tool not found: $tool"
            exit 1
        fi
    done
    
    log_success "Prerequisites check passed"
}

# Backup current configuration
backup_current_config() {
    if [[ "$BACKUP_CONFIG" != true ]]; then
        return
    fi
    
    log_step "Backing up current SSO configuration"
    
    local backup_file="hcp-sso-backup-$(date +%Y%m%d-%H%M%S).json"
    
    if [[ "$DRY_RUN" == true ]]; then
        log_info "DRY RUN: Would backup current configuration to: $backup_file"
        return
    fi
    
    # Attempt to get current SSO configuration
    if hcp organizations authentication read "$ORGANIZATION_ID" > "$backup_file" 2>/dev/null; then
        log_success "Configuration backed up to: $backup_file"
    else
        log_warning "No existing SSO configuration found to backup"
        rm -f "$backup_file"
    fi
}

# Test identity provider connectivity
test_provider_connectivity() {
    log_step "Testing identity provider connectivity"
    
    if [[ "$PROVIDER_TYPE" == "oidc" ]]; then
        test_oidc_connectivity
    elif [[ "$PROVIDER_TYPE" == "saml" ]]; then
        test_saml_connectivity
    fi
}

# Test OIDC connectivity
test_oidc_connectivity() {
    log_info "Testing OIDC discovery endpoint"
    
    local discovery_url="${OIDC_ISSUER_URL}/.well-known/openid_configuration"
    
    if curl -s --fail --max-time 10 "$discovery_url" > /dev/null; then
        log_success "OIDC discovery endpoint accessible"
        
        # Test specific endpoints
        local endpoints=$(curl -s "$discovery_url" | jq -r '.authorization_endpoint, .token_endpoint, .userinfo_endpoint')
        echo "$endpoints" | while read -r endpoint; do
            if [[ -n "$endpoint" && "$endpoint" != "null" ]]; then
                if curl -s --fail --max-time 5 -I "$endpoint" > /dev/null; then
                    log_debug "Endpoint accessible: $endpoint"
                else
                    log_warning "Endpoint not accessible: $endpoint"
                fi
            fi
        done
    else
        log_error "OIDC discovery endpoint not accessible: $discovery_url"
        exit 1
    fi
}

# Test SAML connectivity
test_saml_connectivity() {
    log_info "Testing SAML SSO endpoint"
    
    if curl -s --fail --max-time 10 -I "$SAML_SSO_URL" > /dev/null; then
        log_success "SAML SSO endpoint accessible"
    else
        log_error "SAML SSO endpoint not accessible: $SAML_SSO_URL"
        exit 1
    fi
    
    # Test SAML metadata if entity ID looks like a URL
    if [[ "$SAML_ENTITY_ID" =~ ^https?:// ]]; then
        log_info "Testing SAML metadata endpoint"
        if curl -s --fail --max-time 10 "$SAML_ENTITY_ID" > /dev/null; then
            log_success "SAML metadata endpoint accessible"
        else
            log_warning "SAML metadata endpoint not accessible: $SAML_ENTITY_ID"
        fi
    fi
}

# Configure OIDC SSO
configure_oidc_sso() {
    log_step "Configuring OIDC SSO"
    
    if [[ "$DRY_RUN" == true ]]; then
        log_info "DRY RUN: Would configure OIDC SSO with:"
        log_info "  Provider: $PROVIDER_NAME"
        log_info "  Issuer: $OIDC_ISSUER_URL"
        log_info "  Client ID: $OIDC_CLIENT_ID"
        log_info "  Scopes: $OIDC_SCOPES"
        return
    fi
    
    # Create OIDC configuration JSON
    local config_json
    config_json=$(cat << EOF
{
    "providerType": "oidc",
    "providerName": "$PROVIDER_NAME",
    "issuerUrl": "$OIDC_ISSUER_URL",
    "clientId": "$OIDC_CLIENT_ID",
    "clientSecret": "$OIDC_CLIENT_SECRET",
    "scopes": [$(echo "$OIDC_SCOPES" | sed 's/ /", "/g' | sed 's/^/"/; s/$/"/')],,
    "claimMappings": {
        "userId": "sub",
        "email": "email",
        "name": "name",
        "groups": "groups"
    },
    "jitProvisioning": $JIT_PROVISIONING,
    "enforceSSO": $ENFORCE_SSO
}
EOF
    )
    
    # Apply OIDC configuration
    if echo "$config_json" | hcp organizations authentication enable-oidc "$ORGANIZATION_ID" --config-stdin; then
        log_success "OIDC SSO configured successfully"
    else
        log_error "Failed to configure OIDC SSO"
        exit 1
    fi
}

# Configure SAML SSO
configure_saml_sso() {
    log_step "Configuring SAML SSO"
    
    if [[ "$DRY_RUN" == true ]]; then
        log_info "DRY RUN: Would configure SAML SSO with:"
        log_info "  Provider: $PROVIDER_NAME"
        log_info "  SSO URL: $SAML_SSO_URL"
        log_info "  Entity ID: $SAML_ENTITY_ID"
        return
    fi
    
    # Read SAML certificate if provided
    local cert_content=""
    if [[ -n "$SAML_CERTIFICATE" ]]; then
        cert_content=$(cat "$SAML_CERTIFICATE")
    fi
    
    # Create SAML configuration JSON
    local config_json
    config_json=$(cat << EOF
{
    "providerType": "saml",
    "providerName": "$PROVIDER_NAME",
    "ssoUrl": "$SAML_SSO_URL",
    "entityId": "$SAML_ENTITY_ID",
    "x509Certificate": "$cert_content",
    "attributeMappings": {
        "userId": "http://schemas.xmlsoap.org/ws/2005/05/identity/claims/nameidentifier",
        "email": "http://schemas.xmlsoap.org/ws/2005/05/identity/claims/emailaddress",
        "name": "http://schemas.xmlsoap.org/ws/2005/05/identity/claims/name",
        "groups": "http://schemas.xmlsoap.org/ws/2005/05/identity/claims/groups"
    },
    "jitProvisioning": $JIT_PROVISIONING,
    "enforceSSO": $ENFORCE_SSO
}
EOF
    )
    
    # Apply SAML configuration
    if echo "$config_json" | hcp organizations authentication enable-saml "$ORGANIZATION_ID" --config-stdin; then
        log_success "SAML SSO configured successfully"
    else
        log_error "Failed to configure SAML SSO"
        exit 1
    fi
}

# Configure group mappings
configure_group_mappings() {
    if [[ ${#GROUP_MAPPINGS[@]} -eq 0 ]]; then
        log_info "No group mappings to configure"
        return
    fi
    
    log_step "Configuring group mappings"
    
    for idp_group in "${!GROUP_MAPPINGS[@]}"; do
        local mapping="${GROUP_MAPPINGS[$idp_group]}"
        local hcp_role="${mapping%%:*}"
        local projects="${mapping#*:}"
        
        if [[ "$DRY_RUN" == true ]]; then
            log_info "DRY RUN: Would map group '$idp_group' to role '$hcp_role' for projects: $projects"
            continue
        fi
        
        # Configure group mapping
        if hcp organizations rbac create-group-mapping "$ORGANIZATION_ID" \
            --group "$idp_group" \
            --role "$hcp_role" \
            --projects "$projects"; then
            log_success "Configured group mapping: $idp_group -> $hcp_role"
        else
            log_error "Failed to configure group mapping for: $idp_group"
        fi
    done
}

# Test SSO configuration
test_sso_configuration() {
    if [[ "$TEST_MODE" != true ]]; then
        return
    fi
    
    log_step "Testing SSO configuration"
    
    # Get current SSO configuration
    local current_config
    if current_config=$(hcp organizations authentication read "$ORGANIZATION_ID" 2>/dev/null); then
        log_success "SSO configuration retrieved successfully"
        log_debug "Current configuration: $current_config"
    else
        log_error "Failed to retrieve SSO configuration"
        exit 1
    fi
    
    # Test SSO login URL
    local sso_url="https://portal.cloud.hashicorp.com/sign-in/sso?organization_id=$ORGANIZATION_ID"
    log_info "SSO login URL: $sso_url"
    
    if curl -s --fail --max-time 10 -I "$sso_url" > /dev/null; then
        log_success "SSO login URL accessible"
    else
        log_warning "SSO login URL not accessible (this may be expected)"
    fi
}

# Generate summary report
generate_summary() {
    log_step "Generating configuration summary"
    
    cat << EOF

${GREEN}===============================================${NC}
${GREEN}    HCP Organization SSO Setup Complete      ${NC}
${GREEN}===============================================${NC}

${BLUE}Configuration Details:${NC}
- Organization ID: ${ORGANIZATION_ID}
- Provider Type: ${PROVIDER_TYPE}
- Provider Name: ${PROVIDER_NAME}
- JIT Provisioning: ${JIT_PROVISIONING}
- Enforce SSO: ${ENFORCE_SSO}

EOF

    if [[ "$PROVIDER_TYPE" == "oidc" ]]; then
        cat << EOF
${BLUE}OIDC Configuration:${NC}
- Issuer URL: ${OIDC_ISSUER_URL}
- Client ID: ${OIDC_CLIENT_ID}
- Scopes: ${OIDC_SCOPES}

EOF
    elif [[ "$PROVIDER_TYPE" == "saml" ]]; then
        cat << EOF
${BLUE}SAML Configuration:${NC}
- SSO URL: ${SAML_SSO_URL}
- Entity ID: ${SAML_ENTITY_ID}
- Certificate: ${SAML_CERTIFICATE:-"Not provided"}

EOF
    fi

    if [[ ${#GROUP_MAPPINGS[@]} -gt 0 ]]; then
        echo -e "${BLUE}Group Mappings:${NC}"
        for idp_group in "${!GROUP_MAPPINGS[@]}"; do
            local mapping="${GROUP_MAPPINGS[$idp_group]}"
            echo "- $idp_group -> $mapping"
        done
        echo
    fi

    cat << EOF
${BLUE}Next Steps:${NC}
1. Test SSO login at: https://portal.cloud.hashicorp.com/sign-in/sso?organization_id=$ORGANIZATION_ID
2. Configure Vault-specific OIDC authentication
3. Set up team onboarding with namespace isolation
4. Configure audit logging and monitoring
5. Train users on new SSO process

${BLUE}Related Documentation:${NC}
- HCP Organization SSO Guide: docs/setup-guides/03-hcp-organization-sso-setup.md
- Vault OIDC Integration: docs/user-guides/09-vault-oidc-authentication.md
- Multi-Team Onboarding: docs/user-guides/08-multi-team-onboarding.md

EOF

    if [[ "$DRY_RUN" == true ]]; then
        echo -e "${YELLOW}Note: This was a dry run. No changes were made to the actual configuration.${NC}"
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
    backup_current_config
    test_provider_connectivity
    
    if [[ "$PROVIDER_TYPE" == "oidc" ]]; then
        configure_oidc_sso
    elif [[ "$PROVIDER_TYPE" == "saml" ]]; then
        configure_saml_sso
    fi
    
    configure_group_mappings
    test_sso_configuration
    generate_summary
    
    log_success "HCP Organization SSO setup completed successfully!"
}

# Script entry point
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    main "$@"
fi