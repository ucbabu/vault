# Kubernetes Integration with HashiCorp Vault

## Table of Contents

1. [Overview](#overview)
2. [Architecture Patterns](#architecture-patterns)
3. [Kubernetes Authentication Setup](#kubernetes-authentication-setup)
4. [Vault Secrets Operator](#vault-secrets-operator)
5. [Secret Consumption Patterns](#secret-consumption-patterns)
6. [Advanced Integration Patterns](#advanced-integration-patterns)
7. [Security Best Practices](#security-best-practices)
8. [Monitoring and Troubleshooting](#monitoring-and-troubleshooting)

## Overview

This guide covers the complete integration of Kubernetes with HashiCorp Vault, enabling secure secret management for containerized applications. The integration provides multiple patterns for consuming secrets while maintaining security boundaries and operational simplicity.

### Benefits of Kubernetes-Vault Integration

- **Native Authentication**: Kubernetes service accounts authenticate directly with Vault
- **Zero Credential Storage**: No secrets stored in Kubernetes manifests or container images
- **Dynamic Secret Management**: Support for both static and dynamic secrets
- **Namespace Isolation**: Strong security boundaries between different teams/applications
- **Native Kubernetes Experience**: Secrets appear as standard Kubernetes resources
- **Automatic Rotation**: Built-in support for secret rotation and renewal

### Integration Methods

1. **Vault Secrets Operator**: Custom Resource Definitions (CRDs) for declarative secret management
2. **Vault Agent Injector**: Sidecar and init container patterns
3. **Secrets Store CSI Driver**: Volume-mounted secrets
4. **Direct API Integration**: Application-level Vault SDK integration

## Architecture Patterns

### 1. Vault Secrets Operator Architecture

```
┌─────────────────────────────────────────────────────────────┐
│                    Kubernetes Cluster                      │
│                                                             │
│  ┌─────────────────┐    ┌─────────────────┐               │
│  │   Namespace A   │    │   Namespace B   │               │
│  │                 │    │                 │               │
│  │ ┌─────────────┐ │    │ ┌─────────────┐ │               │
│  │ │ VaultAuth   │ │    │ │ VaultAuth   │ │               │
│  │ │   (CRD)     │ │    │ │   (CRD)     │ │               │
│  │ └─────────────┘ │    │ └─────────────┘ │               │
│  │                 │    │                 │               │
│  │ ┌─────────────┐ │    │ ┌─────────────┐ │               │
│  │ │VaultSecret  │ │    │ │VaultSecret  │ │               │
│  │ │Static/Dyn   │ │    │ │Static/Dyn   │ │               │
│  │ └─────────────┘ │    │ └─────────────┘ │               │
│  │        │        │    │        │        │               │
│  │        ▼        │    │        ▼        │               │
│  │ ┌─────────────┐ │    │ ┌─────────────┐ │               │
│  │ │K8s Secret   │ │    │ │K8s Secret   │ │               │
│  │ └─────────────┘ │    │ └─────────────┘ │               │
│  └─────────────────┘    └─────────────────┘               │
│                                                             │
│  ┌─────────────────────────────────────────────────────┐   │
│  │           Vault Secrets Operator                   │   │
│  │                                                     │   │
│  │  ┌───────────────┐    ┌───────────────────────────┐ │   │
│  │  │  Controller   │◄──►│    Vault API Client       │ │   │
│  │  │   Manager     │    │                           │ │   │
│  │  └───────────────┘    └───────────────────────────┘ │   │
│  └─────────────────────────────────────────────────────┘   │
└─────────────────────┼───────────────────────────────────────┘
                      │
                      ▼
              ┌─────────────────┐
              │ HashiCorp Vault │
              │     Cluster     │
              └─────────────────┘
```

### 2. Multiple Authentication Flows

```mermaid
graph TD
    A[Pod with ServiceAccount] -->|JWT Token| B[Vault Kubernetes Auth]
    B --> C{Token Validation}
    C -->|Valid| D[Vault Token Issued]
    C -->|Invalid| E[Authentication Failed]
    D --> F[Access Vault Secrets]
    F --> G[Vault Secrets Operator]
    G --> H[Kubernetes Secret Created]
    H --> I[Pod Consumes Secret]
```

## Kubernetes Authentication Setup

### 1. Prerequisites

- Kubernetes cluster with admin access
- HashiCorp Vault instance configured
- Network connectivity between Kubernetes and Vault
- `kubectl` configured with cluster access

### 2. Enable Kubernetes Authentication in Vault

```bash
# Enable the Kubernetes authentication method
vault auth enable kubernetes

# Get the Kubernetes cluster information
KUBERNETES_HOST=$(kubectl config view --raw --minify --flatten -o jsonpath='{.clusters[].cluster.server}')
KUBERNETES_CA_CERT=$(kubectl config view --raw --minify --flatten -o jsonpath='{.clusters[].cluster.certificate-authority-data}' | base64 -d)

# Configure the Kubernetes authentication method
vault write auth/kubernetes/config \
    token_reviewer_jwt="$(kubectl create token vault-auth --duration=8760h)" \
    kubernetes_host="$KUBERNETES_HOST" \
    kubernetes_ca_cert="$KUBERNETES_CA_CERT" \
    issuer="https://kubernetes.default.svc.cluster.local"
```

### 3. Create Service Account for Vault Authentication

```yaml
# vault-auth-serviceaccount.yaml
apiVersion: v1
kind: ServiceAccount
metadata:
  name: vault-auth
  namespace: vault-secrets-operator-system
---
apiVersion: rbac.authorization.k8s.io/v1
kind: ClusterRoleBinding
metadata:
  name: vault-auth-delegator
roleRef:
  apiGroup: rbac.authorization.k8s.io
  kind: ClusterRole
  name: system:auth-delegator
subjects:
- kind: ServiceAccount
  name: vault-auth
  namespace: vault-secrets-operator-system
```

### 4. Configure Kubernetes Roles in Vault

```bash
# Create a policy for application secrets
vault policy write webapp-policy - <<EOF
# Read application secrets
path "secret/data/webapp/*" {
  capabilities = ["read"]
}

# Read database dynamic secrets
path "database/creds/webapp" {
  capabilities = ["read"]
}

# Read Azure dynamic secrets
path "azure/creds/webapp" {
  capabilities = ["read"]
}
EOF

# Create Kubernetes role for webapp namespace
vault write auth/kubernetes/role/webapp \
    bound_service_account_names=webapp \
    bound_service_account_namespaces=webapp \
    policies=webapp-policy \
    ttl=1h \
    max_ttl=4h

# Create role for multiple namespaces
vault write auth/kubernetes/role/platform \
    bound_service_account_names=platform-service \
    bound_service_account_namespaces=platform,monitoring,logging \
    policies=platform-policy \
    ttl=2h \
    max_ttl=8h

# Create role with wildcard service account names
vault write auth/kubernetes/role/dev-apps \
    bound_service_account_names="*" \
    bound_service_account_namespaces=development \
    policies=dev-policy \
    ttl=30m \
    max_ttl=2h
```

## Vault Secrets Operator

### 1. Installation

#### Using Helm

```bash
# Add HashiCorp Helm repository
helm repo add hashicorp https://helm.releases.hashicorp.com
helm repo update

# Install Vault Secrets Operator
helm install vault-secrets-operator hashicorp/vault-secrets-operator \
    --namespace vault-secrets-operator-system \
    --create-namespace \
    --set defaultVaultConnection.enabled=true \
    --set defaultVaultConnection.address="https://vault.example.com:8200" \
    --set defaultVaultConnection.skipTLSVerify=false
```

#### Using Kubectl

```bash
# Apply the operator manifests
kubectl apply -f https://raw.githubusercontent.com/hashicorp/vault-secrets-operator/main/config/crd/bases/secrets.hashicorp.com_vaultauths.yaml
kubectl apply -f https://raw.githubusercontent.com/hashicorp/vault-secrets-operator/main/config/crd/bases/secrets.hashicorp.com_vaultconnections.yaml
kubectl apply -f https://raw.githubusercontent.com/hashicorp/vault-secrets-operator/main/config/crd/bases/secrets.hashicorp.com_vaultdynamicsecrets.yaml
kubectl apply -f https://raw.githubusercontent.com/hashicorp/vault-secrets-operator/main/config/crd/bases/secrets.hashicorp.com_vaultstaticsecrets.yaml

# Deploy the operator
kubectl apply -f https://raw.githubusercontent.com/hashicorp/vault-secrets-operator/main/config/default/default.yaml
```

### 2. Configure VaultConnection

```yaml
# vault-connection.yaml
apiVersion: secrets.hashicorp.com/v1beta1
kind: VaultConnection
metadata:
  name: default
  namespace: vault-secrets-operator-system
spec:
  # Vault server address
  address: https://vault.example.com:8200
  
  # Skip TLS verification (only for development)
  skipTLSVerify: false
  
  # TLS configuration
  tlsConfig:
    # CA certificate for Vault server
    caCertSecretRef: vault-ca-cert
  
  # Headers to send to Vault
  headers:
    X-Custom-Header: value
```

### 3. Configure VaultAuth

```yaml
# vault-auth.yaml
apiVersion: secrets.hashicorp.com/v1beta1
kind: VaultAuth
metadata:
  name: webapp-auth
  namespace: webapp
spec:
  # Vault connection reference
  vaultConnectionRef: vault-secrets-operator-system/default
  
  # Authentication method
  method: kubernetes
  mount: kubernetes
  
  # Kubernetes-specific configuration
  kubernetes:
    # Vault role to use
    role: webapp
    
    # Service account for authentication
    serviceAccount: webapp
    
    # Optional: specify audiences
    audiences:
      - vault
```

### 4. Static Secrets with VaultStaticSecret

```yaml
# vault-static-secret.yaml
apiVersion: secrets.hashicorp.com/v1beta1
kind VaultStaticSecret
metadata:
  name: webapp-config
  namespace: webapp
spec:
  # Reference to VaultAuth
  vaultAuthRef: webapp-auth
  
  # Vault path for the secret
  mount: secret
  type: kv-v2
  path: webapp/config
  
  # Kubernetes secret configuration
  destination:
    name: webapp-config
    create: true
    type: Opaque
    
  # Refresh interval
  refreshAfter: 30s
  
  # Rollout restart targets
  rolloutRestartTargets:
    - kind: Deployment
      name: webapp
```

### 5. Dynamic Secrets with VaultDynamicSecret

```yaml
# vault-dynamic-secret.yaml
apiVersion: secrets.hashicorp.com/v1beta1
kind: VaultDynamicSecret
metadata:
  name: webapp-database
  namespace: webapp
spec:
  # Reference to VaultAuth
  vaultAuthRef: webapp-auth
  
  # Vault path for dynamic secret
  mount: database
  path: creds/webapp
  
  # Kubernetes secret configuration
  destination:
    name: webapp-database
    create: true
    
  # Renewal configuration
  renewalPercent: 67
  revoke: true
  
  # Rollout restart targets
  rolloutRestartTargets:
    - kind: Deployment
      name: webapp
```

## Secret Consumption Patterns

### 1. Environment Variables

```yaml
# webapp-deployment.yaml
apiVersion: apps/v1
kind: Deployment
metadata:
  name: webapp
  namespace: webapp
spec:
  replicas: 3
  selector:
    matchLabels:
      app: webapp
  template:
    metadata:
      labels:
        app: webapp
    spec:
      serviceAccountName: webapp
      containers:
      - name: webapp
        image: webapp:latest
        env:
        # Static secrets from Vault
        - name: APP_SECRET_KEY
          valueFrom:
            secretKeyRef:
              name: webapp-config
              key: secret_key
        - name: API_TOKEN
          valueFrom:
            secretKeyRef:
              name: webapp-config
              key: api_token
              
        # Dynamic database credentials
        - name: DB_USERNAME
          valueFrom:
            secretKeyRef:
              name: webapp-database
              key: username
        - name: DB_PASSWORD
          valueFrom:
            secretKeyRef:
              name: webapp-database
              key: password
              
        # Azure dynamic credentials
        - name: AZURE_CLIENT_ID
          valueFrom:
            secretKeyRef:
              name: webapp-azure
              key: client_id
        - name: AZURE_CLIENT_SECRET
          valueFrom:
            secretKeyRef:
              name: webapp-azure
              key: client_secret
```

### 2. Volume Mounts

```yaml
# webapp-with-volumes.yaml
apiVersion: apps/v1
kind: Deployment
metadata:
  name: webapp
  namespace: webapp
spec:
  template:
    spec:
      serviceAccountName: webapp
      containers:
      - name: webapp
        image: webapp:latest
        volumeMounts:
        # Mount static secrets
        - name: app-config
          mountPath: /etc/secrets/config
          readOnly: true
          
        # Mount database credentials
        - name: database-creds
          mountPath: /etc/secrets/database
          readOnly: true
          
        # Mount certificates
        - name: tls-certs
          mountPath: /etc/ssl/certs
          readOnly: true
          
      volumes:
      # Static application config
      - name: app-config
        secret:
          secretName: webapp-config
          items:
          - key: config.yaml
            path: app-config.yaml
            
      # Dynamic database credentials
      - name: database-creds
        secret:
          secretName: webapp-database
          
      # TLS certificates
      - name: tls-certs
        secret:
          secretName: webapp-tls
```

### 3. Init Container Pattern

```yaml
# webapp-with-init.yaml
apiVersion: apps/v1
kind: Deployment
metadata:
  name: webapp
  namespace: webapp
spec:
  template:
    spec:
      serviceAccountName: webapp
      
      # Init container to prepare secrets
      initContainers:
      - name: secret-init
        image: alpine:latest
        command:
        - sh
        - -c
        - |
          # Wait for secrets to be available
          while [ ! -f /secrets/database/username ]; do
            echo "Waiting for database credentials..."
            sleep 2
          done
          
          # Create connection string
          DB_USER=$(cat /secrets/database/username)
          DB_PASS=$(cat /secrets/database/password)
          echo "postgresql://$DB_USER:$DB_PASS@postgres:5432/webapp" > /shared/db-connection
          
        volumeMounts:
        - name: database-creds
          mountPath: /secrets/database
        - name: shared-data
          mountPath: /shared
          
      containers:
      - name: webapp
        image: webapp:latest
        command:
        - sh
        - -c
        - |
          export DATABASE_URL=$(cat /shared/db-connection)
          exec /app/webapp
          
        volumeMounts:
        - name: shared-data
          mountPath: /shared
          
      volumes:
      - name: database-creds
        secret:
          secretName: webapp-database
      - name: shared-data
        emptyDir: {}
```

## Advanced Integration Patterns

### 1. Multi-Namespace Setup

```yaml
# Platform-wide VaultAuth for shared services
apiVersion: secrets.hashicorp.com/v1beta1
kind: VaultAuth
metadata:
  name: platform-auth
  namespace: platform
spec:
  vaultConnectionRef: vault-secrets-operator-system/default
  method: kubernetes
  mount: kubernetes
  kubernetes:
    role: platform
    serviceAccount: platform-service
---
# Cross-namespace secret sharing
apiVersion: secrets.hashicorp.com/v1beta1
kind: VaultStaticSecret
metadata:
  name: shared-config
  namespace: platform
spec:
  vaultAuthRef: platform-auth
  mount: secret
  type: kv-v2
  path: shared/platform-config
  destination:
    name: shared-config
    create: true
    
  # Sync to multiple namespaces
  syncConfig:
    instantUpdates: true
    
  # Create secrets in multiple namespaces
  destinationTransformation:
    templates:
      shared-config:
        text: |
          apiKey: {{ .Secrets.api_key }}
          region: {{ .Secrets.region }}
```

### 2. Secret Rotation Handling

```yaml
# Deployment with automatic restart on secret rotation
apiVersion: apps/v1
kind: Deployment
metadata:
  name: webapp
  namespace: webapp
  annotations:
    # Trigger restart when secrets change
    vault.hashicorp.com/agent-inject-secret-rotation: "true"
spec:
  template:
    metadata:
      annotations:
        # Checksum will change when secrets rotate
        vault.hashicorp.com/secret-checksum: "{{ checksum .Values.secrets }}"
    spec:
      containers:
      - name: webapp
        image: webapp:latest
        env:
        - name: SECRET_CHECKSUM
          value: "{{ checksum .Values.secrets }}"
          
        # Graceful shutdown handling
        lifecycle:
          preStop:
            exec:
              command:
              - /bin/sh
              - -c
              - |
                # Graceful shutdown with secret cleanup
                echo "Received termination signal, shutting down gracefully..."
                # Allow time for active requests to complete
                sleep 15
```

### 3. Development and Testing Patterns

```yaml
# Development environment with relaxed security
apiVersion: secrets.hashicorp.com/v1beta1
kind: VaultAuth
metadata:
  name: dev-auth
  namespace: development
spec:
  vaultConnectionRef: vault-secrets-operator-system/default
  method: kubernetes
  mount: kubernetes
  kubernetes:
    role: dev-apps  # Allows any service account in namespace
    serviceAccount: default
---
# Testing with mock secrets
apiVersion: secrets.hashicorp.com/v1beta1
kind: VaultStaticSecret
metadata:
  name: test-secrets
  namespace: development
spec:
  vaultAuthRef: dev-auth
  mount: secret
  type: kv-v2
  path: dev/test-data
  destination:
    name: test-secrets
    create: true
    
  # Override for testing
  destinationTransformation:
    templates:
      config.yaml: |
        {{- if eq .Values.environment "test" }}
        # Test configuration
        database_url: "sqlite:///tmp/test.db"
        debug: true
        {{- else }}
        # Development configuration
        database_url: "{{ .Secrets.database_url }}"
        debug: {{ .Secrets.debug }}
        {{- end }}
```

## Security Best Practices

### 1. Namespace Isolation

```bash
# Create namespace-specific roles
vault write auth/kubernetes/role/webapp-prod \
    bound_service_account_names=webapp \
    bound_service_account_namespaces=webapp-production \
    policies=webapp-prod-policy \
    ttl=1h

vault write auth/kubernetes/role/webapp-staging \
    bound_service_account_names=webapp \
    bound_service_account_namespaces=webapp-staging \
    policies=webapp-staging-policy \
    ttl=2h

# Different policies for different environments
vault policy write webapp-prod-policy - <<EOF
# Production - read-only static secrets
path "secret/data/prod/webapp/*" {
  capabilities = ["read"]
}

# Production database access
path "database/creds/webapp-prod" {
  capabilities = ["read"]
}
EOF

vault policy write webapp-staging-policy - <<EOF
# Staging - more permissive
path "secret/data/staging/webapp/*" {
  capabilities = ["read"]
}

path "secret/data/shared/dev-tools/*" {
  capabilities = ["read"]
}

path "database/creds/webapp-staging" {
  capabilities = ["read"]
}
EOF
```

### 2. Service Account Security

```yaml
# Minimal service account with specific permissions
apiVersion: v1
kind: ServiceAccount
metadata:
  name: webapp
  namespace: webapp-production
  annotations:
    # Disable token auto-mount for security
    vault.hashicorp.com/agent-inject: "false"
automountServiceAccountToken: false
---
# Dedicated RBAC for Vault integration only
apiVersion: rbac.authorization.k8s.io/v1
kind: Role
metadata:
  namespace: webapp-production
  name: vault-secret-reader
rules:
- apiGroups: [""]
  resources: ["secrets"]
  verbs: ["get", "list"]
- apiGroups: ["secrets.hashicorp.com"]
  resources: ["vaultauths", "vaultstaticsecrets", "vaultdynamicsecrets"]
  verbs: ["get", "list"]
---
apiVersion: rbac.authorization.k8s.io/v1
kind: RoleBinding
metadata:
  name: webapp-vault-access
  namespace: webapp-production
subjects:
- kind: ServiceAccount
  name: webapp
  namespace: webapp-production
roleRef:
  kind: Role
  name: vault-secret-reader
  apiGroup: rbac.authorization.k8s.io
```

### 3. Network Security

```yaml
# Network policy to restrict Vault access
apiVersion: networking.k8s.io/v1
kind: NetworkPolicy
metadata:
  name: vault-access
  namespace: webapp-production
spec:
  podSelector:
    matchLabels:
      app: webapp
  policyTypes:
  - Egress
  egress:
  # Allow access to Vault
  - to:
    - namespaceSelector:
        matchLabels:
          name: vault-secrets-operator-system
    ports:
    - protocol: TCP
      port: 8200
      
  # Allow access to Vault external endpoint
  - to: []
    ports:
    - protocol: TCP
      port: 443
    - protocol: TCP
      port: 8200
      
  # Allow DNS
  - to:
    - namespaceSelector:
        matchLabels:
          name: kube-system
    ports:
    - protocol: UDP
      port: 53
```

## Monitoring and Troubleshooting

### 1. Monitoring Setup

```yaml
# ServiceMonitor for Vault Secrets Operator
apiVersion: monitoring.coreos.com/v1
kind: ServiceMonitor
metadata:
  name: vault-secrets-operator
  namespace: vault-secrets-operator-system
spec:
  selector:
    matchLabels:
      app.kubernetes.io/name: vault-secrets-operator
  endpoints:
  - port: metrics
    interval: 30s
    path: /metrics
---
# PrometheusRule for alerting
apiVersion: monitoring.coreos.com/v1
kind: PrometheusRule
metadata:
  name: vault-secrets-operator
  namespace: vault-secrets-operator-system
spec:
  groups:
  - name: vault-secrets-operator
    rules:
    - alert: VaultSecretSyncFailure
      expr: vault_secret_sync_errors_total > 0
      for: 5m
      annotations:
        summary: "Vault secret sync failing"
        description: "VaultSecret {{ $labels.name }} in namespace {{ $labels.namespace }} has failed to sync"
        
    - alert: VaultAuthenticationFailure
      expr: vault_auth_failures_total > 10
      for: 2m
      annotations:
        summary: "High number of Vault authentication failures"
```

### 2. Debugging Commands

```bash
# Check Vault Secrets Operator status
kubectl get pods -n vault-secrets-operator-system
kubectl logs -n vault-secrets-operator-system deployment/vault-secrets-operator

# Check VaultAuth status
kubectl get vaultauth -A
kubectl describe vaultauth webapp-auth -n webapp

# Check VaultStaticSecret status
kubectl get vaultstaticsecret -A
kubectl describe vaultstaticsecret webapp-config -n webapp

# Check generated Kubernetes secrets
kubectl get secrets -n webapp
kubectl describe secret webapp-config -n webapp

# Check Vault connection
kubectl port-forward -n vault-secrets-operator-system svc/vault-secrets-operator 8080:8080
curl http://localhost:8080/metrics

# Test Kubernetes authentication from pod
kubectl run debug --rm -it --image=alpine -- sh
# Inside pod:
cat /var/run/secrets/kubernetes.io/serviceaccount/token
```

### 3. Common Issues and Solutions

#### Issue: VaultAuth fails to authenticate

```bash
# Check service account token
kubectl get serviceaccount webapp -n webapp -o yaml

# Verify Vault Kubernetes auth configuration
vault read auth/kubernetes/config

# Check role binding
vault read auth/kubernetes/role/webapp

# Test authentication manually
JWT=$(kubectl create token webapp -n webapp)
vault write auth/kubernetes/login role=webapp jwt=$JWT
```

#### Issue: Secrets not syncing

```bash
# Check operator logs
kubectl logs -n vault-secrets-operator-system deployment/vault-secrets-operator --tail=100

# Check VaultStaticSecret events
kubectl describe vaultstaticsecret webapp-config -n webapp

# Verify Vault path and permissions
vault kv get secret/webapp/config
vault token capabilities secret/data/webapp/config
```

#### Issue: High memory usage

```bash
# Check resource usage
kubectl top pods -n vault-secrets-operator-system

# Adjust resource limits
kubectl patch deployment vault-secrets-operator -n vault-secrets-operator-system -p '
{
  "spec": {
    "template": {
      "spec": {
        "containers": [
          {
            "name": "manager",
            "resources": {
              "limits": {
                "memory": "512Mi",
                "cpu": "500m"
              },
              "requests": {
                "memory": "256Mi",
                "cpu": "100m"
              }
            }
          }
        ]
      }
    }
  }
}'
```

---

*This comprehensive guide provides everything needed to successfully integrate Kubernetes with HashiCorp Vault using modern patterns and best practices. For specific implementation details, refer to the setup guides and examples in this documentation suite.*