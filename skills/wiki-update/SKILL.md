---
name: wiki-update
description: 重新处理指定的已处理源文件，当源文件内容更新时使用
license: MIT
compatibility: opencode, claude-code
---

## 功能说明

`wiki-update` 用于重新处理已经处理过的源文件。主要使用场景：

- 源文件内容有更新
- 需要重新提取信息
- 之前处理结果不满意
- 配置变更后需要重新处理

## 执行流程

1. **验证文件状态**：检查文件是否已在 `.wiki/.wiki-processed` 中
   - 如果文件不存在于记录路径 → 按 hash 在全 KB 搜索
     - 找到 → 文件被移动了，更新记录中的 path，继续处理
     - 未找到 → 报告幽灵条目，跳过
   - 如果文件存在 → 正常继续
2. **比较哈希**：判断文件内容是否真正发生变化

### 链接文件更新（`.url`）

对于 `.url` 文件，更新流程与普通文件不同——需要重新获取远程内容：

1. **解析 URL**：从 `.url` 文件提取目标 URL
2. **获取最新内容**：优先 MCP/skill/plugin → fallback webfetch
3. **计算新哈希**：对最新内容计算 SHA-256
4. **比对哈希**：与 `.wiki-processed` 中记录的 `hash` 比较
   - **哈希相同** → 远程内容未变化，跳过更新
   - **哈希不同** → 内容已更新，执行完整 re-ingest
5. **更新缓存**：将最新内容写入 `.wiki/cache/`（覆盖旧缓存）
6. **后续流程**：同普通文件的差异分析、wiki 页面更新、日志记录

### 获取失败处理

更新时 URL 不可达：
- 提示用户「链接不可达，上次成功获取时间为 <timestamp>」
- 选项：[1] 重试 [2] 放弃本次更新（保留现有 wiki 内容） [3] 移除该链接

3. **备份旧信息**：记录将被替换的内容
4. **重新处理**：执行完整的 ingest 流程
5. **更新 wiki**：根据新内容更新相关页面
6. **更新记录**：更新 `.wiki/.wiki-processed` 和 `log.md`

## 视觉内容处理策略

`wiki-update` 在处理已变更的源文件时，对于包含视觉内容的文件类型，遵循与 `wiki-ingest` 相同的视觉处理策略：

- 纯图片文件：委托 `vision-reader` subagent 读取
- 办公文档/网页：两段式处理（Read 取文本 + vision-reader 取视觉）
- Markdown 文件：文本优先，按需读取图片

如果当前客户端未配置 `vision-reader` subagent，则跳过视觉读取，仅处理文本内容。OpenCode 配置路径为 `.opencode/agents/vision-reader.md`，Claude Code 配置路径为 `.claude/agents/vision-reader.md`。

详细流程参见 `wiki-ingest` skill 的「视觉内容处理策略」章节。

## 使用方法

### 更新单个文件

```
/wiki-update path/to/file.md
```

### 更新多个文件

```
/wiki-update file1.md file2.md path/to/file3.json
```

### 更新所有已变更文件

```
/wiki-update --all-changed
```

遍历 `.wiki/.wiki-processed` 所有条目，对每条：
1. 检查文件是否存在记录路径，不存在则按 hash 搜索（自愈）
2. 比对新旧哈希值，找出内容变化的文件
3. 对 hash 未命中任何源文件的条目，报告为幽灵条目
4. 对于 `.url` 文件，重新获取远程内容后比对哈希

### 强制更新（即使内容未变）

```
/wiki-update file.md --force
```

## 处理步骤

对于每个指定的源文件：

### 1. 检查状态

```
正在检查: articles/article.md
- 当前哈希: abc123...
- 记录哈希: def456...
- 状态: 内容已变化 ✓
```

如果哈希相同且无 `--force` 参数：

```
正在检查: notes/note.md
- 当前哈希: xyz789...
- 记录哈希: xyz789...
- 状态: 内容未变化，跳过
- 提示: 使用 --force 强制更新
```

### 2. 记录旧信息

提取旧版本关联的 wiki 页面和内容：

```
记录旧版本信息:
- 关联实体: [[实体A]], [[实体B]]
- 关联概念: [[概念X]]
- 摘要页面: [[sources/article-summary.md]]
```

### 3. 重新处理文件

执行与 `/wiki-ingest` 相同的处理流程：

- 读取文件内容
- 提取实体和概念
- 分析关键信息

### 4. 计算 diff

比较新旧版本的差异：

```
差异分析:
+ 新增实体: 实体C
- 移除实体: 实体B (不再提及)
~ 更新信息: 概念X 的定义有变化
= 保持不变: 实体A 的描述
```

### 5. 更新 wiki 页面

**实体页面更新**：
- 新增实体：创建新页面
- 移除实体：从引用来源中移除该文件的链接（如无其他来源则标记为需确认）
- 更新信息：追加新内容，标注来源更新

**概念页面更新**：
- 同实体页面处理逻辑

**摘要页面更新**：
- 完全替换为新版本摘要
- 记录更新历史

### 6. 处理引用变更

```
处理引用变更:
- 从 [[entities/实体B]] 移除对本文件的引用
  (该实体无其他来源，建议用户确认是否删除)
- 添加 [[entities/实体C]] 的引用
```

### 7. 更新记录

更新 `.wiki/.wiki-processed`：

```json
{
  "path": "articles/article.md",
  "hash": "newhash...",
  "processed": "2026-05-03T15:00:00Z"
}
```

更新 `.wiki/log.md`：

```markdown
## [2026-05-03 15:00] update | articles/article.md

### 变更内容
+ 新增实体: 实体C
- 移除实体: 实体B
~ 更新概念: 概念X

### 影响页面
- [[entities/实体C]] (新建)
- [[entities/实体B]] (引用移除)
- [[concepts/概念X]] (内容更新)
- [[sources/article-summary.md]] (完全重构)

---
```

## 输出格式

### 成功更新

```
✓ 已更新: articles/article.md
  - 哈希: abc123... → def456...
  - 新增实体: 1 个
  - 移除实体: 1 个
  - 更新概念: 1 个
  - 影响页面: 4 个

---
共更新 1 个文件
```

### 批量更新结果

```
/wiki-update --all-changed

扫描已处理文件（遵循 .wiki_ignore 排除规则）: 45 个
发现变更文件: 3 个

✓ 已更新: articles/article1.md
✓ 已更新: notes/note.md
✓ 已更新: references/ref.json

---
共更新 3 个文件，影响 12 个 wiki 页面
```

### 无变更文件

```
/wiki-update articles/unchanged.md

该文件内容未变化，无需更新。
使用 --force 强制重新处理。
```

## 特殊情况处理

### 文件被移动或删除

当更新条目时文件不在记录路径：

1. **自动尝试恢复**：在 `.wiki-processed` 中搜索该条目的 hash，在全 KB 文件中查找匹配
2. **找到匹配文件** → 文件已被移动，更新 path 并继续正常更新流程
3. **未找到匹配** → 文件已被删除，报告幽灵条目

```
/wiki-update path/to/old-file.md

警告: 记录路径 path/to/old-file.md 不存在
正在按 hash 搜索... 找到匹配文件: path/to/new-file.md
已更新记录路径，继续处理...
```

### 实体完全移除

```
在 articles/article.md 更新中，实体 "某人" 不再被提及。

该实体无其他引用来源:
- [[entities/某人.md]]

选项:
1. 保留页面，标注为"需核实"
2. 移动到 .wiki/_deprecated/ 目录
3. 删除页面（不推荐）

请选择 [1/2/3]:
```

### 矛盾信息处理

如果更新后的内容与 wiki 中其他来源矛盾：

```
发现矛盾:
- 本文件: 实体A 的年龄为 28
- [[sources/other-summary.md]]: 实体A 的年龄为 30

处理:
- 在 [[entities/实体A.md]] 添加争议说明
- 标注两个来源的不同观点
```

## 与其他命令的关系

| 命令 | 用途 |
|------|------|
| `/wiki-ingest` | 处理新文件 |
| `/wiki-update` | 重新处理已有文件 |
| `/wiki-init` | 批量初始化（首次） |
| `/wiki-lint` | 可发现需更新的文件 |
| `/wiki-prune` | 可清理更新后的无效引用 |

## 最佳实践

1. **定期检查**：运行 `/wiki-lint` 发现过时信息
2. **增量更新**：修改源文件后及时更新
3. **验证结果**：检查更新后的 wiki 页面
4. **处理冲突**：关注矛盾信息提示

## 与 wiki-capture 的协作

本 skill 执行期间，对话中可能出现对 skill 功能的说明性内容。这些内容属于基础设施域（Layer 0/Layer 1），不应被 wiki-capture 捕获。Agent 在执行本 skill 时应注意：
- 当本 skill 正在处理任务时，抑制 wiki-capture 的自动感知
- 本 skill 完成后，恢复 wiki-capture 的正常监听

## 配置选项

在 `AGENTS.md` 中可配置：

```markdown
## wiki-update 配置

- 自动删除孤立实体页面: false
- 保留更新历史: true
- 强制更新前确认: true
```
