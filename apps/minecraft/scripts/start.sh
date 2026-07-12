#!/usr/bin/env bash
# Start the Minecraft fleet with clean state.
# Usage: ./start.sh [proxy|survival|creative|modded|insane|all]
#
# Every action is timestamped. Every condition is checked explicitly.
# On success: reports loaded plugins/mods, startup duration, health status.
# On failure: reports which stage failed, dumps journal logs, lists installed artifacts.
set -euxo pipefail

TARGET="${1:-all}"
FAILURES=0
STARTUP_TIMEOUT=180
POLL_INTERVAL=5

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

ts() { date '+%H:%M:%S'; }

resolve_service() {
    case "$1" in
        proxy)            echo "minecraft-proxy.service" ;;
        survival|creative) echo "minecraft@${1}.service" ;;
        modded)           echo "minecraft-modded.service" ;;
        insane)           echo "minecraft-insane.service" ;;
        *) return 1 ;;
    esac
}

service_to_container() {
    echo "$1" | sed 's/\.service$//' | sed 's/@/-/'
}

# Determine data directory for this service
service_to_datadir() {
    local svc="$1"
    case "$svc" in
        minecraft-proxy.service)       echo "${HOME}/minecraft/proxy" ;;
        minecraft@survival.service)    echo "${HOME}/minecraft/survival" ;;
        minecraft@creative.service)    echo "${HOME}/minecraft/creative" ;;
        minecraft-modded.service)      echo "${HOME}/minecraft/modded" ;;
        minecraft-insane.service)      echo "${HOME}/minecraft/insane" ;;
    esac
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

    # Report loaded artifacts
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

    # Memory
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

    # Stop any previous instance
    echo "  [$(ts)] Stopping previous instance..."
    systemctl --user stop "${svc}" 2>/dev/null || true
    systemctl --user reset-failed "${svc}" 2>/dev/null || true

    # Stage 1: systemd start (container creation)
    echo "  [$(ts)] Stage 1: starting systemd unit..."
    if ! systemctl --user start "${svc}"; then
        echo "  [$(ts)] STAGE 1 FAILED: systemd could not start the unit"
        dump_failure "$svc"
        FAILURES=$((FAILURES + 1))
        return 1
    fi
    echo "  [$(ts)] Stage 1: unit started, container created"

    # Stage 2+3: poll for JVM process and health
    local elapsed=0
    local jvm_seen=false

    while [[ $elapsed -lt $STARTUP_TIMEOUT ]]; do
        # Check unit still alive
        if ! systemctl --user is-active "${svc}" &>/dev/null; then
            local now
            now=$(date +%s)
            elapsed=$((now - start_time))
            echo "  [$(ts)] STAGE 2 FAILED: service died after ${elapsed}s"
            dump_failure "$svc"
            FAILURES=$((FAILURES + 1))
            return 1
        fi

        # Check JVM process inside container
        if [[ "$jvm_seen" == "false" ]]; then
            if podman exec "$container" pgrep -f "java\|velocity" &>/dev/null 2>&1; then
                local now
                now=$(date +%s)
                elapsed=$((now - start_time))
                echo "  [$(ts)] Stage 2: JVM process running (${elapsed}s)"
                jvm_seen=true
            fi
        fi

        # Check container health status
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

    # Timeout
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
        echo "[$(ts)] === Stopping fleet ==="
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
