#!/usr/bin/env bash
set -euo pipefail
APP_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
# Retain the old launcher name; Studio is now the production application.
bash "$APP_ROOT/script/build_and_run.sh" run
