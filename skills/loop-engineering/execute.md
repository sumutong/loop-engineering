# Loop Execute（执行引擎）

加载已有契约文件，按契约运行 loop。**每一轮所有 pending 任务各尝试一次 maker→verify，每轮结束后统一判定 no_progress，未收敛则进入下一轮（全新子代理 + 全新 worktree）。** state 是唯一跨迭代载体。

## 前置条件

- 必须在 git 仓库根目录中运行（`git rev-parse --show-toplevel`）
- 父会话模型必须为 sonnet 或 opus（haiku 拒绝启动）
- Git Bash 环境（Windows：MSYS2 / Git for Windows）
- `timeout` 命令可用（`command -v timeout`）。不可用时需用户显式确认接受无超时保护。Windows Git Bash (MSYS2) 默认不安装 GNU coreutils 的 `timeout`——需单独安装或回退到 PowerShell 无超时模式

## 任务列表来源（v1）

v1 的 `discover.type` 仅支持 `manual_list`。任务列表在契约的 `discover.tasks` 字段中直接定义，**loop 执行期间任务列表是静态的**——checker 不会自动发现或追加新任务。

## Task ID 生成规则

`discover.tasks` 中的任务是字符串列表。执行开始时，父会话**按 `tasks` 数组索引自增编号**：
- `tasks[0]` → `id: "task-0"`
- `tasks[1]` → `id: "task-1"`

**执行期间不应编辑契约的 tasks 数组顺序**——重排会导致 state 中的 task ID 与契约错位。

## 任务独立性约束

v1 要求 `discover.tasks` 中各任务相互独立——修改不重叠的文件或文件区域。原因：每轮 maker 都从 `workspace.base_ref` 全新检出 worktree，task-2 看不到 task-1 的修改。

**验证独立性约束（与文件独立性同等重要）：** `verification.command` 是单一 loop 级命令，每轮每个 task 在只含该 task 修改的全新 worktree 中独立运行。因此该命令**必须对每个 task 可独立通过**。

**v1 最佳适配场景是单任务收敛，不是多任务。** 首选配置：一个 task + 一条整套验证命令，由多轮迭代收敛所有问题。这是 v1 唯一无死锁风险的通用形态。

多任务在 v1 的可行窄缝：每个 task 的验证天然只覆盖自身且互不牵连（如 task-A 只 lint README、task-B 只查独立配置文件），且各 task 修改不重叠的文件。

## State 文件格式

State 文件是 loop 执行期间唯一跨迭代持久化的载体。路径由契约的 `state.path` 字段指定（默认 `.loop/state/<name>.json`）。

### JSON Schema

```json
{
  "loop_name": "hello-loop",
  "status": "running",
  "created_at": "2026-07-13T10:00:00Z",
  "updated_at": "2026-07-13T10:15:00Z",
  "total_rounds": 2,
  "pending_tasks_snapshot": 1,
  "completed_before_round": 0,
  "no_progress_streak": -1,
  "escalation_reason": null,
  "tasks": [
    {
      "id": "task-0",
      "description": "修复所有测试失败",
      "status": "completed",
      "retry_count": 1,
      "hint": null,
      "maker_result": {
        "summary": "修复了 3 个测试用例的断言错误",
        "files_changed": ["src/auth.test.ts", "src/utils.test.ts"],
        "verification_output": "Tests: 15 passed, 0 failed",
        "verdict": "pass",
        "timestamp": "2026-07-13T10:14:00Z"
      },
      "feedback_from_checker": null,
      "prev_patch_applied": false
    }
  ]
}
```

### 字段说明

| 字段 | 类型 | 说明 |
|------|------|------|
| `loop_name` | string | 契约中的 loop 名称（冗余存储，方便恢复时识别） |
| `status` | string | 状态机当前状态：`running` / `completed` / `escalated` / `crashed` |
| `created_at` | string | ISO 8601 时间戳，state 文件首次创建时间 |
| `updated_at` | string | ISO 8601 时间戳，state 文件最后一次写入时间 |
| `total_rounds` | number | 已完成的总轮数（含当前轮）。崩溃恢复时可能需要回退 |
| `pending_tasks_snapshot` | number | 当前轮开始时 `pending + in_progress` 任务数快照，用于 no_progress 检测 |
| `completed_before_round` | number | 当前轮开始前 `completed` 任务数。轮末 `completed` 数减去此值 = 本轮真正完成的任务数 |
| `no_progress_streak` | number | 连续无进展轮数。未启用 no_progress 时为 `-1`（哨兵值） |
| `escalation_reason` | string\|null | 触发 escalation 的原因字符串（终态时有值，运行中为 null） |
| `tasks` | array | 任务列表，按契约 `discover.tasks` 的顺序排列 |
| `tasks[].id` | string | 任务 ID，格式 `task-<N>`，N 为 tasks 数组索引 |
| `tasks[].description` | string | 任务描述（来自契约 `discover.tasks[N]`） |
| `tasks[].status` | string | 任务状态：`pending` / `in_progress` / `completed` / `failed` |
| `tasks[].retry_count` | number | 已尝试次数。首次执行为 0，首次失败后自增为 1 |
| `tasks[].hint` | string\|null | v1 始终为 null。v2 预留：per-task 的执行提示 |
| `tasks[].maker_result` | object\|null | 最近一次 maker 执行结果（pending 时为 null） |
| `tasks[].maker_result.summary` | string | maker 子代理的最终回复摘要 |
| `tasks[].maker_result.files_changed` | string[] | maker 修改的文件列表（来自 `git diff --cached --name-only`） |
| `tasks[].maker_result.verification_output` | string | verification 命令的 stdout（截断至最后 2000 字符） |
| `tasks[].maker_result.verdict` | string | 验证判定：`pass` / `fail` / `undetermined` / `code_review_failed` |
| `tasks[].maker_result.timestamp` | string | ISO 8601 时间戳，本轮 maker 完成时间 |
| `tasks[].feedback_from_checker` | string\\|null | v1.1: 代码审查反馈（code_review_failed 时有值）。v2 预留：checker 审查意见 |
| `tasks[].prev_patch_applied` | boolean | V2: 当前轮是否已 apply 上一轮的 cumulative patch（cumulative 模式时为 true，fresh 模式或首次执行为 false） |

## State 原子写入

使用三段式原子写入保证安全。执行 `scripts/write-state.sh <state_file> <json_content>`。

流程概要：写入 .tmp → 备份当前为 .bak → mv 原子替换 → 更新心跳。

**崩溃窗口分析：**
- 步骤 1 崩溃：丢失本次写入，下次启动从旧 state 恢复——等效于本轮未发生
- 步骤 2 崩溃：.bak 可能指向损坏文件，但 .tmp 完整——下次启动优先读 .tmp
- 步骤 3 崩溃：旧 state 和 .tmp 同时存在——下次启动优先读 .tmp（mtime 更新的文件）

**恢复时读取优先级：**
1. `<state_file>.tmp`（若存在且 mtime > state_file 的 mtime）
2. `<state_file>`（正常路径）
3. `<state_file>.bak`（state_file 损坏或不存在时）
4. 全部不可读 → `CRASHED`

## 状态机

```
                           ┌──────────────────────────────────────────┐
                           │                                          │
                           ▼                                          │
┌──────┐  start  ┌───────────┐  per-task maker done  ┌───────────┐   │
│ IDLE │───────→│ ITERATING │─────────────────────→│ CHECKING  │───┘
└──────┘         └──────┬────┘                       └──────┬────┘
                    │          ▲                        │
                    │          │                        ▼
                    │          │                 ┌─────────────┐
                    │          │                 │  DECIDING   │
                    │          │                 └──────┬──────┘
                    │          │                        │
                    │          │     ┌──────────────────┼──────────────────┐
                    │          │     │                  │                  │
                    │          │     ▼                  ▼                  ▼
                    │          │ ┌─────────┐  ┌──────────────────┐  ┌────────────┐
                    │          │ │COMPLETED│  │ 进入下一轮        │  │ ESCALATED  │
                    │          │ │         │  │ (新子代理+        │  │            │
                    │          │ └─────────┘  │  新worktree)      │  └────────────┘
                    │          │              └──────────┬───────┘
                    │          │                         │
                    │          └─────────────────────────┘
                    ╔══════════════════════════════════════════════════╗
                    ║ 以下转换从任何状态都可能发生：                    ║
                    ║ IDLE/ITERATING/CHECKING/DECIDING → CRASHED       ║
                    ║ 触发：state 损坏且 .bak 不可读、                 ║
                    ║      所有 task worktree 均创建失败、             ║
                    ║      磁盘满/权限错误                              ║
                    ╚══════════════════════════════════════════════════╝
```

| 状态 | 含义 |
|------|------|
| IDLE | 等待开始 |
| ITERATING | maker 子代理正在工作（一轮内可能有多个 maker 顺序执行） |
| CHECKING | 父会话运行 verification（v1）/ checker 子代理（v2） |
| DECIDING | 父会话在一轮结束后做分支判断 |
| COMPLETED | 所有任务完成，loop 成功退出 |
| ESCALATED | 触发升级条件，loop 退出等待人工 |
| CRASHED | 不可恢复的错误（state 损坏且不可恢复、worktree 创建失败、磁盘满/权限错误） |

**终态重启：** `COMPLETED` 和 `ESCALATED` 是终态。用户可通过同名契约重启 loop 回到 `IDLE`——租约锁判定表处理终态时的用户确认，确认后 state 重置。`CRASHED` 需先修复环境问题再重启。

## 启动序列

execute 必须按此顺序执行 9 步。任一"拒绝启动"步骤在抢锁之前终止，不会留下 running 状态或锁残留。

### Step 1: 定位仓库根
```bash
cd "$(git rev-parse --show-toplevel)"
```
不在 git 仓库中 → **拒绝启动**。

### Step 2: 契约最小校验
检查项（手写契约可能跳过 audit 直接 execute，此处做最小校验）：
- `name` 合法：允许字符 `[a-zA-Z0-9_-]`，≤ 20 字符，不含 `-r<N>` 模式，不以 `.` 开头，不以 `-` 结尾，不含 `/` `\` 空格
- `discover.tasks` 非空（空 tasks 会让主循环空转并"虚空为真"判定全部完成）
- `exit.condition` 严格等于 `all_tasks_completed`
- `escalation.method`：省略时先套默认值 `notify`，套用后须 ∈ {notify, manual}
- `context` 中列出的文件是否存在：warn 不 fail（文件可能后续才创建）
- `verification.expect` 至少有一个有效判定维度
- `workspace.base_ref` 可解析：`git rev-parse --verify <base_ref>`。若失败：
  - 用户显式设置了非默认值 → **拒绝启动**（用户指定了无效 ref）
  - 用户未设置（走默认值推导链 `origin/main → origin/master → HEAD`）→ 按推导链逐项 resolve，最终回退到 HEAD。推导链全部失败才拒绝启动

任一 fail 项 → **拒绝启动**。

### Step 3: Windows 路径长度硬检查

**先检测 LongPathsEnabled 注册表：**

```powershell
$longPaths = Get-ItemProperty -Path "HKLM:\SYSTEM\CurrentControlSet\Control\FileSystem" -Name "LongPathsEnabled" -ErrorAction SilentlyContinue
if ($longPaths -and $longPaths.LongPathsEnabled -eq 1) {
  Write-Output "LONGPATHS_ENABLED"
} else {
  Write-Output "LONGPATHS_DISABLED"
}
```

**判定逻辑：**
- `LongPathsEnabled=1` → 有效 MAX_PATH = 32767，阈值放宽到 **32000 字符**（常规项目路径不可能超过，实质跳过此检查）。打印 info 日志。
- `LongPathsEnabled=0` 或注册表键不存在 → 使用传统 MAX_PATH = 260。计算项目路径长度。Git Bash 环境用 `cygpath -w "$(pwd)"`；PowerShell 用 `(Get-Location).Path.Length`。阈值 = 260 - 57（worktree 子路径最坏值） - 50（内部文件路径深度）= **153 字符**。

项目 Windows 路径超过阈值且长路径未启用 → **拒绝启动**，并提示用户两个替代方案：
- **方案 A（推荐）：** 启用 Windows 长路径支持——管理员 PowerShell 执行
  `New-ItemProperty -Path "HKLM:\SYSTEM\CurrentControlSet\Control\FileSystem" -Name "LongPathsEnabled" -Value 1 -PropertyType DWord -Force`，重启后生效。
- **方案 B：** 将项目 clone 到更短的路径下（如 `D:\work\`）

### Step 4: timeout 可用性硬检查

执行 `scripts/timeout-detect.sh` 检测 timeout 可用性（三阶回退：gnu → powershell → none）。

- `gnu` → 使用 heredoc 包装：`timeout <N> sh -c "$(cat <<'LOOP_VERIFY_EOF' ... LOOP_VERIFY_EOF)"`
- `powershell` → **需用户显式确认后才能继续**。确认提示：
  ```
  ⚠️ 当前环境无 GNU timeout，将回退到 PowerShell 执行 verification。
  影响：
  - verification 无超时保护——命令挂死会导致父会话一起挂死
  - verification.timeout=<N> 在 PowerShell 回退下不生效
  建议：安装 GNU coreutils (MSYS2: pacman -S coreutils) 后重启终端
  是否继续？（yes/no）
  ```
- `none` → **拒绝启动**——要求用户安装 MSYS2 coreutils 后再试

**jq 可用性检查（Step 4 附加项）：**
- jq 可用 → 所有 JSON 解析走 jq（精确）
- jq 不可用 → warn——租约锁 JSON 解析使用 grep fallback，极端情况下可能误判
- jq 不可用 + PowerShell 回退 → 额外 warn 建议安装 jq

### Step 5: .gitignore 补写

先检查 `.gitignore` 是否已包含规则，缺失则追加：

```
.loop/*
!.loop/contracts/
.claude/worktrees/
```

只追加不修改——不覆盖项目现有的 unignore 模式。

### Step 6: 父会话模型检查
haiku → **拒绝启动**；sonnet/opus → 继续。

### Step 7: 抢租约锁 + 判定
执行 `scripts/acquire-lock.sh <loop-name>`。按启动判定矩阵处理冷启动 / 运行中(拒绝) / 终态(询问重启) / 崩溃(询问恢复)四类。

退出码：`0` = 抢到锁，`1` = 有实例运行/竞争失败，`2` = STALE_FOREIGN（过期锁来自其他机器 → 询问用户）。

### Step 8: 崩溃恢复
仅当第 7 步判定为崩溃/恢复分支时执行。执行 `scripts/crash-recovery.sh <loop-name>`。

6 步流程：清理孤儿进程 → 清理残留 worktree → 重置 in_progress 任务 → 回退 total_rounds → 孤儿 .patch 检查 → 重算快照。

### Step 9: 进入主循环
置 `state.status = running`，进入主循环。

## 租约锁（Lease Lock）

并发保护 + 崩溃恢复。基于心跳新鲜度的目录锁，`mkdir` 在 NTFS/POSIX 上都是原子操作。

### 锁载体
```
.loop/state/<loop-name>.lock/          ← mkdir 成功 = 抢到锁
    └── meta.json
```

### meta.json 结构
```json
{
  "loop_name": "daily-triage",
  "host": {"hostname": "DESKTOP-ABC", "uname_n": "MSYS_NT-10.0-..."},
  "acquired_at": "2026-07-10T10:00:00Z",
  "heartbeat_epoch": 1750608923,
  "lease_seconds": 1800
}
```

- `lease_seconds` = 1800s（v1 固定值：覆盖最长 maker 运行 + cp node_modules + 余量）
- `host` 区分本机残留 vs 其他机器。检测时两者任一匹配即视为本机

### 心跳写入点
| 时机 | 说明 |
|------|------|
| task 置 in_progress + 写 state | 每轮每个 task 开头 |
| worktree 创建 + `cp -r node_modules` 完成后 | 补心跳——NTFS 上 cp 可达 3-10 分钟 |
| verification 结果落盘 | 每轮每个 task 结尾 |
| 每轮结束写 state | 轮边界 |

> V2 并行模式下，父会话在等待 maker 子代理返回期间每 300s 主动刷新心跳，不再依赖 lease_seconds 覆盖 maker 执行时长。lease_seconds 仅作为崩溃恢复的安全网。
>
> **⚠️ 大 node_modules 风险：** NTFS 上 cp 可达 3-10 分钟，极端情况可能更长。若 cp 耗时超过 1800s 租约，其他进程可能误判锁过期。v1 不做预优化（cp 上限 ~600s << 1800s），仅在此记录风险。

### 启动判定矩阵

`fresh = (now - heartbeat_epoch) < lease_seconds`

| lock 目录 | state.status | 心跳 | host | 判定 |
|-----------|-------------|------|------|------|
| 不存在 | 非 running | — | — | 冷启动，mkdir 抢锁 |
| 不存在 | running | — | — | 锁丢失但状态残留 → 问用户 |
| 存在 | running | fresh | 任意 | 拒绝启动（"另一实例运行中"） |
| 存在 | running | stale | 本机 | 判定崩溃 → 清理残留 → 恢复 |
| 存在 | running | stale | 其他机器 | 问用户 |
| — | completed/escalated | — | — | 终态，提示上次结果，询问是否重新开始 |
| — | crashed | — | — | 提示上次 crashed 原因，询问是否重试 |

锁实现见 `scripts/acquire-lock.sh`。正常退出时 `rm -rf "$lock"`。硬崩溃 → 锁残留，靠下次启动的租约过期自动回收。

## 崩溃恢复

启动时（租约锁判定通过后）执行 `scripts/crash-recovery.sh <loop-name>`。

### 6 步流程

1. **清理孤儿 maker 进程** — 扫描并 kill 以当前 loop name 为标识的残留 maker 子进程（Windows：`tasklist` + `taskkill`；Linux/Mac：`pkill -f claude-code-agent`）
2. **清理残留 worktree** — 扫描 `.claude/worktrees/` 清理以当前 loop name 为前缀的残留 worktree
3. **重置 in_progress 任务** — 所有 `in_progress` 任务重置为 `pending`：清除 summary/files_changed/timestamp，保留 feedback_from_checker
4. **回退 total_rounds** — 若步骤 3 重置了任何 `in_progress` 任务且 `total_rounds > 0`，则 `total_rounds -= 1`。`total_rounds == 0` 时保持不变
5. **孤儿 .patch 检查** — `.loop/diffs/<loop-name>/<task-id>.patch` 存在但对应 task 被重置 → 日志警告，不自动使用
6. **重算快照** — 重新计算 `pending_tasks_snapshot` 和 `completed_before_round`，不沿用崩溃前的旧值

## 执行流程（主循环伪代码）

```
// 启动时：检查 state 文件是否存在
//   存在且 status=running → 崩溃恢复路径
//   不存在 → 冷启动路径
round = state.total_rounds || 0
// ⚠️ 父会话始终保持在项目根 CWD——worktree 操作通过绝对路径进行

while true:
  round++
  total_rounds = round  ← 持久化到 state 文件（每轮开始时落盘）

  // ===== 早期退出检查 =====
  non_completed = tasks where status != "completed"
  if non_completed 非空 AND all(non_completed have retry_count >= max_retries):
    for each task in non_completed:
      task.status = "failed"
    写入 state 文件
    state.status = "escalated"
    state.escalation_reason = "budget_exhausted"
    写入 state 文件
    → escalation（budget_exhausted），直接退出

  // ===== 记录本轮快照 =====
  pending_tasks_snapshot = count(tasks where status == "pending" OR status == "in_progress")
  completed_before_round = count(tasks where status == "completed")
  持久化到 state.pending_tasks_snapshot 和 state.completed_before_round

  // ===== Per-Task 执行（V2 并行引擎） =====
  pending_tasks = tasks where status in ["pending", "in_progress"]
  parallel_count = min(len(pending_tasks), execution.max_parallel)

  // 1. Spawn N makers concurrently — 批量创建 worktree + 启动子代理
  makers = []
  for i in range(parallel_count):
    task = pending_tasks[i]
    if task.retry_count >= budget.max_retries:
      task.status = "failed"
      continue

    task.status = "in_progress"
    写入 state 文件（同时刷新 heartbeat_epoch）

    // 2. 创建 worktree（V2 cumulative 模式：预 apply 上一轮 patch，失败退化为 fresh）
    if retry_strategy == "cumulative" and task 有上一轮的 .patch 文件:
      worktree = git worktree add .claude/worktrees/loop-<loop-name>-r<round>-<task-id> <base_ref>
      result = git -C <worktree> apply <previous .patch>
      if result != 0:
        warn "cumulative patch apply 失败，退化为 fresh 模式"
        task.prev_patch_applied = false
        // worktree 保持干净，maker 从 base_ref 零开始
      else:
        task.prev_patch_applied = true
        log "cumulative 模式：已 apply 上一轮 patch 到 worktree"
    else:
      // fresh 模式：全新检出
      worktree = git worktree add .claude/worktrees/loop-<loop-name>-r<round>-<task-id> <base_ref>
      task.prev_patch_applied = false

    // node_modules 复用（若项目根存在）
    若项目根存在 node_modules → cp -r 到 worktree
      - cp 失败 → 等待 2s → 重试
      - 仍失败 → 降级：rm -rf worktree/node_modules + warn 日志
    若主项目无 node_modules → 提示 maker 需自行 npm install

    写入 state（prev_patch_applied 已记录）
    刷新心跳（cp node_modules 可能很慢）

    // 3. Spawn maker 子代理（全新会话）
    工作目录：worktree 绝对路径
    注入内容（按此顺序）：
      a. worktree 绝对路径（首行）
      b. 当前 state JSON（完整，含上一轮结果）
      c. 契约的 objective + verification.command + verification.expect
      d. 当前 task 描述 + hint（若有）
      e. 上一轮 maker 的 diff 内容（若存在，按截断策略注入——见"Fresh Context"节）
      f. loop-contract.md 内容（契约格式规范）
      g. context 文件列表内容（按配置顺序）

    ⚠️ maker prompt 关键警告：
    - "context 以此处注入的内容为准，勿读取 worktree 内的同名文件"
    - "不要执行 git 命令——所有文件操作由父会话统一管理"

    makers.append(spawn maker 子代理(worktree, task))

  // 4. 并发等待全部 maker 返回 + 每 300s 刷新租约心跳
  //    V2 并行模式下父会话在等待 Promise.all 期间主动刷新心跳
  wait_start = epoch_seconds()
  并发等待全部 makers 返回，期间：
    while makers 未全部返回:
      sleep 300s
      刷新 heartbeat_epoch（touch meta.json 中的 heartbeat_epoch 字段）
      if (epoch_seconds() - wait_start) > lease_seconds:
        warn "maker 执行时间超过租约窗口，心跳已持续刷新，lease 仅作安全网"
      // 若 execution.estimated_maker_runtime 超时 → kill 超时 maker → task 视为失败

  // 5. 顺序处理每个 maker 的结果（state 写入需串行，按 task-id 升序）
  for each 完成的 maker（按 task-id 数值升序）:
    // 4. 内置检查 + 抓取 patch（verification 之前——防测试产物污染）
    (a) 测试删除检查：
        扫描 *.test.* 和 *.spec.* 文件的 deletions vs additions
        仅有删除无新增 → FAIL（maker 删测试让 suite 通过）
        有删有增 → WARN（可能是 rename）
    (b) git -C <worktree> add -A
    (c) git -C <worktree> diff --cached --binary > .loop/diffs/<loop-name>/<task-id>.patch
    (d) git -C <worktree> diff --cached --name-only → task.maker_result.files_changed

    // 4.5 代码审查（maker patch 质量闸门）
    若契约配置了 `verification.code_review.enabled = true`（默认规则集）：
    (e) 扫描 maker 修改的每个文件（来自 files_changed）：
        • bare except（Python）/ 空 catch（JS/TS）→ FAIL + feedback
        • 魔法数字（未命名常量）→ FAIL + feedback（排除 0, 1, -1, 100, 255, 404, 500）
        • 死代码：未使用的 import / 定义后未引用的变量 → WARN + feedback
        • 安全：eval() / exec() / os.system() / subprocess(shell=True) → FAIL + feedback
        • 测试删除检查（已在上方 (a) 覆盖）
    (f) 审查结果：
        • 全部通过或仅 WARN → 继续 verification
        • 任一 FAIL → 跳过 verification，task.maker_result.verdict = "code_review_failed"
          task.maker_result.feedback = 具体违规项列表
          task.retry_count++ ; task.status = "pending"
          → 下一轮 maker 将在 prompt 中收到此 feedback
    若契约未配置 code_review（disabled 或省略）：
    (g) 跳过此步，直接进入 verification

    // 5. 运行 verification
    工作目录：当前 task 的 worktree 根目录
    执行 scripts/verify-runner.sh <command> <timeout> <use_timeout_mode>
    按 verification.expect 逐项判定

    // 6. 验证结果处理
    verdict = pass → task.status = "completed"
    verdict = fail 或 undetermined → task.retry_count++ ; task.status = "pending"
    task.maker_result 更新

    // 7. 写 state 文件（同时刷新 heartbeat_epoch）

    // 8. 即时检查：剩余未处理的 pending 任务 retry_count 是否全部 ≥ max_retries？
    是 → 跳出 per-task 循环，进入下方"一轮结束，统一判定"

    // 9. 删除 worktree（无论通过与否）。失败则记日志不阻塞

  // ===== 冲突预检（V2 新增）=====
  // 收集本轮所有 maker 的有效 patch（排除 code_review_failed 和 verification-failed 的 task）
  valid_tasks = [t for t in makers where t.verdict not in ("code_review_failed")]
  all_patches = [t.patch for t in valid_tasks]
  conflicts = check_file_intersection(all_patches)
  // check_file_intersection：提取各 patch 的 files_changed，检测文件级交集

  if conflicts and merge_strategy == "strict":
    // 严格模式：任何文件冲突直接 escalation
    triggered += "merge_conflict"
    state.escalation_reason = "merge_conflict"
    写入 state 文件
    → escalation（报告冲突文件交集 + 建议合并任务或拆分 loop）

  if conflicts and merge_strategy == "auto":
    // 自动合并模式：尝试 git merge-file 三路合并
    for each conflict_pair (task_i, task_j 修改同一文件 f):
      base = git show <base_ref>:<f>
      current = task_i worktree 中的文件 <f>
      other = task_j worktree 中的文件 <f>
      result = git merge-file <current> <base> <other>
      if result != 0 (冲突标记未自动解决):
        triggered += "merge_conflict"
        state.escalation_reason = "merge_conflict"
        写入 state 文件
        → escalation（报告 merge-file 冲突详情 + 建议手动解决或拆分）
      else:
        log "三路合并成功：<f>（task-<i> ∪ task-<j>）"
        // 更新对应的 .patch 以反映合并结果
        git -C <worktree_i> diff --cached --binary > .loop/diffs/<loop-name>/<task-i>.patch

  // ===== 合并验证轮（V2 增强）=====
  non_empty_patches = 非空 .patch 文件数量
  if non_empty_patches == 0:
    → loop status = "completed"，直接退出（无改动即通过）
    → git commit feat（自动提交收敛结果）
  elif non_empty_patches == 1:
    → loop status = "completed"，直接退出（唯一 patch 已在自身 worktree 验证通过）
    → git commit feat（自动提交收敛结果）
  else:  // ≥2 非空 patch
    // 创建合并 worktree
    mergetree = .claude/worktrees/loop-<loop-name>-merge
    git worktree add "$mergetree" <base_ref>

    // apply 全部有效 patch（排除 code_review_failed 和 verification-failed 的 task）
    applied_patches = []
    for each task in valid_tasks（按 task-id 数值升序）:
      if .patch 为空: skip
      git -C "$mergetree" apply <patch-path>
      if apply 成功:
        applied_patches.append(task)
      else:
        stderr = git apply --check 的输出
        if stderr 含系统级错误:
          state.status = "crashed"
          → escalation（不可恢复的系统错误）
        else:
          warn "patch task-<id> apply 冲突: <stderr>"
          // 继续尝试剩余 patch

    // 运行合并 verification
    运行 verification.command
    通过:
      → loop status = "completed"，退出
      → git commit feat（V2 新增：自动提交合并验证通过的结果）
    不通过:
      // 二分回退策略（V2 新增）：定位导致失败的冲突 patch
      if len(applied_patches) >= 2:
        git worktree remove --force "$mergetree"
        // 逐 patch apply + verify，定位第一个导致 verification 失败的 patch
        mergetree = git worktree add "$mergetree" <base_ref>
        for each patch in applied_patches:
          git -C "$mergetree" apply <patch>
          运行 verification.command
          if 不通过:
            记录 culprit = task-<id>
            break
        triggered += "merge_verification_failed"
        state.escalation_reason = "merge_verification_failed"
        写入 state 文件
        → escalation（报告：culprit patch = task-<id>，建议拆分或合并相关任务）
      else:
        triggered += "merge_verification_failed"
        state.escalation_reason = "merge_verification_failed"
        写入 state 文件
        → escalation（合并验证失败，单 patch 无法二分，建议检查 verification 逻辑）

  // ===== 一轮结束，统一判定 =====
  open_tasks = count(tasks where status != "completed" AND status != "failed")

  // 更新 no_progress_streak
  // 关键：只有 pending/in_progress → completed 才算"进展"
  // pending/in_progress → failed（retry 耗尽）不算进展——那是"失败退出"而非"收敛前进"
  if "no_progress" in escalation.on:
    newly_completed = count(tasks where status == "completed") - completed_before_round
    if newly_completed > 0:
      no_progress_streak = 0   ← 有任务真正完成，清零
    else:
      no_progress_streak++     ← 无任务完成（含全部 pending→failed 或全部 undetermined），累计
  else:
    no_progress_streak = -1    ← 哨兵值：未启用

  // 收集触发的 escalation 条件（非短路——先收集再判定）
  triggered = []
  failed_tasks = count(tasks where status == "failed")
  if failed_tasks > 0 AND count(tasks where status != "completed") == failed_tasks:
    triggered += "budget_exhausted"
  if "no_progress" in escalation.on AND no_progress_streak >= no_progress_limit:
    triggered += "no_progress"
  if "timeout" in escalation.on AND max_wall_time 已设置且已超时:
    triggered += "timeout"

  // 判定退出条件
  if 所有 task status == "completed":
    // 合并验证轮已在上面执行，此处处理已完成路径
    if non_empty_patches <= 1:
      → loop status = "completed"，直接退出
      → git commit feat（V2 新增：单/零 patch 时自动提交收敛结果）
    // 多 patch 合并验证已在上方合并验证轮中处理（git commit feat 在验证通过时触发）

  elif triggered 非空:
    state.status = "escalated"
    state.escalation_reason = 按优先级取最高者：
      merge_verification_failed > merge_conflict > timeout > budget_exhausted > no_progress
    写入 state 文件
    → escalation
  else:
    → 进入下一轮（round++）
```

## 合并验证轮详细流程

> **前置条件：** 非空 `.patch` 文件 ≥ 2 个时才进入此流程。

```
mainroot=$(git rev-parse --show-toplevel)  ← 必须在主项目根 CWD 下执行
mergetree=<mainroot>/.claude/worktrees/loop-<loop-name>-merge

git worktree add "$mergetree" <workspace.base_ref>

for each completed task（按 task.id 中数字部分的数值升序）:
  if .patch 为空: skip
  if .patch 非空: git -C "$mergetree" apply <mainroot>/.loop/diffs/<loop-name>/<task-id>.patch
  if apply 失败:
    stderr=$(git -C "$mergetree" apply --check ... 2>&1)
    if stderr 含系统级错误:
      → state.status = "crashed"（不可恢复的系统错误）
    else:
      → 打印冲突详情 + 各 patch 的 files_changed 交集分析
      → triggered += "merge_verification_failed"

运行 verification.command

通过 → 确认收敛，退出。报告标注"合并验证通过"
不通过 → merge_verification_failed escalation
```

### 合并验证失败的用户解决路径

**escalation 报告必须包含以下诊断信息：**

1. **冲突文件交集分析** — 列出各 patch 修改的文件，标注重叠文件
2. **冲突详情** — `git apply --check` 的完整 stderr 输出
3. **逐 patch 验证结果** — 每个 task 在自身 worktree 中的独立 verification 结果
4. **解决建议（按推荐顺序）：**
   - **方案 A（推荐——合并任务）：** 修改契约将冲突的多个 task 合并为单任务
   - **方案 B（拆分为独立 loop）：** 将冲突的 task 拆到不同 loop 中顺序执行
   - **方案 C（手动修复冲突）：** 用户手动 git apply 各 patch，解决冲突后运行 verification
5. **保存工作产物** — 所有 .patch 文件保留在 `.loop/diffs/<loop-name>/` 中

## Fresh Context Per Iteration（核心约束）

| 约束 | 说明 |
|------|------|
| 每轮 = 新子代理 | 每轮每个任务的 maker 都是全新会话，不继承上一轮的对话上下文 |
| state 是唯一跨迭代载体 | 上一轮的结果、未修复的问题、验证输出，全部通过 state 文件传递 |
| context 文件每轮重新注入 | context 字段列出的文件 + 契约本身在每轮开始时作为 user message 注入 |
| 代码从 base_ref 重新检出 | 每轮全新 worktree，不保留上一轮的代码修改 |

**为什么必须这样：**
- 防止上下文污染：同一会话连续跑 N 轮的讨论会占据上下文窗口
- 防止"自我批改"惯性：新子代理 = 真正的独立审查
- 可恢复性：每轮独立，崩溃后从 state 恢复

**已知取舍——单任务收敛时丢弃代码进度：** 若第 1 轮已正确修好一部分，第 2 轮 maker 在干净 worktree 里只拿到上一轮的 diff 文本，必须从 diff 重新推导已有进度。v1 通过保留 .patch 并注入文本来缓解。v2 的 `retry_strategy: cumulative` 将支持预 apply 上一轮 patch。

**Diff 注入大小限制：**

| 条件 | 注入内容 |
|------|---------|
| diff ≤ 500 行 | 全文注入 |
| diff > 500 行 | 注入 diff 的文件列表（`files_changed`）+ 每个文件的前 50 行 diff + `... (<N> more lines truncated)` 标记 |
| diff > 1000 行 | 仅注入 `files_changed` 列表 + 统计摘要（每个文件的新增/删除行数）+ 提示"diff 过大，请从 state 中的 verification_result 推断上一轮未修复的问题" |

截断阈值使用命名常量 `DIFF_INJECT_FULL_LIMIT=500`、`DIFF_INJECT_TRUNCATE_LIMIT=1000`。

## Worktree 生命周期

```
每轮每个 pending 任务:
  1. git worktree add .claude/worktrees/loop-<loop-name>-r<round>-<task-id> <base_ref>（全新检出）
  2. maker 完成后：git -C <worktree> add -A && git -C <worktree> diff --cached --binary > .loop/diffs/<loop-name>/<task-id>.patch
  3. verify 判定后：
     a. 通过 → git worktree remove --force
     b. 不通过 → 保留 .patch → git worktree remove --force
```

- 不保留 worktree。下一轮 maker 是全新子代理 + 全新 worktree
- maker 的修改不提交、不推送
- v1 不自动创建 PR。产出是 .patch 文件

## node_modules 复用

新 worktree 不含 node_modules（被 gitignore）。父会话在 spawn maker 之前检查项目根目录是否有 node_modules → 有则 `cp -r` 到 worktree。**只用 cp -r 不用 symlink**——防止 maker 污染主项目。

**版本错配风险：** worktree 从 base_ref 检出，其 package.json 可能与主项目当前 node_modules 的版本不一致。execute 启动时检测：用 `git show <base_ref>:package.json` 与主项目 package.json 做 diff——不同则 warn 建议在 worktree 中运行 npm install。

**⚠️ pnpm / yarn PnP 警告：** pnpm 硬链接结构会被 cp -r 破坏，yarn PnP 无 node_modules 目录。v1 仅推荐用于传统 npm 项目。

**⚠️ Windows 符号链接警告：** npm 3+ 部分包使用 symlink，cp -r 在 MSYS2 上可能报错。若遇此问题，建议退回 `npm install`。

## Checker 验证质量警告

v1 checker 分两层：**代码审查（v1.1 新增）** + **verification 命令**。

**代码审查层**（verification 之前运行）：
- 测试文件删除检测
- bare except / 空 catch 检测
- 魔法数字检测
- 死代码 / 未使用导入检测
- 安全风险检测（eval/exec/os.system）

`verification.code_review.enabled: true` 启用全部规则。`false` 或省略则仅保留测试删除检测（硬编码，不可关闭）。

**verification 命令层**（代码审查通过后运行）：
验证质量仍然取决于 `verification.command` 的覆盖度。代码审查是**语法和规范**层面的闸门，不能替代业务逻辑验证。

**已知盲区：**
- maker 删除测试让 suite 通过
- maker 用 try-catch 吞异常
- maker 写通过测试但逻辑错误的实现（如 `return 42` hardcode 期望值）

v2 的 `code_review` 字段已实现代码级审查（见上文「Checker 验证质量警告」节第 4.5 步）。

## Diff 冲突风险

所有 patch 都基于 workspace.base_ref 生成。即使修改同一文件的不同行，第二个 patch 也可能因行号偏移（3 行上下文）而 apply 失败。

**Loop 完成报告的文件交集检测：**
- 同文件重叠 → **error**：违反 v1 任务独立性约束
- 同模块不同文件 → **warn**：行号上下文偏移可能导致 apply 冲突

**推荐 apply 顺序：** 按 task 编号顺序 apply。每 apply 一个 patch 后运行 verification.command 确认通过再继续。

## 错误处理矩阵

| 场景 | 处理方式 |
|------|---------|
| 子代理崩溃（非零退出） | 视为一次失败迭代，retry_count++，不触发 escalation 除非达到 max_retries |
| maker 子代理超时 | Agent 工具不暴露 timeout 参数，v1 无法强制超时。Linux/Mac 靠 tmux/screen 托管；Windows 用 PowerShell `Start-Job` 托管 + `taskkill /F /T` 强制终止 |
| verification 命令挂死 | heredoc 包装的 timeout 杀进程，视同验证失败 |
| state 文件损坏 | 读 .bak → 不可恢复则 status 设为 crashed 并 escalation |
| verification 输出无法解析 | 原始输出写入 state，verdict 标为 undetermined，视为不通过 |
| worktree 创建失败（单 task） | 重试 2 次（间隔 2s），仍失败 → 标该 task 为 failed。只有所有 task 的 worktree 均创建失败才 crashed |
| 多个不同 loop 并发运行 | 不同 loop 的租约锁互不冲突。git worktree add 内部依赖 .git/index.lock——偶发竞争由重试逻辑覆盖 |
| worktree 删除失败 | 记日志警告，不阻塞——残留由下次启动清理兜底 |
| state 写入失败（磁盘满） | 写 crashed 状态本身也会失败——降级为终端打印错误信息并退出 |
| patch 写入失败（磁盘满/权限） | 记日志错误，标该 task 为 failed。合并验证轮检测到 .patch 缺失时跳过该 task |

## 子代理类型

- **maker：** `general-purpose` agent，模型按 `delegation.maker.model` 设置（默认 sonnet），在 worktree 中有写权限
- **验证（v1）：** 父会话直接运行 verification.command + 解析输出，不 spawn checker 子代理
- **父会话（loop 控制器）：** 状态机驱动 + 编排 + 验证。使用当前会话的模型。推理负载——JSON 读写、验证输出解析、escalation 判定

## 运行时产物生命周期

| 目录 | 生命周期 |
|------|---------|
| contracts/ | 永久保留，纳入版本控制 |
| state/ | loop 执行期间持续更新。终态时保留在原位——下次同名 loop 启动时提示上次结果。用户确认重启后移入 archive/ |
| diffs/ | 按 loop name 隔离。loop 完成后保留，下次启动同名 loop 时清理该 loop 的旧 diffs |
| reports/ | 永久保留 |
| logs/ | 每 loop 一个追加文件。execute 启动时检查 >5 个不同 loop → 按修改时间从旧到新循环删除至 ≤5 |
| *.lock/ | 正常退出时删除，崩溃残留由下次启动回收 |

## Agent 调用成本

v1 每轮每个 pending 任务 spawn 1 个 maker Agent（全新会话，无 prompt 缓存）。验证由父会话直接执行（不消耗 AI token）。

| 场景 | 任务数 | max_retries | 最坏情况 |
|------|--------|-------------|---------|
| 轻量 | 2 | 2 | 4 |
| 中等 | 3 | 3 | 9 |
| 重度 | 5 | 3 | 15 |

建议任务数控制在 2-3 个，优先用于 node_modules 较小的项目。

## Loop 完成报告

所有任务完成或 escalation 触发后，父会话生成报告写入 `.loop/reports/<loop-name>-<timestamp>.md`：

```markdown
# Loop Report: <loop-name>
**时间**: <start> - <end>
**结果**: completed | escalated (<reason>)
**总轮数**: N

## 任务
| 任务 | 状态 | 重试次数 | 修改文件 |
|------|------|---------|---------|
| ... | ✅ completed | N | file1, file2 |

## Diff 文件
- [task-0.patch](../diffs/<loop-name>/task-0.patch)

## 文件交集检测
- ✅ 无同文件重叠 | ⚠️ 同模块不同文件 | ❌ 同文件重叠

**推荐 apply 顺序：** 按 task 编号顺序 apply
所有 patch 基于 workspace.base_ref 生成
```

报告同时打印到终端。

## 依赖的 superpowers skills

| 依赖 skill | 用途 |
|------------|------|
| subagent-driven-development | maker 子代理调度 |
| using-git-worktrees | 独立 worktree 隔离 maker |
| verification-before-completion | checker 端的验证哲学 |

## 不做什么（YAGNI）

v1 明确不做以下 15 项，保持 skill 聚焦和可维护：

1. **不做 MCP server**——保持纯 skill 分发，不引入额外服务依赖
2. **不修改任何现有 superpowers skill 文件**——loop-engineering 是独立 skill，零侵入
3. **不内置 cron 调度执行**——父会话手动触发或通过 Claude Code `/loop` 命令实现周期性
4. **不做 loop 间依赖编排（DAG 执行图）**——v1 只做单 loop
5. **loop 控制器不自己做 maker/checker**——只做编排，maker 由子代理执行，checker 由父会话直接验证
6. **不做自动发现**——`discover.type` 仅 `manual_list`
7. **不做多任务共享同一整套 verification 命令**——这是死锁路径，audit 会拒绝
8. **不做 token_limit / time_box**——v1 无跨平台令牌计数和挂钟计时能力
9. **不做并发任务处理**——state 单文件、顺序执行
10. **~~checker 不做代码审查~~**——V2 已通过 `verification.code_review` 实现（见上文「Checker 验证质量警告」节第 4.5 步）
11. **不做任务间依赖处理**——v1 任务必须相互独立
12. **checker 不能"顺手修一下"**——checker 只判定通过/不通过，修改必须由下一轮的全新 maker 重新执行
13. **并发保护通过租约锁实现**——不做额外的进程级锁
14. **不做逐任务 hint**——state 中的 `task.hint` 字段 v1 始终为 null
15. **不做 `retry_strategy` 选择**——v1 同任务重试固定"fresh worktree + 上一轮 diff 文本"策略

以下两项 v1 列于此，V2 已实现：

16. ~~不做并发任务处理~~——V2 已实现：`execution.max_parallel` 支持并行 maker 执行（见主循环伪代码「Per-Task 执行（V2 并行引擎）」节）
17. ~~不做 `retry_strategy` 选择~~——V2 已实现：`retry_strategy: cumulative` 支持累积重试，预 apply 上一轮 patch 到 worktree（见主循环伪代码 worktree 创建步骤）
