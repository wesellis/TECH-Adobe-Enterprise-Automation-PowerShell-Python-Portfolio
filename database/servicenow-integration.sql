-- ServiceNow Integration Tables for Adobe Automation
-- Tracks incidents, requests, and sync operations

USE AdobeAutomation;
GO

-- ServiceNow Incidents table
CREATE TABLE adobe.ServiceNowIncidents (
    IncidentID INT IDENTITY(1,1) PRIMARY KEY,
    IncidentNumber NVARCHAR(50) NOT NULL UNIQUE,
    SysId NVARCHAR(100) NOT NULL,
    ShortDescription NVARCHAR(500),
    Description NVARCHAR(MAX),
    Status NVARCHAR(50),
    Priority INT,
    AssignmentGroup NVARCHAR(200),
    AssignedTo NVARCHAR(255),
    CreatedBy NVARCHAR(255),
    CreatedAt DATETIME2 DEFAULT GETDATE(),
    UpdatedAt DATETIME2,
    ResolvedAt DATETIME2,
    ResolutionNotes NVARCHAR(MAX),
    Category NVARCHAR(100),
    Subcategory NVARCHAR(100),
    RelatedUserEmail NVARCHAR(255),
    INDEX IX_ServiceNowIncidents_Number (IncidentNumber),
    INDEX IX_ServiceNowIncidents_Status (Status),
    INDEX IX_ServiceNowIncidents_CreatedAt (CreatedAt DESC)
);
GO

-- ServiceNow Requests table
CREATE TABLE adobe.ServiceNowRequests (
    RequestID INT IDENTITY(1,1) PRIMARY KEY,
    RequestNumber NVARCHAR(50) NOT NULL UNIQUE,
    SysId NVARCHAR(100) NOT NULL,
    RequestType NVARCHAR(100),
    CatalogItem NVARCHAR(200),
    RequestedFor NVARCHAR(255),
    RequestedBy NVARCHAR(255),
    UserEmail NVARCHAR(255),
    Products NVARCHAR(MAX),
    Justification NVARCHAR(MAX),
    Status NVARCHAR(50),
    ApprovalStatus NVARCHAR(50),
    ApprovedBy NVARCHAR(255),
    ApprovedAt DATETIME2,
    RejectionReason NVARCHAR(MAX),
    Department NVARCHAR(100),
    CostCenter NVARCHAR(50),
    EstimatedCost DECIMAL(10,2),
    CreatedAt DATETIME2 DEFAULT GETDATE(),
    CompletedAt DATETIME2,
    INDEX IX_ServiceNowRequests_Number (RequestNumber),
    INDEX IX_ServiceNowRequests_Status (Status),
    INDEX IX_ServiceNowRequests_UserEmail (UserEmail)
);
GO

-- ServiceNow Sync History table
CREATE TABLE adobe.ServiceNowSyncHistory (
    SyncID INT IDENTITY(1,1) PRIMARY KEY,
    SyncType NVARCHAR(50),
    Direction NVARCHAR(50), -- 'to_snow' or 'from_snow'
    StartTime DATETIME2 DEFAULT GETDATE(),
    EndTime DATETIME2,
    Status NVARCHAR(50),
    RecordsProcessed INT,
    RecordsCreated INT,
    RecordsUpdated INT,
    RecordsFailed INT,
    ErrorDetails NVARCHAR(MAX),
    InitiatedBy NVARCHAR(255),
    JobId NVARCHAR(100),
    INDEX IX_ServiceNowSyncHistory_StartTime (StartTime DESC),
    INDEX IX_ServiceNowSyncHistory_JobId (JobId)
);
GO

-- ServiceNow Webhook Events table
CREATE TABLE adobe.ServiceNowWebhookEvents (
    EventID INT IDENTITY(1,1) PRIMARY KEY,
    EventType NVARCHAR(100),
    EventData NVARCHAR(MAX),
    ReceivedAt DATETIME2 DEFAULT GETDATE(),
    ProcessedAt DATETIME2,
    ProcessingStatus NVARCHAR(50),
    ProcessingError NVARCHAR(MAX),
    RelatedIncident NVARCHAR(50),
    RelatedRequest NVARCHAR(50),
    INDEX IX_ServiceNowWebhookEvents_ReceivedAt (ReceivedAt DESC),
    INDEX IX_ServiceNowWebhookEvents_EventType (EventType)
);
GO

-- ServiceNow Field Mappings table
CREATE TABLE adobe.ServiceNowFieldMappings (
    MappingID INT IDENTITY(1,1) PRIMARY KEY,
    EntityType NVARCHAR(100),
    AdobeField NVARCHAR(200),
    ServiceNowField NVARCHAR(200),
    DataType NVARCHAR(50),
    TransformRule NVARCHAR(MAX),
    IsActive BIT DEFAULT 1,
    CreatedAt DATETIME2 DEFAULT GETDATE(),
    UpdatedAt DATETIME2,
    UpdatedBy NVARCHAR(255)
);
GO

-- Stored Procedures for ServiceNow Integration

-- Create or update ServiceNow incident
CREATE PROCEDURE adobe.sp_UpsertServiceNowIncident
    @IncidentNumber NVARCHAR(50),
    @SysId NVARCHAR(100),
    @ShortDescription NVARCHAR(500),
    @Status NVARCHAR(50),
    @AssignedTo NVARCHAR(255) = NULL,
    @UpdatedAt DATETIME2 = NULL
AS
BEGIN
    SET NOCOUNT ON;
    
    IF EXISTS (SELECT 1 FROM adobe.ServiceNowIncidents WHERE IncidentNumber = @IncidentNumber)
    BEGIN
        UPDATE adobe.ServiceNowIncidents
        SET 
            Status = @Status,
            AssignedTo = ISNULL(@AssignedTo, AssignedTo),
            UpdatedAt = ISNULL(@UpdatedAt, GETDATE()),
            ResolvedAt = CASE 
                WHEN @Status IN ('Resolved', 'Closed') AND ResolvedAt IS NULL 
                THEN GETDATE() 
                ELSE ResolvedAt 
            END
        WHERE IncidentNumber = @IncidentNumber;
    END
    ELSE
    BEGIN
        INSERT INTO adobe.ServiceNowIncidents (
            IncidentNumber, SysId, ShortDescription, Status, 
            AssignedTo, CreatedAt
        )
        VALUES (
            @IncidentNumber, @SysId, @ShortDescription, @Status,
            @AssignedTo, GETDATE()
        );
    END
END;
GO

-- Get ServiceNow integration statistics
CREATE PROCEDURE adobe.sp_GetServiceNowStats
    @DaysBack INT = 30
AS
BEGIN
    SET NOCOUNT ON;
    
    DECLARE @StartDate DATETIME2 = DATEADD(DAY, -@DaysBack, GETDATE());
    
    -- Incident statistics
    SELECT 
        'Incidents' as MetricType,
        COUNT(*) as TotalCount,
        SUM(CASE WHEN Status = 'Open' THEN 1 ELSE 0 END) as OpenCount,
        SUM(CASE WHEN Status = 'In Progress' THEN 1 ELSE 0 END) as InProgressCount,
        SUM(CASE WHEN Status IN ('Resolved', 'Closed') THEN 1 ELSE 0 END) as ClosedCount,
        AVG(CASE 
            WHEN ResolvedAt IS NOT NULL 
            THEN DATEDIFF(HOUR, CreatedAt, ResolvedAt) 
            ELSE NULL 
        END) as AvgResolutionHours
    FROM adobe.ServiceNowIncidents
    WHERE CreatedAt >= @StartDate;
    
    -- Request statistics
    SELECT 
        'Requests' as MetricType,
        COUNT(*) as TotalCount,
        SUM(CASE WHEN Status = 'Pending' THEN 1 ELSE 0 END) as PendingCount,
        SUM(CASE WHEN ApprovalStatus = 'Approved' THEN 1 ELSE 0 END) as ApprovedCount,
        SUM(CASE WHEN ApprovalStatus = 'Rejected' THEN 1 ELSE 0 END) as RejectedCount,
        SUM(EstimatedCost) as TotalEstimatedCost
    FROM adobe.ServiceNowRequests
    WHERE CreatedAt >= @StartDate;
    
    -- Sync history
    SELECT 
        'Sync' as MetricType,
        COUNT(*) as TotalSyncs,
        SUM(CASE WHEN Status = 'Success' THEN 1 ELSE 0 END) as SuccessfulSyncs,
        SUM(CASE WHEN Status = 'Failed' THEN 1 ELSE 0 END) as FailedSyncs,
        SUM(RecordsProcessed) as TotalRecordsProcessed,
        MAX(StartTime) as LastSyncTime
    FROM adobe.ServiceNowSyncHistory
    WHERE StartTime >= @StartDate;
END;
GO

-- Process ServiceNow webhook event
CREATE PROCEDURE adobe.sp_ProcessServiceNowWebhook
    @EventType NVARCHAR(100),
    @EventData NVARCHAR(MAX),
    @RelatedIncident NVARCHAR(50) = NULL,
    @RelatedRequest NVARCHAR(50) = NULL
AS
BEGIN
    SET NOCOUNT ON;
    
    BEGIN TRY
        BEGIN TRANSACTION;
        
        -- Insert webhook event
        INSERT INTO adobe.ServiceNowWebhookEvents (
            EventType, EventData, RelatedIncident, RelatedRequest,
            ProcessingStatus
        )
        VALUES (
            @EventType, @EventData, @RelatedIncident, @RelatedRequest,
            'Processing'
        );
        
        DECLARE @EventID INT = SCOPE_IDENTITY();
        
        -- Process based on event type
        IF @EventType = 'incident.created'
        BEGIN
            -- Extract data from JSON and create incident
            DECLARE @IncidentData NVARCHAR(MAX) = @EventData;
            -- Parse JSON and insert/update incident
        END
        ELSE IF @EventType = 'request.approved'
        BEGIN
            -- Update request approval status
            UPDATE adobe.ServiceNowRequests
            SET ApprovalStatus = 'Approved',
                ApprovedAt = GETDATE(),
                Status = 'Processing'
            WHERE RequestNumber = @RelatedRequest;
            
            -- Queue for Adobe provisioning
            INSERT INTO adobe.ProvisioningQueue (
                RequestNumber, UserEmail, Products, Status
            )
            SELECT 
                RequestNumber, UserEmail, Products, 'Pending'
            FROM adobe.ServiceNowRequests
            WHERE RequestNumber = @RelatedRequest;
        END
        
        -- Mark webhook as processed
        UPDATE adobe.ServiceNowWebhookEvents
        SET ProcessingStatus = 'Completed',
            ProcessedAt = GETDATE()
        WHERE EventID = @EventID;
        
        COMMIT TRANSACTION;
    END TRY
    BEGIN CATCH
        ROLLBACK TRANSACTION;
        
        -- Update webhook with error
        UPDATE adobe.ServiceNowWebhookEvents
        SET ProcessingStatus = 'Failed',
            ProcessingError = ERROR_MESSAGE(),
            ProcessedAt = GETDATE()
        WHERE EventType = @EventType 
            AND EventData = @EventData
            AND ProcessingStatus = 'Processing';
        
        THROW;
    END CATCH;
END;
GO

-- Get pending ServiceNow requests for processing
CREATE PROCEDURE adobe.sp_GetPendingServiceNowRequests
AS
BEGIN
    SET NOCOUNT ON;
    
    SELECT 
        r.RequestNumber,
        r.SysId,
        r.RequestType,
        r.UserEmail,
        r.Products,
        r.Department,
        r.CostCenter,
        r.RequestedBy,
        r.CreatedAt,
        u.UserID,
        u.FirstName,
        u.LastName
    FROM adobe.ServiceNowRequests r
    LEFT JOIN adobe.Users u ON r.UserEmail = u.Email
    WHERE r.ApprovalStatus = 'Approved'
        AND r.Status = 'Processing'
        AND NOT EXISTS (
            SELECT 1 FROM adobe.ProvisioningQueue pq
            WHERE pq.RequestNumber = r.RequestNumber
                AND pq.Status IN ('Completed', 'Failed')
        )
    ORDER BY r.CreatedAt ASC;
END;
GO

-- Insert sample field mappings
INSERT INTO adobe.ServiceNowFieldMappings (
    EntityType, AdobeField, ServiceNowField, DataType
)
VALUES 
    ('User', 'Email', 'email', 'string'),
    ('User', 'FirstName', 'first_name', 'string'),
    ('User', 'LastName', 'last_name', 'string'),
    ('User', 'Department', 'department', 'string'),
    ('User', 'IsActive', 'active', 'boolean'),
    ('Incident', 'ShortDescription', 'short_description', 'string'),
    ('Incident', 'Description', 'description', 'string'),
    ('Incident', 'Priority', 'priority', 'integer'),
    ('Request', 'UserEmail', 'u_user_email', 'string'),
    ('Request', 'Products', 'u_products', 'string'),
    ('Request', 'Justification', 'u_justification', 'string'),
    ('Request', 'CostCenter', 'u_cost_center', 'string');
GO

-- Create view for ServiceNow dashboard
CREATE VIEW adobe.vw_ServiceNowDashboard AS
SELECT 
    'Incidents' as ItemType,
    i.IncidentNumber as ItemNumber,
    i.ShortDescription as Description,
    i.Status,
    i.Priority,
    i.CreatedBy,
    i.CreatedAt,
    i.AssignedTo,
    NULL as ApprovalStatus,
    NULL as EstimatedCost
FROM adobe.ServiceNowIncidents i
WHERE i.CreatedAt >= DATEADD(DAY, -7, GETDATE())

UNION ALL

SELECT 
    'Requests' as ItemType,
    r.RequestNumber as ItemNumber,
    r.RequestType as Description,
    r.Status,
    CASE 
        WHEN r.EstimatedCost > 1000 THEN 1
        WHEN r.EstimatedCost > 500 THEN 2
        ELSE 3
    END as Priority,
    r.RequestedBy as CreatedBy,
    r.CreatedAt,
    r.RequestedFor as AssignedTo,
    r.ApprovalStatus,
    r.EstimatedCost
FROM adobe.ServiceNowRequests r
WHERE r.CreatedAt >= DATEADD(DAY, -7, GETDATE());
GO

PRINT 'ServiceNow Integration tables and procedures created successfully';