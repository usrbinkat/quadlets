#!/usr/bin/env bash
# Deploy the Minecraft quadlet fleet to the current user's systemd.
# Usage: ./deploy.sh [--generate-secret]
#
# Reads fleet configuration from .env.example (defaults) then .env (overrides).
# FLEET_* variables control which worlds are deployed, routed, and auto-started.
#
# Generates:
#   - velocity.toml from template (filtered by FLEET_* enablement)
#   - Quadlet drop-in files for memory (10-memory.conf), enablement (20-fleet.conf),
#     and anti-stampede restart stagger (30-restart.conf)
#   - minecraft.target in ~/.config/systemd/user/ (outside Quadlet search path)
#
# Podman 5.8.4 / systemd 259 / Fedora 44
set -euxo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
APP_DIR="$(dirname "$SCRIPT_DIR")"
SYSTEMD_DIR="${HOME}/.config/containers/systemd"
SYSTEMD_USER_DIR="${HOME}/.config/systemd/user"
PODMAN_VERSION="$(podman --version | awk '{print $3}')"

# Source fleet config: defaults first, then user overrides
set -a
[[ -f "${APP_DIR}/.env.example" ]] && . "${APP_DIR}/.env.example"
[[ -f "${APP_DIR}/.env" ]] && . "${APP_DIR}/.env"
set +a

echo "=== Minecraft Quadlet Fleet Deployment ==="
echo "Source: ${APP_DIR}"
echo "Target: ${SYSTEMD_DIR}"
echo "Podman: ${PODMAN_VERSION}"
echo ""
echo "Fleet:"
echo "  survival=${FLEET_SURVIVAL:-false}  creative=${FLEET_CREATIVE:-false}"
echo "  modded=${FLEET_MODDED:-false}    insane=${FLEET_INSANE:-false}"
echo ""

# --- Helper functions ---

memory_to_bytes() {
    local val="$1"
    local num="${val%[gGmM]*}"
    local unit="${val##*[0-9]}"
    case "$unit" in
        g|G) echo $(( num * 1073741824 )) ;;
        m|M) echo $(( num * 1048576 )) ;;
        *)   echo "$num" ;;
    esac
}

# --- Create directories ---

mkdir -p "${SYSTEMD_DIR}"
mkdir -p "${SYSTEMD_USER_DIR}"

echo "Creating data directories..."
for world in proxy survival creative modded insane; do
    mkdir -p "${HOME}/minecraft/${world}"
done
echo "  Created: ~/minecraft/{proxy,survival,creative,modded,insane}"

# --- Generate velocity.toml from template ---
# Includes only FLEET_*-enabled worlds in [servers] and [forced-hosts].
# The itzg/mc-proxy init copies /config/velocity.toml to /server/ on start
# and expands ${CFG_*} variables via REPLACE_ENV_VARIABLES=TRUE.

echo "Generating velocity.toml from template..."
rm -f "${HOME}/minecraft/proxy/velocity.toml"
rm -f "${HOME}/minecraft/proxy/forwarding.secret"
VELOCITY_TEMPLATE="${APP_DIR}/config/velocity.toml.template"
VELOCITY_OUTPUT="${APP_DIR}/config/velocity.toml"
{
    sed -n '1,/^\[servers\]$/p' "$VELOCITY_TEMPLATE"
    [[ "${FLEET_SURVIVAL:-false}" == "true" ]] && echo 'survival = "${CFG_SERVER_SURVIVAL}"'
    [[ "${FLEET_CREATIVE:-false}" == "true" ]] && echo 'creative = "${CFG_SERVER_CREATIVE}"'
    [[ "${FLEET_MODDED:-false}" == "true" ]]   && echo 'modded = "${CFG_SERVER_MODDED}"'
    [[ "${FLEET_INSANE:-false}" == "true" ]]   && echo 'insane = "${CFG_SERVER_INSANE}"'
    echo 'try = ["survival"]'
    echo ''
    echo '[forced-hosts]'
    [[ "${FLEET_SURVIVAL:-false}" == "true" ]] && echo '"${CFG_HOST_SURVIVAL}" = ["survival"]'
    [[ "${FLEET_CREATIVE:-false}" == "true" ]] && echo '"${CFG_HOST_CREATIVE}" = ["creative"]'
    [[ "${FLEET_MODDED:-false}" == "true" ]]   && echo '"${CFG_HOST_MODDED}" = ["modded"]'
    [[ "${FLEET_INSANE:-false}" == "true" ]]   && echo '"${CFG_HOST_INSANE}" = ["insane"]'
    echo ''
    sed -n '/^\[advanced\]$/,$p' "$VELOCITY_TEMPLATE"
} > "$VELOCITY_OUTPUT"
echo "  Generated: config/velocity.toml"

# --- Generate forwarding secret ---

if [[ "${1:-}" == "--generate-secret" ]] || [[ ! -f "${SYSTEMD_DIR}/minecraft-secrets.env" ]]; then
    echo "Generating forwarding secret..."
    bash "${SCRIPT_DIR}/generate-secret.sh" > "${SYSTEMD_DIR}/minecraft-secrets.env"
    chmod 0600 "${SYSTEMD_DIR}/minecraft-secrets.env"
    echo "  Written: ${SYSTEMD_DIR}/minecraft-secrets.env (0600)"
else
    echo "  Secret exists: ${SYSTEMD_DIR}/minecraft-secrets.env (preserved)"
fi

# --- Install env files ---

echo "Installing environment files..."
for envfile in "${APP_DIR}/env"/minecraft-*.env; do
    [[ "$(basename "$envfile")" == "minecraft-secrets.env.example" ]] && continue
    cp "$envfile" "${SYSTEMD_DIR}/$(basename "$envfile")"
    echo "  Installed: $(basename "$envfile")"
done

# --- Install quadlet units ---

echo "Installing quadlet units..."
for unitfile in "${APP_DIR}/quadlet"/*.network "${APP_DIR}/quadlet"/*.image "${APP_DIR}/quadlet"/*.container; do
    [[ -f "$unitfile" ]] || continue
    cp "$unitfile" "${SYSTEMD_DIR}/$(basename "$unitfile")"
    echo "  Installed: $(basename "$unitfile")"
done

# --- Install minecraft.target ---
# .target is not a supported Quadlet extension — must live in ~/.config/systemd/user/

echo "Installing minecraft.target..."
cp "${APP_DIR}/systemd/minecraft.target" "${SYSTEMD_USER_DIR}/minecraft.target"
echo "  Installed: ${SYSTEMD_USER_DIR}/minecraft.target"

# --- Generate drop-in files ---
# Three drop-ins per container:
#   10-memory.conf   — Memory=, PodmanArgs= cgroup-conf, MemorySwapMax=
#   20-fleet.conf    — [Install] WantedBy=minecraft.target (enabled worlds only)
#   30-restart.conf  — [Service] RestartSec= (staggered per instance, anti-stampede)

declare -A DROPIN_MAP=(
    [proxy]="minecraft-proxy.container"
    [survival]="minecraft@survival.container"
    [creative]="minecraft@creative.container"
    [modded]="minecraft-modded.container"
    [insane]="minecraft-insane.container"
)

# Staggered RestartSec values per instance (v259 workaround for absent
# RestartRandomizedDelaySec which requires v262). Prevents all backends
# from restarting simultaneously after a correlated failure.
declare -A RESTART_SEC=(
    [proxy]=10
    [survival]=30
    [creative]=35
    [modded]=40
    [insane]=45
)

echo "Generating drop-in files..."
for world in proxy survival creative modded insane; do
    container_file="${DROPIN_MAP[$world]}"
    dropin_dir="${SYSTEMD_DIR}/${container_file}.d"
    mkdir -p "$dropin_dir"

    # 10-memory.conf — memory allocation from FLEET_*_MEMORY
    fleet_mem_var="FLEET_$(echo "$world" | tr '[:lower:]' '[:upper:]')_MEMORY"
    mem="${!fleet_mem_var:-}"
    if [[ -n "$mem" ]]; then
        mem_bytes=$(memory_to_bytes "$mem")
        # memory.high at 90% of container memory — throttle before OOM kill
        high_bytes=$(( mem_bytes * 90 / 100 ))
        high_systemd=$(( high_bytes / 1048576 ))M

        cat > "${dropin_dir}/10-memory.conf" <<EOF
[Container]
Memory=${mem}
PodmanArgs=--cgroup-conf=memory.swap.max=0 --cgroup-conf=memory.high=${high_bytes} --cgroup-conf=memory.oom.group=1

[Service]
MemoryHigh=${high_systemd}
MemorySwapMax=0
EOF
        echo "  ${container_file}: Memory=${mem}, memory.high=${high_systemd}"
    fi

    # 20-fleet.conf — [Install] WantedBy=minecraft.target for enabled worlds
    # Proxy always enabled. Backends enabled by FLEET_* flag.
    fleet_enable_var="FLEET_$(echo "$world" | tr '[:lower:]' '[:upper:]')"
    is_enabled="false"
    [[ "$world" == "proxy" ]] && is_enabled="true"
    [[ "${!fleet_enable_var:-false}" == "true" ]] && is_enabled="true"

    if [[ "$is_enabled" == "true" ]]; then
        cat > "${dropin_dir}/20-fleet.conf" <<EOF
[Install]
WantedBy=minecraft.target
EOF
        echo "  ${container_file}: enabled (WantedBy=minecraft.target)"
    else
        rm -f "${dropin_dir}/20-fleet.conf"
        echo "  ${container_file}: disabled (no WantedBy)"
    fi

    # 30-restart.conf — staggered RestartSec for anti-stampede
    restart_sec="${RESTART_SEC[$world]}"
    cat > "${dropin_dir}/30-restart.conf" <<EOF
[Service]
RestartSec=${restart_sec}
EOF
done

# --- Download Hangar plugins for enabled Paper worlds ---

HANGAR_FAILURES=0
echo "Downloading Hangar plugins..."
for world in survival creative; do
    fleet_var="FLEET_$(echo "$world" | tr '[:lower:]' '[:upper:]')"
    if [[ "${!fleet_var:-false}" != "true" ]]; then
        echo "  ${world}: skipped (disabled)"
        continue
    fi
    hangar_file="${APP_DIR}/config/hangar-plugins-${world}.txt"
    if [[ -f "$hangar_file" ]]; then
        echo "  ${world}:"
        if ! bash "${SCRIPT_DIR}/hangar-download.sh" "$world" "$hangar_file"; then
            HANGAR_FAILURES=$((HANGAR_FAILURES + $?))
        fi
    fi
done
if [[ "$HANGAR_FAILURES" -gt 0 ]]; then
    echo ""
    echo "  WARNING: ${HANGAR_FAILURES} Hangar plugin download(s) failed"
fi

# --- Clean up orphan units from prior naming schemes ---

echo "Cleaning up orphan units..."
for orphan in minecraft-modded-creative.service minecraft-modded-survival.service; do
    systemctl --user stop "${orphan}" 2>/dev/null || true
    systemctl --user disable "${orphan}" 2>/dev/null || true
done

# Stop disabled services that may be running from a prior deploy
for world in survival creative modded insane; do
    fleet_var="FLEET_$(echo "$world" | tr '[:lower:]' '[:upper:]')"
    if [[ "${!fleet_var:-false}" != "true" ]]; then
        svc="minecraft-${world}.service"
        [[ "$world" == "survival" || "$world" == "creative" ]] && svc="minecraft@${world}.service"
        if systemctl --user is-active "${svc}" &>/dev/null 2>&1; then
            systemctl --user stop "${svc}" 2>/dev/null || true
            echo "  Stopped disabled: ${svc}"
        fi
    fi
done
systemctl --user reset-failed 2>/dev/null || true

# --- Reload systemd ---
# Quadlet generator reads .container + .container.d/*.conf, merges them,
# generates .service files. The [Install] WantedBy= in 20-fleet.conf
# creates symlinks in minecraft.target.wants/ during generation.

echo "Reloading systemd user daemon..."
systemctl --user daemon-reload

# Enable minecraft.target for boot auto-start.
# The target itself is a regular unit file (not Quadlet-generated),
# so systemctl enable is correct here.
systemctl --user enable minecraft.target 2>/dev/null || true

# --- Post-deploy verification ---
# Verify critical settings parsed correctly (silent misconfiguration risk).

echo ""
echo "=== Post-deploy verification ==="
for world in proxy survival creative modded insane; do
    fleet_var="FLEET_$(echo "$world" | tr '[:lower:]' '[:upper:]')"
    [[ "$world" != "proxy" && "${!fleet_var:-false}" != "true" ]] && continue

    svc="minecraft-${world}.service"
    [[ "$world" == "survival" || "$world" == "creative" ]] && svc="minecraft@${world}.service"

    oom=$(systemctl --user show "${svc}" -P OOMPolicy 2>/dev/null || echo "unknown")
    restart_usec=$(systemctl --user show "${svc}" -P RestartUSec 2>/dev/null || echo "unknown")
    swap_max=$(systemctl --user show "${svc}" -P MemorySwapMax 2>/dev/null || echo "unknown")
    managed_oom=$(systemctl --user show "${svc}" -P ManagedOOMMemoryPressure 2>/dev/null || echo "unknown")

    echo "  ${svc}:"
    echo "    OOMPolicy=${oom} RestartSec=${restart_usec} MemorySwapMax=${swap_max} ManagedOOMMemoryPressure=${managed_oom}"
done

echo ""
echo "=== Deployment complete ==="
echo ""
echo "Start the fleet:"
echo "  ./scripts/enable.sh all"
echo ""
echo "Start a single world:"
echo "  ./scripts/enable.sh survival"
echo ""
echo "Verify:"
echo "  systemctl --user status minecraft.target"
echo "  journalctl --user -t minecraft-proxy -f"
