#!/bin/bash
# migrate.sh - Migrate a single-instance Village deployment to the multi-instance layout
#
# Usage: sudo ./scripts/migrate.sh --instance <name> [--dry-run]
#
# This script migrates the old directory layout:
#   /opt/village/{data,logs,config,backups}
#
# To the new multi-instance layout:
#   /opt/village/instances/<name>/{data,logs,config,backups}
#
# It also replaces the old village-docker.service with the new template unit.

set -euo pipefail

# Source common configuration
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# Note: common.sh parses and strips --instance from $@
source "${SCRIPT_DIR}/common.sh"

DRY_RUN=false

# Parse additional arguments
while [[ $# -gt 0 ]]; do
    case $1 in
        --dry-run)
            DRY_RUN=true
            shift
            ;;
        --help|-h)
            cat << EOF
Usage: sudo $(basename "$0") --instance <name> [OPTIONS]

Migrate an existing single-instance Village deployment to the multi-instance layout.

Options:
    --instance NAME   Instance name for the migrated deployment (required)
    --dry-run         Preview changes without making them
    --help            Show this help message

What This Does:
    1. Checks that the old layout exists (/opt/village/{data,logs,config,backups})
    2. Creates the new instance directory structure
    3. Moves data, logs, config, and backups to the instance directory
    4. Adds HOST_PORT=8000 to village.env (if not already set)
    5. Sets correct ownership
    6. Removes the old village-docker.service
    7. Installs the new village-docker@<name>.service template
    8. Prints a summary and next steps

Safety:
    - Will NOT overwrite an existing instance directory
    - Use --dry-run to preview all changes before executing
    - The old village-docker.service is stopped before migration

Examples:
    # Preview what would happen
    sudo $(basename "$0") --instance mysite --dry-run

    # Actually migrate
    sudo $(basename "$0") --instance mysite

EOF
            exit 0
            ;;
        *)
            error "Unknown option: $1"
            exit 1
            ;;
    esac
done

# Check if running as root
if [[ $EUID -ne 0 ]]; then
    error "This script must be run as root (use sudo)"
    exit 1
fi

info "Village Migration: single-instance → multi-instance"
info "===================================================="
echo ""
info "Instance name: ${VILLAGE_INSTANCE}"
info "Target directory: ${INSTANCE_DIR}"
if [[ "$DRY_RUN" == "true" ]]; then
    warn "DRY RUN MODE — no changes will be made"
fi
echo ""

# Old layout paths
OLD_DATA="${VILLAGE_BASE_DIR}/data"
OLD_LOGS="${VILLAGE_BASE_DIR}/logs"
OLD_CONFIG="${VILLAGE_BASE_DIR}/config"
OLD_BACKUPS="${VILLAGE_BASE_DIR}/backups"
OLD_SERVICE="/etc/systemd/system/village-docker.service"
NEW_SERVICE_TEMPLATE="${SCRIPT_REPO}/village_docker/village-docker@.service"
NEW_SERVICE_DEST="/etc/systemd/system/village-docker@.service"

# Step 1: Validate old layout exists
info "Step 1: Checking old layout..."
MISSING=()
for dir in "$OLD_DATA" "$OLD_LOGS" "$OLD_CONFIG"; do
    if [[ -d "$dir" ]]; then
        info "  ✓ Found: $dir"
    else
        warn "  ✗ Missing: $dir"
        MISSING+=("$dir")
    fi
done

if [[ ${#MISSING[@]} -gt 0 ]]; then
    error "Old layout directories not found. Nothing to migrate."
    error "Expected directories: ${OLD_DATA}, ${OLD_LOGS}, ${OLD_CONFIG}"
    exit 1
fi

# Check backups directory (optional)
if [[ -d "$OLD_BACKUPS" ]]; then
    info "  ✓ Found: $OLD_BACKUPS"
else
    info "  - No backups directory (will skip)"
fi

echo ""

# Step 2: Check for conflicts
info "Step 2: Checking for conflicts..."

if [[ -d "${INSTANCE_DIR}" ]]; then
    error "Instance directory already exists: ${INSTANCE_DIR}"
    error "Will not overwrite an existing instance. Choose a different name or remove it first."
    exit 1
fi
info "  ✓ No conflicts"
echo ""

# Step 3: Stop old service if running
info "Step 3: Stopping old service..."
if [[ "$DRY_RUN" == "true" ]]; then
    if systemctl is-active --quiet village-docker.service 2>/dev/null; then
        info "  [DRY RUN] Would stop village-docker.service"
    else
        info "  [DRY RUN] village-docker.service not active (nothing to stop)"
    fi
else
    if systemctl is-active --quiet village-docker.service 2>/dev/null; then
        info "  Stopping village-docker.service..."
        systemctl stop village-docker.service
        info "  ✓ Service stopped"
    else
        info "  village-docker.service not active (nothing to stop)"
    fi

    # Also stop the docker container directly
    if docker ps --format '{{.Names}}' 2>/dev/null | grep -q "^village$"; then
        info "  Stopping Docker container 'village'..."
        docker stop village || true
        info "  ✓ Container stopped"
    fi
fi
echo ""

# Step 4: Create new directory structure
info "Step 4: Creating new directory structure..."

DIRS_TO_CREATE=(
    "${VILLAGE_BASE_DIR}/instances"
    "${INSTANCE_DIR}"
)

for dir in "${DIRS_TO_CREATE[@]}"; do
    if [[ "$DRY_RUN" == "true" ]]; then
        info "  [DRY RUN] Would create: $dir"
    else
        mkdir -p "$dir"
        info "  ✓ Created: $dir"
    fi
done
echo ""

# Step 5: Move data
info "Step 5: Moving data to instance directory..."

move_dir() {
    local src="$1"
    local dst="$2"
    local label="$3"

    if [[ ! -d "$src" ]]; then
        info "  - Skipping ${label} (source not found: ${src})"
        return
    fi

    if [[ "$DRY_RUN" == "true" ]]; then
        local size
        size=$(du -sh "$src" 2>/dev/null | cut -f1 || echo "unknown")
        info "  [DRY RUN] Would move: ${src} → ${dst} (${size})"
    else
        info "  Moving ${label}: ${src} → ${dst}"
        mv "$src" "$dst"
        info "  ✓ ${label} moved"
    fi
}

move_dir "$OLD_DATA"    "${INSTANCE_DIR}/data"    "data"
move_dir "$OLD_LOGS"    "${INSTANCE_DIR}/logs"    "logs"
move_dir "$OLD_CONFIG"  "${INSTANCE_DIR}/config"  "config"
move_dir "$OLD_BACKUPS" "${INSTANCE_DIR}/backups" "backups"

# Create backups dir if it didn't exist before
if [[ ! -d "$OLD_BACKUPS" ]]; then
    if [[ "$DRY_RUN" == "true" ]]; then
        info "  [DRY RUN] Would create: ${INSTANCE_DIR}/backups"
    else
        mkdir -p "${INSTANCE_DIR}/backups"
        info "  ✓ Created: ${INSTANCE_DIR}/backups"
    fi
fi
echo ""

# Step 6: Add HOST_PORT to village.env
info "Step 6: Ensuring HOST_PORT is set in village.env..."

MIGRATED_ENV="${INSTANCE_DIR}/config/village.env"
if [[ "$DRY_RUN" == "true" ]]; then
    if [[ -f "${OLD_CONFIG}/village.env" ]]; then
        if grep -q '^HOST_PORT=' "${OLD_CONFIG}/village.env" 2>/dev/null; then
            info "  [DRY RUN] HOST_PORT already set in config"
        else
            info "  [DRY RUN] Would add HOST_PORT=8000 to village.env"
        fi
    fi
else
    if [[ -f "$MIGRATED_ENV" ]]; then
        if grep -q '^HOST_PORT=' "$MIGRATED_ENV" 2>/dev/null; then
            EXISTING_PORT=$(grep '^HOST_PORT=' "$MIGRATED_ENV" | head -1 | cut -d= -f2)
            info "  ✓ HOST_PORT already set: ${EXISTING_PORT}"
        else
            # Add HOST_PORT after the REQUIRED SETTINGS header if it exists, or at the end
            echo "" >> "$MIGRATED_ENV"
            echo "# Host port (added by migration)" >> "$MIGRATED_ENV"
            echo "HOST_PORT=8000" >> "$MIGRATED_ENV"
            info "  ✓ Added HOST_PORT=8000 to village.env"
        fi
    else
        warn "  village.env not found at ${MIGRATED_ENV}"
    fi
fi
echo ""

# Step 7: Set ownership
info "Step 7: Setting ownership..."

if [[ "$DRY_RUN" == "true" ]]; then
    info "  [DRY RUN] Would set ownership of ${INSTANCE_DIR} to ${VILLAGE_USER}:${VILLAGE_USER}"
else
    if id "${VILLAGE_USER}" &>/dev/null; then
        chown -R "${VILLAGE_USER}:${VILLAGE_USER}" "${INSTANCE_DIR}"
        # Config file should be restricted
        if [[ -f "$MIGRATED_ENV" ]]; then
            chmod 600 "$MIGRATED_ENV"
        fi
        info "  ✓ Ownership set to ${VILLAGE_USER}:${VILLAGE_USER}"
    else
        warn "  Village user '${VILLAGE_USER}' does not exist, skipping ownership"
    fi
fi
echo ""

# Step 8: Update systemd service
info "Step 8: Updating systemd service..."

if [[ "$DRY_RUN" == "true" ]]; then
    if [[ -f "$OLD_SERVICE" ]]; then
        info "  [DRY RUN] Would disable and remove: ${OLD_SERVICE}"
    fi
    info "  [DRY RUN] Would install: ${NEW_SERVICE_DEST}"
    info "  [DRY RUN] Would enable: village-docker@${VILLAGE_INSTANCE}.service"
else
    # Remove old service
    if [[ -f "$OLD_SERVICE" ]]; then
        info "  Disabling old village-docker.service..."
        systemctl disable village-docker.service 2>/dev/null || true
        rm -f "$OLD_SERVICE"
        info "  ✓ Old service removed"
    fi

    # Install new template service
    if [[ -f "$NEW_SERVICE_TEMPLATE" ]]; then
        cp "$NEW_SERVICE_TEMPLATE" "$NEW_SERVICE_DEST"
        systemctl daemon-reload
        info "  ✓ Template service installed: ${NEW_SERVICE_DEST}"

        # Enable the instance
        systemctl enable "village-docker@${VILLAGE_INSTANCE}.service"
        info "  ✓ Enabled: village-docker@${VILLAGE_INSTANCE}.service"
    else
        warn "  Template service file not found: ${NEW_SERVICE_TEMPLATE}"
        warn "  You'll need to install it manually"
    fi
fi
echo ""

# Summary
info "===== Migration Summary ====="
echo ""
if [[ "$DRY_RUN" == "true" ]]; then
    warn "DRY RUN — no changes were made"
    echo ""
    info "Run without --dry-run to apply changes:"
    echo "  sudo $(basename "$0") --instance ${VILLAGE_INSTANCE}"
else
    info "Migration complete!"
    echo ""
    info "Old layout (removed):"
    echo "  /opt/village/data/     → ${INSTANCE_DIR}/data/"
    echo "  /opt/village/logs/     → ${INSTANCE_DIR}/logs/"
    echo "  /opt/village/config/   → ${INSTANCE_DIR}/config/"
    echo "  /opt/village/backups/  → ${INSTANCE_DIR}/backups/"
    echo ""
    info "New layout:"
    echo "  ${INSTANCE_DIR}/"
    echo "  ├── data/"
    echo "  ├── logs/"
    echo "  ├── config/"
    echo "  │   └── village.env"
    echo "  └── backups/"
    echo ""
    info "Systemd service:"
    echo "  Old: village-docker.service (removed)"
    echo "  New: village-docker@${VILLAGE_INSTANCE}.service (enabled)"
    echo ""
    info "Next steps:"
    echo "  1. Verify the migration:"
    echo "     ls -la ${INSTANCE_DIR}/"
    echo ""
    echo "  2. Start the service:"
    echo "     sudo systemctl start village-docker@${VILLAGE_INSTANCE}"
    echo ""
    echo "  3. Check status:"
    echo "     sudo systemctl status village-docker@${VILLAGE_INSTANCE}"
    echo ""
    echo "  4. List instances:"
    echo "     ./scripts/instances.sh"
fi
echo ""
