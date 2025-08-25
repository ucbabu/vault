#!/bin/bash
# kubernetes-vault-setup.sh
# Kubernetes-Vault integration setup script with Secrets Operator

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

# Check prerequisites
check_prerequisites() {
    log_info "Checking prerequisites for Kubernetes-Vault integration..."
    
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
    
    # Check helm
    if ! command -v helm &> /dev/null; then
        log_warning "Helm not found. Will use kubectl for installation."
    fi
    
    log_success "Prerequisites check passed"
}

# Configure Kubernetes authentication in Vault
configure_kubernetes_auth() {
    log_info "Configuring Kubernetes authentication in Vault..."
    
    # Enable Kubernetes auth method if not already enabled
    if ! vault auth list | grep -q "kubernetes/"; then
        vault auth enable kubernetes
        log_success "Kubernetes auth method enabled"
    else
        log_warning "Kubernetes auth method already enabled"
    fi
    
    # Get Kubernetes cluster information
    local k8s_host=$(kubectl config view --raw --minify --flatten -o jsonpath='{.clusters[].cluster.server}')
    local k8s_ca_cert=$(kubectl config view --raw --minify --flatten -o jsonpath='{.clusters[].cluster.certificate-authority-data}' | base64 -d)
    
    # Create service account for Vault authentication
    kubectl create namespace $VAULT_SECRETS_OPERATOR_NAMESPACE --dry-run=client -o yaml | kubectl apply -f -
    
    cat <<EOF | kubectl apply -f -
apiVersion: v1
kind: ServiceAccount
metadata:
  name: vault-auth
  namespace: $VAULT_SECRETS_OPERATOR_NAMESPACE
---
apiVersion: rbac.authorization.k8s.io/v1
kind: ClusterRoleBinding
metadata:
  name: vault-auth-delegator
roleRef:
  apiGroup: rbac.authorization.k8s.io
  kind: ClusterRole
  name: system:auth-delegator
subjects:
- kind: ServiceAccount
  name: vault-auth
  namespace: $VAULT_SECRETS_OPERATOR_NAMESPACE
EOF
    
    # Get service account token
    local token_name=$(kubectl get serviceaccount vault-auth -n $VAULT_SECRETS_OPERATOR_NAMESPACE -o jsonpath='{.secrets[0].name}' 2>/dev/null || echo "")
    local reviewer_jwt
    
    if [[ -n "$token_name" ]]; then
        reviewer_jwt=$(kubectl get secret $token_name -n $VAULT_SECRETS_OPERATOR_NAMESPACE -o jsonpath='{.data.token}' | base64 -d)
    else
        # Kubernetes 1.24+ doesn't auto-create tokens
        reviewer_jwt=$(kubectl create token vault-auth -n $VAULT_SECRETS_OPERATOR_NAMESPACE --duration=8760h)
    fi
    
    # Configure Kubernetes auth in Vault
    vault write auth/kubernetes/config \
        token_reviewer_jwt="$reviewer_jwt" \
        kubernetes_host="$k8s_host" \
        kubernetes_ca_cert="$k8s_ca_cert" \
        issuer="https://kubernetes.default.svc.cluster.local"
    
    log_success "Kubernetes authentication configured in Vault"
}

# Create Kubernetes roles and policies in Vault
create_vault_policies() {
    log_info "Creating Vault policies for Kubernetes integration..."
    
    # Create webapp policy
    cat > /tmp/webapp-policy.hcl << 'EOF'
# Read application secrets
path "secret/data/webapp/*" {
  capabilities = ["read"]
}

# Read shared configuration
path "secret/data/shared/config" {
  capabilities = ["read"]
}

# Generate database credentials
path "database/creds/webapp" {
  capabilities = ["read"]
}

# Generate Azure credentials
path "azure/creds/readonly" {
  capabilities = ["read"]
}

# Read own token information
path "auth/token/lookup-self" {
  capabilities = ["read"]
}
EOF
    vault policy write webapp-policy /tmp/webapp-policy.hcl
    
    # Create platform policy
    cat > /tmp/platform-policy.hcl << 'EOF'
# Read platform secrets
path "secret/data/platform/*" {
  capabilities = ["read"]
}

path "secret/data/shared/*" {
  capabilities = ["read"]
}

# Read monitoring secrets
path "secret/data/monitoring/*" {
  capabilities = ["read"]
}

# Generate infrastructure credentials
path "azure/creds/monitoring" {
  capabilities = ["read"]
}

path "database/creds/monitoring" {
  capabilities = ["read"]
}
EOF
    vault policy write platform-policy /tmp/platform-policy.hcl
    
    # Create development policy
    cat > /tmp/dev-policy.hcl << 'EOF'
# Full access to dev secrets
path "secret/data/dev/*" {
  capabilities = ["create", "read", "update", "delete", "list"]
}

path "secret/metadata/dev/*" {
  capabilities = ["create", "read", "update", "delete", "list"]
}

# Generate dev database credentials
path "database/creds/readonly" {
  capabilities = ["read"]
}
EOF
    vault policy write dev-policy /tmp/dev-policy.hcl
    
    rm -f /tmp/*-policy.hcl
    
    # Create Kubernetes roles
    vault write auth/kubernetes/role/webapp \
        bound_service_account_names=webapp \
        bound_service_account_namespaces=webapp \
        policies=webapp-policy \
        ttl=1h \
        max_ttl=4h
    
    vault write auth/kubernetes/role/platform \
        bound_service_account_names=platform-service \
        bound_service_account_namespaces="platform,monitoring,logging" \
        policies=platform-policy \
        ttl=2h \
        max_ttl=8h
    
    vault write auth/kubernetes/role/dev-apps \
        bound_service_account_names="*" \
        bound_service_account_namespaces=development \
        policies=dev-policy \
        ttl=30m \
        max_ttl=2h
    
    log_success "Vault policies and Kubernetes roles created"
}

# Install Vault Secrets Operator
install_vault_secrets_operator() {
    log_info "Installing Vault Secrets Operator..."
    
    if command -v helm &> /dev/null; then
        # Install using Helm
        helm repo add hashicorp https://helm.releases.hashicorp.com
        helm repo update
        
        helm upgrade --install vault-secrets-operator hashicorp/vault-secrets-operator \
            --namespace $VAULT_SECRETS_OPERATOR_NAMESPACE \
            --create-namespace \
            --set defaultVaultConnection.enabled=true \
            --set defaultVaultConnection.address="$VAULT_ADDR" \
            --set defaultVaultConnection.skipTLSVerify=false \
            --wait
            
        log_success "Vault Secrets Operator installed via Helm"
    else
        # Install using kubectl
        log_info "Installing Vault Secrets Operator using kubectl..."
        
        # Apply CRDs
        kubectl apply -f https://raw.githubusercontent.com/hashicorp/vault-secrets-operator/main/config/crd/bases/secrets.hashicorp.com_vaultauths.yaml
        kubectl apply -f https://raw.githubusercontent.com/hashicorp/vault-secrets-operator/main/config/crd/bases/secrets.hashicorp.com_vaultconnections.yaml
        kubectl apply -f https://raw.githubusercontent.com/hashicorp/vault-secrets-operator/main/config/crd/bases/secrets.hashicorp.com_vaultdynamicsecrets.yaml
        kubectl apply -f https://raw.githubusercontent.com/hashicorp/vault-secrets-operator/main/config/crd/bases/secrets.hashicorp.com_vaultstaticsecrets.yaml
        
        # Deploy operator
        kubectl apply -f https://raw.githubusercontent.com/hashicorp/vault-secrets-operator/main/config/default/default.yaml
        
        log_success "Vault Secrets Operator installed via kubectl"
    fi
    
    # Wait for operator to be ready
    kubectl wait --for=condition=available --timeout=300s deployment/vault-secrets-operator-controller-manager -n $VAULT_SECRETS_OPERATOR_NAMESPACE
}

# Configure VaultConnection
configure_vault_connection() {
    log_info "Configuring Vault connection..."
    
    cat <<EOF | kubectl apply -f -
apiVersion: secrets.hashicorp.com/v1beta1
kind: VaultConnection
metadata:
  name: default
  namespace: $VAULT_SECRETS_OPERATOR_NAMESPACE
spec:
  address: $VAULT_ADDR
  skipTLSVerify: false
EOF
    
    log_success "VaultConnection configured"
}

# Set up test namespace and resources
setup_test_namespace() {
    log_info "Setting up test namespace and resources..."
    
    # Create test namespace
    kubectl create namespace $TEST_NAMESPACE --dry-run=client -o yaml | kubectl apply -f -
    
    # Create service account
    cat <<EOF | kubectl apply -f -
apiVersion: v1
kind: ServiceAccount
metadata:
  name: webapp
  namespace: $TEST_NAMESPACE
EOF
    
    # Create test secrets in Vault
    vault kv put secret/webapp/config \
        app_name="webapp" \
        debug="false" \
        log_level="info" \
        api_token="test-api-token-123"
    
    vault kv put secret/shared/config \
        region="us-west-2" \
        environment="production" \
        monitoring_enabled="true"
    
    log_success "Test namespace and secrets created"
}

# Create VaultAuth resources
create_vault_auth() {
    log_info "Creating VaultAuth resources..."
    
    cat <<EOF | kubectl apply -f -
apiVersion: secrets.hashicorp.com/v1beta1
kind: VaultAuth
metadata:
  name: webapp-auth
  namespace: $TEST_NAMESPACE
spec:
  vaultConnectionRef: $VAULT_SECRETS_OPERATOR_NAMESPACE/default
  method: kubernetes
  mount: kubernetes
  kubernetes:
    role: webapp
    serviceAccount: webapp
EOF
    
    log_success "VaultAuth resources created"
}

# Create VaultStaticSecret resources
create_vault_static_secrets() {
    log_info "Creating VaultStaticSecret resources..."
    
    # Application configuration secret
    cat <<EOF | kubectl apply -f -
apiVersion: secrets.hashicorp.com/v1beta1
kind: VaultStaticSecret
metadata:
  name: webapp-config
  namespace: $TEST_NAMESPACE
spec:
  vaultAuthRef: webapp-auth
  mount: secret
  type: kv-v2
  path: webapp/config
  destination:
    name: webapp-config
    create: true
  refreshAfter: 30s
EOF
    
    # Shared configuration secret
    cat <<EOF | kubectl apply -f -
apiVersion: secrets.hashicorp.com/v1beta1
kind: VaultStaticSecret
metadata:
  name: shared-config
  namespace: $TEST_NAMESPACE
spec:
  vaultAuthRef: webapp-auth
  mount: secret
  type: kv-v2
  path: shared/config
  destination:
    name: shared-config
    create: true
  refreshAfter: 60s
EOF
    
    log_success "VaultStaticSecret resources created"
}

# Create VaultDynamicSecret resources
create_vault_dynamic_secrets() {
    log_info "Creating VaultDynamicSecret resources..."
    
    # Database dynamic secret (if database engine is configured)
    if vault read database/config/postgresql &>/dev/null; then
        cat <<EOF | kubectl apply -f -
apiVersion: secrets.hashicorp.com/v1beta1
kind: VaultDynamicSecret
metadata:
  name: webapp-database
  namespace: $TEST_NAMESPACE
spec:
  vaultAuthRef: webapp-auth
  mount: database
  path: creds/webapp
  destination:
    name: webapp-database
    create: true
  renewalPercent: 67
  revoke: true
EOF
        log_success "Database VaultDynamicSecret created"
    else
        log_warning "Database engine not configured, skipping database dynamic secret"
    fi
    
    # Azure dynamic secret (if Azure engine is configured)
    if vault read azure/config &>/dev/null; then
        cat <<EOF | kubectl apply -f -
apiVersion: secrets.hashicorp.com/v1beta1
kind: VaultDynamicSecret
metadata:
  name: webapp-azure
  namespace: $TEST_NAMESPACE
spec:
  vaultAuthRef: webapp-auth
  mount: azure
  path: creds/readonly
  destination:
    name: webapp-azure
    create: true
  renewalPercent: 67
  revoke: true
EOF
        log_success "Azure VaultDynamicSecret created"
    else
        log_warning "Azure engine not configured, skipping Azure dynamic secret"
    fi
}

# Create test deployment
create_test_deployment() {
    log_info "Creating test deployment..."
    
    cat <<EOF | kubectl apply -f -
apiVersion: apps/v1
kind: Deployment
metadata:
  name: webapp
  namespace: $TEST_NAMESPACE
  labels:
    app: webapp
spec:
  replicas: 1
  selector:
    matchLabels:
      app: webapp
  template:
    metadata:
      labels:
        app: webapp
    spec:
      serviceAccountName: webapp
      containers:
      - name: webapp
        image: nginx:alpine
        env:
        # Static secrets from Vault
        - name: APP_NAME
          valueFrom:
            secretKeyRef:
              name: webapp-config
              key: app_name
        - name: LOG_LEVEL
          valueFrom:
            secretKeyRef:
              name: webapp-config
              key: log_level
        - name: API_TOKEN
          valueFrom:
            secretKeyRef:
              name: webapp-config
              key: api_token
              
        # Shared configuration
        - name: REGION
          valueFrom:
            secretKeyRef:
              name: shared-config
              key: region
        - name: ENVIRONMENT
          valueFrom:
            secretKeyRef:
              name: shared-config
              key: environment
              
        # Dynamic database credentials (if available)
        - name: DB_USERNAME
          valueFrom:
            secretKeyRef:
              name: webapp-database
              key: username
              optional: true
        - name: DB_PASSWORD
          valueFrom:
            secretKeyRef:
              name: webapp-database
              key: password
              optional: true
              
        # Azure credentials (if available)
        - name: AZURE_CLIENT_ID
          valueFrom:
            secretKeyRef:
              name: webapp-azure
              key: client_id
              optional: true
        - name: AZURE_CLIENT_SECRET
          valueFrom:
            secretKeyRef:
              name: webapp-azure
              key: client_secret
              optional: true
              
        ports:
        - containerPort: 80
          name: http
          
        # Health checks
        livenessProbe:
          httpGet:
            path: /
            port: 80
          initialDelaySeconds: 10
          periodSeconds: 10
          
        readinessProbe:
          httpGet:
            path: /
            port: 80
          initialDelaySeconds: 5
          periodSeconds: 5
          
        resources:
          limits:
            cpu: 100m
            memory: 128Mi
          requests:
            cpu: 50m
            memory: 64Mi
EOF
    
    log_success "Test deployment created"
}

# Test the integration
test_integration() {
    log_info "Testing Kubernetes-Vault integration..."
    
    # Wait for secrets to be created
    local max_attempts=30
    local attempt=0
    
    while [[ $attempt -lt $max_attempts ]]; do
        if kubectl get secret webapp-config -n $TEST_NAMESPACE &>/dev/null; then
            log_success "Static secrets created successfully"
            break
        fi
        
        attempt=$((attempt + 1))
        log_info "Waiting for secrets to be created... (attempt $attempt/$max_attempts)"
        sleep 10
    done
    
    if [[ $attempt -eq $max_attempts ]]; then
        log_error "Secrets were not created within expected time"
        return 1
    fi
    
    # Check secret contents
    log_info "Verifying secret contents..."
    kubectl get secret webapp-config -n $TEST_NAMESPACE -o yaml
    
    # Wait for deployment to be ready
    kubectl wait --for=condition=available --timeout=300s deployment/webapp -n $TEST_NAMESPACE
    
    # Test pod environment variables
    log_info "Testing environment variables in pod..."
    local pod_name=$(kubectl get pods -n $TEST_NAMESPACE -l app=webapp -o jsonpath='{.items[0].metadata.name}')
    kubectl exec $pod_name -n $TEST_NAMESPACE -- env | grep -E "(APP_NAME|LOG_LEVEL|REGION)" || true
    
    log_success "Integration test completed"
}

# Create monitoring resources
create_monitoring() {
    log_info "Creating monitoring resources..."
    
    # Create ServiceMonitor for Vault Secrets Operator
    cat <<EOF | kubectl apply -f -
apiVersion: monitoring.coreos.com/v1
kind: ServiceMonitor
metadata:
  name: vault-secrets-operator
  namespace: $VAULT_SECRETS_OPERATOR_NAMESPACE
  labels:
    app.kubernetes.io/name: vault-secrets-operator
spec:
  selector:
    matchLabels:
      app.kubernetes.io/name: vault-secrets-operator
  endpoints:
  - port: metrics
    interval: 30s
    path: /metrics
EOF
    
    # Create basic alerts
    cat <<EOF | kubectl apply -f -
apiVersion: monitoring.coreos.com/v1
kind: PrometheusRule
metadata:
  name: vault-secrets-operator
  namespace: $VAULT_SECRETS_OPERATOR_NAMESPACE
spec:
  groups:
  - name: vault-secrets-operator
    rules:
    - alert: VaultSecretSyncFailure
      expr: vault_secret_sync_errors_total > 0
      for: 5m
      annotations:
        summary: "Vault secret sync failing"
        description: "VaultSecret sync has failed for 5 minutes"
        
    - alert: VaultAuthenticationFailure
      expr: vault_auth_failures_total > 10
      for: 2m
      annotations:
        summary: "High number of Vault authentication failures"
EOF
    
    log_success "Monitoring resources created"
}

# Create utility scripts
create_utilities() {
    log_info "Creating utility scripts..."
    
    # Vault-Kubernetes status script
    cat > ../scripts/k8s-vault-status.sh << 'EOF'
#!/bin/bash
# k8s-vault-status.sh - Check Kubernetes-Vault integration status

echo "Kubernetes-Vault Integration Status"
echo "==================================="

# Check Vault Secrets Operator
echo -e "\n1. Vault Secrets Operator:"
kubectl get pods -n vault-secrets-operator-system

# Check VaultConnections
echo -e "\n2. VaultConnections:"
kubectl get vaultconnection -A

# Check VaultAuth resources
echo -e "\n3. VaultAuth resources:"
kubectl get vaultauth -A

# Check VaultStaticSecrets
echo -e "\n4. VaultStaticSecrets:"
kubectl get vaultstaticsecret -A

# Check VaultDynamicSecrets
echo -e "\n5. VaultDynamicSecrets:"
kubectl get vaultdynamicsecret -A

# Check generated secrets
echo -e "\n6. Generated Kubernetes secrets:"
kubectl get secrets -l "app.kubernetes.io/managed-by=vault-secrets-operator" -A

echo -e "\nStatus check complete."
EOF
    chmod +x ../scripts/k8s-vault-status.sh
    
    # Debug script
    cat > ../scripts/debug-k8s-vault.sh << 'EOF'
#!/bin/bash
# debug-k8s-vault.sh - Debug Kubernetes-Vault integration issues

NAMESPACE="${1:-webapp}"

echo "Debugging Kubernetes-Vault Integration"
echo "======================================"
echo "Namespace: $NAMESPACE"

# Check VaultAuth
echo -e "\n1. VaultAuth status:"
kubectl describe vaultauth -n $NAMESPACE

# Check VaultStaticSecret
echo -e "\n2. VaultStaticSecret status:"
kubectl describe vaultstaticsecret -n $NAMESPACE

# Check VaultDynamicSecret
echo -e "\n3. VaultDynamicSecret status:"
kubectl describe vaultdynamicsecret -n $NAMESPACE

# Check service account
echo -e "\n4. Service account:"
kubectl get serviceaccount -n $NAMESPACE

# Check operator logs
echo -e "\n5. Operator logs (last 20 lines):"
kubectl logs -n vault-secrets-operator-system deployment/vault-secrets-operator-controller-manager --tail=20

# Check events
echo -e "\n6. Recent events:"
kubectl get events -n $NAMESPACE --sort-by='.lastTimestamp'

echo -e "\nDebugging complete."
EOF
    chmod +x ../scripts/debug-k8s-vault.sh
    
    log_success "Utility scripts created"
}

# Generate summary
generate_summary() {
    cat << EOF

${GREEN}===============================================${NC}
${GREEN}  Kubernetes-Vault Integration Complete      ${NC}
${GREEN}===============================================${NC}

${BLUE}Components Installed:${NC}
- Vault Secrets Operator: $(kubectl get pods -n $VAULT_SECRETS_OPERATOR_NAMESPACE --no-headers | wc -l) pods running
- Kubernetes Auth: Configured in Vault
- VaultConnection: default connection configured
- Test Resources: Created in $TEST_NAMESPACE namespace

${BLUE}Vault Configuration:${NC}
- Kubernetes auth method: Enabled
- Vault policies: webapp-policy, platform-policy, dev-policy
- Kubernetes roles: webapp, platform, dev-apps

${BLUE}Test Resources Created:${NC}
- VaultAuth: webapp-auth
- VaultStaticSecret: webapp-config, shared-config
- VaultDynamicSecret: webapp-database (if DB configured), webapp-azure (if Azure configured)
- Test Deployment: webapp with environment variables from Vault

${BLUE}Available Commands:${NC}
# Check integration status
./scripts/k8s-vault-status.sh

# Debug issues
./scripts/debug-k8s-vault.sh $TEST_NAMESPACE

# Check Vault auth from Kubernetes
kubectl exec -n $TEST_NAMESPACE deployment/webapp -- env | grep -E "(APP_NAME|LOG_LEVEL|REGION)"

# View secrets
kubectl get secrets -n $TEST_NAMESPACE
kubectl describe vaultstaticsecret webapp-config -n $TEST_NAMESPACE

${BLUE}Next Steps:${NC}
1. Deploy applications using the patterns shown
2. Configure additional namespaces and VaultAuth resources
3. Set up monitoring and alerting
4. Implement secret rotation policies
5. Configure advanced patterns (CSI driver, Agent injection)

${BLUE}Security Notes:${NC}
- Service accounts are bound to specific Vault roles
- Secrets are namespace-isolated
- Dynamic secrets are automatically rotated
- All secret access is audited in Vault

EOF
}

# Main execution
main() {
    log_info "Starting Kubernetes-Vault integration setup..."
    
    check_prerequisites
    configure_kubernetes_auth
    create_vault_policies
    install_vault_secrets_operator
    configure_vault_connection
    setup_test_namespace
    create_vault_auth
    create_vault_static_secrets
    create_vault_dynamic_secrets
    create_test_deployment
    test_integration
    create_monitoring
    create_utilities
    generate_summary
    
    log_success "Kubernetes-Vault integration setup completed successfully!"
}

main "$@"