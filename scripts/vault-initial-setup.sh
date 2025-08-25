#!/bin/bash
# vault-initial-setup.sh
# Initial configuration script for HashiCorp Vault Cloud

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

# Check prerequisites
check_prerequisites() {
    log_info "Checking prerequisites..."
    
    # Check if vault CLI is installed
    if ! command -v vault &> /dev/null; then
        log_error "Vault CLI is not installed. Please install it first."
        log_info "Install with: curl -fsSL https://apt.releases.hashicorp.com/gpg | sudo apt-key add -"
        log_info "sudo apt-add-repository \"deb [arch=amd64] https://apt.releases.hashicorp.com \$(lsb_release -cs) main\""
        log_info "sudo apt-get update && sudo apt-get install vault"
        exit 1
    fi
    
    # Check if jq is installed
    if ! command -v jq &> /dev/null; then
        log_error "jq is not installed. Please install it: sudo apt-get install jq"
        exit 1
    fi
    
    # Check environment variables
    if [[ -z "${VAULT_ADDR:-}" ]]; then
        log_error "VAULT_ADDR environment variable is not set"
        exit 1
    fi
    
    if [[ -z "${VAULT_NAMESPACE:-}" ]]; then
        log_error "VAULT_NAMESPACE environment variable is not set"
        exit 1
    fi
    
    if [[ -z "${VAULT_TOKEN:-}" ]]; then
        log_error "VAULT_TOKEN environment variable is not set"
        exit 1
    fi
    
    log_success "Prerequisites check passed"
}

# Test Vault connection
test_vault_connection() {
    log_info "Testing Vault connection..."
    
    if vault status &> /dev/null; then
        log_success "Successfully connected to Vault"
        vault status
    else
        log_error "Failed to connect to Vault"
        exit 1
    fi
}

# Enable audit logging
enable_audit_logging() {
    log_info "Enabling audit logging..."
    
    # Enable file audit device
    if vault audit list | grep -q "file/"; then
        log_warning "File audit device already enabled"
    else
        vault audit enable file file_path=/vault/logs/audit.log
        log_success "File audit device enabled"
    fi
    
    # Verify audit devices
    log_info "Current audit devices:"
    vault audit list
}

# Create initial policies
create_initial_policies() {
    log_info "Creating initial policies..."
    
    # Admin policy
    cat > /tmp/admin-policy.hcl << 'EOF'
# Admin policy for full Vault access
path "*" {
  capabilities = ["create", "read", "update", "delete", "list", "sudo"]
}
EOF
    vault policy write admin /tmp/admin-policy.hcl
    log_success "Admin policy created"
    
    # Developer policy
    cat > /tmp/developer-policy.hcl << 'EOF'
# Developer policy for application secrets
path "secret/data/apps/*" {
  capabilities = ["create", "read", "update", "delete", "list"]
}

path "secret/metadata/apps/*" {
  capabilities = ["list", "read", "delete"]
}

# Database credentials access
path "database/creds/readonly" {
  capabilities = ["read"]
}

path "database/creds/readwrite" {
  capabilities = ["read"]
}

# Azure credentials access
path "azure/creds/readonly" {
  capabilities = ["read"]
}
EOF
    vault policy write developer /tmp/developer-policy.hcl
    log_success "Developer policy created"
    
    # Operator policy
    cat > /tmp/operator-policy.hcl << 'EOF'
# Operator policy for monitoring and maintenance
path "sys/health" {
  capabilities = ["read"]
}

path "sys/metrics" {
  capabilities = ["read"]
}

path "sys/mounts" {
  capabilities = ["read"]
}

path "auth/*" {
  capabilities = ["read", "list"]
}

path "sys/auth" {
  capabilities = ["read"]
}

path "sys/policies/acl" {
  capabilities = ["list"]
}

path "sys/policies/acl/*" {
  capabilities = ["read"]
}
EOF
    vault policy write operator /tmp/operator-policy.hcl
    log_success "Operator policy created"
    
    # CI/CD policy
    cat > /tmp/cicd-policy.hcl << 'EOF'
# CI/CD policy for automated deployments
path "secret/data/ci/*" {
  capabilities = ["read"]
}

path "secret/data/deploy/*" {
  capabilities = ["read"]
}

path "azure/creds/app-deployer" {
  capabilities = ["read"]
}

path "database/creds/migration" {
  capabilities = ["read"]
}
EOF
    vault policy write cicd /tmp/cicd-policy.hcl
    log_success "CI/CD policy created"
    
    # Clean up temporary files
    rm -f /tmp/*-policy.hcl
    
    # List all policies
    log_info "Current policies:"
    vault policy list
}

# Configure authentication methods
configure_auth_methods() {
    log_info "Configuring authentication methods..."
    
    # Enable userpass auth method for testing
    if vault auth list | grep -q "userpass/"; then
        log_warning "Userpass auth method already enabled"
    else
        vault auth enable userpass
        log_success "Userpass auth method enabled"
    fi
    
    # Create test users
    vault write auth/userpass/users/developer \
        password=developer123 \
        policies=developer \
        ttl=8h \
        max_ttl=24h
    log_success "Developer user created"
    
    vault write auth/userpass/users/operator \
        password=operator123 \
        policies=operator \
        ttl=4h \
        max_ttl=12h
    log_success "Operator user created"
    
    # Note: OIDC and other auth methods require additional configuration
    log_info "Note: Configure OIDC, AWS IAM, or other auth methods as needed"
}

# Enable secrets engines
enable_secrets_engines() {
    log_info "Enabling secrets engines..."
    
    # Enable KV v2 secrets engine
    if vault secrets list | grep -q "secret/"; then
        log_warning "KV secrets engine already enabled at secret/"
    else
        vault secrets enable -version=2 -path=secret kv
        log_success "KV v2 secrets engine enabled at secret/"
    fi
    
    # Enable database secrets engine
    if vault secrets list | grep -q "database/"; then
        log_warning "Database secrets engine already enabled"
    else
        vault secrets enable database
        log_success "Database secrets engine enabled"
    fi
    
    # Enable Azure secrets engine
    if vault secrets list | grep -q "azure/"; then
        log_warning "Azure secrets engine already enabled"
    else
        vault secrets enable azure
        log_success "Azure secrets engine enabled"
    fi
    
    # List all secrets engines
    log_info "Current secrets engines:"
    vault secrets list
}

# Create initial secret structure
create_secret_structure() {
    log_info "Creating initial secret structure..."
    
    # Create namespace structure
    vault kv put secret/prod/shared/info \
        description="Production shared secrets" \
        environment="production" \
        created_by="vault-setup-script"
    
    vault kv put secret/staging/shared/info \
        description="Staging shared secrets" \
        environment="staging" \
        created_by="vault-setup-script"
    
    vault kv put secret/dev/shared/info \
        description="Development shared secrets" \
        environment="development" \
        created_by="vault-setup-script"
    
    # Create CI/CD secrets
    vault kv put secret/ci/shared/info \
        description="CI/CD shared secrets" \
        environment="ci-cd" \
        created_by="vault-setup-script"
    
    log_success "Initial secret structure created"
    
    # List secrets
    log_info "Secret structure:"
    vault kv list secret/
}

# Configure security settings
configure_security() {
    log_info "Configuring security settings..."
    
    # Configure UI security headers
    vault write sys/config/ui \
        header_x_frame_options="DENY" \
        header_x_content_type_options="nosniff" \
        header_referrer_policy="same-origin" \
        header_strict_transport_security="max-age=31536000; includeSubDomains"
    
    log_success "UI security headers configured"
    
    # Configure password policy
    cat > /tmp/password-policy.hcl << 'EOF'
length = 20
rule "charset" {
  charset = "abcdefghijklmnopqrstuvwxyz"
  min_chars = 1
}
rule "charset" {
  charset = "ABCDEFGHIJKLMNOPQRSTUVWXYZ"
  min_chars = 1
}
rule "charset" {
  charset = "0123456789"
  min_chars = 1
}
rule "charset" {
  charset = "!@#$%^&*"
  min_chars = 1
}
EOF
    vault write sys/policies/password/default policy=@/tmp/password-policy.hcl
    log_success "Default password policy configured"
    
    rm -f /tmp/password-policy.hcl
}

# Generate summary report
generate_summary() {
    log_info "Generating setup summary..."
    
    cat << EOF

${GREEN}===============================================${NC}
${GREEN}    Vault Cloud Initial Setup Complete       ${NC}
${GREEN}===============================================${NC}

${BLUE}Vault Information:${NC}
- Address: ${VAULT_ADDR}
- Namespace: ${VAULT_NAMESPACE}
- Status: $(vault status --format=json | jq -r '.sealed // "Unknown"' | sed 's/false/Unsealed/g' | sed 's/true/Sealed/g')

${BLUE}Enabled Features:${NC}
- Audit logging: File audit device
- Secrets engines: KV v2, Database, Azure
- Authentication: Userpass (for testing)
- Policies: admin, developer, operator, cicd

${BLUE}Test Commands:${NC}
# Test developer access
vault login -method=userpass username=developer password=developer123
vault kv get secret/dev/shared/info

# Test operator access  
vault login -method=userpass username=operator password=operator123
vault read sys/health

${BLUE}Next Steps:${NC}
1. Configure OIDC or other production auth methods
2. Set up Azure secrets engine with service principal
3. Configure database connections
4. Set up monitoring and alerting
5. Implement backup procedures

${YELLOW}Security Note:${NC}
- Change default userpass passwords
- Configure production authentication methods
- Review and adjust policies as needed
- Set up network security controls

EOF
}

# Main execution
main() {
    log_info "Starting Vault Cloud initial setup..."
    
    check_prerequisites
    test_vault_connection
    enable_audit_logging
    create_initial_policies
    configure_auth_methods
    enable_secrets_engines
    create_secret_structure
    configure_security
    generate_summary
    
    log_success "Vault Cloud initial setup completed successfully!"
}

# Execute main function
main "$@"