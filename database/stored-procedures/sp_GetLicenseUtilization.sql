-- =============================================
-- Get License Utilization
-- =============================================
USE AdobeAutomation;
GO

IF OBJECT_ID('adobe.sp_GetLicenseUtilization', 'P') IS NOT NULL
    DROP PROCEDURE adobe.sp_GetLicenseUtilization;
GO

CREATE PROCEDURE adobe.sp_GetLicenseUtilization
    @OrganizationID INT = NULL
AS
BEGIN
    SET NOCOUNT ON;

    SELECT
        p.ProductID,
        p.ProductName,
        p.CostPerLicense,
        ISNULL(l.TotalQuantity, 0) AS TotalLicenses,
        ISNULL(l.UsedQuantity, 0) AS UsedLicenses,
        ISNULL(l.AvailableQuantity, 0) AS AvailableLicenses,
        CASE
            WHEN l.TotalQuantity > 0
            THEN CAST(l.UsedQuantity AS FLOAT) / l.TotalQuantity * 100
            ELSE 0
        END AS UtilizationPercent,
        ISNULL(l.UsedQuantity * p.CostPerLicense, 0) AS MonthlyCost,
        ISNULL(l.AvailableQuantity * p.CostPerLicense, 0) AS PotentialMonthlySavings
    FROM adobe.Products p
    LEFT JOIN adobe.Licenses l ON p.ProductID = l.ProductID
        AND (@OrganizationID IS NULL OR l.OrganizationID = @OrganizationID)
        AND l.IsActive = 1
    WHERE p.IsActive = 1
    ORDER BY p.ProductName;
END
GO