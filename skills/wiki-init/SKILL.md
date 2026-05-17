---
name: wiki-init
description: 批量处理知识库中所有 raw sources 文件，构建初始 wiki 知识库
license: MIT
compatibility: opencode
---

## 功能说明

`wiki-init` 用于首次初始化知识库 wiki。它会扫描知识库中所有符合格式的 raw source 文件，逐个处理并构建初始的 wiki 结构。

## 执行流程

1. **读取配置**：从 `AGENTS.md` 获取知识库配置和约定
2. **扫描文件**：遍历知识库目录，找出所有支持的文件格式
3. **过滤排除**：排除 `.wiki/`、`.opencode/`、`.git/` 目录
4. **检查状态**：读取 `.wiki/.wiki-processed` 确认哪些文件尚未处理
5. **逐个处理**：对每个文件执行 ingest 流程
6. **更新记录**：将处理结果写入 `.wiki/.wiki-processed` 和 `log.md`

## 支持的文件格式

**文本格式**：
- 文档：`.md`, `.txt`, `.rst`, `.org`, `.tex`
- 数据：`.json`, `.yaml`, `.yml`, `.csv`, `.xml`
- 网页：`.html`
- 代码：常见编程语言的源代码文件

**办公文档格式**：
- PDF：`.pdf`
- Word：`.docx`, `.doc`
- PowerPoint：`.pptx`, `.ppt`
- Excel：`.xlsx`, `.xls`
- OpenDocument：`.odt`, `.odp`, `.ods`

**图片格式**：`.png`, `.jpg`, `.jpeg`, `.gif`, `.webp`, `.svg`, `.bmp`

## 视觉内容处理策略

主 agent 可能是纯文本模型，不具备图像/视觉能力。当处理以下需要视觉能力的文件时，应借助 `vision-reader` subagent。

### 触发条件

以下文件类型需要视觉能力处理：
- 纯图片文件：`.png`, `.jpg`, `.jpeg`, `.gif`, `.webp`, `.svg`, `.bmp`
- 办公文档的视觉元素：`.pptx`, `.ppt`, `.pdf`, `.docx`, `.doc`
- 网页和 Markdown 中的嵌入图片

如果 `.opencode/agents/vision-reader.md` 未配置，则跳过视觉读取，仅处理文本内容。

### 两段式处理流程（办公文档 & 网页）

1. 先用 **Read 工具**直接读取文件，获取全部文本内容
2. 再用 **Task 工具**调用 `vision-reader` subagent 读取同一文件，获取视觉元素描述
   - `vision-reader` 的 system prompt 已明确指令只描述视觉元素、不重复文本
   - 兜底规则：如文档文本提取明显不完整，subagent 会补充关键文本信息
3. 合并两段结果进行知识提取

### 完整委托（纯图片）

- 纯图片文件直接用 Task 工具调用 `vision-reader` subagent 读取，获得图片文字描述
- 基于描述进行后续知识提取

### Markdown 文件

- 先用 Read 工具读取 Markdown 文本内容
- 仅当图片引用对理解内容关键时，按需调用 `vision-reader` 单独读取图片

## 处理每个文件的步骤

对于每个 raw source 文件：

1. **读取内容**
   - 文本文件：直接读取全文
   - 办公文档/网页：两段式处理（Read 取文本 + vision-reader 取视觉）
   - 纯图片文件：委托 vision-reader subagent 读取描述

2. **提取关键信息**
   - 识别主要实体（人物、组织、概念、事件等）
   - 提取核心观点和论述
   - 记录重要数据和引用
   - 标注文件来源和时间

3. **创建/更新 wiki 页面**
   - 为每个实体创建页面（如不存在）：`.wiki/entities/实体名称.md`
   - 创建源文件摘要页面：`.wiki/sources/文件名-summary.md`
   - 更新相关的概念页面：`.wiki/concepts/概念名称.md`
   - 在各页面间建立双向链接

4. **更新索引**
   - 更新 `.wiki/index.md` 的页面列表
   - 添加新页面的一行摘要

5. **记录日志**
   - 在 `.wiki/log.md` 添加处理记录

6. **更新处理状态**
   - 在 `.wiki/.wiki-processed` 添加文件记录

## 页面结构规范

### 实体页面 (`entities/`)

```markdown
# 实体名称

## 概述
[一句话描述]

## 详细信息
[从各源文件提取的相关信息]

## 相关实体
- [[实体A]]
- [[实体B]]

## 引用来源
- [[源文件1-summary|源文件1]]
- [[源文件2-summary|源文件2]]

---
*创建时间: YYYY-MM-DD*
*最后更新: YYYY-MM-DD*
```

### 概念页面 (`concepts/`)

```markdown
# 概念名称

## 定义
[概念的定义和解释]

## 相关论述
[从源文件提取的相关讨论]

## 相关实体
- [[实体A]]
- [[实体B]]

## 引用来源
- [[源文件-summary|源文件]]

---
*创建时间: YYYY-MM-DD*
*最后更新: YYYY-MM-DD*
```

### 源文件摘要 (`sources/`)

```markdown
# 源文件名

## 来源信息
- 文件路径: `path/to/file`
- 处理时间: YYYY-MM-DD HH:MM:SS
- 文件类型: [文本/图片]

## 核心内容
[主要内容摘要，2-5 个要点]

## 关键实体
- [[实体A]]: [在该文件中的角色或描述]
- [[实体B]]: [在该文件中的角色或描述]

## 关键概念
- [[概念A]]
- [[概念B]]

## 引用此文件的页面
- [[实体A]]
- [[概念B]]

---
*处理时间: YYYY-MM-DD*
```

## 使用方法

用户调用：

```
/wiki-init
```

## 输出

- 处理进度反馈
- 处理的文件数量统计
- 创建的页面数量统计
- 遇到的问题或警告

## 注意事项

- 对于大型知识库，处理可能需要较长时间
- 如遇到中断，可以重新运行，已处理的文件不会重复处理
- 图片文件会单独处理，优先分析文本内容
- 如果文件内容与已有 wiki 页面存在矛盾，在相关页面标注争议

## 错误处理

- 文件读取失败：跳过并记录错误到日志
- 编码问题：尝试多种编码（UTF-8, GBK, Latin-1）
- 损坏的图片：记录警告，跳过该文件
