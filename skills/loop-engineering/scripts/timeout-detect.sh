#!/usr/bin/env bash
# timeout-detect.sh — timeout 可用性三阶检测
# Usage: timeout-detect.sh
# Output: 打印 USE_TIMEOUT=<gnu|powershell|none> 和 HAS_JQ=<0|1>
# Exit code: 0=gnu或powershell, 1=none

set -euo pipefail

USE_TIMEOUT=""
HAS_JQ=0

if command -v timeout >/dev/null 2>&1; then
  USE_TIMEOUT="gnu"
  echo "USE_TIMEOUT=gnu"
elif command -v powershell.exe >/dev/null 2>&1; then
  USE_TIMEOUT="powershell"
  echo "USE_TIMEOUT=powershell"
else
  USE_TIMEOUT="none"
  echo "USE_TIMEOUT=none"
fi

if command -v jq >/dev/null 2>&1; then
  HAS_JQ=1
else
  HAS_JQ=0
  if [ "$USE_TIMEOUT" = "powershell" ]; then
    echo "WARN: jq 不可用 + PowerShell 回退：建议安装 jq（pacman -S jq 或 apt-get install jq）以提高锁判定可靠性" >&2
  else
    echo "WARN: jq 不可用，租约锁 JSON 解析使用 grep fallback——极端情况下可能误判锁状态" >&2
  fi
fi

echo "HAS_JQ=${HAS_JQ}"

if [ "$USE_TIMEOUT" = "none" ]; then
  exit 1
fi
exit 0
