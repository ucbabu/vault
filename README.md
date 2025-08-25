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
│   │   └── 07-advanced-kubernetes-patterns.md
│   └── operations/
├── terraform/                          # Infrastructure as Code for Azure deployment
│   ├── main.tf
│   ├── variables.tf
│   ├── outputs.tf
│   └── terraform.tfvars.example
├── scripts/                           # Automation scripts
│   ├── vault-initial-setup.sh
│   ├── keystore-setup.sh
│   ├── azure-setup.sh
│   ├── database-setup.sh
│   └── kubernetes-vault-setup.sh
├── examples/                          # Integration examples
│   ├── python/
│   ├── kubernetes/
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

### Story 8: Implement Backup and Disaster Recovery (8 points)
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
2. **Follow setup guide**: Use [Vault Cloud Setup Guide](docs/setup-guides/02-vault-cloud-setup-guide.md)
3. **Configure keystore**: Implement using [Keystore Management Guide](docs/user-guides/03-keystore-management-guide.md)
4. **Enable dynamic rotation**: Follow Azure and database guides as needed
5. **Setup Kubernetes integration**: Configure using [Kubernetes Vault Integration](docs/user-guides/06-kubernetes-vault-integration.md)
6. **Implement advanced patterns**: Deploy using [Advanced Kubernetes Patterns](docs/user-guides/07-advanced-kubernetes-patterns.md)

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