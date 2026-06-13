#!/usr/bin/env bash
set -euo pipefail

source "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/_common.sh"

echo "Photos Wallpaper saved data"

APP_SUPPORT_DIRS=()

add_app_support_dir() {
    local dir="$1"
    local existing_dir
    if ((${#APP_SUPPORT_DIRS[@]} > 0)); then
        for existing_dir in "${APP_SUPPORT_DIRS[@]}"; do
            [[ "$existing_dir" == "$dir" ]] && return
        done
    fi
    APP_SUPPORT_DIRS+=("$dir")
}

print_log_tail() {
    local title="$1"
    local filename="$2"
    local line_count="$3"
    local found_log=false
    local app_support_dir

    echo
    echo "$title"
    for app_support_dir in "${APP_SUPPORT_DIRS[@]}"; do
        local log_path="${app_support_dir}/${filename}"
        if [[ -f "$log_path" ]]; then
            found_log=true
            echo
            echo "[$log_path]"
            tail -n "$line_count" "$log_path"
        fi
    done

    if [[ "$found_log" == false ]]; then
        echo "No ${filename} found."
    fi
}

add_app_support_dir "$APP_SUPPORT_DIR"

echo
echo "Saved preferences:"
DOMAINS=()
while IFS= read -r domain; do
    [[ -z "$domain" ]] && continue
    DOMAINS+=("$domain")
done < <(matching_defaults_domains | sort -u)

if ((${#DOMAINS[@]} == 0)); then
    echo "No app preferences domains found."
else
    printed_defaults=false
    for domain in "${DOMAINS[@]}"; do
        if defaults read "${domain}" >/dev/null 2>&1; then
            printed_defaults=true
            echo
            echo "[${domain}]"
            defaults read "${domain}" || true
        fi
    done
    if [[ "$printed_defaults" == false ]]; then
        echo "No saved app preferences found."
    fi
fi

echo
echo "App support:"
found_app_support=false
for app_support_dir in "${APP_SUPPORT_DIRS[@]}"; do
    if [[ -d "$app_support_dir" ]]; then
        found_app_support=true
        echo
        echo "$app_support_dir"
        find "$app_support_dir" -maxdepth 3 -print | sed "s#${app_support_dir}#.#"
        du -sh "$app_support_dir" 2>/dev/null || true
    fi
done

if [[ "$found_app_support" == false ]]; then
    echo "No app support directories found. Checked:"
    for app_support_dir in "${APP_SUPPORT_DIRS[@]}"; do
        echo "- $app_support_dir"
    done
fi

print_log_tail "Recent history log:" "wallpaper-history.log" 20
print_log_tail "Recent runtime log:" "runtime.log" 40

echo
echo "Photos permission:"
echo "macOS does not provide a simple tccutil status command."
echo "Check System Settings > Privacy & Security > Photos for the current permission."

echo
echo "Start at Login:"
echo "Check System Settings > General > Login Items & Extensions for the current login item state."
