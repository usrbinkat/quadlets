#!/usr/bin/env bash
# Download latest Hangar plugin releases for a given world.
# Usage: ./hangar-download.sh <world> [plugins-file]
#
# Reads author/slug pairs from the plugins file (one per line, # comments
# and blank lines ignored), resolves the latest release version via the
# Hangar API, and downloads the PAPER platform JAR into ~/minecraft/<world>/plugins/.
#
# Idempotent: skips download if the JAR filename already exists.
set -euo pipefail

WORLD="${1:?Usage: $0 <world> [plugins-file]}"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
APP_DIR="$(dirname "$SCRIPT_DIR")"
PLUGINS_FILE="${2:-${APP_DIR}/config/hangar-plugins-${WORLD}.txt}"
PLUGINS_DIR="${HOME}/minecraft/${WORLD}/plugins"

if [[ ! -f "$PLUGINS_FILE" ]]; then
    return 0 2>/dev/null || exit 0
fi

mkdir -p "$PLUGINS_DIR"

HANGAR_API="https://hangar.papermc.io/api/v1/projects"

while IFS= read -r line || [[ -n "$line" ]]; do
    # Skip comments and blank lines
    line="${line%%#*}"
    line="$(echo "$line" | xargs)"
    [[ -z "$line" ]] && continue

    author="${line%%/*}"
    slug="${line##*/}"

    echo "  Hangar: ${author}/${slug}"

    # Resolve latest version
    version=$(curl -sf "${HANGAR_API}/${author}/${slug}/latestrelease" 2>/dev/null)
    if [[ -z "$version" ]]; then
        echo "    WARNING: could not resolve latest version, skipping"
        continue
    fi

    # Build download URL
    download_url="${HANGAR_API}/${author}/${slug}/versions/${version}/PAPER/download"

    # Resolve the redirect to get the actual filename
    jar_url=$(curl -sfLI -o /dev/null -w '%{url_effective}' "$download_url" 2>/dev/null)
    jar_name=$(basename "$jar_url")

    if [[ -f "${PLUGINS_DIR}/${jar_name}" ]]; then
        echo "    Already installed: ${jar_name}"
        continue
    fi

    # Remove older versions of the same plugin
    # Pattern: slug appears in the filename (lowercase match)
    slug_lower=$(echo "$slug" | tr '[:upper:]' '[:lower:]')
    for old in "${PLUGINS_DIR}"/*"${slug_lower}"*.jar; do
        [[ -f "$old" ]] && rm -f "$old" && echo "    Removed old: $(basename "$old")"
    done

    # Download
    if curl -sfL -o "${PLUGINS_DIR}/${jar_name}" "$download_url"; then
        echo "    Downloaded: ${jar_name} (v${version})"
    else
        echo "    WARNING: download failed for ${author}/${slug} v${version}"
    fi
done < "$PLUGINS_FILE"
