# AKS + HCP Vault Connectivity Troubleshooting Guide

## Overview

This guide helps diagnose and resolve connectivity issues between Azure Kubernetes Service (AKS) and HashiCorp Cloud Platform (HCP) Vault, specifically focusing on JWT/OIDC authentication challenges.

## Common Connectivity Issues

### 1. No Network Connectivity from HCP Vault to AKS

**Symptoms:**
- OIDC discovery failures in Vault logs
- JWT authentication works but keys become stale
- Error: "failed to fetch OIDC discovery metadata"

**Root Cause:**
HCP Vault cannot reach your AKS cluster's API server for OIDC discovery or JWKS key refresh.

**Solutions:**

#### Solution A: Manual JWKS Configuration (Recommended)
```bash
# 1. Fetch current JWKS keys from AKS
kubectl get --raw /openid/v1/jwks > k8s-jwks.json

# 2. Configure Vault with static keys
vault write auth/kubernetes-jwt/config \
    bound_issuer="https://kubernetes.default.svc.cluster.local" \
    jwt_validation_pubkeys=@k8s-jwks.json

# 3. Test authentication
kubectl run jwt-test --rm -i --tty --serviceaccount=webapp --image=vault:latest -- sh
# Inside pod: authenticate and test
```

#### Solution B: Establish Limited Connectivity
```bash
# Option 1: VPN/Private Peering
# Set up Azure VPN Gateway to HCP network
# Configure routes for Kubernetes API server access only

# Option 2: HTTP Proxy
# Deploy proxy in DMZ, configure HCP Vault to use proxy
# for /.well-known/openid_configuration and /openid/v1/jwks endpoints
```

### 2. Authentication Failures After Setup

**Symptoms:**
- Error: "invalid JWT signature"
- Error: "unknown kid in JWT header"
- Previously working authentication suddenly fails

**Diagnostic Commands:**
```bash
# Check current JWKS keys in AKS
kubectl get --raw /openid/v1/jwks | jq '.keys[].kid'

# Check keys configured in Vault
vault read -field=jwt_validation_pubkeys auth/kubernetes-jwt/config | jq '.keys[].kid'

# Compare service account token structure
kubectl get serviceaccount webapp -n webapp -o yaml
kubectl create token webapp -n webapp --duration=3600s | base64 -d | jq .
```

**Solutions:**
```bash
# If keys don't match, update Vault with current keys
kubectl get --raw /openid/v1/jwks > updated-jwks.json
vault write auth/kubernetes-jwt/config \
    bound_issuer="https://kubernetes.default.svc.cluster.local" \
    jwt_validation_pubkeys=@updated-jwks.json

# Test authentication again
kubectl exec -n webapp jwt-test -- sh -c '
    JWT_TOKEN=$(cat /var/run/secrets/kubernetes.io/serviceaccount/token)
    vault write -field=token auth/kubernetes-jwt/login role=webapp jwt=$JWT_TOKEN
'
```

### 3. Service Account Token Issues

**Symptoms:**
- Error: "service account token not found"
- Error: "audience claim validation failed"
- Empty or missing JWT token

**Diagnostic Commands:**
```bash
# Check service account exists
kubectl get serviceaccount webapp -n webapp

# Check token availability (K8s 1.24+)
kubectl get secret | grep webapp
ls -la /var/run/secrets/kubernetes.io/serviceaccount/

# Check token claims
kubectl create token webapp -n webapp --audience=https://kubernetes.default.svc.cluster.local | 
    cut -d. -f2 | base64 -d | jq .
```

**Solutions:**

#### For Kubernetes 1.24+ (No Auto-Generated Tokens)
```bash
# Create token manually
cat <<EOF | kubectl apply -f -
apiVersion: v1
kind: Secret
metadata:
  name: webapp-token
  namespace: webapp
  annotations:
    kubernetes.io/service-account.name: webapp
type: kubernetes.io/service-account-token
EOF

# Or use projected volumes in pod spec
cat <<EOF | kubectl apply -f -
apiVersion: v1
kind: Pod
metadata:
  name: webapp-pod
spec:
  serviceAccountName: webapp
  volumes:
  - name: vault-token
    projected:
      sources:
      - serviceAccountToken:
          path: token
          audience: https://kubernetes.default.svc.cluster.local
  containers:
  - name: app
    image: nginx
    volumeMounts:
    - name: vault-token
      mountPath: /var/run/secrets/tokens
EOF
```

#### For Audience Claim Issues
```bash
# Verify JWT role configuration
vault read auth/kubernetes-jwt/role/webapp

# Update role with correct audience
vault write auth/kubernetes-jwt/role/webapp \
    bound_audiences="https://kubernetes.default.svc.cluster.local" \
    bound_subject="system:serviceaccount:webapp:webapp" \
    policies="webapp-policy"
```

### 4. Permission Denied Errors

**Symptoms:**
- Error: "permission denied accessing secret"
- Authentication succeeds but secret access fails
- Error: "insufficient privileges"

**Diagnostic Commands:**
```bash
# Check token capabilities
vault token capabilities secret/webapp/config

# Check assigned policies
vault token lookup | grep policies

# Test policy directly
vault policy read webapp-policy

# Check secret path exists
vault kv list secret/
vault kv get secret/webapp/config
```

**Solutions:**
```bash
# Fix policy issues
cat > webapp-policy.hcl << 'EOF'
# Correct paths for KV v2
path "secret/data/webapp/*" {
  capabilities = ["read"]
}

path "secret/metadata/webapp/*" {
  capabilities = ["list", "read"]
}
EOF

vault policy write webapp-policy webapp-policy.hcl

# Update role if needed
vault write auth/kubernetes-jwt/role/webapp \
    policies="webapp-policy" \
    # ... other parameters
```

### 5. Vault Secrets Operator Issues

**Symptoms:**
- VaultAuth resource shows authentication errors
- Secrets not synchronizing to Kubernetes
- Error: "failed to authenticate to Vault"

**Diagnostic Commands:**
```bash
# Check VaultAuth status
kubectl get vaultauth webapp-auth -n webapp -o yaml

# Check operator logs
kubectl logs -l app.kubernetes.io/name=vault-secrets-operator -n vault-secrets-operator-system

# Check VaultConnection
kubectl get vaultconnection -n vault-secrets-operator-system -o yaml

# Check secret sync status
kubectl get vaultstaticsecret webapp-config -n webapp -o yaml
```

**Solutions:**
```bash
# Fix VaultConnection for HCP Vault
cat <<EOF | kubectl apply -f -
apiVersion: secrets.hashicorp.com/v1beta1
kind: VaultConnection
metadata:
  name: default
  namespace: vault-secrets-operator-system
spec:
  address: $VAULT_ADDR
  headers:
    X-Vault-Namespace: admin
  skipTLSVerify: false
EOF

# Fix VaultAuth for JWT method
cat <<EOF | kubectl apply -f -
apiVersion: secrets.hashicorp.com/v1beta1
kind: VaultAuth
metadata:
  name: webapp-auth
  namespace: webapp
spec:
  vaultConnectionRef: vault-secrets-operator-system/default
  method: jwt
  mount: kubernetes-jwt
  jwt:
    role: webapp
    serviceAccount: webapp
EOF

# Check and fix secret paths
cat <<EOF | kubectl apply -f -
apiVersion: secrets.hashicorp.com/v1beta1
kind: VaultStaticSecret
metadata:
  name: webapp-config
  namespace: webapp
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
```

## Debugging Tools and Commands

### 1. Network Connectivity Testing
```bash
# Test from HCP Vault perspective (if you have access)
# This shows what HCP Vault sees when trying to reach your cluster

# From a machine with HCP Vault access:
curl -k "https://your-aks-cluster/.well-known/openid_configuration"
curl -k "https://your-aks-cluster/openid/v1/jwks"

# From your local machine (simulating HCP Vault):
kubectl config view --raw --minify --flatten -o jsonpath='{.clusters[].cluster.server}'
# Try to access this URL from HCP Vault's perspective
```

### 2. JWT Token Analysis
```bash
# Create and analyze a service account token
TOKEN=$(kubectl create token webapp -n webapp --audience=https://kubernetes.default.svc.cluster.local)

# Decode header
echo $TOKEN | cut -d. -f1 | base64 -d | jq .

# Decode payload
echo $TOKEN | cut -d. -f2 | base64 -d | jq .

# Check token expiration
echo $TOKEN | cut -d. -f2 | base64 -d | jq '.exp | todate'
```

### 3. Vault Configuration Verification
```bash
# Check JWT auth method configuration
vault read auth/kubernetes-jwt/config

# List available roles
vault list auth/kubernetes-jwt/role

# Check specific role configuration
vault read auth/kubernetes-jwt/role/webapp

# Test authentication manually
vault write auth/kubernetes-jwt/login role=webapp jwt=$TOKEN
```

### 4. JWKS Key Monitoring
```bash
# Create monitoring script for key rotation
cat > monitor-jwks.sh << 'EOF'
#!/bin/bash
set -e

echo "Checking JWKS key rotation..."

# Get current keys from AKS
AKS_KEYS=$(kubectl get --raw /openid/v1/jwks | jq -c '.keys | sort_by(.kid)')

# Get keys from Vault
VAULT_KEYS=$(vault read -field=jwt_validation_pubkeys auth/kubernetes-jwt/config | jq -c '.keys | sort_by(.kid)')

if [ "$AKS_KEYS" != "$VAULT_KEYS" ]; then
    echo "❌ JWKS keys have rotated!"
    echo "AKS keys:"
    echo "$AKS_KEYS" | jq '.[] | .kid'
    echo "Vault keys:"
    echo "$VAULT_KEYS" | jq '.[] | .kid'
    
    # Auto-update if desired
    read -p "Update Vault with new keys? (y/N): " -r
    if [[ $REPLY =~ ^[Yy]$ ]]; then
        kubectl get --raw /openid/v1/jwks > new-jwks.json
        vault write auth/kubernetes-jwt/config \
            bound_issuer="https://kubernetes.default.svc.cluster.local" \
            jwt_validation_pubkeys=@new-jwks.json
        echo "✅ Vault updated with new keys"
    fi
else
    echo "✅ JWKS keys are current"
fi
EOF

chmod +x monitor-jwks.sh
```

## Step-by-Step Diagnostic Process

### Step 1: Verify Basic Connectivity
```bash
# 1. Can you reach your AKS API server?
kubectl cluster-info

# 2. Are OIDC endpoints accessible?
kubectl get --raw /.well-known/openid_configuration
kubectl get --raw /openid/v1/jwks

# 3. Is Vault accessible?
vault status
vault auth list
```

### Step 2: Check Configuration Alignment
```bash
# 1. Compare issuer claims
kubectl get --raw /.well-known/openid_configuration | jq '.issuer'
vault read auth/kubernetes-jwt/config | grep bound_issuer

# 2. Compare JWKS keys
kubectl get --raw /openid/v1/jwks | jq '.keys[].kid'
vault read -field=jwt_validation_pubkeys auth/kubernetes-jwt/config | jq '.keys[].kid'

# 3. Check service account configuration
kubectl get serviceaccount webapp -n webapp -o yaml
vault read auth/kubernetes-jwt/role/webapp
```

### Step 3: Test Authentication Flow
```bash
# 1. Create test pod
kubectl run debug-pod --rm -i --tty --serviceaccount=webapp -n webapp --image=vault:latest -- sh

# 2. Inside pod, test each step
# Get token
JWT_TOKEN=$(cat /var/run/secrets/kubernetes.io/serviceaccount/token)
echo $JWT_TOKEN | cut -d. -f2 | base64 -d | jq .

# Test Vault connection
vault status

# Test authentication
vault write -field=token auth/kubernetes-jwt/login role=webapp jwt=$JWT_TOKEN

# Test secret access
export VAULT_TOKEN=<token-from-previous-step>
vault kv get secret/webapp/config
```

### Step 4: Check Vault Secrets Operator
```bash
# 1. Verify operator status
kubectl get deployment -n vault-secrets-operator-system
kubectl get pods -n vault-secrets-operator-system

# 2. Check resource statuses
kubectl get vaultconnection -A
kubectl get vaultauth -A
kubectl get vaultstaticsecret -A

# 3. Review logs for errors
kubectl logs -l app.kubernetes.io/name=vault-secrets-operator -n vault-secrets-operator-system --tail=50
```

## Common Error Messages and Solutions

| Error Message | Root Cause | Solution |
|---------------|------------|----------|
| `failed to fetch OIDC discovery metadata` | No connectivity from HCP to AKS | Use manual JWKS configuration |
| `invalid JWT signature` | JWKS keys have rotated | Update Vault with current keys |
| `unknown kid in JWT header` | Key ID not found in Vault | Refresh JWKS keys in Vault |
| `audience claim validation failed` | Wrong audience in JWT | Check bound_audiences in role |
| `permission denied` | Policy doesn't allow access | Update Vault policies |
| `service account token not found` | K8s 1.24+ token changes | Create explicit token or use projected volumes |
| `authentication failed` | Role/claims mismatch | Verify role configuration matches SA |

## Prevention and Monitoring

### 1. Automated Key Rotation Monitoring
```bash
# Set up cron job for key monitoring
cat > /etc/cron.d/vault-jwks-monitor << 'EOF'
# Check JWKS keys every hour
0 * * * * /usr/local/bin/monitor-jwks.sh >> /var/log/vault-jwks.log 2>&1
EOF
```

### 2. Health Check Endpoints
```bash
# Create health check script
cat > health-check.sh << 'EOF'
#!/bin/bash
# Test end-to-end authentication

kubectl run health-check --rm -i --tty --serviceaccount=webapp -n webapp --image=vault:latest -- sh -c '
JWT_TOKEN=$(cat /var/run/secrets/kubernetes.io/serviceaccount/token)
if VAULT_TOKEN=$(vault write -field=token auth/kubernetes-jwt/login role=webapp jwt=$JWT_TOKEN 2>/dev/null); then
    export VAULT_TOKEN
    if vault kv get secret/webapp/config >/dev/null 2>&1; then
        echo "✅ Health check passed"
        exit 0
    else
        echo "❌ Secret access failed"
        exit 1
    fi
else
    echo "❌ Authentication failed"
    exit 1
fi
' 2>/dev/null

echo "Health check completed with exit code: $?"
EOF
```

### 3. Alerting Setup
```bash
# Example Prometheus alert for authentication failures
cat > vault-auth-alerts.yaml << 'EOF'
groups:
- name: vault.auth
  rules:
  - alert: VaultAuthenticationFailure
    expr: increase(vault_auth_login_total{auth_method="kubernetes-jwt",success="false"}[5m]) > 5
    for: 2m
    labels:
      severity: warning
    annotations:
      summary: "Vault JWT authentication failures detected"
      description: "Multiple JWT authentication failures in the last 5 minutes"

  - alert: VaultJWKSKeysStale
    expr: time() - vault_auth_jwt_last_jwks_fetch_timestamp > 86400
    for: 5m
    labels:
      severity: critical
    annotations:
      summary: "Vault JWKS keys may be stale"
      description: "JWKS keys haven't been refreshed in over 24 hours"
EOF
```

This troubleshooting guide should help you diagnose and resolve the most common connectivity and authentication issues between AKS and HCP Vault.