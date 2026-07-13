# Loop 模式库

预置 8 个常见 Loop 模式模板。每个模式包含适用场景说明和完整 YAML 契约示例，可直接复制使用或在 design 模式中作为起点。

## 模式概览

| 模式 | 触发方式 | 用途 |
|------|---------|------|
| CI Sweeper | manual | 自动修复 CI 失败的测试，直到全部通过 |
| Bug Fix Loop | manual | 根据测试用例自动写修复 → 跑全量测试 → 收敛 |
| Code Quality Loop | manual | 扫描代码异味 → maker 修复 → checker 验证 → 收敛 |
| Refactor Loop | manual | 重构目标 → maker 执行 → checker 验证行为不变 → 收敛 |
| Daily Triage | manual | 扫描 CI/Issue，生成 triage 报告 |
| PR Babysitter | manual | 监控 PR，自动审查反馈 |
| Dependency Sweeper | manual | 依赖更新与安全检查 |
| Changelog Drafter | manual | 自动生成变更日志 |

> 注：v1 所有模式触发方式均为 `manual`（cron 留给后续版本）。Daily Triage / PR Babysitter 等天然周期性场景建议配合 Claude Code `/loop` 命令使用。

## CI Sweeper

**适用场景：** CI 流水线失败，需要自动修复测试。这是 v1 最成熟、推荐首选的模式。

**特点：** 单任务 + 整套 `npm test`。由多轮迭代收敛所有失败——这是 v1 唯一无死锁风险的通用形态。

```yaml
loop:
  name: "ci-sweeper"
  objective: "自动修复 CI 失败的测试，直到所有测试通过"
  trigger:
    type: manual
  discover:
    type: manual_list
    tasks:
      - "修复所有 CI 失败的测试，直到 npm test 全部通过"
  workspace:
    type: worktree
    base_ref: "origin/main"
  context:
    - "CLAUDE.md"
  delegation:
    maker:
      agent_type: "general-purpose"
      model: "sonnet"
  verification:
    command: "npm test"
    timeout: 300
    expect:
      exit_code: [0]
      stdout_contains:
        match_mode: word
        patterns:
          - "passed"
  state:
    path: ".loop/state/ci-sweeper.json"
  budget:
    max_retries: 3
    max_wall_time: 1800
  escalation:
    on:
      - timeout
    method: notify
  exit:
    condition: all_tasks_completed
```

**关键设计决策：**
- 不加 `stdout_not_contains: ["fail", "error"]`——`npm test` 冗长输出中独立单词 fail/error 极常见（测试标题如 `it('returns error on ...')`、文件名 `PASS src/error.test.js`），word 模式会误命中 → 明明测试全绿却判 fail → 假 budget_exhausted。`exit_code: [0]` + `stdout_contains: ["passed"]` 已足够。**如果需要更严格的验证**（防止测试框架崩溃但最后一行恰好打印了 "passed" 的假阳性，或 `exit_code=0` 但部分测试被跳过），可用 regex 模式做精确匹配。以下是常见测试框架的推荐 regex，可直接复制使用：
  - **Jest:** `Tests:\s+\d+\s+passed,\s+0\s+failed,\s+0\s+skipped`（Jest 30+ 默认输出格式，同时确保无 skipped 测试）
  - **Mocha:** `\d+\s+passing\s+\(`
  - **Vitest:** `Tests\s+\d+\s+passed\s+\(`
  - **pytest:** `\d+\s+passed`
  v1 默认不启用此严格模式（不同测试框架的统计行格式各异，通用性差），留给具体项目的契约自行添加
- 不放 `no_progress` 在 `escalation.on` 中——单任务每轮 `open_tasks` 不变，`no_progress` 会在耗尽 `max_retries` 前提前终止

## Bug Fix Loop

**适用场景：** 有明确的测试用例，需要写代码让测试通过。

```yaml
loop:
  name: "bug-fix"
  objective: "根据测试用例修改实现代码，使所有测试通过"
  trigger:
    type: manual
  discover:
    type: manual_list
    tasks:
      - "修复所有失败的测试用例"
  workspace:
    type: worktree
    base_ref: "origin/main"
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
    path: ".loop/state/bug-fix.json"
  budget:
    max_retries: 3
    max_wall_time: 1800
  escalation:
    on:
      - timeout
    method: notify
  exit:
    condition: all_tasks_completed
```

**区别于 CI Sweeper：** Bug Fix Loop 面向实现代码修改（而非测试修复），verification 侧重"已有测试全量通过"。如果测试本身就有问题，应使用 CI Sweeper。

## Code Quality Loop

**适用场景：** 扫描代码异味并自动修复。

```yaml
loop:
  name: "code-quality"
  objective: "扫描并修复代码异味，直到 lint 和类型检查全部通过"
  trigger:
    type: manual
  discover:
    type: manual_list
    tasks:
      - "修复所有 lint 错误和类型错误"
  workspace:
    type: worktree
    base_ref: "origin/main"
  delegation:
    maker:
      agent_type: "general-purpose"
      model: "sonnet"
  verification:
    command: "npm run lint && npx tsc --noEmit"
    timeout: 300
    expect:
      exit_code: [0]
  state:
    path: ".loop/state/code-quality.json"
  budget:
    max_retries: 3
    max_wall_time: 1800
  escalation:
    on:
      - timeout
    method: notify
  exit:
    condition: all_tasks_completed
```

## Refactor Loop

**适用场景：** 重构代码的同时确保行为不变。

```yaml
loop:
  name: "refactor"
  objective: "执行重构任务，同时确保所有现有测试继续通过"
  trigger:
    type: manual
  discover:
    type: manual_list
    tasks:
      - "重构 src/auth 模块，提取公共逻辑到独立的 service 层"
  workspace:
    type: worktree
    base_ref: "origin/main"
  delegation:
    maker:
      agent_type: "general-purpose"
      model: "sonnet"
  verification:
    command: "npm test"
    timeout: 600
    expect:
      exit_code: [0]
      stdout_contains:
        match_mode: word
        patterns:
          - "passed"
  state:
    path: ".loop/state/refactor.json"
  budget:
    max_retries: 2
    max_wall_time: 3600
  escalation:
    on:
      - timeout
    method: notify
  exit:
    condition: all_tasks_completed
```

**注意事项：** 重构通常涉及较大范围改动，建议 `max_retries` 设低（2 次）以减少成本。`max_wall_time` 设高（3600s）给足单轮时间。

## Daily Triage

**适用场景：** 每日自动扫描 CI/Issue，生成分类报告。

```yaml
loop:
  name: "daily-triage"
  objective: "扫描 CI 失败和新增 Issue，按严重程度分类并生成 triage 报告"
  trigger:
    type: manual
  discover:
    type: manual_list
    tasks:
      - "扫描 CI 最近 24 小时的失败"
      - "扫描新增 Issue"
      - "生成 triage 报告到 .loop/reports/"
  workspace:
    type: worktree
    base_ref: "origin/main"
  delegation:
    maker:
      agent_type: "general-purpose"
      model: "sonnet"
  verification:
    command: "test -f .loop/reports/daily-triage-*.md && echo 'report generated'"
    timeout: 120
    expect:
      exit_code: [0]
      stdout_contains:
        match_mode: substring
        patterns:
          - "report generated"
  state:
    path: ".loop/state/daily-triage.json"
  budget:
    max_retries: 1
    max_wall_time: 600
  escalation:
    on: []
    method: notify
  exit:
    condition: all_tasks_completed
```

**注意事项：** 此模式的 3 个任务修改不重叠的文件（各自产出独立报告或分析结果），满足 v1 任务独立性约束。建议配合 Claude Code `/loop` 命令实现每日触发。

## PR Babysitter

**适用场景：** 监控 PR 的 CI 状态，发现问题时自动审查并提供修复建议。

```yaml
loop:
  name: "pr-babysitter"
  objective: "监控指定 PR 的 CI 状态，发现问题时生成审查报告和修复建议"
  trigger:
    type: manual
  discover:
    type: manual_list
    tasks:
      - "获取 PR CI 状态"
      - "分析失败原因"
      - "生成修复建议报告"
  workspace:
    type: worktree
    base_ref: "origin/main"
  delegation:
    maker:
      agent_type: "general-purpose"
      model: "sonnet"
  verification:
    command: "test -f .loop/reports/pr-babysitter-*.md && echo 'ok'"
    timeout: 120
    expect:
      exit_code: [0]
  state:
    path: ".loop/state/pr-babysitter.json"
  budget:
    max_retries: 1
    max_wall_time: 600
  escalation:
    on: []
    method: notify
  exit:
    condition: all_tasks_completed
```

## Dependency Sweeper

**适用场景：** 自动检查依赖更新和安全漏洞。

```yaml
loop:
  name: "dep-sweeper"
  objective: "检查 npm 依赖更新和安全漏洞，生成更新报告"
  trigger:
    type: manual
  discover:
    type: manual_list
    tasks:
      - "运行 npm outdated 检查过期依赖"
      - "运行 npm audit 检查安全漏洞"
      - "生成依赖更新报告"
  workspace:
    type: worktree
    base_ref: "origin/main"
  delegation:
    maker:
      agent_type: "general-purpose"
      model: "sonnet"
  verification:
    command: "test -f .loop/reports/dep-sweeper-*.md && echo 'ok'"
    timeout: 120
    expect:
      exit_code: [0]
  state:
    path: ".loop/state/dep-sweeper.json"
  budget:
    max_retries: 1
    max_wall_time: 600
  escalation:
    on: []
    method: notify
  exit:
    condition: all_tasks_completed
```

## Changelog Drafter

**适用场景：** 自动从 git 历史生成变更日志。

```yaml
loop:
  name: "changelog"
  objective: "从 git 提交历史自动生成 CHANGELOG.md"
  trigger:
    type: manual
  discover:
    type: manual_list
    tasks:
      - "分析自上次 release 以来的所有提交"
      - "按类型分类（feat/fix/breaking/docs）"
      - "生成 CHANGELOG.md 草稿"
  workspace:
    type: worktree
    base_ref: "origin/main"
  delegation:
    maker:
      agent_type: "general-purpose"
      model: "sonnet"
  verification:
    command: "test -f CHANGELOG.md && grep -q '## ' CHANGELOG.md && echo 'ok'"
    timeout: 120
    expect:
      exit_code: [0]
  state:
    path: ".loop/state/changelog.json"
  budget:
    max_retries: 1
    max_wall_time: 600
  escalation:
    on: []
    method: notify
  exit:
    condition: all_tasks_completed
```
