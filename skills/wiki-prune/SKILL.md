---
name: wiki-prune
description: 清理知识库 wiki 中的无效内容，包括孤立页面、失效链接、重复内容等
license: MIT
compatibility: opencode
---

## 功能说明

`wiki-prune` 用于清理 wiki 中的无效内容，保持知识库整洁。它会：

- 移除孤立页面（没有任何入链）
- 清理断裂链接（指向不存在页面的链接）
- 合并重复或近似的内容
- 移除过时的临时页面
- 清理空的章节和无效格式

## 执行流程

1. **扫描 `.wiki/` 目录**：收集所有页面
2. **构建链接图谱**：建立页面间关系
3. **识别可清理项**：按类别列出
4. **生成清理报告**：供用户确认
5. **执行清理操作**：删除或合并

## 使用方法

### 预览模式（默认）

```
/wiki-prune
```

只显示报告，不执行删除操作。

### 执行清理

```
/wiki-prune --execute
```

执行实际删除操作。

### 自动清理

```
/wiki-prune --execute --no-confirm
```

执行清理，跳过确认步骤。

### 深度清理

```
/wiki-prune --deep --execute
```

包括：
- 近似内容合并
- 空章节清理
- 格式规范化

## 清理项目

### 0. 幽灵条目清理 (.wiki-processed)

**定义**：`.wiki/.wiki-processed` 中 entries 的 path 指向不存在的源文件

**检查逻辑**：
- 遍历 `.wiki-processed` 的 entries
- 对每条，检查文件是否存在记录路径
- 不存在时，在全 KB 源文件中搜索匹配的 hash
  - 找到匹配 → 文件已移动，自动更新 path（自愈）
  - 未找到匹配 → 文件已删除，移除该条目

**处理策略**：

| 情况 | 操作 |
|------|------|
| 文件已移动（hash 匹配） | 更新 path 为新位置 |
| 文件已删除（hash 无匹配） | 移除该条目 |

**示例报告**：
```
### 幽灵条目清理 (3 个)

已自愈（path 已更新）：
- `papers/old.md` → `archive/paper.md`

已移除（文件已删除）：
- `notes/deleted-note.md`
- `temp/scratch.txt`
```

### 1. 孤立页面

**定义**：没有任何其他页面链接到的页面

**检查逻辑**：
```python
for page in all_pages:
    inlinks = count_incoming_links(page)
    if inlinks == 0 and page != "index.md":
        mark_as_orphan(page)
```

**处理策略**：

| 页面类型 | 默认操作 |
|---------|---------|
| 实体页面 | 移动到 `_deprecated/entities/` |
| 概念页面 | 移动到 `_deprecated/concepts/` |
| 源文件摘要 | 保留（可能有未记录的引用） |
| 分析页面 | 询问用户 |

**示例报告**：

```
### 孤立页面 (3 个)

可移除:
- [[entities/孤立实体.md]]
  最后更新: 2026-03-15
  大小: 512 字节
  
- [[concepts/未引用概念.md]]
  最后更新: 2026-02-20
  大小: 320 字节

需确认:
- [[analysis/某分析.md]]
  创建时间: 2026-01-10
  似乎是手动创建的分析页面

建议操作:
1. 移动到 _deprecated/ 目录 (推荐)
2. 从 index.md 移除条目
```

### 2. 断裂链接

**定义**：指向不存在页面的链接

**检查逻辑**：
```python
for page in all_pages:
    links = extract_wiki_links(page)
    for link in links:
        if not exists(link.target):
            mark_broken_link(page, link)
```

**处理策略**：

| 情况 | 操作 |
|------|------|
| 引用已删除实体 | 移除链接 |
| 引用未创建概念 | 询问是否创建 |
| 路径错误 | 修正路径 |

**示例报告**：

```
### 断裂链接 (4 处)

- [[entities/已删除实体]] 出现于:
  - concepts/某概念.md 第 12 行
  - sources/source-summary.md 第 8 行
  
- [[concepts/未创建]] 出现于:
  - entities/某实体.md 第 5 行

修复建议:
1. 移除断裂链接
2. 创建缺失页面
```

### 3. 重复内容

**定义**：相似度过高的页面内容

**检查逻辑**：
- 计算内容相似度
- 识别可能重复的实体/概念
- 报告相似度 > 80% 的页面对

**处理策略**：

```
### 可能重复 (1 对)

- [[entities/实体A]] 与 [[entities/实体A别名]]
  相似度: 92%
  
建议: 合并为一个页面，将另一个作为别名

合并预览:
  保留: entities/实体A.md
  重定向: entities/实体A别名.md → [[实体A]]
```

### 4. 空章节

**定义**：只有标题没有内容的章节

**示例报告**：

```
### 空章节 (2 处)

- entities/某实体.md
  - "## 详细信息" (空)
  - "## 参考资料" (空)

- concepts/某概念.md
  - "## 相关实体" (空)

建议: 移除空章节或补充内容
```

### 5. 过时临时文件

**定义**：创建已久但从未有用的临时文件

**检查逻辑**：
- 识别命名模式（如 `temp-*`, `draft-*`）
- 检查创建时间
- 检查是否被引用

**示例报告**：

```
### 临时文件 (1 个)

- [[analysis/draft-analysis.md]]
  创建时间: 2026-01-05
  状态: 未完成，无引用
  
建议: 删除或完成
```

### 6. 索引冗余

**定义**：index.md 中的条目指向不存在的页面

```
### 索引冗余 (1 项)

- index.md 引用了 [[entities/已删除.md]]
  该页面不存在

建议: 移除索引条目
```

## 清理报告格式

```markdown
# Wiki 清理报告

生成时间: YYYY-MM-DD HH:MM:SS

## 清理统计

| 项目 | 数量 | 操作 |
|------|------|------|
| 孤立页面 | 3 | 移动到 _deprecated/ |
| 断裂链接 | 4 | 移除 |
| 重复内容 | 1 | 合并 |
| 空章节 | 2 | 删除 |
| 临时文件 | 1 | 删除 |
| 索引冗余 | 1 | 移除条目 |

## 预计空间节省: 2.5 KB

## 任务列表

### 必须确认
- [ ] 合并 [[entities/实体A]] 和 [[entities/实体A别名]]
- [ ] 删除 [[analysis/draft-analysis.md]]

### 可自动执行
- [ ] 移动孤立页面到 _deprecated/
- [ ] 移除断裂链接
- [ ] 删除空章节
- [ ] 清理索引冗余

---
运行 /wiki-prune --execute 执行清理
```

## 执行模式

执行清理时，会：

1. **备份**：将删除的内容备份到 `.wiki/.prune-backup/`
2. **日志**：记录所有删除操作到 `.wiki/log.md`
3. **确认**：逐项确认重大变更

```
/wiki-prune --execute

正在执行清理...

[1/6] 移动孤立页面到 _deprecated/
✓ entities/孤立实体.md → _deprecated/entities/孤立实体.md
✓ concepts/未引用概念.md → _deprecated/concepts/未引用概念.md

[2/6] 移除断裂链接
✓ 修复 concepts/某概念.md (移除 1 个链接)
✓ 修复 sources/source-summary.md (移除 1 个链接)

[3/6] 合并重复内容
? 合并 [[entities/实体A]] 和 [[entities/实体A别名]]? [y/N]

...

清理完成:
- 移动: 2 个页面
- 移除: 4 个链接
- 合并: 1 个页面
- 删除: 1 个空章节

备份位于: .wiki/.prune-backup/YYYY-MM-DD-HHMM/
```

## 回滚机制

如清理后发现问题，可从备份恢复：

```
/wiki-prune --rollback
```

或手动从 `.wiki/.prune-backup/` 目录恢复文件。

## 与其他命令的关系

| 命令 | 关系 |
|------|------|
| `/wiki-lint` | lint 发现问题，prune 执行清理 |
| `/wiki-update` | update 后可能产生孤立页面，用 prune 清理 |
| `/wiki-ingest` | ingest 时避免产生重复，用 prune 清理已有重复 |

## 配置选项

在 `AGENTS.md` 中可配置：

```markdown
## wiki-prune 配置

### 孤立页面处理
- 保留天数: 30 (超过此天数的孤立页面才清理)
- 保护分析页面: true (不自动删除手动创建的分析)

### 重复检测
- 相似度阈值: 0.8 (80% 以上视为可能重复)

### 备份
- 保留备份数量: 5
- 备份目录: .wiki/.prune-backup/

### 临时文件模式
- temp-*
- draft-*
- wip-*
```

## 最佳实践

1. **先 lint 后 prune**：用 lint 发现问题，用 prune 清理
2. **定期清理**：每月运行一次
3. **执行前预览**：默认预览模式，确认后再执行
4. **保留备份**：清理后观察几天再删除备份
5. **渐进清理**：对于大量孤立页面，分批处理

## 与 wiki-capture 的协作

本 skill 执行期间，对话中可能出现对 skill 功能的说明性内容。这些内容属于基础设施域（Layer 0/Layer 1），不应被 wiki-capture 捕获。Agent 在执行本 skill 时应注意：
- 当本 skill 正在处理任务时，抑制 wiki-capture 的自动感知
- 本 skill 完成后，恢复 wiki-capture 的正常监听

## 命令行示例

```bash
# 基本使用
/wiki-prune                    # 预览
/wiki-prune --execute          # 执行（需确认）

# 自动化
/wiki-prune --execute --no-confirm  # 跳过确认

# 深度清理
/wiki-prune --deep --execute

# 回滚
/wiki-prune --rollback
```
