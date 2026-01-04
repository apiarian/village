#!/bin/bash
# Health check script for Village.py deployment

set -e

echo "Village Health Check"
echo "===================="
echo ""

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

# Function to check service status
check_service() {
    local service=$1
    if systemctl is-active --quiet "$service"; then
        echo -e "${GREEN}✓${NC} $service is running"
        return 0
    else
        echo -e "${RED}✗${NC} $service is not running"
        return 1
    fi
}

# Function to check port
check_port() {
    local port=$1
    local service=$2
    if ss -tuln | grep -q ":$port "; then
        echo -e "${GREEN}✓${NC} Port $port is listening ($service)"
        return 0
    else
        echo -e "${RED}✗${NC} Port $port is not listening ($service)"
        return 1
    fi
}

# Function to check HTTP response
check_http() {
    local url=$1
    local name=$2
    
    response=$(curl -s -o /dev/null -w "%{http_code}" "$url" 2>/dev/null || echo "000")
    
    if [[ "$response" == "200" ]] || [[ "$response" == "302" ]]; then
        echo -e "${GREEN}✓${NC} $name is responding (HTTP $response)"
        return 0
    else
        echo -e "${RED}✗${NC} $name is not responding properly (HTTP $response)"
        return 1
    fi
}

# Check services
echo "Service Status:"
echo "--------------"
check_service "village.service"
echo ""

# Check ports
echo "Port Status:"
echo "-----------"
check_port 8000 "Village"
echo ""

# Check HTTP endpoints
echo "HTTP Endpoints:"
echo "--------------"
check_http "http://127.0.0.1:8000/" "Village local"
echo ""

# Check disk space
echo "Disk Space:"
echo "----------"
df -h /opt/village | awk 'NR==2 {
    used_percent = $5;
    gsub("%", "", used_percent);
    if (used_percent > 90) 
        printf "\033[0;31m✗\033[0m";
    else if (used_percent > 80)
        printf "\033[1;33m⚠\033[0m";
    else
        printf "\033[0;32m✓\033[0m";
    printf " /opt/village: %s used (Available: %s)\n", $5, $4
}'
echo ""

# Check logs for errors
echo "Recent Errors (last 24 hours):"
echo "-----------------------------"
ERROR_COUNT=$(journalctl -u village.service --since "24 hours ago" 2>/dev/null | grep -i error | wc -l)
if [ $ERROR_COUNT -eq 0 ]; then
    echo -e "${GREEN}✓${NC} No errors in Village logs"
else
    echo -e "${YELLOW}⚠${NC} Found $ERROR_COUNT error(s) in Village logs"
    echo "  Run 'sudo journalctl -u village.service --since \"24 hours ago\" | grep -i error' to view"
fi

echo ""

# Check configuration files
echo "Configuration Files:"
echo "-------------------"
if [ -f "/etc/village.env" ]; then
    perms=$(stat -c "%a" "/etc/village.env")
    if [ "$perms" == "600" ]; then
        echo -e "${GREEN}✓${NC} /etc/village.env exists with correct permissions ($perms)"
    else
        echo -e "${YELLOW}⚠${NC} /etc/village.env exists but has permissions $perms (should be 600)"
    fi
else
    echo -e "${RED}✗${NC} /etc/village.env is missing"
fi
echo ""

# Memory usage
echo "Memory Usage:"
echo "------------"
VILLAGE_PID=$(systemctl show -p MainPID village.service | cut -d= -f2)
if [ "$VILLAGE_PID" != "0" ]; then
    VILLAGE_MEM=$(ps -p "$VILLAGE_PID" -o %mem= 2>/dev/null | xargs)
    echo "Village process: ${VILLAGE_MEM}% of system memory"
else
    echo "Village process not found"
fi

# System load
echo ""
echo "System Load:"
echo "-----------"
uptime | awk -F'load average:' '{print "Load average:" $2}'

# Summary
echo ""
echo "Summary:"
echo "--------"
ISSUES=0

systemctl is-active --quiet village.service || ((ISSUES++))
[ -f /etc/village.env ] || ((ISSUES++))

if [ $ISSUES -eq 0 ]; then
    echo -e "${GREEN}✓ All systems operational${NC}"
else
    echo -e "${RED}✗ Found $ISSUES issue(s) that need attention${NC}"
fi