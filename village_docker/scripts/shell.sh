#!/bin/bash
# shell.sh - Open an interactive shell in the Village Docker container
# Usage: ./shell.sh --instance <name> [--command "command to run"]

set -e

# Source common configuration
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# Note: common.sh parses and strips --instance from $@
source "${SCRIPT_DIR}/common.sh"

# Check if we need to sync to deployment location and re-execute as village user
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

# Help text
show_help() {
    cat << EOF
Usage: $(basename "$0") --instance <name> [OPTIONS]

Open an interactive shell in the Village Docker container.

Options:
    --instance NAME       Instance name (required, or set VILLAGE_INSTANCE)
    -c, --command "cmd"   Run a command instead of opening interactive shell
    -h, --help            Show this help message

Examples:
    # Open interactive bash shell
    $(basename "$0") --instance mysite

    # Run a single command
    $(basename "$0") --instance mysite --command "ls -la /opt/village/data"

    # Check Python environment
    $(basename "$0") --instance mysite --command "poetry run python --version"

Notes:
    - Opens a shell as the village user (not root)
    - Has access to the same volumes as the running container (data, logs)
    - Environment variables from village.env are loaded
    - Working directory is /app (where the application code is)
    - For running poetry scripts, use run-script.sh instead

EOF
}

# Parse arguments
COMMAND=""

while [[ $# -gt 0 ]]; do
    case $1 in
        -c|--command)
            COMMAND="$2"
            shift 2
            ;;
        -h|--help)
            show_help
            exit 0
            ;;
        *)
            error "Unknown option: $1"
            echo ""
            show_help
            exit 1
            ;;
    esac
done

# Check if Docker is available
if ! command -v docker &> /dev/null; then
    error "Docker is not installed or not in PATH"
    exit 1
fi

# Check if Docker daemon is running
if ! docker info &> /dev/null; then
    error "Docker daemon is not running"
    exit 1
fi

# Check if container exists
if ! docker ps -a --format '{{.Names}}' | grep -q "^${CONTAINER_NAME}$"; then
    error "Container '${CONTAINER_NAME}' does not exist"
    error "Create it first by running: ./scripts/start.sh --instance ${VILLAGE_INSTANCE}"
    exit 1
fi

# Check if config file exists
ENV_FILE="${CONFIG_DIR}/village.env"
if [[ ! -f "${ENV_FILE}" ]]; then
    error "Configuration file not found: ${ENV_FILE}"
    error "Run setup.sh --instance ${VILLAGE_INSTANCE} first or create the configuration file"
    exit 1
fi

# Check if the image exists
if ! docker images --format '{{.Repository}}:{{.Tag}}' | grep -q "^${IMAGE_NAME}$"; then
    error "Docker image '${IMAGE_NAME}' not found"
    error "Build it first by running: ./scripts/build.sh"
    exit 1
fi

# Determine if we should exec into running container or start a new one
CONTAINER_RUNNING=$(docker inspect -f '{{.State.Running}}' "${CONTAINER_NAME}" 2>/dev/null || echo "false")

if [[ "${CONTAINER_RUNNING}" == "true" ]]; then
    # Container is running - exec into it
    info "Container is running (instance: ${VILLAGE_INSTANCE}). Opening shell in running container..."
    
    if [[ -n "${COMMAND}" ]]; then
        info "Running command: ${COMMAND}"
        docker exec -it "${CONTAINER_NAME}" /bin/sh -c "${COMMAND}"
    else
        info "Type 'exit' to close the shell and return to host"
        docker exec -it "${CONTAINER_NAME}" /bin/sh
    fi
else
    # Container is not running - start a new temporary container
    warn "Container is not running. Starting a temporary container for shell access..."
    
    # Build docker run command
    DOCKER_CMD="docker run --rm -it \
        --name ${CONTAINER_NAME}-shell \
        -v ${DATA_DIR}:/opt/village/data \
        -v ${LOGS_DIR}:/opt/village/logs \
        --env-file ${ENV_FILE} \
        ${IMAGE_NAME}"
    
    if [[ -n "${COMMAND}" ]]; then
        info "Running command: ${COMMAND}"
        eval "${DOCKER_CMD} /bin/sh -c \"${COMMAND}\""
    else
        info "Starting temporary container with shell..."
        info "Type 'exit' to close the shell. The container will be removed automatically."
        eval "${DOCKER_CMD} /bin/sh"
    fi
fi

# Success message (only shown for commands, not interactive shells)
if [[ -n "${COMMAND}" ]]; then
    info "Command completed successfully"
fi
