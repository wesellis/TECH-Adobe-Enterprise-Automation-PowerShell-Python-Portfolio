-- =============================================
-- Find Inactive Users
-- =============================================
USE AdobeAutomation;
GO

IF OBJECT_ID('adobe.sp_FindInactiveUsers', 'P') IS NOT NULL
    DROP PROCEDURE adobe.sp_FindInactiveUsers;
GO

CREATE PROCEDURE adobe.sp_FindInactiveUsers
    @DaysInactive INT = 30,
    @OrganizationID INT = NULL
AS
BEGIN
    SET NOCOUNT ON;

    SELECT
        u.UserID,
        u.Email,
        u.FirstName,
        u.LastName,
        u.Department,
        u.LastLoginDate,
        COUNT(ula.AssignmentID) AS ActiveLicenses,
        STRING_AGG(p.ProductName, ', ') AS Products,
        SUM(p.CostPerLicense) AS MonthlyCost,
        MAX(ula.LastUsedDate) AS LastUsedDate,
        DATEDIFF(DAY, MAX(ISNULL(ula.LastUsedDate, ula.AssignedDate)), GETUTCDATE()) AS DaysInactive
    FROM adobe.Users u
    INNER JOIN adobe.UserLicenseAssignments ula ON u.UserID = ula.UserID
    INNER JOIN adobe.Products p ON ula.ProductID = p.ProductID
    WHERE ula.Status = 'active'
        AND (@OrganizationID IS NULL OR u.OrganizationID = @OrganizationID)
        AND u.Status = 'active'
    GROUP BY u.UserID, u.Email, u.FirstName, u.LastName, u.Department, u.LastLoginDate
    HAVING DATEDIFF(DAY, MAX(ISNULL(ula.LastUsedDate, ula.AssignedDate)), GETUTCDATE()) >= @DaysInactive
    ORDER BY DaysInactive DESC;
END
GO