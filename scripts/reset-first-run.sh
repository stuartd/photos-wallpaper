#!/usr/bin/env bash
set -euo pipefail

APP_SUPPORT_DIR="${HOME}/Library/Application Support/photos-wallpaper"

KNOWN_DOMAINS=(
    "com.rosehillsolutions.photoswallpaper"
    "photos-wallpaper"
    "photos_wallpaper"
)

echo "Resetting Photos Wallpaper first-run state..."

echo
echo "Clearing matching defaults domains..."
DOMAINS=("${KNOWN_DOMAINS[@]}")
while IFS= read -r domain; do
    [[ -z "${domain}" ]] && continue
    DOMAINS+=("${domain}")
done < <(
    defaults domains 2>/dev/null |
        tr ',' '\n' |
        sed 's/^ *//; s/ *$//' |
        grep -Ei 'photos[-_.]?wallpaper' || true
)
if ((${#DOMAINS[@]} == 0)); then
    echo "No matching defaults domains found."
else
    printf '%s\n' "${DOMAINS[@]}" | sort -u | while read -r domain; do
        [[ -z "${domain}" ]] && continue
        if defaults read "${domain}" >/dev/null 2>&1; then
            defaults delete "${domain}" >/dev/null 2>&1 || true
            echo "Deleted defaults domain: ${domain}"
        fi
    done
fi

echo
echo "Removing local logs/cache/history..."
if [[ -d "${APP_SUPPORT_DIR}" ]]; then
    rm -rf "${APP_SUPPORT_DIR}"
    echo "Removed: ${APP_SUPPORT_DIR}"
else
    echo "Nothing to remove at: ${APP_SUPPORT_DIR}"
fi

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

echo
echo "Start at Login cannot be removed reliably from a shell script on all macOS versions."
echo "Check System Settings > General > Login Items & Extensions and remove Photos Wallpaper if present."

echo
echo "Done. Launch Photos Wallpaper again to get first-run behavior."
