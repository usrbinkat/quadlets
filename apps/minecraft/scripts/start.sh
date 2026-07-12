#!/usr/bin/env bash
# Start the Minecraft fleet with clean state.
# Usage: ./start.sh [proxy|survival|creative|modded-survival|modded-creative|all]
# Default: starts proxy, then all backends.
#
# Each start: stops existing container (if running), resets failed state,
# then starts fresh. No data loss — world data is in ~/minecraft/<instance>/
# which persists across container lifecycle. Containers are ephemeral (--rm).
#
# Service naming:
#   Vanilla worlds use the template: minecraft@survival.service, minecraft@creative.service
#   Modded worlds use explicit units: minecraft-modded-survival.service, minecraft-modded-creative.service
#   (Podman 5.8 does not support Image= override in template drop-ins)
set -euo pipefail

TARGET="${1:-all}"

start_service() {
    local unit="$1"
    echo "=== ${unit} ==="
    systemctl --user stop "${unit}" 2>/dev/null || true
    systemctl --user reset-failed "${unit}" 2>/dev/null || true
    systemctl --user start "${unit}"
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
    modded-survival)
        start_service minecraft-modded-survival.service
        ;;
    modded-creative)
        start_service minecraft-modded-creative.service
        ;;
    all)
        start_service minecraft-proxy.service
        start_service minecraft@survival.service
        start_service minecraft@creative.service
        start_service minecraft-modded-survival.service
        start_service minecraft-modded-creative.service
        ;;
    *)
        echo "Usage: $0 [proxy|survival|creative|modded-survival|modded-creative|all]"
        exit 1
        ;;
esac

echo "=== Fleet Status ==="
systemctl --user list-units "minecraft*" --no-pager --no-legend
