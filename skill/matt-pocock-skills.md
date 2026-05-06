# mattpocock/skills 使用说明

## 什么时候启用

当用户明确提到 `mattpocock/skills`，或者任务明显属于下面这些工作流时启用：

- 需求、方案、设计需要被追问和压力测试。
- 需要用 TDD 写功能或修 bug。
- 需要系统诊断 bug、失败测试或性能回退。
- 需要把对话整理成 PRD、issue、任务拆分或 triage。
- 需要评估代码架构、重构方向、上下文和领域语言。
- 需要把视角拉高，解释某段代码在整体系统中的位置。
- 需要创建或改写 skill、文章、课程练习、pre-commit 配置等。

总门槛：

- 这些 skill 只在长程、复杂、多阶段、需求不清或需要系统化流程的任务中触发。
- 如果只是普通小改动、简单问答、单文件小修、小模块局部修改、明确的窄修复，不触发。
- 具体场景命中下面任一 skill 时，也必须先满足这个总门槛。

## 怎么启用

在任务开始时先判断场景，然后读取对应 skill 的 `SKILL.md`。不要一次读完整个
`mattpocock/skills` 仓库，只读当前任务需要的 skill。

常用路径：

- `.codex_home`：
  `/inspire/hdd/project/embodied-multimodality/chenxie-25019/fj/.codex_home/skills/<skill-name>/SKILL.md`
- `.codex_home_api2`：
  `/inspire/hdd/project/embodied-multimodality/chenxie-25019/fj/.codex_home_api2/skills/<skill-name>/SKILL.md`

使用流程：

1. 判断任务是否匹配某个 skill。
2. 打开该 skill 的 `SKILL.md`，只读取必要说明。
3. 按 skill 的流程执行，不要把 skill 当成普通参考资料随便摘用。
4. 如果 skill 要求生成文档、计划、测试或 issue，按它的输出格式交付。
5. 如果 skill 的建议和用户当前指令冲突，以用户当前指令为准，并向用户确认。

## 常用场景

### 追问和压力测试方案

使用：

- `grill-me`
- `grill-with-docs`

触发方式：

- 主要在计划阶段触发。
- 使用子代理执行，让它独立拷问需求、方案、假设和边界。
- 主代理负责整理子代理结论，并决定是否继续问用户或进入实现。

适合：

- 用户说“帮我拷问这个方案”“grill me”“这个设计有没有问题”。
- 需求还不清楚，不能直接实现。
- 需要把项目已有文档、领域词汇、ADR 一起纳入讨论。

怎么做：

1. 先让用户给出方案、目标或约束。
2. 用问题树逐层追问，不急着给实现。
3. 对每个分支确认结论、风险和未决问题。
4. 如果使用 `grill-with-docs`，还要检查 `CONTEXT.md`、`docs/adr/` 等项目文档是否需要同步更新。

产物：

- 明确后的方案。
- 未决问题清单。
- 必要时更新后的上下文文档或 ADR。

### 测试驱动开发

使用：

- `tdd`

触发方式：

- 主要在测试设计、测试优先实现、回归测试和 bug 修复验证时触发。
- 当用户要求先写测试、补测试、用测试证明修复有效，或者任务需要明确验收行为时使用。

适合：

- 用户要求 TDD、test-first、red-green-refactor。
- 功能或 bug 修复适合先定义可验证行为。

怎么做：

1. 先写失败测试，确认失败原因是预期行为缺失。
2. 写最小实现让测试通过。
3. 重构实现，保持测试通过。
4. 每轮只处理一个小的垂直切片。

产物：

- 新增或修改的测试。
- 最小可工作的实现。
- 测试命令和结果。

### 诊断 bug 或性能问题

使用：

- `diagnose`

触发方式：

- 命令报错、测试失败、运行时异常、行为不符合预期或性能明显回退时触发。
- 不要直接猜修复；先复现、缩小范围、提出假设并收集证据。

适合：

- 用户说“debug this”“diagnose this”“这个报错/测试失败/性能变差”。
- 问题原因不明确，不能直接猜修复。

怎么做：

1. 建立可重复反馈环：测试、复现脚本、日志或最小命令。
2. 复现问题，并把现象缩小到最小范围。
3. 提出假设，但每个假设都要有证据验证。
4. 加必要 instrumentation，不靠猜。
5. 修复后补回归测试。
6. 清理临时日志、脚本和调试输出。

产物：

- 根因说明。
- 修复补丁。
- 回归测试或复现命令。
- 清理后的工作树说明。

### PRD、issue 和 triage

使用：

- `to-prd`
- `to-issues`
- `triage`
- `setup-matt-pocock-skills`

触发方式：

- 使用 Git、GitHub、GitLab、issue、PRD 或任务队列管理项目工作时触发。
- 如果项目还没有配置 issue tracker、triage 标签或领域文档位置，先触发 `setup-matt-pocock-skills`。
- 已经有讨论上下文但缺少正式需求文档时用 `to-prd`。
- 已经有 PRD、计划或方案，需要拆成可执行任务时用 `to-issues`。
- 已经有 issue 或任务队列，需要分类、补信息、排序或推进状态时用 `triage`。

适合：

- 用户要把当前讨论整理成 PRD。
- 用户要把计划拆成 issue 或任务。
- 用户要 triage bug、feature request、issue 队列。
- 第一次使用这些 issue/PRD 工作流时，先用 `setup-matt-pocock-skills` 配置项目上下文。

怎么做：

1. 先确认项目使用 GitHub、GitLab 还是本地 markdown issue。
2. 如果上下文未配置，运行 `setup-matt-pocock-skills` 的流程。
3. `to-prd` 负责沉淀问题、方案、用户故事、实现决策、测试决策和 out-of-scope。
4. `to-issues` 负责把 PRD 或计划拆成可独立领取的垂直切片。
5. `triage` 负责按状态机处理 issue，明确 needs-info、ready、blocked 等状态。

产物：

- PRD。
- issue 列表或 issue 内容。
- triage 结果和下一步处理人/条件。

### 架构和代码库理解

使用：

- `improve-codebase-architecture`
- `zoom-out`

触发方式：

- 重构代码、初始化新代码库、接手陌生仓库或理解陌生模块时触发。
- `zoom-out` 用于先建立全局视角；`improve-codebase-architecture` 用于寻找模块边界、耦合点和可执行重构机会。

适合：

- 用户要“看看架构怎么改”“找重构机会”“这块代码在系统里干什么”。
- 需要从局部代码上升到模块边界、领域语言和长期维护性。

怎么做：

1. 先读相关入口、调用关系、测试和项目文档。
2. 用 `zoom-out` 解释局部代码在整体中的角色。
3. 用 `improve-codebase-architecture` 找深层模块边界、耦合点、命名问题、测试困难点。
4. 优先给可验证的小步重构，不做大而空的架构建议。

产物：

- 架构发现。
- 风险和改进机会。
- 可执行的重构计划或小补丁。

### 创建和维护 skill

使用：

- `write-a-skill`

适合：

- 用户要新建 skill、改写 skill、整理 skill 使用规则。

怎么做：

1. 明确 skill 的触发条件，不要写成泛泛的说明文。
2. 保持 progressive disclosure：主 `SKILL.md` 放核心流程，细节拆到引用文件。
3. 只在有必要时增加 scripts、assets、templates。
4. 检查 skill 是否能被 agent 在正确场景自动触发。

产物：

- 新的或更新后的 skill 目录。
- 清晰的 `name`、`description` 和使用流程。

### 其他已安装 skill

- `setup-pre-commit`：给前端/Node 项目配置 Husky、lint-staged、格式化、类型检查和测试钩子。
- `git-guardrails-claude-code`：给 Claude Code 配置危险 Git 命令拦截。Codex 场景只在用户明确要求时参考。
- `scaffold-exercises`：搭建课程练习目录、题目、解法和讲解文件。
- `migrate-to-shoehorn`：TypeScript 测试从 `as` 断言迁移到 `@total-typescript/shoehorn`。
- `edit-article`：重写、润色、调整文章结构。
- `obsidian-vault`：管理 Obsidian 笔记库。
- `caveman`：使用极简表达风格；只有用户明确要求这种风格时使用。

## 使用注意

- 这些 skill 是工作流，不是自动替代用户决策的理由。
- 不确定需求、目标、边界、工具选择或副作用时，先问用户。
- 修改代码前仍然遵守本仓库 `AGENTS.md` 的 Git 规范。
- 长任务同时满足条件时，先用 `planning-with-files` 建立计划文件，再使用对应 Matt Pocock skill。
- 非必要不要启用 deprecated skill。

## 已安装位置

- `/inspire/hdd/project/embodied-multimodality/chenxie-25019/fj/.codex_home/skills`
- `/inspire/hdd/project/embodied-multimodality/chenxie-25019/fj/.codex_home_api2/skills`
