#!/bin/bash
set -euo pipefail

# Source common configuration and functions
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# Note: common.sh parses and strips --instance from $@
source "${SCRIPT_DIR}/common.sh"

# Show help
show_help() {
    cat << EOF
Usage: $(basename "$0") --instance <name> [OPTIONS]

Backup the Village data directory to a timestamped tarball.

This script creates a compressed backup of the Village data directory and
optionally the configuration file. Backups are stored in ${BACKUP_DIR}.

Options:
    --instance NAME     Instance name (required, or set VILLAGE_INSTANCE)
    --include-config    Include the configuration file in the backup
    --output DIR        Use custom backup directory (default: ${BACKUP_DIR})
    --compress TYPE     Compression type: gzip (default), bzip2, xz, none
    --no-verify         Skip verification of the created backup
    --no-gc             Skip garbage collection after backup
    --gc-dry-run        Run garbage collection in dry-run mode (report only)
    --help              Show this help message

Examples:
    # Basic backup (data only)
    $(basename "$0") --instance mysite

    # Backup including configuration (contains secrets!)
    $(basename "$0") --instance mysite --include-config

    # Custom backup location
    $(basename "$0") --instance mysite --output /mnt/external/backups

Backup Location:
    Default: ${BACKUP_DIR}/village-${VILLAGE_INSTANCE}-data-YYYYMMDD-HHMMSS.tar.gz

What Gets Backed Up:
    - Data directory: ${DATA_DIR}
    - Config file (if --include-config): ${CONFIG_FILE}

Restoration:
    # Stop the container first
    ./stop.sh --instance ${VILLAGE_INSTANCE}

    # Extract backup
    sudo tar -xzf ${BACKUP_DIR}/village-${VILLAGE_INSTANCE}-data-YYYYMMDD-HHMMSS.tar.gz -C /

    # Verify ownership is correct
    sudo ./setup.sh --instance ${VILLAGE_INSTANCE}

    # Start container
    ./start.sh --instance ${VILLAGE_INSTANCE}

EOF
}

# Parse arguments
INCLUDE_CONFIG=false
BACKUP_OUTPUT_DIR="${BACKUP_DIR}"
COMPRESS_TYPE="gzip"
VERIFY=true
RUN_GC=true
GC_DRY_RUN=false

while [[ $# -gt 0 ]]; do
    case $1 in
        --include-config)
            INCLUDE_CONFIG=true
            shift
            ;;
        --output)
            if [[ -z "${2:-}" ]]; then
                error "ERROR: --output requires a directory path"
                exit 1
            fi
            BACKUP_OUTPUT_DIR="$2"
            shift 2
            ;;
        --compress)
            if [[ -z "${2:-}" ]]; then
                error "ERROR: --compress requires a type (gzip, bzip2, xz, none)"
                exit 1
            fi
            COMPRESS_TYPE="$2"
            shift 2
            ;;
        --no-verify)
            VERIFY=false
            shift
            ;;
        --no-gc)
            RUN_GC=false
            shift
            ;;
        --gc-dry-run)
            GC_DRY_RUN=true
            shift
            ;;
        --help)
            show_help
            exit 0
            ;;
        *)
            error "ERROR: Unknown option: $1"
            echo "Use --help for usage information"
            exit 1
            ;;
    esac
done

# Validate compression type
case "$COMPRESS_TYPE" in
    gzip)
        COMPRESS_FLAG="z"
        COMPRESS_EXT=".gz"
        COMPRESS_CMD="gzip"
        ;;
    bzip2)
        COMPRESS_FLAG="j"
        COMPRESS_EXT=".bz2"
        COMPRESS_CMD="bzip2"
        ;;
    xz)
        COMPRESS_FLAG="J"
        COMPRESS_EXT=".xz"
        COMPRESS_CMD="xz"
        ;;
    none)
        COMPRESS_FLAG=""
        COMPRESS_EXT=""
        COMPRESS_CMD=""
        ;;
    *)
        error "ERROR: Invalid compression type: ${COMPRESS_TYPE}"
        error "Valid options: gzip, bzip2, xz, none"
        exit 1
        ;;
esac

# Check if compression command is available (if needed)
if [[ -n "$COMPRESS_CMD" ]] && ! command -v "$COMPRESS_CMD" &> /dev/null; then
    error "ERROR: Compression command '${COMPRESS_CMD}' not found"
    error "Install it or use a different compression type (--compress gzip|bzip2|xz|none)"
    exit 1
fi

# Validate data directory exists
if [[ ! -d "$DATA_DIR" ]]; then
    error "ERROR: Data directory does not exist: ${DATA_DIR}"
    error ""
    error "Have you initialized the repository yet?"
    error "Run: ./run-script.sh --instance ${VILLAGE_INSTANCE} initialize-repository"
    exit 1
fi

# Validate config file exists (if including it)
if [[ "$INCLUDE_CONFIG" == true ]] && [[ ! -f "$CONFIG_FILE" ]]; then
    error "ERROR: Configuration file does not exist: ${CONFIG_FILE}"
    exit 1
fi

# Create backup directory if it doesn't exist
if [[ ! -d "$BACKUP_OUTPUT_DIR" ]]; then
    info "Creating backup directory: ${BACKUP_OUTPUT_DIR}"
    sudo mkdir -p "$BACKUP_OUTPUT_DIR"
    
    # Set ownership to village user if possible
    VILLAGE_UID=$(get_village_uid)
    if id -u "village" &>/dev/null; then
        sudo chown village:village "$BACKUP_OUTPUT_DIR"
        info "Set backup directory ownership to village:village"
    fi
fi

# Generate timestamp
TIMESTAMP=$(date +%Y%m%d-%H%M%S)

# Determine backup filename (includes instance name)
BACKUP_FILENAME="village-${VILLAGE_INSTANCE}-data-${TIMESTAMP}.tar${COMPRESS_EXT}"
BACKUP_PATH="${BACKUP_OUTPUT_DIR}/${BACKUP_FILENAME}"

# Build tar command
TAR_CMD="sudo tar -c${COMPRESS_FLAG}f"

info "===== Village Backup (instance: ${VILLAGE_INSTANCE}) ====="
info "Backup location: ${BACKUP_PATH}"
info "Compression: ${COMPRESS_TYPE}"
info "Including config: ${INCLUDE_CONFIG}"
echo ""

# Check if container is running
if docker ps --format '{{.Names}}' | grep -q "^${CONTAINER_NAME}$"; then
    warn "WARNING: Container is currently running"
    warn "For best results, stop the container before backing up:"
    warn "  ./stop.sh --instance ${VILLAGE_INSTANCE}"
    echo ""
    read -p "Continue anyway? (y/N) " -n 1 -r
    echo ""
    if [[ ! $REPLY =~ ^[Yy]$ ]]; then
        info "Backup cancelled"
        exit 0
    fi
fi

# Calculate size of data to backup
info "Calculating backup size..."
DATA_SIZE=$(sudo du -sh "$DATA_DIR" 2>/dev/null | cut -f1 || echo "unknown")
info "Data directory size: ${DATA_SIZE}"

if [[ "$INCLUDE_CONFIG" == true ]]; then
    CONFIG_SIZE=$(sudo du -sh "$CONFIG_FILE" 2>/dev/null | cut -f1 || echo "unknown")
    info "Config file size: ${CONFIG_SIZE}"
fi

echo ""
info "Creating backup..."

# Create the backup
if [[ "$INCLUDE_CONFIG" == true ]]; then
    $TAR_CMD "$BACKUP_PATH" \
        -C / \
        "${DATA_DIR#/}" \
        "${CONFIG_FILE#/}" \
        2>&1 | grep -v "Removing leading" || true
else
    $TAR_CMD "$BACKUP_PATH" \
        -C / \
        "${DATA_DIR#/}" \
        2>&1 | grep -v "Removing leading" || true
fi

# Check if backup was created successfully
if [[ ! -f "$BACKUP_PATH" ]]; then
    error "ERROR: Backup file was not created"
    exit 1
fi

# Get backup file size
BACKUP_SIZE=$(du -sh "$BACKUP_PATH" | cut -f1)
info "Backup created successfully!"
info "Backup size: ${BACKUP_SIZE}"
echo ""

# Verify backup integrity
if [[ "$VERIFY" == true ]]; then
    info "Verifying backup integrity..."
    
    if [[ -n "$COMPRESS_FLAG" ]]; then
        if sudo tar -t${COMPRESS_FLAG}f "$BACKUP_PATH" > /dev/null 2>&1; then
            info "✓ Backup verification passed"
        else
            error "ERROR: Backup verification failed!"
            error "The backup file may be corrupted."
            exit 1
        fi
    else
        if sudo tar -tf "$BACKUP_PATH" > /dev/null 2>&1; then
            info "✓ Backup verification passed"
        else
            error "ERROR: Backup verification failed!"
            error "The backup file may be corrupted."
            exit 1
        fi
    fi
    echo ""
fi

# Show what's in the backup
info "Backup contents:"
if [[ -n "$COMPRESS_FLAG" ]]; then
    sudo tar -t${COMPRESS_FLAG}f "$BACKUP_PATH" | head -n 10
else
    sudo tar -tf "$BACKUP_PATH" | head -n 10
fi

# Count total files
if [[ -n "$COMPRESS_FLAG" ]]; then
    TOTAL_FILES=$(sudo tar -t${COMPRESS_FLAG}f "$BACKUP_PATH" | wc -l)
else
    TOTAL_FILES=$(sudo tar -tf "$BACKUP_PATH" | wc -l)
fi
echo "... (${TOTAL_FILES} total files)"
echo ""

# Security warning if config included
if [[ "$INCLUDE_CONFIG" == true ]]; then
    warn "⚠️  SECURITY WARNING ⚠️"
    warn "This backup contains your configuration file with secrets!"
    warn "Store it securely and restrict access:"
    info "  sudo chmod 600 ${BACKUP_PATH}"
    echo ""
fi

# Show restoration instructions
info "===== Restoration Instructions ====="
info "To restore this backup:"
info "  1. Stop the container:"
info "     ./stop.sh --instance ${VILLAGE_INSTANCE}"
info ""
info "  2. Extract the backup:"
info "     sudo tar -x${COMPRESS_FLAG}f ${BACKUP_PATH} -C /"
info ""
info "  3. Fix ownership (if needed):"
info "     sudo ./scripts/setup.sh --instance ${VILLAGE_INSTANCE}"
info ""
info "  4. Start the container:"
info "     ./start.sh --instance ${VILLAGE_INSTANCE}"
echo ""

info "===== Backup Complete ====="
info "Backup saved to: ${BACKUP_PATH}"
echo ""

# ===== Garbage Collection =====
if [[ "$RUN_GC" == true ]]; then
    info "===== Garbage Collection (instance: ${VILLAGE_INSTANCE}) ====="
    info "Running garbage collection to remove expired threads and orphaned uploads..."
    echo ""

    # Build the garbage-collect command
    GC_ARGS=()
    if [[ "$GC_DRY_RUN" == true ]]; then
        GC_ARGS+=("--dry-run")
        info "Mode: dry-run (no changes will be made)"
    fi

    # Check if the main container is running — if so, run GC inside it
    if docker ps --format '{{.Names}}' | grep -q "^${CONTAINER_NAME}$"; then
        info "Running garbage collection inside running container..."
        set +e
        docker exec "${CONTAINER_NAME}" garbage-collect "${GC_ARGS[@]}"
        GC_EXIT=$?
        set -e
    else
        # Run a one-off container, same as run-script.sh does
        if [[ ! -f "${CONFIG_FILE}" ]]; then
            warn "Config file not found, skipping garbage collection"
            GC_EXIT=1
        elif ! docker image inspect "${IMAGE_NAME}" &> /dev/null; then
            warn "Docker image not found, skipping garbage collection"
            GC_EXIT=1
        else
            info "Running garbage collection in a temporary container..."
            set +e
            docker run \
                --rm \
                --name "${CONTAINER_NAME}-gc" \
                -v "${DATA_DIR}:/opt/village/data" \
                -v "${LOGS_DIR:-${INSTANCE_DIR}/logs}:/opt/village/logs" \
                --env-file "${CONFIG_FILE}" \
                "${IMAGE_NAME}" \
                garbage-collect "${GC_ARGS[@]}"
            GC_EXIT=$?
            set -e
        fi
    fi

    echo ""
    if [[ "${GC_EXIT:-0}" -eq 0 ]]; then
        info "✓ Garbage collection completed successfully"
    else
        warn "⚠ Garbage collection exited with code ${GC_EXIT}"
        warn "  The backup itself is still valid."
    fi
    echo ""
else
    info "Garbage collection skipped (--no-gc)"
    echo ""
fi

info "===== All Done ====="
info ""
info "Next steps:"
info "  - Test restoration on a different machine to verify backup works"
info "  - Store backup in a safe location (off-site, cloud storage, etc.)"
info "  - Consider automating backups with a cron job"
info "  - Clean up old backups periodically to save space"
echo ""

exit 0
