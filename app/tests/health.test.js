const request = require('supertest');
const app = require('../src/index');

describe('Health Routes', () => {
  afterAll(() => {
    // Clean up server after tests
    if (app.server && app.server.close) {
      app.server.close();
    }
  });

  describe('GET /health', () => {
    it('should return 200 with healthy status', async () => {
      const res = await request(app).get('/health');
      expect(res.status).toBe(200);
      expect(res.body.status).toBe('healthy');
      expect(res.body.service).toBe('gitops-demo');
      expect(res.body).toHaveProperty('uptime_seconds');
      expect(res.body).toHaveProperty('timestamp');
    });
  });

  describe('GET /health/live', () => {
    it('should return 200 when process is alive', async () => {
      const res = await request(app).get('/health/live');
      expect(res.status).toBe(200);
      expect(res.body.status).toBe('alive');
      expect(res.body.uptime).toBeGreaterThanOrEqual(0);
    });
  });

  describe('GET /health/ready', () => {
    it('should return 200 when app is ready', async () => {
      const res = await request(app).get('/health/ready');
      expect(res.status).toBe(200);
      expect(res.body.status).toBe('ready');
      expect(res.body.checks).toHaveProperty('memory');
      expect(res.body.checks.memory.status).toBe('ok');
    });
  });

  describe('GET /', () => {
    it('should return service info at root', async () => {
      const res = await request(app).get('/');
      expect(res.status).toBe(200);
      expect(res.body.service).toBe('gitops-demo');
      expect(res.body.message).toContain('GitOps');
    });
  });

  describe('404 handling', () => {
    it('should return 404 for unknown routes', async () => {
      const res = await request(app).get('/nonexistent-route');
      expect(res.status).toBe(404);
      expect(res.body).toHaveProperty('error');
    });
  });
});
