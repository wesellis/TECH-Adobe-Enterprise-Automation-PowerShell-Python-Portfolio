# Adobe Enterprise Automation - API Reference

## 📖 Comprehensive API Documentation

This reference covers all Adobe APIs used in the enterprise automation solutions, including authentication, endpoints, parameters, and response formats.

## Table of Contents
1. [Authentication](#authentication)
2. [Adobe User Management API](#adobe-user-management-api)
3. [Adobe Admin Console API](#adobe-admin-console-api)
4. [Adobe PDF Services API](#adobe-pdf-services-api)
5. [Adobe Analytics API](#adobe-analytics-api)
6. [Error Handling](#error-handling)
7. [Rate Limiting](#rate-limiting)
8. [Code Examples](#code-examples)

## Authentication

### JWT-based Authentication (Service Account)

All Adobe APIs use JWT (JSON Web Token) authentication for server-to-server integrations.

#### Authentication Flow
1. Generate JWT token using private key
2. Exchange JWT for access token
3. Use access token in API requests
4. Refresh token before expiration

#### JWT Token Generation (PowerShell)
```powershell
function Get-AdobeJWTToken {
    param(
        [string]$ClientId,
        [string]$TechnicalAccountId,
        [string]$OrganizationId,
        [string]$PrivateKeyPath
    )
    
    # JWT Header
    $header = @{
        alg = "RS256"
        typ = "JWT"
    } | ConvertTo-Json -Compress
    
    # JWT Payload
    $currentTime = [int]((Get-Date) - (Get-Date "1970-01-01")).TotalSeconds
    $expirationTime = $currentTime + 3600  # 1 hour
    
    $payload = @{
        iss = $OrganizationId
        sub = $TechnicalAccountId
        aud = "https://ims-na1.adobelogin.com/c/$ClientId"
        exp = $expirationTime
        iat = $currentTime
        "https://ims-na1.adobelogin.com/s/ent_user_sdk" = $true
    } | ConvertTo-Json -Compress
    
    # Base64 encode
    $encodedHeader = [Convert]::ToBase64String([Text.Encoding]::UTF8.GetBytes($header)).TrimEnd('=').Replace('+', '-').Replace('/', '_')
    $encodedPayload = [Convert]::ToBase64String([Text.Encoding]::UTF8.GetBytes($payload)).TrimEnd('=').Replace('+', '-').Replace('/', '_')
    
    # Sign with private key (requires certificate signing implementation)
    $stringToSign = "$encodedHeader.$encodedPayload"
    $signature = Sign-JWTWithPrivateKey -Data $stringToSign -PrivateKeyPath $PrivateKeyPath
    
    return "$stringToSign.$signature"
}
```

#### Access Token Exchange
```powershell
function Get-AdobeAccessToken {
    param(
        [string]$ClientId,
        [string]$ClientSecret,
        [string]$JWTToken
    )
    
    $body = @{
        client_id = $ClientId
        client_secret = $ClientSecret
        jwt_token = $JWTToken
    }
    
    $response = Invoke-RestMethod -Uri "https://ims-na1.adobelogin.com/ims/exchange/jwt" -Method POST -Body $body -ContentType "application/x-www-form-urlencoded"
    
    return @{
        AccessToken = $response.access_token
        TokenType = $response.token_type
        ExpiresIn = $response.expires_in
    }
}
```

## Adobe User Management API

Base URL: `https://usermanagement.adobe.io`

### Common Headers
```
Authorization: Bearer {access_token}
X-Api-Key: {client_id}
Content-Type: application/json
Accept: application/json
```

### Endpoints

#### 1. Create User

**POST** `/v2/usermanagement/users`

Creates a new user in the Adobe organization.

**Request Body:**
```json
{
  "users": [
    {
      "userID": "user@company.com",
      "email": "user@company.com",
      "firstname": "John",
      "lastname": "Doe",
      "country": "US"
    }
  ]
}
```

**Response:**
```json
{
  "result": "success",
  "user": {
    "userID": "user@company.com",
    "email": "user@company.com",
    "status": "active",
    "groups": [],
    "country": "US"
  }
}
```

**PowerShell Example:**
```powershell
function New-AdobeUser {
    param(
        [string]$AccessToken,
        [string]$ClientId,
        [string]$Email,
        [string]$FirstName,
        [string]$LastName,
        [string]$Country = "US"
    )
    
    $headers = @{
        "Authorization" = "Bearer $AccessToken"
        "X-Api-Key" = $ClientId
        "Content-Type" = "application/json"
    }
    
    $body = @{
        users = @(
            @{
                userID = $Email
                email = $Email
                firstname = $FirstName
                lastname = $LastName
                country = $Country
            }
        )
    } | ConvertTo-Json -Depth 3
    
    $response = Invoke-RestMethod -Uri "https://usermanagement.adobe.io/v2/usermanagement/users" -Method POST -Headers $headers -Body $body
    return $response
}
```

#### 2. Get User Information

**GET** `/v2/usermanagement/users/{userID}`

Retrieves detailed information about a specific user.

**Parameters:**
- `userID` (path): The user's email address or Adobe ID

**Response:**
```json
{
  "userID": "user@company.com",
  "email": "user@company.com",
  "firstname": "John",
  "lastname": "Doe",
  "country": "US",
  "type": "federatedID",
  "status": "active",
  "groups": [
    "Creative Cloud All Apps Users",
    "Acrobat Pro Users"
  ],
  "products": [
    "Creative Cloud All Apps",
    "Acrobat Pro DC"
  ]
}
```

#### 3. Update User

**POST** `/v2/usermanagement/users/{userID}`

Updates user information or group memberships.

**Request Body:**
```json
{
  "update": {
    "firstname": "Jane",
    "lastname": "Smith",
    "email": "jane.smith@company.com"
  }
}
```

#### 4. Remove User

**DELETE** `/v2/usermanagement/users/{userID}`

Removes a user from the organization.

**Query Parameters:**
- `deleteAccount` (boolean): Whether to delete the Adobe account entirely

#### 5. List Users

**GET** `/v2/usermanagement/users`

Retrieves a list of users in the organization.

**Query Parameters:**
- `page` (integer): Page number for pagination
- `pageSize` (integer): Number of users per page (max 200)

**Response:**
```json
{
  "lastPage": false,
  "result": "success",
  "users": [
    {
      "userID": "user1@company.com",
      "email": "user1@company.com",
      "firstname": "User",
      "lastname": "One",
      "country": "US",
      "type": "federatedID",
      "status": "active"
    }
  ]
}
```

#### 6. Manage User Groups

**POST** `/v2/usermanagement/users/{userID}/groups`

Adds or removes a user from groups.

**Request Body:**
```json
{
  "groups": [
    {
      "group": "Creative Cloud All Apps Users",
      "requestID": "action_1"
    }
  ]
}
```

## Adobe Admin Console API

Base URL: `https://adminconsole.adobe.io`

### Endpoints

#### 1. Get Organization Information

**GET** `/v2/organizations/{orgId}`

Retrieves organization details and configuration.

**Response:**
```json
{
  "orgId": "12345@AdobeOrg",
  "name": "Company Name",
  "type": "enterprise",
  "status": "active",
  "licenseQuota": {
    "Creative Cloud All Apps": 500,
    "Acrobat Pro DC": 1000
  }
}
```

#### 2. Get License Usage

**GET** `/v2/organizations/{orgId}/licenses`

Retrieves current license allocation and usage.

**Response:**
```json
{
  "licenses": [
    {
      "product": "Creative Cloud All Apps",
      "licenseQuota": 500,
      "currentAssignments": 425,
      "availableLicenses": 75
    },
    {
      "product": "Acrobat Pro DC", 
      "licenseQuota": 1000,
      "currentAssignments": 850,
      "availableLicenses": 150
    }
  ]
}
```

#### 3. Assign Product License

**POST** `/v2/organizations/{orgId}/users/{userID}/products`

Assigns a product license to a user.

**Request Body:**
```json
{
  "products": [
    {
      "product": "Creative Cloud All Apps",
      "requestID": "assign_cc_all_apps"
    }
  ]
}
```

#### 4. Remove Product License

**DELETE** `/v2/organizations/{orgId}/users/{userID}/products/{productId}`

Removes a product license from a user.

## Adobe PDF Services API

Base URL: `https://pdfservices.adobe.io`

### Endpoints

#### 1. Create PDF from Office Document

**POST** `/operation/createpdf`

Converts Office documents to PDF format.

**Request Headers:**
```
Authorization: Bearer {access_token}
X-API-Key: {client_id}
Content-Type: application/json
```

**Request Body:**
```json
{
  "assetID": "urn:aaid:AS:UE1:12345",
  "options": {
    "documentLanguage": "en-US"
  }
}
```

**Response:**
```json
{
  "status": "in_progress",
  "asset": {
    "assetID": "urn:aaid:AS:UE1:67890",
    "metadata": {
      "type": "application/pdf",
      "size": 1048576
    }
  }
}
```

#### 2. OCR PDF

**POST** `/operation/ocr`

Performs OCR on a PDF document.

**Request Body:**
```json
{
  "assetID": "urn:aaid:AS:UE1:12345",
  "options": {
    "ocrLang": "en-us",
    "ocrType": "searchable_image"
  }
}
```

#### 3. Protect PDF

**POST** `/operation/protectpdf`

Applies password protection to a PDF.

**Request Body:**
```json
{
  "assetID": "urn:aaid:AS:UE1:12345",
  "options": {
    "passwordProtection": {
      "userPassword": "user123",
      "ownerPassword": "owner123",
      "permissions": [
        "PRINT_LOW_QUALITY",
        "EDIT_DOCUMENT_ASSEMBLY",
        "COPY_CONTENT"
      ]
    }
  }
}
```

## Adobe Analytics API

Base URL: `https://analytics.adobe.io`

### Endpoints

#### 1. Get Report Suites

**GET** `/discovery/me`

Retrieves available report suites for the authenticated user.

**Response:**
```json
{
  "companyId": "company123",
  "globalCompanyId": "global456",
  "reportSuites": [
    {
      "rsid": "company.prod",
      "name": "Company Production",
      "currency": "USD",
      "timezoneZoneinfo": "America/New_York"
    }
  ]
}
```

#### 2. Run Report

**POST** `/reports`

Executes a custom analytics report.

**Request Body:**
```json
{
  "rsid": "company.prod",
  "globalFilters": [
    {
      "type": "dateRange",
      "dateRange": "2024-01-01T00:00:00.000/2024-01-31T23:59:59.999"
    }
  ],
  "metricContainer": {
    "metrics": [
      {
        "columnId": "page_views",
        "id": "metrics/pageviews"
      }
    ]
  },
  "dimension": "variables/page"
}
```

## Error Handling

### Common Error Codes

#### HTTP Status Codes
- `400 Bad Request`: Invalid request format or parameters
- `401 Unauthorized`: Invalid or expired access token
- `403 Forbidden`: Insufficient permissions
- `404 Not Found`: Resource not found
- `429 Too Many Requests`: Rate limit exceeded
- `500 Internal Server Error`: Adobe service error

#### Adobe-Specific Error Codes
```json
{
  "error_code": "invalid_token",
  "error": "The access token provided is invalid",
  "error_description": "The token has expired or is malformed"
}
```

#### PowerShell Error Handling Template
```powershell
function Invoke-AdobeAPIWithRetry {
    param(
        [string]$Uri,
        [string]$Method = "GET",
        [hashtable]$Headers,
        [string]$Body,
        [int]$MaxRetries = 3,
        [int]$DelaySeconds = 5
    )
    
    for ($attempt = 1; $attempt -le $MaxRetries; $attempt++) {
        try {
            $response = Invoke-RestMethod -Uri $Uri -Method $Method -Headers $Headers -Body $Body -ErrorAction Stop
            return $response
        }
        catch {
            $statusCode = $_.Exception.Response.StatusCode.Value__
            
            switch ($statusCode) {
                401 {
                    Write-Warning "Authentication failed. Refreshing token..."
                    $Headers["Authorization"] = "Bearer $(Get-NewAccessToken)"
                }
                429 {
                    Write-Warning "Rate limit exceeded. Waiting $($DelaySeconds * $attempt) seconds..."
                    Start-Sleep -Seconds ($DelaySeconds * $attempt)
                }
                500, 502, 503, 504 {
                    Write-Warning "Server error. Retrying in $DelaySeconds seconds... (Attempt $attempt of $MaxRetries)"
                    Start-Sleep -Seconds $DelaySeconds
                }
                default {
                    Write-Error "API call failed with status $statusCode`: $($_.Exception.Message)"
                    throw
                }
            }
            
            if ($attempt -eq $MaxRetries) {
                Write-Error "Maximum retry attempts reached. API call failed."
                throw
            }
        }
    }
}
```

## Rate Limiting

### Adobe API Rate Limits

#### User Management API
- **Rate Limit**: 100 requests per minute per organization
- **Burst Limit**: 10 requests per second
- **Daily Limit**: 100,000 requests per day

#### Admin Console API
- **Rate Limit**: 50 requests per minute per organization
- **Burst Limit**: 5 requests per second

#### PDF Services API
- **Rate Limit**: Varies by plan (typically 500-5000 per month)
- **Concurrent Limit**: 5 operations simultaneously

### Rate Limiting Implementation
```powershell
class AdobeRateLimiter {
    [int]$RequestsPerMinute
    [int]$RequestsThisMinute
    [datetime]$WindowStart
    [System.Collections.Queue]$RequestQueue
    
    AdobeRateLimiter([int]$RequestsPerMinute) {
        $this.RequestsPerMinute = $RequestsPerMinute
        $this.RequestsThisMinute = 0
        $this.WindowStart = Get-Date
        $this.RequestQueue = New-Object System.Collections.Queue
    }
    
    [bool]CanMakeRequest() {
        $currentTime = Get-Date
        
        # Reset window if a minute has passed
        if ($currentTime - $this.WindowStart).TotalMinutes -ge 1) {
            $this.RequestsThisMinute = 0
            $this.WindowStart = $currentTime
        }
        
        return $this.RequestsThisMinute -lt $this.RequestsPerMinute
    }
    
    [void]WaitForSlot() {
        while (-not $this.CanMakeRequest()) {
            Start-Sleep -Milliseconds 100
        }
        $this.RequestsThisMinute++
    }
}

# Usage example
$rateLimiter = [AdobeRateLimiter]::new(100)  # 100 requests per minute

function Invoke-RateLimitedAPICall {
    param([string]$Uri, [hashtable]$Headers, [string]$Body)
    
    $rateLimiter.WaitForSlot()
    return Invoke-RestMethod -Uri $Uri -Headers $Headers -Body $Body
}
```

## Code Examples

### Complete User Provisioning Workflow
```powershell
function Complete-UserProvisioning {
    param(
        [string]$UserEmail,
        [string]$FirstName,
        [string]$LastName,
        [string]$Department,
        [string]$AccessToken,
        [string]$ClientId
    )
    
    try {
        # Step 1: Create user
        $createResult = New-AdobeUser -AccessToken $AccessToken -ClientId $ClientId -Email $UserEmail -FirstName $FirstName -LastName $LastName
        
        if ($createResult.result -eq "success") {
            Write-Host "✓ User created: $UserEmail"
            
            # Step 2: Determine license based on department
            $licenseType = switch ($Department) {
                "Creative" { "Creative Cloud All Apps" }
                "Marketing" { "Creative Cloud Photography" }
                default { "Acrobat Pro DC" }
            }
            
            # Step 3: Assign license
            $licenseResult = Add-AdobeUserLicense -AccessToken $AccessToken -ClientId $ClientId -UserEmail $UserEmail -Product $licenseType
            
            if ($licenseResult.result -eq "success") {
                Write-Host "✓ License assigned: $licenseType"
                
                # Step 4: Add to department group
                $groupName = "$Department Users"
                $groupResult = Add-AdobeUserToGroup -AccessToken $AccessToken -ClientId $ClientId -UserEmail $UserEmail -GroupName $groupName
                
                if ($groupResult.result -eq "success") {
                    Write-Host "✓ Added to group: $groupName"
                    return @{ Success = $true; Message = "User provisioning completed successfully" }
                }
            }
        }
        
        throw "One or more provisioning steps failed"
        
    } catch {
        Write-Error "User provisioning failed: $($_.Exception.Message)"
        return @{ Success = $false; Error = $_.Exception.Message }
    }
}
```

### Python Async API Client
```python
import aiohttp
import asyncio
import json
from typing import Dict, List, Optional

class AdobeAPIClient:
    def __init__(self, client_id: str, access_token: str):
        self.client_id = client_id
        self.access_token = access_token
        self.base_url = "https://usermanagement.adobe.io"
        
    async def __aenter__(self):
        self.session = aiohttp.ClientSession(
            headers={
                "Authorization": f"Bearer {self.access_token}",
                "X-Api-Key": self.client_id,
                "Content-Type": "application/json"
            }
        )
        return self
        
    async def __aexit__(self, exc_type, exc_val, exc_tb):
        await self.session.close()
        
    async def create_user(self, email: str, first_name: str, last_name: str, country: str = "US") -> Dict:
        """Create a new Adobe user"""
        url = f"{self.base_url}/v2/usermanagement/users"
        
        payload = {
            "users": [
                {
                    "userID": email,
                    "email": email,
                    "firstname": first_name,
                    "lastname": last_name,
                    "country": country
                }
            ]
        }
        
        async with self.session.post(url, json=payload) as response:
            return await response.json()
            
    async def get_user(self, user_id: str) -> Dict:
        """Get user information"""
        url = f"{self.base_url}/v2/usermanagement/users/{user_id}"
        
        async with self.session.get(url) as response:
            return await response.json()
            
    async def list_users(self, page: int = 0, page_size: int = 200) -> Dict:
        """List organization users"""
        url = f"{self.base_url}/v2/usermanagement/users"
        params = {"page": page, "pageSize": page_size}
        
        async with self.session.get(url, params=params) as response:
            return await response.json()
            
    async def assign_product(self, user_id: str, product: str) -> Dict:
        """Assign product license to user"""
        url = f"{self.base_url}/v2/usermanagement/users/{user_id}/products"
        
        payload = {
            "products": [
                {
                    "product": product,
                    "requestID": f"assign_{product.replace(' ', '_').lower()}"
                }
            ]
        }
        
        async with self.session.post(url, json=payload) as response:
            return await response.json()

# Usage example
async def provision_users_batch(users: List[Dict], access_token: str, client_id: str):
    """Provision multiple users in parallel"""
    async with AdobeAPIClient(client_id, access_token) as client:
        tasks = []
        
        for user in users:
            task = client.create_user(
                email=user["email"],
                first_name=user["first_name"],
                last_name=user["last_name"]
            )
            tasks.append(task)
            
        results = await asyncio.gather(*tasks, return_exceptions=True)
        
        # Process results
        successful = 0
        failed = 0
        
        for i, result in enumerate(results):
            if isinstance(result, Exception):
                print(f"User {users[i]['email']} failed: {result}")
                failed += 1
            else:
                print(f"User {users[i]['email']} created successfully")
                successful += 1
                
        return {"successful": successful, "failed": failed}
```

---

## API Testing

### PowerShell Testing Framework
```powershell
# Test Adobe API connectivity and basic functions
function Test-AdobeAPIFunctions {
    param(
        [string]$AccessToken,
        [string]$ClientId,
        [string]$TestUserEmail = "test.user@company.com"
    )
    
    $testResults = @()
    
    # Test 1: Authentication validation
    try {
        $orgInfo = Get-AdobeOrganizationInfo -AccessToken $AccessToken -ClientId $ClientId
        $testResults += @{ Test = "Authentication"; Result = "PASS"; Details = "Successfully retrieved org info" }
    } catch {
        $testResults += @{ Test = "Authentication"; Result = "FAIL"; Details = $_.Exception.Message }
    }
    
    # Test 2: User creation
    try {
        $createResult = New-AdobeUser -AccessToken $AccessToken -ClientId $ClientId -Email $TestUserEmail -FirstName "Test" -LastName "User"
        if ($createResult.result -eq "success") {
            $testResults += @{ Test = "User Creation"; Result = "PASS"; Details = "Test user created successfully" }
        } else {
            $testResults += @{ Test = "User Creation"; Result = "FAIL"; Details = $createResult.errors }
        }
    } catch {
        $testResults += @{ Test = "User Creation"; Result = "FAIL"; Details = $_.Exception.Message }
    }
    
    # Test 3: User retrieval
    try {
        $userInfo = Get-AdobeUser -AccessToken $AccessToken -ClientId $ClientId -UserEmail $TestUserEmail
        if ($userInfo.userID -eq $TestUserEmail) {
            $testResults += @{ Test = "User Retrieval"; Result = "PASS"; Details = "User information retrieved successfully" }
        } else {
            $testResults += @{ Test = "User Retrieval"; Result = "FAIL"; Details = "User not found or incorrect data" }
        }
    } catch {
        $testResults += @{ Test = "User Retrieval"; Result = "FAIL"; Details = $_.Exception.Message }
    }
    
    # Test 4: License assignment
    try {
        $licenseResult = Add-AdobeUserLicense -AccessToken $AccessToken -ClientId $ClientId -UserEmail $TestUserEmail -Product "Acrobat Pro DC"
        if ($licenseResult.result -eq "success") {
            $testResults += @{ Test = "License Assignment"; Result = "PASS"; Details = "License assigned successfully" }
        } else {
            $testResults += @{ Test = "License Assignment"; Result = "FAIL"; Details = $licenseResult.errors }
        }
    } catch {
        $testResults += @{ Test = "License Assignment"; Result = "FAIL"; Details = $_.Exception.Message }
    }
    
    # Test 5: User cleanup
    try {
        $deleteResult = Remove-AdobeUser -AccessToken $AccessToken -ClientId $ClientId -UserEmail $TestUserEmail
        if ($deleteResult.result -eq "success") {
            $testResults += @{ Test = "User Cleanup"; Result = "PASS"; Details = "Test user removed successfully" }
        } else {
            $testResults += @{ Test = "User Cleanup"; Result = "FAIL"; Details = $deleteResult.errors }
        }
    } catch {
        $testResults += @{ Test = "User Cleanup"; Result = "FAIL"; Details = $_.Exception.Message }
    }
    
    # Generate test report
    $passCount = ($testResults | Where-Object { $_.Result -eq "PASS" }).Count
    $failCount = ($testResults | Where-Object { $_.Result -eq "FAIL" }).Count
    
    Write-Host "`n=== Adobe API Test Results ===" -ForegroundColor Cyan
    foreach ($test in $testResults) {
        $color = if ($test.Result -eq "PASS") { "Green" } else { "Red" }
        Write-Host "$($test.Test): $($test.Result) - $($test.Details)" -ForegroundColor $color
    }
    
    Write-Host "`nSummary: $passCount passed, $failCount failed" -ForegroundColor $(if ($failCount -eq 0) { "Green" } else { "Yellow" })
    
    return $testResults
}
```

This comprehensive API reference provides all the information needed to integrate with Adobe's enterprise APIs effectively. Use the code examples as templates and modify them according to your specific requirements.