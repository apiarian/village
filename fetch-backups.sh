#!/bin/bash

# Fetch all instance backups from a remote village server to ~/village-backups
# on your local machine.
#
# Usage: ./fetch-backups.sh <ssh-host>
#
# Example: ./fetch-backups.sh user@myserver.com
#          ./fetch-backups.sh village-prod        (using ~/.ssh/config alias)

set -e

if [ -z "$1" ]; then
    echo "Usage: $0 <ssh-host>"
    echo "Example: $0 user@myserver.com"
    exit 1
fi

SSH_HOST="$1"
REMOTE_PATH="/opt/village/instances/*/backups/*.tar.gz"
LOCAL_DIR="$HOME/village-backups"

mkdir -p "$LOCAL_DIR"

echo "Fetching backups from $SSH_HOST ..."

rsync -avz --progress \
    "$SSH_HOST:$REMOTE_PATH" \
    "$LOCAL_DIR/"

echo ""
echo "Done. Backups saved to $LOCAL_DIR/"
ls -lh "$LOCAL_DIR/"
