# planning-with-files 使用说明

## 什么时候启用

遇到下面任一情况时自动启用：

- 长任务、多阶段任务、研究型任务或需求不清的任务。
- 预计需要 5 次以上工具调用。
- 任务可能跨会话、需要恢复上下文。
- 需要持续记录发现、决策、错误和验证结果。

简单问答、单文件小改、一次命令能完成的任务，不需要启用。

## 怎么使用

在项目根目录创建并维护三份文件：

- `task_plan.md`：任务目标、阶段、当前状态、决策和错误记录。
- `findings.md`：调研发现、代码结构、外部信息、关键证据。
- `progress.md`：执行日志、已完成动作、检查命令和结果。

基本流程：

1. 开始前创建计划文件，写清目标和阶段。
2. 每完成一个阶段，把 `task_plan.md` 的阶段状态改成 `complete`。
3. 每有重要发现，写入 `findings.md`。
4. 每完成一组操作或遇到错误，写入 `progress.md`。
5. 做重大决策前重新读取 `task_plan.md`。
6. 停止前确认所有阶段状态是否正确。

## 阶段格式

`task_plan.md` 的阶段要使用 hook 能识别的格式：

```markdown
### Phase 1: Requirements

- Clarify goal and constraints.
- **Status:** complete
```

状态只用：

- `pending`
- `in_progress`
- `complete`

不要只写 `1. [complete] ...`，当前 hook 可能无法正确统计阶段数量。
