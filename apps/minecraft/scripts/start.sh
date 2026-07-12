#!/usr/bin/env bash
# Start the Minecraft fleet and show status.
# Usage: ./start.sh [proxy|survival|creative|modded-survival|modded-creative|all]
# Default: starts proxy, then all backends.
set -euo pipefail

TARGET="${1:-all}"

start_and_watch() {
    local unit="$1"
    echo "=== Starting ${unit} ==="
    systemctl --user reset-failed "${unit}" 2>/dev/null || true
    systemctl --user start "${unit}"
    echo "  Started. Waiting 5s for initial logs..."
    sleep 5
    echo "--- Status ---"
    systemctl --user status "${unit}" --no-pager | head -15
    echo ""
}

case "${TARGET}" in
    proxy)
        start_and_watch minecraft-proxy.service
        ;;
    survival|creative|modded-survival|modded-creative)
        start_and_watch "minecraft@${TARGET}.service"
        ;;
    all)
        start_and_watch minecraft-proxy.service
        start_and_watch minecraft@survival.service
        start_and_watch minecraft@creative.service
        start_and_watch minecraft@modded-survival.service
        start_and_watch minecraft@modded-creative.service
        ;;
    *)
        echo "Usage: $0 [proxy|survival|creative|modded-survival|modded-creative|all]"
        exit 1
        ;;
esac

echo "=== Fleet Status ==="
systemctl --user list-units "minecraft*" --no-pager
