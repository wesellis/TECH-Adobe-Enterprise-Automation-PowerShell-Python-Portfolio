#!/usr/bin/env pwsh
# INTERMEDIATE LEVEL: User management with error handling
# Learning: Parameters, error handling, logging, API patterns

[CmdletBinding(SupportsShouldProcess)]
param(
    [Parameter(Mandatory=$true)]
    [ValidateSet('Add', 'Remove', 'Update', 'List')]
    [string]$Action,

    [Parameter(Mandatory=$false)]
    [string]$UserEmail,

    [Parameter(Mandatory=$false)]
    [string[]]$Products,

    [Parameter(Mandatory=$false)]
    [string]$LogFile = "./logs/adobe-management-$(Get-Date -Format 'yyyyMMdd').log"
)

# Intermediate: Proper error handling
$ErrorActionPreference = 'Stop'

# Logging function
function Write-Log {
    param(
        [string]$Message,
        [ValidateSet('INFO', 'WARNING', 'ERROR', 'SUCCESS')]
        [string]$Level = 'INFO'
    )

    $timestamp = Get-Date -Format 'yyyy-MM-dd HH:mm:ss'
    $logEntry = "[$timestamp] [$Level] $Message"

    # Console output with colors
    switch ($Level) {
        'ERROR'   { Write-Host $logEntry -ForegroundColor Red }
        'WARNING' { Write-Host $logEntry -ForegroundColor Yellow }
        'SUCCESS' { Write-Host $logEntry -ForegroundColor Green }
        default   { Write-Host $logEntry }
    }

    # File logging
    $logEntry | Add-Content -Path $LogFile -ErrorAction SilentlyContinue
}

# API wrapper with retry logic
function Invoke-AdobeAPI {
    param(
        [string]$Endpoint,
        [string]$Method = 'GET',
        [hashtable]$Body
    )

    $maxRetries = 3
    $retryCount = 0

    while ($retryCount -lt $maxRetries) {
        try {
            Write-Log "Calling Adobe API: $Method $Endpoint" -Level INFO

            # Simulate API call with potential failures
            if ((Get-Random -Maximum 10) -eq 1) {
                throw "API timeout"
            }

            # Mock successful response
            return @{
                Success = $true
                Data = @{
                    UserId = [guid]::NewGuid().ToString()
                    Status = 'Completed'
                }
            }
        }
        catch {
            $retryCount++
            Write-Log "API call failed (attempt $retryCount/$maxRetries): $_" -Level WARNING

            if ($retryCount -eq $maxRetries) {
                Write-Log "Max retries reached. Operation failed." -Level ERROR
                throw
            }

            Start-Sleep -Seconds ([Math]::Pow(2, $retryCount))  # Exponential backoff
        }
    }
}

# User management functions
function Add-AdobeUser {
    param(
        [string]$Email,
        [string[]]$Products
    )

    try {
        Write-Log "Adding user: $Email" -Level INFO

        # Validate email format
        if ($Email -notmatch '^[\w\.-]+@[\w\.-]+\.\w+$') {
            throw "Invalid email format: $Email"
        }

        # Check if user exists (mock check)
        $existingUsers = @('existing@company.com', 'admin@company.com')
        if ($Email -in $existingUsers) {
            Write-Log "User already exists: $Email" -Level WARNING
            return $false
        }

        # API call
        $result = Invoke-AdobeAPI -Endpoint "/users" -Method 'POST' -Body @{
            email = $Email
            products = $Products
        }

        if ($result.Success) {
            Write-Log "Successfully added user: $Email (ID: $($result.Data.UserId))" -Level SUCCESS
            return $true
        }
    }
    catch {
        Write-Log "Failed to add user: $_" -Level ERROR
        return $false
    }
}

function Remove-AdobeUser {
    param([string]$Email)

    if ($PSCmdlet.ShouldProcess($Email, "Remove Adobe User")) {
        try {
            Write-Log "Removing user: $Email" -Level INFO

            $result = Invoke-AdobeAPI -Endpoint "/users/$Email" -Method 'DELETE'

            if ($result.Success) {
                Write-Log "Successfully removed user: $Email" -Level SUCCESS
                return $true
            }
        }
        catch {
            Write-Log "Failed to remove user: $_" -Level ERROR
            return $false
        }
    }
}

function Update-AdobeUser {
    param(
        [string]$Email,
        [string[]]$Products
    )

    try {
        Write-Log "Updating user: $Email" -Level INFO

        $result = Invoke-AdobeAPI -Endpoint "/users/$Email" -Method 'PATCH' -Body @{
            products = $Products
        }

        if ($result.Success) {
            Write-Log "Successfully updated user: $Email" -Level SUCCESS
            return $true
        }
    }
    catch {
        Write-Log "Failed to update user: $_" -Level ERROR
        return $false
    }
}

function Get-AdobeUsers {
    try {
        Write-Log "Retrieving user list" -Level INFO

        # Mock data with more complexity
        $users = @(
            [PSCustomObject]@{
                Email = 'john.doe@company.com'
                Name = 'John Doe'
                Products = @('Creative Cloud', 'Acrobat')
                LastActive = (Get-Date).AddDays(-5)
                Status = 'Active'
            },
            [PSCustomObject]@{
                Email = 'jane.smith@company.com'
                Name = 'Jane Smith'
                Products = @('Photoshop')
                LastActive = (Get-Date).AddDays(-45)
                Status = 'Inactive'
            }
        )

        # Format output
        $users | Format-Table Email, Name, Status, @{
            Label = 'Products'
            Expression = { $_.Products -join ', ' }
        }, @{
            Label = 'Days Inactive'
            Expression = { ((Get-Date) - $_.LastActive).Days }
        } -AutoSize

        Write-Log "Retrieved $($users.Count) users" -Level SUCCESS
        return $users
    }
    catch {
        Write-Log "Failed to retrieve users: $_" -Level ERROR
        return @()
    }
}

# Main execution
try {
    # Ensure log directory exists
    $logDir = Split-Path $LogFile -Parent
    if (-not (Test-Path $logDir)) {
        New-Item -ItemType Directory -Path $logDir -Force | Out-Null
    }

    Write-Log "Starting Adobe user management: $Action" -Level INFO

    # Execute based on action
    switch ($Action) {
        'Add' {
            if (-not $UserEmail) {
                throw "UserEmail parameter required for Add action"
            }
            $result = Add-AdobeUser -Email $UserEmail -Products $Products
        }
        'Remove' {
            if (-not $UserEmail) {
                throw "UserEmail parameter required for Remove action"
            }
            $result = Remove-AdobeUser -Email $UserEmail
        }
        'Update' {
            if (-not $UserEmail) {
                throw "UserEmail parameter required for Update action"
            }
            $result = Update-AdobeUser -Email $UserEmail -Products $Products
        }
        'List' {
            $result = Get-AdobeUsers
        }
    }

    Write-Log "Operation completed" -Level INFO
}
catch {
    Write-Log "Fatal error: $_" -Level ERROR
    exit 1
}
finally {
    Write-Log "Log file: $LogFile" -Level INFO
}