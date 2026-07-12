#!/usr/bin/env bash
# Deploy the Minecraft quadlet fleet to the current user's systemd.
# Usage: ./deploy.sh [--generate-secret]
#
# Podman version handling:
#   >= 5.9 (future): podman quadlet install --application=minecraft --replace ./quadlet/
#   5.8.x (current Fedora 44): manual file copy (--application flag not yet available)
#
# When Podman ships --application support, replace the "Install quadlet units"
# section below with:
#   podman quadlet install --application=minecraft --replace "${APP_DIR}/quadlet/"
# and remove the manual file copy, drop-in, and config symlink logic.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
APP_DIR="$(dirname "$SCRIPT_DIR")"
SYSTEMD_DIR="${HOME}/.config/containers/systemd"
PODMAN_VERSION="$(podman --version | awk '{print $3}')"

echo "=== Minecraft Quadlet Fleet Deployment ==="
echo "Source: ${APP_DIR}"
echo "Target: ${SYSTEMD_DIR}"
echo "Podman: ${PODMAN_VERSION}"
echo ""

# Create target directory
mkdir -p "${SYSTEMD_DIR}"

# Generate secret if requested or if none exists
if [[ "${1:-}" == "--generate-secret" ]] || [[ ! -f "${SYSTEMD_DIR}/minecraft-secrets.env" ]]; then
    echo "Generating forwarding secret..."
    bash "${SCRIPT_DIR}/generate-secret.sh" > "${SYSTEMD_DIR}/minecraft-secrets.env"
    chmod 0600 "${SYSTEMD_DIR}/minecraft-secrets.env"
    echo "  Written: ${SYSTEMD_DIR}/minecraft-secrets.env (0600)"
else
    echo "  Secret exists: ${SYSTEMD_DIR}/minecraft-secrets.env (preserved)"
fi

# Install env files
echo "Installing environment files..."
for envfile in "${APP_DIR}/env"/minecraft-*.env; do
    [[ "$(basename "$envfile")" == "minecraft-secrets.env.example" ]] && continue
    cp "$envfile" "${SYSTEMD_DIR}/$(basename "$envfile")"
    echo "  Installed: $(basename "$envfile")"
done

# Install quadlet units
# TODO: Replace with `podman quadlet install --application=minecraft --replace "${APP_DIR}/quadlet/"`
#       when Podman >= 5.9 ships on target hosts (adds --application flag for directory install).
echo "Installing quadlet units..."
for unitfile in "${APP_DIR}/quadlet"/*.network "${APP_DIR}/quadlet"/*.image "${APP_DIR}/quadlet"/*.volume "${APP_DIR}/quadlet"/*.container; do
    [[ -f "$unitfile" ]] || continue
    cp "$unitfile" "${SYSTEMD_DIR}/$(basename "$unitfile")"
    echo "  Installed: $(basename "$unitfile")"
done

# Install drop-in directories
echo "Installing drop-in overrides..."
for dropdir in "${APP_DIR}/quadlet"/*.container.d; do
    [[ -d "$dropdir" ]] || continue
    target_dir="${SYSTEMD_DIR}/$(basename "$dropdir")"
    mkdir -p "$target_dir"
    cp "$dropdir"/*.conf "$target_dir/" 2>/dev/null || true
    echo "  Installed: $(basename "$dropdir")/"
done

# Link config directory (bind-mounted into containers via Volume=./config:/config:ro,Z)
# Quadlet resolves ./config relative to the unit file location (~/.config/containers/systemd/).
echo "Linking config directory..."
ln -sfn "${APP_DIR}/config" "${SYSTEMD_DIR}/config"
echo "  Linked: config -> ${APP_DIR}/config"

# Reload systemd
echo "Reloading systemd user daemon..."
systemctl --user daemon-reload

echo ""
echo "=== Deployment complete ==="
echo ""
echo "Start the fleet:"
echo "  systemctl --user start minecraft-proxy.service"
echo "  systemctl --user start minecraft@survival.service"
echo "  systemctl --user start minecraft@creative.service"
echo "  systemctl --user start minecraft@modded-survival.service"
echo "  systemctl --user start minecraft@modded-creative.service"
echo ""
echo "Verify:"
echo "  systemctl --user status minecraft-proxy.service"
echo "  podman healthcheck run minecraft-proxy"
echo "  journalctl --user -t minecraft-proxy -f"
