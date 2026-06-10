#!/usr/bin/env bash
set -euo pipefail

source "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/common.sh"

echo "Photos Wallpaper saved data"

echo
echo "Defaults domains:"
matching_defaults_domains | sort -u | while read -r domain; do
    [[ -z "${domain}" ]] && continue
    if defaults read "${domain}" >/dev/null 2>&1; then
        echo
        echo "[${domain}]"
        defaults read "${domain}" || true
    fi
done

echo
echo "App support:"
if [[ -d "${APP_SUPPORT_DIR}" ]]; then
    echo "${APP_SUPPORT_DIR}"
    echo
    find "${APP_SUPPORT_DIR}" -maxdepth 3 -print | sed "s#${APP_SUPPORT_DIR}#.#"
    echo
    du -sh "${APP_SUPPORT_DIR}" 2>/dev/null || true
else
    echo "No app support directory found at: ${APP_SUPPORT_DIR}"
fi

echo
echo "Recent history log:"
HISTORY_LOG="${APP_SUPPORT_DIR}/wallpaper-history.log"
if [[ -f "${HISTORY_LOG}" ]]; then
    tail -n 20 "${HISTORY_LOG}"
else
    echo "No history log found."
fi

echo
echo "Recent runtime log:"
RUNTIME_LOG="${APP_SUPPORT_DIR}/runtime.log"
if [[ -f "${RUNTIME_LOG}" ]]; then
    tail -n 40 "${RUNTIME_LOG}"
else
    echo "No runtime log found."
fi

echo
echo "Photos permission:"
echo "macOS does not provide a simple tccutil status command."
echo "Check System Settings > Privacy & Security > Photos for the current permission."

echo
echo "Start at Login:"
echo "Check System Settings > General > Login Items & Extensions for the current login item state."
