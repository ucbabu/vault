# Manual JWT Configuration Guide for HCP Vault + AKS

## Executive Summary

This guide provides step-by-step instructions for configuring JWT authentication between HCP Vault and Azure Kubernetes Service (AKS) when **no network connectivity** exists from HCP Vault to your AKS cluster.

The manual configuration approach eliminates the need for ongoing connectivity while maintaining the same security guarantees as OIDC discovery.

## Prerequisites

### Required Tools
- `kubectl` configured for your AKS cluster
- `vault` CLI authenticated to HCP Vault
- `jq` for JSON processing
- `curl` or `wget` for downloading resources

### Required Permissions
- **AKS**: Read access to cluster configuration and OIDC endpoints
- **HCP Vault**: Admin access to configure auth methods and policies

### Environment Variables
```bash
export VAULT_ADDR="https://your-hcp-vault-cluster.vault.hashicorp.cloud:8200"
export VAULT_TOKEN="your-vault-token"
export VAULT_NAMESPACE="admin"  # For HCP Vault
```

## Step 1: Gather Kubernetes Cluster Information

### 1.1 Get Cluster Details
```bash
# Get API server URL
kubectl config view --raw --minify --flatten -o jsonpath='{.clusters[].cluster.server}'

# Get CA certificate
kubectl config view --raw --minify --flatten -o jsonpath='{.clusters[].cluster.certificate-authority-data}' | base64 -d > k8s-ca.pem

# Get current context name
kubectl config current-context
```

### 1.2 Test OIDC Endpoints
```bash
# Test OIDC discovery endpoint
kubectl get --raw /.well-known/openid_configuration | jq .

# Expected output includes:
# {
#   "issuer": "https://kubernetes.default.svc.cluster.local",
#   "jwks_uri": "https://YOUR_CLUSTER/openid/v1/jwks",
#   ...
# }
```

### 1.3 Fetch JWKS Keys
```bash
# Fetch JSON Web Key Set
kubectl get --raw /openid/v1/jwks | jq . > k8s-jwks.json

# Verify keys were fetched
jq '.keys | length' k8s-jwks.json
jq -r '.keys[] | "Key ID: \(.kid), Algorithm: \(.alg)"' k8s-jwks.json
```

**Sample JWKS Output:**
```json
{
  "keys": [
    {
      "use": "sig",
      "kty": "RSA",
      "kid": "abc123...",
      "alg": "RS256",
      "n": "base64-encoded-modulus...",
      "e": "AQAB"
    }
  ]
}
```

## Step 2: Configure JWT Authentication in HCP Vault

### 2.1 Enable JWT Auth Method
```bash
# Enable JWT auth method
vault auth enable -path=kubernetes-jwt jwt

# Verify it's enabled
vault auth list | grep kubernetes-jwt
```

### 2.2 Configure JWT Auth with Manual JWKS
```bash
# Get your cluster API server URL
K8S_HOST=$(kubectl config view --raw --minify --flatten -o jsonpath='{.clusters[].cluster.server}')

# Configure JWT auth method
vault write auth/kubernetes-jwt/config \
    bound_issuer="https://kubernetes.default.svc.cluster.local" \
    jwks_url="$K8S_HOST/openid/v1/jwks" \
    jwks_ca_pem=@k8s-ca.pem \
    jwt_validation_pubkeys=@k8s-jwks.json
```

**Key Configuration Parameters:**
- `bound_issuer`: Must match the issuer in JWT tokens (always `https://kubernetes.default.svc.cluster.local`)
- `jwks_url`: Reference URL (not actively used in manual mode)
- `jwks_ca_pem`: CA certificate for TLS verification
- `jwt_validation_pubkeys`: Static JWKS keys for signature validation

### 2.3 Verify Configuration
```bash
# Read the configuration
vault read auth/kubernetes-jwt/config

# Expected output should show your configured values
```

## Step 3: Create Policies and Roles

### 3.1 Create Application Policy
```bash
# Create policy file
cat > webapp-policy.hcl << 'EOF'
# Application secrets
path "secret/data/webapp/*" {
  capabilities = ["read"]
}

# Shared configuration
path "secret/data/shared/*" {
  capabilities = ["read"]
}

# Token operations
path "auth/token/lookup-self" {
  capabilities = ["read"]
}

path "auth/token/renew-self" {
  capabilities = ["update"]
}
EOF

# Apply policy to Vault
vault policy write webapp-policy webapp-policy.hcl
```

### 3.2 Create JWT Role
```bash
# Create role for webapp service account
vault write auth/kubernetes-jwt/role/webapp \
    bound_audiences="https://kubernetes.default.svc.cluster.local" \
    bound_subject="system:serviceaccount:webapp:webapp" \
    bound_claims='{
        "kubernetes.io": {
            "namespace": "webapp",
            "serviceaccount": {
                "name": "webapp"
            }
        }
    }' \
    user_claim="sub" \
    policies="webapp-policy" \
    ttl="1h" \
    max_ttl="4h"
```

**Role Configuration Explained:**
- `bound_audiences`: JWT audience claim validation
- `bound_subject`: Expected subject format for service accounts
- `bound_claims`: Additional claims validation for namespace/SA
- `user_claim`: JWT claim to use as the user identity
- `policies`: Vault policies to attach to tokens
- `ttl`/`max_ttl`: Token lifetime settings

### 3.3 Verify Role Creation
```bash
# List roles
vault list auth/kubernetes-jwt/role

# Read role details
vault read auth/kubernetes-jwt/role/webapp
```

## Step 4: Kubernetes Configuration

### 4.1 Create Namespace and Service Account
```bash
# Create namespace
kubectl create namespace webapp

# Create service account
cat <<EOF | kubectl apply -f -
apiVersion: v1
kind: ServiceAccount
metadata:
  name: webapp
  namespace: webapp
  annotations:
    vault.hashicorp.com/auth-method: "kubernetes-jwt"
    vault.hashicorp.com/auth-role: "webapp"
EOF
```

### 4.2 Create Test Secrets in Vault
```bash
# Create application secrets
vault kv put secret/webapp/config \
    app_name="webapp" \
    database_url="postgresql://..." \
    api_key="secret-api-key" \
    auth_method="jwt"

vault kv put secret/shared/config \
    region="eastus" \
    environment="production" \
    log_level="info"
```

## Step 5: Testing and Validation

### 5.1 Test JWT Authentication
```bash
# Create test pod
cat <<EOF | kubectl apply -f -
apiVersion: v1
kind: Pod
metadata:
  name: jwt-test
  namespace: webapp
spec:
  serviceAccountName: webapp
  containers:
  - name: test
    image: vault:latest
    command: ["sh", "-c", "sleep 3600"]
    env:
    - name: VAULT_ADDR
      value: "$VAULT_ADDR"
    - name: VAULT_NAMESPACE
      value: "admin"
  restartPolicy: Never
EOF

# Wait for pod to be ready
kubectl wait --for=condition=Ready pod/jwt-test -n webapp --timeout=60s
```

### 5.2 Authenticate from Pod
```bash
# Execute authentication test
kubectl exec -n webapp jwt-test -- sh -c '
    # Get service account JWT token
    JWT_TOKEN=$(cat /var/run/secrets/kubernetes.io/serviceaccount/token)
    
    # Authenticate to Vault
    VAULT_TOKEN=$(vault write -field=token auth/kubernetes-jwt/login role=webapp jwt=$JWT_TOKEN)
    
    # Test secret access
    export VAULT_TOKEN
    vault kv get secret/webapp/config
'
```

**Expected Success Output:**
```
Key              Value
---              -----
refresh_interval 768h
app_name         webapp
api_key          secret-api-key
auth_method      jwt
database_url     postgresql://...
```

### 5.3 Verify Token Properties
```bash
kubectl exec -n webapp jwt-test -- sh -c '
    JWT_TOKEN=$(cat /var/run/secrets/kubernetes.io/serviceaccount/token)
    VAULT_TOKEN=$(vault write -field=token auth/kubernetes-jwt/login role=webapp jwt=$JWT_TOKEN)
    export VAULT_TOKEN
    
    # Check token info
    vault token lookup
'
```

## Step 6: JWKS Key Rotation Handling

### 6.1 Monitor for Key Rotation
Kubernetes periodically rotates signing keys. Set up monitoring:

```bash
# Create monitoring script
cat > check-jwks-rotation.sh << 'EOF'
#!/bin/bash
CURRENT_KEYS=$(kubectl get --raw /openid/v1/jwks | jq -r '.keys[].kid' | sort)
VAULT_KEYS=$(vault read -field=jwt_validation_pubkeys auth/kubernetes-jwt/config | jq -r '.keys[].kid' | sort)

if [ "$CURRENT_KEYS" != "$VAULT_KEYS" ]; then
    echo "JWKS keys have rotated - update required!"
    exit 1
else
    echo "JWKS keys are current"
    exit 0
fi
EOF

chmod +x check-jwks-rotation.sh
```

### 6.2 Update Process for Key Rotation
```bash
# When rotation is detected, update Vault:

# 1. Fetch new keys
kubectl get --raw /openid/v1/jwks > new-jwks.json

# 2. Update Vault configuration
vault write auth/kubernetes-jwt/config \
    bound_issuer="https://kubernetes.default.svc.cluster.local" \
    jwks_url="$K8S_HOST/openid/v1/jwks" \
    jwks_ca_pem=@k8s-ca.pem \
    jwt_validation_pubkeys=@new-jwks.json

# 3. Test authentication still works
kubectl exec -n webapp jwt-test -- sh -c '
    JWT_TOKEN=$(cat /var/run/secrets/kubernetes.io/serviceaccount/token)
    vault write -field=token auth/kubernetes-jwt/login role=webapp jwt=$JWT_TOKEN
'
```

## Step 7: Production Deployment with Vault Secrets Operator

### 7.1 Install Vault Secrets Operator
```bash
# Add Helm repository
helm repo add hashicorp https://helm.releases.hashicorp.com
helm repo update

# Install operator
helm install vault-secrets-operator hashicorp/vault-secrets-operator \
    --namespace vault-secrets-operator-system \
    --create-namespace \
    --set defaultVaultConnection.enabled=true \
    --set defaultVaultConnection.address="$VAULT_ADDR"
```

### 7.2 Configure VaultConnection
```bash
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
EOF
```

### 7.3 Configure VaultAuth
```bash
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
```

### 7.4 Create VaultStaticSecret
```bash
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

### 7.5 Verify Secret Synchronization
```bash
# Check VaultAuth status
kubectl get vaultauth webapp-auth -n webapp -o yaml

# Check secret creation
kubectl get secret webapp-config -n webapp

# View secret data
kubectl get secret webapp-config -n webapp -o jsonpath='{.data}' | jq 'to_entries[] | {key: .key, value: (.value | @base64d)}'
```

## Troubleshooting Guide

### Common Issues and Solutions

#### 1. JWT Validation Failures
**Error:** `invalid JWT token`

**Solutions:**
```bash
# Check if JWKS keys are current
kubectl get --raw /openid/v1/jwks | jq '.keys[].kid'
vault read -field=jwt_validation_pubkeys auth/kubernetes-jwt/config | jq '.keys[].kid'

# Update keys if they differ
kubectl get --raw /openid/v1/jwks > updated-jwks.json
vault write auth/kubernetes-jwt/config jwt_validation_pubkeys=@updated-jwks.json
```

#### 2. Permission Denied Errors
**Error:** `permission denied`

**Solutions:**
```bash
# Check policy assignment
vault read auth/kubernetes-jwt/role/webapp

# Test policy directly
vault policy read webapp-policy

# Check token capabilities
vault token capabilities secret/webapp/config
```

#### 3. Service Account Token Issues
**Error:** `service account token not found`

**Solutions:**
```bash
# For Kubernetes 1.24+, manually create token
kubectl create token webapp --namespace webapp --duration 8760h

# Or create a long-lived secret
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
```

#### 4. Network Connectivity Verification
```bash
# Confirm no connectivity is required
# Run this from outside your network
curl -k -H "Authorization: Bearer $VAULT_TOKEN" \
     "$VAULT_ADDR/v1/auth/kubernetes-jwt/config"

# Should work without access to your AKS cluster
```

## Security Considerations

### 1. JWKS Key Security
- Store JWKS keys securely during manual updates
- Rotate Vault tokens used for configuration
- Monitor for unauthorized changes to JWT configuration

### 2. Service Account Security
- Use dedicated service accounts per application
- Apply principle of least privilege in policies
- Regular audit of service account permissions

### 3. Token Lifecycle
- Configure appropriate TTL values
- Implement token renewal strategies
- Monitor token usage patterns

## Migration from TokenReview

If migrating from TokenReview authentication:

### 1. Parallel Deployment
```bash
# Keep existing kubernetes auth
vault auth list | grep "kubernetes/"

# Add new JWT auth alongside
vault auth enable -path=kubernetes-jwt jwt
```

### 2. Gradual Migration
```bash
# Test applications with JWT auth
# Update VaultAuth resources to use jwt method
# Verify functionality before removing TokenReview
```

### 3. Cleanup TokenReview
```bash
# After successful migration
vault auth disable kubernetes
```

## Conclusion

This manual configuration approach provides:

✅ **Zero connectivity dependency** from HCP Vault to AKS during runtime  
✅ **High performance** with local JWT validation  
✅ **Enterprise security** with proper claim validation  
✅ **Operational simplicity** with automated secret synchronization  

The only maintenance requirement is updating JWKS keys when Kubernetes rotates them, which can be automated with the provided monitoring scripts.