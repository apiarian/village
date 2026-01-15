# Multi-stage build for Village application
# Build context: repository root (village/)
#
# Build arguments:
#   VILLAGE_UID: User ID for the village user (default: 10000)
#   Example: docker build --build-arg VILLAGE_UID=991 -f village_docker/Dockerfile -t village:latest .

# ============================================================================
# Builder Stage: Install dependencies and prepare application
# ============================================================================
FROM python:3.11-alpine AS builder

# Install build dependencies
RUN apk add --no-cache \
    gcc \
    musl-dev \
    libffi-dev \
    openssl-dev \
    cargo \
    rust

# Install Poetry
RUN pip install --no-cache-dir poetry==1.7.1

# Set working directory for build
WORKDIR /build

# Copy dependency files first (for better caching)
COPY village_py/pyproject.toml village_py/poetry.lock /build/

# Install dependencies (no dev dependencies, no root package yet)
RUN poetry config virtualenvs.create false && \
    poetry install --no-dev --no-root --no-interaction --no-ansi

# Copy application code
COPY village_py/village /build/village/

# ============================================================================
# Runtime Stage: Minimal image with application
# ============================================================================
FROM python:3.11-alpine

# Build argument for user ID (can be overridden at build time)
ARG VILLAGE_UID=10000

# Install runtime dependencies
RUN apk add --no-cache \
    libffi \
    openssl \
    curl \
    git

# Install Poetry in runtime (needed for running scripts)
RUN pip install --no-cache-dir poetry==1.7.1

# Create non-root user with configurable UID
RUN adduser -D -u ${VILLAGE_UID} -s /bin/sh village

# Set working directory
WORKDIR /app

# Copy Python packages from builder
COPY --from=builder /usr/local/lib/python3.11/site-packages /usr/local/lib/python3.11/site-packages

# Copy application files
COPY --chown=village:village village_py/pyproject.toml village_py/poetry.lock /app/
COPY --chown=village:village village_py/village /app/village/
COPY --chown=village:village village_docker/entrypoint.sh /app/

# Make entrypoint executable
RUN chmod +x /app/entrypoint.sh

# Create directories for volumes (will be mounted from host)
RUN mkdir -p /opt/village/data /opt/village/logs && \
    chown -R village:village /opt/village

# Switch to non-root user
USER village

# Expose port
EXPOSE 8000

# Health check using the /about endpoint
HEALTHCHECK --interval=30s --timeout=10s --start-period=40s --retries=3 \
    CMD curl -f http://localhost:8000/about || exit 1

# Set entrypoint
ENTRYPOINT ["/app/entrypoint.sh"]
