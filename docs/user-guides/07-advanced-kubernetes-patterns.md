# Advanced Kubernetes Secret Management Patterns with Vault

## Table of Contents

1. [Vault Agent Injection](#vault-agent-injection)
2. [Secrets Store CSI Driver](#secrets-store-csi-driver)
3. [Multi-Namespace Patterns](#multi-namespace-patterns)
4. [GitOps Integration](#gitops-integration)
5. [Performance Optimization](#performance-optimization)
6. [Security Hardening](#security-hardening)

## Vault Agent Injection

The Vault Agent Injector provides an alternative to the Vault Secrets Operator, using sidecar and init container patterns.

### 1. Install Vault Agent Injector

```bash
# Add HashiCorp Helm repository
helm repo add hashicorp https://helm.releases.hashicorp.com
helm repo update

# Install Vault Agent Injector
helm install vault hashicorp/vault \
    --namespace vault \
    --create-namespace \
    --set "injector.enabled=true" \
    --set "injector.externalVaultAddr=https://vault.example.com:8200" \
    --set "server.enabled=false"
```

### 2. Init Container Pattern

```yaml
# webapp-init-container.yaml
apiVersion: apps/v1
kind: Deployment
metadata:
  name: webapp-init
  namespace: webapp
spec:
  replicas: 1
  template:
    metadata:
      annotations:
        vault.hashicorp.com/agent-inject: "true"
        vault.hashicorp.com/agent-pre-populate-only: "true"
        vault.hashicorp.com/role: "webapp"
        vault.hashicorp.com/auth-path: "auth/kubernetes"
        
        # Inject database configuration
        vault.hashicorp.com/agent-inject-secret-database: "secret/webapp/database"
        vault.hashicorp.com/agent-inject-template-database: |
          {{- with secret "secret/webapp/database" -}}
          export DB_HOST="{{ .Data.data.host }}"
          export DB_USER="{{ .Data.data.username }}"
          export DB_PASS="{{ .Data.data.password }}"
          export DB_NAME="{{ .Data.data.database }}"
          {{- end }}
          
        # Inject API configuration
        vault.hashicorp.com/agent-inject-secret-config: "secret/webapp/config"
        vault.hashicorp.com/agent-inject-template-config: |
          {{- with secret "secret/webapp/config" -}}
          export API_KEY="{{ .Data.data.api_key }}"
          export DEBUG="{{ .Data.data.debug }}"
          export LOG_LEVEL="{{ .Data.data.log_level }}"
          {{- end }}
          
        # Agent configuration
        vault.hashicorp.com/agent-limits-cpu: "100m"
        vault.hashicorp.com/agent-limits-mem: "128Mi"
        vault.hashicorp.com/agent-requests-cpu: "50m"
        vault.hashicorp.com/agent-requests-mem: "64Mi"
        
    spec:
      serviceAccountName: webapp
      containers:
      - name: webapp
        image: webapp:latest
        command: ["/bin/sh"]
        args:
        - -c
        - |
          # Source Vault secrets
          source /vault/secrets/database
          source /vault/secrets/config
          
          # Start application
          exec /app/webapp
          
        resources:
          limits:
            cpu: 500m
            memory: 512Mi
          requests:
            cpu: 200m
            memory: 256Mi
```

### 3. Sidecar Pattern

```yaml
# webapp-sidecar.yaml
apiVersion: apps/v1
kind: Deployment
metadata:
  name: webapp-sidecar
  namespace: webapp
spec:
  template:
    metadata:
      annotations:
        vault.hashicorp.com/agent-inject: "true"
        vault.hashicorp.com/agent-pre-populate: "false"
        vault.hashicorp.com/role: "webapp"
        
        # Dynamic database credentials
        vault.hashicorp.com/agent-inject-secret-db: "database/creds/webapp"
        vault.hashicorp.com/agent-inject-template-db: |
          {{- with secret "database/creds/webapp" -}}
          {
            "username": "{{ .Data.username }}",
            "password": "{{ .Data.password }}",
            "ttl": {{ .LeaseDuration }}
          }
          {{- end }}
          
        # Azure credentials with auto-renewal
        vault.hashicorp.com/agent-inject-secret-azure: "azure/creds/webapp"
        vault.hashicorp.com/agent-inject-template-azure: |
          {{- with secret "azure/creds/webapp" -}}
          {
            "client_id": "{{ .Data.client_id }}",
            "client_secret": "{{ .Data.client_secret }}",
            "lease_id": "{{ .LeaseID }}",
            "renewable": {{ .Renewable }},
            "ttl": {{ .LeaseDuration }}
          }
          {{- end }}
          
        # Continuous renewal
        vault.hashicorp.com/agent-cache-enable: "true"
        vault.hashicorp.com/agent-cache-use-auto-auth-token: "true"
        
    spec:
      serviceAccountName: webapp
      containers:
      - name: webapp
        image: webapp:latest
        env:
        - name: VAULT_SECRETS_PATH
          value: "/vault/secrets"
          
        # Monitor secret files for changes
        command: ["/bin/sh"]
        args:
        - -c
        - |
          # Start background secret monitor
          while true; do
            if [ -f /vault/secrets/db ]; then
              export $(cat /vault/secrets/db | jq -r 'to_entries[] | "\(.key)=\(.value)"')
            fi
            
            if [ -f /vault/secrets/azure ]; then
              export $(cat /vault/secrets/azure | jq -r 'to_entries[] | "\(.key)=\(.value)"')
            fi
            
            sleep 30
          done &
          
          # Start main application
          exec /app/webapp
          
        volumeMounts:
        - name: vault-secrets
          mountPath: /vault/secrets
          readOnly: true
          
      volumes:
      - name: vault-secrets
        emptyDir: {}
```

## Secrets Store CSI Driver

The Secrets Store CSI Driver mounts secrets as volumes in the filesystem.

### 1. Install Secrets Store CSI Driver

```bash
# Install the CSI driver
helm repo add secrets-store-csi-driver https://kubernetes-sigs.github.io/secrets-store-csi-driver/charts
helm install csi-secrets-store secrets-store-csi-driver/secrets-store-csi-driver \
    --namespace kube-system \
    --set enableSecretRotation=true \
    --set rotationPollInterval=30s

# Install Vault Provider
kubectl apply -f https://raw.githubusercontent.com/hashicorp/vault-csi-provider/main/deployment/vault-csi-provider.yaml
```

### 2. Create SecretProviderClass

```yaml
# secret-provider-class.yaml
apiVersion: secrets-store.csi.x-k8s.io/v1
kind: SecretProviderClass
metadata:
  name: webapp-secrets
  namespace: webapp
spec:
  provider: vault
  parameters:
    # Vault connection
    vaultAddress: "https://vault.example.com:8200"
    vaultNamespace: ""
    roleName: "webapp"
    
    # Objects to retrieve
    objects: |
      - objectName: "database-config"
        secretPath: "secret/data/webapp/database"
        secretKey: "config"
        method: "GET"
        
      - objectName: "api-key"
        secretPath: "secret/data/webapp/config"
        secretKey: "api_key"
        method: "GET"
        
      - objectName: "db-username"
        secretPath: "database/creds/webapp"
        secretKey: "username"
        method: "GET"
        
      - objectName: "db-password"
        secretPath: "database/creds/webapp" 
        secretKey: "password"
        method: "GET"
        
  # Sync to Kubernetes secret
  secretObjects:
  - secretName: webapp-csi-secret
    type: Opaque
    data:
    - objectName: database-config
      key: database-config
    - objectName: api-key
      key: api-key
    - objectName: db-username
      key: db-username
    - objectName: db-password
      key: db-password
```

### 3. Use CSI Volumes

```yaml
# webapp-csi.yaml
apiVersion: apps/v1
kind: Deployment
metadata:
  name: webapp-csi
  namespace: webapp
spec:
  template:
    metadata:
      labels:
        app: webapp-csi
    spec:
      serviceAccountName: webapp
      containers:
      - name: webapp
        image: webapp:latest
        env:
        - name: DATABASE_CONFIG_FILE
          value: "/mnt/secrets/database-config"
        - name: API_KEY_FILE
          value: "/mnt/secrets/api-key"
          
        volumeMounts:
        - name: secrets-store
          mountPath: /mnt/secrets
          readOnly: true
          
        # Alternative: use synced Kubernetes secret
        envFrom:
        - secretRef:
            name: webapp-csi-secret
            
      volumes:
      - name: secrets-store
        csi:
          driver: secrets-store.csi.k8s.io
          readOnly: true
          volumeAttributes:
            secretProviderClass: webapp-secrets
```

## Multi-Namespace Patterns

### 1. Namespace Isolation Strategy

```yaml
# namespace-setup.yaml
# Production namespace
apiVersion: v1
kind: Namespace
metadata:
  name: webapp-production
  labels:
    environment: production
    vault-policy: webapp-prod
---
# Staging namespace
apiVersion: v1
kind: Namespace
metadata:
  name: webapp-staging
  labels:
    environment: staging
    vault-policy: webapp-staging
---
# Development namespace
apiVersion: v1
kind: Namespace
metadata:
  name: webapp-development
  labels:
    environment: development
    vault-policy: webapp-dev
```

### 2. Environment-Specific VaultAuth

```yaml
# Production VaultAuth
apiVersion: secrets.hashicorp.com/v1beta1
kind: VaultAuth
metadata:
  name: webapp-prod-auth
  namespace: webapp-production
spec:
  vaultConnectionRef: vault-secrets-operator-system/default
  method: kubernetes
  mount: kubernetes
  kubernetes:
    role: webapp-prod
    serviceAccount: webapp
    audiences: ["vault"]
---
# Staging VaultAuth  
apiVersion: secrets.hashicorp.com/v1beta1
kind: VaultAuth
metadata:
  name: webapp-staging-auth
  namespace: webapp-staging
spec:
  vaultConnectionRef: vault-secrets-operator-system/default
  method: kubernetes
  mount: kubernetes
  kubernetes:
    role: webapp-staging
    serviceAccount: webapp
    audiences: ["vault"]
```

### 3. Cross-Namespace Secret Sharing

```yaml
# Shared platform secrets
apiVersion: secrets.hashicorp.com/v1beta1
kind: VaultStaticSecret
metadata:
  name: platform-config
  namespace: platform
spec:
  vaultAuthRef: platform-auth
  mount: secret
  type: kv-v2
  path: platform/shared-config
  destination:
    name: platform-config
    create: true
    
  # Destination transformation for sharing
  destinationTransformation:
    excludes: ["sensitive_key"]
    includes: ["public_config", "endpoints"]
    
    # Template for shared data
    templates:
      shared-config: |
        api_endpoint: {{ .Secrets.api_endpoint }}
        region: {{ .Secrets.region }}
        environment: {{ .Secrets.environment }}
        
  # Sync to multiple namespaces
  syncConfig:
    instantUpdates: true
```

## GitOps Integration

### 1. ArgoCD Integration

```yaml
# argocd-vault-plugin.yaml
apiVersion: v1
kind: ConfigMap
metadata:
  name: cmp-plugin
  namespace: argocd
data:
  plugin.yaml: |
    apiVersion: argoproj.io/v1alpha1
    kind: ConfigManagementPlugin
    metadata:
      name: vault-plugin
    spec:
      version: v1.0
      generate:
        command: [sh, -c]
        args:
        - |
          # Authenticate to Vault
          export VAULT_TOKEN=$(vault write -field=token auth/kubernetes/login role=argocd jwt=$(cat /var/run/secrets/kubernetes.io/serviceaccount/token))
          
          # Process templates with Vault secrets
          for file in *.yaml; do
            envsubst < $file | vault kv get -format=json secret/argocd/config | jq -r '.data.data | to_entries[] | "export \(.key)=\(.value)"' | while read line; do
              eval $line
              envsubst < $file
            done
          done
```

### 2. Flux Integration

```yaml
# flux-vault-integration.yaml
apiVersion: source.toolkit.fluxcd.io/v1beta2
kind: GitRepository
metadata:
  name: vault-configs
  namespace: flux-system
spec:
  interval: 1m
  url: https://github.com/company/vault-configs
  ref:
    branch: main
  secretRef:
    name: git-credentials
---
apiVersion: kustomize.toolkit.fluxcd.io/v1beta2
kind: Kustomization
metadata:
  name: vault-secrets
  namespace: flux-system
spec:
  interval: 10m
  sourceRef:
    kind: GitRepository
    name: vault-configs
  path: "./environments/production"
  prune: true
  
  # Post-build substitution with Vault
  postBuild:
    substitute:
      VAULT_ROLE: "flux-prod"
      NAMESPACE: "production"
    substituteFrom:
    - kind: Secret
      name: vault-substitutions
```

## Performance Optimization

### 1. Caching Strategies

```yaml
# High-performance caching configuration
apiVersion: secrets.hashicorp.com/v1beta1
kind: VaultAuth
metadata:
  name: high-perf-auth
  namespace: webapp
spec:
  vaultConnectionRef: vault-secrets-operator-system/default
  method: kubernetes
  mount: kubernetes
  kubernetes:
    role: webapp
    serviceAccount: webapp
    
  # Performance optimizations
  cacheSize: 1000
  defaultLeaseTTL: "1h"
  maxLeaseTTL: "4h"
  
  # Connection pooling
  vaultConnectionRef: vault-secrets-operator-system/high-perf-connection
---
apiVersion: secrets.hashicorp.com/v1beta1
kind: VaultConnection
metadata:
  name: high-perf-connection
  namespace: vault-secrets-operator-system
spec:
  address: https://vault.example.com:8200
  
  # Connection pooling
  maxRetries: 3
  timeout: 30s
  
  # TLS optimization
  tlsConfig:
    insecureSkipTLSVerify: false
    minVersion: "1.2"
    cipherSuites:
      - "TLS_ECDHE_RSA_WITH_AES_256_GCM_SHA384"
      - "TLS_ECDHE_RSA_WITH_AES_128_GCM_SHA256"
```

### 2. Resource Optimization

```yaml
# Resource-optimized operator deployment
apiVersion: apps/v1
kind: Deployment
metadata:
  name: vault-secrets-operator-controller-manager
  namespace: vault-secrets-operator-system
spec:
  template:
    spec:
      containers:
      - name: manager
        resources:
          limits:
            cpu: 500m
            memory: 512Mi
          requests:
            cpu: 100m
            memory: 128Mi
            
        # JVM optimization for better performance
        env:
        - name: JAVA_OPTS
          value: "-Xmx256m -Xms128m -XX:+UseG1GC"
          
        # Concurrent processing
        - name: MAX_CONCURRENT_RECONCILES
          value: "10"
          
        # Metrics and profiling
        - name: ENABLE_PROFILING
          value: "true"
```

## Security Hardening

### 1. Network Policies

```yaml
# Restrict network access for Vault integration
apiVersion: networking.k8s.io/v1
kind: NetworkPolicy
metadata:
  name: vault-secrets-operator
  namespace: vault-secrets-operator-system
spec:
  podSelector:
    matchLabels:
      app.kubernetes.io/name: vault-secrets-operator
  policyTypes:
  - Ingress
  - Egress
  
  # Allow ingress for metrics
  ingress:
  - from:
    - namespaceSelector:
        matchLabels:
          name: monitoring
    ports:
    - protocol: TCP
      port: 8080
      
  # Restrict egress
  egress:
  # Allow Vault access
  - to: []
    ports:
    - protocol: TCP
      port: 8200
    - protocol: TCP
      port: 443
      
  # Allow Kubernetes API
  - to:
    - namespaceSelector:
        matchLabels:
          name: kube-system
    ports:
    - protocol: TCP
      port: 443
      
  # Allow DNS
  - to:
    - namespaceSelector:
        matchLabels:
          name: kube-system
    ports:
    - protocol: UDP
      port: 53
```

### 2. Pod Security Standards

```yaml
# Pod Security Policy for Vault workloads
apiVersion: v1
kind: Pod
metadata:
  name: webapp
  namespace: webapp
  annotations:
    # Pod security standards
    pod-security.kubernetes.io/enforce: restricted
    pod-security.kubernetes.io/audit: restricted
    pod-security.kubernetes.io/warn: restricted
spec:
  serviceAccountName: webapp
  
  # Security context
  securityContext:
    runAsNonRoot: true
    runAsUser: 1000
    runAsGroup: 1000
    fsGroup: 1000
    seccompProfile:
      type: RuntimeDefault
      
  containers:
  - name: webapp
    image: webapp:latest
    
    # Container security context
    securityContext:
      allowPrivilegeEscalation: false
      readOnlyRootFilesystem: true
      runAsNonRoot: true
      runAsUser: 1000
      capabilities:
        drop:
        - ALL
        
    # Resource limits for security
    resources:
      limits:
        cpu: 500m
        memory: 512Mi
        ephemeral-storage: 1Gi
      requests:
        cpu: 100m
        memory: 128Mi
        ephemeral-storage: 100Mi
```

### 3. Admission Controllers

```yaml
# OPA Gatekeeper policy for Vault integration
apiVersion: templates.gatekeeper.sh/v1beta1
kind: ConstraintTemplate
metadata:
  name: vaultsecureconfig
spec:
  crd:
    spec:
      names:
        kind: VaultSecureConfig
      validation:
        type: object
        properties:
          requiredAnnotations:
            type: array
            items:
              type: string
              
  targets:
  - target: admission.k8s.gatekeeper.sh
    rego: |
      package vaultsecureconfig
      
      violation[{"msg": msg}] {
        input.review.object.kind == "VaultStaticSecret"
        not input.review.object.spec.destination.create
        msg := "VaultStaticSecret must create Kubernetes secrets"
      }
      
      violation[{"msg": msg}] {
        input.review.object.kind == "VaultAuth"
        not input.review.object.spec.kubernetes.serviceAccount
        msg := "VaultAuth must specify serviceAccount"
      }
---
apiVersion: config.gatekeeper.sh/v1alpha1
kind: VaultSecureConfig
metadata:
  name: vault-security-policy
spec:
  match:
  - excludedNamespaces: ["kube-system", "vault-secrets-operator-system"]
    kinds:
    - apiGroups: ["secrets.hashicorp.com"]
      kinds: ["VaultAuth", "VaultStaticSecret", "VaultDynamicSecret"]
```

---

*This advanced guide provides enterprise-ready patterns for Kubernetes-Vault integration, covering performance, security, and operational excellence. Use these patterns to build robust, scalable secret management solutions.*