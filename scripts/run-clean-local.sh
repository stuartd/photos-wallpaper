#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

"$SCRIPT_DIR/create-local.sh"
"$SCRIPT_DIR/reset-first-run.sh"
"$SCRIPT_DIR/update-local-app.sh"
