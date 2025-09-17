-- =============================================
-- Get User With Licenses Stored Procedure
-- =============================================
USE AdobeAutomation;
GO

IF OBJECT_ID('adobe.sp_GetUserWithLicenses', 'P') IS NOT NULL
    DROP PROCEDURE adobe.sp_GetUserWithLicenses;
GO

CREATE PROCEDURE adobe.sp_GetUserWithLicenses
    @Email NVARCHAR(255)
AS
BEGIN
    SET NOCOUNT ON;

    -- Get user details with licenses
    SELECT
        u.UserID,
        u.Email,
        u.FirstName,
        u.LastName,
        u.Department,
        u.Status,
        u.LastLoginDate,
        u.CreatedAt,
        (
            SELECT
                p.ProductName,
                p.ProductSKU,
                ula.AssignedDate,
                ula.LastUsedDate,
                ula.Status AS LicenseStatus
            FROM adobe.UserLicenseAssignments ula
            INNER JOIN adobe.Products p ON ula.ProductID = p.ProductID
            WHERE ula.UserID = u.UserID AND ula.Status = 'active'
            FOR JSON PATH
        ) AS Licenses
    FROM adobe.Users u
    WHERE u.Email = @Email;
END
GO