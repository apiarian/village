#!/usr/bin/env bash
#
# deploy.sh - Deploy Village Docker (update code, rebuild, restart)
#
# This script automates the deployment process:
# 1. Pull latest code from git (in deployment location: /opt/village/village)
# 2. Rebuild Docker image (from deployment location)
# 3. Restart container(s) via systemd (or direct Docker if systemd not available)
#
# The pull and build always happen (they're idempotent). Only the restart
# targets a specific instance or all instances.
#
# Usage:
#   ./deploy.sh --instance <name> [options]
#   ./deploy.sh --all [options]
#
# Options:
#   --instance NAME Deploy a specific instance
#   --all           Deploy all instances (restart each after shared pull+build)
#   --no-pull       Skip git pull (only rebuild and restart)
#   --no-build      Skip rebuild (only pull and restart with existing image)
#   --force         Force recreate container even if image didn't change
#   --branch NAME   Switch to a different branch before pulling
#   --help          Show this help message
#
# Examples:
#   ./deploy.sh --instance mysite          # Full deploy: pull, build, restart mysite
#   ./deploy.sh --all                      # Full deploy: pull, build, restart all
#   ./deploy.sh --instance mysite --force  # Force recreate even if no changes
#   ./deploy.sh --all --no-pull            # Only rebuild and restart all
#
# Exit codes:
#   0 - Success
#   1 - Error (git pull failed, build failed, etc.)
#

set -e  # Exit on error

# Parse --instance and --all before sourcing common.sh because common.sh
# requires VILLAGE_INSTANCE. For --all mode we skip the requirement.
DEPLOY_ALL=false
_deploy_args=()
for arg in "$@"; do
    if [[ "$arg" == "--all" ]]; then
        DEPLOY_ALL=true
    else
        _deploy_args+=("$arg")
    fi
done

if [[ "$DEPLOY_ALL" == "true" ]]; then
    export VILLAGE_SKIP_INSTANCE_REQUIRE=1
    export VILLAGE_SKIP_INSTANCE_PARSE=1
fi

# Get script directory and source common functions
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${SCRIPT_DIR}/common.sh"

# Parse command line options
SKIP_PULL=false
SKIP_BUILD=false
FORCE=false
BRANCH=""

# Use _deploy_args if --all mode, otherwise use $@ (already filtered by common.sh)
if [[ "$DEPLOY_ALL" == "true" ]]; then
    set -- "${_deploy_args[@]+"${_deploy_args[@]}"}"
fi

while [[ $# -gt 0 ]]; do
    case $1 in
        --no-pull)
            SKIP_PULL=true
            shift
            ;;
        --no-build)
            SKIP_BUILD=true
            shift
            ;;
        --force)
            FORCE=true
            shift
            ;;
        --branch)
            BRANCH="$2"
            shift 2
            ;;
        --help)
            grep '^#' "$0" | grep -v '#!/usr/bin/env' | sed 's/^# //; s/^#//'
            exit 0
            ;;
        *)
            error "Unknown option: $1"
            echo ""
            echo "Run './deploy.sh --help' for usage information"
            exit 1
            ;;
    esac
done

# Validate: must have --instance or --all
if [[ "$DEPLOY_ALL" == "false" ]] && [[ -z "${VILLAGE_INSTANCE:-}" ]]; then
    error "Either --instance <name> or --all is required"
    echo ""
    echo "Run './deploy.sh --help' for usage information"
    exit 1
fi

# Check Docker is available
if ! command -v docker &> /dev/null; then
    error "Docker is not installed"
    echo "Install Docker first: sudo dnf install docker && sudo systemctl start docker"
    exit 1
fi

if ! docker info &> /dev/null; then
    error "Docker daemon is not running"
    echo "Start Docker: sudo systemctl start docker"
    exit 1
fi

# Validate we're in a git repository
if [[ ! -d "${REPO_DIR}/.git" ]]; then
    error "Not a git repository: ${REPO_DIR}"
    echo "This script must be run from a git-managed Village deployment"
    exit 1
fi

info "===== Village Docker Deployment ====="
echo ""
info "Deployment repository: ${REPO_DIR}"
if [[ "${SCRIPT_REPO}" != "${REPO_DIR}" ]]; then
    info "Script location: ${SCRIPT_REPO} (deploying to ${REPO_DIR})"
fi
if [[ "$DEPLOY_ALL" == "true" ]]; then
    info "Target: ALL instances"
else
    info "Target instance: ${VILLAGE_INSTANCE}"
fi
echo ""

# Step 1: Git pull (unless skipped)
if [[ "$SKIP_PULL" == "false" ]]; then
    info "Step 1: Updating code from git..."
    
    cd "${REPO_DIR}"
    
    # Determine if we need to run git commands as village user
    CURRENT_UID=$(id -u)
    VILLAGE_UID=$(get_village_uid)
    REPO_OWNER_UID=$(stat -c '%u' "${REPO_DIR}")
    
    # Helper function to run git commands
    run_git() {
        if [[ "$CURRENT_UID" == "$REPO_OWNER_UID" ]]; then
            git "$@"
        elif [[ "$REPO_OWNER_UID" == "$VILLAGE_UID" ]] && id "${VILLAGE_USER}" &>/dev/null; then
            sudo -u "${VILLAGE_USER}" git "$@"
        else
            git config --global --add safe.directory "${REPO_DIR}" 2>/dev/null || true
            git "$@"
        fi
    }
    
    # Switch branch if requested
    if [[ -n "$BRANCH" ]]; then
        info "Switching to branch: ${BRANCH}"
        if ! run_git checkout "$BRANCH"; then
            error "Failed to switch to branch: ${BRANCH}"
            exit 1
        fi
    fi
    
    # Get current commit before pull
    COMMIT_BEFORE=$(run_git rev-parse HEAD)
    
    # Pull latest code
    info "Pulling latest code..."
    if ! run_git pull; then
        error "Git pull failed"
        echo ""
        echo "You may need to:"
        echo "  1. Commit or stash local changes"
        echo "  2. Resolve merge conflicts"
        echo "  3. Check network connectivity"
        exit 1
    fi
    
    # Get current commit after pull
    COMMIT_AFTER=$(run_git rev-parse HEAD)
    
    # Check if anything changed
    if [[ "$COMMIT_BEFORE" == "$COMMIT_AFTER" ]]; then
        info "No changes (already up to date)"
        CODE_CHANGED=false
    else
        info "Code updated: ${COMMIT_BEFORE:0:8} → ${COMMIT_AFTER:0:8}"
        CODE_CHANGED=true
        
        echo ""
        info "Changes:"
        run_git log --oneline --no-decorate "${COMMIT_BEFORE}..${COMMIT_AFTER}" | sed 's/^/  /'
        echo ""
    fi
else
    info "Step 1: Skipping git pull (--no-pull)"
    CODE_CHANGED=false
fi

# Step 2: Rebuild Docker image (unless skipped)
if [[ "$SKIP_BUILD" == "false" ]]; then
    info "Step 2: Rebuilding Docker image..."
    
    # Get current image ID before rebuild
    IMAGE_BEFORE=$(docker images -q "${IMAGE_NAME}" 2>/dev/null || echo "")
    
    # Build the image (from deployment location after git pull)
    if ! (cd "${REPO_DIR}/village_docker/scripts" && ./build.sh); then
        error "Docker build failed"
        exit 1
    fi
    
    # Get current image ID after rebuild
    IMAGE_AFTER=$(docker images -q "${IMAGE_NAME}" 2>/dev/null || echo "")
    
    # Check if image changed
    if [[ "$IMAGE_BEFORE" == "$IMAGE_AFTER" ]] && [[ -n "$IMAGE_BEFORE" ]]; then
        info "Image unchanged (no rebuild needed)"
        IMAGE_CHANGED=false
    else
        info "Image rebuilt: ${IMAGE_BEFORE:0:12} → ${IMAGE_AFTER:0:12}"
        IMAGE_CHANGED=true
    fi
else
    info "Step 2: Skipping Docker build (--no-build)"
    
    # Check if image exists
    if ! docker image inspect "${IMAGE_NAME}" &> /dev/null; then
        error "Docker image not found: ${IMAGE_NAME}"
        echo "Cannot skip build when image doesn't exist"
        echo "Run without --no-build flag"
        exit 1
    fi
    
    IMAGE_CHANGED=false
fi

# Step 3: Restart container(s)
info "Step 3: Restarting container(s)..."

# Determine if we need to recreate
if [[ "$FORCE" == "true" ]]; then
    NEED_RESTART=true
    RESTART_REASON="forced restart"
elif [[ "$CODE_CHANGED" == "true" ]] || [[ "$IMAGE_CHANGED" == "true" ]]; then
    NEED_RESTART=true
    if [[ "$CODE_CHANGED" == "true" ]] && [[ "$IMAGE_CHANGED" == "true" ]]; then
        RESTART_REASON="code and image changed"
    elif [[ "$CODE_CHANGED" == "true" ]]; then
        RESTART_REASON="code changed"
    else
        RESTART_REASON="image changed"
    fi
else
    NEED_RESTART=false
fi

# Function to restart a single instance
restart_instance() {
    local instance="$1"
    local container_name="village-${instance}"
    local service_name="village-docker@${instance}.service"

    info "Restarting instance: ${instance} (container: ${container_name})..."

    # Check if systemd template service is available
    if systemctl is-active --quiet "${service_name}" 2>/dev/null; then
        info "Using systemd to restart ${service_name}..."
        if sudo systemctl restart "${service_name}"; then
            info "Service ${service_name} restarted successfully"
            sleep 2
            if docker ps -q -f name="${container_name}" | grep -q .; then
                info "Container ${container_name} is running"
            else
                error "Container ${container_name} failed to start"
                echo "Check status: sudo systemctl status ${service_name}"
                return 1
            fi
        else
            error "Failed to restart ${service_name}"
            return 1
        fi
    elif systemctl list-unit-files "${service_name}" &>/dev/null 2>&1; then
        info "Systemd service ${service_name} exists but is not running, starting it..."
        if sudo systemctl start "${service_name}"; then
            info "Service ${service_name} started successfully"
        else
            error "Failed to start ${service_name}"
            return 1
        fi
    else
        # No systemd service, use direct docker commands
        warn "Systemd service not found for ${instance}, using direct Docker commands..."
        
        if docker ps -q -f name="${container_name}" | grep -q .; then
            info "Stopping old container ${container_name}..."
            docker stop "${container_name}" || true
        fi
        if docker ps -aq -f name="${container_name}" | grep -q .; then
            info "Removing old container ${container_name}..."
            docker rm "${container_name}" || true
        fi
        
        info "Starting new container for ${instance}..."
        if (cd "${REPO_DIR}/village_docker/scripts" && ./start.sh --instance "${instance}"); then
            info "Container ${container_name} started successfully"
        else
            error "Failed to start container for ${instance}"
            return 1
        fi
    fi
}

if [[ "$NEED_RESTART" == "true" ]]; then
    info "Restarting (${RESTART_REASON})..."
    
    if [[ "$DEPLOY_ALL" == "true" ]]; then
        # Restart all instances
        INSTANCES_DIR="${VILLAGE_BASE_DIR}/instances"
        if [[ ! -d "$INSTANCES_DIR" ]]; then
            error "Instances directory not found: ${INSTANCES_DIR}"
            exit 1
        fi

        RESTART_FAILURES=0
        for instance_dir in "${INSTANCES_DIR}"/*/; do
            if [[ -d "$instance_dir" ]]; then
                instance=$(basename "$instance_dir")
                restart_instance "$instance" || ((RESTART_FAILURES++))
            fi
        done

        if [[ $RESTART_FAILURES -gt 0 ]]; then
            error "${RESTART_FAILURES} instance(s) failed to restart"
            exit 1
        fi
    else
        # Restart single instance
        restart_instance "${VILLAGE_INSTANCE}"
    fi
else
    info "No restart needed (no changes detected)"
    
    if [[ "$DEPLOY_ALL" == "true" ]]; then
        info "All instances unchanged"
    else
        # Check if container is running
        if docker ps -q -f name="${CONTAINER_NAME}" | grep -q .; then
            info "Container ${CONTAINER_NAME} is already running"
        else
            warn "Container ${CONTAINER_NAME} is not running"
            echo "Start it: ./scripts/start.sh --instance ${VILLAGE_INSTANCE}"
        fi
    fi
fi

# Deployment summary
echo ""
info "===== Deployment Complete ====="
echo ""
echo "Status:"
if [[ "$SKIP_PULL" == "false" ]]; then
    echo "  Code:      $(if [[ "$CODE_CHANGED" == "true" ]]; then echo "Updated ✓"; else echo "No changes"; fi)"
fi
if [[ "$SKIP_BUILD" == "false" ]]; then
    echo "  Image:     $(if [[ "$IMAGE_CHANGED" == "true" ]]; then echo "Rebuilt ✓"; else echo "No changes"; fi)"
fi
echo "  Container: $(if [[ "$NEED_RESTART" == "true" ]]; then echo "Restarted ✓"; else echo "Running"; fi)"
if [[ "$DEPLOY_ALL" == "true" ]]; then
    echo "  Scope:     All instances"
else
    echo "  Instance:  ${VILLAGE_INSTANCE}"
fi
echo ""
echo "Next steps:"
if [[ "$DEPLOY_ALL" == "true" ]]; then
    echo "  List instances:  ./scripts/instances.sh"
else
    echo "  View logs:     ./scripts/logs.sh --instance ${VILLAGE_INSTANCE} --follow"
    echo "  View app:      http://localhost:$(get_host_port 2>/dev/null || echo '<PORT>')"
fi
echo "  Check Docker:  docker ps | grep village"
echo ""

exit 0
