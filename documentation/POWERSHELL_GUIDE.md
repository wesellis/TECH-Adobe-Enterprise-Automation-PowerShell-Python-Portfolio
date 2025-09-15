# PowerShell Automation Guide

## Module Installation

```powershell
# Install from PowerShell Gallery
Install-Module -Name AdobeAutomation -Force -AllowClobber

# Import module
Import-Module AdobeAutomation

# Verify installation
Get-Command -Module AdobeAutomation
```

## Core Functions

### Initialize-AdobeSession
```powershell
function Initialize-AdobeSession {
    param(
        [Parameter(Mandatory)]
        [string]$ConfigPath,

        [Parameter()]
        [switch]$UseCache
    )

    $config = Get-Content $ConfigPath | ConvertFrom-Json
    $global:AdobeSession = New-AdobeConnection @config

    if ($UseCache) {
        Enable-TokenCache -Path "$env:TEMP\adobe_token.cache"
    }

    return $global:AdobeSession
}
```

### User Provisioning Pipeline
```powershell
function Start-UserProvisioning {
    [CmdletBinding()]
    param(
        [Parameter(ValueFromPipeline)]
        [string[]]$UserEmails,

        [Parameter(Mandatory)]
        [string[]]$Products,

        [Parameter()]
        [int]$ThrottleLimit = 5
    )

    begin {
        $results = @()
        Initialize-AdobeSession -ConfigPath ".\config.json"
    }

    process {
        $UserEmails | ForEach-Object -Parallel {
            $email = $_
            try {
                # Get user from Azure AD
                $adUser = Get-AzureADUser -UserPrincipalName $email

                # Create Adobe user
                $adobeUser = New-AdobeUser -Email $email `
                    -FirstName $adUser.GivenName `
                    -LastName $adUser.Surname

                # Assign products
                foreach ($product in $using:Products) {
                    Add-AdobeProduct -Email $email -Product $product
                }

                [PSCustomObject]@{
                    Email = $email
                    Status = "Success"
                    Products = $using:Products
                }
            }
            catch {
                [PSCustomObject]@{
                    Email = $email
                    Status = "Failed"
                    Error = $_.Exception.Message
                }
            }
        } -ThrottleLimit $ThrottleLimit
    }

    end {
        return $results
    }
}
```

### License Optimization
```powershell
function Invoke-LicenseOptimization {
    param(
        [int]$InactiveDays = 30,
        [switch]$WhatIf
    )

    # Get all licensed users
    $users = Get-AdobeUsers -IncludeProducts

    # Identify inactive users
    $inactiveUsers = $users | Where-Object {
        $_.LastActive -lt (Get-Date).AddDays(-$InactiveDays)
    }

    Write-Host "Found $($inactiveUsers.Count) inactive users"

    if (-not $WhatIf) {
        foreach ($user in $inactiveUsers) {
            # Remove all products
            $user.Products | ForEach-Object {
                Remove-AdobeProduct -Email $user.Email -Product $_
                Write-Verbose "Removed $_ from $($user.Email)"
            }
        }
    }

    # Generate report
    $savings = $inactiveUsers.Count * 50  # $50 per license
    [PSCustomObject]@{
        InactiveUsers = $inactiveUsers.Count
        LicensesReclaimed = ($inactiveUsers | Measure-Object -Property Products -Sum).Sum
        EstimatedSavings = $savings
        ProcessedDate = Get-Date
    }
}
```

### Bulk Operations
```powershell
function Import-UsersFromCSV {
    param(
        [Parameter(Mandatory)]
        [string]$Path,

        [Parameter()]
        [int]$BatchSize = 100
    )

    $users = Import-Csv $Path
    $batches = [Math]::Ceiling($users.Count / $BatchSize)

    for ($i = 0; $i -lt $batches; $i++) {
        $batch = $users | Select-Object -Skip ($i * $BatchSize) -First $BatchSize

        $batchPayload = @{
            users = $batch | ForEach-Object {
                @{
                    email = $_.Email
                    firstname = $_.FirstName
                    lastname = $_.LastName
                    country = $_.Country
                    products = $_.Products -split ';'
                }
            }
        }

        Invoke-AdobeBulkOperation -Payload $batchPayload
        Write-Progress -Activity "Importing Users" `
            -Status "Batch $($i+1) of $batches" `
            -PercentComplete (($i+1)/$batches*100)
    }
}
```

### Error Handling
```powershell
function Invoke-AdobeCommand {
    param(
        [scriptblock]$Command,
        [int]$MaxRetries = 3,
        [int]$RetryDelay = 2
    )

    $attempt = 0
    $success = $false

    while (-not $success -and $attempt -lt $MaxRetries) {
        try {
            $attempt++
            $result = & $Command
            $success = $true
            return $result
        }
        catch {
            if ($attempt -eq $MaxRetries) {
                Write-Error "Failed after $MaxRetries attempts: $_"
                throw
            }

            $delay = [Math]::Pow($RetryDelay, $attempt)
            Write-Warning "Attempt $attempt failed. Retrying in $delay seconds..."
            Start-Sleep -Seconds $delay
        }
    }
}
```

### Logging
```powershell
function Write-AdobeLog {
    param(
        [Parameter(Mandatory)]
        [string]$Message,

        [Parameter()]
        [ValidateSet('Info','Warning','Error','Debug')]
        [string]$Level = 'Info',

        [Parameter()]
        [string]$LogPath = ".\logs\adobe-automation.log"
    )

    $timestamp = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
    $logEntry = "[$timestamp] [$Level] $Message"

    # Ensure log directory exists
    $logDir = Split-Path $LogPath -Parent
    if (-not (Test-Path $logDir)) {
        New-Item -ItemType Directory -Path $logDir -Force | Out-Null
    }

    # Write to log file
    Add-Content -Path $LogPath -Value $logEntry

    # Also write to console with color
    switch ($Level) {
        'Error'   { Write-Host $logEntry -ForegroundColor Red }
        'Warning' { Write-Host $logEntry -ForegroundColor Yellow }
        'Debug'   { Write-Debug $logEntry }
        default   { Write-Host $logEntry -ForegroundColor Green }
    }
}
```

### Scheduled Tasks
```powershell
# Create scheduled task for daily license optimization
$action = New-ScheduledTaskAction -Execute 'PowerShell.exe' `
    -Argument '-File "C:\Scripts\Optimize-Licenses.ps1"'

$trigger = New-ScheduledTaskTrigger -Daily -At 2AM

$settings = New-ScheduledTaskSettingsSet -StartWhenAvailable `
    -RestartCount 3 -RestartInterval (New-TimeSpan -Minutes 5)

Register-ScheduledTask -TaskName "Adobe License Optimization" `
    -Action $action `
    -Trigger $trigger `
    -Settings $settings `
    -User "SYSTEM" `
    -RunLevel Highest
```

## Advanced Patterns

### Parallel Processing
```powershell
$computers = Get-Content ".\computers.txt"

$jobs = $computers | ForEach-Object {
    Start-Job -ScriptBlock {
        param($computer)
        Install-AdobeCC -ComputerName $computer -Silent
    } -ArgumentList $_
}

# Wait for all jobs
$results = $jobs | Wait-Job | Receive-Job
$jobs | Remove-Job
```

### Pipeline Integration
```powershell
Get-ADUser -Filter {Department -eq "Marketing"} |
    Select-Object -ExpandProperty UserPrincipalName |
    New-AdobeUser -Products @("Creative Cloud", "Adobe Stock") |
    Export-Csv -Path ".\provisioning-report.csv"
```

### Custom Objects
```powershell
class AdobeUser {
    [string]$Email
    [string]$FirstName
    [string]$LastName
    [string[]]$Products
    [datetime]$Created
    [datetime]$LastActive

    AdobeUser([string]$email) {
        $this.Email = $email
        $this.Created = Get-Date
    }

    [void]AddProduct([string]$product) {
        $this.Products += $product
    }

    [bool]IsActive() {
        return ($this.LastActive -gt (Get-Date).AddDays(-30))
    }
}
```

## Testing

### Pester Tests
```powershell
Describe "Adobe User Management" {
    BeforeAll {
        Import-Module .\AdobeAutomation.psd1
        Mock Initialize-AdobeSession {}
    }

    It "Should create a new user" {
        Mock New-AdobeUser { return @{Email = "test@company.com"} }

        $result = New-AdobeUser -Email "test@company.com"
        $result.Email | Should -Be "test@company.com"
    }

    It "Should handle errors gracefully" {
        Mock New-AdobeUser { throw "API Error" }

        { New-AdobeUser -Email "test@company.com" } | Should -Throw
    }
}
```

## Performance Tips

1. **Use Jobs for Parallel Processing**
2. **Implement Caching for Frequently Accessed Data**
3. **Batch API Calls When Possible**
4. **Use Runspaces for High-Performance Scenarios**
5. **Profile Scripts to Identify Bottlenecks**

## Security Best Practices

1. **Never Store Credentials in Scripts**
2. **Use SecureString for Sensitive Data**
3. **Implement Proper RBAC**
4. **Enable Transcript Logging**
5. **Sign Scripts with Code Signing Certificate**