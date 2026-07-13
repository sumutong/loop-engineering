#!/usr/bin/env bash
# powershell-fallback.sh — PowerShell 回退执行模式
# Usage: powershell-fallback.sh <verification_command>
# 在 Git Bash 中调用 PowerShell 执行 verification（无超时保护）

set -euo pipefail

VERIFY_CMD="${1:?Usage: powershell-fallback.sh <verification_command>}"

echo "WARN: 使用 PowerShell 回退模式执行 verification（无超时保护）" >&2

powershell.exe -NoProfile -Command "
  & {
    \$proc = Start-Process -FilePath 'sh' -ArgumentList '-c', '${VERIFY_CMD}' -Wait -NoNewWindow -PassThru
    exit \$proc.ExitCode
  }
"

EXIT_CODE=$?

echo "PowerShell 回退执行完成，exit_code=${EXIT_CODE}"
exit $EXIT_CODE
