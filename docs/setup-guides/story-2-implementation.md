# Story 2: Keystore Management Implementation

## Overview

This implementation provides complete keystore management using Vault's KV secrets engine with proper namespace organization, access control, and application integration patterns.

## Implementation Components

### 1. Configuration Scripts

- **`keystore-setup.sh`**: Automated keystore setup
  - KV secrets engine configuration
  - Namespace structure creation
  - Policy management
  - Sample secret creation

### 2. Application Integration Examples

- **Python Client** (`examples/python/vault_client.py`): Production-ready Python integration
- **Kubernetes Integration** (`examples/kubernetes/`): Vault Agent Injector patterns
- **Utility Scripts**: Backup and audit tools

### 3. Security Features

- **Role-based Access Control**: Environment and application-specific policies
- **Secret Versioning**: Configurable version limits and cleanup
- **Audit Trails**: Complete secret access logging
- **Metadata Management**: Ownership and rotation scheduling

## Deployment Instructions

### Prerequisites

- Vault Cloud instance running (from Story 1)
- Admin access to Vault
- Appropriate network connectivity

### Step 1: Run Keystore Setup

```bash
# Ensure environment variables are set
export VAULT_ADDR="https://your-vault-cluster.vault.hashicorp.cloud:8200"
export VAULT_NAMESPACE="admin"
export VAULT_TOKEN="your-admin-token"

# Run keystore setup script
cd scripts/
./keystore-setup.sh
```

### Step 2: Verify Configuration

```bash
# Check enabled secrets engines
vault secrets list

# Verify namespace structure
vault kv list secret/
vault kv list secret/prod/
vault kv list secret/prod/webapp/

# Check policies
vault policy list
vault policy read webapp
```

### Step 3: Test Application Integration

```bash
# Test Python client
cd examples/python/
pip install -r requirements.txt
python vault_client.py

# Test secret retrieval
vault kv get secret/prod/webapp/database
vault kv get secret/prod/webapp/config
```

## Keystore Structure

### Namespace Organization

```
secret/
├── prod/
│   ├── webapp/
│   │   ├── database          # Database connection details
│   │   ├── external-services # API keys and external service credentials
│   │   └── config           # Application configuration
│   ├── api/
│   │   └── config           # API service configuration
│   ├── worker/
│   └── shared/
│       ├── monitoring       # Monitoring credentials
│       ├── logging         # Logging service credentials
│       └── ci-cd           # CI/CD pipeline secrets
├── staging/
│   └── [same structure as prod]
├── dev/
│   └── [same structure as prod]

app-secrets/
├── prod/
├── staging/
└── dev/

infrastructure/
├── prod/
│   ├── aws                  # AWS infrastructure secrets
│   └── azure               # Azure infrastructure secrets
├── staging/
└── dev/

certificates/
├── prod/
│   └── webapp              # Certificate metadata
├── staging/
└── dev/
```

### Secret Categories

1. **Application Secrets** (`secret/*/app/*`)
   - Database credentials
   - External API keys
   - Application configuration
   - Session secrets

2. **Infrastructure Secrets** (`infrastructure/*/*`)
   - Cloud provider credentials
   - Network configuration
   - Infrastructure tools

3. **Certificates** (`certificates/*/*`)
   - TLS certificate metadata
   - Certificate authority information
   - Key management details

## Access Control Policies

### 1. Production Read-Only (`prod-readonly`)
```hcl
# Read-only access to production secrets
path "secret/data/prod/*" {
  capabilities = ["read"]
}

path "secret/metadata/prod/*" {
  capabilities = ["read", "list"]
}
```

### 2. Application-Specific (`webapp`)
```hcl
# Application-specific access for webapp
path "secret/data/*/webapp/*" {
  capabilities = ["read"]
}

path "app-secrets/data/*/webapp/*" {
  capabilities = ["read"]
}
```

### 3. DevOps Team (`devops`)
```hcl
# DevOps team secret management
path "secret/data/dev/*" {
  capabilities = ["create", "read", "update", "delete", "list"]
}

path "secret/data/staging/*" {
  capabilities = ["create", "read", "update", "delete", "list"]
}

path "secret/data/prod/*" {
  capabilities = ["read", "update"]
}
```

### 4. CI/CD Pipeline (`cicd-keystore`)
```hcl
# CI/CD pipeline access to secrets
path "secret/data/ci/*" {
  capabilities = ["read"]
}

path "secret/data/*/shared/ci-cd" {
  capabilities = ["read"]
}
```

## Application Integration Patterns

### 1. Python Integration

```python
from vault_client import VaultClient, SecretContext

# Initialize client
vault = VaultClient("https://vault.example.com:8200", "your-token")

# Secure secret handling
with SecretContext(vault, 'secret/prod/webapp/database') as db_config:
    conn = psycopg2.connect(
        host=db_config['host'],
        database=db_config['database'],
        user=db_config['username'],
        password=db_config['password']
    )
    # Secret automatically cleared from memory
```

### 2. Kubernetes Integration

```yaml
# Vault Agent Injector annotation
annotations:
  vault.hashicorp.com/agent-inject: "true"
  vault.hashicorp.com/role: "webapp"
  vault.hashicorp.com/agent-inject-secret-database: "secret/prod/webapp/database"
  vault.hashicorp.com/agent-inject-template-database: |
    {{- with secret "secret/prod/webapp/database" -}}
    export DB_HOST="{{ .Data.data.host }}"
    export DB_USER="{{ .Data.data.username }}"
    export DB_PASSWORD="{{ .Data.data.password }}"
    {{- end }}
```

### 3. Environment Variable Injection

```bash
# Load secrets into environment
source <(vault kv get -format=json secret/prod/webapp/config | \
  jq -r '.data.data | to_entries[] | "export \(.key)=\(.value)"')

# Start application with secrets
exec myapp
```

## Secret Lifecycle Management

### 1. Secret Versioning

```bash
# Configure versioning limits
vault kv metadata put -max-versions=10 secret/prod/
vault kv metadata put -max-versions=5 secret/staging/
vault kv metadata put -max-versions=3 secret/dev/

# Set automatic cleanup
vault kv metadata put -delete-version-after=30d secret/dev/
vault kv metadata put -delete-version-after=90d secret/staging/
```

### 2. Rotation Scheduling

```bash
# Add rotation metadata
vault kv metadata put -custom-metadata=rotation_schedule="monthly" secret/prod/webapp/database
vault kv metadata put -custom-metadata=rotation_schedule="quarterly" secret/prod/webapp/external-services
vault kv metadata put -custom-metadata=owner="webapp-team" secret/prod/webapp/
```

### 3. Backup and Audit

```bash
# Backup secrets
./scripts/backup-secrets.sh

# Audit secret usage
./scripts/audit-secrets.sh

# Check secret metadata
vault kv metadata get secret/prod/webapp/database
```

## Security Best Practices

### 1. Access Control
- **Principle of Least Privilege**: Grant minimum necessary permissions
- **Environment Isolation**: Separate policies for prod/staging/dev
- **Application Isolation**: Application-specific access policies
- **Time-based Access**: Implement time-limited tokens where possible

### 2. Secret Management
- **Regular Rotation**: Implement automated rotation schedules
- **Version Control**: Track secret changes with metadata
- **Secure Storage**: Use appropriate secret categorization
- **Cleanup Policies**: Automatic cleanup of old versions

### 3. Application Integration
- **Memory Safety**: Clear secrets from memory after use
- **Error Handling**: Secure error handling without exposing secrets
- **Caching Strategy**: Cache within lease duration only
- **Network Security**: Use TLS for all Vault communication

## Monitoring and Alerting

### 1. Audit Monitoring

```bash
# Monitor secret access patterns
jq 'select(.request.path | contains("secret/data"))' /vault/logs/audit.log

# Track secret modifications
jq 'select(.request.operation == "create" or .request.operation == "update")' /vault/logs/audit.log
```

### 2. Health Checks

```bash
# Verify secret engines
vault secrets list

# Test secret retrieval
vault kv get secret/prod/webapp/database

# Check policies
vault policy list
```

### 3. Performance Metrics

```bash
# Monitor Vault metrics
vault read sys/metrics

# Check secret count
vault kv list -format=json secret/ | jq length
```

## Troubleshooting

### Common Issues

1. **Permission Denied**
   ```bash
   # Check token capabilities
   vault token capabilities secret/data/prod/webapp/database
   
   # Check policy assignments
   vault token lookup
   ```

2. **Secret Not Found**
   ```bash
   # List available secrets
   vault kv list secret/prod/webapp/
   
   # Check secret metadata
   vault kv metadata get secret/prod/webapp/database
   ```

3. **Version Conflicts**
   ```bash
   # Get current version
   vault kv metadata get secret/prod/webapp/database
   
   # Use check-and-set
   vault kv put -cas=3 secret/prod/webapp/database key=value
   ```

## Success Criteria Validation

- [x] KV v2 secrets engine enabled and configured
- [x] Namespace structure designed for different environments
- [x] Role-based access control implemented
- [x] Secret versioning and rollback capabilities tested
- [x] Integration with application deployment pipelines
- [x] Secret rotation policies defined

## Next Steps

After completing Story 2:

1. **Migrate Existing Secrets**: Move current secrets to Vault
2. **Application Updates**: Update applications to use Vault client
3. **Automation**: Implement automated secret rotation
4. **Monitoring**: Set up secret access monitoring
5. **Azure Integration**: Configure Azure dynamic secrets (Story 3)
6. **Database Integration**: Set up database dynamic secrets (Story 4)

This implementation provides a comprehensive foundation for centralized keystore management with HashiCorp Vault.