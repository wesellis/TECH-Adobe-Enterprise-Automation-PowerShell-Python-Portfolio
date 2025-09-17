/**
 * GraphQL Integration Module
 * Integrates GraphQL with existing Express REST API
 */

const { ApolloServer } = require('@apollo/server');
const { expressMiddleware } = require('@apollo/server/express4');
const { ApolloServerPluginDrainHttpServer } = require('@apollo/server/plugin/drainHttpServer');
const { ApolloServerPluginLandingPageLocalDefault } = require('@apollo/server/plugin/landingPage/default');
const { makeExecutableSchema } = require('@graphql-tools/schema');
const { WebSocketServer } = require('ws');
const { useServer } = require('graphql-ws/lib/use/ws');
const cors = require('cors');
const bodyParser = require('body-parser');
const winston = require('winston');

// Import GraphQL schema and resolvers
const { typeDefs, resolvers } = require('./graphql-server');
const { createResolvers, pubsub } = require('./graphql-resolvers');

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

/**
 * Integrate GraphQL with Express application
 * @param {Express} app - Express application instance
 * @param {http.Server} httpServer - HTTP server instance
 * @param {Object} options - Configuration options
 */
async function integrateGraphQL(app, httpServer, options = {}) {
  const {
    path = '/graphql',
    enablePlayground = process.env.NODE_ENV === 'development',
    enableSubscriptions = true,
    cors: corsOptions = {},
    authMiddleware = null
  } = options;

  try {
    // Create executable schema
    const schema = makeExecutableSchema({ typeDefs, resolvers });

    // Get data sources and pubsub
    const { dataSources, pubsub: pubsubInstance } = createResolvers();

    let wsServer = null;
    let serverCleanup = null;

    // Set up WebSocket server for subscriptions if enabled
    if (enableSubscriptions) {
      wsServer = new WebSocketServer({
        server: httpServer,
        path
      });

      // Set up WebSocket server with GraphQL
      serverCleanup = useServer(
        {
          schema,
          context: async (ctx) => {
            // Get auth token from connection params
            const token = ctx.connectionParams?.authToken;

            // Authenticate user if middleware provided
            let user = null;
            if (authMiddleware && token) {
              try {
                user = await authMiddleware(token);
              } catch (error) {
                logger.error('WebSocket auth failed:', error);
              }
            }

            // Return context for subscriptions
            return {
              user,
              dataSources: {
                userAPI: dataSources.userAPI,
                licenseAPI: dataSources.licenseAPI,
                departmentAPI: dataSources.departmentAPI,
                optimizationAPI: dataSources.optimizationAPI,
                mlAPI: dataSources.mlAPI,
                statisticsAPI: dataSources.statisticsAPI
              },
              pubsub: pubsubInstance
            };
          },
          onConnect: async (ctx) => {
            logger.info('GraphQL WebSocket client connected');
          },
          onDisconnect: async (ctx) => {
            logger.info('GraphQL WebSocket client disconnected');
          }
        },
        wsServer
      );
    }

    // Configure Apollo Server plugins
    const plugins = [
      // Drain HTTP server on shutdown
      ApolloServerPluginDrainHttpServer({ httpServer }),

      // Add landing page in development
      enablePlayground ? ApolloServerPluginLandingPageLocalDefault({
        embed: true,
        includeCookies: true
      }) : undefined,

      // WebSocket cleanup plugin
      enableSubscriptions ? {
        async serverWillStart() {
          return {
            async drainServer() {
              await serverCleanup?.dispose();
            }
          };
        }
      } : undefined,

      // Logging plugin
      {
        async requestDidStart() {
          return {
            async willSendResponse(requestContext) {
              const { request, response } = requestContext;

              // Log GraphQL operations
              if (request.operationName) {
                logger.info('GraphQL operation', {
                  operationName: request.operationName,
                  query: request.query?.substring(0, 100),
                  variables: request.variables,
                  status: response.http?.status
                });
              }
            },
            async didEncounterErrors(requestContext) {
              const { errors } = requestContext;

              // Log GraphQL errors
              errors.forEach(error => {
                logger.error('GraphQL error', {
                  message: error.message,
                  path: error.path,
                  extensions: error.extensions
                });
              });
            }
          };
        }
      }
    ].filter(Boolean);

    // Create Apollo Server
    const server = new ApolloServer({
      schema,
      plugins,
      formatError: (formattedError, error) => {
        // Log full error details
        logger.error('GraphQL execution error:', error);

        // Return formatted error to client
        return {
          ...formattedError,
          extensions: {
            ...formattedError.extensions,
            // Add custom error codes
            code: formattedError.extensions?.code || 'INTERNAL_SERVER_ERROR',
            // Include stack trace in development
            ...(process.env.NODE_ENV === 'development' && {
              stacktrace: error.originalError?.stack
            })
          }
        };
      },
      introspection: enablePlayground,
      includeStacktraceInErrorResponses: process.env.NODE_ENV === 'development'
    });

    // Start Apollo Server
    await server.start();
    logger.info('GraphQL server started successfully');

    // Apply GraphQL middleware to Express
    app.use(
      path,
      cors(corsOptions),
      bodyParser.json(),
      expressMiddleware(server, {
        context: async ({ req }) => {
          // Get user from request (set by auth middleware)
          const user = req.user || null;

          // Initialize data sources with context
          const contextDataSources = {
            userAPI: dataSources.userAPI,
            licenseAPI: dataSources.licenseAPI,
            departmentAPI: dataSources.departmentAPI,
            optimizationAPI: dataSources.optimizationAPI,
            mlAPI: dataSources.mlAPI,
            statisticsAPI: dataSources.statisticsAPI
          };

          // Initialize each data source with context
          Object.values(contextDataSources).forEach(dataSource => {
            if (dataSource.initialize) {
              dataSource.initialize({
                context: { user, dataSources: contextDataSources }
              });
            }
          });

          // Return context for resolvers
          return {
            user,
            dataSources: contextDataSources,
            pubsub: pubsubInstance,
            req
          };
        }
      })
    );

    // Add GraphQL info endpoint
    app.get(`${path}/info`, (req, res) => {
      res.json({
        status: 'running',
        endpoint: path,
        playground: enablePlayground,
        subscriptions: enableSubscriptions,
        wsEndpoint: enableSubscriptions ? `ws://${req.get('host')}${path}` : null,
        introspection: enablePlayground,
        schema: 'Adobe Enterprise Automation GraphQL API',
        version: '1.0.0'
      });
    });

    logger.info(`GraphQL endpoint ready at ${path}`);
    if (enableSubscriptions) {
      logger.info(`GraphQL subscriptions ready at ws://localhost:${httpServer.address()?.port || 'PORT'}${path}`);
    }

    return {
      server,
      wsServer,
      dataSources
    };
  } catch (error) {
    logger.error('Failed to integrate GraphQL:', error);
    throw error;
  }
}

/**
 * Create a standalone GraphQL server
 * @param {number} port - Port to run the server on
 * @param {Object} options - Configuration options
 */
async function createStandaloneGraphQLServer(port = 4000, options = {}) {
  const express = require('express');
  const http = require('http');

  // Create Express app
  const app = express();
  const httpServer = http.createServer(app);

  // Add basic middleware
  app.use(cors());
  app.use(bodyParser.json());

  // Health check endpoint
  app.get('/health', (req, res) => {
    res.json({ status: 'healthy', service: 'graphql' });
  });

  // Integrate GraphQL
  const graphqlServer = await integrateGraphQL(app, httpServer, {
    ...options,
    enablePlayground: true,
    enableSubscriptions: true
  });

  // Start server
  await new Promise((resolve) => {
    httpServer.listen(port, () => {
      logger.info(`GraphQL standalone server running on port ${port}`);
      logger.info(`GraphQL endpoint: http://localhost:${port}/graphql`);
      logger.info(`GraphQL subscriptions: ws://localhost:${port}/graphql`);
      resolve();
    });
  });

  return {
    app,
    httpServer,
    graphqlServer
  };
}

/**
 * GraphQL authentication middleware
 * @param {string} token - Bearer token
 * @returns {Object} User object
 */
async function authenticateGraphQLUser(token) {
  if (!token || !token.startsWith('Bearer ')) {
    return null;
  }

  try {
    const jwt = require('jsonwebtoken');
    const decoded = jwt.verify(
      token.replace('Bearer ', ''),
      process.env.JWT_SECRET || 'your-secret-key'
    );

    // Add permissions based on role
    const permissions = [];
    if (decoded.role === 'admin') {
      permissions.push(
        'CREATE_USER',
        'UPDATE_USER',
        'DELETE_USER',
        'MANAGE_LICENSES',
        'OPTIMIZE_LICENSES',
        'ADMIN'
      );
    } else if (decoded.role === 'manager') {
      permissions.push(
        'CREATE_USER',
        'UPDATE_USER',
        'MANAGE_LICENSES'
      );
    } else {
      permissions.push('READ_ONLY');
    }

    return {
      id: decoded.id,
      email: decoded.email,
      role: decoded.role,
      permissions
    };
  } catch (error) {
    logger.error('GraphQL authentication failed:', error);
    return null;
  }
}

/**
 * Express middleware to add GraphQL auth
 */
function graphQLAuthMiddleware(req, res, next) {
  const token = req.headers.authorization;

  if (token) {
    authenticateGraphQLUser(token)
      .then(user => {
        req.user = user;
        next();
      })
      .catch(() => {
        req.user = null;
        next();
      });
  } else {
    req.user = null;
    next();
  }
}

module.exports = {
  integrateGraphQL,
  createStandaloneGraphQLServer,
  authenticateGraphQLUser,
  graphQLAuthMiddleware
};

// Run standalone server if executed directly
if (require.main === module) {
  const PORT = process.env.GRAPHQL_PORT || 4000;

  createStandaloneGraphQLServer(PORT)
    .then(() => {
      logger.info('GraphQL standalone server started successfully');
    })
    .catch(error => {
      logger.error('Failed to start GraphQL server:', error);
      process.exit(1);
    });
}