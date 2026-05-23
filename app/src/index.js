'use strict';

const express = require('express');
const app = express();

const PORT = process.env.PORT || 3000;
const ENVIRONMENT = process.env.NODE_ENV || 'development';
const SERVICE_VERSION = process.env.SERVICE_VERSION || 'unknown';

app.use(express.json());

// Import routes
const healthRoutes = require('./routes/health');
const apiRoutes = require('./routes/api');
const { requestLogger } = require('./middleware/logger');

app.use(requestLogger);
app.use('/health', healthRoutes);
app.use('/api/v1', apiRoutes);

// Root route
app.get('/', (req, res) => {
  res.json({
    service: 'gitops-demo',
    version: SERVICE_VERSION,
    environment: ENVIRONMENT,
    status: 'running'
  });
});

// 404 handler
app.use((req, res) => {
  res.status(404).json({ error: 'Not found' });
});

// Only start server if this file is run directly (not imported by tests)
if (require.main === module) {
  const server = app.listen(PORT, () => {
    console.log(`[INFO] Service starting...`);
    console.log(`[INFO] Environment : ${ENVIRONMENT}`);
    console.log(`[INFO] Version     : ${SERVICE_VERSION}`);
    console.log(`[INFO] Listening on: http://0.0.0.0:${PORT}`);
  });

  module.exports = { app, server };
} else {
  module.exports = { app };
}
