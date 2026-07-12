#!/usr/bin/env bash
# Download latest Hangar plugin releases for a given world.
# Usage: ./hangar-download.sh <world> [plugins-file]
#
# Reads author/slug pairs from the plugins file (one per line, # comments
# and blank lines ignored), resolves the latest release version via the
# Hangar API, and downloads the PAPER platform JAR into ~/minecraft/<world>/plugins/.
#
# Idempotent: skips download if the JAR filename already exists.
# Fails loudly: any download failure is reported and counted; exits
# with the failure count so the caller knows something is wrong.
set -euo pipefail

WORLD="${1:?Usage: $0 <world> [plugins-file]}"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
APP_DIR="$(dirname "$SCRIPT_DIR")"
PLUGINS_FILE="${2:-${APP_DIR}/config/hangar-plugins-${WORLD}.txt}"
PLUGINS_DIR="${HOME}/minecraft/${WORLD}/plugins"

if [[ ! -f "$PLUGINS_FILE" ]]; then
    exit 0
fi

mkdir -p "$PLUGINS_DIR"

HANGAR_API="https://hangar.papermc.io/api/v1/projects"
CURL_TIMEOUT=15
FAILURES=0

while IFS= read -r line || [[ -n "$line" ]]; do
    # Skip comments and blank lines
    line="${line%%#*}"
    line="$(echo "$line" | xargs)"
    [[ -z "$line" ]] && continue

    author="${line%%/*}"
    slug="${line##*/}"

    echo "    Hangar: ${author}/${slug}"

    # Resolve latest version
    if ! version=$(curl -sf --max-time "$CURL_TIMEOUT" "${HANGAR_API}/${author}/${slug}/latestrelease"); then
        echo "      ERROR: could not resolve latest version for ${author}/${slug}"
        FAILURES=$((FAILURES + 1))
        continue
    fi

    # Build download URL
    download_url="${HANGAR_API}/${author}/${slug}/versions/${version}/PAPER/download"

    # Resolve the redirect to get the actual filename
    if ! jar_url=$(curl -sfLI --max-time "$CURL_TIMEOUT" -o /dev/null -w '%{url_effective}' "$download_url"); then
        echo "      ERROR: redirect resolution failed for ${author}/${slug} v${version}"
        FAILURES=$((FAILURES + 1))
        continue
    fi

    # Detect external host redirects that will 403 (CurseForge, etc.)
    if [[ "$jar_url" != *"hangar"* && "$jar_url" != *"papermc"* ]]; then
        echo "      ERROR: ${author}/${slug} redirects to external host ($(echo "$jar_url" | cut -d/ -f3)), automated download blocked"
        FAILURES=$((FAILURES + 1))
        continue
    fi

    jar_name=$(basename "$jar_url")

    if [[ -f "${PLUGINS_DIR}/${jar_name}" ]]; then
        echo "      Already installed: ${jar_name}"
        continue
    fi

    # Remove older versions of the same plugin
    slug_lower=$(echo "$slug" | tr '[:upper:]' '[:lower:]')
    for old in "${PLUGINS_DIR}"/*"${slug_lower}"*.jar; do
        [[ -f "$old" ]] && rm -f "$old" && echo "      Removed old: $(basename "$old")"
    done

    # Download
    if curl -sfL --max-time 60 -o "${PLUGINS_DIR}/${jar_name}" "$download_url"; then
        echo "      Downloaded: ${jar_name} (v${version})"
    else
        rm -f "${PLUGINS_DIR}/${jar_name}"
        echo "      ERROR: download failed for ${author}/${slug} v${version}"
        FAILURES=$((FAILURES + 1))
    fi
done < "$PLUGINS_FILE"

if [[ "$FAILURES" -gt 0 ]]; then
    echo "    ${FAILURES} Hangar plugin(s) FAILED for ${WORLD}"
fi
exit "$FAILURES"
