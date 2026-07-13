#!/usr/bin/env bash
# crash-recovery.sh — 崩溃恢复 6 步流程
# Usage: crash-recovery.sh <loop-name>

set -euo pipefail

LOOP_NAME="${1:?Usage: crash-recovery.sh <loop-name>}"
STATE_FILE=".loop/state/${LOOP_NAME}.json"
MAINROOT="$(git rev-parse --show-toplevel 2>/dev/null || echo "")"

if [ -z "$MAINROOT" ]; then
  echo "ERROR: 不在 git 仓库中" >&2
  exit 1
fi

echo "=== 崩溃恢复: ${LOOP_NAME} ==="

echo "[1/6] 清理孤儿 maker 进程..."
if command -v tasklist &>/dev/null 2>&1; then
  orphans=$(tasklist 2>/dev/null | grep -i "claude-code" || echo "")
  if [ -n "$orphans" ]; then
    echo "  发现残留 claude-code 进程"
    taskkill /F /IM "claude-code.exe" 2>/dev/null || true
  fi
elif command -v pkill &>/dev/null 2>&1; then
  pkill -f "claude-code-agent" 2>/dev/null || true
fi
if command -v ps &>/dev/null 2>&1; then
  ps aux 2>/dev/null | grep -i "claude-code" | grep -v grep | awk '{print $2}' | while read -r pid; do
    kill "$pid" 2>/dev/null || true
  done
fi
echo "  完成"

echo "[2/6] 清理残留 worktree..."
if [ -d ".claude/worktrees" ]; then
  for wt_dir in .claude/worktrees/loop-"${LOOP_NAME}"-*; do
    if [ -d "$wt_dir" ]; then
      echo "  清理: $wt_dir"
      git worktree remove --force "$wt_dir" 2>/dev/null || rm -rf "$wt_dir"
    fi
  done
fi
git worktree prune 2>/dev/null || true
echo "  完成"

echo "[3/6] 重置 in_progress 任务..."
reset_count=0
if [ -f "$STATE_FILE" ] && command -v jq &>/dev/null; then
  reset_count=$(jq '[.tasks[] | select(.status == "in_progress")] | length' "$STATE_FILE" 2>/dev/null || echo "0")
  if [ "$reset_count" -gt 0 ]; then
    new_state=$(jq '.tasks = [.tasks[] | if .status == "in_progress" then .status = "pending" | .maker_result = null else . end]' "$STATE_FILE")
    echo "$new_state" > "${STATE_FILE}.tmp" && mv "${STATE_FILE}.tmp" "${STATE_FILE}"
    echo "  重置了 $reset_count 个 in_progress 任务"
  else
    echo "  无 in_progress 任务"
  fi
else
  echo "  WARN: jq 不可用或 state 文件不存在，跳过 state 修复"
fi

echo "[4/6] 回退 total_rounds..."
if [ "$reset_count" -gt 0 ] && [ -f "$STATE_FILE" ] && command -v jq &>/dev/null; then
  current_rounds=$(jq '.total_rounds' "$STATE_FILE" 2>/dev/null || echo "0")
  if [ "$current_rounds" -gt 0 ]; then
    new_rounds=$(( current_rounds - 1 ))
    jq --arg r "$new_rounds" '.total_rounds = ($r | tonumber)' "$STATE_FILE" > "${STATE_FILE}.tmp" \
      && mv "${STATE_FILE}.tmp" "${STATE_FILE}"
    echo "  total_rounds: ${current_rounds} -> ${new_rounds}"
  else
    echo "  total_rounds=0，保持不变"
  fi
else
  echo "  无需回退"
fi

echo "[5/6] 孤儿 .patch 检查..."
diffs_dir=".loop/diffs/${LOOP_NAME}"
if [ -d "$diffs_dir" ]; then
  for patch_file in "$diffs_dir"/*.patch; do
    if [ -f "$patch_file" ]; then
      task_id=$(basename "$patch_file" .patch)
      if [ -f "$STATE_FILE" ] && command -v jq &>/dev/null; then
        task_status=$(jq -r ".tasks[] | select(.id == \"$task_id\") | .status" "$STATE_FILE" 2>/dev/null || echo "")
        if [ "$task_status" = "pending" ] || [ -z "$task_status" ]; then
          echo "  WARN: 孤儿 .patch 文件 ${patch_file}（对应 task 已重置或不存在），不自动使用"
        fi
      fi
    fi
  done
fi
echo "  完成"

echo "[6/6] 重算快照..."
if [ -f "$STATE_FILE" ] && command -v jq &>/dev/null; then
  new_snapshot=$(jq '[.tasks[] | select(.status == "pending" or .status == "in_progress")] | length' "$STATE_FILE" 2>/dev/null || echo "0")
  new_completed=$(jq '[.tasks[] | select(.status == "completed")] | length' "$STATE_FILE" 2>/dev/null || echo "0")
  jq --arg ps "$new_snapshot" --arg cb "$new_completed" \
    '.pending_tasks_snapshot = ($ps | tonumber) | .completed_before_round = ($cb | tonumber)' \
    "$STATE_FILE" > "${STATE_FILE}.tmp" && mv "${STATE_FILE}.tmp" "${STATE_FILE}"
  echo "  pending_tasks_snapshot=${new_snapshot}, completed_before_round=${new_completed}"
else
  echo "  跳过（state 文件不存在或 jq 不可用）"
fi

echo "=== 崩溃恢复完成 ==="
