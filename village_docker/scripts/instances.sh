#!/bin/bash
# instances.sh - List all Village Docker instances with their status
#
# Usage: ./instances.sh
#
# This script does not require --instance — it operates on all instances.

set -e

# Opt out of instance requirement
export VILLAGE_SKIP_INSTANCE_PARSE=1
export VILLAGE_SKIP_INSTANCE_REQUIRE=1

# Source common configuration
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${SCRIPT_DIR}/common.sh"

INSTANCES_DIR="${VILLAGE_BASE_DIR}/instances"

if [[ "${1:-}" == "-h" ]] || [[ "${1:-}" == "--help" ]]; then
    cat << EOF
Usage: $(basename "$0")

List all Village Docker instances with their port, container name, and status.

Notes:
    - Instances are discovered from ${INSTANCES_DIR}/
    - Port is read from each instance's config/village.env (HOST_PORT)
    - Container status is read from Docker

EOF
    exit 0
fi

if [[ ! -d "$INSTANCES_DIR" ]]; then
    warn "No instances directory found at ${INSTANCES_DIR}"
    info "Create an instance with: sudo ./scripts/setup.sh --instance <name>"
    exit 0
fi

# Check if any instances exist
has_instances=false
for instance_dir in "${INSTANCES_DIR}"/*/; do
    if [[ -d "$instance_dir" ]]; then
        has_instances=true
        break
    fi
done

if [[ "$has_instances" == "false" ]]; then
    info "No instances found"
    info "Create an instance with: sudo ./scripts/setup.sh --instance <name>"
    exit 0
fi

# Print header
printf "%-20s %-8s %-25s %s\n" "INSTANCE" "PORT" "CONTAINER" "STATUS"
printf "%-20s %-8s %-25s %s\n" "--------" "----" "---------" "------"

for instance_dir in "${INSTANCES_DIR}"/*/; do
    if [[ ! -d "$instance_dir" ]]; then
        continue
    fi

    instance=$(basename "$instance_dir")
    container_name="village-${instance}"
    env_file="${instance_dir}/config/village.env"
    port="-"

    # Read HOST_PORT from env file
    if [[ -f "$env_file" ]]; then
        port=$(grep -E '^HOST_PORT=' "$env_file" 2>/dev/null | head -1 | cut -d= -f2 | tr -d ' ')
        if [[ -z "$port" ]]; then
            port="-"
        fi
    fi

    # Check container status
    status="not created"
    if docker ps --format '{{.Names}}' 2>/dev/null | grep -q "^${container_name}$"; then
        status="running"
    elif docker ps -a --format '{{.Names}}' 2>/dev/null | grep -q "^${container_name}$"; then
        status="stopped"
    fi

    printf "%-20s %-8s %-25s %s\n" "$instance" "$port" "$container_name" "$status"
done
