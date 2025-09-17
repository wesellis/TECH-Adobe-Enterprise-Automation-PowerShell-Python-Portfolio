<#
.SYNOPSIS
    Optimizes Adobe license allocation by reclaiming unused licenses
.DESCRIPTION
    Identifies inactive users and automatically reclaims their licenses
.EXAMPLE
    .\Optimize-Licenses.ps1 -InactiveDays 30 -AutoReclaim
#>

[CmdletBinding()]
param(
    [int]$InactiveDays = 30,
    [switch]$AutoReclaim,
    [switch]$GenerateReport,
    [switch]$TestMode,
    [string]$ConfigPath = "..\..\config\adobe-config.json"
)

# Initialize logging
$script:LogPath = "..\..\logs\license-optimization-$(Get-Date -Format 'yyyyMMdd').log"

function Write-Log {
    param(
        [string]$Message,
        [string]$Level = "INFO"
    )

    $timestamp = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
    $logEntry = "[$timestamp] [$Level] $Message"

    Add-Content -Path $script:LogPath -Value $logEntry

    switch ($Level) {
        "ERROR" { Write-Host $logEntry -ForegroundColor Red }
        "WARNING" { Write-Host $logEntry -ForegroundColor Yellow }
        "SUCCESS" { Write-Host $logEntry -ForegroundColor Green }
        default { Write-Host $logEntry -ForegroundColor White }
    }
}

function Get-AdobeAccessToken {
    param($Config)

    $body = @{
        client_id = $Config.adobe.client_id
        client_secret = $Config.adobe.client_secret
        jwt_token = "jwt_placeholder" # In production, generate proper JWT
    }

    try {
        $response = Invoke-RestMethod -Uri "https://ims-na1.adobelogin.com/ims/exchange/jwt" `
            -Method Post -Body $body
        return $response.access_token
    }
    catch {
        Write-Log "Failed to authenticate with Adobe API: $_" "ERROR"
        throw
    }
}

function Get-InactiveUsers {
    param(
        [int]$Days,
        [string]$Token,
        $Config
    )

    Write-Log "Fetching user activity data..."

    if ($TestMode) {
        # Generate test data
        return @(
            [PSCustomObject]@{Email="inactive1@company.com"; LastLogin=(Get-Date).AddDays(-45); Products=@("Photoshop","Illustrator")}
            [PSCustomObject]@{Email="inactive2@company.com"; LastLogin=(Get-Date).AddDays(-60); Products=@("Creative Cloud")}
            [PSCustomObject]@{Email="inactive3@company.com"; LastLogin=(Get-Date).AddDays(-90); Products=@("Acrobat DC")}
        )
    }

    $headers = @{
        "Authorization" = "Bearer $Token"
        "X-Api-Key" = $Config.adobe.client_id
    }

    $url = "https://usermanagement.adobe.io/v2/usermanagement/users/$($Config.adobe.org_id)"

    try {
        $response = Invoke-RestMethod -Uri $url -Method Get -Headers $headers
        $users = $response.users

        $inactiveUsers = $users | Where-Object {
            $lastLogin = [DateTime]::Parse($_.lastLogin)
            $daysSinceLogin = (Get-Date) - $lastLogin
            $daysSinceLogin.Days -gt $Days
        }

        Write-Log "Found $($inactiveUsers.Count) inactive users (>$Days days)" "WARNING"
        return $inactiveUsers
    }
    catch {
        Write-Log "Failed to fetch users: $_" "ERROR"
        throw
    }
}

function Remove-UserProducts {
    param(
        [string]$Email,
        [string[]]$Products,
        [string]$Token,
        $Config
    )

    if ($TestMode) {
        Write-Log "TEST MODE: Would remove products from $Email : $($Products -join ', ')" "WARNING"
        return @{success = $true}
    }

    $headers = @{
        "Authorization" = "Bearer $Token"
        "X-Api-Key" = $Config.adobe.client_id
        "Content-Type" = "application/json"
    }

    $body = @{
        user = @{email = $Email}
        do = @(
            @{
                remove = @{
                    product = $Products
                }
            }
        )
    } | ConvertTo-Json -Depth 10

    $url = "https://usermanagement.adobe.io/v2/usermanagement/action/$($Config.adobe.org_id)"

    try {
        $response = Invoke-RestMethod -Uri $url -Method Post -Headers $headers -Body $body
        Write-Log "Successfully removed products from $Email" "SUCCESS"
        return $response
    }
    catch {
        Write-Log "Failed to remove products from $Email : $_" "ERROR"
        throw
    }
}

function Calculate-Savings {
    param(
        [array]$ReclaimedLicenses
    )

    $licenseCosts = @{
        "Creative Cloud" = 80
        "Photoshop" = 35
        "Illustrator" = 35
        "Acrobat DC" = 25
        "InDesign" = 35
        "Premiere Pro" = 35
        "After Effects" = 35
    }

    $totalSavings = 0

    foreach ($license in $ReclaimedLicenses) {
        $cost = $licenseCosts[$license]
        if ($cost) {
            $totalSavings += $cost
        } else {
            $totalSavings += 30  # Default cost
        }
    }

    return $totalSavings
}

function Generate-OptimizationReport {
    param(
        $InactiveUsers,
        $ReclaimedLicenses,
        $Savings
    )

    $html = @"
<!DOCTYPE html>
<html>
<head>
    <title>Adobe License Optimization Report</title>
    <style>
        body { font-family: Arial, sans-serif; margin: 40px; }
        h1 { color: #FF0000; }
        .summary { background: #f0f0f0; padding: 20px; border-radius: 5px; margin: 20px 0; }
        .savings { color: green; font-size: 24px; font-weight: bold; }
        table { width: 100%; border-collapse: collapse; margin: 20px 0; }
        th { background: #333; color: white; padding: 10px; text-align: left; }
        td { padding: 10px; border-bottom: 1px solid #ddd; }
        .recommendation { background: #fff3cd; padding: 15px; border-left: 4px solid #ffc107; margin: 20px 0; }
    </style>
</head>
<body>
    <h1>Adobe License Optimization Report</h1>
    <p>Generated: $(Get-Date -Format "yyyy-MM-dd HH:mm:ss")</p>

    <div class="summary">
        <h2>Executive Summary</h2>
        <p>Inactive Users Identified: <strong>$($InactiveUsers.Count)</strong></p>
        <p>Licenses Reclaimed: <strong>$($ReclaimedLicenses.Count)</strong></p>
        <p class="savings">Monthly Savings: `$$Savings</p>
        <p class="savings">Annual Savings: `$$($Savings * 12)</p>
    </div>

    <h2>Inactive Users</h2>
    <table>
        <tr>
            <th>Email</th>
            <th>Last Login</th>
            <th>Days Inactive</th>
            <th>Products</th>
        </tr>
"@

    foreach ($user in $InactiveUsers) {
        $daysInactive = ((Get-Date) - $user.LastLogin).Days
        $html += @"
        <tr>
            <td>$($user.Email)</td>
            <td>$($user.LastLogin.ToString("yyyy-MM-dd"))</td>
            <td>$daysInactive</td>
            <td>$($user.Products -join ", ")</td>
        </tr>
"@
    }

    $html += @"
    </table>

    <div class="recommendation">
        <h3>Recommendations</h3>
        <ul>
            <li>Review inactive users monthly</li>
            <li>Implement automated license reclamation after 45 days</li>
            <li>Consider usage-based allocation for seasonal workers</li>
            <li>Enable single sign-on to track actual usage</li>
        </ul>
    </div>

    <p><small>Report generated by Adobe Enterprise Automation Suite</small></p>
</body>
</html>
"@

    $reportPath = "..\..\reports\license-optimization-$(Get-Date -Format 'yyyyMMdd-HHmmss').html"
    $html | Out-File -FilePath $reportPath -Encoding UTF8
    Write-Log "Report saved to: $reportPath" "SUCCESS"

    # Open report in browser
    Start-Process $reportPath
}

# Main execution
function Main {
    Write-Log "=== Adobe License Optimization Started ===" "INFO"

    # Load configuration
    if (Test-Path $ConfigPath) {
        $config = Get-Content $ConfigPath | ConvertFrom-Json
    } else {
        Write-Log "Configuration file not found: $ConfigPath" "ERROR"
        return
    }

    # Get access token
    $token = if ($TestMode) {
        "test_token"
    } else {
        Get-AdobeAccessToken -Config $config
    }

    # Get inactive users
    $inactiveUsers = Get-InactiveUsers -Days $InactiveDays -Token $token -Config $config

    if ($inactiveUsers.Count -eq 0) {
        Write-Log "No inactive users found. Nothing to optimize." "SUCCESS"
        return
    }

    $reclaimedLicenses = @()

    # Process reclamation if requested
    if ($AutoReclaim) {
        Write-Log "Starting automatic license reclamation..." "WARNING"

        foreach ($user in $inactiveUsers) {
            try {
                Remove-UserProducts -Email $user.Email -Products $user.Products `
                    -Token $token -Config $config

                $reclaimedLicenses += $user.Products
            }
            catch {
                Write-Log "Failed to process $($user.Email): $_" "ERROR"
            }
        }
    }

    # Calculate savings
    $monthlySavings = Calculate-Savings -ReclaimedLicenses $reclaimedLicenses

    Write-Log "Potential monthly savings: `$$monthlySavings" "SUCCESS"
    Write-Log "Potential annual savings: `$$($monthlySavings * 12)" "SUCCESS"

    # Generate report if requested
    if ($GenerateReport -or $AutoReclaim) {
        Generate-OptimizationReport -InactiveUsers $inactiveUsers `
            -ReclaimedLicenses $reclaimedLicenses -Savings $monthlySavings
    }

    Write-Log "=== Adobe License Optimization Completed ===" "SUCCESS"
}

# Run main function
Main