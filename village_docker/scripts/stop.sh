#!/bin/bash
# stop.sh - Stop the Village Docker container
#
# Usage: ./stop.sh --instance <name> [OPTIONS]
#
# Options:
#   --instance NAME  Instance name (required, or set VILLAGE_INSTANCE)
#   --timeout N      Wait N seconds for graceful shutdown (default: 10)
#   --force          Force kill if graceful stop fails
#   --remove         Remove the container after stopping
#   --help           Show this help message
#
# Examples:
#   ./stop.sh --instance mysite                    # Graceful stop with 10 second timeout
#   ./stop.sh --instance mysite --timeout 30       # Graceful stop with 30 second timeout
#   ./stop.sh --instance mysite --force            # Force stop if graceful fails
#   ./stop.sh --instance mysite --remove           # Stop and remove container
#   ./stop.sh --instance mysite --force --remove   # Force stop and remove
#
# Exit codes:
#   0 - Success
#   1 - Error (Docker not available, container doesn't exist, etc.)
#   2 - Container still running after stop attempt

set -e

# Get the directory where this script is located
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# Source common configuration and functions
# Note: common.sh parses and strips --instance from $@
source "$SCRIPT_DIR/common.sh"

# Default options
TIMEOUT=10
FORCE=false
REMOVE=false

# Parse command line arguments
while [[ $# -gt 0 ]]; do
    case $1 in
        --timeout)
            TIMEOUT="$2"
            if ! [[ "$TIMEOUT" =~ ^[0-9]+$ ]]; then
                error "Timeout must be a positive integer"
                exit 1
            fi
            shift 2
            ;;
        --force)
            FORCE=true
            shift
            ;;
        --remove)
            REMOVE=true
            shift
            ;;
        --help)
            grep '^#' "$0" | tail -n +2 | head -n -1 | cut -c 3-
            exit 0
            ;;
        *)
            error "Unknown option: $1"
            echo "Use --help for usage information"
            exit 1
            ;;
    esac
done

# Validate Docker is available
if ! command -v docker &> /dev/null; then
    error "Docker is not installed or not in PATH"
    exit 1
fi

if ! docker info &> /dev/null; then
    error "Docker daemon is not running or you don't have permission to access it"
    exit 1
fi

# Check if container exists
if ! docker ps -a --format '{{.Names}}' | grep -q "^${CONTAINER_NAME}$"; then
    warn "Container '$CONTAINER_NAME' does not exist"
    exit 0
fi

# Check if container is running
if ! docker ps --format '{{.Names}}' | grep -q "^${CONTAINER_NAME}$"; then
    warn "Container '$CONTAINER_NAME' is not running"
    if $REMOVE; then
        info "Removing stopped container..."
        docker rm "$CONTAINER_NAME"
        info "Container removed"
    fi
    exit 0
fi

# Stop the container
info "Stopping container '$CONTAINER_NAME' (instance: ${VILLAGE_INSTANCE}, timeout: ${TIMEOUT}s)..."
if docker stop --time "$TIMEOUT" "$CONTAINER_NAME" &> /dev/null; then
    info "Container stopped successfully"
else
    if $FORCE; then
        warn "Graceful stop failed, force killing container..."
        if docker kill "$CONTAINER_NAME" &> /dev/null; then
            info "Container killed"
        else
            error "Failed to kill container"
            exit 1
        fi
    else
        error "Failed to stop container gracefully"
        error "Use --force to force kill, or increase --timeout"
        exit 1
    fi
fi

# Verify container is stopped
if docker ps --format '{{.Names}}' | grep -q "^${CONTAINER_NAME}$"; then
    error "Container is still running after stop attempt"
    exit 2
fi

# Remove container if requested
if $REMOVE; then
    info "Removing container..."
    if docker rm "$CONTAINER_NAME" &> /dev/null; then
        info "Container removed"
    else
        error "Failed to remove container"
        exit 1
    fi
fi

# Show final status
info "Status: Container stopped"
if $REMOVE; then
    info "Container has been removed"
else
    info "Container still exists (use 'docker start $CONTAINER_NAME' to restart)"
    info "Or use 'docker rm $CONTAINER_NAME' to remove"
fi
