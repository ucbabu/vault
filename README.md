# HashiCorp Vault Cloud Onboarding Project

This repository contains the complete EPIC documentation and implementation guides for onboarding HashiCorp Vault Cloud for keystore management and dynamic key rotation across Azure services and databases.

## 📋 Project Overview

**Epic:** Onboard HashiCorp Vault Cloud for Keystore Management and Dynamic Key Rotation  
**Status:** In Progress  
**Timeline:** 10-14 weeks  
**Priority:** High  

## 🎯 Business Goals

- Establish HashiCorp Vault Cloud as the centralized secrets management platform
- Implement secure keystore management with proper access controls
- Enable dynamic key rotation for Azure services to reduce long-lived credential risks
- Implement database dynamic credential rotation for enhanced security
- Integrate Kubernetes with Vault using native authentication and Secrets Operator
- Provide multiple secret consumption patterns for Kubernetes workloads
- Ensure high availability, monitoring, and disaster recovery capabilities

## 📁 Repository Structure

```
vault/
├── EPIC-Vault-Cloud-Onboarding.md     # Main EPIC with all stories and requirements
├── docs/
│   ├── vault-introduction/
│   │   └── 01-introduction-to-hashicorp-vault.md
│   ├── setup-guides/
│   │   └── 02-vault-cloud-setup-guide.md
│   ├── user-guides/
│   │   ├── 03-keystore-management-guide.md
│   │   ├── 04-azure-dynamic-key-rotation.md
│   │   ├── 05-database-dynamic-key-rotation.md
│   │   ├── 06-kubernetes-vault-integration.md
│   │   ├── 07-advanced-kubernetes-patterns.md
│   │   └── 08-multi-team-onboarding.md
│   └── operations/
├── terraform/                          # Infrastructure as Code for Azure deployment
│   ├── main.tf
│   ├── variables.tf
│   ├── outputs.tf
│   └── terraform.tfvars.example
├── scripts/                           # Automation scripts
│   ├── vault-initial-setup.sh
│   ├── hcp-org-sso-setup.sh
│   ├── azure-ad-hcp-sso-setup.sh
│   ├── hcp-terraform-vault-setup.sh      # HCP Terraform integration setup
│   ├── keystore-setup.sh
│   ├── azure-setup.sh
│   ├── database-setup.sh
│   ├── kubernetes-vault-setup.sh
│   ├── kubernetes-vault-jwt-setup.sh     # Enhanced JWT auth for no-connectivity scenarios
│   └── team-onboarding.sh
├── examples/                          # Integration examples
│   ├── python/
│   ├── kubernetes/
│   │   ├── app-deployment.yaml
│   │   └── multi-team-deployment.yaml
│   ├── hcp-terraform/                # HCP Terraform integration examples
│   │   ├── README.md
│   │   ├── basic-deployment/
│   │   ├── workspace-configuration/
│   │   └── advanced-deployment/
│   └── docker/
└── README.md
```

## 📚 Documentation

### 1. Introduction and Concepts
- **[Introduction to HashiCorp Vault](docs/vault-introduction/01-introduction-to-hashicorp-vault.md)**
  - Core concepts and architecture
  - Security model and benefits
  - Use cases and best practices

### 2. Setup and Configuration
- **[Vault Cloud Setup Guide](docs/setup-guides/02-vault-cloud-setup-guide.md)**
  - Complete installation and configuration
  - Authentication methods setup
  - Network configuration and security hardening

- **[HCP Organization SSO Setup](docs/setup-guides/03-hcp-organization-sso-setup.md)**
  - Single Sign-On configuration for HCP Organization
  - OIDC and SAML identity provider integration
  - Centralized authentication and user management
  - Role-based access control and group mappings

- **[Azure AD HCP SSO Setup](docs/setup-guides/04-azure-ad-hcp-sso-setup.md)**
  - Azure AD/Entra ID specific SSO configuration
  - Step-by-step Azure AD application setup
  - Automated scripts for Azure AD integration
  - Group mappings and conditional access

- **[HCP Terraform Vault Integration](docs/setup-guides/09-hcp-terraform-vault-integration.md)**
  - HCP Terraform workspace configuration with Vault dynamic credentials
  - JWT authentication setup for HCP Terraform workspaces
  - Azure dynamic credential integration for infrastructure deployment
  - Automated setup scripts and comprehensive examples
  - Security best practices and monitoring guidelines

### 3. User Guides
- **[Keystore Management Guide](docs/user-guides/03-keystore-management-guide.md)**
  - KV secrets engine configuration
  - Secret organization and lifecycle management
  - Application integration patterns

- **[Azure Dynamic Key Rotation](docs/user-guides/04-azure-dynamic-key-rotation.md)**
  - Azure secrets engine setup
  - Service principal management
  - Dynamic credential generation and renewal

- **[Database Dynamic Key Rotation](docs/user-guides/05-database-dynamic-key-rotation.md)**
  - Database secrets engine configuration
  - Support for PostgreSQL, MySQL, MongoDB, and more
  - Application integration examples

- **[Kubernetes Vault Integration](docs/user-guides/06-kubernetes-vault-integration.md)**
  - Kubernetes authentication with Vault
  - Vault Secrets Operator deployment and configuration
  - VaultAuth, VaultStaticSecret, and VaultDynamicSecret CRDs
  - Multiple secret consumption patterns

- **[Advanced Kubernetes Patterns](docs/user-guides/07-advanced-kubernetes-patterns.md)**
  - Vault Agent Injector patterns (init containers and sidecars)
  - Secrets Store CSI Driver integration
  - GitOps workflows and multi-namespace patterns
  - Performance optimization and security best practices

- **[Multi-Team Onboarding with Vault Namespaces](docs/user-guides/08-multi-team-onboarding.md)**
  - HCP Vault namespace setup for multiple teams
  - Kubernetes namespace mapping and isolation
  - Automated team onboarding process
  - Access management and governance patterns
  - Cross-team secret sharing strategies

- **[HCP Terraform Vault Integration Overview](docs/user-guides/09-hcp-terraform-vault-integration-overview.md)**
  - Complete overview of HCP Terraform integration with Vault
  - Dynamic Azure credentials for infrastructure deployment
  - Security benefits and architecture explanation
  - Quick start guide and usage examples
  - Best practices and troubleshooting guide

### 4. Special Solutions
- **[AKS + HCP Vault No-Connectivity Solution](docs/solutions/aks-hcp-no-connectivity-solution.md)**
  - Complete solution for AKS integration when HCP Vault cannot reach Kubernetes
  - Manual JWKS configuration for JWT authentication
  - Zero network dependency implementation
  - Production-ready scripts and automation

- **[Manual JWT Configuration Guide](docs/guides/manual-jwt-configuration.md)**
  - Step-by-step manual configuration when no connectivity exists
  - JWKS key management and rotation procedures
  - Comprehensive testing and validation

- **[JWT Authentication Callback Comparison](docs/comparisons/jwt-callback-comparison.md)**
  - Detailed comparison of TokenReview vs JWT/OIDC authentication
  - Network connectivity requirements and solutions
  - Performance impact analysis

- **[AKS-HCP Connectivity Troubleshooting](docs/troubleshooting/aks-hcp-connectivity.md)**
  - Common connectivity issues and solutions
  - Step-by-step diagnostic procedures
  - Error message reference and resolution guide

## 🎫 Epic Stories

### Story 1: Set up HashiCorp Vault Cloud Instance (8 points)
- [x] Vault Cloud instance provisioned
- [x] Initial authentication methods configured
- [x] Network security controls implemented
- [x] Admin policies and users configured

### Story 2: Implement Keystore Management (5 points)
- [x] KV v2 secrets engine enabled
- [x] Namespace structure designed
- [x] Role-based access control implemented
- [x] Documentation complete

### Story 3: Configure Azure Dynamic Key Rotation (13 points)
- [x] Azure secrets engine enabled
- [x] Service principal roles defined
- [x] Dynamic credential generation tested
- [x] Integration patterns documented

### Story 4: Implement Database Dynamic Key Rotation (13 points)
- [x] Database secrets engine configured
- [x] Multiple database support implemented
- [x] Application integration examples provided
- [x] Best practices documented

### Story 5: Set up Monitoring and Alerting (8 points)
- [ ] Vault metrics exported to monitoring system
- [ ] Dashboards created for key operational metrics
- [ ] Alerts configured for critical events
- [ ] Implementation pending

### Story 6: Configure Kubernetes Authentication and Vault Secrets Operator (10 points)
- [x] Kubernetes authentication method enabled and configured in Vault
- [x] Service account token reviewer configured for Kubernetes auth
- [x] Kubernetes roles and policies created for different namespaces
- [x] Vault Secrets Operator deployed and configured in Kubernetes cluster
- [x] VaultAuth and VaultStaticSecret custom resources tested
- [x] Dynamic secret integration with VaultDynamicSecret tested
- [x] Secret rotation and renewal policies configured
- [x] Integration with multiple Kubernetes namespaces verified

### Story 7: Implement Advanced Kubernetes Secret Management Patterns (8 points)
- [x] Vault Agent init container pattern implemented and tested
- [x] Vault Agent sidecar injection configured with annotations
- [x] Secrets Store CSI Driver integration configured
- [x] SecretProviderClass resources created for different secret types
- [x] Volume mounting of secrets tested and verified
- [x] Secret rotation and updates handled gracefully
- [x] Performance and resource usage optimized
- [x] Security isolation between namespaces verified

### Story 8: Implement Multi-Team Onboarding with Vault Namespaces (13 points)
- [x] HCP Vault namespace architecture designed for multi-team isolation
- [x] Automated team onboarding script created with comprehensive configuration
- [x] Team-specific Kubernetes authentication and authorization implemented
- [x] Environment-based access policies created (dev/staging/prod separation)
- [x] Vault Secrets Operator integration configured per team namespace
- [x] Cross-team governance and monitoring patterns established
- [x] OIDC and userpass authentication methods configured per team
- [x] Documentation and examples created for team onboarding process
- [x] Network isolation policies implemented in Kubernetes
- [x] Audit logging and compliance patterns configured per namespace

### Story 9: Implement Backup and Disaster Recovery (8 points)
- [ ] Automated backup procedures implemented
- [ ] Disaster recovery runbooks created
- [ ] Recovery procedures documented
- [ ] Implementation pending

## 🚀 Quick Start

### Prerequisites
- HashiCorp Cloud Platform (HCP) account
- Azure subscription with appropriate permissions
- Kubernetes cluster access with admin privileges
- Database access for testing
- Network connectivity planning

### Basic Setup
1. **Review the EPIC document**: Start with [EPIC-Vault-Cloud-Onboarding.md](EPIC-Vault-Cloud-Onboarding.md)
2. **Configure HCP Organization SSO**: Set up centralized authentication with [HCP Organization SSO Setup](docs/setup-guides/03-hcp-organization-sso-setup.md)
3. **Follow setup guide**: Use [Vault Cloud Setup Guide](docs/setup-guides/02-vault-cloud-setup-guide.md)
4. **Configure keystore**: Implement using [Keystore Management Guide](docs/user-guides/03-keystore-management-guide.md)
5. **Enable dynamic rotation**: Follow Azure and database guides as needed
6. **Setup Kubernetes integration**: Configure using [Kubernetes Vault Integration](docs/user-guides/06-kubernetes-vault-integration.md)
7. **Implement advanced patterns**: Deploy using [Advanced Kubernetes Patterns](docs/user-guides/07-advanced-kubernetes-patterns.md)
8. **Onboard multiple teams**: Use [Multi-Team Onboarding Guide](docs/user-guides/08-multi-team-onboarding.md) for namespace isolation

### Multi-Team Onboarding
```bash
# Automated team onboarding with HCP Vault namespaces
./scripts/team-onboarding.sh team-alpha

# Team with custom environments and cloud engines
./scripts/team-onboarding.sh -e "dev,test,staging,prod" -c -d team-beta

# Preview changes before applying
./scripts/team-onboarding.sh --dry-run team-gamma
```

### Environment Variables
```bash
# Vault configuration
export VAULT_ADDR="https://your-vault-cluster.vault.hashicorp.cloud:8200"
export VAULT_NAMESPACE="admin"
export VAULT_TOKEN="your-vault-token"

# Azure configuration
export AZURE_SUBSCRIPTION_ID="your-subscription-id"
export AZURE_TENANT_ID="your-tenant-id"

# Kubernetes configuration
export KUBECONFIG="/path/to/your/kubeconfig"
export KUBERNETES_NAMESPACE="vault-secrets-operator-system"
```

## 🏢 Multi-Team Onboarding with HCP Vault Namespaces

### Overview
HCP Vault provides namespace isolation that enables multiple teams to securely share a single Vault cluster while maintaining complete separation of their secrets and policies. Each Kubernetes namespace can be mapped to a specific Vault namespace, providing granular access control and organizational boundaries.

### Vault Namespace Architecture
```
vault/
├── admin/                     # Root admin namespace
├── platform/                  # Platform engineering team
│   ├── shared/               # Shared platform resources
│   ├── monitoring/           # Monitoring and observability
│   └── infrastructure/       # Infrastructure secrets
├── team-alpha/               # Development team Alpha
│   ├── dev/                  # Development environment
│   ├── staging/              # Staging environment
│   └── prod/                 # Production environment
├── team-beta/                # Development team Beta
│   ├── dev/
│   ├── staging/
│   └── prod/
├── security/                 # Security team namespace
│   ├── policies/             # Security policies
│   └── audit/                # Audit configurations
└── data-engineering/         # Data engineering team
    ├── pipelines/            # Data pipeline secrets
    ├── databases/            # Database credentials
    └── analytics/            # Analytics tools
```

### Team Onboarding Process

#### 1. Vault Namespace Setup
```bash
# Create team namespace (admin privilege required)
vault namespace create team-alpha

# Set namespace context
export VAULT_NAMESPACE="team-alpha"

# Enable KV secrets engine for the team
vault secrets enable -path=secrets kv-v2

# Enable database secrets engine if needed
vault secrets enable database

# Enable cloud provider secrets engines as needed
vault secrets enable -path=azure azure
vault secrets enable -path=aws aws
vault secrets enable -path=gcp gcp
```

#### 2. Team-Specific Policies
```bash
# Create team admin policy
cat > team-alpha-admin.hcl << 'EOF'
# Full access to team namespace
path "secrets/*" {
  capabilities = ["create", "read", "update", "delete", "list"]
}

path "database/*" {
  capabilities = ["create", "read", "update", "delete", "list"]
}

path "azure/*" {
  capabilities = ["create", "read", "update", "delete", "list"]
}

# Manage team policies
path "sys/policies/acl/team-alpha-*" {
  capabilities = ["create", "read", "update", "delete", "list"]
}

# Manage team auth methods
path "sys/auth/team-alpha-*" {
  capabilities = ["create", "read", "update", "delete"]
}

# View team audit logs
path "sys/audit" {
  capabilities = ["read", "list"]
}
EOF

vault policy write team-alpha-admin team-alpha-admin.hcl -namespace=team-alpha

# Create team developer policy
cat > team-alpha-dev.hcl << 'EOF'
# Read/write access to dev environment
path "secrets/data/dev/*" {
  capabilities = ["create", "read", "update", "delete", "list"]
}

path "secrets/metadata/dev/*" {
  capabilities = ["read", "list", "delete"]
}

# Read-only access to staging
path "secrets/data/staging/*" {
  capabilities = ["read"]
}

# Generate dev database credentials
path "database/creds/dev-*" {
  capabilities = ["read"]
}

# Generate dev cloud credentials
path "azure/creds/dev-*" {
  capabilities = ["read"]
}
EOF

vault policy write team-alpha-dev team-alpha-dev.hcl -namespace=team-alpha

# Create team production policy
cat > team-alpha-prod.hcl << 'EOF'
# Read-only access to production secrets
path "secrets/data/prod/*" {
  capabilities = ["read"]
}

# Generate production database credentials
path "database/creds/prod-*" {
  capabilities = ["read"]
}

# Generate production cloud credentials
path "azure/creds/prod-*" {
  capabilities = ["read"]
}
EOF

vault policy write team-alpha-prod team-alpha-prod.hcl -namespace=team-alpha
```

#### 3. Kubernetes Authentication per Team
```bash
# Enable Kubernetes auth for the team
vault auth enable -path=team-alpha-k8s kubernetes -namespace=team-alpha

# Configure Kubernetes auth
vault write auth/team-alpha-k8s/config \
    token_reviewer_jwt="$(kubectl create token vault-auth -n vault-secrets-operator-system --duration=8760h)" \
    kubernetes_host="$(kubectl config view --raw --minify --flatten -o jsonpath='{.clusters[].cluster.server}')" \
    kubernetes_ca_cert="$(kubectl config view --raw --minify --flatten -o jsonpath='{.clusters[].cluster.certificate-authority-data}' | base64 -d)" \
    issuer="https://kubernetes.default.svc.cluster.local" \
    -namespace=team-alpha

# Create Kubernetes roles for different environments
vault write auth/team-alpha-k8s/role/dev \
    bound_service_account_names=* \
    bound_service_account_namespaces=team-alpha-dev \
    policies=team-alpha-dev \
    ttl=1h \
    max_ttl=4h \
    -namespace=team-alpha

vault write auth/team-alpha-k8s/role/staging \
    bound_service_account_names=* \
    bound_service_account_namespaces=team-alpha-staging \
    policies=team-alpha-dev \
    ttl=30m \
    max_ttl=2h \
    -namespace=team-alpha

vault write auth/team-alpha-k8s/role/prod \
    bound_service_account_names=* \
    bound_service_account_namespaces=team-alpha-prod \
    policies=team-alpha-prod \
    ttl=15m \
    max_ttl=1h \
    -namespace=team-alpha
```

#### 4. Kubernetes Namespace Setup
```bash
# Create Kubernetes namespaces for the team
kubectl create namespace team-alpha-dev
kubectl create namespace team-alpha-staging
kubectl create namespace team-alpha-prod

# Label namespaces for identification
kubectl label namespace team-alpha-dev vault-namespace=team-alpha
kubectl label namespace team-alpha-staging vault-namespace=team-alpha
kubectl label namespace team-alpha-prod vault-namespace=team-alpha

kubectl label namespace team-alpha-dev environment=dev
kubectl label namespace team-alpha-staging environment=staging
kubectl label namespace team-alpha-prod environment=prod
```

#### 5. Vault Secrets Operator Configuration per Team
```yaml
# VaultConnection for team-alpha
apiVersion: secrets.hashicorp.com/v1beta1
kind: VaultConnection
metadata:
  name: team-alpha-vault
  namespace: team-alpha-dev
spec:
  address: "https://your-vault-cluster.vault.hashicorp.cloud:8200"
  vaultNamespace: "team-alpha"
  skipTLSVerify: false
---
# VaultAuth for dev environment
apiVersion: secrets.hashicorp.com/v1beta1
kind: VaultAuth
metadata:
  name: team-alpha-dev-auth
  namespace: team-alpha-dev
spec:
  vaultConnectionRef: team-alpha-vault
  method: kubernetes
  mount: team-alpha-k8s
  kubernetes:
    role: dev
    serviceAccount: default
---
# VaultStaticSecret for dev configuration
apiVersion: secrets.hashicorp.com/v1beta1
kind: VaultStaticSecret
metadata:
  name: app-config
  namespace: team-alpha-dev
spec:
  type: kv-v2
  mount: secrets
  path: dev/app/config
  destination:
    name: app-config
    create: true
  vaultAuthRef: team-alpha-dev-auth
```

### Team Onboarding Automation Script

```bash
#!/bin/bash
# team-onboarding.sh - Automate team onboarding with Vault namespaces

set -euo pipefail

# Configuration
TEAM_NAME="$1"
VAULT_NAMESPACE="$TEAM_NAME"
K8S_NAMESPACES=("${TEAM_NAME}-dev" "${TEAM_NAME}-staging" "${TEAM_NAME}-prod")
ENVIRONMENTS=("dev" "staging" "prod")

if [[ -z "$TEAM_NAME" ]]; then
    echo "Usage: $0 <team-name>"
    exit 1
fi

echo "Onboarding team: $TEAM_NAME"

# 1. Create Vault namespace
echo "Creating Vault namespace: $VAULT_NAMESPACE"
vault namespace create "$VAULT_NAMESPACE"

# 2. Switch to team namespace
export VAULT_NAMESPACE="$VAULT_NAMESPACE"

# 3. Enable secrets engines
echo "Enabling secrets engines for $TEAM_NAME"
vault secrets enable -path=secrets kv-v2
vault secrets enable database
vault secrets enable -path=azure azure

# 4. Create team policies
echo "Creating team policies"
for env in "${ENVIRONMENTS[@]}"; do
    cat > "/tmp/${TEAM_NAME}-${env}-policy.hcl" << EOF
# Access to $env environment secrets
path "secrets/data/$env/*" {
  capabilities = ["create", "read", "update", "delete", "list"]
}

path "secrets/metadata/$env/*" {
  capabilities = ["read", "list", "delete"]
}

# Generate $env database credentials
path "database/creds/$env-*" {
  capabilities = ["read"]
}

# Generate $env cloud credentials
path "azure/creds/$env-*" {
  capabilities = ["read"]
}
EOF
    vault policy write "${TEAM_NAME}-${env}" "/tmp/${TEAM_NAME}-${env}-policy.hcl"
done

# 5. Setup Kubernetes authentication
echo "Setting up Kubernetes authentication for $TEAM_NAME"
vault auth enable -path="${TEAM_NAME}-k8s" kubernetes

# Configure Kubernetes auth
vault write "auth/${TEAM_NAME}-k8s/config" \
    token_reviewer_jwt="$(kubectl create token vault-auth -n vault-secrets-operator-system --duration=8760h)" \
    kubernetes_host="$(kubectl config view --raw --minify --flatten -o jsonpath='{.clusters[].cluster.server}')" \
    kubernetes_ca_cert="$(kubectl config view --raw --minify --flatten -o jsonpath='{.clusters[].cluster.certificate-authority-data}' | base64 -d)" \
    issuer="https://kubernetes.default.svc.cluster.local"

# Create Kubernetes roles
for i in "${!ENVIRONMENTS[@]}"; do
    env="${ENVIRONMENTS[$i]}"
    k8s_ns="${K8S_NAMESPACES[$i]}"
    
    vault write "auth/${TEAM_NAME}-k8s/role/$env" \
        bound_service_account_names=* \
        bound_service_account_namespaces="$k8s_ns" \
        policies="${TEAM_NAME}-${env}" \
        ttl=30m \
        max_ttl=2h
done

# 6. Create Kubernetes namespaces
echo "Creating Kubernetes namespaces for $TEAM_NAME"
for i in "${!K8S_NAMESPACES[@]}"; do
    k8s_ns="${K8S_NAMESPACES[$i]}"
    env="${ENVIRONMENTS[$i]}"
    
    kubectl create namespace "$k8s_ns" --dry-run=client -o yaml | kubectl apply -f -
    kubectl label namespace "$k8s_ns" vault-namespace="$VAULT_NAMESPACE"
    kubectl label namespace "$k8s_ns" environment="$env"
    kubectl label namespace "$k8s_ns" team="$TEAM_NAME"
done

# 7. Deploy Vault Secrets Operator resources
echo "Deploying Vault Secrets Operator resources for $TEAM_NAME"
for i in "${!K8S_NAMESPACES[@]}"; do
    k8s_ns="${K8S_NAMESPACES[$i]}"
    env="${ENVIRONMENTS[$i]}"
    
    cat << EOF | kubectl apply -f -
apiVersion: secrets.hashicorp.com/v1beta1
kind: VaultConnection
metadata:
  name: ${TEAM_NAME}-vault
  namespace: $k8s_ns
spec:
  address: "$VAULT_ADDR"
  vaultNamespace: "$VAULT_NAMESPACE"
  skipTLSVerify: false
---
apiVersion: secrets.hashicorp.com/v1beta1
kind: VaultAuth
metadata:
  name: ${TEAM_NAME}-${env}-auth
  namespace: $k8s_ns
spec:
  vaultConnectionRef: ${TEAM_NAME}-vault
  method: kubernetes
  mount: ${TEAM_NAME}-k8s
  kubernetes:
    role: $env
    serviceAccount: default
EOF
done

echo "Team $TEAM_NAME onboarded successfully!"
echo "Vault namespace: $VAULT_NAMESPACE"
echo "Kubernetes namespaces: ${K8S_NAMESPACES[*]}"
echo "Environments: ${ENVIRONMENTS[*]}"
```

### Team Access Management

#### Human Access (for team members)
```bash
# Team lead authentication (using userpass auth)
vault auth enable -path=team-alpha-userpass userpass -namespace=team-alpha

# Create team lead user
vault write auth/team-alpha-userpass/users/alice \
    password=secure-password \
    policies=team-alpha-admin \
    -namespace=team-alpha

# Developers authentication
vault write auth/team-alpha-userpass/users/bob \
    password=secure-password \
    policies=team-alpha-dev \
    -namespace=team-alpha

# Team member login
vault auth -method=userpass \
    -path=team-alpha-userpass \
    -namespace=team-alpha \
    username=alice
```

#### OIDC Integration for Teams
```bash
# Enable OIDC auth for team
vault auth enable -path=team-alpha-oidc oidc -namespace=team-alpha

# Configure OIDC for team
vault write auth/team-alpha-oidc/config \
    oidc_discovery_url="https://your-oidc-provider/.well-known/openid_configuration" \
    oidc_client_id="team-alpha-vault-client" \
    oidc_client_secret="client-secret" \
    default_role="team-alpha-member" \
    -namespace=team-alpha

# Create OIDC role for team
vault write auth/team-alpha-oidc/role/team-alpha-member \
    bound_audiences="team-alpha-vault-client" \
    allowed_redirect_uris="https://vault.company.com:8200/ui/vault/auth/team-alpha-oidc/oidc/callback" \
    user_claim="sub" \
    policies="team-alpha-dev" \
    -namespace=team-alpha
```

### Monitoring and Governance

#### Namespace Audit Configuration
```bash
# Enable audit logging per namespace
vault audit enable -path=team-alpha-audit file \
    file_path=/vault/audit/team-alpha.log \
    -namespace=team-alpha

# Configure log rotation and forwarding
vault write sys/config/auditing/request-headers \
    X-Forwarded-For=true \
    X-Real-IP=true \
    -namespace=team-alpha
```

#### Cross-Namespace Policies (Admin namespace)
```bash
# Policy to manage all team namespaces (admin only)
cat > namespace-admin.hcl << 'EOF'
# Manage all namespaces
path "sys/namespaces/*" {
  capabilities = ["create", "read", "update", "delete", "list"]
}

# Read audit logs from all namespaces
path "+/sys/audit" {
  capabilities = ["read", "list"]
}

# Monitor namespace health
path "+/sys/health" {
  capabilities = ["read"]
}
EOF

vault policy write namespace-admin namespace-admin.hcl -namespace=admin
```

### Best Practices for Multi-Team Setup

1. **Namespace Naming Convention**
   - Use consistent naming: `team-<name>`, `<team>-<env>`
   - Avoid special characters and spaces
   - Use lowercase for compatibility

2. **Environment Isolation**
   - Separate policies for dev/staging/prod
   - Different token TTLs per environment
   - Network-level isolation where needed

3. **Secret Organization**
   ```
   secrets/
   ├── dev/
   │   ├── app1/
   │   ├── app2/
   │   └── shared/
   ├── staging/
   │   ├── app1/
   │   ├── app2/
   │   └── shared/
   └── prod/
       ├── app1/
       ├── app2/
       └── shared/
   ```

4. **Access Control**
   - Principle of least privilege
   - Regular access reviews
   - Time-bound tokens
   - MFA for production access

5. **Monitoring and Alerting**
   - Namespace-specific dashboards
   - Token usage monitoring
   - Failed authentication alerts
   - Policy violation notifications

## 🔐 HCP Organization SSO Setup

### Overview
HCP Organization SSO provides centralized authentication for all HashiCorp Cloud Platform services, including Vault Cloud. This enables seamless integration with your existing identity provider and establishes organization-wide access control.

### Supported Identity Providers
- **OIDC**: Azure AD, Google Workspace, Okta, Auth0, Keycloak
- **SAML**: Azure AD, Okta, PingIdentity, OneLogin, ADFS

### Quick Setup Examples

#### Azure AD/Entra ID (Recommended)
```bash
# Complete Azure AD and HCP SSO setup (automated)
./scripts/azure-ad-hcp-sso-setup.sh \
    --hcp-org-id "org-abc123" \
    --azure-tenant-id "your-tenant-id"

# Manual Azure AD OIDC configuration
./scripts/hcp-org-sso-setup.sh oidc \
    --name "Azure AD" \
    --org-id "org-abc123" \
    --oidc-issuer "https://login.microsoftonline.com/tenant-id/v2.0" \
    --oidc-client-id "your-client-id" \
    --oidc-secret "your-client-secret" \
    --group-mapping "HCP-Vault-Admins:Admin:*" \
    --group-mapping "HCP-Vault-Developers:Contributor:vault-dev,vault-staging" \
    --jit-provisioning
```

#### Generic OIDC with Other Providers
```bash
# Configure HCP Organization SSO with Azure AD
./scripts/hcp-org-sso-setup.sh oidc \
    --name "Azure AD" \
    --org-id "org-abc123" \
    --oidc-issuer "https://login.microsoftonline.com/tenant-id/v2.0" \
    --oidc-client-id "your-client-id" \
    --oidc-secret "your-client-secret" \
    --group-mapping "HCP-Vault-Admins:Admin:*" \
    --group-mapping "HCP-Vault-Developers:Contributor:vault-dev,vault-staging" \
    --jit-provisioning
```

#### SAML with Okta
```bash
# Configure HCP Organization SSO with Okta SAML
./scripts/hcp-org-sso-setup.sh saml \
    --name "Okta SAML" \
    --org-id "org-abc123" \
    --saml-sso-url "https://company.okta.com/app/sso/saml" \
    --saml-entity-id "http://www.okta.com/entity-id" \
    --saml-cert "/path/to/okta-cert.pem" \
    --enforce-sso
```

#### Using Configuration File
```bash
# Use YAML configuration file for complex setups
./scripts/hcp-org-sso-setup.sh oidc --config hcp-sso-config.yaml --dry-run
```

#### Terraform Infrastructure as Code
```hcl
# Enable Azure AD HCP SSO in your Terraform configuration
module "azure_ad_hcp_sso" {
  source = "./modules/azure-ad-hcp-sso"

  application_name    = "HashiCorp Cloud Platform"
  hcp_organization_id = "your-hcp-org-id"
  environment        = "prod"
  
  create_groups       = true
  enable_group_claims = true
  jit_provisioning   = true

  tags = {
    Environment = "production"
    ManagedBy   = "terraform"
  }
}

# Then apply the configuration
terraform init
terraform plan
terraform apply

# Use the output to configure HCP SSO
terraform output -raw hcp_sso_setup_command | bash
```

### Benefits
- **Centralized Authentication**: Single point of authentication for all HCP services
- **Enhanced Security**: Leverage existing identity provider security features
- **Automated User Management**: Just-In-Time (JIT) provisioning and group synchronization
- **Role-Based Access**: Map identity provider groups to HCP roles and permissions
- **Audit Trail**: Comprehensive audit logging for authentication events

### Integration with Vault Team Onboarding
Once HCP Organization SSO is configured, team onboarding becomes more streamlined:

```bash
# Team onboarding with SSO-integrated users
./scripts/team-onboarding.sh team-alpha \
    --oidc \
    --oidc-url "https://login.microsoftonline.com/tenant-id/v2.0" \
    --oidc-client-id "vault-team-client" \
    --oidc-secret "team-client-secret"
```

For detailed configuration instructions, see the [HCP Organization SSO Setup Guide](docs/setup-guides/03-hcp-organization-sso-setup.md).

## 🔧 Implementation Examples

### Keystore Management
```bash
# Store application secrets
vault kv put secret/prod/myapp/database \
    username=dbuser \
    password=supersecret \
    host=db.example.com

# Retrieve secrets
vault kv get secret/prod/myapp/database
```

### Azure Dynamic Credentials
```bash
# Configure Azure secrets engine
vault secrets enable azure
vault write azure/config \
    subscription_id="..." \
    tenant_id="..." \
    client_id="..." \
    client_secret="..."

# Generate Azure credentials
vault read azure/creds/readonly
```

### Database Dynamic Credentials
```bash
# Configure database secrets engine
vault secrets enable database
vault write database/config/postgresql \
    plugin_name=postgresql-database-plugin \
    connection_url="postgresql://{{username}}:{{password}}@db.example.com:5432/mydb"

# Generate database credentials
vault read database/creds/readonly
```

### Kubernetes Integration

#### Vault Secrets Operator
```yaml
# VaultAuth custom resource
apiVersion: secrets.hashicorp.com/v1beta1
kind: VaultAuth
metadata:
  name: default
  namespace: webapp
spec:
  method: kubernetes
  mount: kubernetes
  kubernetes:
    role: webapp
    serviceAccount: webapp
---
# VaultStaticSecret for KV secrets
apiVersion: secrets.hashicorp.com/v1beta1
kind: VaultStaticSecret
metadata:
  name: webapp-config
  namespace: webapp
spec:
  type: kv-v2
  mount: secret
  path: webapp/config
  destination:
    name: webapp-config
    create: true
  vaultAuthRef: default
```

#### Vault Agent Injector
```yaml
# Pod with Vault Agent annotations
apiVersion: v1
kind: Pod
metadata:
  name: webapp
  annotations:
    vault.hashicorp.com/agent-inject: "true"
    vault.hashicorp.com/role: "webapp"
    vault.hashicorp.com/agent-inject-secret-database: "secret/prod/webapp/database"
spec:
  serviceAccountName: webapp
  containers:
  - name: app
    image: webapp:latest
```

#### Kubernetes Authentication Setup
```bash
# Enable Kubernetes auth method
vault auth enable kubernetes

# Configure Kubernetes auth
vault write auth/kubernetes/config \
    token_reviewer_jwt="$(cat /var/run/secrets/kubernetes.io/serviceaccount/token)" \
    kubernetes_host="https://kubernetes.default.svc:443" \
    kubernetes_ca_cert=@/var/run/secrets/kubernetes.io/serviceaccount/ca.crt

# Create Kubernetes role
vault write auth/kubernetes/role/webapp \
    bound_service_account_names=webapp \
    bound_service_account_namespaces=production \
    policies=webapp-policy \
    ttl=1h
```

## 📊 Success Metrics

- [ ] Vault Cloud instance operational with 99.9% uptime
- [ ] Zero static credentials in production applications
- [ ] All secrets accessed through Vault with audit trails
- [ ] Azure services using dynamic credentials exclusively
- [ ] Database access using short-lived credentials only
- [ ] Kubernetes workloads consuming secrets through Vault Secrets Operator
- [ ] Multiple Kubernetes namespaces with proper secret isolation
- [ ] Complete documentation and team training

## 🔍 Monitoring and Alerting

Key metrics to monitor:
- Vault cluster health and performance
- Authentication success/failure rates
- Secret access patterns and anomalies
- Dynamic credential generation rates
- Lease renewal and revocation patterns
- Kubernetes authentication events and token renewals
- Vault Secrets Operator custom resource status
- Secret synchronization success/failure rates

## 🛠️ Troubleshooting

Common issues and solutions are documented in each guide:
- **Connection issues**: Check network configuration and firewall rules
- **Authentication failures**: Verify auth method configuration and user policies
- **Permission denied**: Review Vault policies and Azure/database permissions
- **Performance issues**: Monitor metrics and optimize configurations
- **Kubernetes integration issues**: Verify service account configuration and RBAC
- **Vault Secrets Operator problems**: Check custom resource status and operator logs
- **Secret synchronization failures**: Review namespace policies and network connectivity

## 📈 Next Steps

After completing the current epic:
1. **Advanced Features**: Implement encryption-as-a-service, PKI management
2. **Multi-Cloud**: Extend to AWS and Google Cloud dynamic credentials
3. **Advanced Kubernetes Patterns**: Implement GitOps workflows, multi-cluster federation
4. **Automation**: Implement GitOps workflows for Vault configuration
5. **Compliance**: Add compliance monitoring and reporting
6. **Advanced Monitoring**: Implement advanced analytics and anomaly detection
7. **Service Mesh Integration**: Integrate with Istio/Consul Connect for mTLS

## 🤝 Contributing

1. Review the epic requirements in [EPIC-Vault-Cloud-Onboarding.md](EPIC-Vault-Cloud-Onboarding.md)
2. Follow the implementation guides for your specific use case
3. Test configurations in development environments first
4. Document any custom configurations or lessons learned
5. Share feedback and improvements with the team

## 📞 Support

- **HashiCorp Vault Documentation**: [vaultproject.io/docs](https://www.vaultproject.io/docs)
- **HCP Vault Cloud**: [cloud.hashicorp.com/docs/vault](https://cloud.hashicorp.com/docs/vault)
- **Community Forum**: [discuss.hashicorp.com](https://discuss.hashicorp.com/c/vault)
- **Internal Support**: Contact the Platform Engineering team

## 📋 Checklist

### Pre-Production Checklist
- [ ] Vault Cloud instance configured and tested
- [ ] Authentication methods implemented and tested
- [ ] Network security controls in place
- [ ] Keystore management operational
- [ ] Azure dynamic rotation tested
- [ ] Database dynamic rotation tested
- [ ] Kubernetes authentication configured and tested
- [ ] Vault Secrets Operator deployed and operational
- [ ] Kubernetes secret consumption patterns validated
- [ ] Multi-namespace isolation verified
- [ ] Monitoring and alerting configured
- [ ] Backup and disaster recovery procedures in place
- [ ] Documentation complete and reviewed
- [ ] Team training completed
- [ ] Security review passed
- [ ] Performance testing completed

### Production Readiness
- [ ] Production deployment successful
- [ ] All applications migrated to Vault
- [ ] Static credentials removed
- [ ] Kubernetes workloads using Vault secrets
- [ ] Secret rotation policies active
- [ ] Monitoring operational
- [ ] Incident response procedures tested
- [ ] Post-implementation review completed

---

**Last Updated**: August 2024  
**Version**: 1.0  
**Status**: Implementation Phase