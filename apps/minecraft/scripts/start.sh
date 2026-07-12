#!/usr/bin/env bash
# Start the Minecraft fleet with clean state.
# Usage: ./start.sh [proxy|survival|creative|modded|insane|all]
# Default: starts proxy first, then all backends in parallel.
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

BACKEND_SERVICES=(
    minecraft@survival.service
    minecraft@creative.service
    minecraft-modded.service
    minecraft-insane.service
)

ALL_SERVICES=(
    minecraft-proxy.service
    "${BACKEND_SERVICES[@]}"
)

resolve_service() {
    case "$1" in
        proxy)            echo "minecraft-proxy.service" ;;
        survival|creative) echo "minecraft@${1}.service" ;;
        modded)           echo "minecraft-modded.service" ;;
        insane)           echo "minecraft-insane.service" ;;
        *) return 1 ;;
    esac
}

start_single() {
    local svc="$1"
    echo "=== ${svc} ==="
    systemctl --user stop "${svc}" 2>/dev/null || true
    systemctl --user reset-failed "${svc}" 2>/dev/null || true
    if ! systemctl --user start "${svc}"; then
        echo "  FAILED to start ${svc}"
        return 1
    fi
    echo "  Started."
}

case "${TARGET}" in
    proxy|survival|creative|modded|insane)
        svc=$(resolve_service "${TARGET}")
        start_single "${svc}"
        sleep 5
        systemctl --user status "${svc}" --no-pager --lines=5
        ;;
    all)
        echo "=== Stopping fleet ==="
        systemctl --user stop "${ALL_SERVICES[@]}" 2>/dev/null || true
        systemctl --user reset-failed 2>/dev/null || true

        echo "=== Starting proxy ==="
        systemctl --user start minecraft-proxy.service
        sleep 5

        echo "=== Starting backends (parallel) ==="
        systemctl --user start "${BACKEND_SERVICES[@]}" || echo "  WARNING: one or more backends failed initial start (will retry via systemd)"

        echo "=== Waiting for health checks (120s) ==="
        sleep 120

        echo ""
        echo "=== Fleet Status ==="
        podman ps --all --format "table {{.Names}}\t{{.Image}}\t{{.Status}}"
        echo ""
        systemctl --user list-units "minecraft*" --no-pager --no-legend
        ;;
    *)
        echo "Usage: $0 [proxy|survival|creative|modded|insane|all]"
        exit 1
        ;;
esac
