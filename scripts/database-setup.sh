#!/bin/bash
# database-setup.sh
# Database dynamic key rotation setup script for HashiCorp Vault

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

# Check prerequisites
check_prerequisites() {
    log_info "Checking prerequisites..."
    
    if [[ -z "${VAULT_ADDR:-}" ]] || [[ -z "${VAULT_TOKEN:-}" ]]; then
        log_error "VAULT_ADDR and VAULT_TOKEN must be set"
        exit 1
    fi
    
    if ! vault status &> /dev/null; then
        log_error "Cannot connect to Vault"
        exit 1
    fi
    
    log_success "Prerequisites OK"
}

# Configure database secrets engine
configure_database_engine() {
    log_info "Configuring database secrets engine..."
    
    if vault secrets list | grep -q "database/"; then
        log_warning "Database engine already enabled"
    else
        vault secrets enable database
        log_success "Database engine enabled"
    fi
}

# Configure PostgreSQL
configure_postgresql() {
    log_info "Configuring PostgreSQL..."
    
    local host="${POSTGRES_HOST:-postgres.example.com}"
    local user="${POSTGRES_ADMIN_USER:-vault_admin}"
    local pass="${POSTGRES_ADMIN_PASSWORD:-admin_password}"
    local db="${POSTGRES_DATABASE:-vault_db}"
    
    vault write database/config/postgresql \
        plugin_name=postgresql-database-plugin \
        connection_url="postgresql://{{username}}:{{password}}@${host}:5432/${db}?sslmode=require" \
        allowed_roles="readonly,readwrite,webapp" \
        username="$user" \
        password="$pass"
    
    # Create roles
    vault write database/roles/readonly \
        db_name=postgresql \
        creation_statements="CREATE ROLE \"{{name}}\" WITH LOGIN PASSWORD '{{password}}' VALID UNTIL '{{expiration}}'; GRANT SELECT ON ALL TABLES IN SCHEMA public TO \"{{name}}\";" \
        revocation_statements="DROP ROLE IF EXISTS \"{{name}}\";" \
        default_ttl="1h" \
        max_ttl="24h"
    
    vault write database/roles/webapp \
        db_name=postgresql \
        creation_statements="CREATE ROLE \"{{name}}\" WITH LOGIN PASSWORD '{{password}}' VALID UNTIL '{{expiration}}'; GRANT SELECT, INSERT, UPDATE, DELETE ON ALL TABLES IN SCHEMA public TO \"{{name}}\";" \
        revocation_statements="DROP ROLE IF EXISTS \"{{name}}\";" \
        default_ttl="4h" \
        max_ttl="12h"
    
    log_success "PostgreSQL configured"
}

# Configure MySQL  
configure_mysql() {
    log_info "Configuring MySQL..."
    
    local host="${MYSQL_HOST:-mysql.example.com}"
    local user="${MYSQL_ADMIN_USER:-vault_admin}"
    local pass="${MYSQL_ADMIN_PASSWORD:-admin_password}"
    
    vault write database/config/mysql \
        plugin_name=mysql-database-plugin \
        connection_url="{{username}}:{{password}}@tcp(${host}:3306)/" \
        allowed_roles="app,analytics" \
        username="$user" \
        password="$pass"
    
    vault write database/roles/app \
        db_name=mysql \
        creation_statements="CREATE USER '{{name}}'@'%' IDENTIFIED BY '{{password}}'; GRANT SELECT, INSERT, UPDATE, DELETE ON myapp.* TO '{{name}}'@'%';" \
        revocation_statements="DROP USER '{{name}}'@'%';" \
        default_ttl="2h" \
        max_ttl="6h"
    
    log_success "MySQL configured"
}

# Create policies
create_policies() {
    log_info "Creating database policies..."
    
    # Developer policy
    cat > /tmp/db-dev-policy.hcl << 'EOF'
path "database/creds/readonly" { capabilities = ["read"] }
path "database/creds/webapp" { capabilities = ["read"] }
path "database/creds/app" { capabilities = ["read"] }
path "database/roles" { capabilities = ["list"] }
path "database/roles/*" { capabilities = ["read"] }
EOF
    vault policy write database-developer /tmp/db-dev-policy.hcl
    
    # Admin policy
    cat > /tmp/db-admin-policy.hcl << 'EOF'
path "database/creds/*" { capabilities = ["read"] }
path "database/roles/*" { capabilities = ["create", "read", "update", "delete"] }
path "database/config/*" { capabilities = ["read", "update"] }
EOF
    vault policy write database-admin /tmp/db-admin-policy.hcl
    
    rm -f /tmp/db-*-policy.hcl
    log_success "Policies created"
}

# Test credentials
test_credentials() {
    log_info "Testing credential generation..."
    
    local roles=("readonly" "webapp" "app")
    for role in "${roles[@]}"; do
        if vault read database/roles/$role &>/dev/null; then
            if creds=$(vault read -format=json "database/creds/$role" 2>/dev/null); then
                username=$(echo "$creds" | jq -r '.data.username')
                lease_id=$(echo "$creds" | jq -r '.lease_id')
                log_success "Generated: $role -> $username"
                vault lease revoke "$lease_id" &>/dev/null
            else
                log_warning "Failed: $role"
            fi
        fi
    done
}

# Create utilities
create_utilities() {
    log_info "Creating utility scripts..."
    
    cat > ../scripts/get-db-creds.sh << 'EOF'
#!/bin/bash
if [[ $# -ne 1 ]]; then
    echo "Usage: $0 <role_name>"
    vault list database/roles
    exit 1
fi

CREDS=$(vault read -format=json "database/creds/$1")
if [[ $? -eq 0 ]]; then
    echo "Username: $(echo "$CREDS" | jq -r '.data.username')"
    echo "Password: $(echo "$CREDS" | jq -r '.data.password')"
    echo "Lease ID: $(echo "$CREDS" | jq -r '.lease_id')"
else
    echo "Failed to generate credentials for $1"
fi
EOF
    chmod +x ../scripts/get-db-creds.sh
    
    cat > ../scripts/monitor-db-creds.sh << 'EOF'
#!/bin/bash
echo "Database Credential Report - $(date)"
echo "===================================="
echo "Configured databases:"
vault list database/config
echo -e "\nAvailable roles:"
vault list database/roles
echo -e "\nActive credentials count:"
vault list sys/leases/lookup/database/creds 2>/dev/null | wc -l
EOF
    chmod +x ../scripts/monitor-db-creds.sh
    
    log_success "Utilities created"
}

# Generate summary
generate_summary() {
    cat << EOF

${GREEN}==============================================${NC}
${GREEN}  Database Dynamic Key Rotation Complete    ${NC}
${GREEN}==============================================${NC}

${BLUE}Status:${NC}
- Database engine: Enabled
- PostgreSQL: $(vault read database/config/postgresql &>/dev/null && echo "Configured" || echo "Not configured")
- MySQL: $(vault read database/config/mysql &>/dev/null && echo "Configured" || echo "Not configured")

${BLUE}Available Roles:${NC}
$(vault list database/roles 2>/dev/null | sed 's/^/- /')

${BLUE}Usage Examples:${NC}
# Generate credentials
vault read database/creds/readonly
vault read database/creds/webapp

# Use utility script
./scripts/get-db-creds.sh readonly

# Monitor usage
./scripts/monitor-db-creds.sh

${BLUE}Connection Example:${NC}
CREDS=\$(vault read -format=json database/creds/readonly)
USER=\$(echo \$CREDS | jq -r '.data.username')
PASS=\$(echo \$CREDS | jq -r '.data.password')
psql -h postgres.example.com -U \$USER -d mydb

${BLUE}Next Steps:${NC}
1. Configure real database connections
2. Test application integration
3. Set up monitoring and alerting
4. Implement automated renewal

EOF
}

# Main execution
main() {
    log_info "Starting database setup..."
    
    check_prerequisites
    configure_database_engine
    
    # Configure databases based on environment variables
    [[ -n "${POSTGRES_HOST:-}" ]] && configure_postgresql
    [[ -n "${MYSQL_HOST:-}" ]] && configure_mysql
    
    create_policies
    test_credentials
    create_utilities
    generate_summary
    
    log_success "Database setup completed!"
}

main "$@"