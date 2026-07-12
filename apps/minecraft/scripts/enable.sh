#!/usr/bin/env bash
# Enable and start Minecraft fleet services.
# Usage: ./enable.sh [proxy|survival|creative|modded|insane|all] [--force]
#
# Reads fleet configuration from .env.example (defaults) then .env (overrides).
# FLEET_SURVIVAL, FLEET_CREATIVE, FLEET_MODDED, FLEET_INSANE control which
# worlds are started when invoked with "all". Individual targets ignore the
# FLEET_* flags and start unconditionally.
#
# On success: reports loaded plugins/mods, startup duration, health, memory.
# On failure: reports which stage failed, dumps journal, lists installed artifacts.
set -euxo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
APP_DIR="$(dirname "$SCRIPT_DIR")"

# Source fleet config: defaults first, then user overrides
set -a
[[ -f "${APP_DIR}/.env.example" ]] && . "${APP_DIR}/.env.example"
[[ -f "${APP_DIR}/.env" ]] && . "${APP_DIR}/.env"
set +a

TARGET="${1:-all}"
FORCE=false
[[ "${2:-}" == "--force" || "${1:-}" == "--force" ]] && FORCE=true
[[ "${1:-}" == "--force" ]] && TARGET="all"
FAILURES=0
STARTUP_TIMEOUT="${FLEET_STARTUP_TIMEOUT:-180}"
POLL_INTERVAL="${FLEET_POLL_INTERVAL:-5}"

# --force: kill all containers immediately, skip graceful stop
if [[ "$FORCE" == "true" ]]; then
    echo "[$(ts)] === FORCE: killing all containers ==="
    podman kill --all 2>/dev/null || true
    podman rm -f --all 2>/dev/null || true
    systemctl --user reset-failed 2>/dev/null || true
    echo "  All containers killed"
fi

# Orphan units from prior naming schemes — always cleaned up
ORPHAN_SERVICES=(
    minecraft-modded-creative.service
    minecraft-modded-survival.service
)

ts() { date '+%H:%M:%S'; }

resolve_service() {
    case "$1" in
        proxy)             echo "minecraft-proxy.service" ;;
        survival|creative) echo "minecraft@${1}.service" ;;
        modded)            echo "minecraft-modded.service" ;;
        insane)            echo "minecraft-insane.service" ;;
        *) echo "Unknown target: $1" >&2; return 1 ;;
    esac
}

service_to_container() {
    echo "$1" | sed 's/\.service$//' | sed 's/@/-/'
}

service_to_datadir() {
    local svc="$1"
    case "$svc" in
        minecraft-proxy.service)    echo "${HOME}/minecraft/proxy" ;;
        minecraft@survival.service) echo "${HOME}/minecraft/survival" ;;
        minecraft@creative.service) echo "${HOME}/minecraft/creative" ;;
        minecraft-modded.service)   echo "${HOME}/minecraft/modded" ;;
        minecraft-insane.service)   echo "${HOME}/minecraft/insane" ;;
    esac
}

# Build the list of enabled backend services from FLEET_* vars
build_backend_services() {
    local services=()
    [[ "${FLEET_SURVIVAL:-false}" == "true" ]] && services+=(minecraft@survival.service)
    [[ "${FLEET_CREATIVE:-false}" == "true" ]] && services+=(minecraft@creative.service)
    [[ "${FLEET_MODDED:-false}" == "true" ]]   && services+=(minecraft-modded.service)
    [[ "${FLEET_INSANE:-false}" == "true" ]]   && services+=(minecraft-insane.service)
    echo "${services[@]}"
}

# Build the list of disabled backend services (to stop if running)
build_disabled_services() {
    local services=()
    [[ "${FLEET_SURVIVAL:-false}" != "true" ]] && services+=(minecraft@survival.service)
    [[ "${FLEET_CREATIVE:-false}" != "true" ]] && services+=(minecraft@creative.service)
    [[ "${FLEET_MODDED:-false}" != "true" ]]   && services+=(minecraft-modded.service)
    [[ "${FLEET_INSANE:-false}" != "true" ]]   && services+=(minecraft-insane.service)
    echo "${services[@]}"
}

dump_failure() {
    local svc="$1"
    local datadir
    datadir=$(service_to_datadir "$svc")
    echo ""
    echo "!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!"
    echo "  [$(ts)] FAILED: ${svc}"
    echo "!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!"
    echo ""
    echo "--- systemctl status ---"
    systemctl --user status "${svc}" --no-pager --lines=0 2>&1 || true
    echo ""
    echo "--- installed artifacts ---"
    if [[ -d "${datadir}/plugins" ]]; then
        echo "  plugins/:"
        ls -1 "${datadir}/plugins/"*.jar 2>/dev/null | while read -r f; do echo "    $(basename "$f")"; done
        [[ $(ls -1 "${datadir}/plugins/"*.jar 2>/dev/null | wc -l) -eq 0 ]] && echo "    (none)"
    fi
    if [[ -d "${datadir}/mods" ]]; then
        echo "  mods/:"
        ls -1 "${datadir}/mods/"*.jar 2>/dev/null | while read -r f; do echo "    $(basename "$f")"; done
        [[ $(ls -1 "${datadir}/mods/"*.jar 2>/dev/null | wc -l) -eq 0 ]] && echo "    (none)"
    fi
    echo ""
    echo "--- journal (last 80 lines) ---"
    journalctl --user -u "${svc}" --since "3 min ago" --no-pager 2>&1 | tail -80
    echo "!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!"
    echo ""
}

report_success() {
    local svc="$1"
    local container="$2"
    local elapsed="$3"
    local datadir
    datadir=$(service_to_datadir "$svc")

    echo "  [$(ts)] Stage 3: healthy — accepting connections (${elapsed}s)"
    echo ""

    if [[ -d "${datadir}/plugins" ]]; then
        local count
        count=$(ls -1 "${datadir}/plugins/"*.jar 2>/dev/null | wc -l)
        echo "  Plugins (${count}):"
        ls -1 "${datadir}/plugins/"*.jar 2>/dev/null | while read -r f; do echo "    $(basename "$f")"; done
    fi
    if [[ -d "${datadir}/mods" ]]; then
        local count
        count=$(ls -1 "${datadir}/mods/"*.jar 2>/dev/null | wc -l)
        echo "  Mods (${count}):"
        ls -1 "${datadir}/mods/"*.jar 2>/dev/null | while read -r f; do echo "    $(basename "$f")"; done
    fi

    local mem
    mem=$(podman stats --no-stream --format '{{.MemUsage}}' "$container" 2>/dev/null || echo "unknown")
    echo "  Memory: ${mem}"
    echo ""
}

start_and_verify() {
    local svc="$1"
    local container
    container=$(service_to_container "$svc")
    local start_time
    start_time=$(date +%s)

    echo "=== ${svc} ==="

    echo "  [$(ts)] Stopping previous instance..."
    systemctl --user stop "${svc}" 2>/dev/null || true
    systemctl --user reset-failed "${svc}" 2>/dev/null || true

    echo "  [$(ts)] Stage 1: starting systemd unit..."
    if ! systemctl --user start "${svc}"; then
        echo "  [$(ts)] STAGE 1 FAILED: systemd could not start the unit"
        dump_failure "$svc"
        FAILURES=$((FAILURES + 1))
        return 1
    fi
    echo "  [$(ts)] Stage 1: unit started, container created"

    local elapsed=0
    local jvm_seen=false

    while [[ $elapsed -lt $STARTUP_TIMEOUT ]]; do
        if ! systemctl --user is-active "${svc}" &>/dev/null; then
            local now
            now=$(date +%s)
            elapsed=$((now - start_time))
            echo "  [$(ts)] STAGE 2 FAILED: service died after ${elapsed}s"
            dump_failure "$svc"
            FAILURES=$((FAILURES + 1))
            return 1
        fi

        if [[ "$jvm_seen" == "false" ]]; then
            if podman exec "$container" pgrep -f "java\|velocity" &>/dev/null 2>&1; then
                local now
                now=$(date +%s)
                elapsed=$((now - start_time))
                echo "  [$(ts)] Stage 2: JVM process running (${elapsed}s)"
                jvm_seen=true
            fi
        fi

        local health
        health=$(podman inspect --format '{{.State.Health.Status}}' "$container" 2>/dev/null || echo "none")

        if [[ "$health" == "healthy" ]]; then
            local now
            now=$(date +%s)
            elapsed=$((now - start_time))
            report_success "$svc" "$container" "$elapsed"
            return 0
        fi

        sleep "$POLL_INTERVAL"
    done

    local now
    now=$(date +%s)
    elapsed=$((now - start_time))
    local health_final
    health_final=$(podman inspect --format '{{.State.Health.Status}}' "$container" 2>/dev/null || echo "none")
    echo "  [$(ts)] TIMEOUT after ${elapsed}s (health=${health_final}, jvm=${jvm_seen})"

    if [[ "$jvm_seen" == "false" ]]; then
        echo "  Root cause: JVM never started — check env vars, image pull, init errors"
    elif [[ "$health_final" == "starting" ]]; then
        echo "  Root cause: JVM running but not yet accepting connections — slow startup or plugin error"
    else
        echo "  Root cause: health=${health_final} — check RCON, health check, or server crash"
    fi

    dump_failure "$svc"
    FAILURES=$((FAILURES + 1))
    return 1
}

case "${TARGET}" in
    proxy|survival|creative|modded|insane)
        svc=$(resolve_service "${TARGET}")
        start_and_verify "${svc}"
        ;;
    all)
        echo "[$(ts)] === Fleet configuration ==="
        echo "  FLEET_SURVIVAL=${FLEET_SURVIVAL:-false}"
        echo "  FLEET_CREATIVE=${FLEET_CREATIVE:-false}"
        echo "  FLEET_MODDED=${FLEET_MODDED:-false}"
        echo "  FLEET_INSANE=${FLEET_INSANE:-false}"
        echo ""

        # Clean up orphan units from prior naming schemes
        echo "[$(ts)] === Cleaning orphan units ==="
        for orphan in "${ORPHAN_SERVICES[@]}"; do
            systemctl --user stop "${orphan}" 2>/dev/null || true
            systemctl --user disable "${orphan}" 2>/dev/null || true
        done

        # Stop disabled services that may be running from a prior config
        read -ra DISABLED_SERVICES <<< "$(build_disabled_services)"
        if [[ ${#DISABLED_SERVICES[@]} -gt 0 ]]; then
            echo "[$(ts)] === Stopping disabled services ==="
            for svc in "${DISABLED_SERVICES[@]}"; do
                systemctl --user stop "${svc}" 2>/dev/null || true
                echo "  Stopped: ${svc}"
            done
        fi

        # Build enabled service list
        read -ra BACKEND_SERVICES <<< "$(build_backend_services)"
        ALL_SERVICES=(minecraft-proxy.service "${BACKEND_SERVICES[@]}")

        echo "[$(ts)] === Stopping enabled services ==="
        systemctl --user stop "${ALL_SERVICES[@]}" 2>/dev/null || true
        systemctl --user reset-failed 2>/dev/null || true
        echo ""

        start_and_verify minecraft-proxy.service || echo "  Proxy failed — continuing with backends"
        echo ""

        for svc in "${BACKEND_SERVICES[@]}"; do
            start_and_verify "${svc}" || true
            echo ""
        done

        echo "[$(ts)] === Fleet Status ==="
        podman ps --all --format "table {{.Names}}\t{{.Image}}\t{{.Status}}"
        echo ""
        systemctl --user list-units "minecraft*" --no-pager --no-legend

        if [[ "$FAILURES" -gt 0 ]]; then
            echo ""
            echo "[$(ts)] ${FAILURES} service(s) FAILED — review errors above"
        else
            echo ""
            echo "[$(ts)] All services healthy"
        fi
        ;;
    *)
        echo "Usage: $0 [proxy|survival|creative|modded|insane|all]"
        exit 1
        ;;
esac

exit "${FAILURES}"
