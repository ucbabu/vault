# HashiCorp Vault Complete User Guide

## Document Information
- **Document Type**: Complete User Guide  
- **Target Audience**: DevOps Engineers, Security Engineers, Platform Teams
- **Version**: 1.0
- **Last Updated**: August 2025

---

## Table of Contents

1. [Executive Summary](#executive-summary)
2. [Vault Introduction](#vault-introduction)
3. [Implementation Roadmap](#implementation-roadmap)
4. [User Guides](#user-guides)
   - [Keystore Management](#keystore-management)
   - [Azure Dynamic Key Rotation](#azure-dynamic-key-rotation)
   - [Database Dynamic Key Rotation](#database-dynamic-key-rotation)
   - [Kubernetes Integration](#kubernetes-integration)
   - [Advanced Kubernetes Patterns](#advanced-kubernetes-patterns)
   - [Multi-Team Onboarding](#multi-team-onboarding)
5. [Best Practices Summary](#best-practices-summary)
6. [Support and Resources](#support-and-resources)

---

## Executive Summary

This comprehensive guide provides complete implementation instructions for HashiCorp Vault Cloud (HCP Vault) integration across your infrastructure. It covers:

- **Centralized Secret Management**: Secure storage and access control for API keys, passwords, and certificates
- **Dynamic Credential Generation**: Automated database and cloud provider credential lifecycle
- **Kubernetes Integration**: Native secret injection for containerized applications
- **Multi-Team Architecture**: Namespace isolation for enterprise environments
- **Security Best Practices**: Industry-standard implementation patterns

**Business Benefits:**
- Eliminate static secrets and hard-coded passwords
- Reduce security incidents through automated rotation
- Achieve compliance with audit trails and access controls
- Scale secret management across multiple teams and environments

---

## Vault Introduction

### What is HashiCorp Vault?

HashiCorp Vault is a secrets management platform that provides secure storage, dynamic secret generation, and comprehensive access control for modern infrastructure.

### Core Capabilities

**Secrets Management**
- Centralized storage for API keys, passwords, certificates
- Automatic encryption at rest and in transit
- Version control and rollback capabilities
- Fine-grained access policies

**Dynamic Secrets**
- On-demand credential generation for databases
- Cloud provider access keys with automatic cleanup
- Short-lived certificates and tokens
- Automatic revocation when no longer needed

**Authentication & Authorization**
- Multiple authentication methods (LDAP, OIDC, Kubernetes, etc.)
- Policy-based access control
- Identity-based secrets and encryption
- Comprehensive audit logging

**Enterprise Features (HCP Vault)**
- Multi-tenancy with namespaces
- Disaster recovery and replication
- Performance standby nodes
- Advanced monitoring and analytics

### Architecture Overview

```
┌─────────────────────────────────────────────────────────────┐
│                    HCP Vault Cloud                          │
├─────────────────────┬───────────────────┬───────────────────┤
│   Team A Namespace  │  Team B Namespace │  Team C Namespace │
│                     │                   │                   │
│ ┌─── Secrets ────┐  │ ┌─── Secrets ──┐  │ ┌─── Secrets ──┐  │
│ │ • API Keys     │  │ │ • Database   │  │ │ • Certificates│  │
│ │ • Certificates │  │ │ • Cloud Creds│  │ │ • API Keys    │  │
│ │ • Config Data  │  │ │ • SSH Keys   │  │ │ • Tokens      │  │
│ └────────────────┘  │ └──────────────┘  │ └───────────────┘  │
└─────────────────────┴───────────────────┴───────────────────┘
         │                       │                       │
         ▼                       ▼                       ▼
┌─────────────────────────────────────────────────────────────┐
│              Applications & Infrastructure                   │
├─────────────────┬───────────────────┬───────────────────────┤
│   Kubernetes    │      Databases    │    Cloud Services     │
│   Clusters      │                   │                       │
└─────────────────┴───────────────────┴───────────────────────┘
```

### Implementation Benefits

**Security Improvements**
- Eliminate static credentials in code and configuration
- Implement just-in-time access with dynamic secrets
- Comprehensive audit trails for compliance
- Centralized secret lifecycle management

**Operational Efficiency**  
- Automate credential rotation and management
- Reduce manual secret distribution and updates
- Standardize access patterns across teams
- Improve incident response with centralized control

**Developer Experience**
- Native integration with Kubernetes and CI/CD
- Simple APIs for secret consumption
- Transparent secret injection without code changes
- Self-service secret management for teams

---

## Implementation Roadmap

### Phase 1: Foundation (Weeks 1-2)
- **Week 1**: HCP Vault cluster setup and basic configuration
- **Week 2**: Enable authentication methods and create initial policies
- **Deliverables**: 
  - Functional Vault cluster
  - Basic authentication and policies
  - Initial secret storage setup

### Phase 2: Secret Management (Weeks 3-6)
- **Week 3-4**: Implement centralized keystore management
- **Week 5-6**: Configure dynamic database credentials
- **Deliverables**:
  - Centralized secret storage
  - Database credential automation
  - Initial application integration

### Phase 3: Platform Integration (Weeks 7-10)
- **Week 7-8**: Kubernetes integration with Vault Secrets Operator
- **Week 9-10**: Azure dynamic credentials and cloud integration
- **Deliverables**:
  - Kubernetes secret automation
  - Cloud provider credential management
  - Container workload integration

### Phase 4: Multi-Team & Enterprise (Weeks 11-14)
- **Week 11-12**: Multi-team namespace architecture
- **Week 13-14**: Advanced patterns and monitoring
- **Deliverables**:
  - Team isolation with namespaces
  - Advanced automation patterns
  - Comprehensive monitoring and alerting

---

## User Guides

### Keystore Management

Centralized management of static secrets using Vault's KV secrets engine.

**Key Features:**
- Version-controlled secret storage
- Fine-grained access control  
- Hierarchical organization
- Audit logging

**Quick Start:**
```bash
# Enable KV secrets engine
vault secrets enable -path=secret kv-v2

# Store application secrets
vault kv put secret/myapp/config \
    api_key=abc123 \
    database_url=postgres://localhost:5432/myapp

# Retrieve secrets
vault kv get secret/myapp/config
```

**Organization Strategy:**
```
secret/
├── prod/
│   ├── webapp/{database, api-keys, certificates}
│   └── api/{database, external-services}
├── staging/
│   ├── webapp/
│   └── api/
└── shared/
    ├── monitoring/
    └── infrastructure/
```

**Best Practices:**
- Use consistent naming conventions
- Implement environment separation
- Regular secret rotation schedules
- Comprehensive access policies

---

### Azure Dynamic Key Rotation

Automated Azure credential generation with lifecycle management.

**Benefits:**
- Short-lived Azure credentials
- Automatic cleanup and rotation
- Role-based access control
- No more static service principals

**Setup Process:**
```bash
# Enable Azure secrets engine
vault secrets enable azure

# Configure Azure connection
vault write azure/config \
    subscription_id=$AZURE_SUBSCRIPTION_ID \
    tenant_id=$AZURE_TENANT_ID \
    client_id=$AZURE_CLIENT_ID \
    client_secret=$AZURE_CLIENT_SECRET

# Create role for read-only access
vault write azure/roles/readonly \
    azure_roles='[
        {
            "role_name": "Reader",
            "scope": "/subscriptions/$AZURE_SUBSCRIPTION_ID"
        }
    ]' \
    ttl=1h \
    max_ttl=24h
```

**Credential Generation:**
```bash
# Generate Azure credentials
vault read azure/creds/readonly

# Example output:
# client_id       abc-123-def-456
# client_secret   xyz-789-secret
# lease_duration  3600
```

**Integration Example:**
```python
import hvac
from azure.identity import ClientSecretCredential

# Get Azure credentials from Vault
vault_client = hvac.Client(url='https://vault.example.com')
azure_creds = vault_client.read('azure/creds/readonly')

# Use credentials with Azure SDK
credential = ClientSecretCredential(
    tenant_id=TENANT_ID,
    client_id=azure_creds['data']['client_id'],
    client_secret=azure_creds['data']['client_secret']
)
```

---

### Database Dynamic Key Rotation

Eliminate static database passwords with on-demand credential generation.

**Supported Databases:**
- PostgreSQL, MySQL, MongoDB
- SQL Server, Oracle, Redis
- Cassandra, Elasticsearch

**PostgreSQL Setup:**
```bash
# Enable database engine
vault secrets enable database

# Configure PostgreSQL connection
vault write database/config/postgres \
    plugin_name=postgresql-database-plugin \
    connection_url="postgresql://{{username}}:{{password}}@postgres:5432/mydb" \
    allowed_roles="readonly,readwrite" \
    username="vault_admin" \
    password="admin_password"

# Create application role
vault write database/roles/app \
    db_name=postgres \
    creation_statements="CREATE ROLE \"{{name}}\" WITH LOGIN PASSWORD '{{password}}' VALID UNTIL '{{expiration}}'; GRANT SELECT, INSERT, UPDATE, DELETE ON ALL TABLES IN SCHEMA public TO \"{{name}}\";" \
    default_ttl="2h" \
    max_ttl="8h"
```

**Application Integration:**
```python
# Get database credentials
db_creds = vault_client.read('database/creds/app')
username = db_creds['data']['username']
password = db_creds['data']['password']
lease_id = db_creds['lease_id']

# Connect to database
import psycopg2
conn = psycopg2.connect(
    host='postgres.example.com',
    database='myapp',
    user=username,
    password=password
)

# Always revoke lease when done
vault_client.sys.revoke_lease(lease_id)
```

---

### Kubernetes Integration

Native Kubernetes secret management using Vault Secrets Operator.

**Architecture Components:**
- Vault Secrets Operator
- Custom Resources (VaultAuth, VaultStaticSecret, VaultDynamicSecret)
- Service Account authentication
- Automatic secret synchronization

**Installation:**
```bash
# Install Vault Secrets Operator
helm repo add hashicorp https://helm.releases.hashicorp.com
helm install vault-secrets-operator hashicorp/vault-secrets-operator \
    --namespace vault-secrets-operator-system \
    --create-namespace

# Configure Kubernetes authentication in Vault
vault auth enable kubernetes
vault write auth/kubernetes/config \
    token_reviewer_jwt="$(kubectl create token vault-auth)" \
    kubernetes_host="$(kubectl config view --minify -o jsonpath='{.clusters[0].cluster.server}')" \
    kubernetes_ca_cert="$(kubectl config view --raw --minify --flatten -o jsonpath='{.clusters[].cluster.certificate-authority-data}' | base64 -d)"
```

**Example Implementation:**
```yaml
# VaultConnection
apiVersion: secrets.hashicorp.com/v1beta1
kind: VaultConnection
metadata:
  name: default
spec:
  address: "https://vault.example.com:8200"

---
# VaultAuth  
apiVersion: secrets.hashicorp.com/v1beta1
kind: VaultAuth
metadata:
  name: webapp-auth
spec:
  vaultConnectionRef: default
  method: kubernetes
  kubernetes:
    role: webapp
    serviceAccount: webapp

---
# VaultStaticSecret
apiVersion: secrets.hashicorp.com/v1beta1
kind: VaultStaticSecret
metadata:
  name: webapp-config
spec:
  type: kv-v2
  mount: secret
  path: webapp/config
  destination:
    name: webapp-config
    create: true
  vaultAuthRef: webapp-auth
  refreshAfter: 30s
```

---

### Advanced Kubernetes Patterns

Enterprise-grade patterns for production Kubernetes environments.

**GitOps Integration:**
- Infrastructure as Code with Terraform
- Secret management in CI/CD pipelines
- Automated policy and role management
- Configuration drift detection

**Cross-Namespace Secrets:**
```yaml
# Shared secret accessible across namespaces
apiVersion: secrets.hashicorp.com/v1beta1
kind: VaultStaticSecret
metadata:
  name: shared-monitoring
  namespace: monitoring
spec:
  type: kv-v2
  mount: secret
  path: shared/monitoring
  destination:
    name: monitoring-config
    create: true
    labels:
      shared: "true"
  vaultAuthRef: monitoring-auth
```

**Multi-Environment Management:**
- Environment-specific Vault policies
- Automated environment provisioning
- Configuration promotion workflows
- Environment isolation strategies

---

### Multi-Team Onboarding

Enterprise namespace architecture for team isolation and self-service.

**Architecture Benefits:**
- Complete team isolation
- Self-service secret management
- Standardized onboarding process
- Centralized governance

**Namespace Strategy:**
```
HCP Vault Cluster
├── team-alpha/          # Team Alpha namespace
│   ├── secrets/         # Team secrets engine
│   ├── database/        # Team database engine
│   └── team-alpha-k8s/  # Team Kubernetes auth
├── team-beta/           # Team Beta namespace
│   ├── secrets/
│   ├── azure/
│   └── team-beta-k8s/
└── shared/              # Shared resources
    ├── monitoring/
    └── infrastructure/
```

**Automated Onboarding:**
```bash
# Use the team onboarding script
./scripts/team-onboarding.sh \
    --team-name "team-gamma" \
    --environments "dev,staging,prod" \
    --enable-database \
    --enable-azure \
    --kubernetes-namespace "team-gamma"
```

**Team Policies:**
```hcl
# Team-specific policy
path "secrets/data/{{identity.entity.metadata.team}}/*" {
  capabilities = ["create", "read", "update", "delete", "list"]
}

path "database/creds/{{identity.entity.metadata.team}}-*" {
  capabilities = ["read"]
}
```

---

## Best Practices Summary

### Security
- **Principle of Least Privilege**: Grant minimal required access
- **Regular Rotation**: Implement automated credential rotation
- **Audit Logging**: Enable comprehensive audit trails
- **Network Security**: Use TLS and network policies

### Operations
- **Infrastructure as Code**: Manage Vault configuration with Terraform
- **Monitoring**: Implement comprehensive metrics and alerting
- **Backup**: Regular configuration and data backups
- **Documentation**: Maintain current procedures and runbooks

### Development
- **Secret Injection**: Use native Kubernetes integration
- **Error Handling**: Implement proper error handling and retries
- **Testing**: Include secret management in testing workflows
- **CI/CD Integration**: Automate secret provisioning in pipelines

---

## Support and Resources

### Documentation Links
- **HashiCorp Vault Documentation**: https://developer.hashicorp.com/vault
- **HCP Vault Cloud**: https://cloud.hashicorp.com/products/vault
- **Vault Secrets Operator**: https://github.com/hashicorp/vault-secrets-operator
- **Terraform Vault Provider**: https://registry.terraform.io/providers/hashicorp/vault

### Community Resources
- **HashiCorp Community Forum**: https://discuss.hashicorp.com/c/vault
- **GitHub Issues**: https://github.com/hashicorp/vault/issues
- **Training**: HashiCorp Learn platform

### Internal Support
- **Platform Team**: platform-team@company.com
- **Security Team**: security-team@company.com
- **On-call Support**: Use internal incident management system

### Success Metrics
- **Security**: Zero static credentials in production
- **Reliability**: 99.9% secret availability SLA
- **Performance**: <100ms average secret retrieval time
- **Adoption**: 100% of applications using centralized secrets

---

## Conclusion

This guide provides the complete foundation for implementing HashiCorp Vault across your infrastructure. Follow the implementation roadmap, use the provided examples, and adapt the patterns to your specific requirements.

**Next Steps:**
1. Start with Phase 1 foundation setup
2. Implement one use case at a time
3. Establish monitoring and operational procedures
4. Expand to additional teams and applications
5. Implement advanced enterprise patterns

For additional support or questions, contact the platform team or refer to the HashiCorp documentation and community resources.

---

*Document Version: 1.0 | Last Updated: August 2025 | HashiCorp Vault Complete User Guide*