# Loop 契约格式规范

本文件定义 loop-engineering skill 的标准契约格式，供其他 skill（如 executing-plans）程序化引用。包含 13 个字段的完整 schema、验证规则和测试用例。

## 字段定义

### 1. name
- **类型:** string
- **必填:** 是
- **允许字符:** `[a-zA-Z0-9_-]`
- **长度上限:** ≤ 20 字符
- **禁止模式:**
  - 含 `-r<N>` 模式（N 为数字，如 `-r1`、`-r99`）——防止 worktree 命名冲突
  - 以 `.` 开头
  - 以 `-` 结尾——worktree 名 `loop-<name>-r<N>` 中会在 `-r<N>` 前产生双连字符 `--`，工具解析时可能产生歧义
  - 含路径分隔符 `/` 或 `\`
  - 含空格
- **说明:** loop 唯一标识，用于 worktree 目录命名和 state/diff 文件路径

### 2. objective
- **类型:** string
- **必填:** 是
- **说明:** 循环目标，自然语言描述。maker 和 checker 在每轮开始时接收此字段，作为本轮工作的最高目标

### 3. trigger
- **类型:** object
- **必填:** 是
- **字段:**
  - `type`: string，枚举值。v1 仅支持 `manual`
- **默认值:** 无（必填）
- **说明:** v1 所有 loop 均为手动触发。`cron` 等自动触发留给后续版本

### 4. discover
- **类型:** object
- **必填:** 是
- **字段:**
  - `type`: string，枚举值。v1 仅支持 `manual_list`
  - `tasks`: string[]，`type=manual_list` 时必填。任务描述列表
- **约束:** `tasks` 数组不可为空（v1 必须至少 1 个任务）
- **说明:** v1 任务列表在契约中静态定义，执行期间不自动发现或追加新任务。v2 将支持 `ci_failures`、`github_issues` 等自动发现类型

### 5. workspace
- **类型:** object
- **必填:** 是
- **字段:**
  - `type`: string，枚举值。v1 仅支持 `worktree`
  - `base_ref`: string，git ref（分支名、tag、commit SHA）。默认值推导链：`origin/main` → `origin/master` → `HEAD`（每步用 `git rev-parse --verify` 检查，不存在则试下一个；全部失败则拒绝启动）
- **约束:** 必须可被 `git rev-parse --verify` 解析为有效 ref（audit 模式会检查）

### 6. context
- **类型:** string[]
- **必填:** 否
- **默认值:** `[]`（空数组）
- **说明:** 每轮迭代追加传给 maker 的额外知识文件路径列表（相对于项目根目录）。`loop-contract.md` 会自动注入，无需在此列出。注入顺序：loop-contract.md 在前，context 文件在后——后注入的内容在 LLM 注意力窗口中位置更靠后，自然获得更高优先级（软约定）

### 7. delegation
- **类型:** object
- **必填:** 是
- **字段:**
  - `maker`: object，必填
    - `agent_type`: string，子代理类型。v1 使用 `"general-purpose"`
    - `model`: string，执行模型。v1 支持 `"sonnet"` 或 `"opus"`
  - `checker`: object，可选。v2 预留——v1 验证由父会话直接执行，不使用此字段。若显式设置，audit 会 warn 提示"v1 不使用此配置"

### 8. verification
- **类型:** object
- **必填:** 是
- **字段:**
  - `command`: string，必填。必须可 Shell 执行。**不要手写 `timeout` 前缀**——父会话自动用 heredoc 包装：`timeout <N> sh -c "$(cat <<'LOOP_VERIFY_EOF' ... LOOP_VERIFY_EOF)"`。heredoc 定界符 `'LOOP_VERIFY_EOF'`（带单引号）确保命令内容被当作字面量、不展开变量、不处理引号嵌套——verification.command 可含任意字符而不会被包装破坏
  - `timeout`: number，可选。默认 300（秒）
  - `expect`: object，必填。结构化判定标准，全部满足 = pass
    - `exit_code`: number[]，可选。接受的退出码数组，如 `[0]` 或 `[0, 1]`。默认 `[0]`
    - `stdout_contains`: object，可选。正向断言，输出中必须包含这些模式。**全部 pattern 都必须匹配**（AND 语义）。空 patterns 数组 = 跳过
      - `match_mode`: string，`"word"`（默认）| `"substring"` | `"regex"`
      - `patterns`: string[]
    - `stdout_not_contains`: object，可选。负向断言，输出中不得包含这些模式。**任一匹配即 fail**（OR 语义）。空 patterns 数组 = 跳过
      - `match_mode`: string，`"word"`（默认）| `"substring"` | `"regex"`
      - `patterns`: string[]
- **约束:** `exit_code`、`stdout_contains`（非空 patterns）、`stdout_not_contains`（非空 patterns）三者不能同时为空/未指定。若全部省略，任何命令都会 trivially pass——违背"verification 强制机器可验证"的核心设计决策
  - `code_review`: object，可选。maker patch 代码审查闸门
    - `enabled`: boolean，默认 `false`。`true` 时在 verification 命令之前运行代码审查
    - 规则集（不可单独关闭）：bare except / 空 catch（FAIL）、魔法数字（FAIL）、死代码/未使用导入（WARN）、eval/exec/os.system（FAIL）、测试删除（FAIL，硬编码不可关闭）
    - 全部通过或仅 WARN → 继续 verification；任一 FAIL → 跳过 verification，打回 maker 下一轮重做
    - 若省略或 `enabled: false`，仅保留测试删除检测（硬编码）

### 9. state
- **类型:** object
- **必填:** 是
- **字段:**
  - `path`: string，必填。state 文件的相对路径（相对于项目根目录）。父目录必须为 `.loop/state/`，不得含 `..` 穿越
- **默认值:** `.loop/state/<name>.json`

### 10. budget
- **类型:** object
- **必填:** 是
- **字段:**
  - `max_retries`: number，必填。单个任务最大总尝试次数（含首次）。必须 > 0。`max_retries=3` 表示最多 3 次尝试（retry_count: 0, 1, 2）
  - `max_wall_time`: number，可选。整体 loop 最长运行秒数。非硬墙钟——仅在每轮结束时评估，无法中断挂死的 maker。v1 最佳实践，非强制

> **⚠️ `max_retries` 命名说明：** 字段名"retries"暗示"重试次数"，但 v1 语义为**最大总尝试次数**（含首次 run + (max_retries - 1) 次 retry）。`max_retries=1` 时 retry_count 永远到不了 1（首次失败后 retry_count=1 ≥ 1 → 标 failed），即"只试一次、不重试"。如果后续版本引入真正的"重试次数上限"字段，建议新增 `max_attempts` 并废弃此字段。

### 11. escalation
- **类型:** object
- **必填:** 是
- **字段:**
  - `on`: string[]，可选。可选条件开关（OR 语义——任一满足即触发）。有效值：`"no_progress"`、`"timeout"`。空数组 `[]` 合法——此时仅强制条件（`budget_exhausted`、`merge_verification_failed`、`crashed`）生效
  - `method`: string，必填（省略时默认 `"notify"`）。v1 有效值：`"notify"` | `"manual"`。`notify` 依赖 MCP notify 工具，不可用时自动降级为终端打印+立即退出。`manual` 无需任何外部依赖
  - `manual_timeout`: number，可选。manual 模式的等待超时秒数，默认 120
- **强制生效的 escalation 条件（始终启用，不可禁用）：**
  - `budget_exhausted`：所有非 completed 任务都达到 max_retries
  - `merge_verification_failed`：所有 task 单独通过但合并后 verification 不通过
  - `crashed`：不可恢复的环境错误
- **escalation 优先级（决定 `state.escalation_reason` 取值 + 报告标题；v1 所有条件使用同一 method）：**
  `merge_verification_failed` > `timeout` > `budget_exhausted` > `no_progress`

### 12. exit
- **类型:** object
- **必填:** 是
- **字段:**
  - `condition`: string，必填。v1 仅支持 `"all_tasks_completed"`（值必须严格等于此字符串，大小写敏感）
- **说明:** `all_tasks_completed` 要求 state 中所有 task status 均为 `completed`（严格全部通过）。有 failed 任务时不会满足此条件——会先被 `budget_exhausted` escalation 拦截

### 13. no_progress_limit
- **类型:** number
- **必填:** 否
- **默认值:** `max(1, min(2, max_retries - 1))`
- **约束:** 仅当 `escalation.on` 含 `no_progress` 时才生效。必须 < `max_retries`（当 max_retries ≥ 3 时，audit 判 fail）
- **说明:** 连续 N 轮无新任务完成（`newly_completed == 0`）则触发 `no_progress` escalation。pending→failed 不算"进展"，不会重置 streak

## 验证规则汇总

以下约束在 audit 模式中判 **fail**（不满足则拒绝）：

| # | 规则 | 字段 |
|---|------|------|
| 1 | 必须可 Shell 执行 + 有结构化 expect | verification |
| 2 | expect 至少有一个有效判定维度（exit_code/stdout_contains/stdout_not_contains 不能同时为空） | verification.expect |
| 3 | exit_code 为数字数组，match_mode 为有效值 | verification.expect |
| 4 | condition 值必须严格等于 `all_tasks_completed` | exit |
| 5 | tasks 数组不能为空 | discover |
| 6 | max_retries 必须 > 0 | budget |
| 7 | no_progress_limit ≥ 1 且 < max_retries（当 max_retries ≥ 3 且 on 含 no_progress 时，不满足则 fail）。max_retries=1 或 2 时统一判 warn——详见 audit.md 检查项 #10 | no_progress_limit |
| 8 | method 必须为 `notify` 或 `manual` | escalation |
| 9 | state.path 父目录为 `.loop/state/`，不含 `..` | state |
| 10 | name 不含 `-r<N>` 模式 | name |
| 11 | name 长度 ≤ 20 字符 | name |
| 12 | on 非空时必须包含至少一个有效值 | escalation |
| 13 | name 不能以 `-` 结尾 | name |

## 完整示例

最小可运行契约（v1 单任务收敛形态）：

```yaml
loop:
  name: "hello-loop"
  objective: "确保 npm test 全部通过"
  trigger:
    type: manual
  discover:
    type: manual_list
    tasks:
      - "修复所有测试失败"
  workspace:
    type: worktree
    base_ref: "HEAD"
  delegation:
    maker:
      agent_type: "general-purpose"
      model: "sonnet"
  verification:
    command: "npm test"
    timeout: 300
    expect:
      exit_code: [0]
  state:
    path: ".loop/state/hello-loop.json"
  budget:
    max_retries: 3
    max_wall_time: 1800
  escalation:
    on:
      - timeout
    method: manual
  exit:
    condition: all_tasks_completed
```

## match_mode 行为规范

以下测试用例定义三种 match_mode 的精确语义（语言无关）：

| mode | 输入 | pattern | 结果 | 说明 |
|------|------|---------|------|------|
| word | `test FAIL: timeout` | `fail` | ✅ 匹配 | `:` 是词边界，`\b` 在标点处成立 |
| word | `test_failure_recovery passed` | `fail` | ❌ 不匹配 | `_` 不是词边界 |
| word | `FAILED (exit 1)` | `fail` | ❌ 不匹配 | `\b` 不在 `FAILED` 的 `D` 之后成立 |
| substring | `test_failure` | `fail` | ✅ 匹配 | 大小写不敏感子串包含 |
| substring | `TEST FAILURE` | `fail` | ✅ 匹配 | 大小写不敏感 |
| regex | `Error at line 42` | `error at line \d+` | ✅ 匹配 | 大小写不敏感正则 |
| regex | `Error(code: 500)` | `error\(code: \d+\)` | ✅ 匹配 | 特殊字符需显式转义——与 word 模式的自动转义不同 |
| regex | `Error(code: 500)` | `error(code: \d+)` | ❌ 不匹配 | `(` 未转义，被解析为正则分组符——与 word 模式对比：word 模式中 `error(code)` 会被自动转义为 `error\(code\)` |
| word | `Error(code: 500)` | `error(code: \d+)` | — (N/A) | word 模式中 regex 元字符会被自动转义，`\d+` 变为字面量 `\\d\+`——这不是一个有效的 word 模式 pattern。含 regex 语法的 pattern 请用 regex 模式 |

**通用规则：** 三种模式均大小写不敏感。word 模式将 pattern 做 regex 转义后加 `\b` 边界。含特殊字符的 pattern（如 `error(`）word 模式先转义为 `error\(` 再加边界。regex 模式**不自动转义**——特殊字符由用户负责显式写出转义，这是两种模式的本质差异。
