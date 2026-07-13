# Loop Audit（审查模式）

审查已有契约文件，按严重程度分三级输出：**不通过（fail）/ 警告（warn）/ 通过（pass）**。每项给出具体修改建议。

## 审查清单

以下 27 个检查项按字段分组。每项标注判定级别、精确的判定条件和修复建议。

### verification 字段组

**1. verification 是否机器可验证**
- **级别:** fail
- **条件:** `verification.command` 必须存在且为非空字符串，`verification.expect` 必须存在。拒绝纯自然语言描述如"AI 自己判断是否通过"
- **修复:** 提供可 Shell 执行的命令 + 结构化 expect 字段

**2. verification.expect 是否可解析**
- **级别:** fail
- **条件:** `exit_code` 为数字数组（如 `[0]` 或 `[0, 1]`），`stdout_contains`/`stdout_not_contains` 格式有效（含 `match_mode` 和 `patterns`），`match_mode` 为 `word` / `substring` / `regex` 之一
- **修复:** 确保 exit_code 是数字数组格式，match_mode 为三个有效值之一

**3. verification.expect 至少有一个有效判定维度**
- **级别:** fail
- **条件:** `exit_code`、`stdout_contains`（非空 patterns）、`stdout_not_contains`（非空 patterns）三者不能同时为空/未指定。若全部省略，任何命令都会 trivially pass——违背"verification 强制机器可验证"的核心设计决策
- **修复:** 至少设置 `exit_code: [0]` 作为最基本的通过闸门

**3.5. verification.code_review 配置检查**
- **级别:** warn
- **条件:** `verification.code_review.enabled` 未配置或为 `false`
- **说明:** 未启用代码审查意味着 maker 的代码质量不受控——bare except、魔法数字等不会被拦截。强烈建议生产 loop 启用
- **修复:** 添加 `verification.code_review.enabled: true`

### escalation 字段组

**4. escalation.on 含 timeout ↔ max_wall_time 不配套**
- **级别:** warn（两个方向均 warn）
- **条件 A:** `escalation.on` 含 `timeout` 但 `budget.max_wall_time` 未设置 → timeout 永不触发
- **条件 B:** `budget.max_wall_time` 已设置但 `escalation.on` 不含 `timeout` → max_wall_time 独立无效
- **修复:** 同时设置或同时移除

**5. escalation.on 是否有效**
- **级别:** fail（on 非空时）
- **条件:** 空 `on`（`[]`）合法——`budget_exhausted` 始终强制兜底。`max_retries > 5` 且 `on` 为空时 **warn**"仅靠重试上限兜底，可能跑满 N 轮才终止"。`on` 非空时必须包含至少一个有效值（`no_progress` 或 `timeout`）
- **修复:** 添加至少 `timeout` 或让 on 为空（接受仅靠 budget_exhausted 兜底）

**6. escalation.method 是否有效**
- **级别:** fail
- **条件:** 值必须为 `notify` 或 `manual`（大小写敏感）
- **修复:** 改为 `notify` 或 `manual`

### V2 并行/合并字段组

**24. V2 parallel.execution_mode 是否有效**
- **级别:** fail（parallel 已配置时）| pass（未配置 parallel 时）
- **条件:** `parallel.execution_mode` 值必须为 `concurrent`、`sequential` 或 `adaptive` 之一。v1 契约无 parallel 配置时为 pass（v2 特性尚未启用）
- **修复:** 改为 `concurrent`（最快）、`sequential`（顺序执行）或 `adaptive`（根据资源自动选择）

**25. V2 parallel.max_concurrency 约束**
- **级别:** warn（parallel 已配置时）| pass（未配置时）
- **条件:** `parallel.max_concurrency` 若设置，须 ≥ 1 且 ≤ 任务数。值为 0 或超过任务数时 warn"无实际并发效果"；未设置时采用默认值 1（即顺序执行，等同于 sequential 模式）
- **修复:** 设为 `min(4, len(tasks))` 或保留默认值

**26. V2 merge.strategy 是否有效**
- **级别:** fail（merge 已配置时）| pass（未配置 merge 时）
- **条件:** `merge.strategy` 值必须为 `auto`、`manual` 或 `per_file` 之一。v1 契约无 merge 配置时为 pass
- **修复:** 改为 `auto`（自动合并）、`manual`（人工确认）或 `per_file`（逐文件合并）

**27. V2 并行任务验证命令独立性**
- **级别:** fail（parallel 已启用 + 多任务 + 单条 verification.command 且无 task-scope 参数时）
- **条件:** v2 并行模式下每个 task 的 verification 必须可独立执行。若 `parallel` 已配置、任务数 > 1、且 `verification.command` 为单一整套命令而无 per-task scope 参数，则各 task 无法独立验证——并行优势丧失且可能死锁
- **修复:** 为每个 task 添加独立验证命令（v2 支持 per-task `verification.command`），或合并为单任务

### exit 字段组

**7. exit.condition 值是否合法**
- **级别:** fail
- **条件:** v1 仅支持 `all_tasks_completed`——值必须**严格等于**此字符串（大小写敏感，其他值一律 fail）
- **修复:** 改为 `all_tasks_completed`

### delegation 字段组

**8. maker/checker 模型配置**
- **级别:** warn（checker 已设置时，无论模型是否相同）| pass（checker 未设置/省略时）
- **条件:** v1 验证由父会话直接执行，**任何 checker 配置在 v1 都是死字段**。checker 省略时不 warn（v1 推荐做法）；一旦设置就 warn 提示"v1 不使用 checker，此配置无效（含 model/agent_type）"；若与 maker **同模型**额外附注"且违反 v2 的模型分离约束"
- **修复:** 删除 checker 配置块（v1 推荐），或忽略此 warn（已知 v2 会启用）

### budget 字段组

**9. budget.max_retries 是否设置**
- **级别:** fail
- **条件:** 必须存在且 > 0
- **修复:** 设置 `max_retries: 3`（推荐默认值）

### no_progress / no_progress_limit 字段组

**10. no_progress_limit 约束**
- **级别:** 取决于 max_retries——见下表
- **条件:** 省略即采用默认值 `max(1, min(2, max_retries - 1))`，按默认值套用约束

| max_retries | no_progress_limit 约束 | 审计级别 | 说明 |
|-------------|----------------------|---------|------|
| 1 | — | warn（若 escalation.on 含 no_progress）\| pass（若不含） | max_retries=1 时 no_progress 会在第 1 轮末触发（streak 达 no_progress_limit=1），与 budget_exhausted（第 2 轮开头标 failed）几乎同轮、结果一致——冗余但无害。建议移除 no_progress 以简化。不含时 budget_exhausted 已保证终止，pass |
| 2 | ≥ 1 | warn | 交互复杂——取决于任务数和收敛速度。单任务时两者等价（retry_count 达 2 后 failed）；多任务时 no_progress 可能因其他任务的 open_tasks 不变而先触发。统一 warn 交由用户判断 |
| ≥ 3 | ≥ 1 且 < max_retries | fail | 给 no_progress 先触发的机会。no_progress_limit ≥ max_retries 意味着 budget_exhausted 会先触发——no_progress 被遮蔽，违背"no_progress 应先于 budget_exhausted 触发"的设计意图 |

**11. 单任务 + escalation.on 含 no_progress**
- **级别:** warn
- **条件:** `discover.tasks` 仅 1 个任务 + `escalation.on` 含 `no_progress`
- **说明:** 单任务每轮 `newly_completed` 始终为 0（失败轮回退为 pending）→ `no_progress_streak` 每轮递增——实际重试次数 = `no_progress_limit`（而非 `max_retries`）。注意 `no_progress_limit ≥ max_retries` 在 `max_retries≥3` 时会被审计判 fail，故**不能**靠调大 `no_progress_limit` 让 no_progress 后触发
- **修复:** 直接从 `escalation.on` 移除 `no_progress`，仅靠 `budget_exhausted` 兜底（此时实际重试次数 = `max_retries`）

**12. no_progress_limit 已设置但 escalation.on 不含 no_progress**
- **级别:** warn
- **条件:** 字段显式写了值但 `escalation.on` 不含 `no_progress`。`no_progress_streak` 仍被追踪但永不触发 escalation——no_progress_limit 在此配置下无实际作用
- **修复:** 若意图仅靠 `budget_exhausted` 兜底，**直接省略该字段**（省略即用默认值、不触发此 warn；仅在**显式写出**时才 warn）

### discover 字段组

**13. discover.tasks 是否非空**
- **级别:** fail
- **条件:** v1 必须至少有 1 个任务
- **修复:** 添加至少一个任务描述

**14. 多任务 + verification 疑似整套命令**
- **级别:** fail
- **条件:** 多个任务时 `verification.command` 须对每个 task 可独立通过。启发式：命令含 `test`/`build`/`lint` 等整套关键字且无明显 task 作用域参数（如 `--` 后跟具体文件/用例）→ fail"多任务配整套命令导致死锁：每个 task 单独永远无法通过（其他 task 未修复 → 整套命令失败 → retry_count 递增 → 全部耗尽 max_retries）。请合并为单任务'修复所有失败'，或等待 v2 的 per-task 验证命令"
- **修复:** 合并为单任务"修复所有失败"，或为每个 task 添加 per-task 验证命令（v2）

**15. 多任务 + verification 带 scope 参数**
- **级别:** warn
- **条件:** 命令含 scope 参数（如 `npm test -- <file>`、`tsc <file>`）但只有一条命令 → warn"单一 scope 无法同时覆盖所有 task：不匹配该 scope 的 task 会 trivially pass（假通过），匹配的 task 又可能因其他 task 未修复而失败。共享一条验证命令的多任务在 v1 无可行配置，请合并为单任务或等待 v2 的 per-task 验证命令"
- **修复:** 合并为单任务，或等待 v2

### state 字段组

**16. state.path 是否有效**
- **级别:** fail
- **条件:** 合法相对路径，父目录为 `.loop/state/`，不含 `..` 穿越
- **修复:** 使用 `.loop/state/<name>.json` 格式

### context 字段组

**17. context 文件是否存在**
- **级别:** warn
- **条件:** 列出的每个文件路径若不存在则 warn（不 fail——可能是后续才创建的）
- **修复:** 确认文件名拼写正确，或在需要时再创建

**18. context 文件大小**
- **级别:** warn
- **条件:** 单个文件超过 5000 字（约 300 行）。context 每轮注入 maker，多轮累积成本显著
- **修复:** 精简 context 文件或拆分为多个小文件按需引用

### workspace 字段组

**19. workspace.base_ref 是否有效**
- **级别:** warn
- **条件:** `git rev-parse --verify <base_ref>` 检查。无效 ref 会导致 worktree 创建失败，虽为运行时错误但 audit 提前发现可减少失败
- **修复:** 确认 ref 存在（`git branch -a` 或 `git log --oneline`）

### name 字段组

**20. name 是否含 `-r<数字>` 模式**
- **级别:** fail
- **条件:** name 匹配 `-r[0-9]+` 模式（如 `-r1`、`-r99`）。会与 worktree 命名冲突（`loop-<name>-r<round>` 中的分段歧义）
- **修复:** 移除 `-r<N>` 后缀或改用下划线

**21. name 是否以 `-` 结尾**
- **级别:** fail
- **条件:** name 以 `-` 结尾（如 `"sweeper-"`）。worktree 名会变成 `loop-sweeper--r1-task-0`（双连字符），工具解析时可能产生歧义
- **修复:** 去掉末尾的 `-`

**22. name 长度**
- **级别:** fail
- **条件:** 必须 ≤ 20 字符。name > 20 会使 worktree 子路径超出"路径长度硬性检查"的 57 字符估算（固定部分最坏约 37 + name），绕过检查后在运行时炸 Windows MAX_PATH
- **修复:** 缩短 name

## 输出格式

审查完成后输出三级汇总：

```
## Audit Result: <contract-name>

### ❌ 不通过（N 项）
- [ ] **检查项名称**: 具体问题 → 修复建议
...

### ⚠️ 警告（N 项）
- [ ] **检查项名称**: 具体问题 → 修复建议
...

### ✅ 通过（N 项）
...

**结论:** 通过 / 有警告可接受 / 不通过需修复
```
