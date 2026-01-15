#!/usr/bin/env bash
#
# deploy.sh - Deploy Village Docker (update code, rebuild, restart)
#
# This script automates the deployment process:
# 1. Pull latest code from git (in deployment location: /opt/village/village)
# 2. Rebuild Docker image (from deployment location)
# 3. Restart container via systemd (or direct Docker if systemd not available)
#
# Note: This script always deploys to /opt/village/village regardless of where
#       you run it from. You can run it from your personal clone (e.g., ~/village)
#       and it will deploy to the production location.
#
# Usage:
#   ./deploy.sh [options]
#
# Options:
#   --no-pull       Skip git pull (only rebuild and restart)
#   --no-build      Skip rebuild (only pull and restart with existing image)
#   --force         Force recreate container even if image didn't change
#   --branch NAME   Switch to a different branch before pulling
#   --help          Show this help message
#
# Examples:
#   ./deploy.sh                    # Full deploy: pull, build, restart
#   ./deploy.sh --no-pull          # Only rebuild and restart
#   ./deploy.sh --force            # Force recreate even if no changes
#   ./deploy.sh --branch develop   # Deploy from develop branch
#
# Exit codes:
#   0 - Success
#   1 - Error (git pull failed, build failed, etc.)
#

set -e  # Exit on error

# Get script directory and source common functions
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${SCRIPT_DIR}/common.sh"

# Parse command line options
SKIP_PULL=false
SKIP_BUILD=false
FORCE=false
BRANCH=""

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
echo ""

# Step 1: Git pull (unless skipped)
if [[ "$SKIP_PULL" == "false" ]]; then
    info "Step 1: Updating code from git..."
    
    cd "${REPO_DIR}"
    
    # Determine if we need to run git commands as village user
    # This is needed to avoid "dubious ownership" errors when host user != village user
    CURRENT_UID=$(id -u)
    VILLAGE_UID=$(get_village_uid)
    REPO_OWNER_UID=$(stat -c '%u' "${REPO_DIR}")
    
    # Helper function to run git commands
    run_git() {
        if [[ "$CURRENT_UID" == "$REPO_OWNER_UID" ]]; then
            # Current user owns the repo, run directly
            git "$@"
        elif [[ "$REPO_OWNER_UID" == "$VILLAGE_UID" ]] && id "${VILLAGE_USER}" &>/dev/null; then
            # Repo is owned by village user, run as village user
            sudo -u "${VILLAGE_USER}" git "$@"
        else
            # Try to add to safe.directory and run directly
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
        
        # Show what changed
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
    # We need to run build.sh from REPO_DIR so it builds the code we just pulled
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

# Step 3: Restart container
info "Step 3: Restarting container..."

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

if [[ "$NEED_RESTART" == "true" ]]; then
    info "Restarting container (${RESTART_REASON})..."
    
    # Check if systemd service is available
    if systemctl is-active --quiet village-docker.service 2>/dev/null; then
        info "Using systemd to restart service..."
        if sudo systemctl restart village-docker.service; then
            info "Service restarted successfully"
            
            # Wait a moment for container to start
            sleep 2
            
            # Verify container is running
            if docker ps -q -f name="${CONTAINER_NAME}" | grep -q .; then
                info "Container is running"
            else
                error "Container failed to start"
                echo ""
                echo "Check status: sudo systemctl status village-docker.service"
                echo "Check logs:   ./scripts/logs.sh --error"
                exit 1
            fi
        else
            error "Failed to restart service"
            echo ""
            echo "Check status: sudo systemctl status village-docker.service"
            exit 1
        fi
    elif systemctl list-unit-files village-docker.service &>/dev/null; then
        # Service exists but is not running - start it
        info "Systemd service exists but is not running, starting it..."
        if sudo systemctl start village-docker.service; then
            info "Service started successfully"
        else
            error "Failed to start service"
            echo ""
            echo "Check status: sudo systemctl status village-docker.service"
            exit 1
        fi
    else
        # No systemd service, use direct docker commands
        warn "Systemd service not found, using direct Docker commands..."
        
        # Stop and remove old container
        if docker ps -q -f name="${CONTAINER_NAME}" | grep -q .; then
            info "Stopping old container..."
            docker stop "${CONTAINER_NAME}" || true
        fi
        if docker ps -aq -f name="${CONTAINER_NAME}" | grep -q .; then
            info "Removing old container..."
            docker rm "${CONTAINER_NAME}" || true
        fi
        
        # Start new container
        info "Starting new container..."
        if (cd "${REPO_DIR}/village_docker/scripts" && ./start.sh); then
            info "Container started successfully"
        else
            error "Failed to start container"
            echo ""
            echo "Check logs: ${REPO_DIR}/village_docker/scripts/logs.sh --error"
            exit 1
        fi
    fi
else
    info "No restart needed (no changes detected)"
    
    # Check if container is running
    if docker ps -q -f name="${CONTAINER_NAME}" | grep -q .; then
        info "Container is already running"
    elif systemctl is-active --quiet village-docker.service 2>/dev/null; then
        info "Systemd service is active"
    else
        warn "Container/service is not running"
        echo ""
        if systemctl list-unit-files village-docker.service &>/dev/null; then
            echo "Start it: sudo systemctl start village-docker.service"
        else
            echo "Start it: ./scripts/start.sh"
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
echo ""
echo "Next steps:"
echo "  View logs:     ${REPO_DIR}/village_docker/scripts/logs.sh --follow"
echo "  View app:      http://localhost:8000"
echo "  Check status:  sudo systemctl status village-docker.service"
echo "  Check Docker:  docker ps | grep ${CONTAINER_NAME}"
echo ""

exit 0
