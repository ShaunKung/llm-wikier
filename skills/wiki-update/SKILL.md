---
name: wiki-update
description: 重新处理指定的已处理源文件，当源文件内容更新时使用
license: MIT
compatibility: opencode
---

## 功能说明

`wiki-update` 用于重新处理已经处理过的源文件。主要使用场景：

- 源文件内容有更新
- 需要重新提取信息
- 之前处理结果不满意
- 配置变更后需要重新处理

## 执行流程

1. **验证文件状态**：检查文件是否已在 `.wiki/.wiki-processed` 中
2. **比较哈希**：判断文件内容是否真正发生变化
3. **备份旧信息**：记录将被替换的内容
4. **重新处理**：执行完整的 ingest 流程
5. **更新 wiki**：根据新内容更新相关页面
6. **更新记录**：更新 `.wiki/.wiki-processed` 和 `log.md`

## 视觉内容处理策略

`wiki-update` 在处理已变更的源文件时，对于包含视觉内容的文件类型，遵循与 `wiki-ingest` 相同的视觉处理策略：

- 纯图片文件：委托 `vision-reader` subagent 读取
- 办公文档/网页：两段式处理（Read 取文本 + vision-reader 取视觉）
- Markdown 文件：文本优先，按需读取图片

如果 `.opencode/agents/vision-reader.md` 未配置，则跳过视觉读取，仅处理文本内容。

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

比对 `.wiki/.wiki-processed` 记录的哈希值，找出所有内容有变化的文件。

### 强制更新（即使内容未变）

```
/wiki-update file.md --force
```

## 处理步骤

对于每个指定的源文件：

### 1. 检查状态

```
正在检查: articles/article.md
- 当前哈希: sha256:abc123...
- 记录哈希: sha256:def456...
- 状态: 内容已变化 ✓
```

如果哈希相同且无 `--force` 参数：

```
正在检查: notes/note.md
- 当前哈希: sha256:xyz789...
- 记录哈希: sha256:xyz789...
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
  "hash": "sha256:newhash...",
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
  - 哈希: sha256:abc123... → sha256:def456...
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

扫描已处理文件: 45 个
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

### 文件被删除

```
/wiki-update deleted/file.md

错误: 文件不存在
建议:
1. 如文件已删除，考虑运行 /wiki-prune 清理相关引用
2. 或将文件恢复后重新运行
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

## 配置选项

在 `AGENTS.md` 中可配置：

```markdown
## wiki-update 配置

- 自动删除孤立实体页面: false
- 保留更新历史: true
- 强制更新前确认: true
```
