#Requires -Version 5.1
<#
.SYNOPSIS
    Adobe Enterprise Automation PowerShell Module

.DESCRIPTION
    Comprehensive module for Adobe Creative Cloud enterprise automation including
    user provisioning, license management, reporting, and optimization.

.NOTES
    Version: 2.0.0
    Author: Enterprise Automation Team
#>

# Module Variables
$script:AdobeAPIConnection = $null
$script:ModuleRoot = $PSScriptRoot
$script:ConfigPath = Join-Path $ModuleRoot "Config"
$script:TemplatePath = Join-Path $ModuleRoot "Templates"

# Import nested modules
$NestedModules = @(
    "Authentication",
    "UserManagement",
    "LicenseManagement",
    "Reporting",
    "Utilities"
)

foreach ($Module in $NestedModules) {
    $ModulePath = Join-Path $ModuleRoot "Modules\$Module.psm1"
    if (Test-Path $ModulePath) {
        Import-Module $ModulePath -Force -Scope Global
    }
}

#region Connection Management

function Connect-AdobeAPI {
    <#
    .SYNOPSIS
        Establishes connection to Adobe User Management API

    .DESCRIPTION
        Authenticates and creates a persistent connection to Adobe APIs using JWT authentication

    .PARAMETER ConfigPath
        Path to configuration file containing Adobe API credentials

    .PARAMETER OrgId
        Adobe Organization ID

    .PARAMETER ClientId
        Adobe API Client ID

    .PARAMETER ClientSecret
        Adobe API Client Secret (SecureString)

    .PARAMETER TechnicalAccountId
        Adobe Technical Account ID

    .PARAMETER PrivateKeyPath
        Path to private key file for JWT signing

    .EXAMPLE
        Connect-AdobeAPI -ConfigPath "C:\Config\adobe.json"

    .EXAMPLE
        Connect-AdobeAPI -OrgId "12345@AdobeOrg" -ClientId "abc123" -PrivateKeyPath "C:\Keys\private.key"
    #>
    [CmdletBinding(DefaultParameterSetName = 'Config')]
    param(
        [Parameter(ParameterSetName = 'Config', Mandatory)]
        [ValidateScript({ Test-Path $_ })]
        [string]$ConfigPath,

        [Parameter(ParameterSetName = 'Manual', Mandatory)]
        [string]$OrgId,

        [Parameter(ParameterSetName = 'Manual', Mandatory)]
        [string]$ClientId,

        [Parameter(ParameterSetName = 'Manual', Mandatory)]
        [SecureString]$ClientSecret,

        [Parameter(ParameterSetName = 'Manual', Mandatory)]
        [string]$TechnicalAccountId,

        [Parameter(ParameterSetName = 'Manual', Mandatory)]
        [ValidateScript({ Test-Path $_ })]
        [string]$PrivateKeyPath
    )

    begin {
        Write-Verbose "Initializing Adobe API connection..."
    }

    process {
        try {
            # Load configuration
            if ($PSCmdlet.ParameterSetName -eq 'Config') {
                $config = Get-Content $ConfigPath | ConvertFrom-Json
                $OrgId = $config.OrgId
                $ClientId = $config.ClientId
                $ClientSecret = ConvertTo-SecureString $config.ClientSecret -AsPlainText -Force
                $TechnicalAccountId = $config.TechnicalAccountId
                $PrivateKeyPath = $config.PrivateKeyPath
            }

            # Create JWT token
            Write-Verbose "Generating JWT token..."
            $jwt = New-AdobeJWT -OrgId $OrgId `
                               -ClientId $ClientId `
                               -TechnicalAccountId $TechnicalAccountId `
                               -PrivateKeyPath $PrivateKeyPath

            # Exchange JWT for access token
            Write-Verbose "Exchanging JWT for access token..."
            $tokenResponse = Get-AdobeAccessToken -JWT $jwt `
                                                 -ClientId $ClientId `
                                                 -ClientSecret $ClientSecret

            # Store connection
            $script:AdobeAPIConnection = @{
                OrgId = $OrgId
                ClientId = $ClientId
                AccessToken = $tokenResponse.access_token
                TokenExpiry = (Get-Date).AddSeconds($tokenResponse.expires_in)
                BaseUrl = "https://usermanagement.adobe.io"
                Connected = $true
                ConnectedAt = Get-Date
            }

            Write-Host "Successfully connected to Adobe API for organization: $OrgId" -ForegroundColor Green
            return $script:AdobeAPIConnection
        }
        catch {
            Write-Error "Failed to connect to Adobe API: $_"
            throw
        }
    }
}

function Disconnect-AdobeAPI {
    <#
    .SYNOPSIS
        Disconnects from Adobe API

    .DESCRIPTION
        Clears the current Adobe API connection and removes cached tokens
    #>
    [CmdletBinding()]
    param()

    if ($script:AdobeAPIConnection) {
        $script:AdobeAPIConnection = $null
        Write-Host "Disconnected from Adobe API" -ForegroundColor Yellow
    }
    else {
        Write-Warning "No active Adobe API connection found"
    }
}

function Test-AdobeConnection {
    <#
    .SYNOPSIS
        Tests the current Adobe API connection

    .DESCRIPTION
        Verifies that the current connection is valid and the access token hasn't expired
    #>
    [CmdletBinding()]
    param()

    if (-not $script:AdobeAPIConnection) {
        Write-Warning "Not connected to Adobe API"
        return $false
    }

    if ($script:AdobeAPIConnection.TokenExpiry -lt (Get-Date)) {
        Write-Warning "Access token has expired"
        return $false
    }

    try {
        $headers = @{
            'Authorization' = "Bearer $($script:AdobeAPIConnection.AccessToken)"
            'X-Api-Key' = $script:AdobeAPIConnection.ClientId
            'Content-Type' = 'application/json'
        }

        $uri = "$($script:AdobeAPIConnection.BaseUrl)/v2/usermanagement/users/$($script:AdobeAPIConnection.OrgId)?page=0&pageSize=1"

        $response = Invoke-RestMethod -Uri $uri -Headers $headers -Method Get

        Write-Host "Adobe API connection is healthy" -ForegroundColor Green
        return $true
    }
    catch {
        Write-Error "Adobe API connection test failed: $_"
        return $false
    }
}

#endregion

#region Core Functions

function Invoke-AdobeAPI {
    <#
    .SYNOPSIS
        Makes authenticated API calls to Adobe User Management API

    .DESCRIPTION
        Internal function to handle API calls with retry logic and error handling
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$Endpoint,

        [ValidateSet('GET', 'POST', 'PUT', 'DELETE', 'PATCH')]
        [string]$Method = 'GET',

        [hashtable]$Body,

        [int]$MaxRetries = 3,

        [int]$RetryDelay = 2
    )

    # Ensure connection
    if (-not $script:AdobeAPIConnection -or $script:AdobeAPIConnection.TokenExpiry -lt (Get-Date)) {
        throw "Not connected to Adobe API or token expired. Please run Connect-AdobeAPI"
    }

    $headers = @{
        'Authorization' = "Bearer $($script:AdobeAPIConnection.AccessToken)"
        'X-Api-Key' = $script:AdobeAPIConnection.ClientId
        'Content-Type' = 'application/json'
    }

    $uri = "$($script:AdobeAPIConnection.BaseUrl)$Endpoint"

    $attempt = 0
    while ($attempt -lt $MaxRetries) {
        try {
            $params = @{
                Uri = $uri
                Headers = $headers
                Method = $Method
            }

            if ($Body) {
                $params.Body = $Body | ConvertTo-Json -Depth 10
            }

            $response = Invoke-RestMethod @params
            return $response
        }
        catch {
            $attempt++

            if ($_.Exception.Response.StatusCode -eq 429) {
                # Rate limited
                $retryAfter = $_.Exception.Response.Headers['Retry-After']
                if ($retryAfter) {
                    Write-Warning "Rate limited. Waiting $retryAfter seconds..."
                    Start-Sleep -Seconds $retryAfter
                }
                else {
                    Start-Sleep -Seconds ($RetryDelay * $attempt)
                }
            }
            elseif ($attempt -lt $MaxRetries) {
                Write-Warning "API call failed (attempt $attempt/$MaxRetries). Retrying..."
                Start-Sleep -Seconds ($RetryDelay * $attempt)
            }
            else {
                throw "API call failed after $MaxRetries attempts: $_"
            }
        }
    }
}

#endregion

#region Utility Functions

function Get-AdobeModuleVersion {
    <#
    .SYNOPSIS
        Gets the current version of the Adobe Automation module
    #>
    [CmdletBinding()]
    param()

    $manifest = Import-PowerShellDataFile "$ModuleRoot\AdobeAutomation.psd1"
    return $manifest.ModuleVersion
}

function Update-AdobeModule {
    <#
    .SYNOPSIS
        Updates the Adobe Automation module to the latest version
    #>
    [CmdletBinding()]
    param()

    Write-Host "Checking for module updates..." -ForegroundColor Cyan

    try {
        $currentVersion = Get-AdobeModuleVersion
        $latestVersion = Find-Module -Name AdobeAutomation -Repository PSGallery |
                        Select-Object -ExpandProperty Version

        if ($latestVersion -gt $currentVersion) {
            Write-Host "New version available: $latestVersion (current: $currentVersion)" -ForegroundColor Yellow

            $confirm = Read-Host "Do you want to update? (Y/N)"
            if ($confirm -eq 'Y') {
                Update-Module -Name AdobeAutomation -Force
                Write-Host "Module updated successfully. Please reload the module." -ForegroundColor Green
            }
        }
        else {
            Write-Host "Module is up to date (version: $currentVersion)" -ForegroundColor Green
        }
    }
    catch {
        Write-Error "Failed to check for updates: $_"
    }
}

#endregion

#region Module Initialization

# Load default configuration if exists
$defaultConfig = Join-Path $ConfigPath "DefaultConfig.json"
if (Test-Path $defaultConfig) {
    $script:DefaultConfiguration = Get-Content $defaultConfig | ConvertFrom-Json
}

# Set up logging
$script:LogPath = Join-Path $env:TEMP "AdobeAutomation"
if (-not (Test-Path $LogPath)) {
    New-Item -Path $LogPath -ItemType Directory -Force | Out-Null
}

# Export module member
Export-ModuleMember -Function * -Variable 'AdobeAPIConnection' -Alias *

Write-Verbose "Adobe Automation Module loaded successfully (v$(Get-AdobeModuleVersion))"

#endregion