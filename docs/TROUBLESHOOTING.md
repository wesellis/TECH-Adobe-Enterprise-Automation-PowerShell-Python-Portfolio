# 🔧 Troubleshooting Guide

## Quick Diagnostics

```powershell
# Run complete diagnostics
.\Diagnose-AdobeAutomation.ps1 -Full

# Quick health check
.\Diagnose-AdobeAutomation.ps1 -Quick
```

## Common Issues and Solutions

### 1. Authentication Failures

#### Issue: JWT Token Generation Fails

**Symptoms:**
- Error: "Unable to generate JWT token"
- 401 Unauthorized responses from Adobe API

**Diagnosis:**
```powershell
# Check certificate
Get-ChildItem Cert:\LocalMachine\My | Where-Object {$_.Subject -match "Adobe"}

# Test private key access
Test-PrivateKeyAccess -CertThumbprint "YOUR_THUMBPRINT"

# Verify certificate expiration
$cert = Get-Item Cert:\LocalMachine\My\YOUR_THUMBPRINT
if ($cert.NotAfter -lt (Get-Date)) {
    Write-Warning "Certificate has expired!"
}
```

**Solutions:**

1. **Certificate Issues:**
```powershell
# Re-import certificate with private key
$pfxPath = "C:\Certs\adobe-cert.pfx"
$password = Read-Host -AsSecureString "Enter PFX password"
Import-PfxCertificate -FilePath $pfxPath -CertStoreLocation Cert:\LocalMachine\My -Password $password

# Grant private key access
$cert = Get-ChildItem Cert:\LocalMachine\My | Where-Object {$_.Subject -match "Adobe"}
$keyPath = "C:\ProgramData\Microsoft\Crypto\RSA\MachineKeys\$($cert.PrivateKey.CspKeyContainerInfo.UniqueKeyContainerName)"
icacls $keyPath /grant "IIS_IUSRS:R"
```

2. **Time Sync Issues:**
```powershell
# Check system time
w32tm /query /status

# Force time sync
w32tm /resync /force
```

3. **Configuration Issues:**
```powershell
# Validate configuration
Test-AdobeConfiguration -ConfigPath "config.json"

# Regenerate configuration
New-AdobeConfiguration -Interactive
```

#### Issue: Access Token Exchange Fails

**Symptoms:**
- Error: "Failed to exchange JWT for access token"
- Invalid client credentials error

**Solutions:**

```python
# Python diagnostic script
import jwt
import json
from datetime import datetime

def diagnose_jwt_issues(jwt_token, public_key_path):
    """Diagnose JWT token issues"""
    try:
        # Decode without verification first
        unverified = jwt.decode(jwt_token, options={"verify_signature": False})
        print("JWT Claims:")
        print(json.dumps(unverified, indent=2))

        # Check expiration
        exp = datetime.fromtimestamp(unverified['exp'])
        if exp < datetime.utcnow():
            print("ERROR: Token has expired!")

        # Verify with public key
        with open(public_key_path, 'r') as f:
            public_key = f.read()

        verified = jwt.decode(jwt_token, public_key, algorithms=['RS256'])
        print("SUCCESS: Token signature valid")

    except Exception as e:
        print(f"ERROR: {str(e)}")
```

### 2. API Rate Limiting

#### Issue: 429 Too Many Requests

**Symptoms:**
- Frequent 429 errors
- "Rate limit exceeded" messages
- Slow processing of bulk operations

**Diagnosis:**
```powershell
# Check current rate limit status
$headers = @{
    'Authorization' = "Bearer $accessToken"
    'X-Api-Key' = $clientId
}
$response = Invoke-WebRequest -Uri "https://usermanagement.adobe.io/v2/usermanagement/users/$orgId" `
    -Headers $headers -Method Head

Write-Host "Rate Limit Remaining: $($response.Headers['X-Rate-Limit-Remaining'])"
Write-Host "Rate Limit Reset: $($response.Headers['X-Rate-Limit-Reset'])"
```

**Solutions:**

1. **Implement Exponential Backoff:**
```powershell
function Invoke-AdobeAPIWithBackoff {
    param(
        [string]$Uri,
        [hashtable]$Headers,
        [int]$MaxRetries = 5
    )

    $attempt = 0
    $baseDelay = 1

    while ($attempt -lt $MaxRetries) {
        try {
            $response = Invoke-RestMethod -Uri $Uri -Headers $Headers
            return $response
        }
        catch {
            if ($_.Exception.Response.StatusCode -eq 429) {
                $retryAfter = $_.Exception.Response.Headers['Retry-After']
                if ($retryAfter) {
                    Start-Sleep -Seconds $retryAfter
                } else {
                    $delay = $baseDelay * [Math]::Pow(2, $attempt)
                    Start-Sleep -Seconds $delay
                }
                $attempt++
            } else {
                throw
            }
        }
    }
    throw "Max retries exceeded"
}
```

2. **Implement Request Batching:**
```python
# Batch API requests
import asyncio
from typing import List
import aiohttp

class BatchProcessor:
    def __init__(self, batch_size=100, delay_between_batches=1):
        self.batch_size = batch_size
        self.delay = delay_between_batches

    async def process_users(self, users: List[dict], operation):
        """Process users in batches"""
        results = []

        for i in range(0, len(users), self.batch_size):
            batch = users[i:i + self.batch_size]

            # Process batch
            batch_results = await asyncio.gather(*[
                operation(user) for user in batch
            ])
            results.extend(batch_results)

            # Delay between batches
            if i + self.batch_size < len(users):
                await asyncio.sleep(self.delay)

        return results
```

### 3. User Provisioning Failures

#### Issue: Users Not Created in Adobe

**Symptoms:**
- Users exist in AD but not in Adobe
- "User already exists" errors
- Partial user creation

**Diagnosis:**
```powershell
# Check user sync status
function Test-UserSyncStatus {
    param([string]$Email)

    $adUser = Get-ADUser -Filter "UserPrincipalName -eq '$Email'"
    $adobeUser = Get-AdobeUser -Email $Email

    return @{
        ExistsInAD = ($adUser -ne $null)
        ExistsInAdobe = ($adobeUser -ne $null)
        ADEnabled = $adUser.Enabled
        AdobeStatus = $adobeUser.status
        SyncRequired = ($adUser -ne $null -and $adobeUser -eq $null)
    }
}
```

**Solutions:**

1. **Force User Sync:**
```powershell
function Sync-SingleUser {
    param([string]$Email)

    $status = Test-UserSyncStatus -Email $Email

    if ($status.SyncRequired) {
        $adUser = Get-ADUser -Filter "UserPrincipalName -eq '$Email'" -Properties *

        $result = New-AdobeUser `
            -Email $Email `
            -FirstName $adUser.GivenName `
            -LastName $adUser.Surname `
            -Country "US" `
            -Force

        if ($result.success) {
            Write-Host "User synced successfully" -ForegroundColor Green
        } else {
            Write-Error "Sync failed: $($result.error)"
        }
    }
}
```

2. **Bulk Remediation:**
```powershell
# Find and fix out-of-sync users
$adUsers = Get-ADGroupMember -Identity "Adobe-Users" | Get-ADUser -Properties UserPrincipalName
$adobeUsers = Get-AllAdobeUsers

$adobeEmails = $adobeUsers | ForEach-Object { $_.email }
$missingSyncUsers = $adUsers | Where-Object {
    $_.UserPrincipalName -notin $adobeEmails
}

foreach ($user in $missingSyncUsers) {
    Write-Host "Syncing missing user: $($user.UserPrincipalName)"
    Sync-SingleUser -Email $user.UserPrincipalName
    Start-Sleep -Seconds 1  # Rate limiting
}
```

### 4. License Assignment Issues

#### Issue: Licenses Not Being Assigned

**Symptoms:**
- Users created but no products assigned
- "No licenses available" errors
- License count mismatches

**Diagnosis:**
```powershell
# Check license availability
function Get-LicenseAvailability {
    $products = Get-AdobeProducts

    $availability = @()
    foreach ($product in $products) {
        $availability += [PSCustomObject]@{
            Product = $product.name
            Total = $product.totalLicenses
            Used = $product.usedLicenses
            Available = $product.totalLicenses - $product.usedLicenses
            Percentage = [math]::Round(($product.usedLicenses / $product.totalLicenses) * 100, 2)
        }
    }

    return $availability | Format-Table -AutoSize
}
```

**Solutions:**

1. **Reclaim Unused Licenses:**
```powershell
# Find and reclaim inactive licenses
function Reclaim-InactiveLicenses {
    param(
        [int]$InactiveDays = 90
    )

    $cutoffDate = (Get-Date).AddDays(-$InactiveDays)
    $allUsers = Get-AllAdobeUsers

    $inactiveUsers = $allUsers | Where-Object {
        $_.lastLogin -lt $cutoffDate -and
        $_.products.Count -gt 0
    }

    foreach ($user in $inactiveUsers) {
        Write-Host "Reclaiming licenses from inactive user: $($user.email)"

        foreach ($product in $user.products) {
            Remove-AdobeLicense -Email $user.email -Product $product
        }
    }

    return @{
        UsersProcessed = $inactiveUsers.Count
        LicensesReclaimed = ($inactiveUsers | Measure-Object -Property products -Sum).Sum
    }
}
```

2. **License Queue System:**
```python
# License queue manager
import queue
import threading
import time

class LicenseQueueManager:
    def __init__(self):
        self.pending_queue = queue.Queue()
        self.retry_queue = queue.Queue()
        self.running = False

    def add_request(self, user_email, product):
        """Add license request to queue"""
        self.pending_queue.put({
            'email': user_email,
            'product': product,
            'timestamp': time.time(),
            'attempts': 0
        })

    def process_queue(self):
        """Process pending license assignments"""
        self.running = True

        while self.running:
            try:
                # Check for available licenses
                if self.check_license_availability():
                    request = self.pending_queue.get(timeout=1)
                    success = self.assign_license(request)

                    if not success and request['attempts'] < 3:
                        request['attempts'] += 1
                        self.retry_queue.put(request)
                else:
                    # Wait for licenses to become available
                    time.sleep(60)

            except queue.Empty:
                # Move retry items back to pending
                while not self.retry_queue.empty():
                    self.pending_queue.put(self.retry_queue.get())
                time.sleep(5)
```

### 5. Performance Issues

#### Issue: Slow Script Execution

**Symptoms:**
- Scripts taking longer than expected
- Timeouts during bulk operations
- High memory usage

**Diagnosis:**
```powershell
# Performance profiling
Measure-Command {
    # Your operation here
    Get-AllAdobeUsers
} | Select-Object TotalSeconds, TotalMilliseconds

# Memory usage
[System.GC]::GetTotalMemory($false) / 1MB
```

**Solutions:**

1. **Parallel Processing:**
```powershell
# Parallel user processing
$users = Get-Content "users.csv" | ConvertFrom-Csv

$users | ForEach-Object -Parallel {
    $user = $_
    New-AdobeUser -Email $user.Email -FirstName $user.FirstName -LastName $user.LastName
} -ThrottleLimit 10
```

2. **Connection Pooling:**
```python
# Connection pool for API calls
import aiohttp
import asyncio

class APIConnectionPool:
    def __init__(self, pool_size=20):
        self.connector = aiohttp.TCPConnector(
            limit=pool_size,
            limit_per_host=pool_size,
            ttl_dns_cache=300
        )
        self.session = None

    async def __aenter__(self):
        self.session = aiohttp.ClientSession(connector=self.connector)
        return self

    async def __aexit__(self, exc_type, exc_val, exc_tb):
        await self.session.close()

    async def make_request(self, url, **kwargs):
        async with self.session.get(url, **kwargs) as response:
            return await response.json()
```

### 6. Database Connection Issues

#### Issue: SQL Connection Timeouts

**Symptoms:**
- "Connection timeout expired" errors
- Intermittent database failures
- Slow query performance

**Solutions:**

```powershell
# Connection string with retry logic
$connectionString = @"
Server=sql-server.company.com;
Database=AdobeAutomation;
Integrated Security=True;
Connection Timeout=30;
ConnectRetryCount=3;
ConnectRetryInterval=10;
Application Name=Adobe Automation;
"@

# Test connection with detailed diagnostics
function Test-DatabaseConnection {
    param([string]$ConnectionString)

    $connection = New-Object System.Data.SqlClient.SqlConnection($ConnectionString)

    try {
        $stopwatch = [System.Diagnostics.Stopwatch]::StartNew()
        $connection.Open()
        $stopwatch.Stop()

        $command = $connection.CreateCommand()
        $command.CommandText = "SELECT @@VERSION"
        $version = $command.ExecuteScalar()

        return @{
            Success = $true
            ConnectionTime = $stopwatch.ElapsedMilliseconds
            ServerVersion = $version
            State = $connection.State
        }
    }
    catch {
        return @{
            Success = $false
            Error = $_.Exception.Message
            InnerError = $_.Exception.InnerException?.Message
        }
    }
    finally {
        $connection.Close()
    }
}
```

### 7. Active Directory Issues

#### Issue: AD Sync Failures

**Symptoms:**
- Users not found in AD
- Group membership not updating
- Authentication failures

**Solutions:**

```powershell
# AD connectivity test
function Test-ADConnectivity {
    $tests = @()

    # Test domain controller connectivity
    $dc = Get-ADDomainController
    $tests += @{
        Test = "DC Connectivity"
        Result = Test-NetConnection -ComputerName $dc.HostName -Port 389
    }

    # Test LDAPS
    $tests += @{
        Test = "LDAPS"
        Result = Test-NetConnection -ComputerName $dc.HostName -Port 636
    }

    # Test authentication
    try {
        $user = Get-ADUser -Identity $env:USERNAME
        $tests += @{
            Test = "Authentication"
            Result = "Success"
            User = $user.DistinguishedName
        }
    }
    catch {
        $tests += @{
            Test = "Authentication"
            Result = "Failed"
            Error = $_.Exception.Message
        }
    }

    return $tests
}

# Fix group membership
function Repair-GroupMembership {
    param(
        [string]$GroupName = "Adobe-Users"
    )

    $group = Get-ADGroup -Identity $GroupName
    $members = Get-ADGroupMember -Identity $group

    $adobeUsers = Get-AllAdobeUsers
    $adobeEmails = $adobeUsers | ForEach-Object { $_.email }

    # Add missing users to AD group
    foreach ($email in $adobeEmails) {
        $adUser = Get-ADUser -Filter "UserPrincipalName -eq '$email'" -ErrorAction SilentlyContinue

        if ($adUser -and $adUser.DistinguishedName -notin $members.DistinguishedName) {
            Add-ADGroupMember -Identity $group -Members $adUser
            Write-Host "Added $email to $GroupName" -ForegroundColor Green
        }
    }
}
```

### 8. Certificate Issues

#### Issue: Certificate Errors

**Symptoms:**
- SSL/TLS handshake failures
- Certificate validation errors
- Expired certificate warnings

**Solutions:**

```powershell
# Certificate diagnostic tool
function Diagnose-Certificates {
    $issues = @()

    # Check all certificates
    $certs = Get-ChildItem Cert:\LocalMachine\My

    foreach ($cert in $certs) {
        # Check expiration
        if ($cert.NotAfter -lt (Get-Date).AddDays(30)) {
            $issues += @{
                Type = "Expiring Soon"
                Certificate = $cert.Subject
                ExpiresIn = ($cert.NotAfter - (Get-Date)).Days
            }
        }

        # Check private key
        if ($cert.HasPrivateKey) {
            try {
                $key = [System.Security.Cryptography.X509Certificates.RSACertificateExtensions]::GetRSAPrivateKey($cert)
                if ($null -eq $key) {
                    $issues += @{
                        Type = "Private Key Issue"
                        Certificate = $cert.Subject
                        Error = "Cannot access private key"
                    }
                }
            }
            catch {
                $issues += @{
                    Type = "Private Key Issue"
                    Certificate = $cert.Subject
                    Error = $_.Exception.Message
                }
            }
        }

        # Check trust chain
        $chain = New-Object System.Security.Cryptography.X509Certificates.X509Chain
        if (!$chain.Build($cert)) {
            $issues += @{
                Type = "Trust Chain Issue"
                Certificate = $cert.Subject
                Error = $chain.ChainStatus | ForEach-Object { $_.StatusInformation }
            }
        }
    }

    return $issues
}

# Fix certificate permissions
function Repair-CertificatePermissions {
    param([string]$Thumbprint)

    $cert = Get-Item Cert:\LocalMachine\My\$Thumbprint
    $keyPath = "C:\ProgramData\Microsoft\Crypto\RSA\MachineKeys\$($cert.PrivateKey.CspKeyContainerInfo.UniqueKeyContainerName)"

    # Set proper permissions
    $acl = Get-Acl $keyPath
    $permission = "NETWORK SERVICE", "Read", "Allow"
    $accessRule = New-Object System.Security.AccessControl.FileSystemAccessRule $permission
    $acl.SetAccessRule($accessRule)
    Set-Acl $keyPath $acl

    Write-Host "Permissions fixed for certificate $Thumbprint" -ForegroundColor Green
}
```

## Diagnostic Scripts

### Complete System Diagnostic

```powershell
# Diagnose-AdobeAutomation.ps1
function Invoke-CompleteDiagnostic {
    Write-Host "Starting Adobe Automation Diagnostic" -ForegroundColor Cyan
    Write-Host "=" * 50

    $results = @{
        Timestamp = Get-Date
        Tests = @()
    }

    # Test 1: Configuration
    Write-Host "Testing configuration..." -NoNewline
    $configTest = Test-AdobeConfiguration
    $results.Tests += @{
        Name = "Configuration"
        Result = $configTest.Success
        Details = $configTest
    }
    Write-Host $(if ($configTest.Success) { " PASS" } else { " FAIL" }) -ForegroundColor $(if ($configTest.Success) { "Green" } else { "Red" })

    # Test 2: Adobe API
    Write-Host "Testing Adobe API..." -NoNewline
    $apiTest = Test-AdobeAPI
    $results.Tests += @{
        Name = "Adobe API"
        Result = $apiTest.Success
        Details = $apiTest
    }
    Write-Host $(if ($apiTest.Success) { " PASS" } else { " FAIL" }) -ForegroundColor $(if ($apiTest.Success) { "Green" } else { "Red" })

    # Test 3: Database
    Write-Host "Testing database..." -NoNewline
    $dbTest = Test-DatabaseConnection
    $results.Tests += @{
        Name = "Database"
        Result = $dbTest.Success
        Details = $dbTest
    }
    Write-Host $(if ($dbTest.Success) { " PASS" } else { " FAIL" }) -ForegroundColor $(if ($dbTest.Success) { "Green" } else { "Red" })

    # Test 4: Active Directory
    Write-Host "Testing Active Directory..." -NoNewline
    $adTest = Test-ADConnectivity
    $results.Tests += @{
        Name = "Active Directory"
        Result = ($adTest | Where-Object { $_.Result -ne "Success" }).Count -eq 0
        Details = $adTest
    }
    Write-Host $(if ($results.Tests[-1].Result) { " PASS" } else { " FAIL" }) -ForegroundColor $(if ($results.Tests[-1].Result) { "Green" } else { "Red" })

    # Test 5: Certificates
    Write-Host "Testing certificates..." -NoNewline
    $certIssues = Diagnose-Certificates
    $results.Tests += @{
        Name = "Certificates"
        Result = $certIssues.Count -eq 0
        Details = $certIssues
    }
    Write-Host $(if ($certIssues.Count -eq 0) { " PASS" } else { " FAIL" }) -ForegroundColor $(if ($certIssues.Count -eq 0) { "Green" } else { "Red" })

    # Generate report
    $results | ConvertTo-Json -Depth 10 | Out-File "diagnostic_$(Get-Date -Format 'yyyyMMdd_HHmmss').json"

    # Summary
    Write-Host "`nDiagnostic Summary:" -ForegroundColor Cyan
    $passed = ($results.Tests | Where-Object { $_.Result }).Count
    $failed = ($results.Tests | Where-Object { -not $_.Result }).Count

    Write-Host "  Passed: $passed" -ForegroundColor Green
    Write-Host "  Failed: $failed" -ForegroundColor Red

    if ($failed -gt 0) {
        Write-Host "`nFailed Tests:" -ForegroundColor Yellow
        $results.Tests | Where-Object { -not $_.Result } | ForEach-Object {
            Write-Host "  - $($_.Name): $($_.Details)" -ForegroundColor Yellow
        }
    }

    return $results
}

# Run diagnostic
Invoke-CompleteDiagnostic
```

## Emergency Procedures

### Complete System Reset

```powershell
# WARNING: This will reset the entire system
function Reset-AdobeAutomation {
    param(
        [switch]$Force,
        [switch]$BackupFirst
    )

    if (!$Force) {
        $confirm = Read-Host "This will reset the entire system. Type 'RESET' to confirm"
        if ($confirm -ne 'RESET') {
            Write-Host "Reset cancelled" -ForegroundColor Yellow
            return
        }
    }

    if ($BackupFirst) {
        Write-Host "Creating backup..." -ForegroundColor Yellow
        Backup-AdobeConfiguration -Path "C:\Backups\emergency_backup_$(Get-Date -Format 'yyyyMMdd_HHmmss').zip"
    }

    Write-Host "Starting system reset..." -ForegroundColor Red

    # Clear caches
    Clear-AdobeCache
    Clear-TokenCache

    # Reset configuration
    Remove-Item "C:\AdobeAutomation\Config\*" -Force -Recurse
    New-AdobeConfiguration -Default

    # Restart services
    Restart-Service "Adobe Automation Service"
    Restart-Service "Adobe Sync Service"

    # Re-authenticate
    Initialize-AdobeAuthentication

    # Verify
    $diagnostic = Invoke-CompleteDiagnostic

    if (($diagnostic.Tests | Where-Object { -not $_.Result }).Count -eq 0) {
        Write-Host "System reset successful!" -ForegroundColor Green
    } else {
        Write-Host "System reset completed with issues. Review diagnostic report." -ForegroundColor Yellow
    }
}
```

## Support Contacts

| Issue Type | Contact | Response Time |
|------------|---------|---------------|
| Critical Production Issue | security-team@company.com | 15 minutes |
| Authentication Issues | identity-team@company.com | 1 hour |
| License Issues | procurement@company.com | 4 hours |
| General Support | it-helpdesk@company.com | 24 hours |

## Additional Resources

- [Adobe API Documentation](https://adobe-apiplatform.github.io/umapi-documentation/)
- [PowerShell Best Practices](https://docs.microsoft.com/powershell/scripting/)
- [Python Async Programming](https://docs.python.org/3/library/asyncio.html)
- Internal Wiki: https://wiki.company.com/adobe-automation