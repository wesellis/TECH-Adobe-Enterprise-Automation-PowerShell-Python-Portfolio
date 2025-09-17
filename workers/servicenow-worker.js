/**
 * ServiceNow Integration Worker
 * Processes ServiceNow requests and syncs data
 */

const redis = require('redis');
const sql = require('mssql');
const axios = require('axios');
const winston = require('winston');
const { spawn } = require('child_process');

// Logger configuration
const logger = winston.createLogger({
    level: 'info',
    format: winston.format.json(),
    transports: [
        new winston.transports.File({ filename: 'servicenow-worker.log' }),
        new winston.transports.Console({
            format: winston.format.simple()
        })
    ]
});

// Redis configuration
const redisClient = redis.createClient({
    host: process.env.REDIS_HOST || 'localhost',
    port: process.env.REDIS_PORT || 6379
});

// SQL configuration
const sqlConfig = {
    user: process.env.DB_USER || 'sa',
    password: process.env.DB_PASSWORD,
    database: process.env.DB_NAME || 'AdobeAutomation',
    server: process.env.DB_HOST || 'localhost',
    pool: {
        max: 10,
        min: 0,
        idleTimeoutMillis: 30000
    },
    options: {
        encrypt: true,
        trustServerCertificate: true
    }
};

// Adobe API configuration
const adobeConfig = {
    clientId: process.env.ADOBE_CLIENT_ID,
    clientSecret: process.env.ADOBE_CLIENT_SECRET,
    orgId: process.env.ADOBE_ORG_ID,
    apiBaseUrl: 'https://usermanagement.adobe.io/v2/usermanagement'
};

/**
 * Process approved ServiceNow requests
 */
async function processApprovedRequests() {
    try {
        const requestData = await redisClient.blpopAsync('approved_requests', 5);
        
        if (!requestData) return;
        
        const request = JSON.parse(requestData[1]);
        logger.info(`Processing approved request: ${request.requestNumber}`);
        
        // Connect to database
        const pool = await sql.connect(sqlConfig);
        
        // Get full request details
        const result = await pool.request()
            .input('RequestNumber', sql.NVarChar, request.requestNumber)
            .query(`
                SELECT * FROM adobe.ServiceNowRequests 
                WHERE RequestNumber = @RequestNumber
            `);
        
        if (result.recordset.length === 0) {
            logger.error(`Request not found: ${request.requestNumber}`);
            return;
        }
        
        const fullRequest = result.recordset[0];
        
        // Process based on request type
        switch (fullRequest.RequestType) {
            case 'new_user':
                await provisionNewUser(fullRequest);
                break;
            case 'add_license':
                await addLicensesToUser(fullRequest);
                break;
            case 'remove_license':
                await removeLicensesFromUser(fullRequest);
                break;
            case 'deactivate_user':
                await deactivateUser(fullRequest);
                break;
            default:
                logger.warn(`Unknown request type: ${fullRequest.RequestType}`);
        }
        
        // Update request status
        await pool.request()
            .input('RequestNumber', sql.NVarChar, request.requestNumber)
            .input('Status', sql.NVarChar, 'Completed')
            .input('CompletedAt', sql.DateTime2, new Date())
            .query(`
                UPDATE adobe.ServiceNowRequests
                SET Status = @Status, CompletedAt = @CompletedAt
                WHERE RequestNumber = @RequestNumber
            `);
        
        logger.info(`Completed processing request: ${request.requestNumber}`);
        
    } catch (error) {
        logger.error('Error processing approved request:', error);
    }
}

/**
 * Provision new Adobe user
 */
async function provisionNewUser(request) {
    try {
        const userData = {
            email: request.UserEmail,
            firstName: request.UserEmail.split('@')[0].split('.')[0],
            lastName: request.UserEmail.split('@')[0].split('.')[1] || 'User',
            products: request.Products ? request.Products.split(',') : [],
            department: request.Department,
            costCenter: request.CostCenter
        };
        
        // Call PowerShell provisioning script
        const ps = spawn('pwsh', [
            '-File',
            './creative-cloud/user-provisioning/New-AdobeUser.ps1',
            '-Email', userData.email,
            '-FirstName', userData.firstName,
            '-LastName', userData.lastName,
            '-Products', userData.products.join(','),
            '-Department', userData.department
        ]);
        
        return new Promise((resolve, reject) => {
            let output = '';
            let error = '';
            
            ps.stdout.on('data', (data) => {
                output += data.toString();
            });
            
            ps.stderr.on('data', (data) => {
                error += data.toString();
            });
            
            ps.on('close', async (code) => {
                if (code === 0) {
                    logger.info(`User provisioned successfully: ${userData.email}`);
                    
                    // Update database
                    const pool = await sql.connect(sqlConfig);
                    await pool.request()
                        .input('Email', sql.NVarChar, userData.email)
                        .input('FirstName', sql.NVarChar, userData.firstName)
                        .input('LastName', sql.NVarChar, userData.lastName)
                        .input('Department', sql.NVarChar, userData.department)
                        .input('IsActive', sql.Bit, 1)
                        .query(`
                            INSERT INTO adobe.Users 
                            (Email, FirstName, LastName, Department, IsActive, CreatedAt)
                            VALUES (@Email, @FirstName, @LastName, @Department, @IsActive, GETDATE())
                        `);
                    
                    // Send notification
                    await sendNotification('user_provisioned', userData);
                    
                    resolve();
                } else {
                    logger.error(`User provisioning failed: ${error}`);
                    reject(new Error(error));
                }
            });
        });
    } catch (error) {
        logger.error('Error provisioning user:', error);
        throw error;
    }
}

/**
 * Add licenses to existing user
 */
async function addLicensesToUser(request) {
    try {
        const products = request.Products ? request.Products.split(',') : [];
        
        // Call PowerShell script to add licenses
        const ps = spawn('pwsh', [
            '-File',
            './creative-cloud/license-management/Add-License.ps1',
            '-UserEmail', request.UserEmail,
            '-Products', products.join(',')
        ]);
        
        return new Promise((resolve, reject) => {
            ps.on('close', async (code) => {
                if (code === 0) {
                    logger.info(`Licenses added for user: ${request.UserEmail}`);
                    
                    // Update database
                    const pool = await sql.connect(sqlConfig);
                    for (const product of products) {
                        await pool.request()
                            .input('UserEmail', sql.NVarChar, request.UserEmail)
                            .input('ProductName', sql.NVarChar, product)
                            .query(`
                                INSERT INTO adobe.UserLicenses (UserID, ProductID, AssignedAt, IsActive)
                                SELECT u.UserID, p.ProductID, GETDATE(), 1
                                FROM adobe.Users u
                                CROSS JOIN adobe.Products p
                                WHERE u.Email = @UserEmail
                                    AND p.ProductName = @ProductName
                                    AND NOT EXISTS (
                                        SELECT 1 FROM adobe.UserLicenses ul
                                        WHERE ul.UserID = u.UserID 
                                            AND ul.ProductID = p.ProductID
                                    )
                            `);
                    }
                    
                    resolve();
                } else {
                    reject(new Error('Failed to add licenses'));
                }
            });
        });
    } catch (error) {
        logger.error('Error adding licenses:', error);
        throw error;
    }
}

/**
 * Remove licenses from user
 */
async function removeLicensesFromUser(request) {
    try {
        const products = request.Products ? request.Products.split(',') : [];
        
        // Call PowerShell script to remove licenses
        const ps = spawn('pwsh', [
            '-File',
            './creative-cloud/license-management/Remove-License.ps1',
            '-UserEmail', request.UserEmail,
            '-Products', products.join(',')
        ]);
        
        return new Promise((resolve, reject) => {
            ps.on('close', async (code) => {
                if (code === 0) {
                    logger.info(`Licenses removed for user: ${request.UserEmail}`);
                    
                    // Update database
                    const pool = await sql.connect(sqlConfig);
                    await pool.request()
                        .input('UserEmail', sql.NVarChar, request.UserEmail)
                        .input('Products', sql.NVarChar, products.join(','))
                        .query(`
                            UPDATE adobe.UserLicenses
                            SET IsActive = 0, RemovedAt = GETDATE()
                            FROM adobe.UserLicenses ul
                            INNER JOIN adobe.Users u ON ul.UserID = u.UserID
                            INNER JOIN adobe.Products p ON ul.ProductID = p.ProductID
                            WHERE u.Email = @UserEmail
                                AND p.ProductName IN (SELECT value FROM STRING_SPLIT(@Products, ','))
                        `);
                    
                    resolve();
                } else {
                    reject(new Error('Failed to remove licenses'));
                }
            });
        });
    } catch (error) {
        logger.error('Error removing licenses:', error);
        throw error;
    }
}

/**
 * Deactivate Adobe user
 */
async function deactivateUser(request) {
    try {
        // Call PowerShell script to deactivate user
        const ps = spawn('pwsh', [
            '-File',
            './creative-cloud/user-provisioning/Remove-AdobeUser.ps1',
            '-Email', request.UserEmail
        ]);
        
        return new Promise((resolve, reject) => {
            ps.on('close', async (code) => {
                if (code === 0) {
                    logger.info(`User deactivated: ${request.UserEmail}`);
                    
                    // Update database
                    const pool = await sql.connect(sqlConfig);
                    await pool.request()
                        .input('Email', sql.NVarChar, request.UserEmail)
                        .query(`
                            UPDATE adobe.Users
                            SET IsActive = 0, DeactivatedAt = GETDATE()
                            WHERE Email = @Email;
                            
                            UPDATE adobe.UserLicenses
                            SET IsActive = 0, RemovedAt = GETDATE()
                            FROM adobe.UserLicenses ul
                            INNER JOIN adobe.Users u ON ul.UserID = u.UserID
                            WHERE u.Email = @Email AND ul.IsActive = 1;
                        `);
                    
                    resolve();
                } else {
                    reject(new Error('Failed to deactivate user'));
                }
            });
        });
    } catch (error) {
        logger.error('Error deactivating user:', error);
        throw error;
    }
}

/**
 * Sync users between ServiceNow and Adobe
 */
async function syncUsers() {
    try {
        const jobData = await redisClient.blpopAsync('sync_queue', 5);
        
        if (!jobData) return;
        
        const job = JSON.parse(jobData[1]);
        logger.info(`Starting user sync job: ${job.jobId}`);
        
        // Update job status
        await redisClient.setAsync(`sync:status:${job.jobId}`, JSON.stringify({
            status: 'running',
            startedAt: new Date().toISOString(),
            progress: 0
        }));
        
        // Get users from database
        const pool = await sql.connect(sqlConfig);
        const result = await pool.request().query(`
            SELECT 
                u.UserID,
                u.Email,
                u.FirstName,
                u.LastName,
                u.Department,
                u.IsActive,
                STRING_AGG(p.ProductName, ',') as Products
            FROM adobe.Users u
            LEFT JOIN adobe.UserLicenses ul ON u.UserID = ul.UserID AND ul.IsActive = 1
            LEFT JOIN adobe.Products p ON ul.ProductID = p.ProductID
            GROUP BY u.UserID, u.Email, u.FirstName, u.LastName, u.Department, u.IsActive
        `);
        
        const users = result.recordset;
        let processed = 0;
        let errors = [];
        
        for (const user of users) {
            try {
                // Sync user to ServiceNow
                await syncUserToServiceNow(user);
                processed++;
                
                // Update progress
                const progress = Math.round((processed / users.length) * 100);
                await redisClient.setAsync(`sync:status:${job.jobId}`, JSON.stringify({
                    status: 'running',
                    progress: progress,
                    processed: processed,
                    total: users.length
                }));
            } catch (error) {
                logger.error(`Error syncing user ${user.Email}:`, error);
                errors.push({ email: user.Email, error: error.message });
            }
        }
        
        // Update final status
        await redisClient.setAsync(`sync:status:${job.jobId}`, JSON.stringify({
            status: 'completed',
            completedAt: new Date().toISOString(),
            processed: processed,
            total: users.length,
            errors: errors
        }));
        
        // Log to database
        await pool.request()
            .input('SyncType', sql.NVarChar, 'user_sync')
            .input('Direction', sql.NVarChar, 'to_snow')
            .input('RecordsProcessed', sql.Int, processed)
            .input('RecordsFailed', sql.Int, errors.length)
            .input('Status', sql.NVarChar, 'Success')
            .input('JobId', sql.NVarChar, job.jobId)
            .input('InitiatedBy', sql.NVarChar, job.initiatedBy)
            .query(`
                INSERT INTO adobe.ServiceNowSyncHistory 
                (SyncType, Direction, RecordsProcessed, RecordsFailed, Status, JobId, InitiatedBy, EndTime)
                VALUES (@SyncType, @Direction, @RecordsProcessed, @RecordsFailed, @Status, @JobId, @InitiatedBy, GETDATE())
            `);
        
        logger.info(`User sync completed: ${processed} processed, ${errors.length} errors`);
        
    } catch (error) {
        logger.error('Error during user sync:', error);
    }
}

/**
 * Sync individual user to ServiceNow
 */
async function syncUserToServiceNow(user) {
    // This would make actual API calls to ServiceNow
    // For now, it's a placeholder
    logger.info(`Syncing user to ServiceNow: ${user.Email}`);
    
    // Simulate API call
    await new Promise(resolve => setTimeout(resolve, 100));
    
    return { success: true, sysId: 'SNOW' + user.UserID };
}

/**
 * Send notification
 */
async function sendNotification(type, data) {
    try {
        await redisClient.lpushAsync('notifications', JSON.stringify({
            type: type,
            data: data,
            timestamp: new Date().toISOString()
        }));
    } catch (error) {
        logger.error('Error sending notification:', error);
    }
}

/**
 * Main worker loop
 */
async function startWorker() {
    logger.info('ServiceNow worker started');
    
    // Process different queues
    setInterval(() => processApprovedRequests(), 5000);
    setInterval(() => syncUsers(), 10000);
    
    // Health check
    setInterval(async () => {
        try {
            await redisClient.pingAsync();
            logger.debug('Worker health check: OK');
        } catch (error) {
            logger.error('Worker health check failed:', error);
        }
    }, 30000);
}

// Graceful shutdown
process.on('SIGTERM', () => {
    logger.info('SIGTERM received, shutting down gracefully');
    redisClient.quit();
    sql.close();
    process.exit(0);
});

process.on('SIGINT', () => {
    logger.info('SIGINT received, shutting down gracefully');
    redisClient.quit();
    sql.close();
    process.exit(0);
});

// Start the worker
startWorker().catch(error => {
    logger.error('Failed to start worker:', error);
    process.exit(1);
});