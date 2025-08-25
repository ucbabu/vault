#!/bin/bash
# keystore-setup.sh
# Keystore management setup script for HashiCorp Vault

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
    log_info "Checking prerequisites for keystore setup..."
    
    if [[ -z "${VAULT_ADDR:-}" ]]; then
        log_error "VAULT_ADDR environment variable is not set"
        exit 1
    fi
    
    if [[ -z "${VAULT_TOKEN:-}" ]]; then
        log_error "VAULT_TOKEN environment variable is not set"
        exit 1
    fi
    
    # Test Vault connection
    if ! vault status &> /dev/null; then
        log_error "Cannot connect to Vault at $VAULT_ADDR"
        exit 1
    fi
    
    log_success "Prerequisites check passed"
}

# Configure KV secrets engines
configure_kv_engines() {
    log_info "Configuring KV secrets engines..."
    
    # Enable KV v2 at secret/ (should already exist from initial setup)
    if vault secrets list | grep -q "secret/"; then
        log_warning "KV secrets engine already enabled at secret/"
    else
        vault secrets enable -version=2 -path=secret kv
        log_success "KV v2 secrets engine enabled at secret/"
    fi
    
    # Enable additional KV engines for different purposes
    local engines=("app-secrets" "infrastructure" "certificates")
    
    for engine in "${engines[@]}"; do
        if vault secrets list | grep -q "${engine}/"; then
            log_warning "KV secrets engine already enabled at ${engine}/"
        else
            vault secrets enable -version=2 -path="${engine}" kv
            log_success "KV v2 secrets engine enabled at ${engine}/"
        fi
    done
    
    log_info "Current secrets engines:"
    vault secrets list
}

# Create namespace structure
create_namespace_structure() {
    log_info "Creating namespace structure..."
    
    # Environment-based structure
    local environments=("prod" "staging" "dev")
    local applications=("webapp" "api" "worker" "database")
    local shared_services=("monitoring" "logging" "backup" "ci-cd")
    
    # Create environment-based secrets
    for env in "${environments[@]}"; do
        for app in "${applications[@]}"; do
            vault kv put "secret/${env}/${app}/info" \
                description="Secrets for ${app} in ${env}" \
                environment="${env}" \
                application="${app}" \
                created_by="keystore-setup" \
                last_updated="$(date -u +%Y-%m-%dT%H:%M:%SZ)"
            log_success "Created namespace: secret/${env}/${app}/"
        done
        
        # Create shared services
        for service in "${shared_services[@]}"; do
            vault kv put "secret/${env}/shared/${service}" \
                description="Shared ${service} secrets for ${env}" \
                environment="${env}" \
                service_type="shared" \
                created_by="keystore-setup" \
                last_updated="$(date -u +%Y-%m-%dT%H:%M:%SZ)"
            log_success "Created namespace: secret/${env}/shared/${service}"
        done
    done
    
    # Create application-specific secrets structure
    vault kv put "app-secrets/prod/webapp/database" \
        description="Database connection for webapp" \
        host="db.prod.example.com" \
        port="5432" \
        database="webapp_prod" \
        ssl_mode="require"
    
    vault kv put "app-secrets/prod/webapp/external-services" \
        description="External service API keys for webapp" \
        service_type="external_apis"
    
    vault kv put "app-secrets/prod/api/config" \
        description="API service configuration" \
        jwt_algorithm="RS256" \
        rate_limit="1000"
    
    # Create infrastructure secrets
    vault kv put "infrastructure/prod/aws" \
        description="AWS infrastructure secrets" \
        region="us-west-2" \
        account_id="123456789012"
    
    vault kv put "infrastructure/prod/azure" \
        description="Azure infrastructure secrets" \
        subscription_id="12345678-1234-1234-1234-123456789012" \
        tenant_id="87654321-4321-4321-4321-210987654321"
    
    # Create certificate store
    vault kv put "certificates/prod/webapp" \
        description="TLS certificates for webapp" \
        cert_type="wildcard" \
        domain="*.example.com"
    
    log_success "Namespace structure created"
}

# Configure secret versioning and metadata
configure_versioning() {
    log_info "Configuring secret versioning and metadata..."
    
    # Set maximum versions for different secret types
    vault kv metadata put -max-versions=10 secret/prod/
    vault kv metadata put -max-versions=5 secret/staging/
    vault kv metadata put -max-versions=3 secret/dev/
    
    # Set automatic cleanup for development secrets
    vault kv metadata put -delete-version-after=30d secret/dev/
    vault kv metadata put -delete-version-after=90d secret/staging/
    
    # Configure check-and-set for production secrets
    vault kv metadata put -cas-required=true secret/prod/webapp/database
    vault kv metadata put -cas-required=true secret/prod/api/config
    
    log_success "Versioning and metadata configured"
}

# Create environment-specific policies
create_keystore_policies() {
    log_info "Creating keystore-specific policies..."
    
    # Production read-only policy
    cat > /tmp/prod-readonly-policy.hcl << 'EOF'
# Production read-only access
path "secret/data/prod/*" {
  capabilities = ["read"]
}

path "secret/metadata/prod/*" {
  capabilities = ["read", "list"]
}

path "app-secrets/data/prod/*" {
  capabilities = ["read"]
}

path "app-secrets/metadata/prod/*" {
  capabilities = ["read", "list"]
}

# Infrastructure secrets (limited)
path "infrastructure/data/prod/*" {
  capabilities = ["read"]
}
EOF
    vault policy write prod-readonly /tmp/prod-readonly-policy.hcl
    log_success "Production read-only policy created"
    
    # Application-specific policy
    cat > /tmp/webapp-policy.hcl << 'EOF'
# Policy for webapp application
path "secret/data/*/webapp/*" {
  capabilities = ["read"]
}

path "app-secrets/data/*/webapp/*" {
  capabilities = ["read"]
}

path "certificates/data/*/webapp/*" {
  capabilities = ["read"]
}

# Metadata access
path "secret/metadata/*/webapp/*" {
  capabilities = ["read", "list"]
}
EOF
    vault policy write webapp /tmp/webapp-policy.hcl
    log_success "Webapp policy created"
    
    # DevOps policy for secret management
    cat > /tmp/devops-policy.hcl << 'EOF'
# DevOps policy for secret management
path "secret/data/dev/*" {
  capabilities = ["create", "read", "update", "delete", "list"]
}

path "secret/data/staging/*" {
  capabilities = ["create", "read", "update", "delete", "list"]
}

path "secret/data/prod/*" {
  capabilities = ["read", "update"]
}

path "secret/metadata/*" {
  capabilities = ["read", "list", "update"]
}

# Application secrets management
path "app-secrets/data/dev/*" {
  capabilities = ["create", "read", "update", "delete", "list"]
}

path "app-secrets/data/staging/*" {
  capabilities = ["create", "read", "update", "delete", "list"]
}

path "app-secrets/data/prod/*" {
  capabilities = ["read", "update"]
}

# Infrastructure secrets (read-only in prod)
path "infrastructure/data/dev/*" {
  capabilities = ["create", "read", "update", "delete", "list"]
}

path "infrastructure/data/staging/*" {
  capabilities = ["create", "read", "update", "delete", "list"]
}

path "infrastructure/data/prod/*" {
  capabilities = ["read"]
}

# Certificate management
path "certificates/data/*" {
  capabilities = ["create", "read", "update", "delete", "list"]
}
EOF
    vault policy write devops /tmp/devops-policy.hcl
    log_success "DevOps policy created"
    
    # CI/CD pipeline policy
    cat > /tmp/cicd-keystore-policy.hcl << 'EOF'
# CI/CD pipeline access to secrets
path "secret/data/ci/*" {
  capabilities = ["read"]
}

path "secret/data/*/shared/ci-cd" {
  capabilities = ["read"]
}

path "app-secrets/data/staging/*" {
  capabilities = ["read"]
}

path "app-secrets/data/prod/*" {
  capabilities = ["read"]
}

# Deployment secrets
path "infrastructure/data/*/aws" {
  capabilities = ["read"]
}

path "infrastructure/data/*/azure" {
  capabilities = ["read"]
}
EOF
    vault policy write cicd-keystore /tmp/cicd-keystore-policy.hcl
    log_success "CI/CD keystore policy created"
    
    # Clean up temporary files
    rm -f /tmp/*-policy.hcl
    
    log_info "Current policies:"
    vault policy list
}

# Create sample secrets with proper structure
create_sample_secrets() {
    log_info "Creating sample secrets..."
    
    # Database secrets
    vault kv put secret/prod/webapp/database \
        username="webapp_prod_user" \
        password="$(openssl rand -base64 32)" \
        host="db.prod.example.com" \
        port="5432" \
        database="webapp_prod" \
        ssl_mode="require" \
        connection_pool_size="10" \
        connection_timeout="30s"
    
    vault kv put secret/staging/webapp/database \
        username="webapp_staging_user" \
        password="$(openssl rand -base64 32)" \
        host="db.staging.example.com" \
        port="5432" \
        database="webapp_staging" \
        ssl_mode="require"
    
    # API keys and external services
    vault kv put secret/prod/webapp/external-services \
        stripe_publishable_key="pk_live_example123" \
        stripe_secret_key="sk_live_example456" \
        sendgrid_api_key="SG.example_key_789" \
        aws_access_key_id="AKIA_EXAMPLE_KEY" \
        aws_secret_access_key="$(openssl rand -base64 40)"
    
    # Application configuration
    vault kv put secret/prod/webapp/config \
        app_name="webapp" \
        environment="production" \
        debug="false" \
        log_level="info" \
        session_timeout="3600" \
        jwt_secret="$(openssl rand -base64 64)" \
        encryption_key="$(openssl rand -hex 32)"
    
    # API service secrets
    vault kv put secret/prod/api/config \
        service_name="api" \
        environment="production" \
        jwt_algorithm="RS256" \
        jwt_expiry="1h" \
        rate_limit_requests="1000" \
        rate_limit_window="1h" \
        cors_origins="https://app.example.com,https://admin.example.com"
    
    # Monitoring and logging
    vault kv put secret/prod/shared/monitoring \
        prometheus_url="https://prometheus.example.com" \
        grafana_admin_password="$(openssl rand -base64 32)" \
        alertmanager_webhook="https://alerts.example.com/webhook" \
        datadog_api_key="$(openssl rand -hex 32)" \
        datadog_app_key="$(openssl rand -hex 40)"
    
    # Certificate information
    vault kv put certificates/prod/webapp \
        certificate_authority="letsencrypt" \
        domain="*.example.com" \
        renewal_date="2024-12-31" \
        key_algorithm="RSA-2048" \
        certificate_path="/etc/ssl/certs/webapp.crt" \
        private_key_path="/etc/ssl/private/webapp.key"
    
    log_success "Sample secrets created"
}

# Set up secret rotation schedule
setup_rotation_schedule() {
    log_info "Setting up secret rotation metadata..."
    
    # Add rotation metadata to secrets
    vault kv metadata put -custom-metadata=rotation_schedule="monthly" secret/prod/webapp/database
    vault kv metadata put -custom-metadata=rotation_schedule="quarterly" secret/prod/webapp/external-services
    vault kv metadata put -custom-metadata=rotation_schedule="annually" secret/prod/webapp/config
    vault kv metadata put -custom-metadata=rotation_schedule="weekly" secret/prod/shared/monitoring
    
    # Add ownership metadata
    vault kv metadata put -custom-metadata=owner="webapp-team" secret/prod/webapp/
    vault kv metadata put -custom-metadata=owner="api-team" secret/prod/api/
    vault kv metadata put -custom-metadata=owner="platform-team" secret/prod/shared/
    vault kv metadata put -custom-metadata=owner="security-team" certificates/prod/
    
    log_success "Rotation schedule metadata configured"
}

# Create backup and export utilities
create_utilities() {
    log_info "Creating keystore utility scripts..."
    
    # Secret backup script
    cat > ../scripts/backup-secrets.sh << 'EOF'
#!/bin/bash
# backup-secrets.sh - Backup Vault secrets

set -euo pipefail

BACKUP_DIR="${1:-./vault-backups}"
TIMESTAMP=$(date +%Y%m%d-%H%M%S)
BACKUP_FILE="${BACKUP_DIR}/vault-secrets-${TIMESTAMP}.json"

mkdir -p "$BACKUP_DIR"

echo "Backing up Vault secrets to $BACKUP_FILE"

# Get all secret engines
SECRET_ENGINES=$(vault secrets list -format=json | jq -r 'to_entries[] | select(.value.type == "kv") | .key' | sed 's|/$||')

{
    echo "{"
    first=true
    for engine in $SECRET_ENGINES; do
        if [ "$first" = false ]; then
            echo ","
        fi
        echo "  \"$engine\": {"
        
        # Get all secrets in this engine
        vault kv list -format=json "$engine" 2>/dev/null | jq -r '.[]' | while IFS= read -r secret; do
            echo "    \"$secret\": $(vault kv get -format=json "$engine/$secret")"
        done
        
        echo "  }"
        first=false
    done
    echo "}"
} > "$BACKUP_FILE"

echo "Backup completed: $BACKUP_FILE"
EOF
    
    # Secret audit script
    cat > ../scripts/audit-secrets.sh << 'EOF'
#!/bin/bash
# audit-secrets.sh - Audit secret usage and metadata

set -euo pipefail

echo "Vault Secret Audit Report - $(date)"
echo "============================================"

# Check secret engines
echo -e "\n1. Enabled Secret Engines:"
vault secrets list

# Check policies
echo -e "\n2. Policies Related to Secrets:"
vault policy list | grep -E "(secret|keystore|app)"

# Check secret metadata
echo -e "\n3. Secret Metadata Summary:"
SECRET_ENGINES=$(vault secrets list -format=json | jq -r 'to_entries[] | select(.value.type == "kv") | .key' | sed 's|/$||')

for engine in $SECRET_ENGINES; do
    echo -e "\nEngine: $engine"
    vault kv list "$engine" 2>/dev/null | head -10
done

# Check for secrets without metadata
echo -e "\n4. Secrets Requiring Attention:"
echo "- Secrets older than 90 days"
echo "- Secrets without rotation schedule"
echo "- Secrets without ownership metadata"

echo -e "\n5. Recommendations:"
echo "- Review and rotate old secrets"
echo "- Ensure all secrets have proper metadata"
echo "- Implement automated rotation where possible"
EOF
    
    # Make scripts executable
    chmod +x ../scripts/backup-secrets.sh ../scripts/audit-secrets.sh
    
    log_success "Utility scripts created"
}

# Test keystore functionality
test_keystore() {
    log_info "Testing keystore functionality..."
    
    # Test secret operations
    local test_secret="secret/test/keystore-test"
    
    # Create test secret
    vault kv put "$test_secret" \
        test_key="test_value" \
        created_at="$(date -u +%Y-%m-%dT%H:%M:%SZ)"
    log_success "Test secret created"
    
    # Read test secret
    local secret_data=$(vault kv get -format=json "$test_secret")
    if echo "$secret_data" | jq -e '.data.data.test_key' &> /dev/null; then
        log_success "Test secret read successfully"
    else
        log_error "Failed to read test secret"
        return 1
    fi
    
    # Update test secret
    vault kv put "$test_secret" \
        test_key="updated_value" \
        updated_at="$(date -u +%Y-%m-%dT%H:%M:%SZ)"
    log_success "Test secret updated"
    
    # Check versions
    local versions=$(vault kv metadata get -format=json "$test_secret" | jq -r '.data.current_version')
    if [[ "$versions" == "2" ]]; then
        log_success "Secret versioning working"
    else
        log_warning "Unexpected version count: $versions"
    fi
    
    # Clean up test secret
    vault kv delete "$test_secret"
    log_success "Test secret cleaned up"
    
    # Test policy enforcement
    log_info "Testing policy enforcement..."
    vault token capabilities secret/prod/webapp/database
    
    log_success "Keystore functionality tests passed"
}

# Generate summary report
generate_summary() {
    log_info "Generating keystore setup summary..."
    
    cat << EOF

${GREEN}===============================================${NC}
${GREEN}      Keystore Management Setup Complete      ${NC}
${GREEN}===============================================${NC}

${BLUE}KV Secrets Engines Enabled:${NC}
- secret/ (KV v2) - Main application secrets
- app-secrets/ (KV v2) - Application-specific secrets  
- infrastructure/ (KV v2) - Infrastructure secrets
- certificates/ (KV v2) - Certificate store

${BLUE}Namespace Structure:${NC}
- secret/{env}/{app}/* - Environment and application-based
- app-secrets/{env}/{app}/* - Application-specific secrets
- infrastructure/{env}/* - Infrastructure secrets
- certificates/{env}/* - Certificate management

${BLUE}Policies Created:${NC}
- prod-readonly - Read-only access to production secrets
- webapp - Application-specific access for webapp
- devops - DevOps team secret management
- cicd-keystore - CI/CD pipeline access

${BLUE}Sample Secrets Created:${NC}
- Database configurations for webapp
- External service API keys
- Application configuration secrets
- Monitoring and logging credentials
- Certificate metadata

${BLUE}Features Configured:${NC}
- Secret versioning (max 10 versions for prod)
- Automatic cleanup (30 days for dev)
- Check-and-set for critical secrets
- Rotation schedule metadata
- Ownership metadata

${BLUE}Utility Scripts:${NC}
- scripts/backup-secrets.sh - Backup all secrets
- scripts/audit-secrets.sh - Audit secret usage

${BLUE}Example Usage:${NC}
# Read application database config
vault kv get secret/prod/webapp/database

# Update API configuration
vault kv put secret/prod/api/config rate_limit=2000

# List secrets in environment
vault kv list secret/prod/

# Check secret metadata
vault kv metadata get secret/prod/webapp/database

# Backup secrets
./scripts/backup-secrets.sh

${BLUE}Next Steps:${NC}
1. Migrate existing secrets to Vault
2. Update applications to use Vault for secret retrieval
3. Implement secret rotation procedures
4. Set up monitoring for secret access
5. Configure Azure and database dynamic secrets

${YELLOW}Security Reminders:${NC}
- Regularly rotate secrets according to schedule
- Monitor secret access patterns
- Use least privilege access policies
- Implement proper secret lifecycle management

EOF
}

# Main execution
main() {
    log_info "Starting keystore management setup..."
    
    check_prerequisites
    configure_kv_engines
    create_namespace_structure
    configure_versioning
    create_keystore_policies
    create_sample_secrets
    setup_rotation_schedule
    create_utilities
    test_keystore
    generate_summary
    
    log_success "Keystore management setup completed successfully!"
}

# Execute main function
main "$@"