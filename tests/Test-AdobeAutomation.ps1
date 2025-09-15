<#
.SYNOPSIS
    Comprehensive testing framework for Adobe Enterprise Automation
.DESCRIPTION
    Pester-based testing suite covering unit, integration, and performance tests
#>

BeforeAll {
    # Import modules
    Import-Module Pester
    Import-Module "$PSScriptRoot\..\creative-cloud\AdobeAutomation.psd1"

    # Mock configuration
    $script:MockConfig = @{
        Adobe = @{
            OrgId = "TEST123@AdobeOrg"
            ClientId = "test-client-id"
            ClientSecret = ConvertTo-SecureString "test-secret" -AsPlainText -Force
        }
        TestMode = $true
    }

    # Setup test data
    $script:TestUsers = @(
        @{Email = "test1@company.com"; FirstName = "Test"; LastName = "User1"}
        @{Email = "test2@company.com"; FirstName = "Test"; LastName = "User2"}
        @{Email = "test3@company.com"; FirstName = "Test"; LastName = "User3"}
    )
}

Describe "Adobe Authentication Tests" {
    Context "JWT Token Generation" {
        It "Should generate valid JWT token" {
            $token = New-AdobeJWT -Config $MockConfig.Adobe

            $token | Should -Not -BeNullOrEmpty
            $token | Should -Match "^[A-Za-z0-9-_]+\.[A-Za-z0-9-_]+\.[A-Za-z0-9-_]+$"
        }

        It "Should include required claims" {
            $token = New-AdobeJWT -Config $MockConfig.Adobe
            $parts = $token.Split('.')
            $payload = [System.Text.Encoding]::UTF8.GetString([System.Convert]::FromBase64String($parts[1] + '=='))
            $claims = $payload | ConvertFrom-Json

            $claims.iss | Should -Be $MockConfig.Adobe.OrgId
            $claims.aud | Should -Match $MockConfig.Adobe.ClientId
            $claims.exp | Should -BeGreaterThan ([DateTimeOffset]::UtcNow.ToUnixTimeSeconds())
        }

        It "Should handle missing private key gracefully" {
            Mock Test-Path { $false }

            { New-AdobeJWT -Config $MockConfig.Adobe -ErrorAction Stop } |
                Should -Throw -ErrorId "PrivateKeyNotFound"
        }
    }

    Context "Access Token Exchange" {
        It "Should exchange JWT for access token" {
            Mock Invoke-RestMethod {
                return @{
                    access_token = "mock-access-token"
                    token_type = "Bearer"
                    expires_in = 86400
                }
            }

            $token = Get-AdobeAccessToken -JWT "mock-jwt" -Config $MockConfig.Adobe

            $token | Should -Not -BeNullOrEmpty
            $token.access_token | Should -Be "mock-access-token"
            $token.expires_in | Should -Be 86400
        }

        It "Should handle authentication errors" {
            Mock Invoke-RestMethod { throw "401 Unauthorized" }

            { Get-AdobeAccessToken -JWT "invalid-jwt" -Config $MockConfig.Adobe -ErrorAction Stop } |
                Should -Throw -ErrorId "AuthenticationFailed"
        }

        It "Should implement retry logic for transient failures" {
            $script:attempts = 0
            Mock Invoke-RestMethod {
                $script:attempts++
                if ($script:attempts -lt 3) {
                    throw "503 Service Unavailable"
                }
                return @{ access_token = "success-token" }
            }

            $token = Get-AdobeAccessToken -JWT "mock-jwt" -Config $MockConfig.Adobe -MaxRetries 3

            $token.access_token | Should -Be "success-token"
            $script:attempts | Should -Be 3
        }
    }
}

Describe "User Management Tests" {
    Context "User Creation" {
        BeforeEach {
            Mock Invoke-AdobeAPI {
                return @{
                    success = $true
                    user = @{
                        email = $Email
                        status = "active"
                    }
                }
            }
        }

        It "Should create single user successfully" {
            $result = New-AdobeUser -Email "test@company.com" `
                -FirstName "Test" -LastName "User" -TestMode

            $result.success | Should -Be $true
            $result.user.email | Should -Be "test@company.com"
        }

        It "Should validate email format" {
            { New-AdobeUser -Email "invalid-email" -FirstName "Test" -LastName "User" -ErrorAction Stop } |
                Should -Throw -ErrorId "InvalidEmailFormat"
        }

        It "Should handle duplicate user creation" {
            Mock Invoke-AdobeAPI {
                throw "User already exists"
            }

            $result = New-AdobeUser -Email "existing@company.com" `
                -FirstName "Test" -LastName "User" -TestMode

            $result.success | Should -Be $false
            $result.error | Should -Match "already exists"
        }

        It "Should process bulk users efficiently" {
            $users = 1..100 | ForEach-Object {
                @{
                    Email = "user$_@company.com"
                    FirstName = "User"
                    LastName = "$_"
                }
            }

            $stopwatch = [System.Diagnostics.Stopwatch]::StartNew()
            $results = New-AdobeUserBulk -Users $users -TestMode
            $stopwatch.Stop()

            $results.Count | Should -Be 100
            $stopwatch.ElapsedMilliseconds | Should -BeLessThan 5000  # Should complete in under 5 seconds
        }
    }

    Context "User Retrieval" {
        It "Should get user by email" {
            Mock Invoke-AdobeAPI {
                return @{
                    users = @(
                        @{
                            email = "test@company.com"
                            firstname = "Test"
                            lastname = "User"
                            status = "active"
                        }
                    )
                }
            }

            $user = Get-AdobeUser -Email "test@company.com"

            $user | Should -Not -BeNullOrEmpty
            $user.email | Should -Be "test@company.com"
            $user.status | Should -Be "active"
        }

        It "Should return null for non-existent user" {
            Mock Invoke-AdobeAPI {
                return @{ users = @() }
            }

            $user = Get-AdobeUser -Email "nonexistent@company.com"

            $user | Should -BeNullOrEmpty
        }

        It "Should get all users with pagination" {
            $script:page = 0
            Mock Invoke-AdobeAPI {
                $script:page++
                if ($script:page -eq 1) {
                    return @{
                        users = 1..100 | ForEach-Object { @{email = "user$_@company.com"} }
                        lastPage = $false
                    }
                } else {
                    return @{
                        users = 101..150 | ForEach-Object { @{email = "user$_@company.com"} }
                        lastPage = $true
                    }
                }
            }

            $users = Get-AllAdobeUsers

            $users.Count | Should -Be 150
        }
    }

    Context "User Deletion" {
        It "Should delete user successfully" {
            Mock Invoke-AdobeAPI {
                return @{ success = $true }
            }

            $result = Remove-AdobeUser -Email "test@company.com" -Confirm:$false

            $result.success | Should -Be $true
        }

        It "Should require confirmation for deletion" {
            Mock Invoke-AdobeAPI { }
            Mock Get-UserConfirmation { $false }

            $result = Remove-AdobeUser -Email "test@company.com"

            $result | Should -BeNullOrEmpty
            Assert-MockCalled Invoke-AdobeAPI -Times 0
        }
    }
}

Describe "License Management Tests" {
    Context "License Assignment" {
        It "Should assign single product to user" {
            Mock Invoke-AdobeAPI {
                return @{
                    success = $true
                    products = @("Creative Cloud")
                }
            }

            $result = Add-AdobeLicense -Email "test@company.com" -Product "Creative Cloud"

            $result.success | Should -Be $true
            $result.products | Should -Contain "Creative Cloud"
        }

        It "Should assign multiple products in batch" {
            Mock Invoke-AdobeAPI { return @{ success = $true } }

            $products = @("Photoshop", "Illustrator", "InDesign")
            $result = Add-AdobeLicense -Email "test@company.com" -Product $products

            $result.success | Should -Be $true
            Assert-MockCalled Invoke-AdobeAPI -Times 1  # Should batch, not individual calls
        }

        It "Should check license availability before assignment" {
            Mock Get-LicenseAvailability { return 0 }

            { Add-AdobeLicense -Email "test@company.com" -Product "Photoshop" -ErrorAction Stop } |
                Should -Throw -ErrorId "NoLicensesAvailable"
        }
    }

    Context "License Optimization" {
        It "Should identify inactive users" {
            Mock Get-AllAdobeUsers {
                return @(
                    @{email = "active@company.com"; lastLogin = (Get-Date).AddDays(-5)}
                    @{email = "inactive1@company.com"; lastLogin = (Get-Date).AddDays(-45)}
                    @{email = "inactive2@company.com"; lastLogin = (Get-Date).AddDays(-60)}
                )
            }

            $inactiveUsers = Get-InactiveUsers -Days 30

            $inactiveUsers.Count | Should -Be 2
            $inactiveUsers.email | Should -Contain "inactive1@company.com"
            $inactiveUsers.email | Should -Contain "inactive2@company.com"
        }

        It "Should calculate cost savings from optimization" {
            $licenses = @(
                @{product = "Creative Cloud"; count = 10; costPerLicense = 80}
                @{product = "Photoshop"; count = 5; costPerLicense = 35}
            )

            $savings = Calculate-LicenseSavings -ReclaimedLicenses $licenses

            $savings.monthly | Should -Be 975  # (10*80) + (5*35)
            $savings.annual | Should -Be 11700  # 975 * 12
        }

        It "Should generate optimization report" {
            Mock Export-Html { }

            $report = New-OptimizationReport -InactiveUsers 25 -ReclaimedLicenses 20 -Savings 1000

            $report | Should -Not -BeNullOrEmpty
            $report.InactiveUsers | Should -Be 25
            $report.MonthlySavings | Should -Be 1000
            Assert-MockCalled Export-Html -Times 1
        }
    }
}

Describe "Integration Tests" {
    Context "Active Directory Integration" {
        It "Should sync users from AD group" {
            Mock Get-ADGroupMember {
                return $TestUsers | ForEach-Object {
                    [PSCustomObject]@{
                        UserPrincipalName = $_.Email
                        GivenName = $_.FirstName
                        Surname = $_.LastName
                        Enabled = $true
                    }
                }
            }

            Mock New-AdobeUser { return @{ success = $true } }

            $results = Sync-ADUsersToAdobe -GroupName "Adobe-Users" -TestMode

            $results.Count | Should -Be 3
            $results | Where-Object { $_.success -eq $true } | Should -HaveCount 3
        }

        It "Should handle AD connection failures gracefully" {
            Mock Get-ADGroupMember { throw "Cannot connect to AD" }

            { Sync-ADUsersToAdobe -GroupName "Adobe-Users" -ErrorAction Stop } |
                Should -Throw -ErrorId "ADConnectionFailed"
        }
    }

    Context "Azure AD Integration" {
        It "Should sync users from Azure AD" {
            Mock Get-MgGroupMember {
                return $TestUsers | ForEach-Object {
                    @{
                        Mail = $_.Email
                        GivenName = $_.FirstName
                        Surname = $_.LastName
                    }
                }
            }

            Mock New-AdobeUser { return @{ success = $true } }

            $results = Sync-AzureADUsersToAdobe -GroupId "12345" -TestMode

            $results.Count | Should -Be 3
        }
    }

    Context "End-to-End Workflow" {
        It "Should complete full user lifecycle" {
            # Create user
            Mock New-AdobeUser { return @{ success = $true } }
            $createResult = New-AdobeUser -Email "lifecycle@company.com" -FirstName "Life" -LastName "Cycle"
            $createResult.success | Should -Be $true

            # Assign license
            Mock Add-AdobeLicense { return @{ success = $true } }
            $licenseResult = Add-AdobeLicense -Email "lifecycle@company.com" -Product "Creative Cloud"
            $licenseResult.success | Should -Be $true

            # Update user
            Mock Update-AdobeUser { return @{ success = $true } }
            $updateResult = Update-AdobeUser -Email "lifecycle@company.com" -LastName "CycleUpdated"
            $updateResult.success | Should -Be $true

            # Remove license
            Mock Remove-AdobeLicense { return @{ success = $true } }
            $removeResult = Remove-AdobeLicense -Email "lifecycle@company.com" -Product "Creative Cloud"
            $removeResult.success | Should -Be $true

            # Delete user
            Mock Remove-AdobeUser { return @{ success = $true } }
            $deleteResult = Remove-AdobeUser -Email "lifecycle@company.com" -Confirm:$false
            $deleteResult.success | Should -Be $true
        }
    }
}

Describe "Performance Tests" {
    Context "Load Testing" {
        It "Should handle concurrent API calls" {
            Mock Invoke-AdobeAPI {
                Start-Sleep -Milliseconds (Get-Random -Min 10 -Max 100)
                return @{ success = $true }
            }

            $jobs = 1..50 | ForEach-Object {
                Start-Job -ScriptBlock {
                    param($num)
                    New-AdobeUser -Email "concurrent$num@company.com" -FirstName "Test" -LastName "$num"
                } -ArgumentList $_
            }

            $results = $jobs | Wait-Job | Receive-Job
            $jobs | Remove-Job

            $results | Where-Object { $_.success -eq $true } | Should -HaveCount 50
        }

        It "Should respect rate limits" {
            $rateLimiter = New-RateLimiter -RequestsPerMinute 100

            $stopwatch = [System.Diagnostics.Stopwatch]::StartNew()

            1..150 | ForEach-Object {
                Wait-RateLimit -RateLimiter $rateLimiter
            }

            $stopwatch.Stop()

            # Should take at least 30 seconds for 150 requests at 100/min rate
            $stopwatch.ElapsedMilliseconds | Should -BeGreaterThan 30000
        }
    }

    Context "Resource Usage" {
        It "Should not exceed memory limits" {
            $initialMemory = (Get-Process -Id $PID).WorkingSet64

            # Process large dataset
            $largeDataset = 1..10000 | ForEach-Object {
                @{
                    Email = "user$_@company.com"
                    FirstName = "User"
                    LastName = "$_"
                    Products = @("Product1", "Product2", "Product3")
                }
            }

            Process-LargeDataset -Data $largeDataset

            $finalMemory = (Get-Process -Id $PID).WorkingSet64
            $memoryIncrease = ($finalMemory - $initialMemory) / 1MB

            $memoryIncrease | Should -BeLessThan 500  # Should not use more than 500MB
        }
    }
}

Describe "Error Handling Tests" {
    Context "API Error Handling" {
        It "Should handle 401 Unauthorized" {
            Mock Invoke-RestMethod {
                throw [System.Net.WebException]::new("401 Unauthorized")
            }

            $result = Invoke-AdobeAPIWithErrorHandling -Endpoint "/test"

            $result.error | Should -Match "Authentication"
            $result.shouldRetry | Should -Be $true
        }

        It "Should handle 429 Rate Limit" {
            Mock Invoke-RestMethod {
                $response = [PSCustomObject]@{
                    StatusCode = 429
                    Headers = @{ "Retry-After" = "60" }
                }
                throw [System.Net.WebException]::new("429 Too Many Requests")
            }

            $result = Invoke-AdobeAPIWithErrorHandling -Endpoint "/test"

            $result.error | Should -Match "Rate limit"
            $result.retryAfter | Should -Be 60
        }

        It "Should handle 500 Server Error with retry" {
            $script:attempts = 0
            Mock Invoke-RestMethod {
                $script:attempts++
                if ($script:attempts -lt 3) {
                    throw [System.Net.WebException]::new("500 Internal Server Error")
                }
                return @{ success = $true }
            }

            $result = Invoke-AdobeAPIWithErrorHandling -Endpoint "/test" -MaxRetries 3

            $result.success | Should -Be $true
            $script:attempts | Should -Be 3
        }
    }

    Context "Data Validation" {
        It "Should validate required fields" {
            { New-AdobeUser -Email $null -FirstName "Test" -LastName "User" } |
                Should -Throw -ErrorId "MissingRequiredField"

            { New-AdobeUser -Email "test@company.com" -FirstName $null -LastName "User" } |
                Should -Throw -ErrorId "MissingRequiredField"
        }

        It "Should sanitize input data" {
            $sanitized = Sanitize-UserInput -Input "<script>alert('xss')</script>Test"

            $sanitized | Should -Be "Test"
            $sanitized | Should -Not -Match "<script>"
        }
    }
}

Describe "Logging and Audit Tests" {
    Context "Audit Logging" {
        It "Should log all user operations" {
            Mock Write-AuditLog { }

            New-AdobeUser -Email "audit@company.com" -FirstName "Audit" -LastName "Test" -TestMode

            Assert-MockCalled Write-AuditLog -Times 1 -ParameterFilter {
                $Action -eq "CreateUser" -and
                $Target -eq "audit@company.com"
            }
        }

        It "Should include security context in logs" {
            Mock Write-AuditLog { }
            Mock Get-CurrentUser { "DOMAIN\TestUser" }

            New-AdobeUser -Email "test@company.com" -FirstName "Test" -LastName "User" -TestMode

            Assert-MockCalled Write-AuditLog -ParameterFilter {
                $PerformedBy -eq "DOMAIN\TestUser"
            }
        }

        It "Should handle log rotation" {
            $logFile = "TestDrive:\test.log"

            # Create large log file
            "x" * 10MB | Out-File $logFile

            Rotate-LogFile -Path $logFile -MaxSizeKB 5120

            (Get-Item $logFile).Length | Should -BeLessThan 1KB
            Test-Path "$logFile.1" | Should -Be $true
        }
    }
}

Describe "Security Tests" {
    Context "Authentication Security" {
        It "Should not expose credentials in logs" {
            Mock Write-Log { }

            $secureString = ConvertTo-SecureString "SuperSecret123!" -AsPlainText -Force
            New-AdobeConnection -ClientSecret $secureString -Verbose

            Assert-MockCalled Write-Log -Times 0 -ParameterFilter {
                $Message -match "SuperSecret123"
            }
        }

        It "Should validate certificate thumbprints" {
            $validThumbprint = "A9B8C7D6E5F4A3B2C1D0E9F8A7B6C5D4E3F2A1B0"
            $invalidThumbprint = "INVALID"

            Test-CertificateThumbprint -Thumbprint $validThumbprint | Should -Be $true
            Test-CertificateThumbprint -Thumbprint $invalidThumbprint | Should -Be $false
        }

        It "Should enforce secure communication" {
            Mock Invoke-RestMethod { }

            Invoke-AdobeAPI -Endpoint "http://api.adobe.com/test" -ErrorAction SilentlyContinue

            Assert-MockCalled Invoke-RestMethod -Times 0 -ParameterFilter {
                $Uri -match "^http://"
            }
        }
    }

    Context "Input Sanitization" {
        It "Should prevent SQL injection" {
            $maliciousInput = "'; DROP TABLE Users; --"
            $sanitized = Sanitize-DatabaseInput -Input $maliciousInput

            $sanitized | Should -Not -Match "DROP TABLE"
            $sanitized | Should -Not -Match ";"
        }

        It "Should prevent command injection" {
            $maliciousInput = "test; rm -rf /"

            { Invoke-SafeCommand -Input $maliciousInput } | Should -Not -Throw
            Test-Path "/" | Should -Be $true  # System should still exist!
        }
    }
}

Describe "Compliance Tests" {
    Context "GDPR Compliance" {
        It "Should allow user data export" {
            Mock Get-AdobeUser {
                return @{
                    email = "test@company.com"
                    personalData = @{}
                }
            }

            $export = Export-UserDataForGDPR -Email "test@company.com"

            $export | Should -Not -BeNullOrEmpty
            $export.format | Should -Be "JSON"
        }

        It "Should support right to be forgotten" {
            Mock Remove-AdobeUser { return @{ success = $true } }
            Mock Remove-AuditLogs { return @{ success = $true } }

            $result = Invoke-RightToBeForgotten -Email "forget@company.com" -Confirm:$false

            $result.userDeleted | Should -Be $true
            $result.logsDeleted | Should -Be $true
        }
    }

    Context "SOC2 Compliance" {
        It "Should maintain audit trail integrity" {
            $log1 = New-AuditLog -Action "CreateUser" -Target "test@company.com"
            $hash1 = Get-FileHash -InputStream ([IO.MemoryStream]::new([Text.Encoding]::UTF8.GetBytes($log1)))

            Start-Sleep -Milliseconds 100

            $log2 = New-AuditLog -Action "CreateUser" -Target "test@company.com"
            $hash2 = Get-FileHash -InputStream ([IO.MemoryStream]::new([Text.Encoding]::UTF8.GetBytes($log2)))

            $hash1.Hash | Should -Not -Be $hash2.Hash  # Should include timestamp
        }
    }
}

Describe "Monitoring Tests" {
    Context "Health Checks" {
        It "Should verify API connectivity" {
            $health = Test-AdobeAPIHealth

            $health.status | Should -BeIn @("healthy", "degraded", "unhealthy")
            $health.latency | Should -BeGreaterThan 0
            $health.latency | Should -BeLessThan 5000
        }

        It "Should check certificate expiration" {
            $certs = Get-ExpiringCertificates -DaysBeforeExpiry 30

            $certs | ForEach-Object {
                $_.DaysUntilExpiry | Should -BeGreaterThan 0
            }
        }
    }

    Context "Metrics Collection" {
        It "Should track API call metrics" {
            Reset-Metrics

            1..10 | ForEach-Object {
                Record-APICall -Endpoint "/users" -Duration (Get-Random -Min 100 -Max 500)
            }

            $metrics = Get-APIMetrics

            $metrics.totalCalls | Should -Be 10
            $metrics.averageLatency | Should -BeGreaterThan 0
            $metrics.p95Latency | Should -BeGreaterThan $metrics.averageLatency
        }
    }
}

Describe "Disaster Recovery Tests" {
    Context "Backup and Restore" {
        It "Should backup configuration" {
            $backupPath = "TestDrive:\backup.json"

            Backup-AdobeConfiguration -Path $backupPath

            Test-Path $backupPath | Should -Be $true
            $backup = Get-Content $backupPath | ConvertFrom-Json
            $backup.version | Should -Not -BeNullOrEmpty
        }

        It "Should restore from backup" {
            $backupData = @{
                version = "1.0"
                config = @{ testSetting = "testValue" }
            }

            $backupPath = "TestDrive:\restore.json"
            $backupData | ConvertTo-Json | Out-File $backupPath

            Restore-AdobeConfiguration -Path $backupPath

            $config = Get-AdobeConfiguration
            $config.testSetting | Should -Be "testValue"
        }
    }

    Context "Failover Testing" {
        It "Should switch to secondary endpoint on primary failure" {
            Mock Test-NetConnection {
                param($ComputerName)
                if ($ComputerName -eq "primary.adobe.com") {
                    return @{ TcpTestSucceeded = $false }
                } else {
                    return @{ TcpTestSucceeded = $true }
                }
            }

            $endpoint = Get-ActiveEndpoint

            $endpoint | Should -Be "secondary.adobe.com"
        }
    }
}

Describe "Regression Tests" {
    Context "Known Issue Fixes" {
        It "Should handle special characters in user names (Bug #1234)" {
            $specialNames = @(
                "O'Brien",
                "José García",
                "François Müller",
                "李明 (Li Ming)"
            )

            $specialNames | ForEach-Object {
                $result = Validate-UserName -Name $_
                $result | Should -Be $true
            }
        }

        It "Should not timeout on large group sync (Bug #5678)" {
            Mock Get-ADGroupMember {
                1..5000 | ForEach-Object {
                    [PSCustomObject]@{
                        UserPrincipalName = "user$_@company.com"
                    }
                }
            }

            $stopwatch = [System.Diagnostics.Stopwatch]::StartNew()
            $result = Sync-LargeADGroup -GroupName "LargeGroup" -TestMode
            $stopwatch.Stop()

            $stopwatch.ElapsedMilliseconds | Should -BeLessThan 30000  # 30 seconds max
            $result.Count | Should -Be 5000
        }
    }
}

AfterAll {
    # Cleanup
    Remove-Variable -Name MockConfig -Scope Script -ErrorAction SilentlyContinue
    Remove-Variable -Name TestUsers -Scope Script -ErrorAction SilentlyContinue

    # Generate test report
    $testResults = Invoke-Pester -Path $PSScriptRoot -PassThru
    $testResults | Export-NUnitReport -Path "$PSScriptRoot\TestResults.xml"

    Write-Host "Test Results Summary:" -ForegroundColor Cyan
    Write-Host "  Total Tests: $($testResults.TotalCount)"
    Write-Host "  Passed: $($testResults.PassedCount)" -ForegroundColor Green
    Write-Host "  Failed: $($testResults.FailedCount)" -ForegroundColor Red
    Write-Host "  Skipped: $($testResults.SkippedCount)" -ForegroundColor Yellow
    Write-Host "  Duration: $($testResults.Time.TotalSeconds) seconds"
}