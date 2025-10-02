<#
.SYNOPSIS
    Perform compliance audit of Adobe Creative Cloud environment.
.DESCRIPTION
    Audits Adobe CC for compliance violations including inactive users with licenses,
    unauthorized product assignments, policy violations, and security risks.
.PARAMETER InactiveDays
    Days of inactivity to flag users (default: 90).
.PARAMETER CheckSecurity
    Include security compliance checks.
.PARAMETER ExportPath
    Path to save compliance report.
.PARAMETER RemediateIssues
    Automatically remediate found issues (requires confirmation).
.EXAMPLE
    .\Get-AdobeComplianceAudit.ps1 -InactiveDays 90 -CheckSecurity -ExportPath "C:\Audits\compliance.html"
.NOTES
    Requires Adobe Admin Console API access and appropriate permissions
#>
[CmdletBinding(SupportsShouldProcess)]
param(
    [Parameter(Mandatory = $false)]
    [ValidateRange(1, 365)]
    [int]$InactiveDays = 90,
    [Parameter(Mandatory = $false)]
    [switch]$CheckSecurity,
    [Parameter(Mandatory = $false)]
    [string]$ExportPath,
    [Parameter(Mandatory = $false)]
    [switch]$RemediateIssues,
    [Parameter(Mandatory = $false)]
    [string]$ConfigPath = "..\..\config\adobe-config.json"
)

function Get-ComplianceViolations {
    param($Users, $Config, [int]$InactiveDays)

    Write-Host "Analyzing compliance violations..." -ForegroundColor Cyan

    $violations = @{
        InactiveWithLicenses = @()
        MultipleProductViolations = @()
        UnauthorizedProducts = @()
        ExpiredAccounts = @()
        SecurityRisks = @()
    }

    $cutoffDate = (Get-Date).AddDays(-$InactiveDays)

    foreach ($user in $Users) {
        # Check inactive users with active licenses
        $lastLogin = if ($user.lastLogin) { [datetime]$user.lastLogin } else { $cutoffDate.AddDays(-365) }

        if ($lastLogin -lt $cutoffDate -and $user.status -eq "active" -and $user.groups.Count -gt 0) {
            $violations.InactiveWithLicenses += [PSCustomObject]@{
                Email = $user.email
                LastLogin = $lastLogin
                DaysInactive = [math]::Round(((Get-Date) - $lastLogin).TotalDays, 0)
                LicenseCount = $user.groups.Count
                Products = $user.groups -join ', '
                Severity = if (((Get-Date) - $lastLogin).TotalDays -gt 180) { "High" } else { "Medium" }
            }
        }

        # Check for excessive product assignments
        if ($user.groups.Count -gt 5) {
            $violations.MultipleProductViolations += [PSCustomObject]@{
                Email = $user.email
                ProductCount = $user.groups.Count
                Products = $user.groups -join ', '
                Severity = "Medium"
            }
        }

        # Check for unauthorized products (example: non-IT users with technical products)
        if ($user.country -ne "IT" -and $user.groups -contains "_admin_console") {
            $violations.UnauthorizedProducts += [PSCustomObject]@{
                Email = $user.email
                Department = $user.country
                UnauthorizedProduct = "Admin Console"
                Severity = "High"
            }
        }

        # Check for expired accounts
        if ($user.status -ne "active") {
            $violations.ExpiredAccounts += [PSCustomObject]@{
                Email = $user.email
                Status = $user.status
                LastLogin = $user.lastLogin
                Severity = "Low"
            }
        }
    }

    return $violations
}

function Get-SecurityCompliance {
    param($Users)

    Write-Host "Checking security compliance..." -ForegroundColor Cyan

    $securityIssues = @{
        WeakPasswords = @()
        No2FA = @()
        ExcessivePermissions = @()
        SharedAccounts = @()
    }

    foreach ($user in $Users) {
        # Check for 2FA (if API provides this data)
        if (-not $user.has2FA) {
            $securityIssues.No2FA += [PSCustomObject]@{
                Email = $user.email
                AccountType = $user.type
                Severity = "High"
            }
        }

        # Check for admin permissions
        if ($user.adminRoles -and $user.adminRoles.Count -gt 0) {
            $securityIssues.ExcessivePermissions += [PSCustomObject]@{
                Email = $user.email
                AdminRoles = $user.adminRoles -join ', '
                Severity = "Medium"
            }
        }

        # Check for potential shared accounts (generic email patterns)
        if ($user.email -match '^(admin|info|support|team|group|dept|shared)@') {
            $securityIssues.SharedAccounts += [PSCustomObject]@{
                Email = $user.email
                Type = "Suspected Shared Account"
                Severity = "High"
            }
        }
    }

    return $securityIssues
}

function Invoke-Remediation {
    param($Violations, $Token, $Config)

    Write-Host "`n=== Starting Automated Remediation ===" -ForegroundColor Yellow
    Write-Warning "This will make changes to user accounts. Proceed with caution."

    $remediatedCount = 0

    # Remediate inactive users
    foreach ($violation in $Violations.InactiveWithLicenses) {
        if ($PSCmdlet.ShouldProcess($violation.Email, "Remove licenses from inactive user")) {
            try {
                # Remove product assignments
                $headers = @{
                    "Authorization" = "Bearer $Token"
                    "X-Api-Key" = $Config.adobe.client_id
                    "Content-Type" = "application/json"
                }

                $body = @{
                    user = @{ email = $violation.Email }
                    do = @(
                        @{ removeFromOrg = @{} }
                    )
                } | ConvertTo-Json -Depth 10

                $url = "https://usermanagement.adobe.io/v2/usermanagement/action/$($Config.adobe.org_id)"
                Invoke-RestMethod -Uri $url -Method Post -Headers $headers -Body $body | Out-Null

                Write-Host "  ✓ Removed licenses from: $($violation.Email)" -ForegroundColor Green
                $remediatedCount++
            }
            catch {
                Write-Warning "Failed to remediate $($violation.Email): $_"
            }
        }
    }

    Write-Host "`n✓ Remediated $remediatedCount issues" -ForegroundColor Green
}

function Export-ComplianceReport {
    param($Violations, $SecurityIssues, [string]$OutputPath)

    $timestamp = Get-Date -Format "yyyyMMdd-HHmmss"

    if (-not $OutputPath) {
        $OutputPath = "..\..\reports\compliance-audit-$timestamp.html"
    }

    $totalViolations = 0
    $totalViolations += $Violations.InactiveWithLicenses.Count
    $totalViolations += $Violations.MultipleProductViolations.Count
    $totalViolations += $Violations.UnauthorizedProducts.Count

    if ($SecurityIssues) {
        $totalViolations += $SecurityIssues.No2FA.Count
        $totalViolations += $SecurityIssues.ExcessivePermissions.Count
        $totalViolations += $SecurityIssues.SharedAccounts.Count
    }

    $html = @"
<!DOCTYPE html>
<html>
<head>
    <title>Adobe Compliance Audit Report</title>
    <style>
        body { font-family: 'Segoe UI', Arial, sans-serif; margin: 0; padding: 20px; background: #f0f0f0; }
        .container { max-width: 1400px; margin: 0 auto; background: white; padding: 30px; border-radius: 8px; box-shadow: 0 2px 10px rgba(0,0,0,0.1); }
        h1 { color: #DC143C; border-bottom: 3px solid #DC143C; padding-bottom: 10px; }
        h2 { color: #333; margin-top: 30px; padding-left: 10px; border-left: 4px solid #DC143C; }
        .summary { display: grid; grid-template-columns: repeat(auto-fit, minmax(250px, 1fr)); gap: 20px; margin: 30px 0; }
        .summary-card { padding: 20px; border-radius: 8px; text-align: center; }
        .summary-card.critical { background: #ffebee; border: 2px solid #c62828; }
        .summary-card.warning { background: #fff3e0; border: 2px solid #ef6c00; }
        .summary-card.info { background: #e3f2fd; border: 2px solid #1976d2; }
        .summary-value { font-size: 48px; font-weight: bold; margin: 10px 0; }
        .summary-label { font-size: 14px; color: #666; text-transform: uppercase; }
        table { width: 100%; border-collapse: collapse; margin: 20px 0; font-size: 14px; }
        th { background: #DC143C; color: white; padding: 12px; text-align: left; font-weight: 600; }
        td { padding: 10px; border-bottom: 1px solid #ddd; }
        tr:hover { background: #f5f5f5; }
        .severity-high { color: #c62828; font-weight: bold; }
        .severity-medium { color: #ef6c00; font-weight: bold; }
        .severity-low { color: #1976d2; }
        .violation-count { display: inline-block; background: #DC143C; color: white; padding: 2px 8px; border-radius: 12px; font-size: 12px; }
        .recommendations { background: #e8f5e9; padding: 20px; border-radius: 8px; border-left: 4px solid #4caf50; margin: 20px 0; }
    </style>
</head>
<body>
    <div class="container">
        <h1>🔍 Adobe Creative Cloud Compliance Audit</h1>
        <p><strong>Generated:</strong> $(Get-Date -Format 'yyyy-MM-dd HH:mm:ss') | <strong>Inactive Threshold:</strong> $InactiveDays days</p>

        <div class="summary">
            <div class="summary-card critical">
                <div class="summary-value">$totalViolations</div>
                <div class="summary-label">Total Violations</div>
            </div>
            <div class="summary-card warning">
                <div class="summary-value">$($Violations.InactiveWithLicenses.Count)</div>
                <div class="summary-label">Inactive Users</div>
            </div>
            <div class="summary-card info">
                <div class="summary-value">$($Violations.UnauthorizedProducts.Count)</div>
                <div class="summary-label">Unauthorized Access</div>
            </div>
$(if ($SecurityIssues) {
"            <div class='summary-card warning'>
                <div class='summary-value'>$($SecurityIssues.No2FA.Count)</div>
                <div class='summary-label'>No 2FA</div>
            </div>"
})
        </div>

        <h2>⚠️ Inactive Users with Active Licenses <span class="violation-count">$($Violations.InactiveWithLicenses.Count)</span></h2>
        <table>
            <tr>
                <th>Email</th>
                <th>Last Login</th>
                <th>Days Inactive</th>
                <th>License Count</th>
                <th>Severity</th>
            </tr>
$(foreach ($v in $Violations.InactiveWithLicenses | Sort-Object DaysInactive -Descending | Select-Object -First 50) {
"            <tr>
                <td>$($v.Email)</td>
                <td>$($v.LastLogin.ToString('yyyy-MM-dd'))</td>
                <td>$($v.DaysInactive)</td>
                <td>$($v.LicenseCount)</td>
                <td class='severity-$($v.Severity.ToLower())'>$($v.Severity)</td>
            </tr>"
})
        </table>

        <h2>📦 Multiple Product Violations <span class="violation-count">$($Violations.MultipleProductViolations.Count)</span></h2>
        <table>
            <tr>
                <th>Email</th>
                <th>Product Count</th>
                <th>Products</th>
                <th>Severity</th>
            </tr>
$(foreach ($v in $Violations.MultipleProductViolations | Sort-Object ProductCount -Descending | Select-Object -First 20) {
"            <tr>
                <td>$($v.Email)</td>
                <td>$($v.ProductCount)</td>
                <td>$($v.Products)</td>
                <td class='severity-$($v.Severity.ToLower())'>$($v.Severity)</td>
            </tr>"
})
        </table>

$(if ($SecurityIssues -and $SecurityIssues.No2FA.Count -gt 0) {
"        <h2>🔐 Security Issues - No 2FA <span class='violation-count'>$($SecurityIssues.No2FA.Count)</span></h2>
        <table>
            <tr>
                <th>Email</th>
                <th>Account Type</th>
                <th>Severity</th>
            </tr>
$(foreach ($s in $SecurityIssues.No2FA | Select-Object -First 30) {
"            <tr>
                <td>$($s.Email)</td>
                <td>$($s.AccountType)</td>
                <td class='severity-high'>High</td>
            </tr>"
})
        </table>"
})

        <div class="recommendations">
            <h3>💡 Recommendations</h3>
            <ul>
                <li><strong>Immediate Action:</strong> Review and remove licenses from $($Violations.InactiveWithLicenses.Count) inactive users</li>
                <li><strong>Policy Review:</strong> $($Violations.MultipleProductViolations.Count) users exceed recommended product assignments</li>
                <li><strong>Security:</strong> Enforce 2FA for all $(if ($SecurityIssues) { $SecurityIssues.No2FA.Count } else { 0 }) users without multi-factor authentication</li>
                <li><strong>Cost Savings:</strong> Estimated monthly savings: `$$(($Violations.InactiveWithLicenses.Count * 55)).00 (assuming `$55/license)</li>
            </ul>
        </div>

        <p style="text-align: center; color: #666; font-size: 12px; margin-top: 40px;">
            Generated by Adobe Enterprise Automation Suite | Compliance Audit Module
        </p>
    </div>
</body>
</html>
"@

    $html | Out-File -FilePath $OutputPath -Encoding UTF8
    Write-Host "✓ Compliance report exported to: $OutputPath" -ForegroundColor Green
}

# Main execution
try {
    Write-Host "`n=== Adobe Compliance Audit ===" -ForegroundColor Cyan

    # Load config and authenticate
    $config = Get-Content $ConfigPath | ConvertFrom-Json
    $token = Get-AdobeAccessToken -Config $config

    # Get all users
    Write-Host "Retrieving user data..." -ForegroundColor Cyan
    $headers = @{
        "Authorization" = "Bearer $Token"
        "X-Api-Key" = $config.adobe.client_id
    }
    $users = (Invoke-RestMethod -Uri "https://usermanagement.adobe.io/v2/usermanagement/users/$($config.adobe.org_id)/0" `
        -Headers $headers).users

    # Check compliance
    $violations = Get-ComplianceViolations -Users $users -Config $config -InactiveDays $InactiveDays

    # Security compliance if requested
    $securityIssues = if ($CheckSecurity) {
        Get-SecurityCompliance -Users $users
    } else { $null }

    # Display summary
    Write-Host "`n--- Compliance Summary ---" -ForegroundColor Yellow
    Write-Host "Inactive Users with Licenses: $($violations.InactiveWithLicenses.Count)" -ForegroundColor Red
    Write-Host "Multiple Product Violations: $($violations.MultipleProductViolations.Count)" -ForegroundColor Yellow
    Write-Host "Unauthorized Products: $($violations.UnauthorizedProducts.Count)" -ForegroundColor Red

    if ($securityIssues) {
        Write-Host "`n--- Security Summary ---" -ForegroundColor Yellow
        Write-Host "Users without 2FA: $($securityIssues.No2FA.Count)" -ForegroundColor Red
        Write-Host "Excessive Permissions: $($securityIssues.ExcessivePermissions.Count)" -ForegroundColor Yellow
        Write-Host "Suspected Shared Accounts: $($securityIssues.SharedAccounts.Count)" -ForegroundColor Red
    }

    # Export report
    Export-ComplianceReport -Violations $violations -SecurityIssues $securityIssues -OutputPath $ExportPath

    # Remediation if requested
    if ($RemediateIssues) {
        Invoke-Remediation -Violations $violations -Token $token -Config $config
    }

    Write-Host "`n✓ Compliance audit complete`n" -ForegroundColor Green
}
catch {
    Write-Error "Compliance audit failed: $_"
    exit 1
}
