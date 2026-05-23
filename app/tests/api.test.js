const request = require('supertest');
const app = require('../src/index');

describe('API Routes', () => {
  describe('GET /api/v1/info', () => {
    it('should return service info', async () => {
      const res = await request(app).get('/api/v1/info');
      expect(res.status).toBe(200);
      expect(res.body).toHaveProperty('version');
      expect(res.body).toHaveProperty('pipeline');
    });
  });

  describe('GET /api/v1/items', () => {
    it('should return all items', async () => {
      const res = await request(app).get('/api/v1/items');
      expect(res.status).toBe(200);
      expect(res.body).toHaveProperty('total');
      expect(Array.isArray(res.body.items)).toBe(true);
    });

    it('should filter by env query param', async () => {
      const res = await request(app).get('/api/v1/items?env=dev');
      expect(res.status).toBe(200);
      res.body.items.forEach(item => {
        expect(item.env).toBe('dev');
      });
    });
  });

  describe('POST /api/v1/items', () => {
    it('should create a new item', async () => {
      const res = await request(app)
        .post('/api/v1/items')
        .send({ name: 'Test Deployment', env: 'staging' });
      expect(res.status).toBe(201);
      expect(res.body.name).toBe('Test Deployment');
      expect(res.body.env).toBe('staging');
      expect(res.body.status).toBe('pending');
      expect(res.body).toHaveProperty('id');
    });

    it('should reject missing name', async () => {
      const res = await request(app)
        .post('/api/v1/items')
        .send({ env: 'dev' });
      expect(res.status).toBe(400);
      expect(res.body).toHaveProperty('error');
    });

    it('should reject invalid env', async () => {
      const res = await request(app)
        .post('/api/v1/items')
        .send({ name: 'Test', env: 'invalid-env' });
      expect(res.status).toBe(400);
    });
  });

  describe('GET /api/v1/items/:id', () => {
    it('should return 404 for non-existent item', async () => {
      const res = await request(app).get('/api/v1/items/99999');
      expect(res.status).toBe(404);
    });

    it('should return item by id', async () => {
      const res = await request(app).get('/api/v1/items/1');
      expect(res.status).toBe(200);
      expect(res.body.id).toBe(1);
    });
  });

  describe('PUT /api/v1/items/:id', () => {
    it('should update an existing item', async () => {
      const res = await request(app)
        .put('/api/v1/items/1')
        .send({ status: 'deployed' });
      expect(res.status).toBe(200);
      expect(res.body.status).toBe('deployed');
    });

    it('should reject invalid status', async () => {
      const res = await request(app)
        .put('/api/v1/items/1')
        .send({ status: 'blasting-off' });
      expect(res.status).toBe(400);
    });
  });

  describe('DELETE /api/v1/items/:id', () => {
    it('should return 404 for non-existent item', async () => {
      const res = await request(app).delete('/api/v1/items/99999');
      expect(res.status).toBe(404);
    });

    it('should delete an existing item', async () => {
      const res = await request(app).delete('/api/v1/items/2');
      expect(res.status).toBe(200);
      expect(res.body).toHaveProperty('message');
    });
  });
});
