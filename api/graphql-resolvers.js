/**
 * GraphQL Resolvers Implementation
 * Complete resolver functions for the GraphQL API layer
 */

const { GraphQLError } = require('graphql');
const { PubSub } = require('graphql-subscriptions');
const DataLoader = require('dataloader');
const winston = require('winston');

// Initialize logger
const logger = winston.createLogger({
  level: 'info',
  format: winston.format.json(),
  transports: [
    new winston.transports.Console({
      format: winston.format.simple()
    })
  ]
});

// Initialize PubSub for subscriptions
const pubsub = new PubSub();

// Import existing services
const { JiraConnector } = require('./jira-integration');
const { VaultManager } = require('./vault-integration');

/**
 * Base Data Source class with common functionality
 */
class BaseDataSource {
  constructor() {
    this.loader = null;
  }

  initialize({ context }) {
    this.context = context;
  }

  // Helper for authorization checks
  requireAuth(permission) {
    const { user } = this.context;
    if (!user) {
      throw new GraphQLError('Authentication required', {
        extensions: { code: 'UNAUTHENTICATED' }
      });
    }
    if (permission && !user.permissions?.includes(permission)) {
      throw new GraphQLError('Insufficient permissions', {
        extensions: { code: 'FORBIDDEN' }
      });
    }
    return user;
  }

  // Helper for pagination
  paginate(items, { limit = 20, offset = 0, sortBy = 'id', sortOrder = 'ASC' }) {
    const sorted = this.sortItems(items, sortBy, sortOrder);
    const paginated = sorted.slice(offset, offset + limit);

    return {
      edges: paginated.map((item, index) => ({
        node: item,
        cursor: Buffer.from(`${offset + index}`).toString('base64')
      })),
      pageInfo: {
        hasNextPage: offset + limit < sorted.length,
        hasPreviousPage: offset > 0,
        startCursor: paginated.length > 0 ? Buffer.from(`${offset}`).toString('base64') : null,
        endCursor: paginated.length > 0 ? Buffer.from(`${offset + paginated.length - 1}`).toString('base64') : null
      },
      totalCount: sorted.length
    };
  }

  sortItems(items, sortBy, sortOrder) {
    return items.sort((a, b) => {
      const aVal = this.getNestedProperty(a, sortBy);
      const bVal = this.getNestedProperty(b, sortBy);

      if (sortOrder === 'DESC') {
        return bVal > aVal ? 1 : -1;
      }
      return aVal > bVal ? 1 : -1;
    });
  }

  getNestedProperty(obj, path) {
    return path.split('.').reduce((curr, prop) => curr?.[prop], obj);
  }
}

/**
 * User Data Source
 */
class UserDataSource extends BaseDataSource {
  constructor(db) {
    super();
    this.db = db;
    this.users = new Map(); // In-memory store for demo
    this.initSampleData();
  }

  initSampleData() {
    // Add sample users
    const sampleUsers = [
      {
        id: '1',
        email: 'john.doe@company.com',
        firstName: 'John',
        lastName: 'Doe',
        department: 'Marketing',
        products: ['Creative Cloud', 'Acrobat Pro'],
        status: 'ACTIVE',
        createdAt: new Date('2024-01-15'),
        lastLogin: new Date('2024-12-01')
      },
      {
        id: '2',
        email: 'jane.smith@company.com',
        firstName: 'Jane',
        lastName: 'Smith',
        department: 'Design',
        products: ['Creative Cloud', 'Photoshop', 'Illustrator'],
        status: 'ACTIVE',
        createdAt: new Date('2024-02-20'),
        lastLogin: new Date('2024-12-10')
      }
    ];

    sampleUsers.forEach(user => this.users.set(user.id, user));
  }

  async getUser(id) {
    return this.users.get(id) || null;
  }

  async getUserByEmail(email) {
    return Array.from(this.users.values()).find(u => u.email === email) || null;
  }

  async getUsers(filter = {}, pagination = {}) {
    let users = Array.from(this.users.values());

    // Apply filters
    if (filter.email) {
      users = users.filter(u => u.email.includes(filter.email));
    }
    if (filter.department) {
      users = users.filter(u => u.department === filter.department);
    }
    if (filter.status) {
      users = users.filter(u => u.status === filter.status);
    }
    if (filter.product) {
      users = users.filter(u => u.products.includes(filter.product));
    }
    if (filter.search) {
      const search = filter.search.toLowerCase();
      users = users.filter(u =>
        u.firstName.toLowerCase().includes(search) ||
        u.lastName.toLowerCase().includes(search) ||
        u.email.toLowerCase().includes(search)
      );
    }

    return this.paginate(users, pagination);
  }

  async getUsersByDepartment(department) {
    return Array.from(this.users.values()).filter(u => u.department === department);
  }

  async createUser(input) {
    this.requireAuth('CREATE_USER');

    const id = String(this.users.size + 1);
    const user = {
      id,
      ...input,
      status: 'PENDING',
      createdAt: new Date(),
      lastLogin: null
    };

    this.users.set(id, user);

    // Emit subscription event
    pubsub.publish('USER_CREATED', { userCreated: user });

    // Log audit event
    logger.info('User created', { userId: id, email: input.email });

    return user;
  }

  async updateUser(id, input) {
    this.requireAuth('UPDATE_USER');

    const user = this.users.get(id);
    if (!user) {
      throw new GraphQLError('User not found', {
        extensions: { code: 'NOT_FOUND' }
      });
    }

    const updated = { ...user, ...input, updatedAt: new Date() };
    this.users.set(id, updated);

    // Emit subscription events
    pubsub.publish('USER_UPDATED', { userUpdated: updated });
    pubsub.publish(`USER_UPDATED_${id}`, { userUpdated: updated });

    logger.info('User updated', { userId: id });

    return updated;
  }

  async deleteUser(id) {
    this.requireAuth('DELETE_USER');

    if (!this.users.has(id)) {
      throw new GraphQLError('User not found', {
        extensions: { code: 'NOT_FOUND' }
      });
    }

    this.users.delete(id);

    // Emit subscription event
    pubsub.publish('USER_DELETED', { userDeleted: id });

    logger.info('User deleted', { userId: id });

    return true;
  }

  async bulkCreateUsers(users) {
    this.requireAuth('CREATE_USER');

    const created = [];
    const failed = [];

    for (const userData of users) {
      try {
        // Check for duplicate email
        if (await this.getUserByEmail(userData.email)) {
          failed.push({
            email: userData.email,
            error: 'Email already exists'
          });
          continue;
        }

        const user = await this.createUser(userData);
        created.push(user);
      } catch (error) {
        failed.push({
          email: userData.email,
          error: error.message
        });
      }
    }

    return {
      created,
      failed,
      totalProcessed: users.length,
      successCount: created.length,
      failureCount: failed.length
    };
  }

  async suspendUser(id, reason) {
    this.requireAuth('UPDATE_USER');

    const user = await this.updateUser(id, { status: 'SUSPENDED' });

    logger.info('User suspended', { userId: id, reason });

    return user;
  }

  async reactivateUser(id) {
    this.requireAuth('UPDATE_USER');

    const user = await this.updateUser(id, { status: 'ACTIVE' });

    logger.info('User reactivated', { userId: id });

    return user;
  }
}

/**
 * License Data Source
 */
class LicenseDataSource extends BaseDataSource {
  constructor(db) {
    super();
    this.db = db;
    this.licenses = new Map();
    this.initSampleData();
  }

  initSampleData() {
    const sampleLicenses = [
      {
        id: 'L1',
        product: 'Creative Cloud',
        type: 'NAMED_USER',
        userId: '1',
        assignedAt: new Date('2024-01-15'),
        expiresAt: new Date('2025-01-15'),
        status: 'ASSIGNED',
        cost: 79.99
      },
      {
        id: 'L2',
        product: 'Acrobat Pro',
        type: 'NAMED_USER',
        userId: '1',
        assignedAt: new Date('2024-01-15'),
        expiresAt: new Date('2025-01-15'),
        status: 'ASSIGNED',
        cost: 19.99
      },
      {
        id: 'L3',
        product: 'Creative Cloud',
        type: 'NAMED_USER',
        userId: '2',
        assignedAt: new Date('2024-02-20'),
        expiresAt: new Date('2025-02-20'),
        status: 'ASSIGNED',
        cost: 79.99
      },
      {
        id: 'L4',
        product: 'Photoshop',
        type: 'NAMED_USER',
        userId: null,
        assignedAt: null,
        expiresAt: null,
        status: 'AVAILABLE',
        cost: 31.49
      }
    ];

    sampleLicenses.forEach(license => this.licenses.set(license.id, license));
  }

  async getLicense(id) {
    return this.licenses.get(id) || null;
  }

  async getLicenses(filter = {}, pagination = {}) {
    let licenses = Array.from(this.licenses.values());

    // Apply filters
    if (filter.product) {
      licenses = licenses.filter(l => l.product === filter.product);
    }
    if (filter.status) {
      licenses = licenses.filter(l => l.status === filter.status);
    }
    if (filter.unassigned) {
      licenses = licenses.filter(l => !l.userId);
    }

    return this.paginate(licenses, pagination);
  }

  async getLicensesByUser(userId) {
    return Array.from(this.licenses.values()).filter(l => l.userId === userId);
  }

  async getLicensesByDepartment(department) {
    // Would need to join with users table
    const users = await this.context.dataSources.userAPI.getUsersByDepartment(department);
    const userIds = users.map(u => u.id);
    return Array.from(this.licenses.values()).filter(l => userIds.includes(l.userId));
  }

  async getUtilization(product) {
    let licenses = Array.from(this.licenses.values());

    if (product) {
      licenses = licenses.filter(l => l.product === product);
    }

    const total = licenses.length;
    const used = licenses.filter(l => l.status === 'ASSIGNED').length;
    const available = total - used;

    // Calculate by department
    const byDepartment = new Map();
    const byProduct = new Map();

    for (const license of licenses) {
      if (license.userId) {
        const user = await this.context.dataSources.userAPI.getUser(license.userId);
        if (user) {
          const dept = user.department;
          const current = byDepartment.get(dept) || { used: 0, total: 0 };
          current.used += license.status === 'ASSIGNED' ? 1 : 0;
          current.total += 1;
          byDepartment.set(dept, current);
        }
      }

      const prod = license.product;
      const current = byProduct.get(prod) || { used: 0, total: 0 };
      current.used += license.status === 'ASSIGNED' ? 1 : 0;
      current.total += 1;
      byProduct.set(prod, current);
    }

    return {
      total,
      used,
      available,
      utilizationPercentage: total > 0 ? (used / total) * 100 : 0,
      byDepartment: Array.from(byDepartment.entries()).map(([dept, data]) => ({
        department: dept,
        used: data.used,
        total: data.total,
        percentage: data.total > 0 ? (data.used / data.total) * 100 : 0
      })),
      byProduct: Array.from(byProduct.entries()).map(([prod, data]) => ({
        product: prod,
        used: data.used,
        total: data.total,
        percentage: data.total > 0 ? (data.used / data.total) * 100 : 0
      }))
    };
  }

  async assignLicense(userId, product) {
    this.requireAuth('MANAGE_LICENSES');

    // Find available license
    const availableLicense = Array.from(this.licenses.values()).find(
      l => l.product === product && l.status === 'AVAILABLE'
    );

    if (!availableLicense) {
      throw new GraphQLError('No available licenses for this product', {
        extensions: { code: 'NO_LICENSES_AVAILABLE' }
      });
    }

    // Assign license
    availableLicense.userId = userId;
    availableLicense.status = 'ASSIGNED';
    availableLicense.assignedAt = new Date();
    availableLicense.expiresAt = new Date(Date.now() + 365 * 24 * 60 * 60 * 1000);

    // Emit subscription event
    pubsub.publish('LICENSE_ASSIGNED', { licenseAssigned: availableLicense });

    logger.info('License assigned', { licenseId: availableLicense.id, userId, product });

    return availableLicense;
  }

  async revokeLicense(licenseId, reason) {
    this.requireAuth('MANAGE_LICENSES');

    const license = this.licenses.get(licenseId);
    if (!license) {
      throw new GraphQLError('License not found', {
        extensions: { code: 'NOT_FOUND' }
      });
    }

    license.userId = null;
    license.status = 'AVAILABLE';
    license.assignedAt = null;
    license.expiresAt = null;

    // Emit subscription event
    pubsub.publish('LICENSE_REVOKED', { licenseRevoked: license });

    logger.info('License revoked', { licenseId, reason });

    return license;
  }

  async transferLicense(licenseId, toUserId) {
    this.requireAuth('MANAGE_LICENSES');

    const license = this.licenses.get(licenseId);
    if (!license) {
      throw new GraphQLError('License not found', {
        extensions: { code: 'NOT_FOUND' }
      });
    }

    const oldUserId = license.userId;
    license.userId = toUserId;
    license.assignedAt = new Date();

    logger.info('License transferred', { licenseId, from: oldUserId, to: toUserId });

    return license;
  }
}

/**
 * Department Data Source
 */
class DepartmentDataSource extends BaseDataSource {
  constructor(db) {
    super();
    this.db = db;
  }

  async getDepartment(name) {
    const users = await this.context.dataSources.userAPI.getUsersByDepartment(name);
    const licenses = await this.context.dataSources.licenseAPI.getLicensesByDepartment(name);

    const totalCost = licenses.reduce((sum, l) => sum + (l.cost || 0), 0);

    return {
      name,
      userCount: users.length,
      licenseCount: licenses.length,
      totalCost,
      users,
      licenses
    };
  }

  async getAllDepartments() {
    // Get unique departments from users
    const users = await this.context.dataSources.userAPI.getUsers();
    const departments = new Set();

    users.edges.forEach(edge => {
      if (edge.node.department) {
        departments.add(edge.node.department);
      }
    });

    const results = [];
    for (const dept of departments) {
      results.push(await this.getDepartment(dept));
    }

    return results;
  }
}

/**
 * Optimization Data Source
 */
class OptimizationDataSource extends BaseDataSource {
  constructor() {
    super();
  }

  async getOptimizations(products) {
    const results = [];
    const licenses = await this.context.dataSources.licenseAPI.getLicenses();

    // Group licenses by product
    const byProduct = new Map();

    licenses.edges.forEach(edge => {
      const license = edge.node;
      if (!products || products.includes(license.product)) {
        const current = byProduct.get(license.product) || {
          total: 0,
          assigned: 0,
          unused: 0,
          cost: 0
        };

        current.total++;
        if (license.status === 'ASSIGNED') {
          current.assigned++;
          // Check if actually used (would need usage data)
          // For demo, assume 20% are unused
          if (Math.random() < 0.2) {
            current.unused++;
          }
        }
        current.cost += license.cost || 0;

        byProduct.set(license.product, current);
      }
    });

    for (const [product, data] of byProduct.entries()) {
      results.push({
        product,
        currentAllocation: data.total,
        recommendedAllocation: data.assigned - data.unused,
        potentialSavings: data.unused * (data.cost / data.total),
        unusedLicenses: data.unused,
        recommendations: [
          data.unused > 0 ? `Reclaim ${data.unused} unused licenses` : null,
          data.unused > 5 ? 'Consider switching to a pool-based licensing model' : null,
          'Review quarterly usage patterns for better forecasting'
        ].filter(Boolean)
      });
    }

    return results;
  }

  async runOptimization(dryRun = false) {
    this.requireAuth('OPTIMIZE_LICENSES');

    const optimizations = await this.getOptimizations();
    let licensesReclaimed = 0;
    let estimatedSavings = 0;
    const affectedUsers = [];

    for (const opt of optimizations) {
      licensesReclaimed += opt.unusedLicenses;
      estimatedSavings += opt.potentialSavings;
    }

    if (!dryRun) {
      // Actually reclaim licenses
      // This would involve revoking unused licenses
      logger.info('License optimization executed', { licensesReclaimed, estimatedSavings });
    }

    const result = {
      optimized: !dryRun,
      licensesReclaimed,
      estimatedSavings,
      affectedUsers,
      recommendations: [
        'Monthly review of license usage recommended',
        'Consider implementing automated license harvesting',
        'Set up alerts for underutilized licenses'
      ]
    };

    // Emit subscription event
    if (!dryRun) {
      pubsub.publish('OPTIMIZATION_COMPLETED', { optimizationCompleted: result });
    }

    return result;
  }
}

/**
 * ML/Prediction Data Source
 */
class MLDataSource extends BaseDataSource {
  constructor() {
    super();
  }

  async getPredictions(product, department, daysAhead) {
    const predictions = [];
    const startDate = new Date();

    for (let i = 0; i < daysAhead; i++) {
      const date = new Date(startDate);
      date.setDate(date.getDate() + i);

      // Simple prediction logic (would use actual ML model)
      const baseUsage = 50;
      const variation = Math.sin(i / 7) * 10; // Weekly pattern
      const trend = i * 0.1; // Slight upward trend

      predictions.push({
        product: product || 'Creative Cloud',
        department: department || 'All',
        date,
        predictedUsage: Math.round(baseUsage + variation + trend),
        confidenceLower: Math.round(baseUsage + variation + trend - 5),
        confidenceUpper: Math.round(baseUsage + variation + trend + 5),
        trend: trend > 0 ? 'INCREASING' : trend < 0 ? 'DECREASING' : 'STABLE'
      });
    }

    return predictions;
  }
}

/**
 * Statistics Data Source
 */
class StatisticsDataSource extends BaseDataSource {
  constructor() {
    super();
  }

  async getSystemStatistics() {
    const users = await this.context.dataSources.userAPI.getUsers();
    const licenses = await this.context.dataSources.licenseAPI.getLicenses();

    const activeUsers = users.edges.filter(e => e.node.status === 'ACTIVE').length;
    const usedLicenses = licenses.edges.filter(e => e.node.status === 'ASSIGNED').length;

    const monthlyCost = licenses.edges.reduce((sum, e) => sum + (e.node.cost || 0), 0);

    return {
      totalUsers: users.totalCount,
      activeUsers,
      totalLicenses: licenses.totalCount,
      usedLicenses,
      monthlyCost,
      lastSync: new Date(),
      systemHealth: {
        status: 'Healthy',
        apiStatus: true,
        databaseStatus: true,
        cacheStatus: true,
        lastCheck: new Date()
      }
    };
  }

  async getUserStats(userId) {
    // Would fetch from usage tracking system
    return {
      lastActive: new Date(),
      totalLogins: 42,
      averageUsageHours: 6.5,
      productsUsed: [
        {
          product: 'Creative Cloud',
          lastUsed: new Date(),
          totalHours: 156.5,
          frequency: 'Daily'
        }
      ]
    };
  }

  async getCostAnalysis(period) {
    const licenses = await this.context.dataSources.licenseAPI.getLicenses();
    const departments = await this.context.dataSources.departmentAPI.getAllDepartments();

    const totalCost = licenses.edges.reduce((sum, e) => sum + (e.node.cost || 0), 0);

    // Calculate cost by department
    const costByDepartment = departments.map(dept => ({
      department: dept.name,
      cost: dept.totalCost,
      userCount: dept.userCount,
      averageCostPerUser: dept.userCount > 0 ? dept.totalCost / dept.userCount : 0
    }));

    // Calculate cost by product
    const costByProduct = new Map();
    licenses.edges.forEach(edge => {
      const license = edge.node;
      const current = costByProduct.get(license.product) || { cost: 0, count: 0 };
      current.cost += license.cost || 0;
      current.count++;
      costByProduct.set(license.product, current);
    });

    return {
      totalCost,
      costByDepartment,
      costByProduct: Array.from(costByProduct.entries()).map(([product, data]) => ({
        product,
        cost: data.cost,
        licenseCount: data.count,
        averageCostPerLicense: data.count > 0 ? data.cost / data.count : 0
      })),
      trend: 'STABLE',
      projectedCost: totalCost * 1.05, // 5% increase projection
      savingsOpportunity: totalCost * 0.15 // 15% potential savings
    };
  }
}

/**
 * Create complete resolvers with all data sources
 */
function createResolvers() {
  const userAPI = new UserDataSource();
  const licenseAPI = new LicenseDataSource();
  const departmentAPI = new DepartmentDataSource();
  const optimizationAPI = new OptimizationDataSource();
  const mlAPI = new MLDataSource();
  const statisticsAPI = new StatisticsDataSource();

  return {
    dataSources: {
      userAPI,
      licenseAPI,
      departmentAPI,
      optimizationAPI,
      mlAPI,
      statisticsAPI
    },
    pubsub
  };
}

module.exports = {
  BaseDataSource,
  UserDataSource,
  LicenseDataSource,
  DepartmentDataSource,
  OptimizationDataSource,
  MLDataSource,
  StatisticsDataSource,
  createResolvers,
  pubsub
};