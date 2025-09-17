/**
 * Authentication Middleware
 * JWT token verification for API routes
 */

const jwt = require('jsonwebtoken');
const winston = require('winston');

// Logger
const logger = winston.createLogger({
    level: 'info',
    format: winston.format.json(),
    transports: [
        new winston.transports.File({ filename: 'auth.log' }),
        new winston.transports.Console()
    ]
});

/**
 * Verify JWT token middleware
 */
function authenticateToken(req, res, next) {
    const authHeader = req.headers['authorization'];
    const token = authHeader && authHeader.split(' ')[1];

    if (!token) {
        logger.warn(`Unauthorized access attempt from IP: ${req.ip}`);
        return res.status(401).json({ error: 'Access token required' });
    }

    jwt.verify(token, process.env.JWT_SECRET || 'your-secret-key', (err, user) => {
        if (err) {
            logger.warn(`Invalid token from IP: ${req.ip}`);
            return res.status(403).json({ error: 'Invalid or expired token' });
        }

        req.user = user;
        next();
    });
}

/**
 * Verify API key middleware for external services
 */
function authenticateApiKey(req, res, next) {
    const apiKey = req.headers['x-api-key'];

    if (!apiKey) {
        logger.warn(`Missing API key from IP: ${req.ip}`);
        return res.status(401).json({ error: 'API key required' });
    }

    if (apiKey !== process.env.API_KEY) {
        logger.warn(`Invalid API key from IP: ${req.ip}`);
        return res.status(401).json({ error: 'Invalid API key' });
    }

    next();
}

/**
 * Admin role verification middleware
 */
function requireAdmin(req, res, next) {
    if (!req.user || req.user.role !== 'admin') {
        logger.warn(`Admin access denied for user: ${req.user?.username || 'unknown'}`);
        return res.status(403).json({ error: 'Admin access required' });
    }
    next();
}

/**
 * Service account verification middleware
 */
function authenticateService(req, res, next) {
    const serviceToken = req.headers['x-service-token'];

    if (!serviceToken) {
        return res.status(401).json({ error: 'Service token required' });
    }

    jwt.verify(serviceToken, process.env.SERVICE_SECRET || 'service-secret', (err, service) => {
        if (err) {
            logger.warn(`Invalid service token from IP: ${req.ip}`);
            return res.status(403).json({ error: 'Invalid service token' });
        }

        req.service = service;
        next();
    });
}

module.exports = {
    authenticateToken,
    authenticateApiKey,
    requireAdmin,
    authenticateService
};