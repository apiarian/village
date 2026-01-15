#!/bin/bash

# Start the Village Docker container

set -e  # Exit on error

# Get the directory where this script is located
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# Source common configuration and functions
source "$SCRIPT_DIR/common.sh"

# Check if we need to re-execute as the village user
# This is needed because Docker needs to read the config file
if [ "$(id -u)" != "$(get_village_uid)" ] && [ "${RUN_AS_VILLAGE_USER:-}" != "1" ]; then
    # Check if village user exists
    if id "${VILLAGE_USER}" &>/dev/null; then
        debug "Re-executing as ${VILLAGE_USER} user for proper permissions"
        # Re-run this script as the village user
        exec sudo -u "${VILLAGE_USER}" RUN_AS_VILLAGE_USER=1 "$0" "$@"
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
Usage: $(basename "$0") [OPTIONS]

Start the Village Docker container.

OPTIONS:
    -f, --force         Force recreate container even if already running
    -h, --help          Show this help message

DESCRIPTION:
    This script starts the Village application in a Docker container with:
    - Persistent data and logs directories
    - Environment configuration from village.env
    - Port 8000 bound to localhost only
    - Automatic restart policy (unless-stopped)
    
    The container runs as the 'village' user (UID $(get_village_uid)) for security.

EXAMPLES:
    # Normal start
    $(basename "$0")
    
    # Force recreate (useful after config changes)
    $(basename "$0") --force
    
    # View logs after starting
    $(basename "$0") && ./logs.sh

NOTES:
    - Container name: $CONTAINER_NAME
    - Image: $IMAGE_NAME
    - Port: 127.0.0.1:8000:8000 (localhost only)
    - Data: $DATA_DIR
    - Logs: $LOGS_DIR
    - Config: $CONFIG_FILE
    
    If the container already exists and is running, this script will
    notify you and do nothing. Use --force to recreate it.

TROUBLESHOOTING:
    If the container fails to start, check logs:
        ./logs.sh
    
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
    info "Please run setup.sh first, then edit the configuration file"
    exit 1
fi

# Check if required directories exist
if [[ ! -d "$DATA_DIR" ]]; then
    error "Data directory not found: $DATA_DIR"
    info "Please run setup.sh first"
    exit 1
fi

if [[ ! -d "$LOGS_DIR" ]]; then
    error "Logs directory not found: $LOGS_DIR"
    info "Please run setup.sh first"
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
            info "To view logs: ./logs.sh"
            info "To restart: docker restart $CONTAINER_NAME"
            info "To force recreate: $(basename "$0") --force"
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
            info "View logs: ./logs.sh"
            exit 0
        fi
    fi
fi

# Start new container
info "Starting Village container..."
info "Configuration:"
info "  Container: $CONTAINER_NAME"
info "  Image: $IMAGE_NAME"
info "  Port: 127.0.0.1:8000:8000 (localhost only)"
info "  Data: $DATA_DIR"
info "  Logs: $LOGS_DIR"
info "  Config: $CONFIG_FILE"
info ""

# Run the container
docker run -d \
    --name "$CONTAINER_NAME" \
    --restart unless-stopped \
    -p 127.0.0.1:8000:8000 \
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
    info "  View logs:        ./logs.sh"
    info "  Check health:     docker inspect $CONTAINER_NAME | grep -A 10 Health"
    info "  Stop container:   ./stop.sh"
    info "  Open shell:       ./shell.sh"
    info ""
    info "Access the application at: http://localhost:8000"
else
    error "Container failed to start!"
    info "Check logs with: docker logs $CONTAINER_NAME"
    exit 1
fi
