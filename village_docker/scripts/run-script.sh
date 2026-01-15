#!/bin/bash
# Run any poetry script defined in pyproject.toml

set -e

# Get directory of this script
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${SCRIPT_DIR}/common.sh"

# Check if we need to re-execute as the village user
# This is needed because Docker needs to read the config file and access directories
# that are owned by the village user
if [ "$(id -u)" != "$(get_village_uid)" ] && [ "${RUN_AS_VILLAGE_USER:-}" != "1" ]; then
    # Check if village user exists
    if id "${VILLAGE_USER}" &>/dev/null; then
        debug "Re-executing as ${VILLAGE_USER} user for proper permissions"
        # Re-run this script as the village user
        # Pass all original arguments and set marker to prevent infinite loop
        exec sudo -u "${VILLAGE_USER}" RUN_AS_VILLAGE_USER=1 "$0" "$@"
    else
        warn "Village user '${VILLAGE_USER}' does not exist"
        warn "This may cause permission issues. Consider running setup.sh first."
    fi
fi

# Help documentation
show_help() {
    cat << EOF
${BOLD}Village Docker - Run Poetry Script${RESET}

Runs any poetry script defined in pyproject.toml inside a container.

${BOLD}Usage:${RESET}
    $(basename "$0") <script-name> [args...]
    $(basename "$0") --help

${BOLD}Arguments:${RESET}
    script-name     Name of the poetry script to run (required)
    args            Optional arguments to pass to the script

${BOLD}Common Scripts:${RESET}
    initialize-repository    Initialize a new Village repository
    create-user              Create a new user account
    force-reset-password     Reset a user's password
    update-thumbnail         Update thumbnail for a post

${BOLD}How It Works:${RESET}
    - Automatically re-executes as ${VILLAGE_USER} user if needed (for permissions)
    - Runs a one-off container with the same volumes and environment
    - Executes 'poetry run <script-name>' inside the container
    - Container is removed after script completes (--rm flag)
    - Interactive mode (-it) for scripts that need user input

${BOLD}Examples:${RESET}
    # Initialize a new repository
    $(basename "$0") initialize-repository

    # Create a new user
    $(basename "$0") create-user

    # Reset a user's password
    $(basename "$0") force-reset-password username

    # Update a thumbnail
    $(basename "$0") update-thumbnail post-id

    # Run custom script with arguments
    $(basename "$0") my-script --arg1 value1

${BOLD}Requirements:${RESET}
    - Docker image must be built (run build.sh first)
    - Configuration file must exist: ${CONFIG_FILE}
    - Data and logs directories must exist
    - Script must be defined in pyproject.toml [tool.poetry.scripts]

${BOLD}Notes:${RESET}
    - Works even when main container isn't running
    - Uses same environment as main container
    - Changes persist to the data directory
    - Use shell.sh for interactive shell access

${BOLD}Troubleshooting:${RESET}
    - "Script not found": Check pyproject.toml for available scripts
    - "Permission denied": Ensure data directory has correct ownership
    - "Image not found": Run build.sh first
    - "Config not found": Run setup.sh first

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

info "Running poetry script: ${SCRIPT_NAME}"

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
    info "Run setup.sh first to create the configuration file"
    exit 1
fi

# Check if data directory exists
if [ ! -d "${DATA_DIR}" ]; then
    error "Data directory not found: ${DATA_DIR}"
    info "Run setup.sh first to create the data directory"
    exit 1
fi

# Check if logs directory exists
if [ ! -d "${LOGS_DIR}" ]; then
    error "Logs directory not found: ${LOGS_DIR}"
    info "Run setup.sh first to create the logs directory"
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
    --rm                                    # Remove container after it exits
    -it                                     # Interactive terminal
    --name "${CONTAINER_NAME}-script"       # Unique name for script container
    -v "${DATA_DIR}:/opt/village/data"      # Mount data directory
    -v "${LOGS_DIR}:/opt/village/logs"      # Mount logs directory
    --env-file "${CONFIG_FILE}"             # Load environment variables
    "${IMAGE_NAME}"                         # Image to use
    poetry run "${SCRIPT_NAME}"             # Command to run
)

# Add script arguments if any
if [ ${#SCRIPT_ARGS[@]} -gt 0 ]; then
    DOCKER_CMD+=("${SCRIPT_ARGS[@]}")
fi

debug "Docker command: ${DOCKER_CMD[*]}"

# Run the script
info "Executing: poetry run ${SCRIPT_NAME} ${SCRIPT_ARGS[*]}"
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
