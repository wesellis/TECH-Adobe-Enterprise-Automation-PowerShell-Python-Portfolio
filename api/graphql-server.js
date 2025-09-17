/**
 * GraphQL API Layer for Adobe Enterprise Automation
 * Provides a flexible query interface for all Adobe automation operations
 */

const { ApolloServer, gql } = require('apollo-server-express');
const { GraphQLScalarType, Kind } = require('graphql');
const DataLoader = require('dataloader');

// Type definitions for GraphQL schema
const typeDefs = gql`
  scalar Date
  scalar JSON

  # User type
  type User {
    id: ID!
    email: String!
    firstName: String!
    lastName: String!
    department: String!
    products: [String!]!
    status: UserStatus!
    createdAt: Date!
    lastLogin: Date
    licenses: [License!]!
    usageStats: UserUsageStats
  }

  # License type
  type License {
    id: ID!
    product: String!
    type: LicenseType!
    assignedTo: User
    assignedAt: Date
    expiresAt: Date
    status: LicenseStatus!
    cost: Float
  }

  # Department type
  type Department {
    name: String!
    userCount: Int!
    licenseCount: Int!
    totalCost: Float!
    users: [User!]!
    licenses: [License!]!
  }

  # License optimization type
  type LicenseOptimization {
    product: String!
    currentAllocation: Int!
    recommendedAllocation: Int!
    potentialSavings: Float!
    unusedLicenses: Int!
    recommendations: [String!]!
  }

  # Usage statistics type
  type UserUsageStats {
    lastActive: Date
    totalLogins: Int!
    averageUsageHours: Float!
    productsUsed: [ProductUsage!]!
  }

  type ProductUsage {
    product: String!
    lastUsed: Date
    totalHours: Float!
    frequency: String!
  }

  # Provisioning request type
  type ProvisioningRequest {
    id: ID!
    user: User!
    requestedBy: String!
    requestedAt: Date!
    status: RequestStatus!
    products: [String!]!
    approvedBy: String
    approvedAt: Date
    completedAt: Date
    jiraTicket: String
  }

  # Report type
  type Report {
    id: ID!
    type: ReportType!
    generatedAt: Date!
    period: DateRange!
    data: JSON!
    format: String!
    url: String
  }

  type DateRange {
    start: Date!
    end: Date!
  }

  # ML Prediction type
  type LicensePrediction {
    product: String!
    department: String!
    date: Date!
    predictedUsage: Int!
    confidenceLower: Int!
    confidenceUpper: Int!
    trend: TrendDirection!
  }

  # Audit log type
  type AuditLog {
    id: ID!
    action: String!
    performedBy: String!
    timestamp: Date!
    details: JSON!
    entityType: String!
    entityId: String!
  }

  # Enums
  enum UserStatus {
    ACTIVE
    INACTIVE
    SUSPENDED
    PENDING
  }

  enum LicenseStatus {
    ASSIGNED
    AVAILABLE
    EXPIRED
    SUSPENDED
  }

  enum LicenseType {
    NAMED_USER
    DEVICE
    FLOATING
    TRIAL
  }

  enum RequestStatus {
    PENDING
    APPROVED
    REJECTED
    COMPLETED
    CANCELLED
  }

  enum ReportType {
    USAGE
    COST
    COMPLIANCE
    OPTIMIZATION
    AUDIT
  }

  enum TrendDirection {
    INCREASING
    DECREASING
    STABLE
  }

  enum SortOrder {
    ASC
    DESC
  }

  # Input types
  input UserCreateInput {
    email: String!
    firstName: String!
    lastName: String!
    department: String!
    products: [String!]!
  }

  input UserUpdateInput {
    firstName: String
    lastName: String
    department: String
    products: [String!]
    status: UserStatus
  }

  input UserFilterInput {
    email: String
    department: String
    status: UserStatus
    product: String
    search: String
  }

  input LicenseFilterInput {
    product: String
    status: LicenseStatus
    department: String
    unassigned: Boolean
  }

  input DateRangeInput {
    start: Date!
    end: Date!
  }

  input PaginationInput {
    limit: Int
    offset: Int
    sortBy: String
    sortOrder: SortOrder
  }

  # Query root type
  type Query {
    # User queries
    user(id: ID!): User
    userByEmail(email: String!): User
    users(filter: UserFilterInput, pagination: PaginationInput): UserConnection!

    # License queries
    license(id: ID!): License
    licenses(filter: LicenseFilterInput, pagination: PaginationInput): LicenseConnection!
    licenseUtilization(product: String): LicenseUtilization!

    # Department queries
    department(name: String!): Department
    departments: [Department!]!

    # Optimization queries
    licenseOptimizations(products: [String!]): [LicenseOptimization!]!

    # Prediction queries
    licensePredictions(
      product: String
      department: String
      daysAhead: Int!
    ): [LicensePrediction!]!

    # Provisioning queries
    provisioningRequest(id: ID!): ProvisioningRequest
    provisioningRequests(
      status: RequestStatus
      pagination: PaginationInput
    ): ProvisioningRequestConnection!

    # Report queries
    report(id: ID!): Report
    reports(type: ReportType, period: DateRangeInput): [Report!]!
    generateReport(type: ReportType!, period: DateRangeInput!): Report!

    # Audit queries
    auditLogs(
      entityType: String
      entityId: String
      performedBy: String
      dateRange: DateRangeInput
      pagination: PaginationInput
    ): AuditLogConnection!

    # Statistics queries
    statistics: SystemStatistics!
    costAnalysis(period: DateRangeInput): CostAnalysis!
  }

  # Mutation root type
  type Mutation {
    # User mutations
    createUser(input: UserCreateInput!): User!
    updateUser(id: ID!, input: UserUpdateInput!): User!
    deleteUser(id: ID!): Boolean!
    suspendUser(id: ID!, reason: String): User!
    reactivateUser(id: ID!): User!
    bulkCreateUsers(users: [UserCreateInput!]!): BulkCreateResult!

    # License mutations
    assignLicense(userId: ID!, product: String!): License!
    revokeLicense(licenseId: ID!, reason: String): License!
    transferLicense(licenseId: ID!, toUserId: ID!): License!
    optimizeLicenses(dryRun: Boolean): OptimizationResult!

    # Provisioning mutations
    requestProvisioning(
      userId: ID!
      products: [String!]!
      justification: String
    ): ProvisioningRequest!
    approveProvisioning(requestId: ID!, approvedBy: String!): ProvisioningRequest!
    rejectProvisioning(requestId: ID!, reason: String!): ProvisioningRequest!

    # Sync mutations
    syncWithActiveDirectory: SyncResult!
    syncWithAzureAD: SyncResult!
    syncLicenses: SyncResult!

    # Admin mutations
    runOptimization: OptimizationResult!
    generateComplianceReport: Report!
    exportData(format: String!): String!
  }

  # Subscription root type
  type Subscription {
    # Real-time updates
    userCreated: User!
    userUpdated(userId: ID): User!
    userDeleted: ID!

    licenseAssigned: License!
    licenseRevoked: License!

    provisioningRequestCreated: ProvisioningRequest!
    provisioningRequestUpdated(requestId: ID): ProvisioningRequest!

    optimizationCompleted: OptimizationResult!

    systemAlert: SystemAlert!
  }

  # Connection types for pagination
  type UserConnection {
    edges: [UserEdge!]!
    pageInfo: PageInfo!
    totalCount: Int!
  }

  type UserEdge {
    node: User!
    cursor: String!
  }

  type LicenseConnection {
    edges: [LicenseEdge!]!
    pageInfo: PageInfo!
    totalCount: Int!
  }

  type LicenseEdge {
    node: License!
    cursor: String!
  }

  type ProvisioningRequestConnection {
    edges: [ProvisioningRequestEdge!]!
    pageInfo: PageInfo!
    totalCount: Int!
  }

  type ProvisioningRequestEdge {
    node: ProvisioningRequest!
    cursor: String!
  }

  type AuditLogConnection {
    edges: [AuditLogEdge!]!
    pageInfo: PageInfo!
    totalCount: Int!
  }

  type AuditLogEdge {
    node: AuditLog!
    cursor: String!
  }

  type PageInfo {
    hasNextPage: Boolean!
    hasPreviousPage: Boolean!
    startCursor: String
    endCursor: String
  }

  # Result types
  type BulkCreateResult {
    created: [User!]!
    failed: [BulkCreateError!]!
    totalProcessed: Int!
    successCount: Int!
    failureCount: Int!
  }

  type BulkCreateError {
    email: String!
    error: String!
  }

  type SyncResult {
    synced: Int!
    created: Int!
    updated: Int!
    deleted: Int!
    errors: [String!]!
    duration: Float!
  }

  type OptimizationResult {
    optimized: Boolean!
    licensesReclaimed: Int!
    estimatedSavings: Float!
    affectedUsers: [User!]!
    recommendations: [String!]!
  }

  type LicenseUtilization {
    total: Int!
    used: Int!
    available: Int!
    utilizationPercentage: Float!
    byDepartment: [DepartmentUtilization!]!
    byProduct: [ProductUtilization!]!
  }

  type DepartmentUtilization {
    department: String!
    used: Int!
    total: Int!
    percentage: Float!
  }

  type ProductUtilization {
    product: String!
    used: Int!
    total: Int!
    percentage: Float!
  }

  type SystemStatistics {
    totalUsers: Int!
    activeUsers: Int!
    totalLicenses: Int!
    usedLicenses: Int!
    monthlyCost: Float!
    lastSync: Date
    systemHealth: SystemHealth!
  }

  type SystemHealth {
    status: String!
    apiStatus: Boolean!
    databaseStatus: Boolean!
    cacheStatus: Boolean!
    lastCheck: Date!
  }

  type CostAnalysis {
    totalCost: Float!
    costByDepartment: [DepartmentCost!]!
    costByProduct: [ProductCost!]!
    trend: TrendDirection!
    projectedCost: Float!
    savingsOpportunity: Float!
  }

  type DepartmentCost {
    department: String!
    cost: Float!
    userCount: Int!
    averageCostPerUser: Float!
  }

  type ProductCost {
    product: String!
    cost: Float!
    licenseCount: Int!
    averageCostPerLicense: Float!
  }

  type SystemAlert {
    id: ID!
    type: String!
    severity: String!
    message: String!
    timestamp: Date!
    details: JSON!
  }
`;

// Custom scalar for Date
const dateScalar = new GraphQLScalarType({
  name: 'Date',
  description: 'Date custom scalar type',
  serialize(value) {
    return value instanceof Date ? value.toISOString() : value;
  },
  parseValue(value) {
    return new Date(value);
  },
  parseLiteral(ast) {
    if (ast.kind === Kind.STRING) {
      return new Date(ast.value);
    }
    return null;
  },
});

// Custom scalar for JSON
const jsonScalar = new GraphQLScalarType({
  name: 'JSON',
  description: 'JSON custom scalar type',
  serialize(value) {
    return value;
  },
  parseValue(value) {
    return value;
  },
  parseLiteral(ast) {
    if (ast.kind === Kind.STRING) {
      try {
        return JSON.parse(ast.value);
      } catch (e) {
        return null;
      }
    }
    return null;
  },
});

// GraphQL Resolvers
const resolvers = {
  Date: dateScalar,
  JSON: jsonScalar,

  Query: {
    // User queries
    user: async (_, { id }, { dataSources }) => {
      return dataSources.userAPI.getUser(id);
    },

    userByEmail: async (_, { email }, { dataSources }) => {
      return dataSources.userAPI.getUserByEmail(email);
    },

    users: async (_, { filter, pagination }, { dataSources }) => {
      return dataSources.userAPI.getUsers(filter, pagination);
    },

    // License queries
    license: async (_, { id }, { dataSources }) => {
      return dataSources.licenseAPI.getLicense(id);
    },

    licenses: async (_, { filter, pagination }, { dataSources }) => {
      return dataSources.licenseAPI.getLicenses(filter, pagination);
    },

    licenseUtilization: async (_, { product }, { dataSources }) => {
      return dataSources.licenseAPI.getUtilization(product);
    },

    // Department queries
    department: async (_, { name }, { dataSources }) => {
      return dataSources.departmentAPI.getDepartment(name);
    },

    departments: async (_, __, { dataSources }) => {
      return dataSources.departmentAPI.getAllDepartments();
    },

    // Optimization queries
    licenseOptimizations: async (_, { products }, { dataSources }) => {
      return dataSources.optimizationAPI.getOptimizations(products);
    },

    // Prediction queries
    licensePredictions: async (_, { product, department, daysAhead }, { dataSources }) => {
      return dataSources.mlAPI.getPredictions(product, department, daysAhead);
    },

    // Statistics
    statistics: async (_, __, { dataSources }) => {
      return dataSources.statisticsAPI.getSystemStatistics();
    },

    costAnalysis: async (_, { period }, { dataSources }) => {
      return dataSources.statisticsAPI.getCostAnalysis(period);
    },
  },

  Mutation: {
    // User mutations
    createUser: async (_, { input }, { dataSources, user }) => {
      // Check authorization
      if (!user || !user.permissions.includes('CREATE_USER')) {
        throw new Error('Unauthorized');
      }
      return dataSources.userAPI.createUser(input);
    },

    updateUser: async (_, { id, input }, { dataSources, user }) => {
      if (!user || !user.permissions.includes('UPDATE_USER')) {
        throw new Error('Unauthorized');
      }
      return dataSources.userAPI.updateUser(id, input);
    },

    deleteUser: async (_, { id }, { dataSources, user }) => {
      if (!user || !user.permissions.includes('DELETE_USER')) {
        throw new Error('Unauthorized');
      }
      return dataSources.userAPI.deleteUser(id);
    },

    bulkCreateUsers: async (_, { users }, { dataSources, user }) => {
      if (!user || !user.permissions.includes('CREATE_USER')) {
        throw new Error('Unauthorized');
      }
      return dataSources.userAPI.bulkCreateUsers(users);
    },

    // License mutations
    assignLicense: async (_, { userId, product }, { dataSources, user }) => {
      if (!user || !user.permissions.includes('MANAGE_LICENSES')) {
        throw new Error('Unauthorized');
      }
      return dataSources.licenseAPI.assignLicense(userId, product);
    },

    revokeLicense: async (_, { licenseId, reason }, { dataSources, user }) => {
      if (!user || !user.permissions.includes('MANAGE_LICENSES')) {
        throw new Error('Unauthorized');
      }
      return dataSources.licenseAPI.revokeLicense(licenseId, reason);
    },

    optimizeLicenses: async (_, { dryRun }, { dataSources, user }) => {
      if (!user || !user.permissions.includes('OPTIMIZE_LICENSES')) {
        throw new Error('Unauthorized');
      }
      return dataSources.optimizationAPI.runOptimization(dryRun);
    },

    // Sync mutations
    syncWithActiveDirectory: async (_, __, { dataSources, user }) => {
      if (!user || !user.permissions.includes('ADMIN')) {
        throw new Error('Unauthorized');
      }
      return dataSources.syncAPI.syncWithAD();
    },
  },

  Subscription: {
    userCreated: {
      subscribe: (_, __, { pubsub }) => pubsub.asyncIterator(['USER_CREATED']),
    },
    userUpdated: {
      subscribe: (_, { userId }, { pubsub }) => {
        if (userId) {
          return pubsub.asyncIterator([`USER_UPDATED_${userId}`]);
        }
        return pubsub.asyncIterator(['USER_UPDATED']);
      },
    },
    licenseAssigned: {
      subscribe: (_, __, { pubsub }) => pubsub.asyncIterator(['LICENSE_ASSIGNED']),
    },
  },

  // Field resolvers
  User: {
    licenses: async (user, _, { dataSources }) => {
      return dataSources.licenseAPI.getLicensesByUser(user.id);
    },
    usageStats: async (user, _, { dataSources }) => {
      return dataSources.statisticsAPI.getUserStats(user.id);
    },
  },

  License: {
    assignedTo: async (license, _, { dataSources }) => {
      if (!license.userId) return null;
      return dataSources.userAPI.getUser(license.userId);
    },
  },

  Department: {
    users: async (dept, _, { dataSources }) => {
      return dataSources.userAPI.getUsersByDepartment(dept.name);
    },
    licenses: async (dept, _, { dataSources }) => {
      return dataSources.licenseAPI.getLicensesByDepartment(dept.name);
    },
  },
};

// Data source classes (would be implemented to connect to actual databases)
class UserAPI {
  async getUser(id) {
    // Implementation would fetch from database
    return { id, email: 'user@example.com', firstName: 'John', lastName: 'Doe' };
  }

  async getUserByEmail(email) {
    return { id: '1', email, firstName: 'John', lastName: 'Doe' };
  }

  async getUsers(filter, pagination) {
    // Implementation with filtering and pagination
    return {
      edges: [],
      pageInfo: { hasNextPage: false, hasPreviousPage: false },
      totalCount: 0
    };
  }

  async createUser(input) {
    // Create user in database
    return { id: 'new-id', ...input, status: 'ACTIVE', createdAt: new Date() };
  }

  async updateUser(id, input) {
    // Update user in database
    return { id, ...input };
  }

  async deleteUser(id) {
    // Delete user from database
    return true;
  }
}

// Create Apollo Server
function createGraphQLServer(app) {
  const server = new ApolloServer({
    typeDefs,
    resolvers,
    dataSources: () => ({
      userAPI: new UserAPI(),
      // Add other data sources
    }),
    context: ({ req }) => {
      // Add user from JWT token
      const user = req.user || null;
      return { user };
    },
    subscriptions: {
      onConnect: (connectionParams) => {
        // Validate connection
        console.log('Client connected to subscriptions');
      },
      onDisconnect: () => {
        console.log('Client disconnected from subscriptions');
      },
    },
    playground: process.env.NODE_ENV === 'development',
    introspection: process.env.NODE_ENV === 'development',
  });

  return server;
}

module.exports = {
  createGraphQLServer,
  typeDefs,
  resolvers
};