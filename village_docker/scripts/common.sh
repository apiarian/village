#!/bin/bash
# common.sh - Common functions and configuration for Village Docker scripts
# This file is meant to be sourced by other scripts: source "$(dirname "$0")/common.sh"

# Color output
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

info() {
    echo -e "${GREEN}[INFO]${NC} $1"
}

warn() {
    echo -e "${YELLOW}[WARN]${NC} $1"
}

error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

debug() {
    if [[ "${DEBUG:-}" == "1" ]]; then
        echo -e "${BLUE}[DEBUG]${NC} $1"
    fi
}

# Configuration
VILLAGE_BASE_DIR="${VILLAGE_BASE_DIR:-/opt/village}"
DATA_DIR="${DATA_DIR:-${VILLAGE_BASE_DIR}/data}"
LOGS_DIR="${LOGS_DIR:-${VILLAGE_BASE_DIR}/logs}"
CONFIG_DIR="${CONFIG_DIR:-${VILLAGE_BASE_DIR}/config}"
BACKUP_DIR="${BACKUP_DIR:-${VILLAGE_BASE_DIR}/backups}"
VILLAGE_USER="${VILLAGE_USER:-village}"
CONTAINER_NAME="${CONTAINER_NAME:-village}"
IMAGE_NAME="${IMAGE_NAME:-village:latest}"

# Detect which repository we're running from
# This allows scripts to work from both personal clone and deployment location
detect_repo_root() {
    local script_dir="$1"
    # Go up from scripts/ to village_docker/ to repo root
    if [[ -f "${script_dir}/../Dockerfile" ]]; then
        # We're in village_docker/scripts/
        echo "$(cd "${script_dir}/../.." && pwd)"
    elif [[ -f "${script_dir}/Dockerfile" ]]; then
        # We're in village_docker/ somehow
        echo "$(cd "${script_dir}/.." && pwd)"
    else
        # Fallback to deployment location
        echo "${VILLAGE_BASE_DIR}/village"
    fi
}

# SCRIPT_REPO is where THIS script is running from (could be ~/village or /opt/village/village)
# Use this for Docker builds and operations that need the actual repo
SCRIPT_REPO="${SCRIPT_REPO:-$(detect_repo_root "$(dirname "${BASH_SOURCE[0]}")")}"

# REPO_DIR is the deployment location (always /opt/village/village)
# Use this for references to the production deployment
REPO_DIR="${REPO_DIR:-${VILLAGE_BASE_DIR}/village}"

# Detect the village user's UID on the host
# Returns the UID if user exists, otherwise returns the default (10000)
get_village_uid() {
    local default_uid=10000
    
    if id "${VILLAGE_USER}" &>/dev/null; then
        id -u "${VILLAGE_USER}"
    else
        echo "${default_uid}"
    fi
}

# Get the village UID for use in other scripts
# This is the main function scripts should call
VILLAGE_UID=$(get_village_uid)

debug "Configuration:"
debug "  VILLAGE_BASE_DIR: ${VILLAGE_BASE_DIR}"
debug "  SCRIPT_REPO: ${SCRIPT_REPO}"
debug "  REPO_DIR: ${REPO_DIR}"
debug "  DATA_DIR: ${DATA_DIR}"
debug "  LOGS_DIR: ${LOGS_DIR}"
debug "  CONFIG_DIR: ${CONFIG_DIR}"
debug "  BACKUP_DIR: ${BACKUP_DIR}"
debug "  VILLAGE_USER: ${VILLAGE_USER}"
debug "  VILLAGE_UID: ${VILLAGE_UID}"
debug "  CONTAINER_NAME: ${CONTAINER_NAME}"
debug "  IMAGE_NAME: ${IMAGE_NAME}"
