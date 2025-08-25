#!/bin/bash
# team-onboarding.sh - Comprehensive team onboarding with HCP Vault namespaces
# This script automates the complete onboarding process for teams using Vault namespaces
# and Kubernetes integration with proper environment isolation.

set -euo pipefail

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
PURPLE='\033[0;35m'
CYAN='\033[0;36m'
NC='\033[0m'

log_info() { echo -e "${BLUE}[INFO]${NC} $1"; }
log_success() { echo -e "${GREEN}[SUCCESS]${NC} $1"; }
log_warning() { echo -e "${YELLOW}[WARNING]${NC} $1"; }
log_error() { echo -e "${RED}[ERROR]${NC} $1"; }
log_step() { echo -e "${PURPLE}[STEP]${NC} $1"; }
log_detail() { echo -e "${CYAN}[DETAIL]${NC} $1"; }

# Configuration
TEAM_NAME=""
VAULT_NAMESPACE=""
K8S_NAMESPACES=()
ENVIRONMENTS=("dev" "staging" "prod")
ENABLE_CLOUD_ENGINES=false
ENABLE_DATABASE_ENGINE=false
ENABLE_OIDC=false
OIDC_DISCOVERY_URL=""
OIDC_CLIENT_ID=""
OIDC_CLIENT_SECRET=""
DRY_RUN=false
SKIP_K8S=false

# Usage function
usage() {
    cat << EOF
Usage: $0 [OPTIONS] TEAM_NAME

Onboard a new team with HCP Vault namespace and Kubernetes integration.

ARGUMENTS:
    TEAM_NAME           Name of the team to onboard (required)

OPTIONS:
    -e, --environments  Comma-separated list of environments (default: dev,staging,prod)
    -c, --cloud         Enable cloud secrets engines (Azure, AWS, GCP)
    -d, --database      Enable database secrets engine
    -o, --oidc          Enable OIDC authentication with discovery URL
    --oidc-url          OIDC discovery URL (required if --oidc is used)
    --oidc-client-id    OIDC client ID (required if --oidc is used)
    --oidc-secret       OIDC client secret (required if --oidc is used)
    --dry-run           Show what would be done without making changes
    --skip-k8s          Skip Kubernetes namespace and resource creation
    -h, --help          Show this help message

EXAMPLES:
    # Basic team onboarding
    $0 team-alpha

    # Team with custom environments and cloud engines
    $0 -e "dev,test,staging,prod" -c -d team-beta

    # Team with OIDC authentication
    $0 --oidc --oidc-url "https://auth.company.com/.well-known/openid_configuration" \\
       --oidc-client-id "vault-client" --oidc-secret "secret" team-gamma

PREREQUISITES:
    - VAULT_ADDR and VAULT_TOKEN environment variables set
    - Admin access to HCP Vault
    - kubectl configured with cluster admin access
    - Vault Secrets Operator deployed in Kubernetes cluster

EOF
}

# Parse command line arguments
parse_args() {
    while [[ $# -gt 0 ]]; do
        case $1 in
            -e|--environments)
                IFS=',' read -ra ENVIRONMENTS <<< "$2"
                shift 2
                ;;
            -c|--cloud)
                ENABLE_CLOUD_ENGINES=true
                shift
                ;;
            -d|--database)
                ENABLE_DATABASE_ENGINE=true
                shift
                ;;
            -o|--oidc)
                ENABLE_OIDC=true
                shift
                ;;
            --oidc-url)
                OIDC_DISCOVERY_URL="$2"
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
            --dry-run)
                DRY_RUN=true
                shift
                ;;
            --skip-k8s)
                SKIP_K8S=true
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
                if [[ -z "$TEAM_NAME" ]]; then
                    TEAM_NAME="$1"
                else
                    log_error "Too many arguments"
                    usage
                    exit 1
                fi
                shift
                ;;
        esac
    done

    if [[ -z "$TEAM_NAME" ]]; then
        log_error "Team name is required"
        usage
        exit 1
    fi

    # Validate team name
    if [[ ! "$TEAM_NAME" =~ ^[a-z0-9-]+$ ]]; then
        log_error "Team name must contain only lowercase letters, numbers, and hyphens"
        exit 1
    fi

    # Set derived variables
    VAULT_NAMESPACE="$TEAM_NAME"
    for env in "${ENVIRONMENTS[@]}"; do
        K8S_NAMESPACES+=("${TEAM_NAME}-${env}")
    done

    # Validate OIDC configuration
    if [[ "$ENABLE_OIDC" == true ]]; then
        if [[ -z "$OIDC_DISCOVERY_URL" || -z "$OIDC_CLIENT_ID" || -z "$OIDC_CLIENT_SECRET" ]]; then
            log_error "OIDC requires --oidc-url, --oidc-client-id, and --oidc-secret"
            exit 1
        fi
    fi
}

# Check prerequisites
check_prerequisites() {
    log_step "Checking prerequisites for team onboarding..."
    
    # Check Vault connection
    if [[ -z "${VAULT_ADDR:-}" ]] || [[ -z "${VAULT_TOKEN:-}" ]]; then
        log_error "VAULT_ADDR and VAULT_TOKEN must be set"
        exit 1
    fi
    
    if ! vault status &> /dev/null; then
        log_error "Cannot connect to Vault at $VAULT_ADDR"
        exit 1
    fi
    
    # Check Vault permissions
    if ! vault namespace list &> /dev/null; then
        log_error "Insufficient permissions to manage namespaces. Admin access required."
        exit 1
    fi
    
    if [[ "$SKIP_K8S" != true ]]; then
        # Check kubectl
        if ! command -v kubectl &> /dev/null; then
            log_error "kubectl is not installed"
            exit 1
        fi
        
        if ! kubectl cluster-info &> /dev/null; then
            log_error "kubectl cannot connect to Kubernetes cluster"
            exit 1
        fi
        
        # Check if Vault Secrets Operator is deployed
        if ! kubectl get deployment vault-secrets-operator-controller-manager -n vault-secrets-operator-system &> /dev/null; then
            log_warning "Vault Secrets Operator not found. Install it first or use --skip-k8s"
        fi
    fi
    
    log_success "Prerequisites check passed"
}

# Create Vault namespace
create_vault_namespace() {
    log_step "Creating Vault namespace: $VAULT_NAMESPACE"
    
    if [[ "$DRY_RUN" == true ]]; then
        log_detail "DRY RUN: Would create Vault namespace '$VAULT_NAMESPACE'"
        return
    fi
    
    # Check if namespace already exists
    if vault namespace list | grep -q "^${VAULT_NAMESPACE}/"; then
        log_warning "Vault namespace '$VAULT_NAMESPACE' already exists"
        return
    fi
    
    vault namespace create "$VAULT_NAMESPACE"
    log_success "Created Vault namespace: $VAULT_NAMESPACE"
}

# Enable secrets engines
enable_secrets_engines() {
    log_step "Enabling secrets engines for $TEAM_NAME"
    
    if [[ "$DRY_RUN" == true ]]; then
        log_detail "DRY RUN: Would enable secrets engines in namespace '$VAULT_NAMESPACE'"
        return
    fi
    
    # Switch to team namespace
    export VAULT_NAMESPACE="$VAULT_NAMESPACE"
    
    # Enable KV v2 secrets engine
    if ! vault secrets list | grep -q "secrets/"; then
        vault secrets enable -path=secrets kv-v2
        log_success "Enabled KV v2 secrets engine"
    else
        log_warning "KV v2 secrets engine already enabled"
    fi
    
    # Enable database secrets engine if requested
    if [[ "$ENABLE_DATABASE_ENGINE" == true ]]; then
        if ! vault secrets list | grep -q "database/"; then
            vault secrets enable database
            log_success "Enabled database secrets engine"
        else
            log_warning "Database secrets engine already enabled"
        fi
    fi
    
    # Enable cloud secrets engines if requested
    if [[ "$ENABLE_CLOUD_ENGINES" == true ]]; then
        for cloud in azure aws gcp; do
            if ! vault secrets list | grep -q "${cloud}/"; then
                vault secrets enable -path="$cloud" "$cloud"
                log_success "Enabled $cloud secrets engine"
            else
                log_warning "$cloud secrets engine already enabled"
            fi
        done
    fi
}

# Create team policies
create_team_policies() {
    log_step "Creating team policies for environments: ${ENVIRONMENTS[*]}"
    
    if [[ "$DRY_RUN" == true ]]; then
        log_detail "DRY RUN: Would create team policies for environments: ${ENVIRONMENTS[*]}"
        return
    fi
    
    export VAULT_NAMESPACE="$VAULT_NAMESPACE"
    
    # Create admin policy for team leads
    cat > "/tmp/${TEAM_NAME}-admin-policy.hcl" << 'EOF'
# Full access to team secrets
path "secrets/*" {
  capabilities = ["create", "read", "update", "delete", "list"]
}

# Manage team policies
path "sys/policies/acl/{{identity.entity.name}}-*" {
  capabilities = ["create", "read", "update", "delete", "list"]
}

# View team audit logs
path "sys/audit" {
  capabilities = ["read", "list"]
}

# Manage team auth methods
path "sys/auth/{{identity.entity.name}}-*" {
  capabilities = ["create", "read", "update", "delete"]
}
EOF
    
    # Add database and cloud permissions if enabled
    if [[ "$ENABLE_DATABASE_ENGINE" == true ]]; then
        cat >> "/tmp/${TEAM_NAME}-admin-policy.hcl" << 'EOF'

# Manage database configurations
path "database/*" {
  capabilities = ["create", "read", "update", "delete", "list"]
}
EOF
    fi
    
    if [[ "$ENABLE_CLOUD_ENGINES" == true ]]; then
        for cloud in azure aws gcp; do
            cat >> "/tmp/${TEAM_NAME}-admin-policy.hcl" << EOF

# Manage $cloud configurations
path "$cloud/*" {
  capabilities = ["create", "read", "update", "delete", "list"]
}
EOF
        done
    fi
    
    vault policy write "${TEAM_NAME}-admin" "/tmp/${TEAM_NAME}-admin-policy.hcl"
    log_success "Created team admin policy"
    
    # Create environment-specific policies
    for env in "${ENVIRONMENTS[@]}"; do
        cat > "/tmp/${TEAM_NAME}-${env}-policy.hcl" << EOF
# Access to $env environment secrets
path "secrets/data/$env/*" {
  capabilities = ["create", "read", "update", "delete", "list"]
}

path "secrets/metadata/$env/*" {
  capabilities = ["read", "list", "delete"]
}

# Read shared configuration
path "secrets/data/shared/*" {
  capabilities = ["read"]
}
EOF
        
        # Add database permissions if enabled
        if [[ "$ENABLE_DATABASE_ENGINE" == true ]]; then
            cat >> "/tmp/${TEAM_NAME}-${env}-policy.hcl" << EOF

# Generate $env database credentials
path "database/creds/$env-*" {
  capabilities = ["read"]
}
EOF
        fi
        
        # Add cloud permissions if enabled
        if [[ "$ENABLE_CLOUD_ENGINES" == true ]]; then
            for cloud in azure aws gcp; do
                cat >> "/tmp/${TEAM_NAME}-${env}-policy.hcl" << EOF

# Generate $env $cloud credentials
path "$cloud/creds/$env-*" {
  capabilities = ["read"]
}
EOF
            done
        fi
        
        vault policy write "${TEAM_NAME}-${env}" "/tmp/${TEAM_NAME}-${env}-policy.hcl"
        log_success "Created policy for environment: $env"
    done
    
    # Clean up temporary files
    rm -f "/tmp/${TEAM_NAME}"*-policy.hcl
}

# Setup Kubernetes authentication
setup_kubernetes_auth() {
    log_step "Setting up Kubernetes authentication for $TEAM_NAME"
    
    if [[ "$SKIP_K8S" == true ]] || [[ "$DRY_RUN" == true ]]; then
        log_detail "Skipping Kubernetes authentication setup"
        return
    fi
    
    export VAULT_NAMESPACE="$VAULT_NAMESPACE"
    
    # Enable Kubernetes auth method
    local auth_path="${TEAM_NAME}-k8s"
    if ! vault auth list | grep -q "${auth_path}/"; then
        vault auth enable -path="$auth_path" kubernetes
        log_success "Enabled Kubernetes auth method: $auth_path"
    else
        log_warning "Kubernetes auth method already enabled: $auth_path"
    fi
    
    # Get Kubernetes cluster information
    local k8s_host=$(kubectl config view --raw --minify --flatten -o jsonpath='{.clusters[].cluster.server}')
    local k8s_ca_cert=$(kubectl config view --raw --minify --flatten -o jsonpath='{.clusters[].cluster.certificate-authority-data}' | base64 -d)
    local reviewer_jwt=$(kubectl create token vault-auth -n vault-secrets-operator-system --duration=8760h)
    
    # Configure Kubernetes auth
    vault write "auth/${auth_path}/config" \
        token_reviewer_jwt="$reviewer_jwt" \
        kubernetes_host="$k8s_host" \
        kubernetes_ca_cert="$k8s_ca_cert" \
        issuer="https://kubernetes.default.svc.cluster.local"
    
    log_success "Configured Kubernetes auth method"
    
    # Create Kubernetes roles for each environment
    for i in "${!ENVIRONMENTS[@]}"; do
        local env="${ENVIRONMENTS[$i]}"
        local k8s_ns="${K8S_NAMESPACES[$i]}"
        local ttl="30m"
        local max_ttl="2h"
        
        # Adjust TTL for production
        if [[ "$env" == "prod" ]]; then
            ttl="15m"
            max_ttl="1h"
        elif [[ "$env" == "dev" ]]; then
            ttl="1h"
            max_ttl="4h"
        fi
        
        vault write "auth/${auth_path}/role/$env" \
            bound_service_account_names="*" \
            bound_service_account_namespaces="$k8s_ns" \
            policies="${TEAM_NAME}-${env}" \
            ttl="$ttl" \
            max_ttl="$max_ttl"
        
        log_success "Created Kubernetes role for environment: $env (namespace: $k8s_ns)"
    done
}

# Create Kubernetes namespaces
create_kubernetes_namespaces() {
    log_step "Creating Kubernetes namespaces for $TEAM_NAME"
    
    if [[ "$SKIP_K8S" == true ]]; then
        log_detail "Skipping Kubernetes namespace creation"
        return
    fi
    
    if [[ "$DRY_RUN" == true ]]; then
        log_detail "DRY RUN: Would create Kubernetes namespaces: ${K8S_NAMESPACES[*]}"
        return
    fi
    
    for i in "${!K8S_NAMESPACES[@]}"; do
        local k8s_ns="${K8S_NAMESPACES[$i]}"
        local env="${ENVIRONMENTS[$i]}"
        
        # Create namespace
        kubectl create namespace "$k8s_ns" --dry-run=client -o yaml | kubectl apply -f -
        
        # Apply labels
        kubectl label namespace "$k8s_ns" vault-namespace="$VAULT_NAMESPACE" --overwrite
        kubectl label namespace "$k8s_ns" environment="$env" --overwrite
        kubectl label namespace "$k8s_ns" team="$TEAM_NAME" --overwrite
        kubectl label namespace "$k8s_ns" managed-by="vault-team-onboarding" --overwrite
        
        log_success "Created Kubernetes namespace: $k8s_ns"
    done
}

# Deploy Vault Secrets Operator resources
deploy_vault_secrets_operator_resources() {
    log_step "Deploying Vault Secrets Operator resources for $TEAM_NAME"
    
    if [[ "$SKIP_K8S" == true ]]; then
        log_detail "Skipping Vault Secrets Operator resource deployment"
        return
    fi
    
    if [[ "$DRY_RUN" == true ]]; then
        log_detail "DRY RUN: Would deploy Vault Secrets Operator resources"
        return
    fi
    
    for i in "${!K8S_NAMESPACES[@]}"; do
        local k8s_ns="${K8S_NAMESPACES[$i]}"
        local env="${ENVIRONMENTS[$i]}"
        
        # Create VaultConnection and VaultAuth resources
        cat << EOF | kubectl apply -f -
apiVersion: secrets.hashicorp.com/v1beta1
kind: VaultConnection
metadata:
  name: ${TEAM_NAME}-vault
  namespace: $k8s_ns
  labels:
    team: $TEAM_NAME
    environment: $env
spec:
  address: "$VAULT_ADDR"
  vaultNamespace: "$VAULT_NAMESPACE"
  skipTLSVerify: false
---
apiVersion: secrets.hashicorp.com/v1beta1
kind: VaultAuth
metadata:
  name: ${TEAM_NAME}-${env}-auth
  namespace: $k8s_ns
  labels:
    team: $TEAM_NAME
    environment: $env
spec:
  vaultConnectionRef: ${TEAM_NAME}-vault
  method: kubernetes
  mount: ${TEAM_NAME}-k8s
  kubernetes:
    role: $env
    serviceAccount: default
EOF
        
        log_success "Deployed Vault Secrets Operator resources for environment: $env"
    done
}

# Setup OIDC authentication
setup_oidc_auth() {
    if [[ "$ENABLE_OIDC" != true ]]; then
        return
    fi
    
    log_step "Setting up OIDC authentication for $TEAM_NAME"
    
    if [[ "$DRY_RUN" == true ]]; then
        log_detail "DRY RUN: Would setup OIDC authentication"
        return
    fi
    
    export VAULT_NAMESPACE="$VAULT_NAMESPACE"
    
    # Enable OIDC auth method
    local oidc_path="${TEAM_NAME}-oidc"
    if ! vault auth list | grep -q "${oidc_path}/"; then
        vault auth enable -path="$oidc_path" oidc
        log_success "Enabled OIDC auth method: $oidc_path"
    else
        log_warning "OIDC auth method already enabled: $oidc_path"
    fi
    
    # Configure OIDC
    vault write "auth/${oidc_path}/config" \
        oidc_discovery_url="$OIDC_DISCOVERY_URL" \
        oidc_client_id="$OIDC_CLIENT_ID" \
        oidc_client_secret="$OIDC_CLIENT_SECRET" \
        default_role="${TEAM_NAME}-member"
    
    # Create OIDC roles
    vault write "auth/${oidc_path}/role/${TEAM_NAME}-admin" \
        bound_audiences="$OIDC_CLIENT_ID" \
        allowed_redirect_uris="${VAULT_ADDR}/ui/vault/auth/${oidc_path}/oidc/callback" \
        user_claim="sub" \
        policies="${TEAM_NAME}-admin"
    
    vault write "auth/${oidc_path}/role/${TEAM_NAME}-member" \
        bound_audiences="$OIDC_CLIENT_ID" \
        allowed_redirect_uris="${VAULT_ADDR}/ui/vault/auth/${oidc_path}/oidc/callback" \
        user_claim="sub" \
        policies="${TEAM_NAME}-dev"
    
    log_success "Configured OIDC authentication"
}

# Generate team documentation
generate_documentation() {
    log_step "Generating team documentation"
    
    local doc_file="/tmp/${TEAM_NAME}-onboarding-summary.md"
    
    cat > "$doc_file" << EOF
# Team $TEAM_NAME - Vault Onboarding Summary

Generated on: $(date)

## Vault Configuration

**Vault Namespace:** \`$VAULT_NAMESPACE\`
**Vault Address:** \`$VAULT_ADDR\`

## Environments and Namespaces

EOF
    
    for i in "${!ENVIRONMENTS[@]}"; do
        local env="${ENVIRONMENTS[$i]}"
        local k8s_ns="${K8S_NAMESPACES[$i]}"
        cat >> "$doc_file" << EOF
- **$env**: Kubernetes namespace \`$k8s_ns\`
EOF
    done
    
    cat >> "$doc_file" << EOF

## Authentication Methods

EOF
    
    if [[ "$SKIP_K8S" != true ]]; then
        cat >> "$doc_file" << EOF
### Kubernetes Authentication
- **Auth Path:** \`${TEAM_NAME}-k8s\`
- **Roles:** $(IFS=', '; echo "${ENVIRONMENTS[*]}")

EOF
    fi
    
    if [[ "$ENABLE_OIDC" == true ]]; then
        cat >> "$doc_file" << EOF
### OIDC Authentication
- **Auth Path:** \`${TEAM_NAME}-oidc\`
- **Discovery URL:** \`$OIDC_DISCOVERY_URL\`
- **Client ID:** \`$OIDC_CLIENT_ID\`
- **Roles:** \`${TEAM_NAME}-admin\`, \`${TEAM_NAME}-member\`

EOF
    fi
    
    cat >> "$doc_file" << EOF
## Policies

EOF
    
    for env in "${ENVIRONMENTS[@]}"; do
        cat >> "$doc_file" << EOF
- **${TEAM_NAME}-${env}:** Access to $env environment secrets
EOF
    done
    
    cat >> "$doc_file" << EOF
- **${TEAM_NAME}-admin:** Full administrative access to team namespace

## Secrets Engines

- **KV v2:** \`secrets/\` (enabled)
EOF
    
    if [[ "$ENABLE_DATABASE_ENGINE" == true ]]; then
        cat >> "$doc_file" << EOF
- **Database:** \`database/\` (enabled)
EOF
    fi
    
    if [[ "$ENABLE_CLOUD_ENGINES" == true ]]; then
        cat >> "$doc_file" << EOF
- **Azure:** \`azure/\` (enabled)
- **AWS:** \`aws/\` (enabled)
- **GCP:** \`gcp/\` (enabled)
EOF
    fi
    
    cat >> "$doc_file" << EOF

## Example Usage

### Store a secret (dev environment)
\`\`\`bash
export VAULT_NAMESPACE="$VAULT_NAMESPACE"
vault kv put secrets/dev/myapp/config \\
    database_url="postgres://localhost:5432/myapp" \\
    api_key="dev-api-key-12345"
\`\`\`

### Retrieve a secret
\`\`\`bash
vault kv get secrets/dev/myapp/config
\`\`\`

### Kubernetes Secret Example
\`\`\`yaml
apiVersion: secrets.hashicorp.com/v1beta1
kind: VaultStaticSecret
metadata:
  name: myapp-config
  namespace: ${TEAM_NAME}-dev
spec:
  type: kv-v2
  mount: secrets
  path: dev/myapp/config
  destination:
    name: myapp-config
    create: true
  vaultAuthRef: ${TEAM_NAME}-dev-auth
\`\`\`

## Next Steps

1. Configure application-specific secrets in Vault
2. Set up database and cloud provider configurations if enabled
3. Deploy applications using the Vault Secrets Operator
4. Configure monitoring and alerting for the team namespace

## Support

For questions or issues, contact the Platform Engineering team.
EOF
    
    log_success "Documentation generated: $doc_file"
    
    if [[ "$DRY_RUN" != true ]]; then
        cat "$doc_file"
    fi
}

# Main execution
main() {
    echo "========================================"
    echo "   Vault Team Onboarding Script"
    echo "========================================"
    echo ""
    
    parse_args "$@"
    
    log_info "Onboarding team: $TEAM_NAME"
    log_info "Environments: ${ENVIRONMENTS[*]}"
    log_info "Vault namespace: $VAULT_NAMESPACE"
    log_info "Kubernetes namespaces: ${K8S_NAMESPACES[*]}"
    
    if [[ "$DRY_RUN" == true ]]; then
        log_warning "DRY RUN MODE - No changes will be made"
    fi
    
    echo ""
    
    check_prerequisites
    create_vault_namespace
    enable_secrets_engines
    create_team_policies
    setup_kubernetes_auth
    create_kubernetes_namespaces
    deploy_vault_secrets_operator_resources
    setup_oidc_auth
    generate_documentation
    
    echo ""
    log_success "Team $TEAM_NAME onboarded successfully!"
    
    if [[ "$DRY_RUN" != true ]]; then
        echo ""
        echo "Summary:"
        echo "- Vault namespace: $VAULT_NAMESPACE"
        echo "- Environments: ${ENVIRONMENTS[*]}"
        echo "- Kubernetes namespaces: ${K8S_NAMESPACES[*]}"
        echo "- Documentation: /tmp/${TEAM_NAME}-onboarding-summary.md"
    fi
}

# Execute main function with all arguments
main "$@"