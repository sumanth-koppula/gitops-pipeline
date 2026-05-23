/**
 * Structured request logger middleware.
 * Logs method, path, status, latency, and request ID in JSON format
 * so logs are parseable by GCP Cloud Logging / Stackdriver.
 */
const { v4: uuidv4 } = require('uuid');

const requestLogger = (req, res, next) => {
  const requestId = req.headers['x-request-id'] || uuidv4();
  const startTime = process.hrtime.bigint();

  // Attach request ID to request and response
  req.requestId = requestId;
  res.setHeader('X-Request-ID', requestId);

  // Log on response finish
  res.on('finish', () => {
    const durationMs = Number(process.hrtime.bigint() - startTime) / 1_000_000;

    const logEntry = {
      severity: res.statusCode >= 500 ? 'ERROR' : res.statusCode >= 400 ? 'WARNING' : 'INFO',
      httpRequest: {
        requestMethod: req.method,
        requestUrl: req.originalUrl,
        status: res.statusCode,
        latency: `${durationMs.toFixed(2)}ms`,
        userAgent: req.headers['user-agent'],
        remoteIp: req.ip,
        requestId,
      },
      service: 'gitops-demo',
      environment: process.env.NODE_ENV || 'development',
      version: process.env.SERVICE_VERSION || 'unknown',
    };

    // Use structured logging compatible with GCP Cloud Logging
    if (res.statusCode >= 500) {
      console.error(JSON.stringify(logEntry));
    } else if (res.statusCode >= 400) {
      console.warn(JSON.stringify(logEntry));
    } else {
      console.log(JSON.stringify(logEntry));
    }
  });

  next();
};

module.exports = { requestLogger };
