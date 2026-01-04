#!/bin/bash
# Maintenance script for Village.py deployment

set -e

echo "Village Maintenance Script"
echo "=========================="

# Configuration
VILLAGE_USER="village"
VILLAGE_HOME="/opt/village"
VILLAGE_REPO_DIR="$VILLAGE_HOME/village"
VILLAGE_PY_DIR="$VILLAGE_REPO_DIR/village_py"
VILLAGE_VENV_DIR="$VILLAGE_HOME/venv"

# Check if running with sudo
if [[ $EUID -ne 0 ]]; then
   echo "This script must be run with sudo"
   exit 1
fi

# Function to safely restart a service
restart_service() {
    local service=$1
    echo "Restarting $service..."
    systemctl restart "$service"
    sleep 2
    if systemctl is-active --quiet "$service"; then
        echo "$service restarted successfully"
    else
        echo "ERROR: $service failed to restart!"
        systemctl status "$service"
        return 1
    fi
}

echo "1. Stopping village service..."
systemctl stop village.service

echo "2. Creating backup of data directory..."
BACKUP_DIR="$VILLAGE_HOME/backups"
mkdir -p "$BACKUP_DIR"
TIMESTAMP=$(date +%Y%m%d_%H%M%S)
tar -czf "$BACKUP_DIR/village_data_$TIMESTAMP.tar.gz" -C "$VILLAGE_HOME" data
echo "Backup saved to $BACKUP_DIR/village_data_$TIMESTAMP.tar.gz"

# Keep only last 7 backups
echo "Cleaning old backups..."
ls -t "$BACKUP_DIR"/village_data_*.tar.gz | tail -n +8 | xargs -r rm

echo "3. Updating Village code..."
if ! sudo -u "$VILLAGE_USER" test -d "$VILLAGE_REPO_DIR"; then
    echo "ERROR: Village repository not found at $VILLAGE_REPO_DIR"
    exit 1
fi

cd "$VILLAGE_REPO_DIR"

# Get current branch
CURRENT_BRANCH=$(sudo -u "$VILLAGE_USER" git rev-parse --abbrev-ref HEAD)
echo "Current branch: $CURRENT_BRANCH"

sudo -u "$VILLAGE_USER" git fetch
LOCAL=$(sudo -u "$VILLAGE_USER" git rev-parse HEAD)
REMOTE=$(sudo -u "$VILLAGE_USER" git rev-parse @{u})

if [ "$LOCAL" = "$REMOTE" ]; then
    echo "Village is already up to date"
else
    echo "Pulling latest changes..."
    sudo -u "$VILLAGE_USER" git pull
    
    echo "4. Updating Python dependencies..."
    pushd "$VILLAGE_PY_DIR"
    sudo -u "$VILLAGE_USER" "$VILLAGE_VENV_DIR/bin/poetry" install
    popd
fi

echo "5. Checking configuration files..."
if [ ! -f "/etc/village.env" ]; then
    echo "ERROR: /etc/village.env not found!"
    exit 1
fi

echo "6. Setting correct permissions..."
chown -R "$VILLAGE_USER:$VILLAGE_USER" "$VILLAGE_HOME"
chmod 750 "$VILLAGE_HOME"
chmod -R 750 "$VILLAGE_HOME/data"
chmod -R 640 "$VILLAGE_HOME/logs"/*.log 2>/dev/null || true

echo "7. Starting service..."
restart_service "village.service"

echo "8. Running health check..."
sleep 5
if curl -s -o /dev/null -w "%{http_code}" http://127.0.0.1:8000/ | grep -q "200\|302"; then
    echo "✓ Village is responding correctly"
else
    echo "✗ WARNING: Village is not responding as expected"
    echo "Check logs: sudo journalctl -u village.service -n 50"
fi

echo ""
echo "Maintenance complete!"
echo ""
echo "Summary:"
echo "- Backup created: $BACKUP_DIR/village_data_$TIMESTAMP.tar.gz"
echo "- Village version: $(cd $VILLAGE_REPO_DIR && sudo -u $VILLAGE_USER git rev-parse --short HEAD)"
echo "- Service status:"
systemctl is-active village.service >/dev/null && echo "  ✓ village.service: active" || echo "  ✗ village.service: inactive"
