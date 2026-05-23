const express = require('express');
const router = express.Router();

// Track startup time for uptime calculation
const startTime = Date.now();

/**
 * GET /health/live
 * Kubernetes liveness probe — is the process alive?
 * Returns 200 if the process is running, 503 otherwise.
 */
router.get('/live', (req, res) => {
  res.status(200).json({
    status: 'alive',
    uptime: Math.floor((Date.now() - startTime) / 1000),
    timestamp: new Date().toISOString(),
  });
});

/**
 * GET /health/ready
 * Kubernetes readiness probe — is the app ready to serve traffic?
 * Checks all dependencies before accepting requests.
 */
router.get('/ready', async (req, res) => {
  const checks = {};
  let healthy = true;

  // Check: Memory usage
  const memUsage = process.memoryUsage();
  const memUsedMB = Math.round(memUsage.rss / 1024 / 1024);
  const memLimitMB = parseInt(process.env.MEMORY_LIMIT_MB || '512');
  const memOk = memUsedMB < memLimitMB;

  checks.memory = {
    status: memOk ? 'ok' : 'critical',
    used_mb: memUsedMB,
    limit_mb: memLimitMB,
  };

  if (!memOk) healthy = false;

  // Check: External dependencies (database, cache, etc.)
  // Extend here with real dependency checks
  checks.dependencies = {
    status: 'ok',
    note: 'No external dependencies in demo mode',
  };

  const statusCode = healthy ? 200 : 503;

  res.status(statusCode).json({
    status: healthy ? 'ready' : 'not_ready',
    checks,
    uptime: Math.floor((Date.now() - startTime) / 1000),
    version: process.env.SERVICE_VERSION || 'unknown',
    environment: process.env.NODE_ENV || 'development',
    timestamp: new Date().toISOString(),
  });
});

/**
 * GET /health
 * General health summary — used by load balancers and monitoring.
 */
router.get('/', (req, res) => {
  res.status(200).json({
    status: 'healthy',
    service: 'gitops-demo',
    version: process.env.SERVICE_VERSION || 'unknown',
    environment: process.env.NODE_ENV || 'development',
    uptime_seconds: Math.floor((Date.now() - startTime) / 1000),
    timestamp: new Date().toISOString(),
  });
});

module.exports = router;
