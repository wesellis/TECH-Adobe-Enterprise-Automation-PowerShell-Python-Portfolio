-- Adobe Automation Database Schema
-- SQL Server 2019+

USE master;
GO

-- Create database
IF NOT EXISTS (SELECT name FROM sys.databases WHERE name = 'AdobeAutomation')
BEGIN
    CREATE DATABASE AdobeAutomation;
END
GO

USE AdobeAutomation;
GO

-- Users table
IF NOT EXISTS (SELECT * FROM sysobjects WHERE name='Users' AND xtype='U')
BEGIN
    CREATE TABLE Users (
        UserId INT IDENTITY(1,1) PRIMARY KEY,
        Email NVARCHAR(255) UNIQUE NOT NULL,
        FirstName NVARCHAR(100),
        LastName NVARCHAR(100),
        AdobeId NVARCHAR(255),
        ADUsername NVARCHAR(255),
        AzureId NVARCHAR(255),
        Department NVARCHAR(100),
        JobTitle NVARCHAR(100),
        Location NVARCHAR(100),
        Status NVARCHAR(50) DEFAULT 'Active',
        CreatedDate DATETIME2 DEFAULT GETUTCDATE(),
        ModifiedDate DATETIME2 DEFAULT GETUTCDATE(),
        LastSyncDate DATETIME2,
        LastLoginDate DATETIME2,
        INDEX IX_Users_Email (Email),
        INDEX IX_Users_Status (Status),
        INDEX IX_Users_Department (Department)
    );
END
GO

-- Products table
IF NOT EXISTS (SELECT * FROM sysobjects WHERE name='Products' AND xtype='U')
BEGIN
    CREATE TABLE Products (
        ProductId INT IDENTITY(1,1) PRIMARY KEY,
        ProductName NVARCHAR(100) UNIQUE NOT NULL,
        SKU NVARCHAR(50),
        Description NVARCHAR(500),
        CostPerLicense DECIMAL(10,2),
        TotalLicenses INT DEFAULT 0,
        UsedLicenses INT DEFAULT 0,
        CreatedDate DATETIME2 DEFAULT GETUTCDATE(),
        ModifiedDate DATETIME2 DEFAULT GETUTCDATE(),
        INDEX IX_Products_Name (ProductName)
    );
END
GO

-- License Assignments table
IF NOT EXISTS (SELECT * FROM sysobjects WHERE name='LicenseAssignments' AND xtype='U')
BEGIN
    CREATE TABLE LicenseAssignments (
        AssignmentId INT IDENTITY(1,1) PRIMARY KEY,
        UserId INT NOT NULL,
        ProductId INT NOT NULL,
        AssignedDate DATETIME2 DEFAULT GETUTCDATE(),
        RemovedDate DATETIME2,
        AssignedBy NVARCHAR(255),
        RemovedBy NVARCHAR(255),
        Status NVARCHAR(50) DEFAULT 'Active',
        FOREIGN KEY (UserId) REFERENCES Users(UserId),
        FOREIGN KEY (ProductId) REFERENCES Products(ProductId),
        INDEX IX_LicenseAssignments_User (UserId),
        INDEX IX_LicenseAssignments_Product (ProductId),
        INDEX IX_LicenseAssignments_Status (Status)
    );
END
GO

-- User Groups table
IF NOT EXISTS (SELECT * FROM sysobjects WHERE name='UserGroups' AND xtype='U')
BEGIN
    CREATE TABLE UserGroups (
        GroupId INT IDENTITY(1,1) PRIMARY KEY,
        GroupName NVARCHAR(100) UNIQUE NOT NULL,
        Description NVARCHAR(500),
        ADGroupDN NVARCHAR(500),
        AzureGroupId NVARCHAR(255),
        AutoProvision BIT DEFAULT 0,
        DefaultProducts NVARCHAR(MAX), -- JSON array of product IDs
        CreatedDate DATETIME2 DEFAULT GETUTCDATE(),
        ModifiedDate DATETIME2 DEFAULT GETUTCDATE()
    );
END
GO

-- User Group Memberships
IF NOT EXISTS (SELECT * FROM sysobjects WHERE name='UserGroupMemberships' AND xtype='U')
BEGIN
    CREATE TABLE UserGroupMemberships (
        MembershipId INT IDENTITY(1,1) PRIMARY KEY,
        UserId INT NOT NULL,
        GroupId INT NOT NULL,
        AddedDate DATETIME2 DEFAULT GETUTCDATE(),
        RemovedDate DATETIME2,
        FOREIGN KEY (UserId) REFERENCES Users(UserId),
        FOREIGN KEY (GroupId) REFERENCES UserGroups(GroupId),
        INDEX IX_Memberships_User (UserId),
        INDEX IX_Memberships_Group (GroupId)
    );
END
GO

-- Audit Logs table
IF NOT EXISTS (SELECT * FROM sysobjects WHERE name='AuditLogs' AND xtype='U')
BEGIN
    CREATE TABLE AuditLogs (
        LogId BIGINT IDENTITY(1,1) PRIMARY KEY,
        EventType NVARCHAR(100) NOT NULL,
        EventDate DATETIME2 DEFAULT GETUTCDATE(),
        UserId INT,
        TargetUserId INT,
        ProductId INT,
        GroupId INT,
        Action NVARCHAR(255),
        Details NVARCHAR(MAX),
        PerformedBy NVARCHAR(255),
        IPAddress NVARCHAR(50),
        SessionId NVARCHAR(255),
        Success BIT DEFAULT 1,
        ErrorMessage NVARCHAR(MAX),
        INDEX IX_AuditLogs_Date (EventDate),
        INDEX IX_AuditLogs_EventType (EventType),
        INDEX IX_AuditLogs_User (UserId)
    );
END
GO

-- Provisioning Queue table
IF NOT EXISTS (SELECT * FROM sysobjects WHERE name='ProvisioningQueue' AND xtype='U')
BEGIN
    CREATE TABLE ProvisioningQueue (
        QueueId INT IDENTITY(1,1) PRIMARY KEY,
        Email NVARCHAR(255) NOT NULL,
        FirstName NVARCHAR(100),
        LastName NVARCHAR(100),
        Department NVARCHAR(100),
        RequestedProducts NVARCHAR(MAX), -- JSON array
        Priority INT DEFAULT 5,
        Status NVARCHAR(50) DEFAULT 'Pending',
        QueuedDate DATETIME2 DEFAULT GETUTCDATE(),
        ProcessedDate DATETIME2,
        RetryCount INT DEFAULT 0,
        LastError NVARCHAR(MAX),
        INDEX IX_Queue_Status (Status),
        INDEX IX_Queue_Priority (Priority DESC, QueuedDate ASC)
    );
END
GO

-- License Optimization History
IF NOT EXISTS (SELECT * FROM sysobjects WHERE name='OptimizationHistory' AND xtype='U')
BEGIN
    CREATE TABLE OptimizationHistory (
        OptimizationId INT IDENTITY(1,1) PRIMARY KEY,
        RunDate DATETIME2 DEFAULT GETUTCDATE(),
        UsersAnalyzed INT,
        InactiveUsersFound INT,
        LicensesReclaimed INT,
        EstimatedMonthlySavings DECIMAL(10,2),
        Details NVARCHAR(MAX), -- JSON with detailed results
        CompletedDate DATETIME2,
        Status NVARCHAR(50)
    );
END
GO

-- Metrics table for time-series data
IF NOT EXISTS (SELECT * FROM sysobjects WHERE name='Metrics' AND xtype='U')
BEGIN
    CREATE TABLE Metrics (
        MetricId BIGINT IDENTITY(1,1) PRIMARY KEY,
        MetricName NVARCHAR(100) NOT NULL,
        MetricValue FLOAT NOT NULL,
        Labels NVARCHAR(MAX), -- JSON object
        Timestamp DATETIME2 DEFAULT GETUTCDATE(),
        INDEX IX_Metrics_Name_Time (MetricName, Timestamp DESC)
    );
END
GO

-- Scheduled Tasks
IF NOT EXISTS (SELECT * FROM sysobjects WHERE name='ScheduledTasks' AND xtype='U')
BEGIN
    CREATE TABLE ScheduledTasks (
        TaskId INT IDENTITY(1,1) PRIMARY KEY,
        TaskName NVARCHAR(100) UNIQUE NOT NULL,
        TaskType NVARCHAR(50),
        Schedule NVARCHAR(100), -- Cron expression
        LastRunDate DATETIME2,
        NextRunDate DATETIME2,
        Status NVARCHAR(50),
        Enabled BIT DEFAULT 1,
        Configuration NVARCHAR(MAX) -- JSON configuration
    );
END
GO

-- Create stored procedures

-- SP: Get User with License Details
CREATE OR ALTER PROCEDURE sp_GetUserWithLicenses
    @Email NVARCHAR(255)
AS
BEGIN
    SELECT
        u.*,
        (
            SELECT
                p.ProductName,
                p.SKU,
                la.AssignedDate,
                la.Status
            FROM LicenseAssignments la
            INNER JOIN Products p ON la.ProductId = p.ProductId
            WHERE la.UserId = u.UserId AND la.Status = 'Active'
            FOR JSON PATH
        ) AS Licenses
    FROM Users u
    WHERE u.Email = @Email;
END
GO

-- SP: Get License Utilization
CREATE OR ALTER PROCEDURE sp_GetLicenseUtilization
AS
BEGIN
    SELECT
        p.ProductName,
        p.TotalLicenses,
        p.UsedLicenses,
        CAST(CASE
            WHEN p.TotalLicenses > 0
            THEN (CAST(p.UsedLicenses AS FLOAT) / p.TotalLicenses) * 100
            ELSE 0
        END AS DECIMAL(5,2)) AS UtilizationPercent,
        p.CostPerLicense,
        (p.TotalLicenses - p.UsedLicenses) AS AvailableLicenses,
        (p.TotalLicenses - p.UsedLicenses) * p.CostPerLicense AS PotentialMonthlySavings
    FROM Products p
    ORDER BY UtilizationPercent DESC;
END
GO

-- SP: Find Inactive Users
CREATE OR ALTER PROCEDURE sp_FindInactiveUsers
    @DaysInactive INT = 90
AS
BEGIN
    SELECT
        u.UserId,
        u.Email,
        u.FirstName,
        u.LastName,
        u.LastLoginDate,
        DATEDIFF(DAY, u.LastLoginDate, GETUTCDATE()) AS DaysInactive,
        COUNT(la.AssignmentId) AS ActiveLicenses,
        SUM(p.CostPerLicense) AS MonthlyCost
    FROM Users u
    LEFT JOIN LicenseAssignments la ON u.UserId = la.UserId AND la.Status = 'Active'
    LEFT JOIN Products p ON la.ProductId = p.ProductId
    WHERE u.LastLoginDate < DATEADD(DAY, -@DaysInactive, GETUTCDATE())
        OR u.LastLoginDate IS NULL
    GROUP BY u.UserId, u.Email, u.FirstName, u.LastName, u.LastLoginDate
    HAVING COUNT(la.AssignmentId) > 0
    ORDER BY MonthlyCost DESC;
END
GO

-- SP: Queue User for Provisioning
CREATE OR ALTER PROCEDURE sp_QueueUserForProvisioning
    @Email NVARCHAR(255),
    @FirstName NVARCHAR(100),
    @LastName NVARCHAR(100),
    @Department NVARCHAR(100) = NULL,
    @Products NVARCHAR(MAX) = NULL,
    @Priority INT = 5
AS
BEGIN
    -- Check if user already exists
    IF NOT EXISTS (SELECT 1 FROM Users WHERE Email = @Email)
    BEGIN
        -- Add to queue if not already queued
        IF NOT EXISTS (SELECT 1 FROM ProvisioningQueue WHERE Email = @Email AND Status = 'Pending')
        BEGIN
            INSERT INTO ProvisioningQueue (Email, FirstName, LastName, Department, RequestedProducts, Priority)
            VALUES (@Email, @FirstName, @LastName, @Department, @Products, @Priority);

            SELECT SCOPE_IDENTITY() AS QueueId;
        END
    END
END
GO

-- SP: Process Provisioning Queue
CREATE OR ALTER PROCEDURE sp_ProcessProvisioningQueue
    @BatchSize INT = 100
AS
BEGIN
    SELECT TOP (@BatchSize)
        QueueId,
        Email,
        FirstName,
        LastName,
        Department,
        RequestedProducts
    FROM ProvisioningQueue
    WHERE Status = 'Pending'
        AND RetryCount < 3
    ORDER BY Priority DESC, QueuedDate ASC;
END
GO

-- SP: Record Metric
CREATE OR ALTER PROCEDURE sp_RecordMetric
    @MetricName NVARCHAR(100),
    @MetricValue FLOAT,
    @Labels NVARCHAR(MAX) = NULL
AS
BEGIN
    INSERT INTO Metrics (MetricName, MetricValue, Labels)
    VALUES (@MetricName, @MetricValue, @Labels);

    -- Clean up old metrics (keep 30 days)
    DELETE FROM Metrics
    WHERE Timestamp < DATEADD(DAY, -30, GETUTCDATE());
END
GO

-- Create views

-- View: Active Users Summary
CREATE OR ALTER VIEW vw_ActiveUsersSummary
AS
SELECT
    COUNT(DISTINCT u.UserId) AS TotalUsers,
    COUNT(DISTINCT CASE WHEN u.Status = 'Active' THEN u.UserId END) AS ActiveUsers,
    COUNT(DISTINCT la.UserId) AS UsersWithLicenses,
    COUNT(DISTINCT u.Department) AS Departments,
    SUM(CASE WHEN la.Status = 'Active' THEN p.CostPerLicense ELSE 0 END) AS TotalMonthlyCost
FROM Users u
LEFT JOIN LicenseAssignments la ON u.UserId = la.UserId AND la.Status = 'Active'
LEFT JOIN Products p ON la.ProductId = p.ProductId;
GO

-- View: Department License Usage
CREATE OR ALTER VIEW vw_DepartmentLicenseUsage
AS
SELECT
    u.Department,
    COUNT(DISTINCT u.UserId) AS UserCount,
    COUNT(la.AssignmentId) AS TotalLicenses,
    SUM(p.CostPerLicense) AS MonthlyCost,
    STRING_AGG(DISTINCT p.ProductName, ', ') AS Products
FROM Users u
LEFT JOIN LicenseAssignments la ON u.UserId = la.UserId AND la.Status = 'Active'
LEFT JOIN Products p ON la.ProductId = p.ProductId
WHERE u.Department IS NOT NULL
GROUP BY u.Department;
GO

-- Insert default data
INSERT INTO Products (ProductName, SKU, Description, CostPerLicense, TotalLicenses)
VALUES
    ('Creative Cloud All Apps', 'CC-ALL', 'Complete Creative Cloud suite', 79.99, 500),
    ('Photoshop', 'PS-SINGLE', 'Adobe Photoshop', 31.49, 200),
    ('Illustrator', 'AI-SINGLE', 'Adobe Illustrator', 31.49, 150),
    ('InDesign', 'ID-SINGLE', 'Adobe InDesign', 31.49, 100),
    ('Premiere Pro', 'PR-SINGLE', 'Adobe Premiere Pro', 31.49, 100),
    ('After Effects', 'AE-SINGLE', 'Adobe After Effects', 31.49, 75),
    ('Acrobat Pro', 'ACRO-PRO', 'Adobe Acrobat Pro DC', 19.99, 1000),
    ('Adobe Stock', 'STOCK-10', 'Adobe Stock - 10 assets/month', 29.99, 50),
    ('Lightroom', 'LR-SINGLE', 'Adobe Lightroom', 9.99, 200),
    ('XD', 'XD-SINGLE', 'Adobe XD', 9.99, 100);
GO

-- Insert default scheduled tasks
INSERT INTO ScheduledTasks (TaskName, TaskType, Schedule, Status, Enabled)
VALUES
    ('User Sync', 'Sync', '0 */4 * * *', 'Idle', 1),
    ('License Optimization', 'Optimization', '0 2 * * *', 'Idle', 1),
    ('Weekly Report', 'Report', '0 8 * * MON', 'Idle', 1),
    ('Audit Log Cleanup', 'Maintenance', '0 3 * * SUN', 'Idle', 1);
GO

-- Create indexes for performance
CREATE INDEX IX_AuditLogs_DateRange ON AuditLogs(EventDate) INCLUDE (EventType, UserId);
CREATE INDEX IX_Users_Sync ON Users(LastSyncDate, Status) INCLUDE (Email, AdobeId);
CREATE INDEX IX_LicenseAssignments_Active ON LicenseAssignments(Status) WHERE Status = 'Active';

-- Enable query store for performance monitoring
ALTER DATABASE AdobeAutomation SET QUERY_STORE = ON;
GO

PRINT 'Adobe Automation database initialization complete';
GO