#!/usr/bin/env bash
# Deploy the Minecraft quadlet fleet to the current user's systemd.
# Usage: ./deploy.sh [--generate-secret]
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
APP_DIR="$(dirname "$SCRIPT_DIR")"
SYSTEMD_DIR="${HOME}/.config/containers/systemd"

echo "=== Minecraft Quadlet Fleet Deployment ==="
echo "Source: ${APP_DIR}"
echo "Target: ${SYSTEMD_DIR}"
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

# Install quadlet files via podman quadlet install
echo "Installing quadlet units..."
podman quadlet install --application=minecraft --replace "${APP_DIR}/quadlet/"
echo "  Quadlet application installed."

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
