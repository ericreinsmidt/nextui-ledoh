#!/bin/sh
set -eu

PAK_DIR="$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)"
APP_ID="ledoh"

BIN="${PAK_DIR}/bin/ledoh"

if [ -x "${BIN}" ]; then
  export LEDOH_PAK_DIR="${PAK_DIR}"
  export LEDOH_LOG_DIR="${USERDATA_PATH}/../tg5040/logs"

  mkdir -p "$(dirname "${LEDOH_LOG_DIR}")" 2>/dev/null || true

  cd "${PAK_DIR}"
  exec "${BIN}"
else
  echo "Executable not found: ${BIN}"
  exit 0
fi
