#!/bin/bash

# Run a backup on a remote village server, then fetch it to ~/village-backups
# on your local machine.
#
# Usage: ./fetch-backups.sh <ssh-host> <instance>
#
# Example: ./fetch-backups.sh user@myserver.com group-b
#          ./fetch-backups.sh village-prod group-b

set -e

if [ -z "$1" ] || [ -z "$2" ]; then
    echo "Usage: $0 <ssh-host> <instance>"
    echo "Example: $0 user@myserver.com group-b"
    exit 1
fi

SSH_HOST="$1"
INSTANCE="$2"
REMOTE_BASE="/opt/village"
REMOTE_BACKUPS="${REMOTE_BASE}/instances/${INSTANCE}/backups/*.tar.gz"
LOCAL_DIR="$HOME/village-backups"

mkdir -p "$LOCAL_DIR"

# --- Step 1: Run backup on the remote server ---
echo "===== Running backup for instance: $INSTANCE ====="
ssh "$SSH_HOST" "cd ${REMOTE_BASE}/village/village_docker && sudo bash scripts/backup.sh --instance $INSTANCE --yes"
echo ""

# --- Step 2: Fetch backups ---
echo "Fetching backups from $SSH_HOST ..."

rsync -avz --progress \
    "$SSH_HOST:$REMOTE_BACKUPS" \
    "$LOCAL_DIR/"

echo ""
echo "Done. Backups saved to $LOCAL_DIR/"
ls -lh "$LOCAL_DIR/"
