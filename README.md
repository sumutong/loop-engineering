# Loop Engineering — AI 编程第四层范式

> Prompt → Context → Harness → **Loop**

**Loop Engineering（循环工程）** 是继 Prompt Engineering、Context Engineering、Harness Engineering 之后的第四层 AI 编程范式。核心理念：**不再手动一句句提示 AI，而是设计循环系统让 AI 按轮次执行、验证、持久化状态、自收敛——任务由人定义，执行由系统驱动。**

## 安装

```bash
npx loop-engineering
```

自动检测 Claude Code / Hermes Agent 项目并安装。

手动指定：

```bash
# Claude Code 插件市场
/plugin install loop-engineering@jnMetaCode
```

## 包含什么

```
skills/loop-engineering/
├── SKILL.md              # 入口路由（意图识别 → 3 模式分发）
├── design.md             # 设计模式（向导 + 快速双模式，13 字段引导）
├── execute.md            # 执行引擎（状态机 + 轮次模型 + 租约锁 + 崩溃恢复）
├── audit.md              # 审查模式（22 项 fail/warn/pass 分级审计）
├── reference/
│   ├── loop-contract.md  # 13 字段契约格式规范（公开接口）
│   └── loop-patterns.md  # 8 个预置 Loop 模式模板
└── scripts/
    ├── acquire-lock.sh   # 租约锁抢锁（jq + grep fallback）
    ├── write-state.sh    # 三段式原子写入
    ├── crash-recovery.sh # 崩溃恢复 6 步
    ├── timeout-detect.sh # timeout 三阶检测
    ├── powershell-fallback.sh # PowerShell 回退
    └── verify-runner.sh  # verification 包装器
```

## 三种模式

| 模式 | 触发词 | 用途 |
|------|--------|------|
| **design** | "帮我设计一个 loop" | 从零创建契约文件，向导或快速模式 |
| **execute** | "运行这个 loop" | 按契约轮次执行，直到收敛或升级 |
| **audit** | "审查这个 loop" | 22 项审计清单，fail/warn/pass 三级 |

## 8 个预置模式模板

| 模式 | 用途 |
|------|------|
| **CI Sweeper** | 自动修复 CI 失败测试，直到全绿 |
| **Bug Fix Loop** | 根据测试用例自动修复 bug |
| **Code Quality Loop** | 扫描修复代码异味，lint + tsc 全过 |
| **Refactor Loop** | 重构 + 行为不变验证 |
| **Daily Triage** | CI/Issue 每日扫描分类报告 |
| **PR Babysitter** | 监控 PR CI 状态 + 审查建议 |
| **Dependency Sweeper** | 依赖更新与安全漏洞检查 |
| **Changelog Drafter** | 自动生成 CHANGELOG.md |

## 执行模型

```
契约加载 → 抢租约锁 → 逐轮执行：
  每轮: maker（全新子代理 + 全新 worktree）
       → verify（父会话直接运行验证命令）
       → decide（全部通过/升级/下一轮）
→ 合并验证 → 完成报告
```

## 与 superpowers 协作

`writing-plans` 生成的 plan 中可标记 loop 型步骤：

```yaml
- task: "修复所有 CI 失败的测试"
  mode: loop
  loop_contract: ".loop/contracts/fix-ci-failures.yaml"
```

`executing-plans` 读到 `mode: loop` 时自动移交给 loop-engineering execute 模式。

## 契约示例

```yaml
loop:
  name: "ci-sweeper"
  objective: "自动修复 CI 失败的测试，直到所有测试通过"
  trigger:
    type: manual
  discover:
    type: manual_list
    tasks:
      - "修复所有 CI 失败的测试"
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
    path: ".loop/state/ci-sweeper.json"
  budget:
    max_retries: 3
    max_wall_time: 1800
  escalation:
    on: [timeout]
    method: notify
  exit:
    condition: all_tasks_completed
```

## License

MIT
