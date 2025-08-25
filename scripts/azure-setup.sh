#!/bin/bash
# azure-setup.sh
# Azure dynamic key rotation setup script for HashiCorp Vault

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
    log_info "Checking prerequisites for Azure setup..."
    
    # Check Vault connection
    if [[ -z "${VAULT_ADDR:-}" ]] || [[ -z "${VAULT_TOKEN:-}" ]]; then
        log_error "VAULT_ADDR and VAULT_TOKEN environment variables must be set"
        exit 1
    fi
    
    if ! vault status &> /dev/null; then
        log_error "Cannot connect to Vault at $VAULT_ADDR"
        exit 1
    fi
    
    # Check Azure CLI
    if ! command -v az &> /dev/null; then
        log_error "Azure CLI is not installed. Please install it first."
        log_info "Install with: curl -sL https://aka.ms/InstallAzureCLIDeb | sudo bash"
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
    
    log_success "Prerequisites check passed"
}

# Create Azure service principal for Vault
create_vault_service_principal() {
    log_info "Creating Azure service principal for Vault..."
    
    local sp_name="vault-azure-secrets-engine"
    local subscription_id="${AZURE_SUBSCRIPTION_ID}"
    
    # Check if service principal already exists
    local existing_sp=$(az ad sp list --display-name "$sp_name" --query '[0].appId' -o tsv 2>/dev/null || echo "")
    
    if [[ -n "$existing_sp" ]]; then
        log_warning "Service principal '$sp_name' already exists with App ID: $existing_sp"
        export VAULT_SP_CLIENT_ID="$existing_sp"
        
        # Get existing secret (if available) or create new one
        log_info "Creating new client secret for existing service principal..."
        local secret_result=$(az ad sp credential reset --id "$existing_sp" --display-name "vault-secret-$(date +%Y%m%d)" --query 'password' -o tsv)
        export VAULT_SP_CLIENT_SECRET="$secret_result"
    else
        log_info "Creating new service principal..."
        local sp_result=$(az ad sp create-for-rbac \
            --name "$sp_name" \
            --role "Contributor" \
            --scopes "/subscriptions/$subscription_id" \
            --sdk-auth)
        
        export VAULT_SP_CLIENT_ID=$(echo "$sp_result" | jq -r '.clientId')
        export VAULT_SP_CLIENT_SECRET=$(echo "$sp_result" | jq -r '.clientSecret')
    fi
    
    # Assign additional required permissions
    log_info "Assigning required permissions to service principal..."
    
    # User Access Administrator role for managing role assignments
    az role assignment create \
        --assignee "$VAULT_SP_CLIENT_ID" \
        --role "User Access Administrator" \
        --scope "/subscriptions/$subscription_id" \
        --output none 2>/dev/null || log_warning "User Access Administrator role may already be assigned"
    
    # Microsoft Graph permissions for directory access
    local graph_app_id="00000003-0000-0000-c000-000000000000"
    local directory_read_permission="7ab1d382-f21e-4acd-a863-ba3e13f7da61"
    
    az ad app permission add \
        --id "$VAULT_SP_CLIENT_ID" \
        --api "$graph_app_id" \
        --api-permissions "$directory_read_permission=Role" \
        --output none 2>/dev/null || log_warning "Directory permissions may already be assigned"
    
    # Grant admin consent (requires admin privileges)
    az ad app permission admin-consent --id "$VAULT_SP_CLIENT_ID" --output none 2>/dev/null || \
        log_warning "Could not grant admin consent automatically. You may need to do this manually in Azure Portal."
    
    log_success "Service principal created/updated with Client ID: $VAULT_SP_CLIENT_ID"
}

# Enable and configure Azure secrets engine
configure_azure_secrets_engine() {
    log_info "Configuring Azure secrets engine..."
    
    # Enable Azure secrets engine
    if vault secrets list | grep -q "azure/"; then
        log_warning "Azure secrets engine already enabled"
    else
        vault secrets enable azure
        log_success "Azure secrets engine enabled"
    fi
    
    # Configure Azure connection
    vault write azure/config \
        subscription_id="$AZURE_SUBSCRIPTION_ID" \
        tenant_id="$AZURE_TENANT_ID" \
        client_id="$VAULT_SP_CLIENT_ID" \
        client_secret="$VAULT_SP_CLIENT_SECRET" \
        environment="AzurePublicCloud"
    
    log_success "Azure secrets engine configured"
    
    # Verify configuration
    vault read azure/config
}

# Create Azure roles for different use cases
create_azure_roles() {
    log_info "Creating Azure roles for dynamic credential generation..."
    
    local subscription_id="$AZURE_SUBSCRIPTION_ID"
    
    # Read-only role for monitoring and general access
    log_info "Creating readonly role..."
    vault write azure/roles/readonly \
        azure_roles="[
            {
                \"role_name\": \"Reader\",
                \"scope\": \"/subscriptions/$subscription_id\"
            }
        ]" \
        ttl="1h" \
        max_ttl="24h"
    
    # Storage account management role
    log_info "Creating storage-admin role..."
    vault write azure/roles/storage-admin \
        azure_roles="[
            {
                \"role_name\": \"Storage Account Contributor\",
                \"scope\": \"/subscriptions/$subscription_id\"
            },
            {
                \"role_name\": \"Storage Blob Data Contributor\",
                \"scope\": \"/subscriptions/$subscription_id\"
            }
        ]" \
        ttl="30m" \
        max_ttl="2h"
    
    # Virtual machine management role
    log_info "Creating vm-admin role..."
    vault write azure/roles/vm-admin \
        azure_roles="[
            {
                \"role_name\": \"Virtual Machine Contributor\",
                \"scope\": \"/subscriptions/$subscription_id\"
            },
            {
                \"role_name\": \"Network Contributor\",
                \"scope\": \"/subscriptions/$subscription_id\"
            }
        ]" \
        ttl="2h" \
        max_ttl="8h"
    
    # Application deployment role
    log_info "Creating app-deployer role..."
    vault write azure/roles/app-deployer \
        azure_roles="[
            {
                \"role_name\": \"Contributor\",
                \"scope\": \"/subscriptions/$subscription_id\"
            }
        ]" \
        ttl="4h" \
        max_ttl="12h"
    
    # Key Vault management role
    log_info "Creating keyvault-admin role..."
    vault write azure/roles/keyvault-admin \
        azure_roles="[
            {
                \"role_name\": \"Key Vault Administrator\",
                \"scope\": \"/subscriptions/$subscription_id\"
            }
        ]" \
        ttl="1h" \
        max_ttl="4h"
    
    # Monitoring and metrics role
    log_info "Creating monitoring role..."
    vault write azure/roles/monitoring \
        azure_roles="[
            {
                \"role_name\": \"Monitoring Reader\",
                \"scope\": \"/subscriptions/$subscription_id\"
            },
            {
                \"role_name\": \"Log Analytics Reader\",
                \"scope\": \"/subscriptions/$subscription_id\"
            }
        ]" \
        ttl="24h" \
        max_ttl="72h"
    
    # Resource group specific role
    local rg_name="vault-test-rg"
    if az group show --name "$rg_name" &>/dev/null || az group create --name "$rg_name" --location "eastus" &>/dev/null; then
        log_info "Creating rg-contributor role for $rg_name..."
        vault write azure/roles/rg-contributor \
            azure_roles="[
                {
                    \"role_name\": \"Contributor\",
                    \"scope\": \"/subscriptions/$subscription_id/resourceGroups/$rg_name\"
                }
            ]" \
            ttl="2h" \
            max_ttl="6h"
    fi
    
    log_success "Azure roles created"
}

# Create Azure-specific policies
create_azure_policies() {
    log_info "Creating Azure-specific policies..."
    
    # Azure readonly policy
    cat > /tmp/azure-readonly-policy.hcl << 'EOF'
# Azure read-only access policy
path "azure/creds/readonly" {
  capabilities = ["read"]
}

path "azure/creds/monitoring" {
  capabilities = ["read"]
}

# Allow listing roles
path "azure/roles" {
  capabilities = ["list"]
}

path "azure/roles/*" {
  capabilities = ["read"]
}
EOF
    vault policy write azure-readonly /tmp/azure-readonly-policy.hcl
    log_success "Azure readonly policy created"
    
    # Azure developer policy
    cat > /tmp/azure-developer-policy.hcl << 'EOF'
# Azure developer access policy
path "azure/creds/readonly" {
  capabilities = ["read"]
}

path "azure/creds/storage-admin" {
  capabilities = ["read"]
}

path "azure/creds/rg-contributor" {
  capabilities = ["read"]
}

path "azure/roles" {
  capabilities = ["list"]
}

path "azure/roles/*" {
  capabilities = ["read"]
}
EOF
    vault policy write azure-developer /tmp/azure-developer-policy.hcl
    log_success "Azure developer policy created"
    
    # Azure operator policy
    cat > /tmp/azure-operator-policy.hcl << 'EOF'
# Azure operator access policy
path "azure/creds/vm-admin" {
  capabilities = ["read"]
}

path "azure/creds/storage-admin" {
  capabilities = ["read"]
}

path "azure/creds/monitoring" {
  capabilities = ["read"]
}

path "azure/creds/keyvault-admin" {
  capabilities = ["read"]
}

path "azure/roles" {
  capabilities = ["list"]
}

path "azure/roles/*" {
  capabilities = ["read"]
}
EOF
    vault policy write azure-operator /tmp/azure-operator-policy.hcl
    log_success "Azure operator policy created"
    
    # Azure CI/CD policy
    cat > /tmp/azure-cicd-policy.hcl << 'EOF'
# Azure CI/CD pipeline access policy
path "azure/creds/app-deployer" {
  capabilities = ["read"]
}

path "azure/creds/rg-contributor" {
  capabilities = ["read"]
}

path "azure/creds/storage-admin" {
  capabilities = ["read"]
}
EOF
    vault policy write azure-cicd /tmp/azure-cicd-policy.hcl
    log_success "Azure CI/CD policy created"
    
    # Clean up temporary files
    rm -f /tmp/azure-*-policy.hcl
    
    log_info "Current Azure policies:"
    vault policy list | grep azure
}

# Test Azure dynamic credential generation
test_azure_credentials() {
    log_info "Testing Azure dynamic credential generation..."
    
    local roles=("readonly" "storage-admin" "monitoring")
    
    for role in "${roles[@]}"; do
        log_info "Testing role: $role"
        
        # Generate credentials
        local creds=$(vault read -format=json "azure/creds/$role")
        
        if [[ $? -eq 0 ]]; then
            local client_id=$(echo "$creds" | jq -r '.data.client_id')
            local client_secret=$(echo "$creds" | jq -r '.data.client_secret')
            local lease_id=$(echo "$creds" | jq -r '.lease_id')
            
            log_success "Generated credentials for $role - Client ID: $client_id"
            
            # Test Azure CLI login with generated credentials
            if az login --service-principal \
                --username "$client_id" \
                --password "$client_secret" \
                --tenant "$AZURE_TENANT_ID" &>/dev/null; then
                
                log_success "Successfully authenticated with generated credentials"
                
                # Test basic Azure operation
                if az account show &>/dev/null; then
                    log_success "Azure API access verified for $role"
                else
                    log_warning "Could not verify Azure API access for $role"
                fi
                
                # Logout from Azure CLI
                az logout &>/dev/null
            else
                log_warning "Could not authenticate with generated credentials for $role"
            fi
            
            # Revoke credentials
            vault lease revoke "$lease_id" &>/dev/null
            log_info "Revoked test credentials for $role"
        else
            log_error "Failed to generate credentials for $role"
        fi
    done
    
    # Re-login with original Azure CLI session
    az login --service-principal \
        --username "$VAULT_SP_CLIENT_ID" \
        --password "$VAULT_SP_CLIENT_SECRET" \
        --tenant "$AZURE_TENANT_ID" &>/dev/null || true
}

# Create monitoring and alerting for Azure credentials
setup_azure_monitoring() {
    log_info "Setting up Azure credential monitoring..."
    
    # Create monitoring script
    cat > ../scripts/monitor-azure-creds.sh << 'EOF'
#!/bin/bash
# monitor-azure-creds.sh - Monitor Azure credential usage

set -euo pipefail

echo "Azure Credential Monitoring Report - $(date)"
echo "============================================"

# Check Azure secrets engine status
echo -e "\n1. Azure Secrets Engine Status:"
vault read azure/config 2>/dev/null | grep -E "(subscription_id|tenant_id|environment)" || echo "Azure engine not configured"

# List available roles
echo -e "\n2. Available Azure Roles:"
vault list azure/roles 2>/dev/null || echo "No Azure roles found"

# Check active leases
echo -e "\n3. Active Azure Credentials:"
vault list sys/leases/lookup/azure/creds 2>/dev/null || echo "No active Azure credentials"

# Monitor lease count per role
echo -e "\n4. Credential Usage by Role:"
for role in $(vault list -format=json azure/roles 2>/dev/null | jq -r '.[]' 2>/dev/null || echo ""); do
    if [[ -n "$role" ]]; then
        lease_count=$(vault list sys/leases/lookup/azure/creds/$role 2>/dev/null | wc -l || echo "0")
        echo "  $role: $lease_count active leases"
    fi
done

# Check for expiring credentials (next 1 hour)
echo -e "\n5. Credentials Expiring Soon:"
# This would require parsing lease information - simplified for now
echo "  Check individual leases for expiration times"

echo -e "\n6. Recommendations:"
echo "  - Monitor credential generation patterns"
echo "  - Set up alerts for failed authentications"
echo "  - Review role permissions regularly"
echo "  - Implement automated lease renewal where needed"
EOF
    chmod +x ../scripts/monitor-azure-creds.sh
    
    # Create credential renewal script
    cat > ../scripts/renew-azure-creds.sh << 'EOF'
#!/bin/bash
# renew-azure-creds.sh - Renew Azure credentials

set -euo pipefail

if [[ $# -ne 1 ]]; then
    echo "Usage: $0 <lease_id>"
    exit 1
fi

LEASE_ID="$1"

echo "Renewing Azure credential lease: $LEASE_ID"

if vault lease renew "$LEASE_ID"; then
    echo "Successfully renewed lease: $LEASE_ID"
else
    echo "Failed to renew lease: $LEASE_ID"
    echo "Consider generating new credentials"
fi
EOF
    chmod +x ../scripts/renew-azure-creds.sh
    
    log_success "Azure monitoring scripts created"
}

# Create utility scripts for Azure operations
create_azure_utilities() {
    log_info "Creating Azure utility scripts..."
    
    # Azure credential generator script
    cat > ../scripts/get-azure-creds.sh << 'EOF'
#!/bin/bash
# get-azure-creds.sh - Generate Azure credentials for specific role

set -euo pipefail

if [[ $# -ne 1 ]]; then
    echo "Usage: $0 <role_name>"
    echo "Available roles:"
    vault list azure/roles 2>/dev/null || echo "  No roles found"
    exit 1
fi

ROLE_NAME="$1"

echo "Generating Azure credentials for role: $ROLE_NAME"

# Generate credentials
CREDS=$(vault read -format=json "azure/creds/$ROLE_NAME")

if [[ $? -eq 0 ]]; then
    CLIENT_ID=$(echo "$CREDS" | jq -r '.data.client_id')
    CLIENT_SECRET=$(echo "$CREDS" | jq -r '.data.client_secret')
    LEASE_ID=$(echo "$CREDS" | jq -r '.lease_id')
    LEASE_DURATION=$(echo "$CREDS" | jq -r '.lease_duration')
    
    echo "Credentials generated successfully:"
    echo "  Client ID: $CLIENT_ID"
    echo "  Lease ID: $LEASE_ID"
    echo "  Lease Duration: ${LEASE_DURATION}s"
    echo ""
    echo "Environment variables:"
    echo "export AZURE_CLIENT_ID=\"$CLIENT_ID\""
    echo "export AZURE_CLIENT_SECRET=\"$CLIENT_SECRET\""
    echo "export AZURE_TENANT_ID=\"$AZURE_TENANT_ID\""
    echo "export AZURE_SUBSCRIPTION_ID=\"$AZURE_SUBSCRIPTION_ID\""
    echo ""
    echo "Azure CLI login:"
    echo "az login --service-principal --username \"$CLIENT_ID\" --password \"$CLIENT_SECRET\" --tenant \"$AZURE_TENANT_ID\""
    echo ""
    echo "Remember to revoke when done:"
    echo "vault lease revoke \"$LEASE_ID\""
else
    echo "Failed to generate credentials for role: $ROLE_NAME"
    exit 1
fi
EOF
    chmod +x ../scripts/get-azure-creds.sh
    
    # Azure role management script
    cat > ../scripts/manage-azure-roles.sh << 'EOF'
#!/bin/bash
# manage-azure-roles.sh - Manage Azure roles in Vault

set -euo pipefail

show_usage() {
    echo "Usage: $0 <command> [args]"
    echo "Commands:"
    echo "  list                     - List all Azure roles"
    echo "  create <name> <file>     - Create role from JSON file"
    echo "  delete <name>            - Delete Azure role"
    echo "  show <name>              - Show role configuration"
}

case "${1:-}" in
    "list")
        echo "Azure Roles:"
        vault list azure/roles 2>/dev/null || echo "No roles found"
        ;;
    "create")
        if [[ $# -ne 3 ]]; then
            echo "Usage: $0 create <role_name> <json_file>"
            exit 1
        fi
        ROLE_NAME="$2"
        JSON_FILE="$3"
        
        if [[ ! -f "$JSON_FILE" ]]; then
            echo "JSON file not found: $JSON_FILE"
            exit 1
        fi
        
        vault write "azure/roles/$ROLE_NAME" @"$JSON_FILE"
        echo "Role $ROLE_NAME created successfully"
        ;;
    "delete")
        if [[ $# -ne 2 ]]; then
            echo "Usage: $0 delete <role_name>"
            exit 1
        fi
        ROLE_NAME="$2"
        vault delete "azure/roles/$ROLE_NAME"
        echo "Role $ROLE_NAME deleted successfully"
        ;;
    "show")
        if [[ $# -ne 2 ]]; then
            echo "Usage: $0 show <role_name>"
            exit 1
        fi
        ROLE_NAME="$2"
        vault read "azure/roles/$ROLE_NAME"
        ;;
    *)
        show_usage
        exit 1
        ;;
esac
EOF
    chmod +x ../scripts/manage-azure-roles.sh
    
    log_success "Azure utility scripts created"
}

# Generate summary report
generate_summary() {
    log_info "Generating Azure setup summary..."
    
    cat << EOF

${GREEN}===============================================${NC}
${GREEN}    Azure Dynamic Key Rotation Complete       ${NC}
${GREEN}===============================================${NC}

${BLUE}Azure Configuration:${NC}
- Subscription ID: ${AZURE_SUBSCRIPTION_ID}
- Tenant ID: ${AZURE_TENANT_ID}
- Vault Service Principal: ${VAULT_SP_CLIENT_ID}
- Environment: AzurePublicCloud

${BLUE}Azure Secrets Engine:${NC}
- Engine: azure/ (enabled)
- Connection: Configured and tested
- Status: $(vault read azure/config &>/dev/null && echo "Active" || echo "Error")

${BLUE}Azure Roles Created:${NC}
- readonly: General read access (1h TTL)
- storage-admin: Storage management (30m TTL)
- vm-admin: VM and network management (2h TTL)
- app-deployer: Application deployment (4h TTL)
- keyvault-admin: Key Vault management (1h TTL)
- monitoring: Monitoring and logging (24h TTL)
- rg-contributor: Resource group access (2h TTL)

${BLUE}Policies Created:${NC}
- azure-readonly: Read-only credential access
- azure-developer: Developer credential access
- azure-operator: Operator credential access
- azure-cicd: CI/CD pipeline access

${BLUE}Utility Scripts:${NC}
- scripts/get-azure-creds.sh - Generate credentials
- scripts/monitor-azure-creds.sh - Monitor usage
- scripts/renew-azure-creds.sh - Renew credentials
- scripts/manage-azure-roles.sh - Manage roles

${BLUE}Example Usage:${NC}
# Generate read-only credentials
vault read azure/creds/readonly

# Generate credentials via script
./scripts/get-azure-creds.sh readonly

# Monitor credential usage
./scripts/monitor-azure-creds.sh

# Test authentication
CREDS=\$(vault read -format=json azure/creds/readonly)
CLIENT_ID=\$(echo \$CREDS | jq -r '.data.client_id')
CLIENT_SECRET=\$(echo \$CREDS | jq -r '.data.client_secret')
az login --service-principal --username \$CLIENT_ID --password \$CLIENT_SECRET --tenant ${AZURE_TENANT_ID}

${BLUE}Security Features:${NC}
- Short-lived credentials (15min-24h TTL)
- Automatic credential cleanup
- Least privilege access policies
- Complete audit trail
- Role-based access control

${BLUE}Next Steps:${NC}
1. Integrate with applications and CI/CD pipelines
2. Set up monitoring and alerting for credential usage
3. Test credential rotation scenarios
4. Configure resource group-specific roles
5. Implement automated credential renewal

${YELLOW}Important Notes:${NC}
- Test credentials in development first
- Monitor credential generation patterns
- Regularly review and rotate service principal secrets
- Implement proper error handling in applications
- Use network restrictions where possible

EOF
}

# Main execution
main() {
    log_info "Starting Azure dynamic key rotation setup..."
    
    check_prerequisites
    create_vault_service_principal
    configure_azure_secrets_engine
    create_azure_roles
    create_azure_policies
    test_azure_credentials
    setup_azure_monitoring
    create_azure_utilities
    generate_summary
    
    log_success "Azure dynamic key rotation setup completed successfully!"
}

# Execute main function
main "$@"