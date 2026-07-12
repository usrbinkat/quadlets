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
set -euxo pipefail

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

    # Check if Hangar hosts the file or links externally
    version_info=$(curl -sf --max-time "$CURL_TIMEOUT" "${HANGAR_API}/${author}/${slug}/versions/${version}")
    if [[ -z "$version_info" ]]; then
        echo "      ERROR: could not fetch version info for ${author}/${slug} v${version}"
        FAILURES=$((FAILURES + 1))
        continue
    fi

    # Extract PAPER download info
    paper_download_url=$(echo "$version_info" | python3 -c 'import sys,json; d=json.load(sys.stdin)["downloads"].get("PAPER",{}); print(d.get("downloadUrl") or "")' 2>/dev/null)
    paper_external_url=$(echo "$version_info" | python3 -c 'import sys,json; d=json.load(sys.stdin)["downloads"].get("PAPER",{}); print(d.get("externalUrl") or "")' 2>/dev/null)

    if [[ -n "$paper_download_url" ]]; then
        # Hangar-hosted file — use the API download endpoint
        download_url="${HANGAR_API}/${author}/${slug}/versions/${version}/PAPER/download"
        if ! jar_url=$(curl -sfLI --max-time "$CURL_TIMEOUT" -o /dev/null -w '%{url_effective}' "$download_url"); then
            echo "      ERROR: redirect resolution failed for ${author}/${slug} v${version}"
            FAILURES=$((FAILURES + 1))
            continue
        fi
        jar_name=$(basename "$jar_url")
    elif [[ "$paper_external_url" == *"github.com"* ]]; then
        # External GitHub release — resolve JAR from GitHub releases API
        # Extract owner/repo and tag from URL like https://github.com/Owner/Repo/releases/tag/vX.Y.Z
        gh_path=$(echo "$paper_external_url" | sed 's|https://github.com/||; s|/releases/tag/.*||')
        gh_tag=$(echo "$paper_external_url" | sed 's|.*/releases/tag/||')
        echo "      GitHub release: ${gh_path} tag ${gh_tag}"

        # Find the bukkit/paper JAR asset
        jar_url=$(curl -sf --max-time "$CURL_TIMEOUT" "https://api.github.com/repos/${gh_path}/releases/tags/${gh_tag}" \
            | python3 -c 'import sys,json; assets=json.load(sys.stdin).get("assets",[]); urls=[a["browser_download_url"] for a in assets if "bukkit" in a["name"].lower() or "paper" in a["name"].lower()]; print(urls[0] if urls else "")' 2>/dev/null)

        if [[ -z "$jar_url" ]]; then
            echo "      ERROR: no bukkit/paper JAR found in GitHub release ${gh_path}@${gh_tag}"
            FAILURES=$((FAILURES + 1))
            continue
        fi
        download_url="$jar_url"
        jar_name=$(basename "$jar_url")
    else
        echo "      ERROR: ${author}/${slug} has no Hangar download and external URL is not GitHub (${paper_external_url})"
        FAILURES=$((FAILURES + 1))
        continue
    fi

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
