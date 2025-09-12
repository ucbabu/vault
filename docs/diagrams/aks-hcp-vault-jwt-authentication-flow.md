# AKS to HCP Vault JWT Authentication Flow

## High-Level Architecture Diagram

```mermaid
graph TB
    subgraph "Azure Kubernetes Service (AKS)"
        subgraph "Application Namespace"
            App[Application Pod]
            SA[ServiceAccount with JWT]
        end
        
        subgraph "vault-secrets-operator-system"
            VSO[Vault Secrets Operator]
            AuthSA[vault-auth ServiceAccount]
        end
        
        subgraph "Kubernetes API Server"
            TokenReview[TokenReview API]
            RBAC[RBAC Authorization]
        end
    end
    
    subgraph "HashiCorp Cloud Platform"
        HCPVault[HCP Vault]
        subgraph "Vault Auth Methods"
            K8sAuth[Kubernetes Auth Method]
            Policies[Vault Policies]
        end
    end

    %% Authentication Flow
    App -->|1. Request Secret| VSO
    VSO -->|2. Use ServiceAccount JWT| SA
    VSO -->|3. Authenticate with JWT| HCPVault
    HCPVault -->|4. Validate JWT via TokenReview| TokenReview
    TokenReview -->|5. Validate Token Claims| RBAC
    RBAC -->|6. Return Validation Result| HCPVault
    HCPVault -->|7. Check Policies & Roles| K8sAuth
    K8sAuth -->|8. Return Vault Token| VSO
    VSO -->|9. Fetch Secret Data| HCPVault
    HCPVault -->|10. Return Secret| VSO
    VSO -->|11. Create K8s Secret| App

    %% Configuration Dependencies
    AuthSA -.->|Token Reviewer JWT| K8sAuth
    SA -.->|Bound to Role| K8sAuth
    Policies -.->|Authorize Access| HCPVault

    style HCPVault fill:#663399,color:#fff
    style VSO fill:#326ce5,color:#fff
    style App fill:#00d4aa,color:#000
    style TokenReview fill:#ff6b6b,color:#fff
```

## JWT Authentication Flow Details

### Step-by-Step Process

1. **Application Request**: Application pod requests a secret through VSO (via CRDs like VaultStaticSecret)

2. **ServiceAccount JWT**: VSO uses the pod's ServiceAccount JWT token for authentication

3. **Vault Authentication**: VSO sends authentication request to HCP Vault's Kubernetes auth endpoint

4. **Token Validation**: HCP Vault forwards the JWT to Kubernetes TokenReview API for validation

5. **Claims Verification**: Kubernetes API server validates the JWT signature and returns token claims

6. **Policy Check**: HCP Vault checks if the ServiceAccount is authorized based on configured roles

7. **Vault Token**: Upon successful authentication, HCP Vault returns a time-limited Vault token

8. **Secret Retrieval**: VSO uses the Vault token to fetch the requested secret data

9. **Kubernetes Secret**: VSO creates a native Kubernetes Secret with the retrieved data

10. **Application Access**: Application pod consumes the secret via mounted volumes or environment variables

## Key Security Components

### Kubernetes Side
- **ServiceAccount JWT**: Cryptographically signed tokens with claims (namespace, service account, expiration)
- **TokenReview API**: Kubernetes endpoint for validating JWT tokens
- **RBAC**: Controls which service accounts can perform token reviews
- **vault-auth ServiceAccount**: Special account with `system:auth-delegator` role for token validation

### HCP Vault Side
- **Kubernetes Auth Method**: Validates JWTs against Kubernetes API
- **Roles**: Bind specific ServiceAccounts/namespaces to Vault policies
- **Policies**: Define what secrets and operations are allowed
- **TLS Verification**: All communication encrypted and certificate-verified

## Network Connectivity Requirements

```mermaid
graph LR
    subgraph "AKS Cluster"
        VSO[Vault Secrets Operator]
    end
    
    subgraph "Internet/Azure Backbone"
        Network[Encrypted Connection]
    end
    
    subgraph "HashiCorp Cloud"
        HCP[HCP Vault]
    end
    
    VSO -->|HTTPS/TLS 1.3| Network
    Network -->|Port 8200| HCP
    
    HCP -->|TokenReview API| Network
    Network -->|HTTPS to K8s API| VSO
```

### Connectivity Details
- **Outbound from AKS**: HTTPS/TLS to HCP Vault (typically port 8200)
- **Inbound to AKS**: HCP Vault calls Kubernetes TokenReview API (port 6443/443)
- **Network Security**: All traffic encrypted, certificate validation required
- **No Static Credentials**: Only cryptographically signed JWTs used for authentication

## Configuration Summary

### AKS Configuration
```yaml
# ServiceAccount for applications
apiVersion: v1
kind: ServiceAccount
metadata:
  name: webapp
  namespace: production

# ServiceAccount for token validation
apiVersion: v1
kind: ServiceAccount
metadata:
  name: vault-auth
  namespace: vault-secrets-operator-system
```

### HCP Vault Configuration
```bash
# Kubernetes auth method configuration
vault write auth/kubernetes/config \
    token_reviewer_jwt="$reviewer_jwt" \
    kubernetes_host="https://your-aks-cluster.hcp.azure.com" \
    kubernetes_ca_cert="$k8s_ca_cert" \
    issuer="https://kubernetes.default.svc.cluster.local"

# Role binding ServiceAccount to policies
vault write auth/kubernetes/role/webapp \
    bound_service_account_names=webapp \
    bound_service_account_namespaces=production \
    policies=webapp-policy \
    ttl=1h
```

This architecture ensures secure, auditable, and dynamic secret access without storing long-lived credentials in your AKS cluster.