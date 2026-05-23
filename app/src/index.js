const express = require('express');
const morgan = require('morgan');
const helmet = require('helmet');
const cors = require('cors');

const healthRouter = require('./routes/health');
const apiRouter = require('./routes/api');
const { requestLogger } = require('./middleware/logger');

const app = express();
const PORT = process.env.PORT || 3000;
const SERVICE_VERSION = process.env.SERVICE_VERSION || 'unknown';
const ENVIRONMENT = process.env.NODE_ENV || 'development';

// ── Security & Middleware ────────────────────────────────────────────────────
app.use(helmet());
app.use(cors());
app.use(express.json({ limit: '10mb' }));
app.use(express.urlencoded({ extended: true }));
app.use(morgan('combined'));
app.use(requestLogger);

// ── Routes ───────────────────────────────────────────────────────────────────
app.use('/health', healthRouter);
app.use('/api/v1', apiRouter);

// ── Root endpoint ─────────────────────────────────────────────────────────────
app.get('/', (req, res) => {
  res.json({
    service: 'gitops-demo',
    version: SERVICE_VERSION,
    environment: ENVIRONMENT,
    timestamp: new Date().toISOString(),
    message: 'GitOps CI/CD Pipeline — Running Successfully 🚀',
  });
});

// ── 404 Handler ───────────────────────────────────────────────────────────────
app.use((req, res) => {
  res.status(404).json({
    error: 'Not Found',
    path: req.originalUrl,
    timestamp: new Date().toISOString(),
  });
});

// ── Global Error Handler ─────────────────────────────────────────────────────
app.use((err, req, res, next) => {
  console.error('[ERROR]', {
    message: err.message,
    stack: ENVIRONMENT === 'development' ? err.stack : undefined,
    path: req.originalUrl,
    method: req.method,
  });

  res.status(err.status || 500).json({
    error: ENVIRONMENT === 'production' ? 'Internal Server Error' : err.message,
    timestamp: new Date().toISOString(),
  });
});

// ── Start Server ──────────────────────────────────────────────────────────────
const server = app.listen(PORT, () => {
  console.log(`[INFO] Service starting...`);
  console.log(`[INFO] Environment : ${ENVIRONMENT}`);
  console.log(`[INFO] Version     : ${SERVICE_VERSION}`);
  console.log(`[INFO] Listening on: http://0.0.0.0:${PORT}`);
});

// ── Graceful Shutdown ─────────────────────────────────────────────────────────
const shutdown = (signal) => {
  console.log(`\n[INFO] Received ${signal}. Graceful shutdown initiated...`);
  server.close(() => {
    console.log('[INFO] HTTP server closed. Exiting process.');
    process.exit(0);
  });

  // Force shutdown after 10 seconds
  setTimeout(() => {
    console.error('[ERROR] Forced shutdown after timeout.');
    process.exit(1);
  }, 10000);
};

process.on('SIGTERM', () => shutdown('SIGTERM'));
process.on('SIGINT', () => shutdown('SIGINT'));

module.exports = app; // for testing
