#!/bin/sh
set -e

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

# Helper functions
log_info() {
    echo "${GREEN}[INFO]${NC} $1"
}

log_warn() {
    echo "${YELLOW}[WARN]${NC} $1"
}

log_error() {
    echo "${RED}[ERROR]${NC} $1"
}

fail() {
    log_error "$1"
    exit 1
}

# 1. Validate required environment variables
log_info "Validating environment variables..."

# Check if config has been reviewed
if [ ! -z "$CONFIG_NOT_REVIEWED" ]; then
    fail "Configuration file has not been reviewed! 
    
    You must edit /opt/village/config/village.env and:
    1. Delete or comment out the CONFIG_NOT_REVIEWED line
    2. Set FLASK_SECRET_KEY to a secure random value
    
    Generate a key with: python3 -c \"import secrets; print(secrets.token_hex(32))\""
fi

if [ -z "$FLASK_SECRET_KEY" ]; then
    fail "FLASK_SECRET_KEY is not set. Please set it in village.env"
fi

# Check for default/unsafe values
if [ "$FLASK_SECRET_KEY" = "CHANGE_ME" ]; then
    fail "FLASK_SECRET_KEY is still set to default value 'CHANGE_ME'. Please generate a secure random key."
fi

if [ ${#FLASK_SECRET_KEY} -lt 32 ]; then
    fail "FLASK_SECRET_KEY must be at least 32 characters long (current length: ${#FLASK_SECRET_KEY})"
fi

if [ -z "$FLASK_ENV" ]; then
    log_warn "FLASK_ENV is not set, defaulting to 'production'"
    export FLASK_ENV=production
fi

# Set defaults for Gunicorn configuration
export BIND_ADDRESS="${BIND_ADDRESS:-0.0.0.0:8000}"
export WORKERS="${WORKERS:-4}"
export WORKER_CLASS="${WORKER_CLASS:-gevent}"
export WORKER_CONNECTIONS="${WORKER_CONNECTIONS:-1000}"
export MAX_REQUESTS="${MAX_REQUESTS:-1000}"
export MAX_REQUESTS_JITTER="${MAX_REQUESTS_JITTER:-50}"
export TIMEOUT="${TIMEOUT:-30}"
export LOG_LEVEL="${LOG_LEVEL:-info}"

# 2. Set and validate data directory
export VILLAGE_REPOSITORY="${VILLAGE_REPOSITORY:-/opt/village/data}"

log_info "Checking data directory: $VILLAGE_REPOSITORY"

if [ ! -d "$VILLAGE_REPOSITORY" ]; then
    fail "Data directory does not exist: $VILLAGE_REPOSITORY. Please ensure volume is mounted."
fi

# Test if directory is writable
if [ ! -w "$VILLAGE_REPOSITORY" ]; then
    fail "Data directory is not writable: $VILLAGE_REPOSITORY. Check permissions (should be owned by UID 1000)."
fi

# 3. Verify repository is initialized
log_info "Checking if Village repository is initialized..."

if [ ! -f "$VILLAGE_REPOSITORY/settings.yaml" ]; then
    fail "Village repository not initialized. Please run: ./scripts/run-script.sh initialize-repository"
fi

log_info "Repository validation successful"

# 4. Ensure logs directory exists and is writable
LOGS_DIR="${LOGS_DIR:-/opt/village/logs}"
log_info "Checking logs directory: $LOGS_DIR"

if [ ! -d "$LOGS_DIR" ]; then
    fail "Logs directory does not exist: $LOGS_DIR. Please ensure volume is mounted."
fi

if [ ! -w "$LOGS_DIR" ]; then
    fail "Logs directory is not writable: $LOGS_DIR. Check permissions (should be owned by UID 1000)."
fi

# 5. Start Gunicorn
log_info "Starting Gunicorn with configuration:"
log_info "  Bind: $BIND_ADDRESS"
log_info "  Workers: $WORKERS"
log_info "  Worker Class: $WORKER_CLASS"
log_info "  Worker Connections: $WORKER_CONNECTIONS"
log_info "  Max Requests: $MAX_REQUESTS"
log_info "  Max Requests Jitter: $MAX_REQUESTS_JITTER"
log_info "  Timeout: $TIMEOUT"
log_info "  Log Level: $LOG_LEVEL"
log_info "  Data Directory: $VILLAGE_REPOSITORY"
log_info ""

exec poetry run gunicorn \
    --bind "$BIND_ADDRESS" \
    --workers "$WORKERS" \
    --worker-class "$WORKER_CLASS" \
    --worker-connections "$WORKER_CONNECTIONS" \
    --max-requests "$MAX_REQUESTS" \
    --max-requests-jitter "$MAX_REQUESTS_JITTER" \
    --timeout "$TIMEOUT" \
    --log-level "$LOG_LEVEL" \
    --access-logfile "$LOGS_DIR/access.log" \
    --error-logfile "$LOGS_DIR/error.log" \
    "village.app:app"
