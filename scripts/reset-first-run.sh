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
        rm -f "${prefs_file}"
        echo "Removed: ${prefs_file}"
    fi
done
killall cfprefsd >/dev/null 2>&1 || true

echo
echo "Removing local logs/cache/history..."
if [[ -d "${APP_SUPPORT_DIR}" ]]; then
    rm -rf "${APP_SUPPORT_DIR}"
    echo "Removed: ${APP_SUPPORT_DIR}"
else
    echo "No local logs/cache/history directories found."
fi

echo
echo "Removing Photos Wallpaper album from Photos..."
"$SCRIPT_DIR/_delete-photos-wallpaper-album.sh" --yes

echo
echo "Resetting Photos permission for likely bundle identifiers..."
TCC_DOMAINS=()
while IFS= read -r domain; do
    [[ -z "${domain}" ]] && continue
    TCC_DOMAINS+=("${domain}")
done < <(
    printf '%s\n' "${DOMAINS[@]}" |
        sort -u |
        grep -E '^[A-Za-z0-9][A-Za-z0-9.-]*\.[A-Za-z0-9.-]+$' || true
)

if ((${#TCC_DOMAINS[@]} == 0)); then
    tccutil reset Photos >/dev/null 2>&1 || true
    echo "Reset Photos permission globally because no bundle identifier was found."
else
    for domain in "${TCC_DOMAINS[@]}"; do
        tccutil reset Photos "${domain}" >/dev/null 2>&1 || true
        echo "Reset Photos permission for: ${domain}"
    done
fi

tccutil reset Photos com.rosehillsolutions.photoswallpaper

echo
echo "Start at Login cannot be removed reliably from a shell script on all macOS versions."
echo "Check System Settings > General > Login Items & Extensions and remove Photos Wallpaper if present."

echo
echo "Done. Launch Photos Wallpaper again to get first-run behavior."
