#!/bin/bash
# check-and-fix-obs.sh - Check and fix OBS service issues
# Usage: ./check-and-fix-obs.sh

set -e

OBS_CONTAINER="obs-server-test"
OBS_API_URL="http://localhost:4455"
OBS_USER="Admin"
OBS_PASSWORD="admin123"

echo "=========================================="
echo "OBS Service Health Check and Auto-Repair"
echo "=========================================="
echo "Time: $(date)"
echo ""

# Function: Check OBS API
check_obs_api() {
    local response
    response=$(curl -s -o /dev/null -w "%{http_code}" "$OBS_API_URL/source/home:Admin/_meta" \
        --user "$OBS_USER:$OBS_PASSWORD" 2>/dev/null || echo "000")
    echo "$response"
}

# Function: Check OBS processes
check_obs_processes() {
    local count
    count=$(docker exec $OBS_CONTAINER ps aux 2>/dev/null | grep -E "bs_srcserver|bs_repserver|bs_sched|bs_worker" | wc -l)
    echo "$count"
}

# Function: Start OBS services
start_obs_services() {
    echo "Starting OBS services..."
    docker exec $OBS_CONTAINER /start-obs.sh 2>/dev/null || true
    sleep 5
}

echo "=== [1/4] Checking OBS container status ==="
if ! docker ps | grep -q $OBS_CONTAINER; then
    echo "OBS container not running, attempting to start..."
    docker start $OBS_CONTAINER
    sleep 10
fi
echo "OBS container running"

echo ""
echo "=== [2/4] Checking OBS process count ==="
PROCESS_COUNT=$(check_obs_processes)
echo "Current process count: $PROCESS_COUNT"

if [ "$PROCESS_COUNT" -lt 8 ]; then
    echo "Process count insufficient (need >= 8), starting services..."
    start_obs_services
    PROCESS_COUNT=$(check_obs_processes)
    echo "Process count after start: $PROCESS_COUNT"
fi

echo ""
echo "=== [3/4] Checking OBS API response ==="
HTTP_CODE=$(check_obs_api)
echo "API response code: $HTTP_CODE"

if [ "$HTTP_CODE" = "500" ] || [ "$HTTP_CODE" = "000" ]; then
    echo "OBS API abnormal, attempting repair..."
    
    # Fix: Restart container
    echo "Fix 1: Restarting OBS container..."
    docker restart $OBS_CONTAINER
    sleep 15
    
    # Start internal services
    echo "Starting internal services..."
    start_obs_services
    
    # Check again
    HTTP_CODE=$(check_obs_api)
    echo "API response code after fix: $HTTP_CODE"
fi

echo ""
echo "=== [4/4] Verifying OBS build capability ==="
BUILDING_COUNT=$(docker exec $OBS_CONTAINER ps aux 2>/dev/null | grep bs_sched | wc -l)
echo "Scheduler process count: $BUILDING_COUNT"

if [ "$BUILDING_COUNT" -lt 2 ]; then
    echo "Scheduler processes insufficient, attempting to start..."
    docker exec $OBS_CONTAINER bash -c "cd /usr/lib/obs/server && perl bs_sched x86_64 --daemonize & perl bs_sched aarch64 --daemonize &" 2>/dev/null || true
    sleep 3
fi

# Final status
echo ""
echo "=========================================="
echo "OBS Service Status Summary"
echo "=========================================="
FINAL_PROCESS=$(check_obs_processes)
FINAL_API=$(check_obs_api)

echo "Process count: $FINAL_PROCESS (need >= 8)"
echo "API status: $FINAL_API (need 200)"

if [ "$FINAL_PROCESS" -ge 8 ] && [ "$FINAL_API" = "200" ]; then
    echo ""
    echo "✅ OBS service healthy"
    exit 0
else
    echo ""
    echo "❌ OBS service unhealthy, manual intervention required"
    echo ""
    echo "Troubleshooting steps:"
    echo "1. docker logs $OBS_CONTAINER --tail 50"
    echo "2. docker exec $OBS_CONTAINER ps aux"
    echo "3. docker exec $OBS_CONTAINER cat /var/log/obs/*.log"
    exit 1
fi
