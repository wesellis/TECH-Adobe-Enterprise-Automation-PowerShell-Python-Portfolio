-- =============================================
-- Queue User for Provisioning
-- =============================================
USE AdobeAutomation;
GO

IF OBJECT_ID('adobe.sp_QueueUserForProvisioning', 'P') IS NOT NULL
    DROP PROCEDURE adobe.sp_QueueUserForProvisioning;
GO

CREATE PROCEDURE adobe.sp_QueueUserForProvisioning
    @Email NVARCHAR(255),
    @FirstName NVARCHAR(100),
    @LastName NVARCHAR(100),
    @Department NVARCHAR(100) = NULL,
    @Products NVARCHAR(MAX) = NULL -- JSON array
AS
BEGIN
    SET NOCOUNT ON;

    DECLARE @OrganizationID INT = 1; -- Default org for now
    DECLARE @RequestData NVARCHAR(MAX);

    -- Build JSON request data
    SET @RequestData = (
        SELECT
            @Email AS email,
            @FirstName AS firstName,
            @LastName AS lastName,
            @Department AS department,
            @Products AS products
        FOR JSON PATH, WITHOUT_ARRAY_WRAPPER
    );

    -- Insert into queue
    INSERT INTO adobe.ProvisioningQueue (
        OrganizationID,
        RequestType,
        RequestData,
        Priority,
        RequestedBy
    )
    VALUES (
        @OrganizationID,
        'create_user',
        @RequestData,
        5,
        'API'
    );

    SELECT SCOPE_IDENTITY() AS QueueID;
END
GO