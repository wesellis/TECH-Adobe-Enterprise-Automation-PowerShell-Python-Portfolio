/**
 * Adobe Automation REST API Server
 * Production-ready Express.js API with authentication, rate limiting, and monitoring
 */

const express = require('express');
const cors = require('cors');
const helmet = require('helmet');
const compression = require('compression');
const rateLimit = require('express-rate-limit');
const jwt = require('jsonwebtoken');
const { body, validationResult } = require('express-validator');
const winston = require('winston');
const promClient = require('prom-client');
const redis = require('redis');
const sql = require('mssql');
const { spawn } = require('child_process');

// Initialize Express app
const app = express();
const PORT = process.env.API_PORT || 8000;

// Redis client
const redisClient = redis.createClient({
    host: process.env.REDIS_HOST || 'localhost',
    port: process.env.REDIS_PORT || 6379
});

// SQL configuration
const sqlConfig = {
    user: process.env.DB_USER,
    password: process.env.DB_PASSWORD,
    database: process.env.DB_NAME,
    server: process.env.DB_HOST,
    pool: {
        max: 10,
        min: 0,
        idleTimeoutMillis: 30000
    },
    options: {
        encrypt: true,
        trustServerCertificate: false
    }
};

// Logger configuration
const logger = winston.createLogger({
    level: process.env.LOG_LEVEL || 'info',
    format: winston.format.json(),
    transports: [
        new winston.transports.File({ filename: 'error.log', level: 'error' }),
        new winston.transports.File({ filename: 'combined.log' }),
        new winston.transports.Console({
            format: winston.format.simple()
        })
    ]
});

// Prometheus metrics
const collectDefaultMetrics = promClient.collectDefaultMetrics;
collectDefaultMetrics();

const httpRequestDuration = new promClient.Histogram({
    name: 'http_request_duration_seconds',
    help: 'Duration of HTTP requests in seconds',
    labelNames: ['method', 'route', 'status']
});

const apiCallsTotal = new promClient.Counter({
    name: 'adobe_api_calls_total',
    help: 'Total number of API calls',
    labelNames: ['endpoint', 'method']
});

// Middleware
app.use(helmet());
app.use(compression());
app.use(cors());
app.use(express.json());
app.use(express.urlencoded({ extended: true }));

// Request logging middleware
app.use((req, res, next) => {
    const start = Date.now();

    res.on('finish', () => {
        const duration = Date.now() - start;
        logger.info({
            method: req.method,
            url: req.url,
            status: res.statusCode,
            duration: duration
        });

        httpRequestDuration
            .labels(req.method, req.route?.path || req.url, res.statusCode)
            .observe(duration / 1000);
    });

    next();
});

// Rate limiting
const limiter = rateLimit({
    windowMs: 1 * 60 * 1000, // 1 minute
    max: process.env.RATE_LIMIT || 100,
    message: 'Too many requests from this IP, please try again later.',
    standardHeaders: true,
    legacyHeaders: false,
});

app.use('/api/', limiter);

// JWT Authentication middleware
const authenticateToken = (req, res, next) => {
    const authHeader = req.headers['authorization'];
    const token = authHeader && authHeader.split(' ')[1];

    if (!token) {
        return res.status(401).json({ error: 'Access token required' });
    }

    jwt.verify(token, process.env.JWT_SECRET, (err, user) => {
        if (err) {
            return res.status(403).json({ error: 'Invalid or expired token' });
        }
        req.user = user;
        next();
    });
};

// API Key authentication for external services
const authenticateApiKey = (req, res, next) => {
    const apiKey = req.headers['x-api-key'];

    if (!apiKey || apiKey !== process.env.API_KEY) {
        return res.status(401).json({ error: 'Invalid API key' });
    }

    next();
};

// ==================== ROUTES ====================

// Health check endpoint
app.get('/health', async (req, res) => {
    const health = {
        status: 'healthy',
        timestamp: new Date().toISOString(),
        uptime: process.uptime(),
        checks: {}
    };

    // Check Redis
    try {
        await redisClient.ping();
        health.checks.redis = 'healthy';
    } catch (error) {
        health.checks.redis = 'unhealthy';
        health.status = 'degraded';
    }

    // Check SQL
    try {
        const pool = await sql.connect(sqlConfig);
        await pool.request().query('SELECT 1');
        health.checks.database = 'healthy';
    } catch (error) {
        health.checks.database = 'unhealthy';
        health.status = 'unhealthy';
    }

    const statusCode = health.status === 'healthy' ? 200 : 503;
    res.status(statusCode).json(health);
});

// Metrics endpoint for Prometheus
app.get('/metrics', (req, res) => {
    res.set('Content-Type', promClient.register.contentType);
    promClient.register.metrics().then(metrics => {
        res.end(metrics);
    });
});

// Authentication endpoint
app.post('/api/auth/login',
    body('username').isEmail(),
    body('password').isLength({ min: 8 }),
    async (req, res) => {
        const errors = validationResult(req);
        if (!errors.isEmpty()) {
            return res.status(400).json({ errors: errors.array() });
        }

        const { username, password } = req.body;

        try {
            // Validate credentials (simplified for demo)
            // In production, check against database with hashed passwords

            const token = jwt.sign(
                { username, role: 'admin' },
                process.env.JWT_SECRET,
                { expiresIn: '24h' }
            );

            res.json({
                token,
                expiresIn: 86400,
                user: { username, role: 'admin' }
            });

            logger.info(`User logged in: ${username}`);
        } catch (error) {
            logger.error('Login error:', error);
            res.status(500).json({ error: 'Authentication failed' });
        }
});

// User provisioning endpoint
app.post('/api/users',
    authenticateToken,
    body('email').isEmail(),
    body('firstName').notEmpty(),
    body('lastName').notEmpty(),
    async (req, res) => {
        const errors = validationResult(req);
        if (!errors.isEmpty()) {
            return res.status(400).json({ errors: errors.array() });
        }

        const { email, firstName, lastName, products, department } = req.body;

        try {
            apiCallsTotal.labels('/api/users', 'POST').inc();

            // Add to provisioning queue
            await redisClient.rpush('user_provision_queue', JSON.stringify({
                email,
                firstName,
                lastName,
                products: products || [],
                department,
                requestedBy: req.user.username,
                timestamp: new Date().toISOString()
            }));

            // Log to database
            const pool = await sql.connect(sqlConfig);
            await pool.request()
                .input('email', sql.NVarChar, email)
                .input('firstName', sql.NVarChar, firstName)
                .input('lastName', sql.NVarChar, lastName)
                .input('department', sql.NVarChar, department)
                .input('products', sql.NVarChar, JSON.stringify(products))
                .execute('sp_QueueUserForProvisioning');

            res.status(202).json({
                message: 'User queued for provisioning',
                email,
                queuePosition: await redisClient.llen('user_provision_queue')
            });

            logger.info(`User provisioning queued: ${email}`);
        } catch (error) {
            logger.error('User provisioning error:', error);
            res.status(500).json({ error: 'Failed to queue user provisioning' });
        }
});

// Get user endpoint
app.get('/api/users/:email', authenticateToken, async (req, res) => {
    const { email } = req.params;

    try {
        apiCallsTotal.labels('/api/users/:email', 'GET').inc();

        // Check cache first
        const cached = await redisClient.get(`user:${email}`);
        if (cached) {
            return res.json(JSON.parse(cached));
        }

        // Query database
        const pool = await sql.connect(sqlConfig);
        const result = await pool.request()
            .input('email', sql.NVarChar, email)
            .execute('sp_GetUserWithLicenses');

        if (result.recordset.length === 0) {
            return res.status(404).json({ error: 'User not found' });
        }

        const user = result.recordset[0];
        user.licenses = JSON.parse(user.Licenses || '[]');

        // Cache for 5 minutes
        await redisClient.setex(`user:${email}`, 300, JSON.stringify(user));

        res.json(user);
    } catch (error) {
        logger.error('Get user error:', error);
        res.status(500).json({ error: 'Failed to retrieve user' });
    }
});

// Bulk user upload endpoint
app.post('/api/users/bulk',
    authenticateToken,
    async (req, res) => {
        const { users } = req.body;

        if (!Array.isArray(users) || users.length === 0) {
            return res.status(400).json({ error: 'Users array required' });
        }

        if (users.length > 1000) {
            return res.status(400).json({ error: 'Maximum 1000 users per request' });
        }

        try {
            apiCallsTotal.labels('/api/users/bulk', 'POST').inc();

            // Add to queue
            const jobId = `bulk_${Date.now()}`;
            await redisClient.setex(`job:${jobId}`, 3600, JSON.stringify({
                status: 'processing',
                total: users.length,
                processed: 0,
                errors: []
            }));

            // Process async
            setImmediate(async () => {
                for (const user of users) {
                    await redisClient.rpush('user_provision_queue', JSON.stringify(user));
                }
            });

            res.status(202).json({
                jobId,
                message: `${users.length} users queued for processing`,
                statusUrl: `/api/jobs/${jobId}`
            });

            logger.info(`Bulk upload initiated: ${users.length} users`);
        } catch (error) {
            logger.error('Bulk upload error:', error);
            res.status(500).json({ error: 'Failed to process bulk upload' });
        }
});

// License optimization endpoint
app.post('/api/licenses/optimize', authenticateToken, async (req, res) => {
    try {
        apiCallsTotal.labels('/api/licenses/optimize', 'POST').inc();

        // Trigger PowerShell script
        const ps = spawn('pwsh', [
            '-File',
            './creative-cloud/license-management/Optimize-Licenses.ps1'
        ]);

        let output = '';
        ps.stdout.on('data', (data) => {
            output += data.toString();
        });

        ps.on('close', (code) => {
            if (code === 0) {
                res.json({
                    success: true,
                    message: 'License optimization completed',
                    results: output
                });
            } else {
                res.status(500).json({
                    success: false,
                    error: 'Optimization failed'
                });
            }
        });

        logger.info('License optimization triggered');
    } catch (error) {
        logger.error('License optimization error:', error);
        res.status(500).json({ error: 'Failed to optimize licenses' });
    }
});

// Get license utilization
app.get('/api/licenses/utilization', authenticateToken, async (req, res) => {
    try {
        apiCallsTotal.labels('/api/licenses/utilization', 'GET').inc();

        const pool = await sql.connect(sqlConfig);
        const result = await pool.request()
            .execute('sp_GetLicenseUtilization');

        res.json({
            products: result.recordset,
            summary: {
                totalLicenses: result.recordset.reduce((sum, p) => sum + p.TotalLicenses, 0),
                usedLicenses: result.recordset.reduce((sum, p) => sum + p.UsedLicenses, 0),
                monthlySpend: result.recordset.reduce((sum, p) => sum + (p.UsedLicenses * p.CostPerLicense), 0),
                potentialSavings: result.recordset.reduce((sum, p) => sum + p.PotentialMonthlySavings, 0)
            }
        });
    } catch (error) {
        logger.error('Get utilization error:', error);
        res.status(500).json({ error: 'Failed to get license utilization' });
    }
});

// Reporting endpoints
app.get('/api/reports/inactive-users', authenticateToken, async (req, res) => {
    const { days = 90 } = req.query;

    try {
        const pool = await sql.connect(sqlConfig);
        const result = await pool.request()
            .input('daysInactive', sql.Int, parseInt(days))
            .execute('sp_FindInactiveUsers');

        res.json({
            users: result.recordset,
            summary: {
                totalInactive: result.recordset.length,
                licensesReclaimable: result.recordset.reduce((sum, u) => sum + u.ActiveLicenses, 0),
                potentialSavings: result.recordset.reduce((sum, u) => sum + u.MonthlyCost, 0)
            }
        });
    } catch (error) {
        logger.error('Inactive users report error:', error);
        res.status(500).json({ error: 'Failed to generate report' });
    }
});

// Job status endpoint
app.get('/api/jobs/:jobId', authenticateToken, async (req, res) => {
    const { jobId } = req.params;

    try {
        const job = await redisClient.get(`job:${jobId}`);

        if (!job) {
            return res.status(404).json({ error: 'Job not found' });
        }

        res.json(JSON.parse(job));
    } catch (error) {
        logger.error('Job status error:', error);
        res.status(500).json({ error: 'Failed to get job status' });
    }
});

// Webhook endpoint for external integrations
app.post('/api/webhooks/provision',
    authenticateApiKey,
    async (req, res) => {
        const { event, data } = req.body;

        try {
            logger.info(`Webhook received: ${event}`);

            switch (event) {
                case 'user.created':
                    await redisClient.rpush('user_provision_queue', JSON.stringify(data));
                    break;
                case 'user.deleted':
                    await redisClient.rpush('user_deprovision_queue', JSON.stringify(data));
                    break;
                default:
                    logger.warn(`Unknown webhook event: ${event}`);
            }

            res.json({ received: true });
        } catch (error) {
            logger.error('Webhook error:', error);
            res.status(500).json({ error: 'Webhook processing failed' });
        }
});

// Error handling middleware
app.use((err, req, res, next) => {
    logger.error(err.stack);
    res.status(500).json({
        error: 'Internal server error',
        message: process.env.NODE_ENV === 'development' ? err.message : undefined
    });
});

// 404 handler
app.use((req, res) => {
    res.status(404).json({ error: 'Endpoint not found' });
});

// Start server
const server = app.listen(PORT, () => {
    logger.info(`Adobe Automation API running on port ${PORT}`);
    logger.info(`Environment: ${process.env.NODE_ENV || 'development'}`);
});

// Graceful shutdown
process.on('SIGTERM', () => {
    logger.info('SIGTERM signal received: closing HTTP server');
    server.close(() => {
        logger.info('HTTP server closed');
        sql.close();
        redisClient.quit();
        process.exit(0);
    });
});

module.exports = app;