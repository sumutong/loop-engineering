#!/usr/bin/env bash
# verify-runner.sh — verification 命令包装器
# Usage: verify-runner.sh <verification_command> <timeout_seconds> <use_timeout_mode>
#   use_timeout_mode: "gnu" | "powershell" | "none"

set -euo pipefail

VERIFY_CMD="${1:?Usage: verify-runner.sh <command> <timeout> <mode>}"
VERIFY_TIMEOUT="${2:-300}"
USE_TIMEOUT="${3:-gnu}"

if [ "$USE_TIMEOUT" = "gnu" ]; then
  TMP_SCRIPT=$(mktemp 2>/dev/null || echo "/tmp/loop_verify_$$.sh")
  cat > "$TMP_SCRIPT" <<LOOP_VERIFY_EOF
#!/usr/bin/env sh
${VERIFY_CMD}
LOOP_VERIFY_EOF
  chmod +x "$TMP_SCRIPT"

  timeout "${VERIFY_TIMEOUT}" sh -c "$TMP_SCRIPT"
  EXIT_CODE=$?

  rm -f "$TMP_SCRIPT"

  if [ "$EXIT_CODE" -eq 124 ]; then
    echo "VERIFY_TIMEOUT: verification 命令超时（${VERIFY_TIMEOUT}s）" >&2
  fi
  exit $EXIT_CODE

elif [ "$USE_TIMEOUT" = "powershell" ]; then
  echo "WARN: 无超时保护，若命令挂死父会话将同步阻塞（verification.timeout=${VERIFY_TIMEOUT} 被忽略）" >&2

  powershell.exe -NoProfile -Command "
    & {
      \$proc = Start-Process -FilePath 'sh' -ArgumentList '-c', '${VERIFY_CMD}' -Wait -NoNewWindow -PassThru
      exit \$proc.ExitCode
    }
  "
  exit $?

else
  echo "WARN: 无 timeout 和 PowerShell，直接执行 verification（无超时保护）" >&2
  sh -c "${VERIFY_CMD}"
  exit $?
fi
