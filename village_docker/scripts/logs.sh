#!/bin/bash
# logs.sh - View logs from the Village Docker container

set -e

# Get the directory where this script is located
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# Note: common.sh parses and strips --instance from $@
source "${SCRIPT_DIR}/common.sh"

# Default options
FOLLOW=false
TAIL_LINES=""
TIMESTAMPS=false
LOGFILE=""

# Parse command line arguments
while [[ $# -gt 0 ]]; do
    case $1 in
        -f|--follow)
            FOLLOW=true
            shift
            ;;
        -n|--tail)
            if [[ -z "$2" ]] || [[ "$2" =~ ^- ]]; then
                error "Option --tail requires a number argument"
                exit 1
            fi
            TAIL_LINES="$2"
            shift 2
            ;;
        -t|--timestamps)
            TIMESTAMPS=true
            shift
            ;;
        --access)
            LOGFILE="access"
            shift
            ;;
        --error)
            LOGFILE="error"
            shift
            ;;
        -h|--help)
            cat << EOF
Village Docker - View Logs

View logs from the Village Docker container for a specific instance.

USAGE:
    $0 --instance <name> [OPTIONS]

OPTIONS:
    --instance NAME       Instance name (required, or set VILLAGE_INSTANCE)
    -f, --follow          Follow log output (like tail -f)
    -n, --tail LINES      Show last N lines (default: all)
    -t, --timestamps      Show timestamps
    --access              View access.log file directly
    --error               View error.log file directly
    -h, --help            Show this help message

EXAMPLES:
    # View all container logs
    $0 --instance mysite

    # Follow logs in real-time
    $0 --instance mysite --follow

    # Show last 50 lines
    $0 --instance mysite --tail 50

    # View access log file directly
    $0 --instance mysite --access

    # View error log file directly
    $0 --instance mysite --error

LOG FILES:
    Container logs:     Combined stdout/stderr from the container
    Access logs:        ${LOGS_DIR}/access.log
    Error logs:         ${LOGS_DIR}/error.log

NOTES:
    - Without --access or --error, shows container logs (stdout/stderr)
    - Access and error logs are written by Gunicorn inside the container
    - Log files persist outside container in ${LOGS_DIR}/
    - Press Ctrl+C to stop following logs

EOF
            exit 0
            ;;
        *)
            error "Unknown option: $1"
            echo "Use --help for usage information"
            exit 1
            ;;
    esac
done

# Check Docker is available
if ! command -v docker &> /dev/null; then
    error "Docker is not installed or not in PATH"
    exit 1
fi

# Check Docker daemon is running
if ! docker info &> /dev/null; then
    error "Docker daemon is not running"
    exit 1
fi

# If viewing log files directly
if [[ -n "$LOGFILE" ]]; then
    if [[ "$LOGFILE" == "access" ]]; then
        LOGPATH="${LOGS_DIR}/access.log"
    elif [[ "$LOGFILE" == "error" ]]; then
        LOGPATH="${LOGS_DIR}/error.log"
    fi

    # Check log file exists
    if [[ ! -f "$LOGPATH" ]]; then
        warn "Log file does not exist yet: $LOGPATH"
        echo ""
        echo "The log file will be created when the container starts."
        echo "Try viewing container logs instead:"
        echo "  $0 --instance ${VILLAGE_INSTANCE}"
        exit 1
    fi

    # Build tail command
    TAIL_CMD="tail"
    if [[ "$FOLLOW" == true ]]; then
        TAIL_CMD="$TAIL_CMD -f"
    fi
    if [[ -n "$TAIL_LINES" ]]; then
        TAIL_CMD="$TAIL_CMD -n $TAIL_LINES"
    fi

    info "Viewing $LOGFILE log (instance: ${VILLAGE_INSTANCE}): $LOGPATH"
    echo ""
    exec $TAIL_CMD "$LOGPATH"
fi

# Viewing container logs
# Check if container exists
if ! docker ps -a --format '{{.Names}}' | grep -q "^${CONTAINER_NAME}$"; then
    error "Container '${CONTAINER_NAME}' does not exist"
    echo ""
    echo "Create and start the container first:"
    echo "  ./scripts/start.sh --instance ${VILLAGE_INSTANCE}"
    exit 1
fi

# Check if container is running
if ! docker ps --format '{{.Names}}' | grep -q "^${CONTAINER_NAME}$"; then
    warn "Container '${CONTAINER_NAME}' is not running"
    echo ""
    echo "Start the container to see live logs:"
    echo "  ./scripts/start.sh --instance ${VILLAGE_INSTANCE}"
    echo ""
    echo "You can still view old logs from the stopped container."
    echo ""
fi

# Build docker logs command
DOCKER_CMD="docker logs"

if [[ "$FOLLOW" == true ]]; then
    DOCKER_CMD="$DOCKER_CMD --follow"
fi

if [[ -n "$TAIL_LINES" ]]; then
    DOCKER_CMD="$DOCKER_CMD --tail $TAIL_LINES"
fi

if [[ "$TIMESTAMPS" == true ]]; then
    DOCKER_CMD="$DOCKER_CMD --timestamps"
fi

DOCKER_CMD="$DOCKER_CMD ${CONTAINER_NAME}"

# Show what we're doing
info "Viewing container logs (instance: ${VILLAGE_INSTANCE})"
if [[ "$FOLLOW" == true ]]; then
    echo "Following logs in real-time. Press Ctrl+C to stop."
fi
echo ""

# Execute the command
exec $DOCKER_CMD
