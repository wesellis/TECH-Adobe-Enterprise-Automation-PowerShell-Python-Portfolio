#!/usr/bin/env pwsh
# BASIC LEVEL: Simple Adobe user retrieval
# Learning: API basics, JSON parsing, simple output

param(
    [string]$ConfigFile = "../config/adobe-config.json"
)

# Basic function - no error handling yet
function Get-AdobeUsers {
    # Read config
    $config = Get-Content $ConfigFile | ConvertFrom-Json

    # Simple API call simulation
    Write-Host "Fetching Adobe users..." -ForegroundColor Green

    # Mock data for demonstration
    $users = @(
        @{Email="user1@company.com"; Name="John Doe"; Products="Creative Cloud"},
        @{Email="user2@company.com"; Name="Jane Smith"; Products="Photoshop"},
        @{Email="user3@company.com"; Name="Bob Wilson"; Products="Illustrator"}
    )

    # Basic output
    foreach ($user in $users) {
        Write-Host "$($user.Name) - $($user.Email) - $($user.Products)"
    }

    return $users
}

# Run the function
$users = Get-AdobeUsers
Write-Host "`nFound $($users.Count) users" -ForegroundColor Yellow