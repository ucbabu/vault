#!/bin/bash
# kubernetes-vault-jwt-setup.sh
# Enhanced Kubernetes-Vault integration with JWT/OIDC authentication for no-connectivity scenarios

set -euo pipefail

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

log_info() { echo -e "${BLUE}[INFO]${NC} $1"; }
log_success() { echo -e "${GREEN}[SUCCESS]${NC} $1"; }
log_warning() { echo -e "${YELLOW}[WARNING]${NC} $1"; }
log_error() { echo -e "${RED}[ERROR]${NC} $1"; }

# Configuration variables
VAULT_SECRETS_OPERATOR_NAMESPACE="vault-secrets-operator-system"
TEST_NAMESPACE="webapp"
JWT_AUTH_METHOD="kubernetes-jwt"
MANUAL_CONFIG_MODE=false
SKIP_CONNECTIVITY_TEST=false

# Help function
show_help() {
    cat << EOF
Usage: $0 [OPTIONS]

Enhanced Kubernetes-Vault integration setup with JWT/OIDC authentication support.
Designed to work with HCP Vault when there's no network connectivity to AKS.

OPTIONS:
    -h, --help              Show this help message
    --manual-config         Use manual JWT configuration (no auto-discovery)
    --skip-connectivity     Skip connectivity tests (for air-gapped environments)
    --jwt-auth-path PATH    Custom JWT auth method path (default: kubernetes-jwt)
    --namespace NS          Custom namespace for test resources (default: webapp)
    --operator-ns NS        Custom namespace for Vault Secrets Operator (default: vault-secrets-operator-system)

EXAMPLES:
    # Standard setup with manual configuration (recommended for HCP Vault)
    $0 --manual-config --skip-connectivity

    # Custom auth path and namespace
    $0 --manual-config --jwt-auth-path aks-jwt --namespace production

PREREQUISITES:
    - VAULT_ADDR and VAULT_TOKEN environment variables set
    - kubectl configured to access your AKS cluster
    - Vault CLI installed and authenticated

AUTHENTICATION METHODS:
    This script sets up JWT/OIDC authentication which eliminates the need for 
    HCP Vault to connect back to your AKS cluster during authentication.
    
    Manual configuration mode fetches the JWKS keys from your cluster and 
    configures them statically in Vault, completely removing network dependencies.

EOF
}

# Parse command line arguments
parse_arguments() {
    while [[ $# -gt 0 ]]; do
        case $1 in
            -h|--help)
                show_help
                exit 0
                ;;
            --manual-config)
                MANUAL_CONFIG_MODE=true
                shift
                ;;
            --skip-connectivity)
                SKIP_CONNECTIVITY_TEST=true
                shift
                ;;
            --jwt-auth-path)
                JWT_AUTH_METHOD="$2"
                shift 2
                ;;
            --namespace)
                TEST_NAMESPACE="$2"
                shift 2
                ;;
            --operator-ns)
                VAULT_SECRETS_OPERATOR_NAMESPACE="$2"
                shift 2
                ;;
            *)
                log_error "Unknown option: $1"
                show_help
                exit 1
                ;;
        esac
    done
}

# Check prerequisites
check_prerequisites() {
    log_info "Checking prerequisites for Kubernetes-Vault JWT integration..."
    
    # Check Vault connection
    if [[ -z "${VAULT_ADDR:-}" ]] || [[ -z "${VAULT_TOKEN:-}" ]]; then
        log_error "VAULT_ADDR and VAULT_TOKEN must be set"
        exit 1
    fi
    
    if ! vault status &> /dev/null; then
        log_error "Cannot connect to Vault"
        exit 1
    fi
    
    # Check kubectl
    if ! command -v kubectl &> /dev/null; then
        log_error "kubectl is not installed"
        exit 1
    fi
    
    if ! kubectl cluster-info &> /dev/null; then
        log_error "kubectl cannot connect to Kubernetes cluster"
        exit 1
    fi
    
    # Check jq for JSON processing
    if ! command -v jq &> /dev/null; then
        log_error "jq is required for JSON processing. Please install jq."
        exit 1
    fi
    
    log_success "Prerequisites check passed"
}

# Get Kubernetes cluster OIDC information
get_kubernetes_oidc_info() {
    log_info "Gathering Kubernetes OIDC configuration..."
    
    # Get cluster server URL
    local k8s_host=$(kubectl config view --raw --minify --flatten -o jsonpath='{.clusters[].cluster.server}')
    local k8s_ca_cert=$(kubectl config view --raw --minify --flatten -o jsonpath='{.clusters[].cluster.certificate-authority-data}' | base64 -d)
    
    log_info "Kubernetes API Server: $k8s_host"
    
    # Check if OIDC discovery is available
    local oidc_discovery_url="${k8s_host}/.well-known/openid_configuration"
    local jwks_uri="${k8s_host}/openid/v1/jwks"
    
    if [[ "$SKIP_CONNECTIVITY_TEST" == "false" ]]; then
        log_info "Testing OIDC discovery endpoints..."
        
        if kubectl get --raw /.well-known/openid_configuration &>/dev/null; then
            log_success "OIDC discovery endpoint accessible"
            echo "$k8s_host" > /tmp/k8s_host.txt
            echo "$oidc_discovery_url" > /tmp/oidc_discovery_url.txt
            echo "$jwks_uri" > /tmp/jwks_uri.txt
        else
            log_warning "OIDC discovery endpoint not accessible. Will use manual configuration."
            MANUAL_CONFIG_MODE=true
        fi
    else
        log_info "Skipping connectivity test as requested"
        echo "$k8s_host" > /tmp/k8s_host.txt
        echo "$oidc_discovery_url" > /tmp/oidc_discovery_url.txt
        echo "$jwks_uri" > /tmp/jwks_uri.txt
    fi
    
    # Store CA certificate
    echo "$k8s_ca_cert" > /tmp/k8s_ca_cert.pem
    
    log_success "Kubernetes OIDC information gathered"
}

# Fetch JWKS keys manually
fetch_jwks_keys() {
    log_info "Fetching JWKS keys from Kubernetes cluster..."
    
    # Fetch JWKS using kubectl
    local jwks_data
    if jwks_data=$(kubectl get --raw /openid/v1/jwks 2>/dev/null); then
        echo "$jwks_data" > /tmp/jwks.json
        log_success "JWKS keys fetched successfully"
        
        # Display key information
        local key_count=$(echo "$jwks_data" | jq '.keys | length')
        log_info "Found $key_count signing key(s)"
        
        # Show key details
        echo "$jwks_data" | jq -r '.keys[] | "Key ID: \(.kid), Algorithm: \(.alg), Use: \(.use)"' | while read -r line; do
            log_info "$line"
        done
        
        return 0
    else
        log_error "Failed to fetch JWKS keys"
        return 1
    fi
}

# Configure JWT authentication in Vault
configure_jwt_auth() {
    log_info "Configuring JWT authentication in Vault..."
    
    # Enable JWT auth method if not already enabled
    if ! vault auth list | grep -q "${JWT_AUTH_METHOD}/"; then
        vault auth enable -path="$JWT_AUTH_METHOD" jwt
        log_success "JWT auth method enabled at path: $JWT_AUTH_METHOD"
    else
        log_warning "JWT auth method already enabled at path: $JWT_AUTH_METHOD"
    fi
    
    local k8s_host=$(cat /tmp/k8s_host.txt)
    local oidc_discovery_url=$(cat /tmp/oidc_discovery_url.txt)
    
    if [[ "$MANUAL_CONFIG_MODE" == "true" ]]; then
        log_info "Configuring JWT auth with manual JWKS configuration..."
        
        # Fetch JWKS keys
        if ! fetch_jwks_keys; then
            log_error "Failed to fetch JWKS keys for manual configuration"
            exit 1
        fi
        
        # Configure JWT auth with manual JWKS
        vault write auth/"$JWT_AUTH_METHOD"/config \
            bound_issuer="https://kubernetes.default.svc.cluster.local" \
            jwks_url="$k8s_host/openid/v1/jwks" \
            jwks_ca_pem=@/tmp/k8s_ca_cert.pem \
            jwt_validation_pubkeys=@/tmp/jwks.json
            
        log_success "JWT auth configured with manual JWKS"
    else
        log_info "Configuring JWT auth with OIDC discovery..."
        
        # Configure JWT auth with OIDC discovery
        vault write auth/"$JWT_AUTH_METHOD"/config \
            oidc_discovery_url="$oidc_discovery_url" \
            oidc_discovery_ca_pem=@/tmp/k8s_ca_cert.pem \
            bound_issuer="https://kubernetes.default.svc.cluster.local"
            
        log_success "JWT auth configured with OIDC discovery"
    fi
}

# Create comprehensive Vault policies
create_vault_policies() {
    log_info "Creating comprehensive Vault policies for JWT authentication..."
    
    # Create webapp policy
    cat > /tmp/webapp-jwt-policy.hcl << 'EOF'
# Application secrets access
path "secret/data/webapp/*" {
  capabilities = ["read"]
}

path "secret/metadata/webapp/*" {
  capabilities = ["list", "read"]
}

# Shared configuration access
path "secret/data/shared/config" {
  capabilities = ["read"]
}

# Dynamic database credentials
path "database/creds/webapp" {
  capabilities = ["read"]
}

# Token self-inspection
path "auth/token/lookup-self" {
  capabilities = ["read"]
}

path "auth/token/renew-self" {
  capabilities = ["update"]
}
EOF
    vault policy write webapp-jwt-policy /tmp/webapp-jwt-policy.hcl
    
    # Create JWT roles
    vault write auth/"$JWT_AUTH_METHOD"/role/webapp \
        bound_audiences=https://kubernetes.default.svc.cluster.local \
        bound_subject="system:serviceaccount:${TEST_NAMESPACE}:webapp" \
        user_claim=sub \
        policies=webapp-jwt-policy \
        ttl=1h \
        max_ttl=4h
    
    rm -f /tmp/*-jwt-policy.hcl
    log_success "Vault policies and JWT roles created"
}

# Set up test namespace and resources
setup_test_namespace() {
    log_info "Setting up test namespace and resources..."
    
    # Create test namespace
    kubectl create namespace $TEST_NAMESPACE --dry-run=client -o yaml | kubectl apply -f -
    
    # Create service account with proper annotations
    cat <<EOF | kubectl apply -f -
apiVersion: v1
kind: ServiceAccount
metadata:
  name: webapp
  namespace: $TEST_NAMESPACE
  annotations:
    vault.hashicorp.com/auth-method: $JWT_AUTH_METHOD
    vault.hashicorp.com/auth-role: webapp
EOF
    
    # Create test secrets in Vault
    vault kv put secret/webapp/config \
        app_name="webapp" \
        debug="false" \
        log_level="info" \
        api_token="test-api-token-jwt-123" \
        auth_method="jwt"
    
    vault kv put secret/shared/config \
        region="us-west-2" \
        environment="production" \
        monitoring_enabled="true" \
        auth_type="jwt"
    
    log_success "Test namespace and secrets created"
}

# Test JWT authentication
test_jwt_authentication() {
    log_info "Testing JWT authentication..."
    
    # Create a test pod to verify authentication
    cat <<EOF | kubectl apply -f -
apiVersion: v1
kind: Pod
metadata:
  name: jwt-auth-test
  namespace: $TEST_NAMESPACE
spec:
  serviceAccountName: webapp
  containers:
  - name: test
    image: vault:latest
    command: ['sh', '-c', 'sleep 300']
    env:
    - name: VAULT_ADDR
      value: "$VAULT_ADDR"
  restartPolicy: Never
EOF
    
    # Wait for pod to be ready
    kubectl wait --for=condition=Ready pod/jwt-auth-test -n $TEST_NAMESPACE --timeout=60s
    
    # Test authentication inside the pod
    local auth_test_result
    auth_test_result=$(kubectl exec -n $TEST_NAMESPACE jwt-auth-test -- sh -c '
        JWT_TOKEN=$(cat /var/run/secrets/kubernetes.io/serviceaccount/token)
        vault write -field=token auth/'$JWT_AUTH_METHOD'/login role=webapp jwt=$JWT_TOKEN
    ' 2>&1) || true
    
    if [[ "$auth_test_result" =~ ^hvs\. ]]; then
        log_success "JWT authentication test successful"
        log_info "Vault token received: ${auth_test_result:0:20}..."
    else
        log_error "JWT authentication test failed: $auth_test_result"
    fi
    
    # Clean up test pod
    kubectl delete pod jwt-auth-test -n $TEST_NAMESPACE --ignore-not-found=true
}

# Verify setup
verify_setup() {
    log_info "Verifying JWT authentication setup..."
    
    # Check Vault auth method
    if vault auth list | grep -q "${JWT_AUTH_METHOD}/"; then
        log_success "✓ JWT auth method configured"
    else
        log_error "✗ JWT auth method not found"
    fi
    
    # Check policies
    if vault policy list | grep -q "^webapp-jwt-policy$"; then
        log_success "✓ Policy webapp-jwt-policy created"
    else
        log_error "✗ Policy webapp-jwt-policy missing"
    fi
    
    # Check roles
    if vault read auth/"$JWT_AUTH_METHOD"/role/webapp &>/dev/null; then
        log_success "✓ JWT role webapp configured"
    else
        log_error "✗ JWT role webapp missing"
    fi
    
    # Check Kubernetes resources
    if kubectl get namespace $TEST_NAMESPACE &>/dev/null; then
        log_success "✓ Test namespace created"
    else
        log_error "✗ Test namespace missing"
    fi
    
    if kubectl get serviceaccount webapp -n $TEST_NAMESPACE &>/dev/null; then
        log_success "✓ Service account created"
    else
        log_error "✗ Service account missing"
    fi
}

# Generate configuration summary
generate_summary() {
    log_info "Generating configuration summary..."
    
    cat > jwt-auth-config-summary.md << EOF
# JWT Authentication Configuration Summary

## Configuration Details
- **Auth Method Path**: $JWT_AUTH_METHOD
- **Configuration Mode**: $([ "$MANUAL_CONFIG_MODE" == "true" ] && echo "Manual JWKS (No connectivity required)" || echo "OIDC Discovery")
- **Bound Issuer**: https://kubernetes.default.svc.cluster.local
- **Test Namespace**: $TEST_NAMESPACE

## Key Benefits for HCP Vault
✅ **No ongoing connectivity required** from HCP Vault to AKS during authentication\n✅ **High performance** - JWT validation happens locally in Vault\n✅ **Scalable** - No API calls to Kubernetes for each authentication\n✅ **Reliable** - No network dependency during runtime

## Testing Commands
\`\`\`bash
# Test authentication from a pod:
kubectl run jwt-test --rm -i --tty --serviceaccount=webapp -n $TEST_NAMESPACE --image=vault:latest -- sh

# Inside the pod:
JWT_TOKEN=\$(cat /var/run/secrets/kubernetes.io/serviceaccount/token)
vault write -field=token auth/$JWT_AUTH_METHOD/login role=webapp jwt=\$JWT_TOKEN
\`\`\`

$([ "$MANUAL_CONFIG_MODE" == "true" ] && cat << 'EOL'
## Manual JWKS Update Process
When Kubernetes rotates signing keys, update Vault:

```bash
# 1. Fetch current keys
kubectl get --raw /openid/v1/jwks > new-jwks.json

# 2. Update Vault configuration
vault write auth/$JWT_AUTH_METHOD/config \
  bound_issuer="https://kubernetes.default.svc.cluster.local" \
  jwt_validation_pubkeys=@new-jwks.json
```
EOL
)
EOF
    
    log_success "Configuration summary generated: jwt-auth-config-summary.md"
}

# Main execution function
main() {
    log_info "Starting Enhanced Kubernetes-Vault JWT Integration Setup"
    
    parse_arguments "$@"
    check_prerequisites
    get_kubernetes_oidc_info
    configure_jwt_auth
    create_vault_policies
    setup_test_namespace
    test_jwt_authentication
    verify_setup
    generate_summary
    
    log_success "JWT authentication setup completed successfully!"
    log_info "Review the configuration summary: jwt-auth-config-summary.md"
    
    if [[ "$MANUAL_CONFIG_MODE" == "true" ]]; then
        log_success "✅ Manual JWKS configuration active - no connectivity required from HCP Vault to AKS"
    else
        log_warning "⚠ OIDC discovery mode requires periodic connectivity from HCP Vault to AKS"
        log_info "Consider using --manual-config for air-gapped deployments"
    fi
}

# Run main function if script is executed directly
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    main "$@"
fi