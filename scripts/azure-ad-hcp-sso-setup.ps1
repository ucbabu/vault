# Azure AD PowerShell Configuration Script for HCP Organization SSO
# This script provides PowerShell-based configuration for environments that prefer PowerShell

param(
    [Parameter(Mandatory=$true)]
    [string]$TenantId,
    
    [Parameter(Mandatory=$true)]
    [string]$HCPOrgId,
    
    [Parameter(Mandatory=$false)]
    [string]$AppName = "HashiCorp Cloud Platform",
    
    [Parameter(Mandatory=$false)]
    [switch]$DryRun,
    
    [Parameter(Mandatory=$false)]
    [switch]$Verbose
)

# Import required modules
Import-Module AzureAD -ErrorAction Stop
Import-Module Az.Accounts -ErrorAction Stop

# Configuration
$RedirectUri = "https://auth.hashicorp.com/login/callback"
$LogoutUrl = "https://auth.hashicorp.com/logout"

# Azure AD Groups to create
$AzureGroups = @(
    @{Name="HCP-Platform-Admins"; Description="HCP Platform Administrators"},
    @{Name="HCP-Vault-Admins"; Description="Vault Administrators"},
    @{Name="HCP-Vault-Operators"; Description="Vault Operators"},
    @{Name="HCP-Vault-Developers"; Description="Vault Developers"},
    @{Name="HCP-Security-Team"; Description="Security Team - Audit Access"}
)

# Functions
function Write-Log {
    param([string]$Message, [string]$Level = "Info")
    $timestamp = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
    $color = switch($Level) {
        "Error" { "Red" }
        "Warning" { "Yellow" }
        "Success" { "Green" }
        default { "White" }
    }
    Write-Host "[$timestamp] [$Level] $Message" -ForegroundColor $color
}

function Test-Prerequisites {
    Write-Log "Checking prerequisites..." "Info"
    
    # Check Azure AD connection
    try {
        $context = Get-AzureADCurrentSessionInfo -ErrorAction Stop
        Write-Log "Connected to Azure AD tenant: $($context.TenantId)" "Success"
        
        if ($context.TenantId -ne $TenantId) {
            Write-Log "Warning: Connected to different tenant ($($context.TenantId)) than specified ($TenantId)" "Warning"
        }
    }
    catch {
        Write-Log "Not connected to Azure AD. Please run Connect-AzureAD first." "Error"
        throw
    }
    
    # Check permissions
    try {
        $user = Get-AzureADUser -Top 1 -ErrorAction Stop
        Write-Log "Azure AD read access confirmed" "Success"
    }
    catch {
        Write-Log "Insufficient Azure AD permissions" "Error"
        throw
    }
}

function New-HCPApplication {
    Write-Log "Creating Azure AD application: $AppName" "Info"
    
    if ($DryRun) {
        Write-Log "DRY RUN: Would create application '$AppName'" "Info"
        return @{AppId = "dry-run-app-id"; ObjectId = "dry-run-object-id"}
    }
    
    # Check if application exists
    $existingApp = Get-AzureADApplication -Filter "displayName eq '$AppName'" -ErrorAction SilentlyContinue
    
    if ($existingApp) {
        Write-Log "Application '$AppName' already exists with ID: $($existingApp.AppId)" "Warning"
        return @{AppId = $existingApp.AppId; ObjectId = $existingApp.ObjectId}
    }
    
    # Create application
    $appParams = @{
        DisplayName = $AppName
        ReplyUrls = @($RedirectUri)
        LogoutUrl = $LogoutUrl
        AvailableToOtherTenants = $false
    }
    
    $app = New-AzureADApplication @appParams
    Write-Log "Created application with ID: $($app.AppId)" "Success"
    
    # Configure optional claims
    $optionalClaims = @{
        IdToken = @(
            @{
                Name = "groups"
                Source = "user"
                Essential = $false
                AdditionalProperties = @("emit_as_roles")
            },
            @{
                Name = "email"
                Source = "user"
                Essential = $true
            }
        )
    }
    
    Set-AzureADApplication -ObjectId $app.ObjectId -OptionalClaims $optionalClaims
    Write-Log "Configured optional claims" "Success"
    
    # Create service principal
    $sp = New-AzureADServicePrincipal -AppId $app.AppId
    Write-Log "Created service principal with ID: $($sp.ObjectId)" "Success"
    
    return @{AppId = $app.AppId; ObjectId = $app.ObjectId}
}

function New-HCPGroups {
    Write-Log "Creating Azure AD security groups" "Info"
    
    foreach ($group in $AzureGroups) {
        if ($DryRun) {
            Write-Log "DRY RUN: Would create group '$($group.Name)'" "Info"
            continue
        }
        
        # Check if group exists
        $existingGroup = Get-AzureADGroup -Filter "displayName eq '$($group.Name)'" -ErrorAction SilentlyContinue
        
        if ($existingGroup) {
            Write-Log "Group '$($group.Name)' already exists with ID: $($existingGroup.ObjectId)" "Info"
            continue
        }
        
        # Create group
        $groupParams = @{
            DisplayName = $group.Name
            Description = $group.Description
            SecurityEnabled = $true
            MailEnabled = $false
        }
        
        $newGroup = New-AzureADGroup @groupParams
        Write-Log "Created group '$($group.Name)' with ID: $($newGroup.ObjectId)" "Success"
    }
}

function New-ClientSecret {
    param([string]$AppObjectId)
    
    Write-Log "Creating client secret" "Info"
    
    if ($DryRun) {
        Write-Log "DRY RUN: Would create client secret" "Info"
        return "dry-run-client-secret"
    }
    
    $passwordCredential = @{
        StartDate = Get-Date
        EndDate = (Get-Date).AddYears(2)
        DisplayName = "HCP SSO Secret"
    }
    
    $secret = New-AzureADApplicationPasswordCredential -ObjectId $AppObjectId @passwordCredential
    Write-Log "Created client secret (expires: $($secret.EndDate))" "Success"
    
    return $secret.Value
}

function Set-APIPermissions {
    param([string]$AppObjectId)
    
    Write-Log "Configuring API permissions" "Info"
    
    if ($DryRun) {
        Write-Log "DRY RUN: Would configure API permissions" "Info"
        return
    }
    
    # Microsoft Graph API permissions
    $graphAPI = Get-AzureADServicePrincipal -Filter "appId eq '00000003-0000-0000-c000-000000000000'"
    
    # User.Read permission
    $userReadPermission = $graphAPI.Oauth2Permissions | Where-Object {$_.Value -eq "User.Read"}
    
    $requiredResourceAccess = @{
        ResourceAppId = "00000003-0000-0000-c000-000000000000"
        ResourceAccess = @(
            @{
                Id = $userReadPermission.Id
                Type = "Scope"
            }
        )
    }
    
    Set-AzureADApplication -ObjectId $AppObjectId -RequiredResourceAccess $requiredResourceAccess
    Write-Log "Configured Microsoft Graph permissions" "Success"
}

function Test-Configuration {
    param([string]$AppId)
    
    Write-Log "Testing configuration" "Info"
    
    # Test OIDC discovery endpoint
    $discoveryUrl = "https://login.microsoftonline.com/$TenantId/v2.0/.well-known/openid_configuration"
    
    try {
        $response = Invoke-RestMethod -Uri $discoveryUrl -Method Get
        Write-Log "OIDC discovery endpoint accessible" "Success"
        Write-Log "Issuer: $($response.issuer)" "Info"
    }
    catch {
        Write-Log "OIDC discovery endpoint not accessible: $($_.Exception.Message)" "Error"
    }
    
    # Validate groups
    Write-Log "Validating Azure AD groups:" "Info"
    foreach ($group in $AzureGroups) {
        $existingGroup = Get-AzureADGroup -Filter "displayName eq '$($group.Name)'" -ErrorAction SilentlyContinue
        if ($existingGroup) {
            Write-Log "  ✓ $($group.Name) (ID: $($existingGroup.ObjectId))" "Success"
        } else {
            Write-Log "  ✗ $($group.Name) (not found)" "Warning"
        }
    }
}

function Write-Summary {
    param(
        [string]$AppId,
        [string]$ClientSecret
    )
    
    Write-Host ""
    Write-Host "===============================================" -ForegroundColor Green
    Write-Host "  Azure AD HCP Organization SSO Setup        " -ForegroundColor Green
    Write-Host "===============================================" -ForegroundColor Green
    Write-Host ""
    
    Write-Host "Configuration Details:" -ForegroundColor Blue
    Write-Host "- HCP Organization ID: $HCPOrgId"
    Write-Host "- Azure Tenant ID: $TenantId"
    Write-Host "- Application Name: $AppName"
    Write-Host "- Application Client ID: $AppId"
    Write-Host ""
    
    Write-Host "OIDC Configuration:" -ForegroundColor Blue
    Write-Host "- Issuer URL: https://login.microsoftonline.com/$TenantId/v2.0"
    Write-Host "- Client ID: $AppId"
    Write-Host "- Client Secret: [HIDDEN]"
    Write-Host "- Redirect URI: $RedirectUri"
    Write-Host ""
    
    Write-Host "Next Steps:" -ForegroundColor Blue
    Write-Host "1. Configure HCP Organization SSO using the values above"
    Write-Host "2. Test SSO login at: https://portal.cloud.hashicorp.com/sign-in/sso?organization_id=$HCPOrgId"
    Write-Host "3. Add users to appropriate Azure AD groups"
    Write-Host "4. Configure Vault namespace authentication"
    Write-Host ""
    
    if (-not $DryRun) {
        Write-Host "HCP SSO Configuration Command:" -ForegroundColor Blue
        Write-Host "./scripts/hcp-org-sso-setup.sh oidc \"
        Write-Host "  --name \"Azure AD\" \"
        Write-Host "  --org-id \"$HCPOrgId\" \"
        Write-Host "  --oidc-issuer \"https://login.microsoftonline.com/$TenantId/v2.0\" \"
        Write-Host "  --oidc-client-id \"$AppId\" \"
        Write-Host "  --oidc-secret \"$ClientSecret\""
        Write-Host ""
    }
    
    if ($DryRun) {
        Write-Host "Note: This was a dry run. No actual changes were made." -ForegroundColor Yellow
    }
}

# Main execution
try {
    Write-Log "Starting Azure AD HCP Organization SSO setup" "Info"
    Write-Log "Tenant ID: $TenantId" "Info"
    Write-Log "HCP Org ID: $HCPOrgId" "Info"
    
    if ($DryRun) {
        Write-Log "Running in DRY RUN mode - no changes will be made" "Warning"
    }
    
    Test-Prerequisites
    
    $app = New-HCPApplication
    New-HCPGroups
    
    $clientSecret = ""
    if (-not $DryRun) {
        $clientSecret = New-ClientSecret -AppObjectId $app.ObjectId
        Set-APIPermissions -AppObjectId $app.ObjectId
    }
    
    Test-Configuration -AppId $app.AppId
    Write-Summary -AppId $app.AppId -ClientSecret $clientSecret
    
    Write-Log "Azure AD HCP Organization SSO setup completed successfully!" "Success"
}
catch {
    Write-Log "Setup failed: $($_.Exception.Message)" "Error"
    throw
}