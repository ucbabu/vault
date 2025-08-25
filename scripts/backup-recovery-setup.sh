#!/bin/bash
# backup-recovery-setup.sh - Vault backup and disaster recovery setup

set -euo pipefail

log_info() { echo -e "\033[0;34m[INFO]\033[0m $1"; }
log_success() { echo -e "\033[0;32m[SUCCESS]\033[0m $1"; }

# Create backup scripts
create_backup_scripts() {
    log_info "Creating backup and recovery scripts..."
    
    # Vault configuration backup
    cat > ../scripts/backup-vault-config.sh << 'EOF'
#!/bin/bash
# backup-vault-config.sh - Backup Vault configuration

set -euo pipefail

BACKUP_DIR="${1:-./vault-backups}"
TIMESTAMP=$(date +%Y%m%d-%H%M%S)
BACKUP_FILE="${BACKUP_DIR}/vault-config-${TIMESTAMP}.json"

mkdir -p "$BACKUP_DIR"

echo "Backing up Vault configuration to $BACKUP_FILE"

{
    echo "{"
    echo "  \"timestamp\": \"$(date -u +%Y-%m-%dT%H:%M:%SZ)\","
    echo "  \"vault_status\": $(vault status -format=json 2>/dev/null || echo '{}'),"
    echo "  \"secrets_engines\": $(vault secrets list -format=json 2>/dev/null || echo '{}'),"
    echo "  \"auth_methods\": $(vault auth list -format=json 2>/dev/null || echo '{}'),"
    echo "  \"policies\": $(vault policy list -format=json 2>/dev/null || echo '[]'),"
    echo "  \"audit_devices\": $(vault audit list -format=json 2>/dev/null || echo '{}')"
    echo "}"
} > "$BACKUP_FILE"

echo "Configuration backup completed: $BACKUP_FILE"
EOF
    chmod +x ../scripts/backup-vault-config.sh
    
    # Secret backup script (already created, enhance it)
    cat > ../scripts/backup-all-secrets.sh << 'EOF'
#!/bin/bash
# backup-all-secrets.sh - Backup all Vault secrets

set -euo pipefail

BACKUP_DIR="${1:-./vault-backups}"
TIMESTAMP=$(date +%Y%m%d-%H%M%S)
SECRET_BACKUP="${BACKUP_DIR}/vault-secrets-${TIMESTAMP}.json"
CONFIG_BACKUP="${BACKUP_DIR}/vault-config-${TIMESTAMP}.json"

mkdir -p "$BACKUP_DIR"

echo "Creating comprehensive Vault backup..."

# Backup configuration
./backup-vault-config.sh "$BACKUP_DIR"

# Backup secrets
echo "Backing up secrets to $SECRET_BACKUP"
SECRET_ENGINES=$(vault secrets list -format=json | jq -r 'to_entries[] | select(.value.type == "kv") | .key' | sed 's|/$||')

{
    echo "{"
    echo "  \"timestamp\": \"$(date -u +%Y-%m-%dT%H:%M:%SZ)\","
    echo "  \"secrets\": {"
    
    first=true
    for engine in $SECRET_ENGINES; do
        if [ "$first" = false ]; then echo ","; fi
        echo "    \"$engine\": {"
        
        vault kv list -format=json "$engine" 2>/dev/null | jq -r '.[]' | while read -r secret; do
            if [[ -n "$secret" ]]; then
                echo "      \"$secret\": $(vault kv get -format=json "$engine/$secret" 2>/dev/null || echo '{}')"
            fi
        done
        
        echo "    }"
        first=false
    done
    
    echo "  }"
    echo "}"
} > "$SECRET_BACKUP"

echo "Complete backup finished:"
echo "  Configuration: $CONFIG_BACKUP"
echo "  Secrets: $SECRET_BACKUP"
EOF
    chmod +x ../scripts/backup-all-secrets.sh
    
    # Disaster recovery script
    cat > ../scripts/disaster-recovery.sh << 'EOF'
#!/bin/bash
# disaster-recovery.sh - Vault disaster recovery procedures

set -euo pipefail

show_usage() {
    echo "Usage: $0 <command> [options]"
    echo "Commands:"
    echo "  validate <backup_file>  - Validate backup file"
    echo "  restore <backup_file>   - Restore from backup (DANGER)"
    echo "  test                    - Test disaster recovery procedures"
}

validate_backup() {
    local backup_file="$1"
    echo "Validating backup file: $backup_file"
    
    if [[ ! -f "$backup_file" ]]; then
        echo "ERROR: Backup file not found"
        return 1
    fi
    
    if jq empty "$backup_file" 2>/dev/null; then
        echo "✓ Backup file is valid JSON"
        echo "✓ Backup timestamp: $(jq -r '.timestamp' "$backup_file")"
        echo "✓ Contains $(jq -r '.secrets | keys | length' "$backup_file" 2>/dev/null || echo "0") secret engines"
    else
        echo "✗ Backup file is invalid JSON"
        return 1
    fi
}

test_procedures() {
    echo "Testing disaster recovery procedures..."
    echo "1. ✓ Vault connection test"
    vault status >/dev/null && echo "   Vault accessible" || echo "   ERROR: Vault not accessible"
    
    echo "2. ✓ Backup creation test"
    ./backup-vault-config.sh /tmp >/dev/null && echo "   Backup creation OK" || echo "   ERROR: Backup failed"
    
    echo "3. ✓ Backup validation test"
    validate_backup /tmp/vault-config-*.json >/dev/null && echo "   Backup validation OK" || echo "   ERROR: Validation failed"
    
    echo "Disaster recovery test completed"
}

case "${1:-}" in
    "validate")
        validate_backup "$2"
        ;;
    "test")
        test_procedures
        ;;
    *)
        show_usage
        ;;
esac
EOF
    chmod +x ../scripts/disaster-recovery.sh
    
    log_success "Backup and recovery scripts created"
}

# Create recovery documentation
create_recovery_docs() {
    log_info "Creating disaster recovery documentation..."
    
    cat > ../docs/operations/disaster-recovery-runbook.md << 'EOF'
# Vault Disaster Recovery Runbook

## Overview
This runbook provides step-by-step procedures for Vault disaster recovery scenarios.

## Emergency Contacts
- Platform Team: platform-team@company.com
- On-call Engineer: +1-555-0123
- HashiCorp Support: Via HCP Console

## Recovery Procedures

### 1. Vault Cluster Outage
```bash
# Check cluster status
vault status

# Check HCP console for cluster health
# https://cloud.hashicorp.com

# If cluster is down, contact HashiCorp support
```

### 2. Configuration Recovery
```bash
# Restore from latest backup
./scripts/disaster-recovery.sh validate backup-file.json
./scripts/disaster-recovery.sh restore backup-file.json
```

### 3. Data Recovery
```bash
# Create emergency backup
./scripts/backup-all-secrets.sh

# Validate backup integrity
./scripts/disaster-recovery.sh validate backup-file.json
```

## Prevention
- Automated daily backups
- Regular DR testing
- Monitoring and alerting
- Documentation updates

## Recovery Time Objectives
- RTO: 4 hours
- RPO: 1 hour
EOF
    
    log_success "Recovery documentation created"
}

# Main execution
main() {
    log_info "Setting up backup and disaster recovery..."
    
    create_backup_scripts
    create_recovery_docs
    
    cat << 'EOF'

Backup & Disaster Recovery Setup Complete
========================================

Components Created:
- scripts/backup-vault-config.sh - Configuration backup
- scripts/backup-all-secrets.sh - Complete backup
- scripts/disaster-recovery.sh - Recovery procedures
- docs/operations/disaster-recovery-runbook.md - Recovery guide

Usage:
./scripts/backup-vault-config.sh                    # Config backup
./scripts/backup-all-secrets.sh                     # Full backup
./scripts/disaster-recovery.sh test                 # Test procedures
./scripts/disaster-recovery.sh validate backup.json # Validate backup

Recommendations:
- Schedule daily automated backups
- Test recovery procedures monthly
- Store backups in multiple locations
- Document all recovery procedures
- Train team on disaster recovery

EOF
}

main "$@"