# Loop Design（设计模式）

引导用户从零开始创建一个 Loop 契约文件，输出到 `.loop/contracts/<name>.yaml`。

## 模式选择

支持两种模式，根据用户输入自动判断：

| 模式 | 触发方式 | 适用场景 |
|------|---------|---------|
| 向导模式（默认） | 逐步问答 | 新手、复杂 loop、不确定怎么填 |
| 快速模式 | 用户一次性描述所有需求 | 有经验的用户、改动已有契约 |

### 向导模式流程

逐个字段引导用户填写，一次一个问题。流程如下：

```
问清目标 → 选触发方式 → 确定验证手段 → 定义退出条件 → 填完整契约 → 用户确认
```

**逐个字段的提问脚本：**

1. **目标（objective）：** "这个 Loop 要达成什么目标？请用一句话描述。"
2. **触发方式（trigger）：** "v1 仅支持手动触发（manual）。你每次需要手动启动这个 loop。可以接受吗？"（v1 固定 `manual`）
3. **任务列表（discover.tasks）：** "请列出需要完成的任务。每行一个。v1 要求各任务修改不重叠的文件，且建议合并为单任务（如'修复所有失败的测试'）以保证收敛。**任务列表的顺序即合并验证时的 patch apply 顺序——请将基础性任务排前面、依赖它的任务排后面。**"
4. **任务独立性检查：** 输入完所有任务后，显式提问——"以下任务是否修改不同的文件？请确认。如果多个任务修改同一文件，建议合并为一个。"——列出任务清单交由用户自行判断。不做自动关键词分析（不可靠）
5. **工作区（workspace）：** "maker 将从哪个 git 分支/commit 检出工作区？默认 `origin/main`，若不存在则试 `origin/master`，最后回退到 `HEAD`。你也可以指定具体的 commit SHA。"
6. **额外上下文（context）：** "除了自动注入的 loop-contract.md 外，还需要注入哪些知识文件？如 CLAUDE.md、编码规范等。直接回车跳过。"
7. **maker 模型（delegation.maker.model）：** "maker 使用什么模型？默认 `sonnet`。复杂任务可选 `opus`。"
8. **验证命令（verification.command）：** "用什么 Shell 命令来验证任务是否完成？必须是机器可执行的命令（如 `npm test`）。**不要手写 `timeout` 前缀——系统会自动包装。**"
9. **验证超时（verification.timeout）：** "验证命令超时多少秒？默认 300。"
10. **通过标准（verification.expect）：** "如何判断验证通过？默认检查退出码为 0。你还可以添加：正向断言（输出中必须包含的词，如 'passed'）、负向断言（输出中不得包含的词，如 'fail'）。"
11. **State 路径（state.path）：** "状态文件保存到哪里？默认 `.loop/state/<name>.json`。直接回车使用默认值。"
12. **重试上限（budget.max_retries）：** "每个任务最多重试几次？默认 3。含首次尝试，即 max_retries=3 表示最多 3 次机会。"
13. **整体超时（budget.max_wall_time）：** "整个 loop 最长运行多少秒？默认 1800（30 分钟）。注意：此超时仅在每轮结束时检查，无法中断挂死的 maker。"
14. **升级条件（escalation.on）：** "触发哪些条件时需要升级（通知你并退出 loop）？可选：`no_progress`（连续 N 轮无进展）、`timeout`（整体超时）。`budget_exhausted`（重试耗尽）始终强制生效。单任务建议只选 `timeout`——`no_progress` 在单任务中会提前终止。"
15. **no_progress_limit（仅当选了 no_progress 时）：** "连续几轮无进展触发升级？默认 `max(1, min(2, max_retries - 1))`。举例：若 max_retries=3 则默认值=2（连续 2 轮无进展触发，给 1 轮容错空间）；若 max_retries=2 则默认值=1（第 1 轮失败即触发）。必须小于 max_retries。"
16. **通知方式（escalation.method）：** "升级时如何通知你？`notify`（桌面通知，需 MCP 支持，不可用时自动降级为终端打印+退出）或 `manual`（终端打印+等待你确认）。默认 `notify`。"
16b. （仅当选了 `manual` 时追问）**等待超时（escalation.manual_timeout）：** "升级后等待你确认的最长秒数？超时后自动退出。默认 120 秒。直接回车使用默认值。"

**智能默认值（非必填字段自动填充）：**
- `context` 默认 `[]`
- `state.path` 默认 `.loop/state/<name>.json`
- `no_progress_limit` 默认 `max(1, min(2, max_retries - 1))`（省略时按默认值，单任务契约建议省略）
- `delegation.maker.agent_type` 默认 `"general-purpose"`
- `delegation.maker.model` 默认 `"sonnet"`
- `verification.timeout` 默认 `300`
- `escalation.method` 默认 `"notify"`
- `escalation.manual_timeout` 默认 `120`

### 快速模式流程

1. 让用户一次性描述所有需求（目标、任务、验证方式等）
2. AI 根据描述填充全部 13 字段
3. 从 `reference/loop-patterns.md` 模式库中推荐最接近的模板作为起点
4. **逐段确认**（分 3 段：基本设置 / 验证与预算 / 升级与退出），每段展示当前填充值并允许用户修改
5. 确认无误后输出 YAML

### 输出

最终输出完整的 YAML 契约文件到 `.loop/contracts/<name>.yaml`。输出前执行以下检查：

- **context 文件存在性：** 列出的每个文件路径若不存在则 warn（不 fail——文件可能后续才创建）
- **Windows 路径长度提醒：** 如果检测到 Windows 环境，提醒用户注意项目路径长度（详见 execute 模式的路径硬检查）。建议将项目放在短路径下（如 `D:\work\`）

### 模板推荐

根据用户描述的关键词，从 `reference/loop-patterns.md` 推荐最接近的模式：

| 关键词 | 推荐模板 |
|--------|---------|
| CI、测试失败、修复测试 | CI Sweeper |
| bug、修复、测试用例 | Bug Fix Loop |
| lint、代码质量、类型检查 | Code Quality Loop |
| 重构、架构、提取 | Refactor Loop |
| 扫描、triage、报告 | Daily Triage |
| PR、审查、review | PR Babysitter |
| 依赖、更新、安全漏洞 | Dependency Sweeper |
| changelog、变更日志 | Changelog Drafter |
