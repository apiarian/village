#!/bin/bash
set -euo pipefail

# Source common configuration and functions
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${SCRIPT_DIR}/common.sh"

# Show help
show_help() {
    cat << EOF
Usage: $(basename "$0") [OPTIONS]

Backup the Village data directory to a timestamped tarball.

This script creates a compressed backup of the Village data directory and
optionally the configuration file. Backups are stored in ${BACKUP_DIR}.

Options:
    --include-config    Include the configuration file in the backup
    --output DIR        Use custom backup directory (default: ${BACKUP_DIR})
    --compress TYPE     Compression type: gzip (default), bzip2, xz, none
    --no-verify         Skip verification of the created backup
    --help              Show this help message

Examples:
    # Basic backup (data only)
    $(basename "$0")

    # Backup including configuration (contains secrets!)
    $(basename "$0") --include-config

    # Custom backup location
    $(basename "$0") --output /mnt/external/backups

    # Use bzip2 compression (slower, better compression)
    $(basename "$0") --compress bzip2

    # Use xz compression (slowest, best compression)
    $(basename "$0") --compress xz

    # No compression (faster, larger files)
    $(basename "$0") --compress none

Backup Location:
    Default: ${BACKUP_DIR}/village-data-YYYYMMDD-HHMMSS.tar.gz

What Gets Backed Up:
    - Data directory: ${DATA_DIR}
    - Config file (if --include-config): ${CONFIG_FILE}

What Does NOT Get Backed Up:
    - Log files (${LOGS_DIR}) - can be large and are regenerated
    - Docker images - can be rebuilt from Dockerfile
    - Application code - tracked in git

Restoration:
    # Stop the container first
    ./stop.sh

    # Extract backup
    sudo tar -xzf ${BACKUP_DIR}/village-data-YYYYMMDD-HHMMSS.tar.gz -C /

    # If you backed up config too, it will restore to ${CONFIG_FILE}

    # Verify ownership is correct
    ./setup.sh  # This will fix ownership if needed

    # Start container
    ./start.sh

Security Note:
    If using --include-config, the backup will contain secrets (FLASK_SECRET_KEY).
    Store these backups securely and restrict permissions!

Exit Codes:
    0 - Backup successful
    1 - Backup failed (directory doesn't exist, permission denied, etc.)

EOF
}

# Parse arguments
INCLUDE_CONFIG=false
BACKUP_OUTPUT_DIR="${BACKUP_DIR}"
COMPRESS_TYPE="gzip"
VERIFY=true

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
    error "Run: ./run-script.sh initialize-repository"
    exit 1
fi

# Validate config file exists (if including it)
if [[ "$INCLUDE_CONFIG" == true ]] && [[ ! -f "$CONFIG_FILE" ]]; then
    error "ERROR: Configuration file does not exist: ${CONFIG_FILE}"
    error ""
    error "Cannot include config in backup because it doesn't exist."
    error "Either create the config file or remove --include-config flag."
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

# Determine backup filename
BACKUP_FILENAME="village-data-${TIMESTAMP}.tar${COMPRESS_EXT}"
BACKUP_PATH="${BACKUP_OUTPUT_DIR}/${BACKUP_FILENAME}"

# Build tar command
TAR_CMD="sudo tar -c${COMPRESS_FLAG}f"

info "===== Village Backup ====="
info "Backup location: ${BACKUP_PATH}"
info "Compression: ${COMPRESS_TYPE}"
info "Including config: ${INCLUDE_CONFIG}"
echo ""

# Check if container is running
if docker ps --format '{{.Names}}' | grep -q "^${CONTAINER_NAME}$"; then
    warn "WARNING: Container is currently running"
    warn "For best results, stop the container before backing up:"
    warn "  ./stop.sh"
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
    # Backup both data and config
    $TAR_CMD "$BACKUP_PATH" \
        -C / \
        "${DATA_DIR#/}" \
        "${CONFIG_FILE#/}" \
        2>&1 | grep -v "Removing leading" || true
else
    # Backup only data
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
        # For compressed archives, test extraction
        if sudo tar -t${COMPRESS_FLAG}f "$BACKUP_PATH" > /dev/null 2>&1; then
            info "✓ Backup verification passed"
        else
            error "ERROR: Backup verification failed!"
            error "The backup file may be corrupted."
            exit 1
        fi
    else
        # For uncompressed archives
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
info "     ./stop.sh"
info ""
info "  2. Extract the backup:"
info "     sudo tar -x${COMPRESS_FLAG}f ${BACKUP_PATH} -C /"
info ""
info "  3. Fix ownership (if needed):"
info "     cd ${REPO_DIR}/village_docker/scripts"
info "     ./setup.sh"
info ""
info "  4. Start the container:"
info "     ./start.sh"
echo ""

# Show next steps
info "===== Backup Complete ====="
info "Backup saved to: ${BACKUP_PATH}"
info ""
info "Next steps:"
info "  - Test restoration on a different machine to verify backup works"
info "  - Store backup in a safe location (off-site, cloud storage, etc.)"
info "  - Consider automating backups with a cron job"
info "  - Clean up old backups periodically to save space"
echo ""

exit 0
