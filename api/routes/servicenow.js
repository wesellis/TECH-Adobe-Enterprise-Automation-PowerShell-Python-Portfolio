/**
 * ServiceNow Integration API Routes
 * Handles incident creation, user provisioning, and workflow automation
 */

const express = require('express');
const router = express.Router();
const axios = require('axios');
const { body, validationResult } = require('express-validator');
const winston = require('winston');
const redis = require('redis');
const sql = require('mssql');
const crypto = require('crypto');
const { authenticateToken } = require('../middleware/auth');

// Logger setup
const logger = winston.createLogger({
    level: 'info',
    format: winston.format.json(),
    transports: [
        new winston.transports.File({ filename: 'servicenow.log' }),
        new winston.transports.Console()
    ]
});

// Redis client
const redisClient = redis.createClient({
    host: process.env.REDIS_HOST || 'localhost',
    port: process.env.REDIS_PORT || 6379
});

// ServiceNow configuration
const serviceNowConfig = {
    instance: process.env.SNOW_INSTANCE || 'dev12345.service-now.com',
    username: process.env.SNOW_USERNAME,
    password: process.env.SNOW_PASSWORD,
    clientId: process.env.SNOW_CLIENT_ID,
    clientSecret: process.env.SNOW_CLIENT_SECRET
};

// ServiceNow API client
class ServiceNowClient {
    constructor(config) {
        this.config = config;
        this.baseURL = `https://${config.instance}/api/now`;
        this.token = null;
        this.tokenExpiry = null;
    }

    async getAuthToken() {
        if (this.token && this.tokenExpiry > Date.now()) {
            return this.token;
        }

        try {
            const response = await axios.post(
                `https://${this.config.instance}/oauth_token.do`,
                new URLSearchParams({
                    grant_type: 'password',
                    client_id: this.config.clientId,
                    client_secret: this.config.clientSecret,
                    username: this.config.username,
                    password: this.config.password
                }),
                {
                    headers: {
                        'Content-Type': 'application/x-www-form-urlencoded'
                    }
                }
            );

            this.token = response.data.access_token;
            this.tokenExpiry = Date.now() + (response.data.expires_in * 1000);
            return this.token;
        } catch (error) {
            logger.error('ServiceNow auth error:', error.response?.data || error.message);
            throw new Error('Failed to authenticate with ServiceNow');
        }
    }

    async makeRequest(method, endpoint, data = null) {
        const token = await this.getAuthToken();

        try {
            const response = await axios({
                method,
                url: `${this.baseURL}${endpoint}`,
                headers: {
                    'Authorization': `Bearer ${token}`,
                    'Accept': 'application/json',
                    'Content-Type': 'application/json'
                },
                data
            });

            return response.data;
        } catch (error) {
            logger.error('ServiceNow API error:', error.response?.data || error.message);
            throw error;
        }
    }
}

const snowClient = new ServiceNowClient(serviceNowConfig);

/**
 * @route   POST /api/servicenow/incident
 * @desc    Create incident in ServiceNow
 * @access  Protected
 */
router.post('/incident',
    authenticateToken,
    [
        body('short_description').notEmpty(),
        body('description').notEmpty(),
        body('urgency').isIn(['1', '2', '3']).optional(),
        body('impact').isIn(['1', '2', '3']).optional(),
        body('category').optional(),
        body('assignment_group').optional()
    ],
    async (req, res) => {
        const errors = validationResult(req);
        if (!errors.isEmpty()) {
            return res.status(400).json({ errors: errors.array() });
        }

        try {
            const incidentData = {
                short_description: req.body.short_description,
                description: req.body.description,
                urgency: req.body.urgency || '3',
                impact: req.body.impact || '3',
                category: req.body.category || 'Software',
                subcategory: 'Adobe Creative Cloud',
                assignment_group: req.body.assignment_group || 'IT Support',
                caller_id: req.user.username,
                opened_by: req.user.username,
                contact_type: 'API',
                u_custom_field_adobe: 'true'
            };

            const result = await snowClient.makeRequest('POST', '/table/incident', incidentData);

            // Cache incident for quick retrieval
            await redisClient.setAsync(
                `snow:incident:${result.result.sys_id}`,
                JSON.stringify(result.result),
                'EX',
                3600
            );

            // Log to database
            const pool = await sql.connect();
            await pool.request()
                .input('IncidentNumber', sql.NVarChar, result.result.number)
                .input('SysId', sql.NVarChar, result.result.sys_id)
                .input('ShortDescription', sql.NVarChar, req.body.short_description)
                .input('CreatedBy', sql.NVarChar, req.user.username)
                .query(`
                    INSERT INTO adobe.ServiceNowIncidents 
                    (IncidentNumber, SysId, ShortDescription, Status, CreatedBy, CreatedAt)
                    VALUES (@IncidentNumber, @SysId, @ShortDescription, 'Open', @CreatedBy, GETDATE())
                `);

            res.status(201).json({
                success: true,
                incident: {
                    number: result.result.number,
                    sys_id: result.result.sys_id,
                    state: result.result.state,
                    url: `https://${serviceNowConfig.instance}/nav_to.do?uri=incident.do?sys_id=${result.result.sys_id}`
                }
            });

            logger.info(`Incident created: ${result.result.number}`);
        } catch (error) {
            logger.error('Create incident error:', error);
            res.status(500).json({ error: 'Failed to create incident' });
        }
    }
);

/**
 * @route   POST /api/servicenow/request
 * @desc    Create service catalog request for Adobe provisioning
 * @access  Protected
 */
router.post('/request',
    authenticateToken,
    [
        body('request_type').isIn(['new_user', 'add_license', 'remove_license', 'deactivate_user']),
        body('user_email').isEmail(),
        body('products').isArray().optional(),
        body('justification').notEmpty()
    ],
    async (req, res) => {
        const errors = validationResult(req);
        if (!errors.isEmpty()) {
            return res.status(400).json({ errors: errors.array() });
        }

        try {
            const { request_type, user_email, products, justification } = req.body;

            // Map request type to catalog item
            const catalogItems = {
                'new_user': 'adobe_new_user_provision',
                'add_license': 'adobe_add_license',
                'remove_license': 'adobe_remove_license',
                'deactivate_user': 'adobe_user_deactivation'
            };

            const requestData = {
                sysparm_quantity: '1',
                variables: {
                    requested_for: req.user.username,
                    user_email: user_email,
                    products: products ? products.join(',') : '',
                    justification: justification,
                    department: req.user.department || 'IT',
                    cost_center: req.user.cost_center || 'DEFAULT'
                }
            };

            const result = await snowClient.makeRequest(
                'POST',
                `/service_catalog/items/${catalogItems[request_type]}/order_now`,
                requestData
            );

            // Queue for processing
            const jobId = crypto.randomBytes(16).toString('hex');
            await redisClient.lpushAsync('snow_request_queue', JSON.stringify({
                jobId,
                requestType: request_type,
                userEmail: user_email,
                products,
                requestNumber: result.result.request_number,
                sysId: result.result.sys_id,
                requestedBy: req.user.username,
                createdAt: new Date().toISOString()
            }));

            res.status(201).json({
                success: true,
                request: {
                    number: result.result.request_number,
                    sys_id: result.result.sys_id,
                    state: result.result.request_state,
                    jobId: jobId
                }
            });

            logger.info(`Service request created: ${result.result.request_number}`);
        } catch (error) {
            logger.error('Create request error:', error);
            res.status(500).json({ error: 'Failed to create service request' });
        }
    }
);

/**
 * @route   GET /api/servicenow/incident/:number
 * @desc    Get incident details
 * @access  Protected
 */
router.get('/incident/:number', authenticateToken, async (req, res) => {
    try {
        const { number } = req.params;

        // Check cache first
        const cached = await redisClient.getAsync(`snow:incident:number:${number}`);
        if (cached) {
            return res.json(JSON.parse(cached));
        }

        const result = await snowClient.makeRequest(
            'GET',
            `/table/incident?sysparm_query=number=${number}&sysparm_limit=1`
        );

        if (result.result.length === 0) {
            return res.status(404).json({ error: 'Incident not found' });
        }

        const incident = result.result[0];

        // Cache for 5 minutes
        await redisClient.setAsync(
            `snow:incident:number:${number}`,
            JSON.stringify(incident),
            'EX',
            300
        );

        res.json(incident);
    } catch (error) {
        logger.error('Get incident error:', error);
        res.status(500).json({ error: 'Failed to retrieve incident' });
    }
});

/**
 * @route   PUT /api/servicenow/incident/:sys_id
 * @desc    Update incident
 * @access  Protected
 */
router.put('/incident/:sys_id',
    authenticateToken,
    [
        body('work_notes').optional(),
        body('state').isIn(['1', '2', '3', '6', '7']).optional(),
        body('assignment_group').optional()
    ],
    async (req, res) => {
        const errors = validationResult(req);
        if (!errors.isEmpty()) {
            return res.status(400).json({ errors: errors.array() });
        }

        try {
            const { sys_id } = req.params;
            const updateData = {};

            if (req.body.work_notes) updateData.work_notes = req.body.work_notes;
            if (req.body.state) updateData.state = req.body.state;
            if (req.body.assignment_group) updateData.assignment_group = req.body.assignment_group;

            const result = await snowClient.makeRequest(
                'PUT',
                `/table/incident/${sys_id}`,
                updateData
            );

            // Invalidate cache
            await redisClient.delAsync(`snow:incident:${sys_id}`);

            res.json({
                success: true,
                incident: result.result
            });

            logger.info(`Incident updated: ${sys_id}`);
        } catch (error) {
            logger.error('Update incident error:', error);
            res.status(500).json({ error: 'Failed to update incident' });
        }
    }
);

/**
 * @route   POST /api/servicenow/webhook
 * @desc    Receive webhooks from ServiceNow
 * @access  Public (with signature verification)
 */
router.post('/webhook', async (req, res) => {
    try {
        // Verify webhook signature
        const signature = req.headers['x-servicenow-signature'];
        const expectedSignature = crypto
            .createHmac('sha256', process.env.SNOW_WEBHOOK_SECRET || 'webhook_secret')
            .update(JSON.stringify(req.body))
            .digest('hex');

        if (signature !== expectedSignature) {
            return res.status(401).json({ error: 'Invalid signature' });
        }

        const { event_type, data } = req.body;

        logger.info(`ServiceNow webhook received: ${event_type}`);

        switch (event_type) {
            case 'incident.updated':
                await handleIncidentUpdate(data);
                break;
            case 'request.approved':
                await handleRequestApproval(data);
                break;
            case 'request.rejected':
                await handleRequestRejection(data);
                break;
            case 'task.assigned':
                await handleTaskAssignment(data);
                break;
            default:
                logger.warn(`Unknown webhook event: ${event_type}`);
        }

        res.json({ received: true });
    } catch (error) {
        logger.error('Webhook error:', error);
        res.status(500).json({ error: 'Webhook processing failed' });
    }
});

/**
 * @route   GET /api/servicenow/user/:email
 * @desc    Get ServiceNow user details
 * @access  Protected
 */
router.get('/user/:email', authenticateToken, async (req, res) => {
    try {
        const { email } = req.params;

        const result = await snowClient.makeRequest(
            'GET',
            `/table/sys_user?sysparm_query=email=${email}&sysparm_limit=1`
        );

        if (result.result.length === 0) {
            return res.status(404).json({ error: 'User not found in ServiceNow' });
        }

        res.json({
            user: {
                sys_id: result.result[0].sys_id,
                email: result.result[0].email,
                name: result.result[0].name,
                department: result.result[0].department,
                manager: result.result[0].manager,
                active: result.result[0].active
            }
        });
    } catch (error) {
        logger.error('Get user error:', error);
        res.status(500).json({ error: 'Failed to retrieve user' });
    }
});

/**
 * @route   POST /api/servicenow/sync/users
 * @desc    Sync Adobe users with ServiceNow
 * @access  Protected (Admin only)
 */
router.post('/sync/users', authenticateToken, async (req, res) => {
    if (req.user.role !== 'admin') {
        return res.status(403).json({ error: 'Admin access required' });
    }

    try {
        const jobId = crypto.randomBytes(16).toString('hex');

        // Queue sync job
        await redisClient.lpushAsync('sync_queue', JSON.stringify({
            jobId,
            type: 'user_sync',
            source: 'servicenow',
            initiatedBy: req.user.username,
            timestamp: new Date().toISOString()
        }));

        res.status(202).json({
            success: true,
            jobId,
            message: 'User sync initiated',
            statusUrl: `/api/servicenow/sync/status/${jobId}`
        });

        logger.info(`User sync initiated by ${req.user.username}`);
    } catch (error) {
        logger.error('Sync error:', error);
        res.status(500).json({ error: 'Failed to initiate sync' });
    }
});

/**
 * @route   GET /api/servicenow/sync/status/:jobId
 * @desc    Get sync job status
 * @access  Protected
 */
router.get('/sync/status/:jobId', authenticateToken, async (req, res) => {
    try {
        const { jobId } = req.params;
        const status = await redisClient.getAsync(`sync:status:${jobId}`);

        if (!status) {
            return res.status(404).json({ error: 'Sync job not found' });
        }

        res.json(JSON.parse(status));
    } catch (error) {
        logger.error('Get sync status error:', error);
        res.status(500).json({ error: 'Failed to retrieve sync status' });
    }
});

/**
 * @route   GET /api/servicenow/reports/integration
 * @desc    Get integration statistics
 * @access  Protected
 */
router.get('/reports/integration', authenticateToken, async (req, res) => {
    try {
        const pool = await sql.connect();
        const result = await pool.request().query(`
            SELECT 
                COUNT(*) as total_incidents,
                SUM(CASE WHEN Status = 'Open' THEN 1 ELSE 0 END) as open_incidents,
                SUM(CASE WHEN Status = 'Resolved' THEN 1 ELSE 0 END) as resolved_incidents,
                AVG(DATEDIFF(hour, CreatedAt, ResolvedAt)) as avg_resolution_hours
            FROM adobe.ServiceNowIncidents
            WHERE CreatedAt >= DATEADD(day, -30, GETDATE())
        `);

        const stats = result.recordset[0];

        // Get request stats from cache
        const requestStats = await redisClient.getAsync('snow:request:stats');

        res.json({
            incidents: stats,
            requests: requestStats ? JSON.parse(requestStats) : {},
            lastSync: await redisClient.getAsync('snow:last:sync')
        });
    } catch (error) {
        logger.error('Get integration report error:', error);
        res.status(500).json({ error: 'Failed to generate report' });
    }
});

// Helper functions
async function handleIncidentUpdate(data) {
    try {
        const pool = await sql.connect();
        await pool.request()
            .input('SysId', sql.NVarChar, data.sys_id)
            .input('State', sql.NVarChar, data.state)
            .input('UpdatedAt', sql.DateTime, new Date())
            .query(`
                UPDATE adobe.ServiceNowIncidents
                SET Status = @State, UpdatedAt = @UpdatedAt
                WHERE SysId = @SysId
            `);

        logger.info(`Incident ${data.number} updated to state ${data.state}`);
    } catch (error) {
        logger.error('Handle incident update error:', error);
    }
}

async function handleRequestApproval(data) {
    try {
        // Queue for Adobe provisioning
        await redisClient.lpushAsync('approved_requests', JSON.stringify({
            requestNumber: data.request_number,
            userEmail: data.variables.user_email,
            products: data.variables.products?.split(',') || [],
            approvedBy: data.approved_by,
            approvedAt: new Date().toISOString()
        }));

        logger.info(`Request ${data.request_number} approved`);
    } catch (error) {
        logger.error('Handle request approval error:', error);
    }
}

async function handleRequestRejection(data) {
    try {
        // Update status in database
        const pool = await sql.connect();
        await pool.request()
            .input('RequestNumber', sql.NVarChar, data.request_number)
            .input('RejectionReason', sql.NVarChar, data.rejection_reason)
            .query(`
                UPDATE adobe.ProvisioningQueue
                SET Status = 'Rejected', Notes = @RejectionReason
                WHERE RequestNumber = @RequestNumber
            `);

        logger.info(`Request ${data.request_number} rejected`);
    } catch (error) {
        logger.error('Handle request rejection error:', error);
    }
}

async function handleTaskAssignment(data) {
    try {
        // Notify assigned user
        await redisClient.lpushAsync('notifications', JSON.stringify({
            type: 'task_assigned',
            assignedTo: data.assigned_to,
            taskNumber: data.task_number,
            shortDescription: data.short_description,
            priority: data.priority
        }));

        logger.info(`Task ${data.task_number} assigned to ${data.assigned_to}`);
    } catch (error) {
        logger.error('Handle task assignment error:', error);
    }
}

module.exports = router;