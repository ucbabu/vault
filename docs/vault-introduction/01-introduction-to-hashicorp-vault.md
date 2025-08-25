# Introduction to HashiCorp Vault

## Table of Contents

1. [What is HashiCorp Vault?](#what-is-hashicorp-vault)
2. [Core Concepts](#core-concepts)
3. [Key Features](#key-features)
4. [Architecture Overview](#architecture-overview)
5. [Vault Cloud vs Self-Hosted](#vault-cloud-vs-self-hosted)
6. [Use Cases](#use-cases)
7. [Security Model](#security-model)
8. [Getting Started](#getting-started)
9. [Best Practices](#best-practices)
10. [Resources and Documentation](#resources-and-documentation)

## What is HashiCorp Vault?

HashiCorp Vault is a comprehensive secrets management platform designed to securely store, manage, and control access to sensitive data such as passwords, API keys, certificates, and encryption keys. Vault provides a unified interface for managing secrets across modern infrastructure, offering both cloud-based (Vault Cloud) and self-hosted deployment options.

### Key Problems Vault Solves

- **Secret Sprawl**: Eliminates scattered secrets across configuration files, environment variables, and databases
- **Static Credentials**: Replaces long-lived credentials with dynamic, short-lived secrets
- **Access Control**: Provides fine-grained access policies and audit trails
- **Compliance**: Ensures regulatory compliance with comprehensive audit logging and encryption

## Core Concepts

### 1. Secrets Engines

Secrets engines are Vault components that store, generate, or encrypt data. Different types include:

- **Key/Value (KV)**: Simple static secret storage
- **Dynamic Secrets**: Generate credentials on-demand (AWS, Azure, databases)
- **Transit**: Encryption-as-a-Service
- **PKI**: Certificate authority and certificate management

### 2. Authentication Methods

Vault supports multiple authentication methods:

- **Token**: Native Vault authentication
- **LDAP/Active Directory**: Enterprise directory integration
- **OIDC/JWT**: Modern identity provider integration
- **Cloud Provider IAM**: AWS IAM, Azure AD, Google Cloud IAM
- **Kubernetes**: Service account-based authentication

### 3. Policies

Policies define what actions are allowed on specific paths:

```hcl
# Example policy for read-only access to application secrets
path "secret/data/myapp/*" {
  capabilities = ["read"]
}

# Example policy for database credential generation
path "database/creds/readonly" {
  capabilities = ["read"]
}
```

### 4. Tokens

Tokens are the core authentication mechanism in Vault:

- **Root Tokens**: Super-admin access (use sparingly)
- **Service Tokens**: Regular access tokens with policies
- **Batch Tokens**: Lightweight tokens for high-throughput scenarios
- **Periodic Tokens**: Tokens that can be renewed indefinitely

### 5. Leases

Leases are associated with dynamic secrets and define:

- **TTL (Time To Live)**: How long the secret is valid
- **Max TTL**: Maximum renewal time
- **Renewal**: Process to extend lease duration
- **Revocation**: Process to invalidate secrets

## Key Features

### 1. Dynamic Secrets

Vault generates secrets on-demand rather than storing static credentials:

```bash
# Generate AWS credentials
vault read aws/creds/my-role

# Generate database credentials
vault read database/creds/readonly
```

**Benefits:**
- Credentials have short lifespans
- Automatic rotation and cleanup
- Audit trail for all credential access
- Reduced blast radius of compromised credentials

### 2. Encryption as a Service

Vault's Transit secrets engine provides encryption/decryption services:

```bash
# Encrypt data
vault write transit/encrypt/my-key plaintext=$(base64 <<< "my secret data")

# Decrypt data
vault write transit/decrypt/my-key ciphertext="vault:v1:abcd1234..."
```

### 3. Certificate Management

Vault can act as a Certificate Authority (CA):

- Generate root and intermediate CAs
- Issue certificates on-demand
- Automatic certificate rotation
- Integration with external CAs

### 4. Secret Versioning

KV v2 engine provides secret versioning:

- Track changes to secrets over time
- Rollback to previous versions
- Soft delete with recovery options
- Check-and-Set operations for safe updates

## Architecture Overview

### High-Level Architecture

```
┌─────────────────┐    ┌─────────────────┐    ┌─────────────────┐
│   Applications  │    │   Operators     │    │   Automation   │
│   & Services    │    │   & Users       │    │   & CI/CD      │
└─────────┬───────┘    └─────────┬───────┘    └─────────┬───────┘
          │                      │                      │
          └──────────────────────┼──────────────────────┘
                                 │
                    ┌────────────▼────────────┐
                    │     Vault Cluster       │
                    │  ┌─────────────────────┐│
                    │  │   Authentication    ││
                    │  │      Methods        ││
                    │  └─────────────────────┘│
                    │  ┌─────────────────────┐│
                    │  │    Policy Engine    ││
                    │  └─────────────────────┘│
                    │  ┌─────────────────────┐│
                    │  │   Secrets Engines   ││
                    │  └─────────────────────┘│
                    │  ┌─────────────────────┐│
                    │  │   Storage Backend   ││
                    │  └─────────────────────┘│
                    └─────────────────────────┘
                                 │
                    ┌────────────▼────────────┐
                    │   External Systems      │
                    │ ┌─────┐ ┌─────┐ ┌─────┐ │
                    │ │ AWS │ │Azure│ │ DB  │ │
                    │ └─────┘ └─────┘ └─────┘ │
                    └─────────────────────────┘
```

### Components

1. **Vault Server**: Core service that handles requests
2. **Storage Backend**: Persistent storage for encrypted data
3. **Barrier**: Encryption layer protecting stored data
4. **Secrets Engines**: Components that handle different types of secrets
5. **Auth Methods**: Authentication and identity verification
6. **Audit Devices**: Security event logging

## Vault Cloud vs Self-Hosted

### Vault Cloud (HCP Vault)

**Advantages:**
- Fully managed service
- Automatic updates and maintenance
- Built-in high availability
- Integrated monitoring and support
- Faster time to value

**Use Cases:**
- Organizations wanting managed infrastructure
- Teams with limited operational expertise
- Rapid deployment requirements
- Focus on consumption rather than management

### Self-Hosted Vault

**Advantages:**
- Complete control over infrastructure
- Customizable configurations
- On-premises or private cloud deployment
- Integration with existing infrastructure

**Use Cases:**
- Strict compliance requirements
- Air-gapped environments
- Custom infrastructure needs
- Organizations with strong operational capabilities

## Use Cases

### 1. Application Secret Management

Store and manage application secrets centrally:

```yaml
# Application configuration
database:
  host: db.example.com
  username: ${vault:secret/data/myapp/db#username}
  password: ${vault:secret/data/myapp/db#password}
```

### 2. Dynamic Database Credentials

Generate short-lived database credentials:

```bash
# Configure database connection
vault write database/config/my-mysql-database \
    plugin_name=mysql-database-plugin \
    connection_url="{{username}}:{{password}}@tcp(mysql.example.com:3306)/" \
    allowed_roles="readonly"

# Create role
vault write database/roles/readonly \
    db_name=my-mysql-database \
    creation_statements="CREATE USER '{{name}}'@'%' IDENTIFIED BY '{{password}}'; GRANT SELECT ON *.* TO '{{name}}'@'%';" \
    default_ttl="1h" \
    max_ttl="24h"

# Generate credentials
vault read database/creds/readonly
```

### 3. Cloud Provider Integration

Dynamic AWS credentials:

```bash
# Configure AWS secrets engine
vault write aws/config/root \
    access_key=AKIAI... \
    secret_key=...

# Create role
vault write aws/roles/s3-readonly \
    credential_type=iam_user \
    policy_document=-<<EOF
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Effect": "Allow",
      "Action": "s3:GetObject",
      "Resource": "*"
    }
  ]
}
EOF

# Generate credentials
vault read aws/creds/s3-readonly
```

### 4. Encryption as a Service

Encrypt/decrypt data without managing keys:

```bash
# Create encryption key
vault write transit/keys/customer-data

# Encrypt data
vault write transit/encrypt/customer-data plaintext=$(base64 <<< "sensitive data")

# Decrypt data
vault write transit/decrypt/customer-data ciphertext="vault:v1:..."
```

## Security Model

### 1. Defense in Depth

Vault implements multiple security layers:

- **Network Security**: TLS encryption, network isolation
- **Authentication**: Multiple authentication methods
- **Authorization**: Fine-grained policies
- **Audit**: Comprehensive logging
- **Encryption**: Data encrypted at rest and in transit

### 2. Zero Trust Architecture

- No implicit trust relationships
- All access must be authenticated and authorized
- Continuous verification and monitoring
- Principle of least privilege

### 3. Threat Model

Vault protects against:

- **Malicious insiders**: Role-based access control
- **Network attackers**: TLS encryption and authentication
- **Storage compromise**: Envelope encryption with master key
- **Memory attacks**: Memory encryption and secure deletion

## Getting Started

### 1. Planning Your Vault Deployment

Before implementation, consider:

- **Authentication strategy**: How users and applications will authenticate
- **Secret organization**: Namespace and path structure
- **Access patterns**: Who needs access to what secrets
- **Integration points**: Applications and systems using Vault
- **Operational requirements**: Monitoring, backup, disaster recovery

### 2. Basic Workflow

1. **Initialize**: Set up Vault cluster and unseal
2. **Configure**: Enable auth methods and secrets engines
3. **Create Policies**: Define access control rules
4. **Onboard Users**: Configure authentication and assign policies
5. **Integrate Applications**: Update applications to use Vault
6. **Monitor**: Set up logging and monitoring

### 3. Common Commands

```bash
# Check Vault status
vault status

# Authenticate
vault login -method=oidc

# Read secret
vault kv get secret/myapp/database

# Write secret
vault kv put secret/myapp/database username=dbuser password=secret123

# List secrets
vault kv list secret/

# Generate dynamic credentials
vault read aws/creds/my-role
```

## Best Practices

### 1. Authentication and Authorization

- **Use appropriate auth methods**: OIDC for users, IAM for cloud services
- **Follow least privilege**: Grant minimum necessary permissions
- **Regular policy reviews**: Audit and update policies regularly
- **Avoid long-lived tokens**: Use short TTLs and regular rotation

### 2. Secret Management

- **Use dynamic secrets**: Prefer dynamic over static secrets
- **Organize secrets logically**: Use consistent naming conventions
- **Version control policies**: Track policy changes in version control
- **Regular secret rotation**: Implement automated rotation where possible

### 3. Operations

- **Monitor everything**: Set up comprehensive monitoring and alerting
- **Automate operations**: Use infrastructure as code for Vault configuration
- **Backup regularly**: Implement automated backup and disaster recovery
- **Security scanning**: Regular vulnerability assessments and penetration testing

### 4. Application Integration

- **Use Vault agents**: Simplify integration with Vault agent templates
- **Handle failures gracefully**: Implement retry logic and circuit breakers
- **Cache appropriately**: Balance security and performance
- **Secure communication**: Always use TLS for Vault communication

## Resources and Documentation

### Official Documentation

- [Vault Documentation](https://www.vaultproject.io/docs)
- [Vault API Documentation](https://www.vaultproject.io/api-docs)
- [Vault Tutorials](https://learn.hashicorp.com/vault)
- [Vault Cloud Documentation](https://cloud.hashicorp.com/docs/vault)

### Community Resources

- [Vault GitHub Repository](https://github.com/hashicorp/vault)
- [Vault Community Forum](https://discuss.hashicorp.com/c/vault)
- [Vault Provider Registry](https://registry.terraform.io/providers/hashicorp/vault/latest)

### Training and Certification

- [HashiCorp Certified: Vault Associate](https://www.hashicorp.com/certification/vault-associate)
- [Vault Workshops and Training](https://learn.hashicorp.com/vault)

### Related Tools

- **Terraform**: Infrastructure as code for Vault configuration
- **Consul Template**: Template rendering with Vault integration
- **Vault Agent**: Simplified secret retrieval and caching
- **Boundary**: Identity-based access management (complements Vault)

---

*This documentation provides a comprehensive introduction to HashiCorp Vault. For implementation-specific guides, refer to the setup and user guides in this documentation suite.*