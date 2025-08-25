# Keystore Management with HashiCorp Vault

## Table of Contents

1. [Overview](#overview)
2. [KV Secrets Engine](#kv-secrets-engine)
3. [Organizing Secrets](#organizing-secrets)
4. [Access Control and Policies](#access-control-and-policies)
5. [Secret Lifecycle Management](#secret-lifecycle-management)
6. [Application Integration](#application-integration)
7. [Best Practices](#best-practices)
8. [Monitoring and Auditing](#monitoring-and-auditing)
9. [Troubleshooting](#troubleshooting)

## Overview

Keystore management in HashiCorp Vault involves securely storing, versioning, and controlling access to sensitive configuration data such as API keys, passwords, certificates, and other secrets. This guide covers the implementation of centralized keystore management using Vault's Key/Value (KV) secrets engine.

### Benefits of Vault Keystore Management

- **Centralized Storage**: Single source of truth for all secrets
- **Access Control**: Fine-grained permissions and audit trails
- **Versioning**: Track changes and rollback capabilities
- **Encryption**: Automatic encryption at rest and in transit
- **Compliance**: Comprehensive audit logging for regulatory requirements

## KV Secrets Engine

### 1. Enable KV Secrets Engine

```bash
# Enable KV v2 secrets engine
vault secrets enable -version=2 kv

# Enable KV v2 at custom path
vault secrets enable -path=secret -version=2 kv

# Verify secrets engines
vault secrets list
```

### 2. KV v2 Features

The KV v2 secrets engine provides:

- **Versioning**: Multiple versions of each secret
- **Soft Delete**: Secrets can be deleted and recovered
- **Check-and-Set**: Prevent concurrent modifications
- **Metadata**: Additional information about secrets

### 3. Basic Operations

```bash
# Write a secret
vault kv put secret/myapp/database \
    username=dbuser \
    password=supersecret \
    host=db.example.com \
    port=5432

# Read a secret
vault kv get secret/myapp/database

# List secrets
vault kv list secret/

# List secrets in subdirectory
vault kv list secret/myapp/

# Get secret metadata
vault kv metadata get secret/myapp/database

# Get specific version
vault kv get -version=2 secret/myapp/database
```

## Organizing Secrets

### 1. Namespace Structure

Design a logical namespace structure for different environments and applications:

```
secret/
├── prod/
│   ├── app1/
│   │   ├── database
│   │   ├── api-keys
│   │   └── certificates
│   ├── app2/
│   │   ├── database
│   │   └── external-services
│   └── shared/
│       ├── monitoring
│       └── backup-credentials
├── staging/
│   ├── app1/
│   └── app2/
├── dev/
│   ├── app1/
│   └── app2/
└── shared/
    ├── ci-cd
    └── infrastructure
```

### 2. Naming Conventions

Establish consistent naming conventions:

```bash
# Environment-based structure
secret/{environment}/{application}/{service}
secret/prod/ecommerce/database
secret/staging/ecommerce/database
secret/dev/ecommerce/database

# Service-based structure
secret/{service}/{environment}/{component}
secret/database/prod/credentials
secret/database/staging/credentials

# Team-based structure
secret/{team}/{environment}/{service}
secret/platform/prod/monitoring
secret/backend/prod/payment-service
```

### 3. Secret Categories

Organize secrets by category:

```bash
# Database credentials
vault kv put secret/prod/app1/database \
    username=app1_user \
    password=secure_password \
    host=prod-db.internal \
    port=5432 \
    ssl_mode=require

# API keys and tokens
vault kv put secret/prod/app1/api-keys \
    stripe_secret_key=sk_live_... \
    sendgrid_api_key=SG... \
    aws_access_key=AKIA... \
    aws_secret_key=...

# Certificates and keys
vault kv put secret/prod/app1/certificates \
    tls_cert=@/path/to/cert.pem \
    tls_key=@/path/to/key.pem \
    ca_cert=@/path/to/ca.pem

# Application configuration
vault kv put secret/prod/app1/config \
    jwt_secret=random_jwt_secret \
    encryption_key=32_byte_encryption_key \
    session_secret=session_signing_key
```

## Access Control and Policies

### 1. Basic Policies

Create policies for different access patterns:

```hcl
# Read-only access to production secrets
path "secret/data/prod/myapp/*" {
  capabilities = ["read"]
}

# Full access to development secrets
path "secret/data/dev/myapp/*" {
  capabilities = ["create", "read", "update", "delete", "list"]
}

# Metadata access
path "secret/metadata/dev/myapp/*" {
  capabilities = ["read", "list", "delete"]
}
```

### 2. Environment-Based Policies

```hcl
# Production read-only policy
path "secret/data/prod/*" {
  capabilities = ["read"]
}

path "secret/metadata/prod/*" {
  capabilities = ["read", "list"]
}

# Development full access policy
path "secret/data/dev/*" {
  capabilities = ["create", "read", "update", "delete", "list"]
}

path "secret/metadata/dev/*" {
  capabilities = ["create", "read", "update", "delete", "list"]
}

# Staging limited access policy
path "secret/data/staging/{{identity.entity.aliases.auth_userpass_12345.name}}/*" {
  capabilities = ["create", "read", "update", "delete", "list"]
}
```

### 3. Application-Specific Policies

```hcl
# Policy for application service accounts
path "secret/data/prod/{{identity.entity.name}}/*" {
  capabilities = ["read"]
}

# Policy for specific application
path "secret/data/*/ecommerce/*" {
  capabilities = ["read"]
}

# Cross-environment read for monitoring
path "secret/data/+/shared/monitoring" {
  capabilities = ["read"]
}
```

### 4. Advanced Policy Examples

```hcl
# Check-and-set policy (prevent concurrent updates)
path "secret/data/prod/critical-app/*" {
  capabilities = ["create", "read", "update"]
  required_parameters = ["cas"]
}

# Time-based access (during business hours)
path "secret/data/sensitive/*" {
  capabilities = ["read"]
  allowed_parameters = {
    "time" = ["9:00-17:00"]
  }
}

# IP-based restrictions
path "secret/data/admin/*" {
  capabilities = ["create", "read", "update", "delete"]
  bound_cidrs = ["10.0.0.0/8", "192.168.1.0/24"]
}
```

## Secret Lifecycle Management

### 1. Secret Versioning

```bash
# Create initial version
vault kv put secret/myapp/database username=user1 password=pass1

# Update secret (creates version 2)
vault kv put secret/myapp/database username=user1 password=new_pass

# Check version history
vault kv metadata get secret/myapp/database

# Get specific version
vault kv get -version=1 secret/myapp/database

# Check differences between versions
vault kv get -version=1 secret/myapp/database
vault kv get -version=2 secret/myapp/database
```

### 2. Secret Rotation

```bash
#!/bin/bash
# secret-rotation.sh

SECRET_PATH="secret/prod/myapp/database"
CURRENT_VERSION=$(vault kv metadata get -format=json $SECRET_PATH | jq -r '.data.current_version')

# Generate new password
NEW_PASSWORD=$(openssl rand -base64 32)

# Update database password (application should handle gracefully)
update_database_password "$NEW_PASSWORD"

# Update Vault secret
vault kv put $SECRET_PATH \
    username=dbuser \
    password="$NEW_PASSWORD" \
    host=db.example.com \
    port=5432

echo "Rotated secret from version $CURRENT_VERSION to $(($CURRENT_VERSION + 1))"
```

### 3. Automated Rotation with CI/CD

```yaml
# .github/workflows/secret-rotation.yml
name: Secret Rotation
on:
  schedule:
    - cron: '0 2 * * 0'  # Weekly on Sunday at 2 AM
  workflow_dispatch:

jobs:
  rotate-secrets:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v3
      
      - name: Setup Vault
        run: |
          curl -fsSL https://apt.releases.hashicorp.com/gpg | sudo apt-key add -
          sudo apt-add-repository "deb [arch=amd64] https://apt.releases.hashicorp.com $(lsb_release -cs) main"
          sudo apt-get update && sudo apt-get install vault
          
      - name: Authenticate to Vault
        run: |
          export VAULT_ADDR=${{ secrets.VAULT_ADDR }}
          vault login -method=jwt role=ci-cd jwt=${{ secrets.VAULT_JWT }}
          
      - name: Rotate API Keys
        run: |
          ./scripts/rotate-api-keys.sh
          
      - name: Rotate Database Passwords
        run: |
          ./scripts/rotate-db-passwords.sh
```

### 4. Secret Cleanup

```bash
# Soft delete (recoverable)
vault kv delete secret/old-app/database

# Permanently delete specific versions
vault kv destroy -versions=1,2 secret/myapp/database

# Undelete (recover soft-deleted secret)
vault kv undelete -versions=3 secret/old-app/database

# Set maximum versions
vault kv metadata put -max-versions=5 secret/myapp/database

# Configure automatic cleanup
vault kv metadata put -delete-version-after=30d secret/myapp/database
```

## Application Integration

### 1. Direct API Integration

```python
# Python example
import requests
import json

class VaultClient:
    def __init__(self, vault_url, token):
        self.vault_url = vault_url
        self.headers = {'X-Vault-Token': token}
    
    def get_secret(self, path):
        response = requests.get(
            f"{self.vault_url}/v1/secret/data/{path}",
            headers=self.headers
        )
        if response.status_code == 200:
            return response.json()['data']['data']
        else:
            raise Exception(f"Failed to get secret: {response.text}")
    
    def put_secret(self, path, data):
        payload = {'data': data}
        response = requests.post(
            f"{self.vault_url}/v1/secret/data/{path}",
            headers=self.headers,
            json=payload
        )
        if response.status_code != 200:
            raise Exception(f"Failed to put secret: {response.text}")

# Usage
vault = VaultClient("https://vault.example.com:8200", "your-token")
db_config = vault.get_secret("prod/myapp/database")

# Connect to database
import psycopg2
conn = psycopg2.connect(
    host=db_config['host'],
    database=db_config['database'],
    user=db_config['username'],
    password=db_config['password']
)
```

### 2. Using Vault Agent

```hcl
# vault-agent.hcl
pid_file = "./pidfile"

vault {
  address = "https://vault.example.com:8200"
}

auto_auth {
  method "aws" {
    mount_path = "auth/aws"
    config = {
      type = "iam"
      role = "my-app-role"
    }
  }

  sink "file" {
    config = {
      path = "/tmp/vault-token"
    }
  }
}

template {
  source      = "/etc/myapp/database.tpl"
  destination = "/etc/myapp/database.conf"
  perms       = 0600
  command     = "systemctl reload myapp"
}
```

```bash
# database.tpl
{{- with secret "secret/prod/myapp/database" -}}
[database]
host = {{ .Data.data.host }}
port = {{ .Data.data.port }}
username = {{ .Data.data.username }}
password = {{ .Data.data.password }}
{{- end }}
```

### 3. Kubernetes Integration

```yaml
# vault-secret-operator.yaml
apiVersion: secrets.hashicorp.com/v1beta1
kind: VaultAuth
metadata:
  name: default
  namespace: myapp
spec:
  method: kubernetes
  mount: kubernetes
  kubernetes:
    role: myapp
    serviceAccount: myapp
---
apiVersion: secrets.hashicorp.com/v1beta1
kind: VaultStaticSecret
metadata:
  name: database-secret
  namespace: myapp
spec:
  type: kv-v2
  mount: secret
  path: prod/myapp/database
  destination:
    name: database-secret
    create: true
  refreshAfter: 30s
  vaultAuthRef: default
```

### 4. Environment Variable Injection

```bash
#!/bin/bash
# env-from-vault.sh

export VAULT_ADDR="https://vault.example.com:8200"
export VAULT_TOKEN="$(cat /tmp/vault-token)"

# Function to get secret value
get_secret() {
    vault kv get -field="$2" "secret/prod/myapp/$1"
}

# Export database configuration
export DB_HOST=$(get_secret "database" "host")
export DB_USER=$(get_secret "database" "username")
export DB_PASS=$(get_secret "database" "password")
export DB_NAME=$(get_secret "database" "database")

# Export API keys
export STRIPE_KEY=$(get_secret "api-keys" "stripe_secret_key")
export SENDGRID_KEY=$(get_secret "api-keys" "sendgrid_api_key")

# Start application with injected environment
exec "$@"
```

## Best Practices

### 1. Secret Organization

- **Use consistent naming conventions** across all environments
- **Implement hierarchical structure** for easy management
- **Separate secrets by environment** (prod, staging, dev)
- **Group related secrets together** (database, API keys, certificates)

### 2. Access Control

- **Apply principle of least privilege** - grant minimal necessary access
- **Use environment-specific policies** to prevent cross-environment access
- **Implement role-based access control** for different user types
- **Regular policy audits** to ensure appropriate access

### 3. Secret Management

- **Use secret versioning** for rollback capabilities
- **Implement regular rotation** for sensitive credentials
- **Set appropriate TTLs** for different secret types
- **Use automation** for secret lifecycle management

### 4. Security

- **Enable audit logging** for all secret access
- **Use strong authentication methods** (OIDC, mutual TLS)
- **Implement network isolation** for Vault access
- **Regular security reviews** and penetration testing

## Monitoring and Auditing

### 1. Audit Log Analysis

```bash
# Parse audit logs for secret access
jq 'select(.type == "request" and .request.path | contains("secret/data"))' \
   /vault/logs/audit.log

# Monitor failed authentication attempts
jq 'select(.type == "response" and .error != null)' \
   /vault/logs/audit.log

# Track secret modifications
jq 'select(.request.operation == "create" or .request.operation == "update")' \
   /vault/logs/audit.log
```

### 2. Metrics and Alerting

```yaml
# Prometheus alerting rules
groups:
  - name: vault-secrets
    rules:
      - alert: VaultSecretAccessFailure
        expr: increase(vault_audit_log_request_failure_total[5m]) > 10
        for: 2m
        annotations:
          summary: "High number of failed secret access attempts"
          
      - alert: VaultSecretNotRotated
        expr: time() - vault_secret_last_updated > 604800  # 7 days
        annotations:
          summary: "Secret hasn't been rotated in over 7 days"
          
      - alert: VaultKVStorageUsage
        expr: vault_secret_kv_count > 1000
        annotations:
          summary: "High number of secrets stored"
```

### 3. Secret Usage Tracking

```python
# secret-usage-tracker.py
import json
import re
from collections import defaultdict
from datetime import datetime

def analyze_secret_usage(audit_log_file):
    secret_access = defaultdict(lambda: {'count': 0, 'users': set(), 'last_access': None})
    
    with open(audit_log_file, 'r') as f:
        for line in f:
            try:
                log_entry = json.loads(line)
                if (log_entry.get('type') == 'request' and 
                    'secret/data' in log_entry.get('request', {}).get('path', '')):
                    
                    path = log_entry['request']['path']
                    user = log_entry['auth'].get('display_name', 'unknown')
                    timestamp = log_entry['time']
                    
                    secret_access[path]['count'] += 1
                    secret_access[path]['users'].add(user)
                    secret_access[path]['last_access'] = timestamp
                    
            except json.JSONDecodeError:
                continue
    
    # Generate usage report
    for path, data in secret_access.items():
        print(f"Secret: {path}")
        print(f"  Access count: {data['count']}")
        print(f"  Users: {', '.join(data['users'])}")
        print(f"  Last access: {data['last_access']}")
        print()

if __name__ == "__main__":
    analyze_secret_usage("/vault/logs/audit.log")
```

## Troubleshooting

### Common Issues

#### 1. Permission Denied

```bash
# Check current token capabilities
vault token capabilities secret/data/myapp/database

# Check policy assignments
vault token lookup

# Debug policy evaluation
vault policy read my-policy

# Test with different token
vault auth -method=userpass username=testuser
vault kv get secret/data/myapp/database
```

#### 2. Secret Not Found

```bash
# List available secrets
vault kv list secret/

# Check secret metadata
vault kv metadata get secret/myapp/database

# Check if secret was deleted
vault kv metadata get secret/myapp/database | grep deletion_time

# Undelete if soft-deleted
vault kv undelete -versions=1 secret/myapp/database
```

#### 3. Version Conflicts

```bash
# Check current version
vault kv metadata get secret/myapp/database

# Use check-and-set to prevent conflicts
CURRENT_VERSION=$(vault kv metadata get -format=json secret/myapp/database | jq -r '.data.current_version')
vault kv put -cas=$CURRENT_VERSION secret/myapp/database username=newuser password=newpass
```

#### 4. Performance Issues

```bash
# Check secret engine configuration
vault secrets list -detailed

# Monitor metrics
vault read sys/metrics

# Check for large secrets
vault kv metadata get secret/large-secret

# Optimize secret structure
# - Split large secrets into smaller ones
# - Use appropriate max-versions settings
# - Implement cleanup policies
```

### Debugging Commands

```bash
# Enable debug logging
export VAULT_LOG_LEVEL=debug

# Check Vault server logs
vault operator diagnose

# Verify network connectivity
vault status

# Check authentication method
vault auth list

# Verify secrets engine
vault secrets list -detailed

# Test basic operations
vault kv put secret/test key=value
vault kv get secret/test
vault kv delete secret/test
```

---

*This guide provides comprehensive coverage of keystore management with HashiCorp Vault. For specific integration patterns and advanced use cases, refer to the additional guides in this documentation suite.*