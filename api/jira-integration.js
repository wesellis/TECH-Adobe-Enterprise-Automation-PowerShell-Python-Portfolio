/**
 * JIRA Integration Connector
 * Integrates Adobe automation with Atlassian JIRA for ticket management
 */

const axios = require('axios');
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

class JiraConnector {
  constructor(config = {}) {
    this.baseUrl = config.baseUrl || process.env.JIRA_BASE_URL;
    this.email = config.email || process.env.JIRA_EMAIL;
    this.apiToken = config.apiToken || process.env.JIRA_API_TOKEN;
    this.projectKey = config.projectKey || process.env.JIRA_PROJECT_KEY || 'ADOBE';

    if (!this.baseUrl || !this.email || !this.apiToken) {
      throw new Error('JIRA configuration missing. Required: baseUrl, email, apiToken');
    }

    // Configure axios instance
    this.client = axios.create({
      baseURL: `${this.baseUrl}/rest/api/3`,
      headers: {
        'Accept': 'application/json',
        'Content-Type': 'application/json'
      },
      auth: {
        username: this.email,
        password: this.apiToken
      },
      timeout: 30000
    });

    // Request interceptor for logging
    this.client.interceptors.request.use(
      request => {
        logger.debug(`JIRA Request: ${request.method?.toUpperCase()} ${request.url}`);
        return request;
      },
      error => Promise.reject(error)
    );

    // Response interceptor for error handling
    this.client.interceptors.response.use(
      response => response,
      error => {
        logger.error(`JIRA Error: ${error.response?.status} - ${error.response?.data?.message || error.message}`);
        return Promise.reject(error);
      }
    );
  }

  /**
   * Test JIRA connection
   */
  async testConnection() {
    try {
      const response = await this.client.get('/myself');
      logger.info(`JIRA connection successful. Connected as: ${response.data.displayName}`);
      return {
        connected: true,
        user: response.data.displayName,
        accountId: response.data.accountId
      };
    } catch (error) {
      logger.error('JIRA connection failed:', error.message);
      return {
        connected: false,
        error: error.message
      };
    }
  }

  /**
   * Create a JIRA ticket for Adobe user provisioning
   */
  async createProvisioningTicket(userData) {
    const { email, firstName, lastName, department, products, requestedBy } = userData;

    const issueData = {
      fields: {
        project: {
          key: this.projectKey
        },
        summary: `Adobe User Provisioning: ${firstName} ${lastName}`,
        description: {
          type: 'doc',
          version: 1,
          content: [
            {
              type: 'paragraph',
              content: [
                {
                  type: 'text',
                  text: 'Adobe Creative Cloud user provisioning request'
                }
              ]
            },
            {
              type: 'paragraph',
              content: [
                {
                  type: 'text',
                  text: `User Email: ${email}`,
                  marks: [{ type: 'strong' }]
                }
              ]
            },
            {
              type: 'paragraph',
              content: [
                {
                  type: 'text',
                  text: `Name: ${firstName} ${lastName}`
                }
              ]
            },
            {
              type: 'paragraph',
              content: [
                {
                  type: 'text',
                  text: `Department: ${department}`
                }
              ]
            },
            {
              type: 'paragraph',
              content: [
                {
                  type: 'text',
                  text: `Products Requested: ${products.join(', ')}`
                }
              ]
            },
            {
              type: 'paragraph',
              content: [
                {
                  type: 'text',
                  text: `Requested By: ${requestedBy || 'System'}`
                }
              ]
            }
          ]
        },
        issuetype: {
          name: 'Task'
        },
        priority: {
          name: 'Medium'
        },
        labels: ['adobe-automation', 'user-provisioning', department.toLowerCase()],
        customfield_10000: email // Custom field for user email
      }
    };

    try {
      const response = await this.client.post('/issue', issueData);
      const issueKey = response.data.key;

      logger.info(`Created JIRA ticket: ${issueKey}`);

      return {
        success: true,
        issueKey,
        issueId: response.data.id,
        url: `${this.baseUrl}/browse/${issueKey}`
      };
    } catch (error) {
      logger.error('Failed to create JIRA ticket:', error.response?.data || error.message);
      throw error;
    }
  }

  /**
   * Create a license optimization ticket
   */
  async createLicenseOptimizationTicket(optimizationData) {
    const { totalReclaimed, departments, products, savings } = optimizationData;

    const issueData = {
      fields: {
        project: {
          key: this.projectKey
        },
        summary: `License Optimization: ${totalReclaimed} licenses reclaimed`,
        description: {
          type: 'doc',
          version: 1,
          content: [
            {
              type: 'heading',
              attrs: { level: 3 },
              content: [
                {
                  type: 'text',
                  text: 'Adobe License Optimization Report'
                }
              ]
            },
            {
              type: 'paragraph',
              content: [
                {
                  type: 'text',
                  text: `Total Licenses Reclaimed: ${totalReclaimed}`,
                  marks: [{ type: 'strong' }]
                }
              ]
            },
            {
              type: 'paragraph',
              content: [
                {
                  type: 'text',
                  text: `Estimated Monthly Savings: $${savings}`
                }
              ]
            },
            {
              type: 'paragraph',
              content: [
                {
                  type: 'text',
                  text: `Affected Departments: ${departments.join(', ')}`
                }
              ]
            },
            {
              type: 'paragraph',
              content: [
                {
                  type: 'text',
                  text: `Products Optimized: ${products.join(', ')}`
                }
              ]
            }
          ]
        },
        issuetype: {
          name: 'Task'
        },
        priority: {
          name: 'Low'
        },
        labels: ['adobe-automation', 'license-optimization', 'cost-savings']
      }
    };

    try {
      const response = await this.client.post('/issue', issueData);
      const issueKey = response.data.key;

      logger.info(`Created optimization ticket: ${issueKey}`);

      return {
        success: true,
        issueKey,
        issueId: response.data.id,
        url: `${this.baseUrl}/browse/${issueKey}`
      };
    } catch (error) {
      logger.error('Failed to create optimization ticket:', error.message);
      throw error;
    }
  }

  /**
   * Create an incident ticket for Adobe service issues
   */
  async createIncidentTicket(incidentData) {
    const { title, description, severity, affectedUsers, service } = incidentData;

    const priorityMap = {
      'critical': 'Highest',
      'high': 'High',
      'medium': 'Medium',
      'low': 'Low'
    };

    const issueData = {
      fields: {
        project: {
          key: this.projectKey
        },
        summary: `[INCIDENT] ${title}`,
        description: {
          type: 'doc',
          version: 1,
          content: [
            {
              type: 'paragraph',
              content: [
                {
                  type: 'text',
                  text: description
                }
              ]
            },
            {
              type: 'paragraph',
              content: [
                {
                  type: 'text',
                  text: `Affected Service: ${service}`,
                  marks: [{ type: 'strong' }]
                }
              ]
            },
            {
              type: 'paragraph',
              content: [
                {
                  type: 'text',
                  text: `Number of Affected Users: ${affectedUsers}`
                }
              ]
            },
            {
              type: 'paragraph',
              content: [
                {
                  type: 'text',
                  text: `Incident Time: ${new Date().toISOString()}`
                }
              ]
            }
          ]
        },
        issuetype: {
          name: 'Bug'
        },
        priority: {
          name: priorityMap[severity] || 'Medium'
        },
        labels: ['adobe-automation', 'incident', service.toLowerCase().replace(/\s+/g, '-')]
      }
    };

    try {
      const response = await this.client.post('/issue', issueData);
      const issueKey = response.data.key;

      logger.info(`Created incident ticket: ${issueKey}`);

      return {
        success: true,
        issueKey,
        issueId: response.data.id,
        url: `${this.baseUrl}/browse/${issueKey}`
      };
    } catch (error) {
      logger.error('Failed to create incident ticket:', error.message);
      throw error;
    }
  }

  /**
   * Update a JIRA ticket
   */
  async updateTicket(issueKey, updateData) {
    const { comment, status, assignee, labels } = updateData;

    try {
      // Add comment if provided
      if (comment) {
        await this.addComment(issueKey, comment);
      }

      // Update fields
      const fields = {};

      if (assignee) {
        fields.assignee = { accountId: assignee };
      }

      if (labels) {
        fields.labels = labels;
      }

      if (Object.keys(fields).length > 0) {
        await this.client.put(`/issue/${issueKey}`, { fields });
      }

      // Transition issue if status provided
      if (status) {
        await this.transitionIssue(issueKey, status);
      }

      logger.info(`Updated ticket: ${issueKey}`);

      return {
        success: true,
        issueKey
      };
    } catch (error) {
      logger.error(`Failed to update ticket ${issueKey}:`, error.message);
      throw error;
    }
  }

  /**
   * Add a comment to a JIRA ticket
   */
  async addComment(issueKey, comment) {
    const commentData = {
      body: {
        type: 'doc',
        version: 1,
        content: [
          {
            type: 'paragraph',
            content: [
              {
                type: 'text',
                text: comment
              }
            ]
          }
        ]
      }
    };

    try {
      await this.client.post(`/issue/${issueKey}/comment`, commentData);
      logger.info(`Added comment to ${issueKey}`);
      return true;
    } catch (error) {
      logger.error(`Failed to add comment to ${issueKey}:`, error.message);
      throw error;
    }
  }

  /**
   * Transition an issue to a different status
   */
  async transitionIssue(issueKey, targetStatus) {
    try {
      // Get available transitions
      const transitionsResponse = await this.client.get(`/issue/${issueKey}/transitions`);
      const transitions = transitionsResponse.data.transitions;

      // Find target transition
      const transition = transitions.find(t =>
        t.name.toLowerCase() === targetStatus.toLowerCase() ||
        t.to.name.toLowerCase() === targetStatus.toLowerCase()
      );

      if (!transition) {
        throw new Error(`Transition to status '${targetStatus}' not available`);
      }

      // Perform transition
      await this.client.post(`/issue/${issueKey}/transitions`, {
        transition: { id: transition.id }
      });

      logger.info(`Transitioned ${issueKey} to ${targetStatus}`);
      return true;
    } catch (error) {
      logger.error(`Failed to transition ${issueKey}:`, error.message);
      throw error;
    }
  }

  /**
   * Get ticket details
   */
  async getTicket(issueKey) {
    try {
      const response = await this.client.get(`/issue/${issueKey}`);

      return {
        key: response.data.key,
        summary: response.data.fields.summary,
        status: response.data.fields.status.name,
        priority: response.data.fields.priority?.name,
        assignee: response.data.fields.assignee?.displayName,
        reporter: response.data.fields.reporter?.displayName,
        created: response.data.fields.created,
        updated: response.data.fields.updated,
        description: response.data.fields.description,
        labels: response.data.fields.labels,
        url: `${this.baseUrl}/browse/${issueKey}`
      };
    } catch (error) {
      logger.error(`Failed to get ticket ${issueKey}:`, error.message);
      throw error;
    }
  }

  /**
   * Search for tickets using JQL
   */
  async searchTickets(jql, maxResults = 50) {
    try {
      const response = await this.client.post('/search', {
        jql,
        maxResults,
        fields: ['key', 'summary', 'status', 'priority', 'assignee', 'created', 'updated']
      });

      return response.data.issues.map(issue => ({
        key: issue.key,
        summary: issue.fields.summary,
        status: issue.fields.status.name,
        priority: issue.fields.priority?.name,
        assignee: issue.fields.assignee?.displayName,
        created: issue.fields.created,
        updated: issue.fields.updated,
        url: `${this.baseUrl}/browse/${issue.key}`
      }));
    } catch (error) {
      logger.error('Failed to search tickets:', error.message);
      throw error;
    }
  }

  /**
   * Get recent Adobe automation tickets
   */
  async getRecentAutomationTickets(days = 7) {
    const jql = `project = ${this.projectKey} AND labels = adobe-automation AND created >= -${days}d ORDER BY created DESC`;
    return this.searchTickets(jql);
  }

  /**
   * Get open provisioning tickets
   */
  async getOpenProvisioningTickets() {
    const jql = `project = ${this.projectKey} AND labels = user-provisioning AND status NOT IN (Done, Closed, Resolved)`;
    return this.searchTickets(jql);
  }

  /**
   * Link two issues
   */
  async linkIssues(inwardIssue, outwardIssue, linkType = 'Relates') {
    try {
      await this.client.post('/issueLink', {
        type: { name: linkType },
        inwardIssue: { key: inwardIssue },
        outwardIssue: { key: outwardIssue }
      });

      logger.info(`Linked ${inwardIssue} to ${outwardIssue}`);
      return true;
    } catch (error) {
      logger.error('Failed to link issues:', error.message);
      throw error;
    }
  }

  /**
   * Attach a file to a ticket
   */
  async attachFile(issueKey, filePath, fileName) {
    const FormData = require('form-data');
    const fs = require('fs');

    const form = new FormData();
    form.append('file', fs.createReadStream(filePath), fileName);

    try {
      await this.client.post(`/issue/${issueKey}/attachments`, form, {
        headers: {
          ...form.getHeaders(),
          'X-Atlassian-Token': 'no-check'
        }
      });

      logger.info(`Attached file to ${issueKey}`);
      return true;
    } catch (error) {
      logger.error(`Failed to attach file to ${issueKey}:`, error.message);
      throw error;
    }
  }
}

// Express middleware for JIRA integration
function jiraMiddleware(jiraConnector) {
  return (req, res, next) => {
    req.jira = jiraConnector;
    next();
  };
}

// Export for use in other modules
module.exports = {
  JiraConnector,
  jiraMiddleware
};

// Example usage
if (require.main === module) {
  (async () => {
    try {
      // Initialize JIRA connector
      const jira = new JiraConnector({
        baseUrl: 'https://your-domain.atlassian.net',
        email: 'your-email@company.com',
        apiToken: 'your-api-token',
        projectKey: 'ADOBE'
      });

      // Test connection
      const connectionTest = await jira.testConnection();
      console.log('Connection test:', connectionTest);

      // Create a provisioning ticket
      const ticket = await jira.createProvisioningTicket({
        email: 'john.doe@company.com',
        firstName: 'John',
        lastName: 'Doe',
        department: 'Marketing',
        products: ['Creative Cloud', 'Acrobat Pro'],
        requestedBy: 'admin@company.com'
      });
      console.log('Created ticket:', ticket);

      // Get recent tickets
      const recentTickets = await jira.getRecentAutomationTickets();
      console.log('Recent tickets:', recentTickets);

    } catch (error) {
      console.error('Example failed:', error);
    }
  })();
}