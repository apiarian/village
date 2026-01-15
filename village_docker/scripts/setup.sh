#!/bin/bash
# setup.sh - Idempotent setup script for Village Docker deployment
# Creates necessary directories and sets ownership
# Can be run multiple times safely

set -euo pipefail

# Source common functions and configuration
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${SCRIPT_DIR}/common.sh"

# Allow VILLAGE_UID override via environment, otherwise use detected/default
VILLAGE_UID="${VILLAGE_UID:-$(get_village_uid)}"

# Repository directory (where the git checkout lives)
REPO_DIR="${REPO_DIR:-${VILLAGE_BASE_DIR}/village}"

info "Village Docker Setup"
info "===================="
echo ""
info "Base directory: ${VILLAGE_BASE_DIR}"
info "Repository directory: ${REPO_DIR}"
info "Village UID: ${VILLAGE_UID}"
echo ""

# Check if running as root
if [[ $EUID -ne 0 ]]; then
   error "This script must be run as root (use sudo)"
   exit 1
fi

# Create village user if it doesn't exist, or use existing user
if id "${VILLAGE_USER}" &>/dev/null; then
    EXISTING_UID=$(id -u "${VILLAGE_USER}")
    info "User '${VILLAGE_USER}' already exists with UID ${EXISTING_UID}"
    # Use the existing UID for all subsequent operations
    VILLAGE_UID="${EXISTING_UID}"
else
    info "Creating system user '${VILLAGE_USER}' with UID ${VILLAGE_UID}..."
    useradd -r -s /bin/false -u "${VILLAGE_UID}" "${VILLAGE_USER}" 2>/dev/null || {
        # If UID is already taken, let useradd assign one automatically
        warn "UID ${VILLAGE_UID} is already in use, letting system assign UID..."
        useradd -r -s /bin/false "${VILLAGE_USER}"
        VILLAGE_UID=$(id -u "${VILLAGE_USER}")
        info "User created with UID ${VILLAGE_UID}"
    }
fi

# Create directories
info "Creating directories..."

for dir in "${VILLAGE_BASE_DIR}" "${DATA_DIR}" "${LOGS_DIR}" "${CONFIG_DIR}" "${BACKUP_DIR}" "${REPO_DIR}"; do
    if [[ -d "${dir}" ]]; then
        info "  ${dir} - already exists"
    else
        mkdir -p "${dir}"
        info "  ${dir} - created"
    fi
done

# Set ownership
info "Setting ownership to ${VILLAGE_USER}:${VILLAGE_USER}..."
chown -R "${VILLAGE_USER}:${VILLAGE_USER}" "${DATA_DIR}"
chown -R "${VILLAGE_USER}:${VILLAGE_USER}" "${LOGS_DIR}"
chown -R "${VILLAGE_USER}:${VILLAGE_USER}" "${BACKUP_DIR}"
chown "${VILLAGE_USER}:${VILLAGE_USER}" "${CONFIG_DIR}"
info "Ownership set successfully"

# Set directory permissions
info "Setting directory permissions..."
chmod 755 "${VILLAGE_BASE_DIR}"
chmod 755 "${DATA_DIR}"
chmod 755 "${LOGS_DIR}"
chmod 755 "${CONFIG_DIR}"
chmod 755 "${BACKUP_DIR}"
info "Permissions set successfully"

echo ""
info "Setup complete!"
echo ""

# Check if repository code is deployed and deploy it if needed
# Detect where we're running from by finding Dockerfile
CURRENT_REPO=""
GIT_REMOTE=""
if [[ -f "../Dockerfile" ]]; then
    # Running from village_docker/scripts, so repo is ../..
    CURRENT_REPO="$(cd ../.. && pwd)"
elif [[ -f "Dockerfile" ]]; then
    # Running from village_docker, so repo is ..
    CURRENT_REPO="$(cd .. && pwd)"
fi

# Get the git remote URL if we're in a git repo
if [[ -n "${CURRENT_REPO}" ]] && [[ -d "${CURRENT_REPO}/.git" ]]; then
    GIT_REMOTE=$(cd "${CURRENT_REPO}" && git remote get-url origin 2>/dev/null || echo "")
fi

if [[ -d "${REPO_DIR}/.git" ]]; then
    info "Repository found at: ${REPO_DIR}"
elif [[ -d "${REPO_DIR}" ]] && [[ ! "$(ls -A "${REPO_DIR}")" ]]; then
    warn "Repository directory exists but is empty: ${REPO_DIR}"
    
    if [[ -n "${GIT_REMOTE}" ]]; then
        info "Cloning repository from ${GIT_REMOTE} to ${REPO_DIR}..."
        if git clone "${GIT_REMOTE}" "${REPO_DIR}"; then
            info "Repository cloned successfully"
        else
            error "Git clone failed"
            exit 1
        fi
    else
        error "Could not detect git remote URL"
        info "Please clone the repository manually:"
        echo "  git clone <your-repo-url> ${REPO_DIR}"
        exit 1
    fi
else
    warn "Repository not found at: ${REPO_DIR}"
    if [[ -d "${REPO_DIR}" ]]; then
        error "Directory exists but is not empty and not a git repo"
        info "Contents:"
        ls -la "${REPO_DIR}" | head -5
        exit 1
    fi
fi

echo ""

# Set up configuration file
ENV_EXAMPLE="${REPO_DIR}/village_docker/config/village.env.example"
ENV_FILE="${CONFIG_DIR}/village.env"

if [[ -f "${ENV_FILE}" ]]; then
    info "Configuration file exists: ${ENV_FILE}"
    
    # Check if config has been reviewed
    if grep -q "^CONFIG_NOT_REVIEWED=" "${ENV_FILE}" 2>/dev/null; then
        warn "Configuration file has NOT been reviewed yet!"
        warn "You MUST edit ${ENV_FILE} before starting the application"
        warn "  1. Delete or comment out the CONFIG_NOT_REVIEWED line"
        warn "  2. Set FLASK_SECRET_KEY to a secure random value"
    elif grep -q "FLASK_SECRET_KEY=CHANGE_ME" "${ENV_FILE}" 2>/dev/null; then
        warn "Configuration file still has default FLASK_SECRET_KEY!"
        warn "You MUST edit ${ENV_FILE} before starting the application"
    fi
else
    if [[ -f "${ENV_EXAMPLE}" ]]; then
        info "Copying example configuration to ${ENV_FILE}..."
        cp "${ENV_EXAMPLE}" "${ENV_FILE}"
        
        # Set ownership
        chown "${VILLAGE_USER}:${VILLAGE_USER}" "${ENV_FILE}"
        chmod 600 "${ENV_FILE}"  # Only owner can read/write (contains secrets)
        
        info "Configuration file created with proper ownership"
        warn "IMPORTANT: You MUST edit ${ENV_FILE} before starting the application"
        echo ""
        echo "  Required changes:"
        echo "  1. Set FLASK_SECRET_KEY to a random string (32+ characters)"
        echo "     Generate one with: python3 -c \"import secrets; print(secrets.token_hex(32))\""
        echo ""
        echo "  Edit the file:"
        echo "    sudo nano ${ENV_FILE}"
    else
        error "Example config file not found: ${ENV_EXAMPLE}"
        info "Please ensure the repository is properly deployed"
        exit 1
    fi
fi

echo ""
info "Next steps:"
echo ""
echo "  1. Edit the configuration (REQUIRED before first run):"
echo "     sudo nano ${ENV_FILE}"
echo ""

# Provide paths relative to where we're running from
if [[ -n "${CURRENT_REPO}" ]]; then
    info "You can run the remaining scripts from your current location:"
    echo ""
    echo "  2. Build the Docker image:"
    echo "     cd ${CURRENT_REPO}/village_docker && ./scripts/build.sh"
    echo ""
    echo "  3. Initialize the repository:"
    echo "     ./scripts/run-script.sh initialize-repository"
    echo ""
    echo "  4. Create a user:"
    echo "     ./scripts/run-script.sh create-user"
    echo ""
    echo "  5. Start the service:"
    echo "     ./scripts/start.sh"
else
    info "Run the remaining scripts from the deployment location:"
    echo ""
    echo "  2. Build the Docker image:"
    echo "     cd ${REPO_DIR}/village_docker && ./scripts/build.sh"
    echo ""
    echo "  3. Initialize the repository:"
    echo "     ./scripts/run-script.sh initialize-repository"
    echo ""
    echo "  4. Create a user:"
    echo "     ./scripts/run-script.sh create-user"
    echo ""
    echo "  5. Start the service:"
    echo "     ./scripts/start.sh"
fi

echo ""
info "Directory structure:"
echo "  ${VILLAGE_BASE_DIR}/"
echo "  ├── village/  (Git repository checkout)"
echo "  ├── data/     (Village repository data)"
echo "  ├── logs/     (Application logs)"
echo "  ├── config/   (Configuration files)"
echo "  └── backups/  (Backup archives)"
echo ""
