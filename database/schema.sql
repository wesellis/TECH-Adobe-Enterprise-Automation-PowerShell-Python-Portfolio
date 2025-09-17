-- Adobe Enterprise Automation Database Schema
-- SQL Server 2019+ Compatible
-- Version: 1.0.0
-- Created: 2024-12-16

-- =============================================
-- Create Database
-- =============================================
IF NOT EXISTS (SELECT * FROM sys.databases WHERE name = 'AdobeAutomation')
BEGIN
    CREATE DATABASE AdobeAutomation;
END
GO

USE AdobeAutomation;
GO

-- =============================================
-- Schema Creation
-- =============================================
IF NOT EXISTS (SELECT * FROM sys.schemas WHERE name = 'adobe')
BEGIN
    EXEC('CREATE SCHEMA adobe');
END
GO

-- =============================================
-- Tables
-- =============================================

-- Organizations table
IF OBJECT_ID('adobe.Organizations', 'U') IS NULL
BEGIN
    CREATE TABLE adobe.Organizations (
        OrganizationID INT IDENTITY(1,1) PRIMARY KEY,
        OrgName NVARCHAR(255) NOT NULL,
        AdobeOrgID NVARCHAR(100) UNIQUE NOT NULL,
        TenantID NVARCHAR(100),
        IsActive BIT DEFAULT 1,
        CreatedAt DATETIME2 DEFAULT GETUTCDATE(),
        UpdatedAt DATETIME2 DEFAULT GETUTCDATE(),
        Metadata NVARCHAR(MAX) -- JSON column for flexible data
    );
END
GO

-- Users table
IF OBJECT_ID('adobe.Users', 'U') IS NULL
BEGIN
    CREATE TABLE adobe.Users (
        UserID INT IDENTITY(1,1) PRIMARY KEY,
        OrganizationID INT NOT NULL,
        Email NVARCHAR(255) NOT NULL,
        FirstName NVARCHAR(100),
        LastName NVARCHAR(100),
        Country NVARCHAR(2) DEFAULT 'US',
        Department NVARCHAR(100),
        JobTitle NVARCHAR(100),
        EmployeeID NVARCHAR(50),
        AdobeUserID NVARCHAR(100),
        Status NVARCHAR(20) DEFAULT 'active', -- active, inactive, suspended, deleted
        UserType NVARCHAR(20) DEFAULT 'standard', -- standard, admin, system
        LastLoginDate DATETIME2,
        CreatedAt DATETIME2 DEFAULT GETUTCDATE(),
        UpdatedAt DATETIME2 DEFAULT GETUTCDATE(),
        DeletedAt DATETIME2 NULL,
        CONSTRAINT FK_Users_Organization FOREIGN KEY (OrganizationID)
            REFERENCES adobe.Organizations(OrganizationID),
        CONSTRAINT UQ_User_Email_Org UNIQUE (Email, OrganizationID)
    );

    CREATE INDEX IX_Users_Email ON adobe.Users(Email);
    CREATE INDEX IX_Users_Status ON adobe.Users(Status);
    CREATE INDEX IX_Users_Department ON adobe.Users(Department);
END
GO

-- Products table
IF OBJECT_ID('adobe.Products', 'U') IS NULL
BEGIN
    CREATE TABLE adobe.Products (
        ProductID INT IDENTITY(1,1) PRIMARY KEY,
        ProductName NVARCHAR(100) NOT NULL UNIQUE,
        ProductSKU NVARCHAR(50),
        ProductCategory NVARCHAR(50),
        CostPerLicense DECIMAL(10,2),
        Description NVARCHAR(500),
        IsActive BIT DEFAULT 1,
        CreatedAt DATETIME2 DEFAULT GETUTCDATE(),
        UpdatedAt DATETIME2 DEFAULT GETUTCDATE()
    );
END
GO

-- Licenses table
IF OBJECT_ID('adobe.Licenses', 'U') IS NULL
BEGIN
    CREATE TABLE adobe.Licenses (
        LicenseID INT IDENTITY(1,1) PRIMARY KEY,
        OrganizationID INT NOT NULL,
        ProductID INT NOT NULL,
        TotalQuantity INT NOT NULL DEFAULT 0,
        UsedQuantity INT NOT NULL DEFAULT 0,
        AvailableQuantity AS (TotalQuantity - UsedQuantity) PERSISTED,
        ExpiryDate DATE,
        ContractNumber NVARCHAR(100),
        PurchaseOrderNumber NVARCHAR(100),
        IsActive BIT DEFAULT 1,
        CreatedAt DATETIME2 DEFAULT GETUTCDATE(),
        UpdatedAt DATETIME2 DEFAULT GETUTCDATE(),
        CONSTRAINT FK_Licenses_Organization FOREIGN KEY (OrganizationID)
            REFERENCES adobe.Organizations(OrganizationID),
        CONSTRAINT FK_Licenses_Product FOREIGN KEY (ProductID)
            REFERENCES adobe.Products(ProductID),
        CONSTRAINT CK_License_Quantity CHECK (UsedQuantity <= TotalQuantity)
    );

    CREATE INDEX IX_Licenses_OrgProduct ON adobe.Licenses(OrganizationID, ProductID);
END
GO

-- User License Assignments
IF OBJECT_ID('adobe.UserLicenseAssignments', 'U') IS NULL
BEGIN
    CREATE TABLE adobe.UserLicenseAssignments (
        AssignmentID INT IDENTITY(1,1) PRIMARY KEY,
        UserID INT NOT NULL,
        LicenseID INT NOT NULL,
        ProductID INT NOT NULL,
        AssignedDate DATETIME2 DEFAULT GETUTCDATE(),
        LastUsedDate DATETIME2,
        RevokedDate DATETIME2 NULL,
        Status NVARCHAR(20) DEFAULT 'active', -- active, revoked, expired
        AssignedBy NVARCHAR(255),
        RevokedBy NVARCHAR(255),
        Notes NVARCHAR(MAX),
        CONSTRAINT FK_Assignment_User FOREIGN KEY (UserID)
            REFERENCES adobe.Users(UserID),
        CONSTRAINT FK_Assignment_License FOREIGN KEY (LicenseID)
            REFERENCES adobe.Licenses(LicenseID),
        CONSTRAINT FK_Assignment_Product FOREIGN KEY (ProductID)
            REFERENCES adobe.Products(ProductID)
    );

    CREATE INDEX IX_Assignments_User ON adobe.UserLicenseAssignments(UserID);
    CREATE INDEX IX_Assignments_Status ON adobe.UserLicenseAssignments(Status);
    CREATE INDEX IX_Assignments_LastUsed ON adobe.UserLicenseAssignments(LastUsedDate);
END
GO

-- Audit Log table
IF OBJECT_ID('adobe.AuditLog', 'U') IS NULL
BEGIN
    CREATE TABLE adobe.AuditLog (
        AuditID BIGINT IDENTITY(1,1) PRIMARY KEY,
        OrganizationID INT,
        UserID INT,
        Action NVARCHAR(100) NOT NULL,
        EntityType NVARCHAR(50), -- User, License, Product, etc.
        EntityID INT,
        OldValue NVARCHAR(MAX), -- JSON
        NewValue NVARCHAR(MAX), -- JSON
        PerformedBy NVARCHAR(255),
        PerformedAt DATETIME2 DEFAULT GETUTCDATE(),
        IPAddress NVARCHAR(45),
        UserAgent NVARCHAR(500),
        Success BIT DEFAULT 1,
        ErrorMessage NVARCHAR(MAX),
        CONSTRAINT FK_Audit_Organization FOREIGN KEY (OrganizationID)
            REFERENCES adobe.Organizations(OrganizationID),
        CONSTRAINT FK_Audit_User FOREIGN KEY (UserID)
            REFERENCES adobe.Users(UserID)
    );

    CREATE INDEX IX_Audit_Date ON adobe.AuditLog(PerformedAt);
    CREATE INDEX IX_Audit_Action ON adobe.AuditLog(Action);
    CREATE INDEX IX_Audit_User ON adobe.AuditLog(UserID);
END
GO

-- License Usage History
IF OBJECT_ID('adobe.LicenseUsageHistory', 'U') IS NULL
BEGIN
    CREATE TABLE adobe.LicenseUsageHistory (
        UsageID BIGINT IDENTITY(1,1) PRIMARY KEY,
        OrganizationID INT NOT NULL,
        ProductID INT NOT NULL,
        UserID INT NOT NULL,
        UsageDate DATE NOT NULL,
        UsageHours DECIMAL(5,2),
        Features NVARCHAR(MAX), -- JSON array of features used
        CreatedAt DATETIME2 DEFAULT GETUTCDATE(),
        CONSTRAINT FK_Usage_Organization FOREIGN KEY (OrganizationID)
            REFERENCES adobe.Organizations(OrganizationID),
        CONSTRAINT FK_Usage_Product FOREIGN KEY (ProductID)
            REFERENCES adobe.Products(ProductID),
        CONSTRAINT FK_Usage_User FOREIGN KEY (UserID)
            REFERENCES adobe.Users(UserID)
    );

    CREATE INDEX IX_Usage_Date ON adobe.LicenseUsageHistory(UsageDate);
    CREATE INDEX IX_Usage_UserProduct ON adobe.LicenseUsageHistory(UserID, ProductID);
END
GO

-- Provisioning Queue
IF OBJECT_ID('adobe.ProvisioningQueue', 'U') IS NULL
BEGIN
    CREATE TABLE adobe.ProvisioningQueue (
        QueueID INT IDENTITY(1,1) PRIMARY KEY,
        OrganizationID INT NOT NULL,
        RequestType NVARCHAR(50) NOT NULL, -- create_user, assign_license, revoke_license, delete_user
        RequestData NVARCHAR(MAX) NOT NULL, -- JSON
        Status NVARCHAR(20) DEFAULT 'pending', -- pending, processing, completed, failed
        Priority INT DEFAULT 5, -- 1-10, 1 being highest
        RetryCount INT DEFAULT 0,
        MaxRetries INT DEFAULT 3,
        RequestedBy NVARCHAR(255),
        RequestedAt DATETIME2 DEFAULT GETUTCDATE(),
        ProcessedAt DATETIME2 NULL,
        CompletedAt DATETIME2 NULL,
        ErrorMessage NVARCHAR(MAX),
        CONSTRAINT FK_Queue_Organization FOREIGN KEY (OrganizationID)
            REFERENCES adobe.Organizations(OrganizationID)
    );

    CREATE INDEX IX_Queue_Status ON adobe.ProvisioningQueue(Status);
    CREATE INDEX IX_Queue_Priority ON adobe.ProvisioningQueue(Priority DESC);
END
GO

-- Groups table
IF OBJECT_ID('adobe.Groups', 'U') IS NULL
BEGIN
    CREATE TABLE adobe.Groups (
        GroupID INT IDENTITY(1,1) PRIMARY KEY,
        OrganizationID INT NOT NULL,
        GroupName NVARCHAR(100) NOT NULL,
        Description NVARCHAR(500),
        GroupType NVARCHAR(50), -- department, project, role
        DefaultProducts NVARCHAR(MAX), -- JSON array of product IDs
        IsActive BIT DEFAULT 1,
        CreatedAt DATETIME2 DEFAULT GETUTCDATE(),
        UpdatedAt DATETIME2 DEFAULT GETUTCDATE(),
        CONSTRAINT FK_Groups_Organization FOREIGN KEY (OrganizationID)
            REFERENCES adobe.Organizations(OrganizationID),
        CONSTRAINT UQ_Group_Name_Org UNIQUE (GroupName, OrganizationID)
    );
END
GO

-- User Group Memberships
IF OBJECT_ID('adobe.UserGroupMemberships', 'U') IS NULL
BEGIN
    CREATE TABLE adobe.UserGroupMemberships (
        MembershipID INT IDENTITY(1,1) PRIMARY KEY,
        UserID INT NOT NULL,
        GroupID INT NOT NULL,
        JoinedDate DATETIME2 DEFAULT GETUTCDATE(),
        LeftDate DATETIME2 NULL,
        IsActive BIT DEFAULT 1,
        CONSTRAINT FK_Membership_User FOREIGN KEY (UserID)
            REFERENCES adobe.Users(UserID),
        CONSTRAINT FK_Membership_Group FOREIGN KEY (GroupID)
            REFERENCES adobe.Groups(GroupID),
        CONSTRAINT UQ_User_Group UNIQUE (UserID, GroupID)
    );

    CREATE INDEX IX_Membership_User ON adobe.UserGroupMemberships(UserID);
    CREATE INDEX IX_Membership_Group ON adobe.UserGroupMemberships(GroupID);
END
GO

-- Cost Centers
IF OBJECT_ID('adobe.CostCenters', 'U') IS NULL
BEGIN
    CREATE TABLE adobe.CostCenters (
        CostCenterID INT IDENTITY(1,1) PRIMARY KEY,
        OrganizationID INT NOT NULL,
        CostCenterCode NVARCHAR(50) NOT NULL,
        CostCenterName NVARCHAR(100) NOT NULL,
        Department NVARCHAR(100),
        Manager NVARCHAR(255),
        Budget DECIMAL(12,2),
        CurrentSpend DECIMAL(12,2) DEFAULT 0,
        FiscalYear INT,
        IsActive BIT DEFAULT 1,
        CreatedAt DATETIME2 DEFAULT GETUTCDATE(),
        UpdatedAt DATETIME2 DEFAULT GETUTCDATE(),
        CONSTRAINT FK_CostCenter_Organization FOREIGN KEY (OrganizationID)
            REFERENCES adobe.Organizations(OrganizationID),
        CONSTRAINT UQ_CostCenter_Code_Org UNIQUE (CostCenterCode, OrganizationID)
    );
END
GO

-- License Optimization Recommendations
IF OBJECT_ID('adobe.OptimizationRecommendations', 'U') IS NULL
BEGIN
    CREATE TABLE adobe.OptimizationRecommendations (
        RecommendationID INT IDENTITY(1,1) PRIMARY KEY,
        OrganizationID INT NOT NULL,
        RecommendationType NVARCHAR(50), -- reclaim, reassign, upgrade, downgrade
        UserID INT,
        ProductID INT,
        CurrentState NVARCHAR(MAX), -- JSON
        RecommendedAction NVARCHAR(MAX), -- JSON
        PotentialSavings DECIMAL(10,2),
        Confidence DECIMAL(3,2), -- 0.00 to 1.00
        Status NVARCHAR(20) DEFAULT 'pending', -- pending, approved, rejected, implemented
        GeneratedAt DATETIME2 DEFAULT GETUTCDATE(),
        ReviewedAt DATETIME2,
        ReviewedBy NVARCHAR(255),
        ImplementedAt DATETIME2,
        CONSTRAINT FK_Recommendation_Organization FOREIGN KEY (OrganizationID)
            REFERENCES adobe.Organizations(OrganizationID),
        CONSTRAINT FK_Recommendation_User FOREIGN KEY (UserID)
            REFERENCES adobe.Users(UserID),
        CONSTRAINT FK_Recommendation_Product FOREIGN KEY (ProductID)
            REFERENCES adobe.Products(ProductID)
    );
END
GO

-- =============================================
-- Views
-- =============================================

-- Active License Summary View
IF OBJECT_ID('adobe.vw_ActiveLicenseSummary', 'V') IS NOT NULL
    DROP VIEW adobe.vw_ActiveLicenseSummary;
GO

CREATE VIEW adobe.vw_ActiveLicenseSummary AS
SELECT
    o.OrganizationID,
    o.OrgName,
    p.ProductName,
    l.TotalQuantity,
    l.UsedQuantity,
    l.AvailableQuantity,
    l.ExpiryDate,
    p.CostPerLicense,
    (l.UsedQuantity * p.CostPerLicense) AS CurrentMonthlySpend,
    (l.AvailableQuantity * p.CostPerLicense) AS UnusedValueMonthly
FROM adobe.Licenses l
INNER JOIN adobe.Organizations o ON l.OrganizationID = o.OrganizationID
INNER JOIN adobe.Products p ON l.ProductID = p.ProductID
WHERE l.IsActive = 1;
GO

-- User License Details View
IF OBJECT_ID('adobe.vw_UserLicenseDetails', 'V') IS NOT NULL
    DROP VIEW adobe.vw_UserLicenseDetails;
GO

CREATE VIEW adobe.vw_UserLicenseDetails AS
SELECT
    u.UserID,
    u.Email,
    u.FirstName,
    u.LastName,
    u.Department,
    u.Status AS UserStatus,
    p.ProductName,
    ula.AssignedDate,
    ula.LastUsedDate,
    ula.Status AS LicenseStatus,
    DATEDIFF(DAY, ISNULL(ula.LastUsedDate, ula.AssignedDate), GETUTCDATE()) AS DaysSinceLastUse
FROM adobe.Users u
INNER JOIN adobe.UserLicenseAssignments ula ON u.UserID = ula.UserID
INNER JOIN adobe.Products p ON ula.ProductID = p.ProductID
WHERE ula.Status = 'active';
GO

-- Inactive Users View (for license reclamation)
IF OBJECT_ID('adobe.vw_InactiveUsers', 'V') IS NOT NULL
    DROP VIEW adobe.vw_InactiveUsers;
GO

CREATE VIEW adobe.vw_InactiveUsers AS
SELECT
    u.UserID,
    u.Email,
    u.FirstName,
    u.LastName,
    u.Department,
    COUNT(ula.AssignmentID) AS ActiveLicenses,
    SUM(p.CostPerLicense) AS MonthlyCost,
    MAX(ula.LastUsedDate) AS LastActiveDate,
    DATEDIFF(DAY, MAX(ISNULL(ula.LastUsedDate, ula.AssignedDate)), GETUTCDATE()) AS DaysInactive
FROM adobe.Users u
INNER JOIN adobe.UserLicenseAssignments ula ON u.UserID = ula.UserID
INNER JOIN adobe.Products p ON ula.ProductID = p.ProductID
WHERE ula.Status = 'active'
GROUP BY u.UserID, u.Email, u.FirstName, u.LastName, u.Department
HAVING DATEDIFF(DAY, MAX(ISNULL(ula.LastUsedDate, ula.AssignedDate)), GETUTCDATE()) > 30;
GO

-- =============================================
-- Indexes for Performance
-- =============================================

-- Additional performance indexes
CREATE INDEX IX_Users_LastLogin ON adobe.Users(LastLoginDate);
CREATE INDEX IX_Licenses_Expiry ON adobe.Licenses(ExpiryDate);
CREATE INDEX IX_Queue_RequestedAt ON adobe.ProvisioningQueue(RequestedAt);
CREATE INDEX IX_Audit_OrgDate ON adobe.AuditLog(OrganizationID, PerformedAt);

-- =============================================
-- Initial Seed Data
-- =============================================

-- Insert default organization
IF NOT EXISTS (SELECT 1 FROM adobe.Organizations WHERE AdobeOrgID = 'DEFAULT_ORG')
BEGIN
    INSERT INTO adobe.Organizations (OrgName, AdobeOrgID, TenantID)
    VALUES ('Default Organization', 'DEFAULT_ORG', 'default-tenant');
END
GO

-- Insert Adobe products
IF NOT EXISTS (SELECT 1 FROM adobe.Products)
BEGIN
    INSERT INTO adobe.Products (ProductName, ProductSKU, ProductCategory, CostPerLicense) VALUES
    ('Creative Cloud All Apps', 'CC_ALL', 'Suite', 79.99),
    ('Photoshop', 'PS_SINGLE', 'Creative', 31.49),
    ('Illustrator', 'AI_SINGLE', 'Creative', 31.49),
    ('InDesign', 'ID_SINGLE', 'Creative', 31.49),
    ('Premiere Pro', 'PR_SINGLE', 'Video', 31.49),
    ('After Effects', 'AE_SINGLE', 'Video', 31.49),
    ('Lightroom', 'LR_SINGLE', 'Photography', 19.99),
    ('XD', 'XD_SINGLE', 'Design', 19.99),
    ('Animate', 'AN_SINGLE', 'Animation', 31.49),
    ('Dreamweaver', 'DW_SINGLE', 'Web', 31.49),
    ('Acrobat Pro', 'ACRO_PRO', 'Document', 19.99),
    ('Audition', 'AU_SINGLE', 'Audio', 31.49),
    ('InCopy', 'IC_SINGLE', 'Creative', 5.99),
    ('Substance 3D', 'S3D_SINGLE', '3D', 49.99),
    ('Stock', 'STOCK', 'Assets', 29.99);
END
GO

PRINT 'Database schema created successfully';
GO