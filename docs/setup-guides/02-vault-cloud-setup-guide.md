# HashiCorp Vault Cloud Setup and Configuration Guide

## Table of Contents

1. [Prerequisites](#prerequisites)
2. [Vault Cloud Instance Setup](#vault-cloud-instance-setup)
3. [Initial Configuration](#initial-configuration)
4. [Authentication Methods](#authentication-methods)
5. [Network Configuration](#network-configuration)
6. [Security Hardening](#security-hardening)
7. [Monitoring and Logging](#monitoring-and-logging)
8. [Backup and Recovery](#backup-and-recovery)
9. [Testing and Validation](#testing-and-validation)
10. [Troubleshooting](#troubleshooting)

## Prerequisites

### Required Access and Permissions

- HashiCorp Cloud Platform (HCP) account with billing enabled
- Organization admin or appropriate project permissions
- Network infrastructure access for VPC peering (if required)
- Identity provider admin access for OIDC/SAML configuration

### Technical Requirements

- Network connectivity planning
- SSL certificate requirements
- Identity provider integration details
- Monitoring and logging infrastructure

### Planning Checklist

- [ ] Determine Vault cluster size and region
- [ ] Plan network connectivity (public, private, or peered)
- [ ] Design authentication strategy
- [ ] Define initial namespace structure
- [ ] Plan access control policies
- [ ] Determine backup and disaster recovery requirements

## Vault Cloud Instance Setup

### 1. Create Vault Cloud Cluster

#### Using HCP Console

1. **Access HCP Console**
   ```bash
   # Navigate to https://cloud.hashicorp.com
   # Sign in with your HCP account
   ```

2. **Create New Vault Cluster**
   - Select "Vault" from the services menu
   - Click "Create cluster"
   - Choose appropriate configuration:

   ```yaml
   Cluster Configuration:
     Name: vault-production
     Region: us-west-2
     Tier: Standard (or Plus for advanced features)
     Size: Small/Medium/Large (based on requirements)
   
   Network Configuration:
     Type: Public (with IP allowlist) or Private (with peering)
     CIDR: 172.25.16.0/20 (default)
   ```

3. **Review and Create**
   - Review configuration
   - Estimate costs
   - Create cluster (deployment takes 5-10 minutes)

#### Using Terraform

```hcl
# terraform/main.tf
terraform {
  required_providers {
    hcp = {
      source  = "hashicorp/hcp"
      version = "~> 0.45"
    }
  }
}

# Configure HCP provider
provider "hcp" {
  client_id     = var.hcp_client_id
  client_secret = var.hcp_client_secret
}

# Create Vault cluster
resource "hcp_vault_cluster" "main" {
  cluster_id      = "vault-production"
  hvn_id          = hcp_hvn.main.hvn_id
  tier            = "standard_small"
  public_endpoint = true
  
  metrics_config {
    datadog_api_key = var.datadog_api_key
  }
  
  audit_log_config {
    datadog_api_key = var.datadog_api_key
  }
}

# Create HVN (HashiCorp Virtual Network)
resource "hcp_hvn" "main" {
  hvn_id         = "vault-hvn"
  cloud_provider = "aws"
  region         = "us-west-2"
  cidr_block     = "172.25.16.0/20"
}

# Output important values
output "vault_private_endpoint_url" {
  value = hcp_vault_cluster.main.vault_private_endpoint_url
}

output "vault_public_endpoint_url" {
  value = hcp_vault_cluster.main.vault_public_endpoint_url
}

output "vault_namespace" {
  value = hcp_vault_cluster.main.namespace
}
```

### 2. Retrieve Admin Token

```bash
# Using HCP CLI
hcp vault clusters list
hcp vault clusters read vault-production

# Generate admin token
hcp vault clusters generate-root-token vault-production
```

## Initial Configuration

### 1. Configure Vault CLI

```bash
# Install Vault CLI
curl -fsSL https://apt.releases.hashicorp.com/gpg | sudo apt-key add -
sudo apt-add-repository "deb [arch=amd64] https://apt.releases.hashicorp.com $(lsb_release -cs) main"
sudo apt-get update && sudo apt-get install vault

# Set environment variables
export VAULT_ADDR="https://vault-production.vault.abc123.aws.hashicorp.cloud:8200"
export VAULT_NAMESPACE="admin"

# Login with admin token
vault login
# Enter admin token when prompted
```

### 2. Enable Audit Logging

```bash
# Enable file audit device
vault audit enable file file_path=/vault/logs/audit.log

# Enable syslog audit device (alternative)
vault audit enable syslog tag="vault" facility="local0"

# Verify audit devices
vault audit list
```

### 3. Configure Initial Policies

```bash
# Create admin policy
vault policy write admin - <<EOF
# Admin policy for full access
path "*" {
  capabilities = ["create", "read", "update", "delete", "list", "sudo"]
}
EOF

# Create developer policy
vault policy write developer - <<EOF
# Developer access to application secrets
path "secret/data/apps/*" {
  capabilities = ["create", "read", "update", "delete", "list"]
}

path "secret/metadata/apps/*" {
  capabilities = ["list", "read", "delete"]
}

# Database credential access
path "database/creds/readonly" {
  capabilities = ["read"]
}
EOF

# Create operator policy
vault policy write operator - <<EOF
# Operator access for monitoring and maintenance
path "sys/health" {
  capabilities = ["read"]
}

path "sys/metrics" {
  capabilities = ["read"]
}

path "sys/mounts" {
  capabilities = ["read"]
}

path "auth/*" {
  capabilities = ["read", "list"]
}
EOF
```

## Authentication Methods

### 1. OIDC Authentication

```bash
# Enable OIDC auth method
vault auth enable oidc

# Configure OIDC
vault write auth/oidc/config \
    oidc_discovery_url="https://your-provider.com/.well-known/openid_configuration" \
    oidc_client_id="vault-client-id" \
    oidc_client_secret="your-client-secret" \
    default_role="default"

# Create OIDC role
vault write auth/oidc/role/default \
    bound_audiences="vault-client-id" \
    allowed_redirect_uris="https://vault-production.vault.abc123.aws.hashicorp.cloud:8200/ui/vault/auth/oidc/oidc/callback" \
    user_claim="email" \
    policies="developer"

# Test OIDC login
vault login -method=oidc role=default
```

### 2. AWS IAM Authentication

```bash
# Enable AWS auth method
vault auth enable aws

# Configure AWS auth
vault write auth/aws/config/client \
    secret_key="AWS_SECRET_KEY" \
    access_key="AWS_ACCESS_KEY" \
    region="us-west-2"

# Create AWS role for EC2 instances
vault write auth/aws/role/ec2-role \
    auth_type=ec2 \
    policies=developer \
    max_ttl=1h \
    bound_region=us-west-2 \
    bound_vpc_id=vpc-12345678

# Create AWS role for IAM users
vault write auth/aws/role/iam-role \
    auth_type=iam \
    policies=developer \
    max_ttl=1h \
    bound_iam_principal_arn="arn:aws:iam::123456789012:user/vault-user"
```

### 3. Kubernetes Authentication

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
    bound_service_account_namespaces=default \
    policies=developer \
    ttl=1h
```

## Network Configuration

### 1. Public Endpoint with IP Allowlist

```bash
# Configure IP allowlist using Terraform
resource "hcp_vault_cluster" "main" {
  # ... other configuration ...
  
  public_endpoint = true
  
  ip_allowlist {
    cidr        = "203.0.113.0/24"
    description = "Office network"
  }
  
  ip_allowlist {
    cidr        = "198.51.100.0/24"
    description = "Production environment"
  }
}
```

### 2. Private Endpoint with VPC Peering

```hcl
# Create VPC peering connection
resource "hcp_aws_network_peering" "main" {
  hvn_id              = hcp_hvn.main.hvn_id
  peering_id          = "vault-peering"
  peer_vpc_id         = var.vpc_id
  peer_account_id     = var.aws_account_id
  peer_vpc_region     = var.aws_region
}

# Accept peering connection (AWS side)
resource "aws_vpc_peering_connection_accepter" "main" {
  vpc_peering_connection_id = hcp_aws_network_peering.main.provider_peering_id
  auto_accept               = true

  tags = {
    Name = "vault-peering"
  }
}

# Add route to HVN
resource "hcp_hvn_route" "main" {
  hvn_link         = hcp_hvn.main.self_link
  hvn_route_id     = "vault-peering-route"
  destination_cidr = var.vpc_cidr
  target_link      = hcp_aws_network_peering.main.self_link
}

# Add route to VPC route table
resource "aws_route" "vault" {
  route_table_id            = var.route_table_id
  destination_cidr_block    = hcp_hvn.main.cidr_block
  vpc_peering_connection_id = hcp_aws_network_peering.main.provider_peering_id
}
```

### 3. Network Security Groups

```hcl
# AWS security group for Vault access
resource "aws_security_group" "vault_client" {
  name_prefix = "vault-client-"
  vpc_id      = var.vpc_id

  egress {
    from_port   = 8200
    to_port     = 8200
    protocol    = "tcp"
    cidr_blocks = [hcp_hvn.main.cidr_block]
  }

  egress {
    from_port   = 443
    to_port     = 443
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = {
    Name = "vault-client-sg"
  }
}
```

## Security Hardening

### 1. Configure TLS

```bash
# Vault Cloud automatically provides TLS certificates
# Verify TLS configuration
openssl s_client -connect vault-production.vault.abc123.aws.hashicorp.cloud:8200 -showcerts

# Configure custom domain (optional)
# Requires DNS configuration and certificate management
```

### 2. Enable MFA

```bash
# Configure TOTP MFA
vault auth enable -path=userpass userpass
vault write auth/userpass/mfa_config type=totp issuer=MyVault

# Enable MFA for specific auth method
vault write sys/mfa/method/totp/my_totp \
    issuer=MyVault \
    period=30 \
    key_size=20 \
    algorithm=SHA1 \
    digits=6

# Apply MFA to authentication method
vault write sys/mfa/login-enforcement/userpass \
    auth_method_accessors=$(vault auth list -format=json | jq -r '.["userpass/"].accessor') \
    mfa_method_ids=my_totp
```

### 3. Configure Security Headers

```bash
# Configure UI security headers
vault write sys/config/ui \
    header_x_frame_options=DENY \
    header_x_content_type_options=nosniff \
    header_referrer_policy=same-origin \
    header_strict_transport_security="max-age=31536000; includeSubDomains"
```

## Monitoring and Logging

### 1. Configure Metrics Export

```bash
# Vault Cloud automatically exports metrics to configured providers
# Configure Datadog integration in cluster settings

# View metrics endpoints
curl -H "X-Vault-Token: $VAULT_TOKEN" \
     "$VAULT_ADDR/v1/sys/metrics?format=prometheus"
```

### 2. Set Up Log Aggregation

```bash
# Vault Cloud audit logs can be exported to:
# - Datadog
# - Splunk
# - CloudWatch
# - Custom HTTPS endpoint

# Configure in HCP console or via Terraform:
resource "hcp_vault_cluster" "main" {
  # ... other configuration ...
  
  audit_log_config {
    datadog_api_key = var.datadog_api_key
  }
}
```

### 3. Configure Alerting

```yaml
# Example Datadog alerts
alerts:
  - name: "Vault Cluster Down"
    query: "avg(last_5m):avg:vault.up{cluster:vault-production} < 1"
    type: "metric alert"
    
  - name: "High Authentication Failures"
    query: "sum(last_15m):sum:vault.auth.failure{cluster:vault-production} > 100"
    type: "metric alert"
    
  - name: "Certificate Expiration"
    query: "avg(last_1h):avg:vault.pki.certificate.expiry{cluster:vault-production} < 604800"
    type: "metric alert"
```

## Backup and Recovery

### 1. Automated Snapshots

```bash
# Vault Cloud provides automated snapshots
# Configure snapshot schedule in HCP console

# Manual snapshot using API
curl -H "X-Vault-Token: $VAULT_TOKEN" \
     -X PUT \
     "$VAULT_ADDR/v1/sys/storage/raft/snapshot" \
     --output vault-snapshot-$(date +%Y%m%d-%H%M%S).snap
```

### 2. Disaster Recovery Setup

```bash
# Enable DR replication (Vault Enterprise feature)
vault write -f sys/replication/dr/primary/enable

# Generate DR secondary token
vault write sys/replication/dr/primary/secondary-token id=dr-secondary

# On DR secondary cluster
vault write sys/replication/dr/secondary/enable token="<token>"
```

## Testing and Validation

### 1. Health Checks

```bash
# Check cluster health
vault status

# Detailed health check
curl "$VAULT_ADDR/v1/sys/health"

# Check authentication methods
vault auth list

# Check policies
vault policy list

# Check secrets engines
vault secrets list
```

### 2. Integration Testing

```bash
#!/bin/bash
# integration-test.sh

set -e

echo "Testing Vault integration..."

# Test authentication
echo "Testing OIDC authentication..."
vault login -method=oidc role=default

# Test secret storage
echo "Testing secret storage..."
vault kv put secret/test/app username=testuser password=testpass
vault kv get secret/test/app

# Test dynamic secrets (if configured)
echo "Testing dynamic secrets..."
vault read database/creds/readonly

# Test policy enforcement
echo "Testing policy enforcement..."
vault auth -method=userpass username=testuser password=testpass
vault kv get secret/test/app  # Should succeed with proper policy

echo "All tests passed!"
```

### 3. Performance Testing

```bash
#!/bin/bash
# performance-test.sh

# Install vault-benchmark tool
go install github.com/hashicorp/vault-benchmark@latest

# Run read performance test
vault-benchmark \
  -duration=60s \
  -rate=100 \
  -workers=10 \
  auth-userpass

# Run write performance test  
vault-benchmark \
  -duration=60s \
  -rate=50 \
  -workers=5 \
  kv-v2-write
```

## Troubleshooting

### Common Issues

#### 1. Connection Issues

```bash
# Check network connectivity
telnet vault-production.vault.abc123.aws.hashicorp.cloud 8200

# Check DNS resolution
nslookup vault-production.vault.abc123.aws.hashicorp.cloud

# Check firewall rules
# Ensure port 8200 (HTTPS) is open in security groups/firewalls
```

#### 2. Authentication Problems

```bash
# Check auth method configuration
vault auth list -detailed

# Check user policies
vault token lookup

# Debug OIDC issues
vault read auth/oidc/config
vault read auth/oidc/role/default
```

#### 3. Performance Issues

```bash
# Check cluster status
vault status

# Monitor metrics
curl -H "X-Vault-Token: $VAULT_TOKEN" \
     "$VAULT_ADDR/v1/sys/metrics"

# Check audit log size and rotation
vault audit list -detailed
```

### Support Resources

- **HCP Support**: Available through HCP console
- **Community Forum**: [discuss.hashicorp.com](https://discuss.hashicorp.com/c/vault)
- **Documentation**: [cloud.hashicorp.com/docs/vault](https://cloud.hashicorp.com/docs/vault)
- **Status Page**: [status.hashicorp.com](https://status.hashicorp.com)

---

*This guide provides comprehensive setup instructions for HashiCorp Vault Cloud. For specific use cases and advanced configurations, refer to the additional guides in this documentation suite.*