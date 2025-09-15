<#
.SYNOPSIS
    Provisions Adobe Creative Cloud users from Active Directory
.DESCRIPTION
    Automatically provisions Adobe users based on AD group membership
.EXAMPLE
    .\New-AdobeUser.ps1 -Email "user@company.com" -Products "Creative Cloud"
#>

[CmdletBinding()]
param(
    [Parameter(Mandatory=$false)]
    [string]$Email,

    [Parameter(Mandatory=$false)]
    [string[]]$Products = @("Creative Cloud"),

    [Parameter(Mandatory=$false)]
    [string]$ConfigPath = "..\..\config\adobe-config.json",

    [switch]$BulkMode,
    [switch]$TestMode
)

# Load configuration
function Get-AdobeConfig {
    param([string]$Path)

    if (Test-Path $Path) {
        return Get-Content $Path | ConvertFrom-Json
    } else {
        Write-Error "Configuration file not found: $Path"
        exit 1
    }
}

# Adobe API Authentication
function Get-AdobeAccessToken {
    param($Config)

    if ($TestMode) {
        Write-Host "TEST MODE: Simulating Adobe authentication" -ForegroundColor Yellow
        return "test_token_12345"
    }

    $body = @{
        client_id = $Config.adobe.client_id
        client_secret = $Config.adobe.client_secret
        jwt_token = New-JWTToken -Config $Config
    }

    try {
        $response = Invoke-RestMethod -Uri "https://ims-na1.adobelogin.com/ims/exchange/jwt" `
            -Method Post -Body $body
        return $response.access_token
    }
    catch {
        Write-Error "Failed to authenticate with Adobe API: $_"
        throw
    }
}

# Create new Adobe user
function New-AdobeUserAPI {
    param(
        [string]$Email,
        [string]$FirstName,
        [string]$LastName,
        [string[]]$Products,
        [string]$Token,
        $Config
    )

    if ($TestMode) {
        Write-Host "TEST MODE: Would create user $Email with products: $($Products -join ', ')" -ForegroundColor Yellow
        return @{success = $true; email = $Email}
    }

    $headers = @{
        "Authorization" = "Bearer $Token"
        "X-Api-Key" = $Config.adobe.client_id
        "Content-Type" = "application/json"
    }

    $body = @{
        user = @{
            email = $Email
            firstname = $FirstName
            lastname = $LastName
            country = "US"
        }
        do = @(
            @{addUser = @{}}
        )
    }

    # Add products if specified
    if ($Products) {
        $body.do += @{
            add = @{
                product = $Products
            }
        }
    }

    $jsonBody = $body | ConvertTo-Json -Depth 10
    $url = "https://usermanagement.adobe.io/v2/usermanagement/action/$($Config.adobe.org_id)"

    try {
        $response = Invoke-RestMethod -Uri $url -Method Post -Headers $headers -Body $jsonBody
        Write-Host "✓ Successfully created Adobe user: $Email" -ForegroundColor Green
        return $response
    }
    catch {
        Write-Error "Failed to create user $Email : $_"
        throw
    }
}

# Process single user
function Process-SingleUser {
    param(
        [string]$Email,
        [string[]]$Products,
        [string]$Token,
        $Config
    )

    # Get user details from AD if available
    try {
        $adUser = Get-ADUser -Filter "UserPrincipalName -eq '$Email'" -Properties GivenName, Surname
        $firstName = $adUser.GivenName
        $lastName = $adUser.Surname
    }
    catch {
        # If AD lookup fails, parse from email
        $nameParts = $Email.Split('@')[0].Split('.')
        $firstName = $nameParts[0]
        $lastName = if ($nameParts.Count -gt 1) { $nameParts[1] } else { "User" }
    }

    New-AdobeUserAPI -Email $Email -FirstName $firstName -LastName $lastName `
        -Products $Products -Token $Token -Config $Config
}

# Process bulk users from AD group
function Process-BulkUsers {
    param(
        [string[]]$Products,
        [string]$Token,
        $Config
    )

    Write-Host "Processing users from Active Directory Creative group..." -ForegroundColor Cyan

    try {
        # Get users from AD group
        $users = Get-ADGroupMember -Identity "Creative-Users" |
            Get-ADUser -Properties UserPrincipalName, GivenName, Surname, Department |
            Where-Object { $_.Enabled -eq $true }

        Write-Host "Found $($users.Count) users to process" -ForegroundColor Cyan

        $results = @()
        foreach ($user in $users) {
            try {
                $result = New-AdobeUserAPI `
                    -Email $user.UserPrincipalName `
                    -FirstName $user.GivenName `
                    -LastName $user.Surname `
                    -Products $Products `
                    -Token $Token `
                    -Config $Config

                $results += [PSCustomObject]@{
                    Email = $user.UserPrincipalName
                    Status = "Success"
                    Products = $Products -join ","
                }
            }
            catch {
                $results += [PSCustomObject]@{
                    Email = $user.UserPrincipalName
                    Status = "Failed"
                    Error = $_.Exception.Message
                }
            }
        }

        # Export results
        $reportPath = "..\..\reports\provisioning-$(Get-Date -Format 'yyyyMMdd-HHmmss').csv"
        $results | Export-Csv -Path $reportPath -NoTypeInformation
        Write-Host "Report saved to: $reportPath" -ForegroundColor Green
    }
    catch {
        Write-Error "Failed to process bulk users: $_"
    }
}

# Main execution
function Main {
    Write-Host "`n=== Adobe User Provisioning Started ===" -ForegroundColor Cyan
    Write-Host "Time: $(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')" -ForegroundColor Gray

    # Load configuration
    $config = Get-AdobeConfig -Path $ConfigPath

    # Get access token
    $token = Get-AdobeAccessToken -Config $config

    if ($BulkMode) {
        Process-BulkUsers -Products $Products -Token $token -Config $config
    }
    elseif ($Email) {
        Process-SingleUser -Email $Email -Products $Products -Token $token -Config $config
    }
    else {
        Write-Error "Please specify either -Email for single user or -BulkMode for bulk processing"
    }

    Write-Host "`n=== Adobe User Provisioning Completed ===" -ForegroundColor Green
}

# Helper function for JWT token
function New-JWTToken {
    param($Config)

    if ($TestMode) {
        return "test_jwt_token"
    }

    # In production, implement proper JWT signing
    # This is a placeholder
    return "jwt_token_placeholder"
}

# Run main function
Main