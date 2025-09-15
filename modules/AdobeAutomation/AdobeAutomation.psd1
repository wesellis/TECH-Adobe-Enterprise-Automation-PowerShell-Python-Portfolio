@{
    # Module Manifest for AdobeAutomation
    RootModule = 'AdobeAutomation.psm1'
    ModuleVersion = '2.0.0'
    GUID = 'a7c4d8e9-3b2f-4e1a-9c5d-8f6b2a1e7d3c'
    Author = 'Enterprise Automation Team'
    CompanyName = 'Your Company'
    Copyright = '(c) 2024. All rights reserved.'
    Description = 'Enterprise-scale Adobe Creative Cloud automation module for user provisioning, license management, and reporting'
    PowerShellVersion = '5.1'

    # Functions to export
    FunctionsToExport = @(
        'Connect-AdobeAPI',
        'Disconnect-AdobeAPI',
        'New-AdobeUser',
        'Get-AdobeUser',
        'Set-AdobeUser',
        'Remove-AdobeUser',
        'Add-AdobeLicense',
        'Remove-AdobeLicense',
        'Get-AdobeLicense',
        'Optimize-AdobeLicenses',
        'Sync-AdobeUsers',
        'Get-AdobeUserActivity',
        'Export-AdobeReport',
        'Start-AdobeBulkOperation',
        'Get-AdobeProducts',
        'Get-AdobeGroups',
        'Add-AdobeGroupMember',
        'Remove-AdobeGroupMember',
        'Test-AdobeConnection',
        'Get-AdobeAuditLog',
        'Invoke-AdobeBackup',
        'Restore-AdobeConfiguration'
    )

    # Cmdlets to export
    CmdletsToExport = @()

    # Variables to export
    VariablesToExport = @('AdobeAPIConnection')

    # Aliases to export
    AliasesToExport = @(
        'aau',   # Add-AdobeUser
        'gau',   # Get-AdobeUser
        'rau',   # Remove-AdobeUser
        'oal'    # Optimize-AdobeLicenses
    )

    # Private data
    PrivateData = @{
        PSData = @{
            Tags = @('Adobe', 'CreativeCloud', 'Automation', 'Enterprise', 'UserManagement', 'Licensing')
            LicenseUri = 'https://github.com/wesellis/adobe-enterprise-automation/LICENSE'
            ProjectUri = 'https://github.com/wesellis/adobe-enterprise-automation'
            IconUri = 'https://github.com/wesellis/adobe-enterprise-automation/icon.png'
            ReleaseNotes = @"
2.0.0 - Major release with async processing, Kubernetes support, and enhanced monitoring
1.5.0 - Added Azure AD integration and batch processing
1.0.0 - Initial release with core functionality
"@
        }
    }

    # Requirements
    RequiredModules = @(
        @{ModuleName = 'Az.Accounts'; ModuleVersion = '2.0.0'},
        @{ModuleName = 'ActiveDirectory'; ModuleVersion = '1.0.0'}
    )

    # External dependencies
    RequiredAssemblies = @(
        'System.Web.dll',
        'System.Net.Http.dll'
    )

    # Script files to process
    ScriptsToProcess = @(
        'Initialize-AdobeEnvironment.ps1'
    )

    # Type files
    TypesToProcess = @()

    # Format files
    FormatsToProcess = @()

    # Nested modules
    NestedModules = @(
        'Modules\Authentication.psm1',
        'Modules\UserManagement.psm1',
        'Modules\LicenseManagement.psm1',
        'Modules\Reporting.psm1',
        'Modules\Utilities.psm1'
    )

    # Default prefix
    DefaultCommandPrefix = ''

    # Module dependencies
    FileList = @(
        'AdobeAutomation.psd1',
        'AdobeAutomation.psm1',
        'Initialize-AdobeEnvironment.ps1',
        'Modules\Authentication.psm1',
        'Modules\UserManagement.psm1',
        'Modules\LicenseManagement.psm1',
        'Modules\Reporting.psm1',
        'Modules\Utilities.psm1',
        'Config\DefaultConfig.json',
        'Templates\UserTemplate.json',
        'Templates\ReportTemplate.html'
    )
}