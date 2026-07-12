#!/usr/bin/env bash
# Start the Minecraft fleet with clean state.
# Usage: ./start.sh [proxy|survival|creative|modded|insane|all]
# Default: starts proxy, then all backends.
#
# Each start: stops existing container (if running), resets failed state,
# then starts fresh. No data loss — world data is in ~/minecraft/<instance>/
# which persists across container lifecycle. Containers are ephemeral (--rm).
#
# Service naming:
#   Vanilla worlds use the template: minecraft@survival.service, minecraft@creative.service
#   NeoForge worlds use explicit units: minecraft-modded.service, minecraft-insane.service
set -euo pipefail

TARGET="${1:-all}"

FAILURES=0

start_service() {
    local unit="$1"
    echo "=== ${unit} ==="
    systemctl --user stop "${unit}" 2>/dev/null || true
    systemctl --user reset-failed "${unit}" 2>/dev/null || true
    if ! systemctl --user start "${unit}"; then
        echo "  FAILED to start ${unit}"
        FAILURES=$((FAILURES + 1))
        return
    fi
    echo "  Started. Waiting for initial output..."
    sleep 5
    systemctl --user status "${unit}" --no-pager --lines=5
    echo ""
}

case "${TARGET}" in
    proxy)
        start_service minecraft-proxy.service
        ;;
    survival|creative)
        start_service "minecraft@${TARGET}.service"
        ;;
    modded)
        start_service minecraft-modded.service
        ;;
    insane)
        start_service minecraft-insane.service
        ;;
    all)
        start_service minecraft-proxy.service
        start_service minecraft@survival.service
        start_service minecraft@creative.service
        start_service minecraft-modded.service
        start_service minecraft-insane.service
        ;;
    *)
        echo "Usage: $0 [proxy|survival|creative|modded|insane|all]"
        exit 1
        ;;
esac

echo "=== Fleet Status ==="
systemctl --user list-units "minecraft*" --no-pager --no-legend
exit "${FAILURES}"
