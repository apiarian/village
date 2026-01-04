#!/bin/bash
# Setup script for village_py deployment on Fedora

set -e

echo "Village deployment setup script"
echo "==============================="
echo ""
echo "This script expects to be run from within the village repository"
echo "or from the village_py_deployment subdirectory."
echo ""

# Check if running as root
if [[ $EUID -eq 0 ]]; then
   echo "This script should not be run as root. Please run as a regular user with sudo privileges."
   exit 1
fi

# Get the directory where the script is located
SCRIPT_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"

# Configuration
VILLAGE_USER="village"
VILLAGE_HOME="/opt/village"
VILLAGE_REPO_DIR="$VILLAGE_HOME/village"
VILLAGE_PY_DIR="$VILLAGE_REPO_DIR/village_py"
VILLAGE_DATA_DIR="$VILLAGE_HOME/data"
VILLAGE_VENV_DIR="$VILLAGE_HOME/venv"

echo "1. Installing system dependencies..."
sudo dnf install -y python3.11 python3.11-devel python3-pip git

echo "2. Creating village user and directories..."
if ! id "$VILLAGE_USER" &>/dev/null; then
    sudo useradd -r -s /bin/bash -m -d "$VILLAGE_HOME" "$VILLAGE_USER"
fi

# Create necessary directories
sudo mkdir -p "$VILLAGE_DATA_DIR"
sudo mkdir -p "$VILLAGE_HOME/logs"

echo "3. Setting up Python virtual environment..."
sudo -u "$VILLAGE_USER" python3.11 -m venv "$VILLAGE_VENV_DIR"

echo "4. Installing poetry in virtual environment..."
sudo -u "$VILLAGE_USER" "$VILLAGE_VENV_DIR/bin/pip" install --upgrade pip setuptools wheel
sudo -u "$VILLAGE_USER" "$VILLAGE_VENV_DIR/bin/pip" install poetry

echo "5. Setting up village repository..."
# Check if we're in a git repository and get the remote URL
if [ -d ".git" ]; then
    # We're in the village repository
    REPO_URL=$(git config --get remote.origin.url)
    CURRENT_DIR=$(pwd)
else
    echo "ERROR: Could not find village git repository!"
    echo "Please run this script from within the village repository."
    exit 1
fi

echo "Found repository: $REPO_URL"

if [ ! -d "$VILLAGE_REPO_DIR" ]; then
    echo "Cloning repository to $VILLAGE_REPO_DIR..."
    sudo -u "$VILLAGE_USER" git clone "$REPO_URL" "$VILLAGE_REPO_DIR"
else
    echo "Repository already exists at $VILLAGE_REPO_DIR"
    echo "Updating to latest changes..."
    sudo -u "$VILLAGE_USER" bash -c "cd $VILLAGE_REPO_DIR && git fetch && git pull"
fi

echo "6. Installing Python dependencies..."
sudo -u "$VILLAGE_USER" bash -c "cd $VILLAGE_PY_DIR && $VILLAGE_VENV_DIR/bin/poetry install --no-dev"

echo "7. Setting up environment configuration..."
sudo cp "$SCRIPT_DIR/village.env" "/etc/village.env"
sudo chown root:root /etc/village.env
sudo chmod 600 /etc/village.env
echo "IMPORTANT: Edit /etc/village.env to configure your environment variables"

echo "8. Installing systemd service..."
sudo cp "$SCRIPT_DIR/village.service" /etc/systemd/system/
sudo systemctl daemon-reload

echo "9. Setting up log rotation..."
sudo cp "$SCRIPT_DIR/village-logrotate" /etc/logrotate.d/village

echo "10. Setting file permissions..."
sudo chown -R "$VILLAGE_USER:$VILLAGE_USER" "$VILLAGE_HOME"
sudo chmod 750 "$VILLAGE_HOME"
sudo chmod 750 "$VILLAGE_DATA_DIR"

echo ""
echo "Setup complete! Next steps:"
echo "1. Edit /etc/village.env to configure your environment variables"
echo "2. Initialize the village repository:"
echo "   sudo -u $VILLAGE_USER bash -c 'cd $VILLAGE_PY_DIR && $VILLAGE_VENV_DIR/bin/poetry run initialize-repository'"
echo "3. Create initial users:"
echo "   sudo -u $VILLAGE_USER bash -c 'cd $VILLAGE_PY_DIR && $VILLAGE_VENV_DIR/bin/poetry run create-user'"
echo "4. Start the service:"
echo "   sudo systemctl enable --now village.service"
echo ""
echo "Note: This setup assumes cloudflared is already configured to proxy to http://127.0.0.1:8000"
