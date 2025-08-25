# Multi-Team Onboarding with HCP Vault Namespaces

## Overview

This guide provides a comprehensive walkthrough for onboarding multiple teams onto HashiCorp Vault Cloud using namespaces. Each team gets their own isolated Vault namespace that maps to dedicated Kubernetes namespaces, providing secure multi-tenancy with complete separation of secrets and policies.

## Table of Contents

- [Architecture Overview](#architecture-overview)
- [Prerequisites](#prerequisites)
- [Team Onboarding Process](#team-onboarding-process)
- [Automated Onboarding](#automated-onboarding)
- [Manual Onboarding Steps](#manual-onboarding-steps)
- [Kubernetes Integration](#kubernetes-integration)
- [Access Management](#access-management)
- [Best Practices](#best-practices)
- [Monitoring and Governance](#monitoring-and-governance)
- [Troubleshooting](#troubleshooting)
- [Examples](#examples)

## Architecture Overview

### Vault Namespace Hierarchy

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

### Multi-Tenancy Model

Each team namespace provides:

- **Complete Isolation**: Teams cannot access other team's secrets
- **Environment Separation**: Dev, staging, and production environments within each team
- **Independent Auth Methods**: Team-specific authentication configurations
- **Granular Policies**: Fine-grained access control per environment
- **Audit Trails**: Separate audit logs per team namespace

### Kubernetes Mapping

```
Vault Namespace     →    Kubernetes Namespaces
team-alpha          →    team-alpha-dev, team-alpha-staging, team-alpha-prod
team-beta           →    team-beta-dev, team-beta-staging, team-beta-prod
platform            →    platform-monitoring, platform-infrastructure
security             →    security-scanning, security-compliance
```

## Prerequisites

### Vault Requirements

1. **HCP Vault Cluster**: Active HCP Vault cluster with admin access
2. **Namespace Support**: HCP Vault Plus or Enterprise tier (namespaces not available in Standard)
3. **Admin Permissions**: Root or admin token with namespace management capabilities

### Kubernetes Requirements

1. **Kubernetes Cluster**: Version 1.19 or later
2. **Cluster Admin Access**: kubectl with cluster-admin permissions
3. **Vault Secrets Operator**: Deployed and operational
4. **Network Connectivity**: Kubernetes cluster can reach HCP Vault

### Tools and Utilities

1. **Vault CLI**: Latest version of vault binary
2. **kubectl**: Configured for your Kubernetes cluster
3. **Helm** (optional): For Vault Secrets Operator installation

## Team Onboarding Process

### 1. Planning Phase

Before onboarding a team, gather the following information:

- **Team Name**: Alphanumeric with hyphens (e.g., `team-alpha`, `data-engineering`)
- **Environments**: List of environments needed (dev, staging, prod, test, etc.)
- **Applications**: Applications the team will deploy
- **Secret Types**: Types of secrets needed (KV, database, cloud provider)
- **Access Patterns**: Who needs access and at what level
- **Compliance Requirements**: Any special security or compliance needs

### 2. Namespace Design

Design the namespace structure based on:

- **Team Organization**: One namespace per team
- **Environment Isolation**: Separate policies per environment
- **Shared Resources**: Consider shared/platform namespaces for common resources
- **Scaling**: Plan for future team growth and restructuring

## Automated Onboarding

### Using the Team Onboarding Script

The repository includes a comprehensive script for automated team onboarding:

```bash
# Basic team onboarding
./scripts/team-onboarding.sh team-alpha

# Team with custom environments and additional engines
./scripts/team-onboarding.sh -e "dev,test,staging,prod" -c -d team-beta

# Team with OIDC authentication
./scripts/team-onboarding.sh \
  --oidc \
  --oidc-url "https://auth.company.com/.well-known/openid_configuration" \
  --oidc-client-id "vault-client" \
  --oidc-secret "client-secret" \
  team-gamma

# Dry run to see what would be created
./scripts/team-onboarding.sh --dry-run team-delta
```

### Script Features

- **Complete Automation**: End-to-end team setup
- **Flexible Configuration**: Customizable environments and engines
- **OIDC Integration**: Optional OIDC authentication setup
- **Kubernetes Integration**: Automatic namespace and resource creation
- **Documentation Generation**: Automatic team documentation
- **Dry Run Mode**: Preview changes before execution
- **Error Handling**: Robust error checking and recovery

## Manual Onboarding Steps

### Step 1: Create Vault Namespace

```bash
# Set admin context
export VAULT_NAMESPACE="admin"

# Create team namespace
vault namespace create team-alpha

# Verify creation
vault namespace list
```

### Step 2: Configure Team Namespace

```bash
# Switch to team namespace
export VAULT_NAMESPACE="team-alpha"

# Enable KV v2 secrets engine
vault secrets enable -path=secrets kv-v2

# Enable database secrets engine (if needed)
vault secrets enable database

# Enable cloud provider secrets engines (if needed)
vault secrets enable -path=azure azure
vault secrets enable -path=aws aws
vault secrets enable -path=gcp gcp
```

### Step 3: Create Team Policies

Create environment-specific policies:

```bash
# Development environment policy
cat > team-alpha-dev-policy.hcl << 'EOF'
# Full access to dev environment secrets
path "secrets/data/dev/*" {
  capabilities = ["create", "read", "update", "delete", "list"]
}

path "secrets/metadata/dev/*" {
  capabilities = ["read", "list", "delete"]
}

# Read shared configuration
path "secrets/data/shared/*" {
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

vault policy write team-alpha-dev team-alpha-dev-policy.hcl
```

```bash
# Production environment policy (more restrictive)
cat > team-alpha-prod-policy.hcl << 'EOF'
# Read-only access to production secrets
path "secrets/data/prod/*" {
  capabilities = ["read"]
}

# Generate production database credentials
path "database/creds/prod-readonly" {
  capabilities = ["read"]
}

# Generate production cloud credentials (read-only roles)
path "azure/creds/prod-readonly" {
  capabilities = ["read"]
}
EOF

vault policy write team-alpha-prod team-alpha-prod-policy.hcl
```

### Step 4: Setup Kubernetes Authentication

```bash
# Enable Kubernetes auth method for the team
vault auth enable -path=team-alpha-k8s kubernetes

# Configure Kubernetes auth
vault write auth/team-alpha-k8s/config \
    token_reviewer_jwt="$(kubectl create token vault-auth -n vault-secrets-operator-system --duration=8760h)" \
    kubernetes_host="$(kubectl config view --raw --minify --flatten -o jsonpath='{.clusters[].cluster.server}')" \
    kubernetes_ca_cert="$(kubectl config view --raw --minify --flatten -o jsonpath='{.clusters[].cluster.certificate-authority-data}' | base64 -d)" \
    issuer="https://kubernetes.default.svc.cluster.local"

# Create Kubernetes role for dev environment
vault write auth/team-alpha-k8s/role/dev \
    bound_service_account_names="*" \
    bound_service_account_namespaces="team-alpha-dev" \
    policies="team-alpha-dev" \
    ttl=1h \
    max_ttl=4h

# Create Kubernetes role for production (shorter TTL)
vault write auth/team-alpha-k8s/role/prod \
    bound_service_account_names="*" \
    bound_service_account_namespaces="team-alpha-prod" \
    policies="team-alpha-prod" \
    ttl=15m \
    max_ttl=1h
```

### Step 5: Create Kubernetes Namespaces

```bash
# Create development namespace
kubectl create namespace team-alpha-dev
kubectl label namespace team-alpha-dev vault-namespace=team-alpha
kubectl label namespace team-alpha-dev environment=dev
kubectl label namespace team-alpha-dev team=team-alpha

# Create production namespace
kubectl create namespace team-alpha-prod
kubectl label namespace team-alpha-prod vault-namespace=team-alpha
kubectl label namespace team-alpha-prod environment=prod
kubectl label namespace team-alpha-prod team=team-alpha
```

### Step 6: Deploy Vault Secrets Operator Resources

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
```

## Kubernetes Integration

### Vault Secrets Operator Configuration

Each team namespace requires specific Vault Secrets Operator resources:

1. **VaultConnection**: Defines connection to team's Vault namespace
2. **VaultAuth**: Configures authentication for the Kubernetes namespace
3. **VaultStaticSecret**: Retrieves static secrets from KV store
4. **VaultDynamicSecret**: Generates dynamic credentials

### Example Secret Consumption

```yaml
# Static secret from team's KV store
apiVersion: secrets.hashicorp.com/v1beta1
kind: VaultStaticSecret
metadata:
  name: app-config
  namespace: team-alpha-dev
spec:
  type: kv-v2
  mount: secrets
  path: dev/myapp/config
  destination:
    name: app-config
    create: true
  vaultAuthRef: team-alpha-dev-auth

---
# Dynamic database credentials
apiVersion: secrets.hashicorp.com/v1beta1
kind: VaultDynamicSecret
metadata:
  name: db-creds
  namespace: team-alpha-dev
spec:
  mount: database
  path: creds/dev-readonly
  destination:
    name: db-creds
    create: true
  vaultAuthRef: team-alpha-dev-auth
  renewalPercent: 67
```

### Vault Agent Injector Alternative

Teams can also use Vault Agent Injector with namespace-specific annotations:

```yaml
metadata:
  annotations:
    vault.hashicorp.com/agent-inject: "true"
    vault.hashicorp.com/namespace: "team-alpha"
    vault.hashicorp.com/role: "dev"
    vault.hashicorp.com/auth-path: "auth/team-alpha-k8s"
    vault.hashicorp.com/agent-inject-secret-config: "secrets/dev/myapp/config"
```

## Access Management

### Human Access

#### OIDC Authentication (Recommended)

```bash
# Enable OIDC for team
vault auth enable -path=team-alpha-oidc oidc -namespace=team-alpha

# Configure OIDC
vault write auth/team-alpha-oidc/config \
    oidc_discovery_url="https://your-oidc-provider/.well-known/openid_configuration" \
    oidc_client_id="team-alpha-vault-client" \
    oidc_client_secret="client-secret" \
    default_role="team-alpha-member"

# Create OIDC roles
vault write auth/team-alpha-oidc/role/team-alpha-admin \
    bound_audiences="team-alpha-vault-client" \
    user_claim="sub" \
    policies="team-alpha-admin"

vault write auth/team-alpha-oidc/role/team-alpha-developer \
    bound_audiences="team-alpha-vault-client" \
    user_claim="sub" \
    policies="team-alpha-dev"
```

#### Userpass Authentication (Alternative)

```bash
# Enable userpass for team
vault auth enable -path=team-alpha-userpass userpass -namespace=team-alpha

# Create team lead
vault write auth/team-alpha-userpass/users/alice \
    password="secure-password" \
    policies="team-alpha-admin"

# Create developer
vault write auth/team-alpha-userpass/users/bob \
    password="secure-password" \
    policies="team-alpha-dev"
```

### Service Account Access

Service accounts in Kubernetes automatically get access through the Kubernetes auth method configured for their namespace.

## Best Practices

### Namespace Naming

- Use consistent naming conventions: `team-<name>`
- Avoid special characters and spaces
- Use lowercase for compatibility
- Consider future reorganization when naming

### Environment Isolation

- Separate policies for each environment
- Different token TTLs per environment (prod: 15m, dev: 1h)
- Network-level isolation where appropriate
- Regular access reviews per environment

### Secret Organization

Organize secrets hierarchically within each team namespace:

```
secrets/
├── dev/
│   ├── app1/
│   │   ├── database
│   │   ├── api-keys
│   │   └── config
│   ├── app2/
│   └── shared/
│       └── external-apis
├── staging/
│   ├── app1/
│   ├── app2/
│   └── shared/
└── prod/
    ├── app1/
    ├── app2/
    └── shared/
```

### Policy Design

- **Principle of Least Privilege**: Grant minimum necessary access
- **Environment-Specific**: Separate policies for each environment
- **Time-Bound Access**: Use appropriate TTLs for tokens
- **Regular Reviews**: Audit and update policies regularly

### Security Considerations

- **MFA for Production**: Require multi-factor authentication for production access
- **Network Policies**: Use Kubernetes NetworkPolicies for namespace isolation
- **Audit Logging**: Enable comprehensive audit logging per namespace
- **Secret Rotation**: Implement regular secret rotation policies

## Monitoring and Governance

### Namespace-Specific Monitoring

Configure monitoring for each team namespace:

```bash
# Enable audit logging per namespace
vault audit enable -path=team-alpha-audit file \
    file_path=/vault/audit/team-alpha.log \
    -namespace=team-alpha
```

### Governance Policies

Implement governance at the platform level:

```bash
# Sentinel policy for secret access patterns
# (HCP Vault Enterprise feature)
vault write sys/policies/egp/secret-access-pattern \
    policy=@secret-access-pattern.sentinel \
    enforcement_level=advisory
```

### Cross-Namespace Monitoring

From the admin namespace, monitor all team namespaces:

```bash
# Policy for platform administrators
cat > platform-admin-policy.hcl << 'EOF'
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

# View all namespace policies
path "+/sys/policies/*" {
  capabilities = ["read", "list"]
}
EOF
```

### Metrics and Alerting

Monitor key metrics per namespace:

- Token usage and renewal patterns
- Failed authentication attempts
- Secret access frequency
- Policy violations
- Lease expiration rates

## Troubleshooting

### Common Issues

#### Namespace Access Issues

```bash
# Check if namespace exists
vault namespace list

# Verify current namespace context
env | grep VAULT_NAMESPACE

# Test authentication in namespace
vault auth -method=kubernetes role=dev -namespace=team-alpha
```

#### Kubernetes Authentication Failures

```bash
# Check Kubernetes auth configuration
vault read auth/team-alpha-k8s/config -namespace=team-alpha

# Verify service account token
kubectl create token vault-auth -n vault-secrets-operator-system --duration=1h

# Check role configuration
vault read auth/team-alpha-k8s/role/dev -namespace=team-alpha
```

#### Vault Secrets Operator Issues

```bash
# Check operator status
kubectl get pods -n vault-secrets-operator-system

# Check VaultConnection status
kubectl get vaultconnection -n team-alpha-dev

# Check VaultAuth status
kubectl get vaultauth -n team-alpha-dev

# View operator logs
kubectl logs -f deployment/vault-secrets-operator-controller-manager -n vault-secrets-operator-system
```

### Debugging Commands

```bash
# Enable debug logging
export VAULT_LOG_LEVEL=debug

# Test namespace connectivity
vault status -namespace=team-alpha

# List all auth methods in namespace
vault auth list -namespace=team-alpha

# Check policy assignments
vault token lookup -namespace=team-alpha
```

## Examples

### Complete Team Setup Example

See the [automated onboarding script](../scripts/team-onboarding.sh) for a complete example of setting up a team with multiple environments.

### Application Deployment Example

See the [multi-team deployment example](../examples/kubernetes/multi-team-deployment.yaml) for a complete Kubernetes application using team-specific Vault namespace.

### Cross-Team Secret Sharing

For scenarios where teams need to share certain secrets:

```bash
# Create shared namespace
vault namespace create shared

# Switch to shared namespace
export VAULT_NAMESPACE="shared"

# Enable KV engine
vault secrets enable -path=secrets kv-v2

# Create shared policy
cat > shared-readonly-policy.hcl << 'EOF'
path "secrets/data/common/*" {
  capabilities = ["read"]
}
EOF

vault policy write shared-readonly shared-readonly-policy.hcl

# Grant access from team namespaces
vault write auth/team-alpha-k8s/role/shared \
    bound_service_account_namespaces="team-alpha-dev,team-alpha-prod" \
    policies="shared-readonly" \
    -namespace=shared
```

## Migration from Single Namespace

If migrating from a single-namespace setup to multi-team namespaces:

1. **Plan the Migration**: Map existing secrets to new team namespaces
2. **Create Team Namespaces**: Set up new namespaces with appropriate policies
3. **Migrate Secrets**: Copy secrets to new locations
4. **Update Applications**: Modify applications to use new secret paths
5. **Test Thoroughly**: Verify all applications work with new configuration
6. **Cleanup**: Remove old secrets and policies after successful migration

## Conclusion

Multi-team onboarding with HCP Vault namespaces provides secure, scalable secret management for organizations with multiple development teams. The combination of Vault namespaces and Kubernetes namespaces creates strong isolation boundaries while maintaining operational efficiency.

Key benefits:

- **Security**: Complete isolation between teams
- **Scalability**: Easy to add new teams and environments
- **Governance**: Centralized control with distributed management
- **Automation**: Scripted onboarding reduces manual errors
- **Compliance**: Audit trails and access controls per team

For additional support or questions, refer to the [main README](../README.md) or contact the Platform Engineering team.