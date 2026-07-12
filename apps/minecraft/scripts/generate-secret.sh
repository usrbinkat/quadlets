#!/usr/bin/env bash
# Generate a forwarding secret for the Minecraft fleet.
# Output: a secrets env file ready for deployment.
set -euo pipefail

SECRET=$(openssl rand -base64 32 | tr -d '/+=' | head -c 32)

cat <<EOF
# Generated: $(date -Iseconds)
# Deploy to: ~/.config/containers/systemd/minecraft-secrets.env
# Permissions: chmod 0600

MINECRAFT_FORWARDING_SECRET=${SECRET}
VELOCITY_FORWARDING_SECRET=${SECRET}
CFG_VELOCITY_SECRET=${SECRET}
EOF
