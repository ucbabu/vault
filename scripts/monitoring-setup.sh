#!/bin/bash
# monitoring-setup.sh - Vault monitoring and alerting setup

set -euo pipefail

log_info() { echo -e "\033[0;34m[INFO]\033[0m $1"; }
log_success() { echo -e "\033[0;32m[SUCCESS]\033[0m $1"; }

# Create comprehensive monitoring script
create_monitoring() {
    log_info "Setting up Vault monitoring..."
    
    cat > ../scripts/vault-monitor.sh << 'EOF'
#!/bin/bash
# vault-monitor.sh - Comprehensive Vault monitoring

echo "Vault Monitoring Report - $(date)"
echo "================================="

# Health check
echo -e "\n1. Vault Health:"
vault status 2>/dev/null || echo "  ERROR: Vault unreachable"

# Secrets engines
echo -e "\n2. Secrets Engines:"
vault secrets list | grep -E "(secret|database|azure)" | wc -l | sed 's/^/  Active engines: /'

# Authentication methods
echo -e "\n3. Authentication:"
vault auth list | wc -l | sed 's/^/  Auth methods: /'

# Active leases
echo -e "\n4. Active Leases:"
vault list sys/leases/lookup/database/creds 2>/dev/null | wc -l | sed 's/^/  Database: /'
vault list sys/leases/lookup/azure/creds 2>/dev/null | wc -l | sed 's/^/  Azure: /'

# Audit status
echo -e "\n5. Audit Devices:"
vault audit list 2>/dev/null | wc -l | sed 's/^/  Enabled: /'

# Metrics
echo -e "\n6. System Metrics:"
vault read sys/metrics 2>/dev/null | grep -c "counter\|gauge" | sed 's/^/  Metrics available: /' || echo "  Metrics: Unavailable"

echo -e "\nMonitoring complete."
EOF
    chmod +x ../scripts/vault-monitor.sh
    
    # Create alerting script
    cat > ../scripts/vault-alerts.sh << 'EOF'
#!/bin/bash
# vault-alerts.sh - Vault alerting checks

check_vault_health() {
    if ! vault status &>/dev/null; then
        echo "CRITICAL: Vault cluster unreachable"
        return 1
    fi
}

check_lease_count() {
    local total_leases=$(vault list sys/leases/lookup 2>/dev/null | wc -l || echo 0)
    if [[ $total_leases -gt 1000 ]]; then
        echo "WARNING: High lease count: $total_leases"
    fi
}

check_auth_failures() {
    # Would check audit logs for authentication failures
    echo "INFO: Auth failure check - implement based on audit log analysis"
}

main() {
    echo "Vault Alert Checks - $(date)"
    check_vault_health
    check_lease_count
    check_auth_failures
}

main "$@"
EOF
    chmod +x ../scripts/vault-alerts.sh
    
    log_success "Monitoring scripts created"
}

# Main execution
main() {
    log_info "Setting up Vault monitoring and alerting..."
    create_monitoring
    
    cat << 'EOF'

Monitoring Setup Complete
========================

Scripts Created:
- scripts/vault-monitor.sh - Comprehensive monitoring
- scripts/vault-alerts.sh - Alerting checks

Usage:
./scripts/vault-monitor.sh    # Run monitoring report
./scripts/vault-alerts.sh     # Check for alerts

Integration:
- Set up cron jobs for regular monitoring
- Integrate with external monitoring systems
- Configure alerting thresholds
- Implement log analysis for audit trails

EOF
}

main "$@"