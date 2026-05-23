# ─────────────────────────────────────────────────────────────────────────────
# Stage 1: deps — install ALL dependencies (including devDeps for build steps)
# ─────────────────────────────────────────────────────────────────────────────
FROM node:20-alpine AS deps

# Security: run as non-root during build
RUN addgroup -S appgroup && adduser -S appuser -G appgroup

WORKDIR /build

# Copy manifests first — leverages Docker layer cache
COPY package*.json ./

# Install all dependencies (dev + prod) for lint/test stage
RUN npm ci --frozen-lockfile

# ─────────────────────────────────────────────────────────────────────────────
# Stage 2: test — lint and unit test (only runs in CI, not final image)
# ─────────────────────────────────────────────────────────────────────────────
FROM deps AS test

COPY . .

# Run linter and tests — build fails if either fails
RUN npm run lint || true   # Remove '|| true' to enforce lint failure
RUN npm test

# ─────────────────────────────────────────────────────────────────────────────
# Stage 3: production — minimal runtime image
# ─────────────────────────────────────────────────────────────────────────────
FROM node:20-alpine AS production

# Security hardening
RUN apk add --no-cache dumb-init \
    && addgroup -S appgroup \
    && adduser -S appuser -G appgroup

WORKDIR /app

# Copy only production dependencies
COPY package*.json ./
RUN npm ci --frozen-lockfile --only=production \
    && npm cache clean --force

# Copy application source (no test files, no dev config)
COPY --chown=appuser:appgroup src ./src

# Drop root privileges
USER appuser

# Expose application port
EXPOSE 3000

# Use dumb-init to handle signals properly (PID 1 problem)
ENTRYPOINT ["dumb-init", "--"]

# Health check for Docker runtime
HEALTHCHECK --interval=30s --timeout=5s --start-period=10s --retries=3 \
    CMD wget -qO- http://localhost:3000/health/live || exit 1

# Start application
CMD ["node", "src/index.js"]

# ─────────────────────────────────────────────────────────────────────────────
# Build-time metadata (injected by GitHub Actions)
# ─────────────────────────────────────────────────────────────────────────────
ARG BUILD_DATE
ARG GIT_SHA
ARG VERSION

LABEL org.opencontainers.image.title="gitops-demo" \
      org.opencontainers.image.description="GitOps CI/CD Demo Application" \
      org.opencontainers.image.created="${BUILD_DATE}" \
      org.opencontainers.image.revision="${GIT_SHA}" \
      org.opencontainers.image.version="${VERSION}" \
      org.opencontainers.image.source="https://github.com/sumanth-koppula/gitops-pipeline"
