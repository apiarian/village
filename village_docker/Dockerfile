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

# Copy README (referenced in pyproject.toml)
COPY village_py/README.md /build/

# Configure poetry to NOT create virtualenvs (install globally)
RUN poetry config virtualenvs.create false && \
    poetry config --list

# Copy application code
COPY village_py/village /build/village/

# Debug: Show what we're about to install
RUN echo "=== Contents before install ===" && \
    ls -la /build/ && \
    echo "" && \
    echo "=== pyproject.toml content ===" && \
    cat /build/pyproject.toml

# Install everything together (dependencies + package)
# This ensures scripts are properly installed
RUN poetry install --only main --no-interaction --no-ansi -vvv

# Debug: Show where things got installed
RUN echo "=== Python site-packages directory ===" && \
    ls -la /usr/local/lib/python3.11/site-packages/ && \
    echo "" && \
    echo "=== Looking for village in site-packages ===" && \
    (ls -la /usr/local/lib/python3.11/site-packages/ | grep village || echo "WARNING: village not found in site-packages listing") && \
    echo "" && \
    echo "=== Checking if village directory/files exist ===" && \
    (ls -la /usr/local/lib/python3.11/site-packages/village* 2>/dev/null || echo "No village files found") && \
    echo "" && \
    echo "=== Testing import in builder ===" && \
    python -c "import village; print('✓ village module importable in builder'); print('Village location:', village.__file__)" || echo "✗ ERROR: Cannot import village in builder!" && \
    echo "" && \
    echo "=== Checking for entry points ===" && \
    python -c "from importlib.metadata import entry_points; eps = entry_points(); console_scripts = eps.get('console_scripts', []); print('Console scripts:', [str(ep) for ep in console_scripts])" && \
    echo "" && \
    echo "=== Contents of /usr/local/bin ===" && \
    ls -la /usr/local/bin/

# Verify that scripts were actually installed
RUN echo "" && \
    echo "=== Checking for required scripts ===" && \
    for script in initialize-repository create-user force-reset-password update-thumbnail gunicorn; do \
        if [ -f "/usr/local/bin/$script" ]; then \
            echo "✓ Found: $script"; \
        else \
            echo "✗ MISSING: $script"; \
            echo "ERROR: Script $script was not installed by poetry!"; \
            exit 1; \
        fi; \
    done && \
    echo "=== All required scripts found ==="

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

# Copy all binaries from builder (includes gunicorn and poetry-installed scripts)
# We copy everything to avoid issues with missing scripts
COPY --from=builder /usr/local/bin /usr/local/bin

# Verify scripts are present in runtime stage
RUN echo "=== Verifying scripts in runtime stage ===" && \
    ls -la /usr/local/bin/ && \
    echo "" && \
    echo "=== Checking for required scripts ===" && \
    for script in initialize-repository create-user force-reset-password update-thumbnail gunicorn; do \
        if [ -f "/usr/local/bin/$script" ]; then \
            echo "✓ Found: $script"; \
        else \
            echo "✗ MISSING: $script"; \
            echo "ERROR: Script $script was not copied to runtime!"; \
            exit 1; \
        fi; \
    done && \
    echo "=== All required scripts verified in runtime ===" && \
    echo "" && \
    echo "=== Checking site-packages for village ===" && \
    ls -la /usr/local/lib/python3.11/site-packages/ | grep village || echo "WARNING: village not found in site-packages!" && \
    echo "" && \
    echo "=== Testing Python import ===" && \
    python -c "import sys; print('Python path:', sys.path)" && \
    python -c "import village; print('✓ village module importable')" || echo "✗ ERROR: Cannot import village module!"

# Copy entrypoint script
COPY --chown=village:village village_docker/entrypoint.sh /app/

# Note: We do NOT copy the village source code here because it's already
# installed in site-packages from the builder stage. Copying it would create
# conflicts and import errors.

# Make entrypoint executable (scripts should already be executable from builder)
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
