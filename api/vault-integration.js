/**
 * HashiCorp Vault Integration for Secrets Management
 * Secure storage and retrieval of sensitive configuration
 */

const vault = require('node-vault');
const winston = require('winston');

// Configure logger
const logger = winston.createLogger({
  level: 'info',
  format: winston.format.json(),
  transports: [
    new winston.transports.Console({
      format: winston.format.simple()
    })
  ]
});

class VaultManager {
  constructor(options = {}) {
    this.options = {
      endpoint: process.env.VAULT_ENDPOINT || 'http://127.0.0.1:8200',
      token: process.env.VAULT_TOKEN,
      apiVersion: options.apiVersion || 'v1',
      namespace: process.env.VAULT_NAMESPACE || '',
      secretPath: options.secretPath || 'secret/data/adobe-automation',
      ...options
    };

    this.client = null;
    this.isInitialized = false;
    this.cache = new Map();
    this.cacheTimeout = options.cacheTimeout || 300000; // 5 minutes default
  }

  /**
   * Initialize Vault client
   */
  async initialize() {
    try {
      // Initialize Vault client
      this.client = vault({
        apiVersion: this.options.apiVersion,
        endpoint: this.options.endpoint,
        token: this.options.token,
        namespace: this.options.namespace
      });

      // Test connection
      const health = await this.client.health();

      if (!health.initialized) {
        throw new Error('Vault is not initialized');
      }

      if (health.sealed) {
        throw new Error('Vault is sealed');
      }

      this.isInitialized = true;
      logger.info('Vault connection established successfully');

      // Start cache cleanup interval
      this.startCacheCleanup();

      return true;
    } catch (error) {
      logger.error('Failed to initialize Vault:', error.message);
      throw error;
    }
  }

  /**
   * Get secret from Vault
   * @param {string} key - Secret key
   * @param {boolean} useCache - Use cached value if available
   */
  async getSecret(key, useCache = true) {
    if (!this.isInitialized) {
      await this.initialize();
    }

    // Check cache first
    if (useCache && this.cache.has(key)) {
      const cached = this.cache.get(key);
      if (Date.now() - cached.timestamp < this.cacheTimeout) {
        logger.debug(`Returning cached value for key: ${key}`);
        return cached.value;
      }
    }

    try {
      // Fetch from Vault
      const path = `${this.options.secretPath}/${key}`;
      const result = await this.client.read(path);

      if (!result || !result.data || !result.data.data) {
        throw new Error(`Secret not found: ${key}`);
      }

      const value = result.data.data.value || result.data.data;

      // Update cache
      this.cache.set(key, {
        value,
        timestamp: Date.now()
      });

      logger.info(`Retrieved secret: ${key}`);
      return value;
    } catch (error) {
      logger.error(`Failed to get secret ${key}:`, error.message);
      throw error;
    }
  }

  /**
   * Store secret in Vault
   * @param {string} key - Secret key
   * @param {any} value - Secret value
   * @param {object} metadata - Optional metadata
   */
  async setSecret(key, value, metadata = {}) {
    if (!this.isInitialized) {
      await this.initialize();
    }

    try {
      const path = `${this.options.secretPath}/${key}`;
      const data = {
        data: {
          value,
          created: new Date().toISOString(),
          ...metadata
        }
      };

      await this.client.write(path, data);

      // Invalidate cache
      this.cache.delete(key);

      logger.info(`Stored secret: ${key}`);
      return true;
    } catch (error) {
      logger.error(`Failed to store secret ${key}:`, error.message);
      throw error;
    }
  }

  /**
   * Delete secret from Vault
   * @param {string} key - Secret key
   */
  async deleteSecret(key) {
    if (!this.isInitialized) {
      await this.initialize();
    }

    try {
      const path = `${this.options.secretPath}/${key}`;
      await this.client.delete(path);

      // Remove from cache
      this.cache.delete(key);

      logger.info(`Deleted secret: ${key}`);
      return true;
    } catch (error) {
      logger.error(`Failed to delete secret ${key}:`, error.message);
      throw error;
    }
  }

  /**
   * List all secrets under a path
   * @param {string} path - Path to list
   */
  async listSecrets(path = '') {
    if (!this.isInitialized) {
      await this.initialize();
    }

    try {
      const fullPath = path ? `${this.options.secretPath}/${path}` : this.options.secretPath;
      const result = await this.client.list(fullPath);

      if (!result || !result.data || !result.data.keys) {
        return [];
      }

      return result.data.keys;
    } catch (error) {
      logger.error(`Failed to list secrets at ${path}:`, error.message);
      throw error;
    }
  }

  /**
   * Get multiple secrets at once
   * @param {Array<string>} keys - Array of secret keys
   */
  async getMultipleSecrets(keys) {
    if (!this.isInitialized) {
      await this.initialize();
    }

    const results = {};
    const errors = [];

    for (const key of keys) {
      try {
        results[key] = await this.getSecret(key);
      } catch (error) {
        errors.push({ key, error: error.message });
      }
    }

    if (errors.length > 0) {
      logger.warn('Some secrets failed to retrieve:', errors);
    }

    return { results, errors };
  }

  /**
   * Get Adobe API credentials from Vault
   */
  async getAdobeCredentials() {
    const credentials = await this.getMultipleSecrets([
      'adobe-client-id',
      'adobe-client-secret',
      'adobe-org-id',
      'adobe-api-key',
      'adobe-technical-account-id',
      'adobe-private-key'
    ]);

    if (credentials.errors.length > 0) {
      throw new Error('Failed to retrieve complete Adobe credentials');
    }

    return {
      clientId: credentials.results['adobe-client-id'],
      clientSecret: credentials.results['adobe-client-secret'],
      orgId: credentials.results['adobe-org-id'],
      apiKey: credentials.results['adobe-api-key'],
      technicalAccountId: credentials.results['adobe-technical-account-id'],
      privateKey: credentials.results['adobe-private-key']
    };
  }

  /**
   * Get database connection string from Vault
   */
  async getDatabaseConfig() {
    const config = await this.getMultipleSecrets([
      'db-host',
      'db-port',
      'db-name',
      'db-username',
      'db-password'
    ]);

    if (config.errors.length > 0) {
      // Try to get full connection string as fallback
      const connectionString = await this.getSecret('db-connection-string');
      return { connectionString };
    }

    return {
      host: config.results['db-host'],
      port: config.results['db-port'],
      database: config.results['db-name'],
      username: config.results['db-username'],
      password: config.results['db-password']
    };
  }

  /**
   * Rotate secrets (generate new values)
   * @param {string} key - Secret key to rotate
   */
  async rotateSecret(key) {
    if (!this.isInitialized) {
      await this.initialize();
    }

    try {
      // Get current secret
      const currentValue = await this.getSecret(key, false);

      // Generate new value (example for API keys)
      const newValue = this.generateSecureToken(32);

      // Store with rotation metadata
      await this.setSecret(key, newValue, {
        previousValue: currentValue,
        rotatedAt: new Date().toISOString(),
        rotatedBy: 'system'
      });

      // Store old value with timestamp
      const archiveKey = `${key}-archive-${Date.now()}`;
      await this.setSecret(archiveKey, currentValue, {
        archivedAt: new Date().toISOString(),
        originalKey: key
      });

      logger.info(`Rotated secret: ${key}`);
      return newValue;
    } catch (error) {
      logger.error(`Failed to rotate secret ${key}:`, error.message);
      throw error;
    }
  }

  /**
   * Generate secure random token
   * @param {number} length - Token length
   */
  generateSecureToken(length = 32) {
    const crypto = require('crypto');
    return crypto.randomBytes(length).toString('hex');
  }

  /**
   * Enable audit logging for secrets access
   */
  async enableAuditLogging(path = 'file') {
    if (!this.isInitialized) {
      await this.initialize();
    }

    try {
      await this.client.auditEnable({
        path: path,
        type: 'file',
        description: 'Adobe Automation audit log',
        options: {
          file_path: '/vault/logs/audit.log'
        }
      });

      logger.info('Audit logging enabled');
      return true;
    } catch (error) {
      logger.error('Failed to enable audit logging:', error.message);
      throw error;
    }
  }

  /**
   * Create or update a policy
   * @param {string} name - Policy name
   * @param {string} rules - Policy rules in HCL format
   */
  async updatePolicy(name, rules) {
    if (!this.isInitialized) {
      await this.initialize();
    }

    try {
      await this.client.policies.write({
        name: name,
        rules: rules
      });

      logger.info(`Updated policy: ${name}`);
      return true;
    } catch (error) {
      logger.error(`Failed to update policy ${name}:`, error.message);
      throw error;
    }
  }

  /**
   * Clean up expired cache entries
   */
  startCacheCleanup() {
    setInterval(() => {
      const now = Date.now();
      for (const [key, value] of this.cache.entries()) {
        if (now - value.timestamp > this.cacheTimeout) {
          this.cache.delete(key);
        }
      }
    }, this.cacheTimeout);
  }

  /**
   * Clear all cached values
   */
  clearCache() {
    this.cache.clear();
    logger.info('Cache cleared');
  }

  /**
   * Check Vault health status
   */
  async checkHealth() {
    try {
      const health = await this.client.health();
      return {
        healthy: health.initialized && !health.sealed,
        initialized: health.initialized,
        sealed: health.sealed,
        version: health.version,
        clusterName: health.cluster_name,
        clusterID: health.cluster_id
      };
    } catch (error) {
      logger.error('Health check failed:', error.message);
      return {
        healthy: false,
        error: error.message
      };
    }
  }

  /**
   * Seal Vault (emergency security measure)
   */
  async sealVault() {
    if (!this.isInitialized) {
      await this.initialize();
    }

    try {
      await this.client.seal();
      logger.warn('Vault has been sealed');
      this.isInitialized = false;
      return true;
    } catch (error) {
      logger.error('Failed to seal vault:', error.message);
      throw error;
    }
  }
}

// Express middleware for Vault integration
function vaultMiddleware(vaultManager) {
  return async (req, res, next) => {
    try {
      // Ensure Vault is initialized
      if (!vaultManager.isInitialized) {
        await vaultManager.initialize();
      }

      // Attach vault manager to request
      req.vault = vaultManager;

      // Load common secrets into request context
      req.secrets = {
        jwtSecret: await vaultManager.getSecret('jwt-secret').catch(() => process.env.JWT_SECRET),
        apiKey: await vaultManager.getSecret('api-key').catch(() => process.env.API_KEY)
      };

      next();
    } catch (error) {
      logger.error('Vault middleware error:', error);
      res.status(500).json({
        error: 'Security configuration error',
        message: process.env.NODE_ENV === 'development' ? error.message : 'Internal server error'
      });
    }
  };
}

// Export for use in other modules
module.exports = {
  VaultManager,
  vaultMiddleware
};

// Example usage
if (require.main === module) {
  (async () => {
    try {
      // Initialize Vault manager
      const vault = new VaultManager({
        endpoint: process.env.VAULT_ENDPOINT || 'http://127.0.0.1:8200',
        token: process.env.VAULT_TOKEN || 'dev-token',
        secretPath: 'secret/data/adobe-automation'
      });

      await vault.initialize();

      // Check health
      const health = await vault.checkHealth();
      console.log('Vault Health:', health);

      // Store some test secrets
      await vault.setSecret('test-key', 'test-value');

      // Retrieve secret
      const value = await vault.getSecret('test-key');
      console.log('Retrieved value:', value);

      // List secrets
      const secrets = await vault.listSecrets();
      console.log('Available secrets:', secrets);

      // Clean up
      await vault.deleteSecret('test-key');

    } catch (error) {
      console.error('Example failed:', error);
    }
  })();
}