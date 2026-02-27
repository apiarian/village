#!/bin/bash

# Start the Village Docker container

set -e  # Exit on error

# Get the directory where this script is located
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# Source common configuration and functions
# Note: common.sh parses and strips --instance from $@
source "$SCRIPT_DIR/common.sh"

# Check if we need to sync to deployment location and re-execute as village user
# This is needed because:
# 1. Docker needs to read the config file (owned by village user)
# 2. Village user shouldn't have access to user home directories
# 3. We want to run from /opt/village/village (the deployment location)
if [ "$(id -u)" != "$(get_village_uid)" ] && [ "${RUN_AS_VILLAGE_USER:-}" != "1" ]; then
    # Check if village user exists
    if id "${VILLAGE_USER}" &>/dev/null; then
        # Check if we're running from the deployment location already
        CURRENT_SCRIPT="$(cd "$(dirname "$0")" && pwd)/$(basename "$0")"
        DEPLOYMENT_SCRIPT="${REPO_DIR}/village_docker/scripts/$(basename "$0")"
        
        if [ "$CURRENT_SCRIPT" != "$DEPLOYMENT_SCRIPT" ]; then
            # We're running from somewhere else (like ~/village), need to sync
            info "Syncing to deployment location: ${REPO_DIR}"
            
            # Check if deployment repo exists
            if [ ! -d "${REPO_DIR}/.git" ]; then
                error "Deployment repository not found at ${REPO_DIR}"
                error "Please run setup.sh first: sudo ./scripts/setup.sh --instance ${VILLAGE_INSTANCE}"
                exit 1
            fi
            
            # Pull latest changes to deployment location
            info "Pulling latest changes..."
            (cd "${REPO_DIR}" && sudo -u "${VILLAGE_USER}" git pull) || {
                warn "Git pull failed, continuing with existing code"
            }
            
            # Now exec the deployment script as village user
            info "Executing from deployment location as ${VILLAGE_USER} user"
            exec sudo -u "${VILLAGE_USER}" RUN_AS_VILLAGE_USER=1 VILLAGE_INSTANCE="${VILLAGE_INSTANCE}" "${DEPLOYMENT_SCRIPT}" "$@"
        else
            # We're already at deployment location, just need to run as village user
            debug "Re-executing as ${VILLAGE_USER} user for proper permissions"
            exec sudo -u "${VILLAGE_USER}" RUN_AS_VILLAGE_USER=1 VILLAGE_INSTANCE="${VILLAGE_INSTANCE}" "$0" "$@"
        fi
    else
        warn "Village user '${VILLAGE_USER}' does not exist"
        warn "This may cause permission issues. Consider running setup.sh first."
    fi
fi

# Parse command line arguments
FORCE_RECREATE=false
HELP=false

while [[ $# -gt 0 ]]; do
    case $1 in
        --force|-f)
            FORCE_RECREATE=true
            shift
            ;;
        --help|-h)
            HELP=true
            shift
            ;;
        *)
            error "Unknown option: $1"
            HELP=true
            shift
            ;;
    esac
done

if [[ "$HELP" == "true" ]]; then
    cat << EOF
Usage: $(basename "$0") --instance <name> [OPTIONS]

Start the Village Docker container for a specific instance.

OPTIONS:
    --instance NAME     Instance name (required, or set VILLAGE_INSTANCE)
    -f, --force         Force recreate container even if already running
    -h, --help          Show this help message

DESCRIPTION:
    This script starts the Village application in a Docker container with:
    - Persistent data and logs directories
    - Environment configuration from village.env
    - Host port from HOST_PORT in village.env (bound to localhost only)
    - Automatic restart policy (unless-stopped)
    
    The container runs as the 'village' user (UID $(get_village_uid)) for security.

EXAMPLES:
    # Normal start
    $(basename "$0") --instance mysite
    
    # Force recreate (useful after config changes)
    $(basename "$0") --instance mysite --force

NOTES:
    - Container name: $CONTAINER_NAME
    - Image: $IMAGE_NAME
    - Data: $DATA_DIR
    - Logs: $LOGS_DIR
    - Config: $CONFIG_FILE

TROUBLESHOOTING:
    If the container fails to start, check logs:
        ./logs.sh --instance ${VILLAGE_INSTANCE}
    
    Or view Docker logs directly:
        docker logs $CONTAINER_NAME

EOF
    exit 0
fi

# Check if Docker is available
if ! command -v docker &> /dev/null; then
    error "Docker is not installed or not in PATH"
    exit 1
fi

# Check if config file exists
if [[ ! -f "$CONFIG_FILE" ]]; then
    error "Configuration file not found: $CONFIG_FILE"
    info "Please run setup.sh --instance ${VILLAGE_INSTANCE} first, then edit the configuration file"
    exit 1
fi

# Read HOST_PORT from config
HOST_PORT=$(get_host_port)
if [[ -z "$HOST_PORT" ]]; then
    error "HOST_PORT is not set in $CONFIG_FILE"
    error "Each instance must define a unique HOST_PORT in its village.env"
    exit 1
fi

# Validate HOST_PORT is numeric
if ! [[ "$HOST_PORT" =~ ^[0-9]+$ ]]; then
    error "HOST_PORT must be numeric, got: $HOST_PORT"
    exit 1
fi

# Check if required directories exist
if [[ ! -d "$DATA_DIR" ]]; then
    error "Data directory not found: $DATA_DIR"
    info "Please run setup.sh --instance ${VILLAGE_INSTANCE} first"
    exit 1
fi

if [[ ! -d "$LOGS_DIR" ]]; then
    error "Logs directory not found: $LOGS_DIR"
    info "Please run setup.sh --instance ${VILLAGE_INSTANCE} first"
    exit 1
fi

# Check if image exists
if ! docker image inspect "$IMAGE_NAME" &> /dev/null; then
    error "Docker image not found: $IMAGE_NAME"
    info "Please run build.sh first to build the image"
    exit 1
fi

# Check if container already exists
if docker ps -a --format '{{.Names}}' | grep -q "^${CONTAINER_NAME}$"; then
    # Container exists - check if running
    if docker ps --format '{{.Names}}' | grep -q "^${CONTAINER_NAME}$"; then
        if [[ "$FORCE_RECREATE" == "true" ]]; then
            info "Stopping and removing existing container..."
            docker stop "$CONTAINER_NAME" &> /dev/null || true
            docker rm "$CONTAINER_NAME" &> /dev/null || true
        else
            warn "Container is already running"
            info "Container status:"
            docker ps --filter "name=^${CONTAINER_NAME}$" --format "table {{.Names}}\t{{.Status}}\t{{.Ports}}"
            info ""
            info "To view logs: ./logs.sh --instance ${VILLAGE_INSTANCE}"
            info "To restart: docker restart $CONTAINER_NAME"
            info "To force recreate: $(basename "$0") --instance ${VILLAGE_INSTANCE} --force"
            exit 0
        fi
    else
        # Container exists but not running
        if [[ "$FORCE_RECREATE" == "true" ]]; then
            info "Removing existing stopped container..."
            docker rm "$CONTAINER_NAME" &> /dev/null || true
        else
            info "Starting existing container..."
            docker start "$CONTAINER_NAME"
            info "Container started successfully"
            info "View logs: ./logs.sh --instance ${VILLAGE_INSTANCE}"
            exit 0
        fi
    fi
fi

# Start new container
info "Starting Village container (instance: ${VILLAGE_INSTANCE})..."
info "Configuration:"
info "  Container: $CONTAINER_NAME"
info "  Image: $IMAGE_NAME"
info "  Port: 127.0.0.1:${HOST_PORT}:8000 (localhost only)"
info "  Data: $DATA_DIR"
info "  Logs: $LOGS_DIR"
info "  Config: $CONFIG_FILE"
info ""

# Run the container
docker run -d \
    --name "$CONTAINER_NAME" \
    --restart unless-stopped \
    -p "127.0.0.1:${HOST_PORT}:8000" \
    -v "$DATA_DIR:/opt/village/data" \
    -v "$LOGS_DIR:/opt/village/logs" \
    --env-file "$CONFIG_FILE" \
    "$IMAGE_NAME"

# Wait a moment for container to start
sleep 2

# Check if container is running
if docker ps --format '{{.Names}}' | grep -q "^${CONTAINER_NAME}$"; then
    info "Container started successfully!"
    info ""
    info "Status:"
    docker ps --filter "name=^${CONTAINER_NAME}$" --format "table {{.Names}}\t{{.Status}}\t{{.Ports}}"
    info ""
    info "Next steps:"
    info "  View logs:        ./logs.sh --instance ${VILLAGE_INSTANCE}"
    info "  Check health:     docker inspect $CONTAINER_NAME | grep -A 10 Health"
    info "  Stop container:   ./stop.sh --instance ${VILLAGE_INSTANCE}"
    info "  Open shell:       ./shell.sh --instance ${VILLAGE_INSTANCE}"
    info ""
    info "Access the application at: http://localhost:${HOST_PORT}"
else
    error "Container failed to start!"
    info "Check logs with: docker logs $CONTAINER_NAME"
    exit 1
fi
