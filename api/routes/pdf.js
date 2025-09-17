/**
 * PDF Processing API Routes
 * Express routes for PDF operations
 */

const express = require('express');
const router = express.Router();
const multer = require('multer');
const path = require('path');
const fs = require('fs').promises;
const { spawn } = require('child_process');
const crypto = require('crypto');
const redis = require('redis');
const { authenticateToken } = require('../middleware/auth');

// Configure multer for file uploads
const storage = multer.diskStorage({
    destination: async (req, file, cb) => {
        const uploadPath = path.join(__dirname, '../../uploads/pdf');
        await fs.mkdir(uploadPath, { recursive: true });
        cb(null, uploadPath);
    },
    filename: (req, file, cb) => {
        const uniqueName = `${Date.now()}-${crypto.randomBytes(6).toString('hex')}-${file.originalname}`;
        cb(null, uniqueName);
    }
});

const upload = multer({
    storage: storage,
    limits: {
        fileSize: 100 * 1024 * 1024, // 100MB limit
        files: 10 // Maximum 10 files
    },
    fileFilter: (req, file, cb) => {
        if (file.mimetype === 'application/pdf') {
            cb(null, true);
        } else {
            cb(new Error('Only PDF files are allowed'), false);
        }
    }
});

// Redis client for job tracking
const redisClient = redis.createClient({
    host: process.env.REDIS_HOST || 'localhost',
    port: process.env.REDIS_PORT || 6379
});

/**
 * @route   POST /api/pdf/merge
 * @desc    Merge multiple PDFs into one
 * @access  Protected
 */
router.post('/merge', authenticateToken, upload.array('pdfs', 10), async (req, res) => {
    try {
        if (!req.files || req.files.length < 2) {
            return res.status(400).json({ error: 'At least 2 PDF files required for merging' });
        }

        const jobId = crypto.randomBytes(16).toString('hex');
        const inputFiles = req.files.map(file => file.path);
        const outputFile = path.join(__dirname, '../../uploads/pdf', `merged-${jobId}.pdf`);

        // Create job in Redis
        await redisClient.setAsync(`pdf_job:${jobId}`, JSON.stringify({
            type: 'merge',
            status: 'processing',
            inputFiles,
            outputFile,
            user: req.user.username,
            createdAt: new Date().toISOString()
        }));

        // Execute Python PDF processor
        const pythonProcess = spawn('python3', [
            path.join(__dirname, '../../pdf-processing/pdf_processor.py'),
            '--operation', 'merge',
            '--input', inputFiles.join(','),
            '--output', outputFile,
            '--job-id', jobId
        ]);

        pythonProcess.on('close', async (code) => {
            if (code === 0) {
                await redisClient.setAsync(`pdf_job:${jobId}`, JSON.stringify({
                    status: 'completed',
                    outputFile
                }));
            } else {
                await redisClient.setAsync(`pdf_job:${jobId}`, JSON.stringify({
                    status: 'failed',
                    error: 'Processing failed'
                }));
            }
        });

        res.status(202).json({
            jobId,
            message: 'PDF merge job created',
            statusUrl: `/api/pdf/status/${jobId}`
        });
    } catch (error) {
        console.error('PDF merge error:', error);
        res.status(500).json({ error: 'Failed to process PDF merge request' });
    }
});

/**
 * @route   POST /api/pdf/split
 * @desc    Split PDF into multiple files
 * @access  Protected
 */
router.post('/split', authenticateToken, upload.single('pdf'), async (req, res) => {
    try {
        if (!req.file) {
            return res.status(400).json({ error: 'PDF file required' });
        }

        const { mode = 'pages', chunkSize = 10, pages } = req.body;
        const jobId = crypto.randomBytes(16).toString('hex');

        const job = {
            type: 'split',
            status: 'processing',
            inputFile: req.file.path,
            mode,
            options: { chunkSize, pages },
            user: req.user.username,
            createdAt: new Date().toISOString()
        };

        await redisClient.setAsync(`pdf_job:${jobId}`, JSON.stringify(job));

        // Process asynchronously
        processJob(jobId, 'split', req.file.path, { mode, chunkSize, pages });

        res.status(202).json({
            jobId,
            message: 'PDF split job created',
            statusUrl: `/api/pdf/status/${jobId}`
        });
    } catch (error) {
        console.error('PDF split error:', error);
        res.status(500).json({ error: 'Failed to process PDF split request' });
    }
});

/**
 * @route   POST /api/pdf/compress
 * @desc    Compress PDF file size
 * @access  Protected
 */
router.post('/compress', authenticateToken, upload.single('pdf'), async (req, res) => {
    try {
        if (!req.file) {
            return res.status(400).json({ error: 'PDF file required' });
        }

        const { quality = 85 } = req.body;
        const jobId = crypto.randomBytes(16).toString('hex');

        await redisClient.setAsync(`pdf_job:${jobId}`, JSON.stringify({
            type: 'compress',
            status: 'processing',
            inputFile: req.file.path,
            options: { quality },
            user: req.user.username
        }));

        processJob(jobId, 'compress', req.file.path, { quality });

        res.status(202).json({
            jobId,
            message: 'PDF compression job created',
            statusUrl: `/api/pdf/status/${jobId}`
        });
    } catch (error) {
        console.error('PDF compress error:', error);
        res.status(500).json({ error: 'Failed to process PDF compression request' });
    }
});

/**
 * @route   POST /api/pdf/ocr
 * @desc    Apply OCR to scanned PDF
 * @access  Protected
 */
router.post('/ocr', authenticateToken, upload.single('pdf'), async (req, res) => {
    try {
        if (!req.file) {
            return res.status(400).json({ error: 'PDF file required' });
        }

        const { language = 'eng' } = req.body;
        const jobId = crypto.randomBytes(16).toString('hex');

        await redisClient.setAsync(`pdf_job:${jobId}`, JSON.stringify({
            type: 'ocr',
            status: 'processing',
            inputFile: req.file.path,
            options: { language },
            user: req.user.username
        }));

        processJob(jobId, 'ocr', req.file.path, { language });

        res.status(202).json({
            jobId,
            message: 'OCR job created',
            statusUrl: `/api/pdf/status/${jobId}`
        });
    } catch (error) {
        console.error('OCR error:', error);
        res.status(500).json({ error: 'Failed to process OCR request' });
    }
});

/**
 * @route   POST /api/pdf/watermark
 * @desc    Add watermark to PDF
 * @access  Protected
 */
router.post('/watermark', authenticateToken, upload.single('pdf'), async (req, res) => {
    try {
        if (!req.file) {
            return res.status(400).json({ error: 'PDF file required' });
        }

        const { text = 'CONFIDENTIAL', position = 'center', opacity = 0.3 } = req.body;
        const jobId = crypto.randomBytes(16).toString('hex');

        await redisClient.setAsync(`pdf_job:${jobId}`, JSON.stringify({
            type: 'watermark',
            status: 'processing',
            inputFile: req.file.path,
            options: { text, position, opacity },
            user: req.user.username
        }));

        processJob(jobId, 'watermark', req.file.path, { text, position, opacity });

        res.status(202).json({
            jobId,
            message: 'Watermark job created',
            statusUrl: `/api/pdf/status/${jobId}`
        });
    } catch (error) {
        console.error('Watermark error:', error);
        res.status(500).json({ error: 'Failed to process watermark request' });
    }
});

/**
 * @route   POST /api/pdf/encrypt
 * @desc    Encrypt PDF with password
 * @access  Protected
 */
router.post('/encrypt', authenticateToken, upload.single('pdf'), async (req, res) => {
    try {
        if (!req.file) {
            return res.status(400).json({ error: 'PDF file required' });
        }

        const { userPassword, ownerPassword, permissions = ['print', 'copy'] } = req.body;

        if (!userPassword && !ownerPassword) {
            return res.status(400).json({ error: 'At least one password required' });
        }

        const jobId = crypto.randomBytes(16).toString('hex');

        await redisClient.setAsync(`pdf_job:${jobId}`, JSON.stringify({
            type: 'encrypt',
            status: 'processing',
            inputFile: req.file.path,
            options: { userPassword, ownerPassword, permissions },
            user: req.user.username
        }));

        processJob(jobId, 'encrypt', req.file.path, { userPassword, ownerPassword, permissions });

        res.status(202).json({
            jobId,
            message: 'Encryption job created',
            statusUrl: `/api/pdf/status/${jobId}`
        });
    } catch (error) {
        console.error('Encryption error:', error);
        res.status(500).json({ error: 'Failed to process encryption request' });
    }
});

/**
 * @route   POST /api/pdf/extract-text
 * @desc    Extract text from PDF
 * @access  Protected
 */
router.post('/extract-text', authenticateToken, upload.single('pdf'), async (req, res) => {
    try {
        if (!req.file) {
            return res.status(400).json({ error: 'PDF file required' });
        }

        const { format = 'txt' } = req.body;
        const jobId = crypto.randomBytes(16).toString('hex');

        await redisClient.setAsync(`pdf_job:${jobId}`, JSON.stringify({
            type: 'extract-text',
            status: 'processing',
            inputFile: req.file.path,
            options: { format },
            user: req.user.username
        }));

        processJob(jobId, 'extract_text', req.file.path, { format });

        res.status(202).json({
            jobId,
            message: 'Text extraction job created',
            statusUrl: `/api/pdf/status/${jobId}`
        });
    } catch (error) {
        console.error('Text extraction error:', error);
        res.status(500).json({ error: 'Failed to process text extraction request' });
    }
});

/**
 * @route   GET /api/pdf/status/:jobId
 * @desc    Get PDF job status
 * @access  Protected
 */
router.get('/status/:jobId', authenticateToken, async (req, res) => {
    try {
        const { jobId } = req.params;
        const jobData = await redisClient.getAsync(`pdf_job:${jobId}`);

        if (!jobData) {
            return res.status(404).json({ error: 'Job not found' });
        }

        const job = JSON.parse(jobData);

        // Check if job belongs to user
        if (job.user !== req.user.username && req.user.role !== 'admin') {
            return res.status(403).json({ error: 'Access denied' });
        }

        res.json(job);
    } catch (error) {
        console.error('Status check error:', error);
        res.status(500).json({ error: 'Failed to get job status' });
    }
});

/**
 * @route   GET /api/pdf/download/:jobId
 * @desc    Download processed PDF
 * @access  Protected
 */
router.get('/download/:jobId', authenticateToken, async (req, res) => {
    try {
        const { jobId } = req.params;
        const jobData = await redisClient.getAsync(`pdf_job:${jobId}`);

        if (!jobData) {
            return res.status(404).json({ error: 'Job not found' });
        }

        const job = JSON.parse(jobData);

        // Check if job belongs to user
        if (job.user !== req.user.username && req.user.role !== 'admin') {
            return res.status(403).json({ error: 'Access denied' });
        }

        if (job.status !== 'completed') {
            return res.status(400).json({ error: 'Job not completed', status: job.status });
        }

        // Send file
        res.download(job.outputFile, `processed-${jobId}.pdf`, (err) => {
            if (err) {
                console.error('Download error:', err);
                res.status(500).json({ error: 'Failed to download file' });
            }
        });
    } catch (error) {
        console.error('Download error:', error);
        res.status(500).json({ error: 'Failed to download file' });
    }
});

/**
 * @route   POST /api/pdf/batch
 * @desc    Process multiple PDF operations in batch
 * @access  Protected
 */
router.post('/batch', authenticateToken, async (req, res) => {
    try {
        const { operations } = req.body;

        if (!Array.isArray(operations) || operations.length === 0) {
            return res.status(400).json({ error: 'Operations array required' });
        }

        if (operations.length > 10) {
            return res.status(400).json({ error: 'Maximum 10 operations per batch' });
        }

        const jobIds = [];

        for (const operation of operations) {
            const jobId = crypto.randomBytes(16).toString('hex');
            jobIds.push(jobId);

            await redisClient.setAsync(`pdf_job:${jobId}`, JSON.stringify({
                ...operation,
                status: 'queued',
                user: req.user.username,
                createdAt: new Date().toISOString()
            }));

            // Queue for processing
            await redisClient.lpushAsync('pdf_job_queue', jobId);
        }

        res.json({
            batchId: crypto.randomBytes(8).toString('hex'),
            jobIds,
            message: `${operations.length} jobs queued for processing`
        });
    } catch (error) {
        console.error('Batch processing error:', error);
        res.status(500).json({ error: 'Failed to process batch request' });
    }
});

// Helper function to process jobs
async function processJob(jobId, operation, inputFile, options) {
    const outputFile = path.join(
        path.dirname(inputFile),
        `processed-${jobId}.pdf`
    );

    const args = [
        path.join(__dirname, '../../pdf-processing/pdf_processor.py'),
        '--operation', operation,
        '--input', inputFile,
        '--output', outputFile,
        '--job-id', jobId,
        '--options', JSON.stringify(options)
    ];

    const pythonProcess = spawn('python3', args);

    pythonProcess.stdout.on('data', (data) => {
        console.log(`PDF processor: ${data}`);
    });

    pythonProcess.stderr.on('data', (data) => {
        console.error(`PDF processor error: ${data}`);
    });

    pythonProcess.on('close', async (code) => {
        const job = JSON.parse(await redisClient.getAsync(`pdf_job:${jobId}`));

        if (code === 0) {
            job.status = 'completed';
            job.outputFile = outputFile;
            job.completedAt = new Date().toISOString();

            // Get file stats
            const stats = await fs.stat(outputFile);
            job.outputSize = stats.size;
        } else {
            job.status = 'failed';
            job.error = 'Processing failed';
            job.failedAt = new Date().toISOString();
        }

        await redisClient.setAsync(`pdf_job:${jobId}`, JSON.stringify(job));
    });
}

module.exports = router;