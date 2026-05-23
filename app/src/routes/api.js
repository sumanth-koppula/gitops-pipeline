const express = require('express');
const router = express.Router();

// In-memory store (replace with real DB in production)
let items = [
  { id: 1, name: 'Alpha Release', status: 'deployed', env: 'prod', createdAt: new Date().toISOString() },
  { id: 2, name: 'Beta Feature',  status: 'pending',  env: 'dev',  createdAt: new Date().toISOString() },
];
let nextId = 3;

// ── GET /api/v1/info ─────────────────────────────────────────────────────────
router.get('/info', (req, res) => {
  res.json({
    service: 'gitops-demo',
    version: process.env.SERVICE_VERSION || 'unknown',
    environment: process.env.NODE_ENV || 'development',
    node_version: process.version,
    pipeline: 'GitHub Actions → GCR → ArgoCD → GKE',
    timestamp: new Date().toISOString(),
  });
});

// ── GET /api/v1/items ────────────────────────────────────────────────────────
router.get('/items', (req, res) => {
  const { env, status } = req.query;

  let result = [...items];
  if (env)    result = result.filter(i => i.env === env);
  if (status) result = result.filter(i => i.status === status);

  res.json({
    total: result.length,
    items: result,
  });
});

// ── GET /api/v1/items/:id ────────────────────────────────────────────────────
router.get('/items/:id', (req, res) => {
  const id = parseInt(req.params.id);
  const item = items.find(i => i.id === id);

  if (!item) {
    return res.status(404).json({ error: `Item ${id} not found` });
  }
  res.json(item);
});

// ── POST /api/v1/items ───────────────────────────────────────────────────────
router.post('/items', (req, res) => {
  const { name, env = 'dev' } = req.body;

  if (!name || typeof name !== 'string' || name.trim().length === 0) {
    return res.status(400).json({ error: 'Field "name" is required and must be a non-empty string' });
  }

  const validEnvs = ['dev', 'staging', 'prod'];
  if (!validEnvs.includes(env)) {
    return res.status(400).json({ error: `Field "env" must be one of: ${validEnvs.join(', ')}` });
  }

  const newItem = {
    id: nextId++,
    name: name.trim(),
    status: 'pending',
    env,
    createdAt: new Date().toISOString(),
  };

  items.push(newItem);
  res.status(201).json(newItem);
});

// ── PUT /api/v1/items/:id ────────────────────────────────────────────────────
router.put('/items/:id', (req, res) => {
  const id = parseInt(req.params.id);
  const index = items.findIndex(i => i.id === id);

  if (index === -1) {
    return res.status(404).json({ error: `Item ${id} not found` });
  }

  const { name, status, env } = req.body;
  const validStatuses = ['pending', 'deployed', 'failed', 'rolling-back'];

  if (status && !validStatuses.includes(status)) {
    return res.status(400).json({ error: `Status must be one of: ${validStatuses.join(', ')}` });
  }

  items[index] = {
    ...items[index],
    ...(name   && { name }),
    ...(status && { status }),
    ...(env    && { env }),
    updatedAt: new Date().toISOString(),
  };

  res.json(items[index]);
});

// ── DELETE /api/v1/items/:id ─────────────────────────────────────────────────
router.delete('/items/:id', (req, res) => {
  const id = parseInt(req.params.id);
  const index = items.findIndex(i => i.id === id);

  if (index === -1) {
    return res.status(404).json({ error: `Item ${id} not found` });
  }

  const deleted = items.splice(index, 1)[0];
  res.json({ message: 'Deleted successfully', item: deleted });
});

module.exports = router;
