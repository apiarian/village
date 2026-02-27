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

# Parse --instance flag from arguments
# This is done early so all scripts get VILLAGE_INSTANCE set before anything else.
# The flag is stripped from the argument list so downstream parsing is unaffected.
_parse_instance_flag() {
    local -a new_args=()
    while [[ $# -gt 0 ]]; do
        case $1 in
            --instance)
                if [[ -z "${2:-}" ]]; then
                    error "--instance requires a value"
                    exit 1
                fi
                VILLAGE_INSTANCE="$2"
                shift 2
                ;;
            *)
                new_args+=("$1")
                shift
                ;;
        esac
    done
    # Update the caller's positional parameters
    VILLAGE_ARGS=("${new_args[@]+"${new_args[@]}"}")
}

# Only parse if VILLAGE_SKIP_INSTANCE_PARSE is not set (allows build.sh to opt out)
if [[ "${VILLAGE_SKIP_INSTANCE_PARSE:-}" != "1" ]]; then
    _parse_instance_flag "$@"
    # Replace positional parameters with the filtered list
    set -- "${VILLAGE_ARGS[@]+"${VILLAGE_ARGS[@]}"}"
fi

# Require VILLAGE_INSTANCE
if [[ "${VILLAGE_SKIP_INSTANCE_REQUIRE:-}" != "1" ]]; then
    if [[ -z "${VILLAGE_INSTANCE:-}" ]]; then
        error "VILLAGE_INSTANCE is required"
        error ""
        error "Provide it via:"
        error "  --instance <name>                    (command-line flag)"
        error "  VILLAGE_INSTANCE=<name> ./script.sh  (environment variable)"
        error ""
        error "List instances: ./scripts/instances.sh"
        exit 1
    fi
fi

# Validate instance name (alphanumeric, hyphens, underscores only)
if [[ -n "${VILLAGE_INSTANCE:-}" ]]; then
    if [[ ! "${VILLAGE_INSTANCE}" =~ ^[a-zA-Z0-9_-]+$ ]]; then
        error "Invalid instance name: '${VILLAGE_INSTANCE}'"
        error "Instance names may only contain letters, numbers, hyphens, and underscores"
        exit 1
    fi
fi

# Configuration - derived from VILLAGE_INSTANCE
VILLAGE_BASE_DIR="${VILLAGE_BASE_DIR:-/opt/village}"

if [[ -n "${VILLAGE_INSTANCE:-}" ]]; then
    INSTANCE_DIR="${VILLAGE_BASE_DIR}/instances/${VILLAGE_INSTANCE}"
    DATA_DIR="${DATA_DIR:-${INSTANCE_DIR}/data}"
    LOGS_DIR="${LOGS_DIR:-${INSTANCE_DIR}/logs}"
    CONFIG_DIR="${CONFIG_DIR:-${INSTANCE_DIR}/config}"
    CONFIG_FILE="${CONFIG_FILE:-${CONFIG_DIR}/village.env}"
    BACKUP_DIR="${BACKUP_DIR:-${INSTANCE_DIR}/backups}"
    CONTAINER_NAME="${CONTAINER_NAME:-village-${VILLAGE_INSTANCE}}"
else
    # Fallback for scripts that don't require an instance (e.g., build.sh)
    INSTANCE_DIR=""
    DATA_DIR="${DATA_DIR:-}"
    LOGS_DIR="${LOGS_DIR:-}"
    CONFIG_DIR="${CONFIG_DIR:-}"
    CONFIG_FILE="${CONFIG_FILE:-}"
    BACKUP_DIR="${BACKUP_DIR:-}"
    CONTAINER_NAME="${CONTAINER_NAME:-}"
fi

VILLAGE_USER="${VILLAGE_USER:-village}"
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

# Read HOST_PORT from the instance's village.env file
# Returns the port if found, empty string otherwise
get_host_port() {
    if [[ -f "${CONFIG_FILE}" ]]; then
        grep -E '^HOST_PORT=' "${CONFIG_FILE}" 2>/dev/null | head -1 | cut -d= -f2 | tr -d ' '
    fi
}

# Get the village UID for use in other scripts
# This is the main function scripts should call
VILLAGE_UID=$(get_village_uid)

debug "Configuration:"
debug "  VILLAGE_INSTANCE: ${VILLAGE_INSTANCE:-<not set>}"
debug "  VILLAGE_BASE_DIR: ${VILLAGE_BASE_DIR}"
debug "  INSTANCE_DIR: ${INSTANCE_DIR:-<not set>}"
debug "  SCRIPT_REPO: ${SCRIPT_REPO}"
debug "  REPO_DIR: ${REPO_DIR}"
debug "  DATA_DIR: ${DATA_DIR:-<not set>}"
debug "  LOGS_DIR: ${LOGS_DIR:-<not set>}"
debug "  CONFIG_DIR: ${CONFIG_DIR:-<not set>}"
debug "  CONFIG_FILE: ${CONFIG_FILE:-<not set>}"
debug "  BACKUP_DIR: ${BACKUP_DIR:-<not set>}"
debug "  VILLAGE_USER: ${VILLAGE_USER}"
debug "  VILLAGE_UID: ${VILLAGE_UID}"
debug "  CONTAINER_NAME: ${CONTAINER_NAME:-<not set>}"
debug "  IMAGE_NAME: ${IMAGE_NAME}"
