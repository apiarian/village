#!/bin/bash
# Run any poetry script defined in pyproject.toml

set -e

# Get directory of this script
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

# Help documentation
show_help() {
    cat << EOF
Village Docker - Run Poetry Script

Runs any poetry script defined in pyproject.toml inside a container.

Usage:
    $(basename "$0") --instance <name> <script-name> [args...]
    $(basename "$0") --help

Arguments:
    --instance NAME     Instance name (required, or set VILLAGE_INSTANCE)
    script-name         Name of the poetry script to run (required)
    args                Optional arguments to pass to the script

Common Scripts:
    initialize-repository    Initialize a new Village repository
    create-user              Create a new user account
    force-reset-password     Reset a user's password
    update-thumbnail         Update thumbnail for a post

Examples:
    # Initialize a new repository
    $(basename "$0") --instance mysite initialize-repository

    # Create a new user
    $(basename "$0") --instance mysite create-user

    # Reset a user's password
    $(basename "$0") --instance mysite force-reset-password username

Notes:
    - Works even when main container isn't running
    - Uses same environment as main container
    - Changes persist to the data directory
    - Use shell.sh for interactive shell access

EOF
}

# Parse arguments
if [ $# -eq 0 ] || [ "$1" = "--help" ] || [ "$1" = "-h" ]; then
    show_help
    exit 0
fi

SCRIPT_NAME="$1"
shift  # Remove script name from arguments
SCRIPT_ARGS=("$@")  # Remaining arguments

info "Running poetry script: ${SCRIPT_NAME} (instance: ${VILLAGE_INSTANCE})"

# Validate Docker is available
if ! command -v docker &> /dev/null; then
    error "Docker is not installed or not in PATH"
    exit 1
fi

# Check if Docker daemon is running
if ! docker info &> /dev/null; then
    error "Docker daemon is not running"
    exit 1
fi

# Check if config file exists
if [ ! -f "${CONFIG_FILE}" ]; then
    error "Configuration file not found: ${CONFIG_FILE}"
    info "Run setup.sh --instance ${VILLAGE_INSTANCE} first to create the configuration file"
    exit 1
fi

# Check if data directory exists
if [ ! -d "${DATA_DIR}" ]; then
    error "Data directory not found: ${DATA_DIR}"
    info "Run setup.sh --instance ${VILLAGE_INSTANCE} first to create the data directory"
    exit 1
fi

# Check if logs directory exists
if [ ! -d "${LOGS_DIR}" ]; then
    error "Logs directory not found: ${LOGS_DIR}"
    info "Run setup.sh --instance ${VILLAGE_INSTANCE} first to create the logs directory"
    exit 1
fi

# Check if Docker image exists
if ! docker image inspect "${IMAGE_NAME}" &> /dev/null; then
    error "Docker image not found: ${IMAGE_NAME}"
    info "Run build.sh first to build the Docker image"
    exit 1
fi

# Build docker run command
DOCKER_CMD=(
    docker run
    --rm                                            # Remove container after it exits
    -it                                             # Interactive terminal
    --name "${CONTAINER_NAME}-script"               # Unique name for script container
    -v "${DATA_DIR}:/opt/village/data"              # Mount data directory
    -v "${LOGS_DIR}:/opt/village/logs"              # Mount logs directory
    --env-file "${CONFIG_FILE}"                     # Load environment variables
    "${IMAGE_NAME}"                                 # Image to use
    "${SCRIPT_NAME}"                                # Command to run (scripts are installed)
)

# Add script arguments if any
if [ ${#SCRIPT_ARGS[@]} -gt 0 ]; then
    DOCKER_CMD+=("${SCRIPT_ARGS[@]}")
fi

debug "Docker command: ${DOCKER_CMD[*]}"

# Run the script
info "Executing: ${SCRIPT_NAME} ${SCRIPT_ARGS[*]}"
echo ""

# Run and capture exit code
set +e
"${DOCKER_CMD[@]}"
EXIT_CODE=$?
set -e

echo ""

# Check exit code
if [ $EXIT_CODE -eq 0 ]; then
    info "Script completed successfully"
else
    error "Script exited with code: ${EXIT_CODE}"
    exit $EXIT_CODE
fi
