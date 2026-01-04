#!/bin/bash
# Firewall configuration for Village.py deployment

set -e

echo "Configuring firewall for Village..."
echo "=================================="

# Check if running as root
if [[ $EUID -ne 0 ]]; then
   echo "This script must be run as root or with sudo"
   exit 1
fi

# Enable firewalld if not already enabled
if ! systemctl is-active --quiet firewalld; then
    echo "Enabling firewalld..."
    systemctl enable --now firewalld
fi

echo "Current firewall status:"
firewall-cmd --list-all

echo ""
echo "Configuring firewall rules..."

# Create a new zone for internal services
firewall-cmd --permanent --new-zone=village-internal 2>/dev/null || echo "Zone village-internal already exists"

# Configure the village-internal zone
# Only allow localhost to connect to port 8000
firewall-cmd --permanent --zone=village-internal --add-source=127.0.0.1/32
firewall-cmd --permanent --zone=village-internal --add-port=8000/tcp

# Ensure the default zone doesn't expose port 8000
firewall-cmd --permanent --zone=public --remove-port=8000/tcp 2>/dev/null || true

# If you need SSH access, ensure it's allowed
firewall-cmd --permanent --zone=public --add-service=ssh

# Reload firewall to apply changes
firewall-cmd --reload

echo ""
echo "Firewall configuration complete!"
echo ""
echo "Current configuration:"
echo "- Port 8000 is only accessible from localhost (for reverse proxy)"
echo "- SSH is allowed from public zone"
echo "- No direct external access to Village"
echo ""
echo "To check firewall status:"
echo "  sudo firewall-cmd --list-all-zones"