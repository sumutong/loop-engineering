#!/usr/bin/env bash
# write-state.sh — 三段式原子写入 state 文件
# Usage: write-state.sh <state_file> <json_content>
#        或通过 stdin 传入 JSON: echo "$json" | write-state.sh <state_file>

set -euo pipefail

STATE_FILE="${1:?Usage: write-state.sh <state_file> [json_content]}"
JSON_CONTENT="${2:-}"

if [ -z "$JSON_CONTENT" ]; then
  JSON_CONTENT=$(cat)
fi

TMP_FILE="${STATE_FILE}.tmp"
BAK_FILE="${STATE_FILE}.bak"
LOCK_DIR="$(dirname "${STATE_FILE}")/$(basename "${STATE_FILE}" .json).lock"

if ! echo "$JSON_CONTENT" > "${TMP_FILE}"; then
  echo "ERROR: 写入 .tmp 文件失败（磁盘满？）" >&2
  exit 1
fi

if [ -f "${STATE_FILE}" ]; then
  cp "${STATE_FILE}" "${BAK_FILE}" 2>/dev/null || true
fi

if ! mv "${TMP_FILE}" "${STATE_FILE}"; then
  echo "ERROR: mv 原子替换失败，.tmp 文件保留在 ${TMP_FILE}" >&2
  exit 1
fi

if [ -d "${LOCK_DIR}" ] && [ -f "${LOCK_DIR}/meta.json" ]; then
  now_epoch=$(date +%s)
  if command -v jq &>/dev/null; then
    jq --arg ts "$now_epoch" '.heartbeat_epoch = ($ts | tonumber)' "${LOCK_DIR}/meta.json" > "${LOCK_DIR}/meta.json.tmp" \
      && mv "${LOCK_DIR}/meta.json.tmp" "${LOCK_DIR}/meta.json" \
      || true
  else
    sed -i "s/\"heartbeat_epoch\": [0-9]*/\"heartbeat_epoch\": ${now_epoch}/" "${LOCK_DIR}/meta.json" 2>/dev/null || true
  fi
fi
