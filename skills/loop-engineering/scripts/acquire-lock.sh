#!/usr/bin/env bash
# acquire-lock.sh — 租约锁抢锁实现
# Usage: acquire-lock.sh [--lease-seconds N] <loop-name>
# Exit codes: 0=抢到锁, 1=有实例运行/竞争失败, 2=STALE_FOREIGN(过期锁来自其他机器)

set -euo pipefail

LEASE_SECONDS=1800

while [ $# -gt 0 ]; do
  case "$1" in
    --lease-seconds)
      LEASE_SECONDS="${2:?Error: --lease-seconds requires a value}"
      shift 2
      ;;
    --)
      shift
      break
      ;;
    -*)
      echo "Unknown option: $1" >&2
      echo "Usage: acquire-lock.sh [--lease-seconds N] <loop-name>" >&2
      exit 1
      ;;
    *)
      break
      ;;
  esac
done

LOOP_NAME="${1:?Usage: acquire-lock.sh [--lease-seconds N] <loop-name>}"
LOCK_DIR=".loop/state/${LOOP_NAME}.lock"

_parse_json() {
  if command -v jq &>/dev/null; then
    jq -r ".$2" "$1" 2>/dev/null
  else
    grep -oE "\"$2\"[[:space:]]*:[[:space:]]*[0-9]+" "$1" 2>/dev/null | grep -oE '[0-9]+' | head -1
  fi
}

_parse_json_str() {
  if command -v jq &>/dev/null; then
    jq --arg k "$2" -r '.host[$k] // empty' "$1" 2>/dev/null
  else
    grep -oE "\"$2\"[[:space:]]*:[[:space:]]*\"[^\"]*\"" "$1" 2>/dev/null | head -1 | sed -E 's/.*:[[:space:]]*"([^"]*)"/\1/'
  fi
}

write_meta() {
  local now_iso
  now_iso=$(date -u +"%Y-%m-%dT%H:%M:%SZ")
  local now_epoch
  now_epoch=$(date +%s)
  local my_hostname
  my_hostname=$(hostname 2>/dev/null || echo "unknown")
  local my_uname
  my_uname=$(uname -n 2>/dev/null || echo "unknown")

  cat > "${LOCK_DIR}/meta.json" <<METAEOF
{
  "loop_name": "${LOOP_NAME}",
  "host": {
    "hostname": "${my_hostname}",
    "uname_n": "${my_uname}"
  },
  "acquired_at": "${now_iso}",
  "heartbeat_epoch": ${now_epoch},
  "lease_seconds": ${LEASE_SECONDS}
}
METAEOF
}

acquire() {
  if mkdir "${LOCK_DIR}" 2>/dev/null; then
    write_meta && return 0
  fi

  local hb_raw
  hb_raw=$(_parse_json "${LOCK_DIR}/meta.json" heartbeat_epoch)

  if [ -z "$hb_raw" ] || ! [ "$hb_raw" -eq "$hb_raw" ] 2>/dev/null; then
    echo "锁文件 meta.json 损坏（heartbeat_epoch 缺失或非数字），尝试修复：删除残留锁"
    rm -rf "${LOCK_DIR}"
    if mkdir "${LOCK_DIR}" 2>/dev/null; then
      write_meta && return 0
    else
      echo "修复失败：无法创建锁目录"
      exit 1
    fi
  fi

  local now_epoch
  now_epoch=$(date +%s)
  local age=$(( now_epoch - hb_raw ))

  local lease
  lease=$(_parse_json "${LOCK_DIR}/meta.json" lease_seconds)
  lease="${lease:-1800}"

  if [ "$age" -lt "$lease" ]; then
    echo "拒绝：疑似有实例在运行（心跳 ${age}s 前 < 租约 ${lease}s）"
    exit 1
  fi

  local lock_hn lock_un
  lock_hn=$(_parse_json_str "${LOCK_DIR}/meta.json" hostname)
  lock_un=$(_parse_json_str "${LOCK_DIR}/meta.json" uname_n)

  local cur_hn cur_un
  cur_hn=$(hostname 2>/dev/null || echo "")
  cur_un=$(uname -n 2>/dev/null || echo "")

  local is_local=0
  if [ -n "$lock_hn" ] && [ "$lock_hn" = "$cur_hn" ]; then
    is_local=1
  fi
  if [ -n "$lock_un" ] && [ "$lock_un" = "$cur_un" ]; then
    is_local=1
  fi

  if [ "$is_local" -ne 1 ]; then
    echo "STALE_FOREIGN：过期锁 host='${lock_hn:-未知}' 非本机或无法确认"
    exit 2
  fi

  rm -rf "${LOCK_DIR}"
  if mkdir "${LOCK_DIR}" 2>/dev/null; then
    write_meta && return 0
  else
    echo "接管竞争失败：无法创建锁目录"
    exit 1
  fi
}

acquire
