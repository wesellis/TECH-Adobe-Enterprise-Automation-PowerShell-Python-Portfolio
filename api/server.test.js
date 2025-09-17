const request = require('supertest');
const jwt = require('jsonwebtoken');

// Mock dependencies
jest.mock('mssql');
jest.mock('redis', () => ({
  createClient: jest.fn(() => ({
    connect: jest.fn(),
    get: jest.fn(),
    set: jest.fn(),
    del: jest.fn(),
    on: jest.fn(),
  })),
}));

describe('Adobe Enterprise Automation API', () => {
  let app;
  let server;

  beforeAll(() => {
    // Set test environment variables
    process.env.NODE_ENV = 'test';
    process.env.JWT_SECRET = 'test-secret-key';
    process.env.PORT = '3001';

    // Require app after setting env vars
    app = require('./server');
  });

  afterAll(done => {
    if (server && server.close) {
      server.close(done);
    } else {
      done();
    }
  });

  describe('Health Check', () => {
    test('GET /health should return 200 with status ok', async () => {
      const response = await request(app)
        .get('/health')
        .expect('Content-Type', /json/)
        .expect(200);

      expect(response.body).toHaveProperty('status', 'ok');
      expect(response.body).toHaveProperty('timestamp');
      expect(response.body).toHaveProperty('uptime');
    });
  });

  describe('Authentication', () => {
    test('POST /api/auth/login with valid credentials should return JWT token', async () => {
      const credentials = {
        username: 'admin@company.com',
        password: 'SecurePassword123!',
      };

      const response = await request(app)
        .post('/api/auth/login')
        .send(credentials)
        .expect('Content-Type', /json/)
        .expect(200);

      expect(response.body).toHaveProperty('token');
      expect(response.body).toHaveProperty('user');
      expect(response.body.user).toHaveProperty('email', credentials.username);
    });

    test('POST /api/auth/login with invalid credentials should return 401', async () => {
      const credentials = {
        username: 'invalid@company.com',
        password: 'wrongpassword',
      };

      const response = await request(app)
        .post('/api/auth/login')
        .send(credentials)
        .expect('Content-Type', /json/)
        .expect(401);

      expect(response.body).toHaveProperty('error');
    });

    test('POST /api/auth/login with missing fields should return 400', async () => {
      const response = await request(app)
        .post('/api/auth/login')
        .send({})
        .expect('Content-Type', /json/)
        .expect(400);

      expect(response.body).toHaveProperty('error');
    });
  });

  describe('User Management', () => {
    let authToken;

    beforeAll(() => {
      // Generate a valid JWT for testing
      authToken = jwt.sign(
        { id: 1, email: 'admin@company.com', role: 'admin' },
        process.env.JWT_SECRET,
        { expiresIn: '1h' }
      );
    });

    test('GET /api/users should require authentication', async () => {
      await request(app)
        .get('/api/users')
        .expect('Content-Type', /json/)
        .expect(401);
    });

    test('GET /api/users with valid token should return users list', async () => {
      const response = await request(app)
        .get('/api/users')
        .set('Authorization', `Bearer ${authToken}`)
        .expect('Content-Type', /json/)
        .expect(200);

      expect(response.body).toHaveProperty('users');
      expect(Array.isArray(response.body.users)).toBe(true);
    });

    test('POST /api/users should create a new user', async () => {
      const newUser = {
        email: 'newuser@company.com',
        firstName: 'John',
        lastName: 'Doe',
        department: 'Marketing',
        products: ['Creative Cloud', 'Acrobat Pro'],
      };

      const response = await request(app)
        .post('/api/users')
        .set('Authorization', `Bearer ${authToken}`)
        .send(newUser)
        .expect('Content-Type', /json/)
        .expect(201);

      expect(response.body).toHaveProperty('user');
      expect(response.body.user).toHaveProperty('email', newUser.email);
    });

    test('POST /api/users with invalid email should return 400', async () => {
      const invalidUser = {
        email: 'not-an-email',
        firstName: 'John',
        lastName: 'Doe',
      };

      await request(app)
        .post('/api/users')
        .set('Authorization', `Bearer ${authToken}`)
        .send(invalidUser)
        .expect('Content-Type', /json/)
        .expect(400);
    });

    test('DELETE /api/users/:id should remove user', async () => {
      await request(app)
        .delete('/api/users/123')
        .set('Authorization', `Bearer ${authToken}`)
        .expect(204);
    });
  });

  describe('License Management', () => {
    let authToken;

    beforeAll(() => {
      authToken = jwt.sign(
        { id: 1, email: 'admin@company.com', role: 'admin' },
        process.env.JWT_SECRET,
        { expiresIn: '1h' }
      );
    });

    test('GET /api/licenses should return license information', async () => {
      const response = await request(app)
        .get('/api/licenses')
        .set('Authorization', `Bearer ${authToken}`)
        .expect('Content-Type', /json/)
        .expect(200);

      expect(response.body).toHaveProperty('licenses');
      expect(response.body).toHaveProperty('summary');
    });

    test('GET /api/licenses/utilization should return utilization metrics', async () => {
      const response = await request(app)
        .get('/api/licenses/utilization')
        .set('Authorization', `Bearer ${authToken}`)
        .expect('Content-Type', /json/)
        .expect(200);

      expect(response.body).toHaveProperty('utilization');
      expect(response.body).toHaveProperty('recommendations');
    });

    test('POST /api/licenses/optimize should trigger optimization', async () => {
      const optimizationParams = {
        inactiveDays: 30,
        autoReclaim: true,
      };

      const response = await request(app)
        .post('/api/licenses/optimize')
        .set('Authorization', `Bearer ${authToken}`)
        .send(optimizationParams)
        .expect('Content-Type', /json/)
        .expect(200);

      expect(response.body).toHaveProperty('optimized');
      expect(response.body).toHaveProperty('reclaimedLicenses');
    });
  });

  describe('Reports', () => {
    let authToken;

    beforeAll(() => {
      authToken = jwt.sign(
        { id: 1, email: 'admin@company.com', role: 'admin' },
        process.env.JWT_SECRET,
        { expiresIn: '1h' }
      );
    });

    test('GET /api/reports/usage should return usage report', async () => {
      const response = await request(app)
        .get('/api/reports/usage')
        .set('Authorization', `Bearer ${authToken}`)
        .query({ startDate: '2024-01-01', endDate: '2024-01-31' })
        .expect('Content-Type', /json/)
        .expect(200);

      expect(response.body).toHaveProperty('report');
      expect(response.body).toHaveProperty('period');
    });

    test('GET /api/reports/compliance should return compliance report', async () => {
      const response = await request(app)
        .get('/api/reports/compliance')
        .set('Authorization', `Bearer ${authToken}`)
        .expect('Content-Type', /json/)
        .expect(200);

      expect(response.body).toHaveProperty('compliant');
      expect(response.body).toHaveProperty('violations');
    });
  });

  describe('Error Handling', () => {
    test('GET /nonexistent should return 404', async () => {
      await request(app)
        .get('/nonexistent')
        .expect('Content-Type', /json/)
        .expect(404);
    });

    test('Invalid JSON should return 400', async () => {
      await request(app)
        .post('/api/users')
        .set('Content-Type', 'application/json')
        .send('{"invalid json}')
        .expect(400);
    });
  });

  describe('Rate Limiting', () => {
    test('Should enforce rate limiting after threshold', async () => {
      const requests = Array(101).fill().map(() =>
        request(app).get('/api/users')
      );

      const responses = await Promise.all(requests);
      const rateLimited = responses.some(res => res.status === 429);

      expect(rateLimited).toBe(true);
    });
  });

  describe('Security Headers', () => {
    test('Should include security headers', async () => {
      const response = await request(app)
        .get('/health')
        .expect(200);

      expect(response.headers).toHaveProperty('x-content-type-options', 'nosniff');
      expect(response.headers).toHaveProperty('x-frame-options');
      expect(response.headers).toHaveProperty('x-xss-protection');
    });
  });
});