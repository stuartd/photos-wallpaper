#!/usr/bin/env bash
set -euo pipefail

source "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/_common.sh"

echo "Resetting Photos Wallpaper first-run state..."

echo
quit_running_app_if_needed

killall cfprefsd >/dev/null 2>&1 || true

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
        for key in "${KNOWN_DEFAULTS_KEYS[@]}"; do
            defaults delete "${domain}" "${key}" >/dev/null 2>&1 || true
        done
        defaults synchronize "${domain}" >/dev/null 2>&1 || true
        echo "Deleted defaults domain if present: ${domain}"
    done
fi
killall cfprefsd >/dev/null 2>&1 || true

echo
echo "Removing local logs/cache/history..."
if [[ -d "${APP_SUPPORT_DIR}" ]]; then
    removed_any=false
    for local_file in \
        "${APP_SUPPORT_DIR}/current-wallpapers.json" \
        "${APP_SUPPORT_DIR}/runtime.log" \
        "${APP_SUPPORT_DIR}/wallpaper-history.log"; do
        if [[ -e "${local_file}" ]]; then
            if rm -f "${local_file}"; then
                echo "Removed: ${local_file}"
                removed_any=true
            else
                echo "Could not remove protected local file: ${local_file}"
            fi
        fi
    done

    while IFS= read -r cache_file; do
        [[ -z "${cache_file}" ]] && continue
        if rm -f "${cache_file}"; then
            echo "Removed: ${cache_file}"
            removed_any=true
        else
            echo "Could not remove protected wallpaper cache file: ${cache_file}"
        fi
    done < <(find "${APP_SUPPORT_DIR}" -maxdepth 1 -type f -name 'current-wallpaper-*.jpg' -print)

    if [[ "${removed_any}" == false ]]; then
        echo "No local logs/cache/history files found."
    fi
else
    echo "No local logs/cache/history directories found."
fi

echo
echo "Removing Photos Wallpaper album from Photos..."
"$SCRIPT_DIR/_delete-photos-wallpaper-album.sh" --yes

echo
echo "Resetting Photos permission..."
tccutil reset Photos "${APP_BUNDLE_ID}" >/dev/null 2>&1 || true
echo "Reset Photos permission for: ${APP_BUNDLE_ID}"

echo
echo "Start at Login cannot be removed reliably from a shell script on all macOS versions."
echo "Check System Settings > General > Login Items & Extensions and remove Photos Wallpaper if present."

echo
echo "Done"
