#!/usr/bin/env bash
set -euo pipefail

source "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/_common.sh"

echo "Resetting Photos Wallpaper first-run state..."

echo
echo "Clearing matching defaults domains..."
DOMAINS=()
while IFS= read -r domain; do
    [[ -z "${domain}" ]] && continue
    DOMAINS+=("${domain}")
done < <(matching_defaults_domains | sort -u)
if ((${#DOMAINS[@]} == 0)); then
    echo "No matching defaults domains found."
else
    printf '%s\n' "${DOMAINS[@]}" | while read -r domain; do
        [[ -z "${domain}" ]] && continue
        defaults delete "${domain}" >/dev/null 2>&1 || true
        echo "Deleted defaults domain if present: ${domain}"
    done
fi

echo
echo "Removing preference plist files..."
for domain in "${DOMAINS[@]}"; do
    [[ -z "${domain}" ]] && continue
    prefs_file="${HOME}/Library/Containers/${domain}/Data/Library/Preferences/${domain}.plist"
    if [[ -e "${prefs_file}" ]]; then
        if rm -f "${prefs_file}" 2>/dev/null; then
            echo "Removed: ${prefs_file}"
        else
            echo "Could not remove protected preference file; defaults were already cleared: ${prefs_file}"
        fi
    fi
done
killall cfprefsd >/dev/null 2>&1 || true

echo
echo "Removing local logs/cache/history..."
if [[ -d "${APP_SUPPORT_DIR}" ]]; then
    if rm -rf "${APP_SUPPORT_DIR}" 2>/dev/null; then
        echo "Removed: ${APP_SUPPORT_DIR}"
    else
        echo "Could not remove protected local logs/cache/history: ${APP_SUPPORT_DIR}"
    fi
else
    echo "No local logs/cache/history directories found."
fi

echo
echo "Removing Photos Wallpaper album from Photos..."
"$SCRIPT_DIR/_delete-photos-wallpaper-album.sh" --yes

echo
echo "Resetting Photos permission..."
tccutil reset Photos "${KNOWN_DEFAULTS_DOMAINS[0]}" >/dev/null 2>&1 || true
echo "Reset Photos permission for: ${KNOWN_DEFAULTS_DOMAINS[0]}"

echo
echo "Start at Login cannot be removed reliably from a shell script on all macOS versions."
echo "Check System Settings > General > Login Items & Extensions and remove Photos Wallpaper if present."

echo
echo "Done"

