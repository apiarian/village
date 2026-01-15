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

# Configure poetry to install globally (no virtualenv)
RUN poetry config virtualenvs.create false

# Copy application code
COPY village_py/village /build/village/

# Install everything together (dependencies + package)
# This ensures scripts are properly installed
RUN poetry install --only main --no-interaction --no-ansi

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

# Create non-root user with configurable UID
RUN adduser -D -u ${VILLAGE_UID} -s /bin/sh village

# Set working directory
WORKDIR /app

# Copy Python site-packages from builder (includes all dependencies and the installed package)
COPY --from=builder /usr/local/lib/python3.11/site-packages /usr/local/lib/python3.11/site-packages

# Copy installed scripts from builder
COPY --from=builder /usr/local/bin/initialize-repository /usr/local/bin/
COPY --from=builder /usr/local/bin/create-user /usr/local/bin/
COPY --from=builder /usr/local/bin/force-reset-password /usr/local/bin/
COPY --from=builder /usr/local/bin/update-thumbnail /usr/local/bin/
COPY --from=builder /usr/local/bin/gunicorn /usr/local/bin/

# Copy application files (needed for imports to work correctly)
COPY --chown=village:village village_py/pyproject.toml village_py/poetry.lock /app/
COPY --chown=village:village village_py/village /app/village/
COPY --chown=village:village village_docker/entrypoint.sh /app/

# Make entrypoint and scripts executable
RUN chmod +x /app/entrypoint.sh && \
    chmod +x /usr/local/bin/initialize-repository && \
    chmod +x /usr/local/bin/create-user && \
    chmod +x /usr/local/bin/force-reset-password && \
    chmod +x /usr/local/bin/update-thumbnail && \
    chmod +x /usr/local/bin/gunicorn

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
