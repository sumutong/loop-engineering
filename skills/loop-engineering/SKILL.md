---
name: loop-engineering
description: >
  Design, execute, and audit self-converging AI loops. Loop Engineering is the
  fourth paradigm of AI programming after Prompt, Context, and Harness Engineering.
  Use this skill when the user wants to create automated iteration cycles where AI
  makes changes, verifies them, and converges — tasks are defined by humans,
  execution is driven by the system. (V2: 并行执行 + 累积重试 + 自动合并)
---

# Loop Engineering

Loop Engineering（循环工程）是 AI 编程领域继 Prompt Engineering、Context Engineering、Harness Engineering 之后的第四层范式。核心理念：**不再手动一句句提示 AI，而是设计循环系统让 AI 按轮次执行、验证、持久化状态、自收敛——任务由人定义，执行由系统驱动。**

本 skill 不修改 superpowers 核心框架的任何现有文件。它是一个独立可分享的 skill，同时通过 `reference/loop-contract.md` 契约格式向其他 skill（特别是 executing-plans）暴露公开接口，使 plan 中的 loop 型任务可以被识别和接管。

## V2 新增能力

| 能力 | 默认值 | 说明 |
|------|--------|------|
| 并行执行 | `execution.max_parallel: 4` | 多个 task 的 maker 同时运行 |
| 累积重试 | `execution.retry_strategy: "fresh"` | `"cumulative"` 模式下轮预 apply 上轮 patch |
| 自动合并 | `verification.merge_strategy: "auto"` | 同文件冲突时 git merge-file 三路合并 |

所有新字段均有默认值——V1 契约在 V2 引擎上可直接运行。

## 意图识别

收到用户消息后，判断意图并路由到对应模式：

```
用户意图判断：
├─ "帮我设计一个 loop" / "我想做一个定期..." / "创建一个循环任务"
│   → 加载 design.md（Loop 设计模式）
│
├─ "运行这个 loop" / "启动 loop" / "执行 loop"
│   → 提示用户指定契约文件路径，然后加载 execute.md（Loop 执行模式）
│
├─ "审查/检查这个 loop" / "审计 loop"
│   → 加载 audit.md（Loop 审查模式）
│
└─ 意图不明确（如只说 "loop" 或 "循环"）
    → 询问："你想设计、执行还是审查一个 Loop？"
```

## 执行模式——契约文件定位

当用户要执行 loop 时，按以下优先级定位契约文件：

1. 用户在调用时通过 args 传入契约路径
2. 若未传入，则扫描 `.loop/contracts/` 目录并让用户选择
3. 若目录不存在，提示先用 design 模式创建第一个契约（design 模式会自动创建 `.loop/contracts/` 目录）
4. 若目录为空，提示先用 design 模式创建契约
5. 若用户传入了路径但文件不存在，提示文件不存在，并列出 `.loop/contracts/` 中已有的文件供选择

> **注：** SKILL.md 中 `Skill("loop-engineering")` 写法指 Claude Code 内部 Skill 工具调用——对用户不可见。用户实际入口为自然语言触发意图识别（"运行这个 loop"、"帮我设计一个 loop" 等）或显式 slash 命令（如果有配置）。

## 与 superpowers 的协作

### 两层协作，不修改任何现有 skill 源码

**第一层：plan 中标记 loop 型任务**

`writing-plans` 生成的 plan 文件中，一个步骤可以标记为 loop 型：

```yaml
- task: "修复所有 CI 失败的测试"
  mode: loop
  loop_contract: ".loop/contracts/fix-ci-failures.yaml"
```

**第二层：executing-plans 识别并移交**

`executing-plans` 读到 `mode: loop` 时，不自己执行该步骤，而是提示用户启动 loop-engineering execute 模式。用户确认后，loop-engineering execute 接管，按契约逐轮运行直到收敛。完成后将结果写回 plan 的 step 状态，executing-plans 继续下一个 step。

### 降级行为

executing-plans 已通过 superpowers-zh 项目层增强支持 `mode: loop` 识别（`步骤 2a. Loop 型任务识别与移交`）。如果项目或全局未安装 loop-engineering skill，executing-plans 降级为普通顺序执行该任务。

### 跨 skill 依赖说明

executing-plans 引用 loop-contract 格式时，优先通过 skill 名 `loop-engineering` + 相对路径 `reference/loop-contract.md` 定位（而非硬编码绝对路径）。如果 loop-engineering skill 未安装，executing-plans 应降级为普通顺序执行。合约格式规范以 loop-engineering skill 的副本为准。

## 父会话模型要求

**execute 模式启动时检查当前模型：**
- haiku → **拒绝启动**（推理能力不足以做编排、JSON 解析、escalation 判定）
- sonnet / opus → 正常启动

**SKILL.md 入口提示：执行 loop 时建议切换到 sonnet。**

## 依赖的 superpowers skills

Loop Engineering 不重复实现，而是编排已有能力：

| 依赖 skill | 用途 |
|------------|------|
| subagent-driven-development | maker 子代理调度 |
| using-git-worktrees | 独立 worktree 隔离 maker |
| verification-before-completion | checker 端的验证哲学 |

## 完整场景

```
用户: "帮我设置一个 CI 自动修复流程"
  │
brainstorming → 产出需求描述
  │
writing-plans → plan 中标记 "CI fixer" step 为 mode: loop
  │
executing-plans → 到该 step 时提示用户: "这个任务是 loop 型的，需要启动 Loop Engineering"
  │
用户确认
  │
loop-engineering execute → 按契约：轮次模型 → 收敛 → 退出
  │
executing-plans → 继续下一个 step
```
