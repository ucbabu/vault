# Azure AD/Entra ID SSO Setup for HCP Organization

This guide provides step-by-step instructions for configuring Single Sign-On (SSO) between Azure AD (Entra ID) and HashiCorp Cloud Platform (HCP) Organization.

## Table of Contents

1. [Prerequisites](#prerequisites)
2. [Azure AD Application Setup](#azure-ad-application-setup)
3. [HCP Organization Configuration](#hcp-organization-configuration)
4. [Group Mappings](#group-mappings)
5. [Testing and Validation](#testing-and-validation)
6. [Troubleshooting](#troubleshooting)

## Prerequisites

### Required Access
- **Azure AD Global Administrator** or **Application Administrator** role
- **HCP Organization Owner** or **Organization Admin** role
- **Domain verification** for your organization

### Required Information
- Azure AD Tenant ID
- HCP Organization ID
- Custom domain (if using custom domain instead of .onmicrosoft.com)

## Azure AD Application Setup

### Step 1: Create Enterprise Application

1. **Login to Azure Portal**:
   ```bash
   # Open Azure Portal
   open https://portal.azure.com
   ```

2. **Navigate to Azure Active Directory**:
   - Go to **Azure Active Directory** → **Enterprise applications**
   - Click **New application** → **Create your own application**
   - Name: "HashiCorp Cloud Platform"
   - Select: "Integrate any other application you don't find in the gallery"

3. **Configure Application Registration**:
   ```bash
   # Using Azure CLI
   az ad app create \
     --display-name "HashiCorp Cloud Platform" \
     --web-redirect-uris "https://auth.hashicorp.com/login/callback" \
     --sign-in-audience "AzureADMyOrg"
   ```

### Step 2: Configure OIDC Settings

1. **Set Redirect URI**:
   - **Redirect URI**: `https://auth.hashicorp.com/login/callback`
   - **Logout URL**: `https://auth.hashicorp.com/logout`

2. **Configure Token Configuration**:
   ```json
   {
     "accessTokenAcceptedVersion": 2,
     "signInAudience": "AzureADMyOrg",
     "optionalClaims": {
       "idToken": [
         {
           "name": "groups",
           "source": "user",
           "essential": false,
           "additionalProperties": ["emit_as_roles"]
         },
         {
           "name": "email",
           "source": "user",
           "essential": true
         }
       ]
     }
   }
   ```

3. **Create Client Secret**:
   ```bash
   # Generate client secret
   az ad app credential reset \
     --id {application-id} \
     --display-name "HCP SSO Secret" \
     --years 2
   ```

### Step 3: Configure API Permissions

```bash
# Grant Microsoft Graph permissions
az ad app permission add \
  --id {application-id} \
  --api 00000003-0000-0000-c000-000000000000 \
  --api-permissions e1fe6dd8-ba31-4d61-89e7-88639da4683d=Scope

# Grant admin consent
az ad app permission admin-consent --id {application-id}
```

### Step 4: Configure Groups Claims

1. **Enable Groups Claims**:
   - Go to **Token configuration** → **Add groups claim**
   - Select **Security groups**
   - Choose **Group ID** for ID tokens

2. **Create Security Groups**:
   ```bash
   # Create HCP access groups
   az ad group create --display-name "HCP-Vault-Admins" --mail-nickname "hcp-vault-admins"
   az ad group create --display-name "HCP-Vault-Operators" --mail-nickname "hcp-vault-operators"
   az ad group create --display-name "HCP-Vault-Developers" --mail-nickname "hcp-vault-developers"
   ```

## HCP Organization Configuration

### Step 1: Configure OIDC Authentication

```bash
# Using the automation script
./scripts/hcp-org-sso-setup.sh oidc \
  --name "Azure AD" \
  --org-id "your-hcp-org-id" \
  --oidc-issuer "https://login.microsoftonline.com/{tenant-id}/v2.0" \
  --oidc-client-id "{application-client-id}" \
  --oidc-secret "{application-client-secret}" \
  --group-mapping "HCP-Vault-Admins:Admin:*" \
  --group-mapping "HCP-Vault-Operators:Contributor:vault-prod,vault-staging" \
  --group-mapping "HCP-Vault-Developers:Contributor:vault-dev" \
  --jit-provisioning
```

### Step 2: Manual Configuration (Alternative)

If using HCP Console directly:

1. **Navigate to Organization Settings**:
   - Login to [HCP Console](https://portal.cloud.hashicorp.com)
   - Go to **Organization Settings** → **Authentication**

2. **Configure OIDC Provider**:
   ```json
   {
     "providerType": "oidc",
     "providerName": "Azure AD",
     "issuerUrl": "https://login.microsoftonline.com/{tenant-id}/v2.0",
     "clientId": "{application-client-id}",
     "clientSecret": "{application-client-secret}",
     "scopes": ["openid", "profile", "email", "groups"],
     "claimMappings": {
       "userId": "sub",
       "email": "email",
       "name": "name",
       "groups": "groups"
     }
   }
   ```

## Group Mappings

### Recommended Group Structure

```yaml
# Azure AD Groups → HCP Roles Mapping
groupMappings:
  # Platform Engineering - Full access
  "HCP-Platform-Admins":
    role: "Admin"
    projects: ["*"]
  
  # Vault Administrators
  "HCP-Vault-Admins":
    role: "Admin"
    projects: ["vault-production", "vault-staging"]
  
  # Vault Operators
  "HCP-Vault-Operators":
    role: "Contributor"
    projects: ["vault-production", "vault-staging"]
  
  # Vault Developers
  "HCP-Vault-Developers":
    role: "Contributor"
    projects: ["vault-development", "vault-staging"]
  
  # Security Team - Audit access
  "Security-Team":
    role: "Viewer"
    projects: ["*"]
```

### Configure Conditional Access (Optional)

```bash
# Create conditional access policy for HCP
az ad conditionalaccess policy create \
  --display-name "HCP SSO - Require MFA" \
  --state "enabled" \
  --conditions '{
    "applications": {
      "includeApplications": ["{hcp-application-id}"]
    },
    "users": {
      "includeGroups": ["HCP-Vault-Admins", "HCP-Vault-Operators"]
    }
  }' \
  --grant-controls '{
    "operator": "OR",
    "builtInControls": ["mfa"]
  }'
```

## Testing and Validation

### Step 1: Test OIDC Configuration

```bash
# Test OIDC discovery endpoint
curl -s "https://login.microsoftonline.com/{tenant-id}/v2.0/.well-known/openid_configuration" | jq .

# Validate issuer and endpoints
curl -s "https://login.microsoftonline.com/{tenant-id}/v2.0/.well-known/openid_configuration" | \
  jq '{issuer, authorization_endpoint, token_endpoint, userinfo_endpoint}'
```

### Step 2: Test Authentication Flow

1. **Access HCP SSO URL**:
   ```
   https://portal.cloud.hashicorp.com/sign-in/sso?organization_id={org-id}
   ```

2. **Verify Claims in Token**:
   - Check that `groups` claim contains Azure AD group IDs
   - Verify `email` and `name` claims are populated
   - Confirm `sub` claim is unique identifier

### Step 3: Validate Group Mappings

```bash
# Test different user scenarios
echo "Testing user access levels:"
echo "1. Admin user from HCP-Vault-Admins group"
echo "2. Operator user from HCP-Vault-Operators group"
echo "3. Developer user from HCP-Vault-Developers group"
```

## Troubleshooting

### Common Issues

#### 1. Groups Claim Not Received
**Problem**: Groups are not included in the token
**Solution**:
```bash
# Ensure groups claim is configured
az ad app update --id {app-id} --optional-claims '{
  "idToken": [
    {
      "name": "groups",
      "source": "user",
      "essential": false,
      "additionalProperties": ["emit_as_roles"]
    }
  ]
}'
```

#### 2. Redirect URI Mismatch
**Problem**: `redirect_uri_mismatch` error
**Solution**: Verify redirect URI exactly matches:
```
https://auth.hashicorp.com/login/callback
```

#### 3. Invalid Client Credentials
**Problem**: Authentication fails with invalid client
**Solution**:
```bash
# Verify client credentials
az ad app show --id {app-id} --query "appId"
az ad app credential list --id {app-id}
```

#### 4. Missing Permissions
**Problem**: Insufficient permissions error
**Solution**:
```bash
# Grant required permissions
az ad app permission add --id {app-id} \
  --api 00000003-0000-0000-c000-000000000000 \
  --api-permissions e1fe6dd8-ba31-4d61-89e7-88639da4683d=Scope

az ad app permission admin-consent --id {app-id}
```

### Diagnostic Commands

```bash
#!/bin/bash
# Azure AD SSO Diagnostics

echo "=== Azure AD SSO Diagnostics ==="

# Check tenant information
echo "1. Tenant Information:"
az account show --query "{tenantId, name}"

# Check application registration
echo "2. Application Registration:"
az ad app show --id {app-id} --query "{appId, displayName, signInAudience}"

# Test OIDC endpoints
echo "3. OIDC Discovery:"
curl -s "https://login.microsoftonline.com/{tenant-id}/v2.0/.well-known/openid_configuration" | \
  jq '{issuer, authorization_endpoint, token_endpoint}'

# Check group memberships
echo "4. User Group Memberships:"
az ad signed-in-user get-member-groups --query "value[].displayName"
```

## Next Steps

After successful Azure AD SSO setup:

1. **Configure Vault-Specific Authentication**:
   ```bash
   # Enable OIDC auth in Vault namespaces
   ./scripts/team-onboarding.sh team-alpha \
     --oidc \
     --oidc-url "https://login.microsoftonline.com/{tenant-id}/v2.0" \
     --oidc-client-id "vault-team-client" \
     --oidc-secret "vault-team-secret"
   ```

2. **Set Up Monitoring**:
   - Configure Azure AD sign-in logs
   - Set up HCP audit logging
   - Monitor authentication patterns

3. **User Training**:
   - Provide SSO login instructions
   - Document group access levels
   - Create troubleshooting guides

For detailed multi-team onboarding with Azure AD integration, see the [Multi-Team Onboarding Guide](../user-guides/08-multi-team-onboarding.md).