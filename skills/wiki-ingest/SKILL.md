---
name: wiki-ingest
description: 增量处理新添加到知识库的 raw source 文件，自动检测或手动指定
license: MIT
compatibility: opencode
---

## 功能说明

`wiki-ingest` 用于增量处理新添加到知识库的文件。它可以自动检测未处理的文件，也可以手动指定要处理的文件。

## 执行流程

### 自动检测模式（无参数）

1. **读取处理记录**：从 `.wiki/.wiki-processed` 获取已处理文件列表
2. **扫描文件**：遍历知识库目录，读取 `.wiki_ignore` 并按规则排除匹配的文件和目录
3. **两阶段识别**：对每个扫描到的文件：

   **阶段一（快速路径）**：在 `.wiki-processed` 中搜索 `path` 等于该文件相对路径的条目。
   - 找到 → 已处理，跳过
   - 未找到 → 进入阶段二

   **阶段二（hash 兜底）**：计算该文件的 SHA-256 哈希，在 `.wiki-processed` 所有条目中搜索相同 hash。
   - hash 命中 → 文件被移动或拷贝了，进入"移动与拷贝处理"（见下文）
   - hash 未命中 → 真正的新文件，进入处理流程

4. **处理文件**：对真正的新文件，逐个执行 ingest 流程

### 手动指定模式

1. **验证文件**：检查指定的文件是否存在
2. **检查状态**：如果已处理，提示用户使用 `/wiki-update`
3. **处理文件**：执行 ingest 流程

## 使用方法

### 自动检测所有新文件

```
/wiki-ingest
```

### 指定特定文件

```
/wiki-ingest path/to/file.md
```

### 指定多个文件

```
/wiki-ingest file1.md file2.json path/to/file3.txt
```

## 处理步骤

对于每个 raw source 文件：

1. **计算文件哈希**
   - 使用 SHA256 计算文件内容哈希
   - 用于后续判断文件是否变更

2. **读取内容**
   - 文本文件：直接读取全文
   - 办公文档/网页：两段式处理（Read 取文本 + vision-reader 取视觉）
   - 纯图片文件：委托 vision-reader subagent 读取描述
   - 编码问题：自动尝试 UTF-8、GBK、Latin-1

3. **提取关键信息**
   - 识别主要实体（人物、组织、概念、事件等）
   - 提取核心观点和论述
   - 记录重要数据和引用
   - 标注文件来源和时间

4. **创建/更新 wiki 页面**
   
   **实体页面** (`.wiki/entities/`)：
   - 检查实体是否已存在页面
   - 不存在则创建，存在则追加信息
   - 在"引用来源"部分添加新链接
   - 更新"最后更新"时间
   
   **概念页面** (`.wiki/concepts/`)：
   - 类似实体页面的处理流程
   
   **源文件摘要** (`.wiki/sources/`)：
   - 创建新的摘要页面
   - 列出所有提取的实体和概念

5. **建立双向链接**
   - 在实体页面添加指向源文件摘要的链接
   - 在源文件摘要列出引用该文件的页面

6. **处理矛盾**
   - 如果新信息与已有信息矛盾
   - 在相关页面添加 `## 争议` 或 `## 不同观点` 章节
   - 分别列出不同观点及其来源

7. **更新索引**
   - 在 `.wiki/index.md` 添加新页面条目
   - 按类别组织（实体、概念、源文件）

8. **记录日志**
   - 在 `.wiki/log.md` 添加处理记录

9. **更新处理状态**
   - 在 `.wiki/.wiki-processed` 添加条目：
   ```json
   {
     "path": "relative/path/to/file.md",
     "hash": "sha256:abc123...",
     "processed": "2026-05-03T14:30:00Z"
   }
   ```

## 移动与拷贝处理

当两阶段识别中 hash 命中已有条目时，表示文件路径发生了变化（移动/重命名）或存在副本。按以下逻辑判定和处理：

### 判定逻辑

```
hash 命中已有条目（旧路径 = matched_entry.path）
  │
  ├── 旧路径对应的文件是否存在？
  │     ├── 不存在 → 判定为"移动"
  │     └── 存在   → 判定为"拷贝"
  │
  两种情况的处理方式见下文。
```

### 处理移动

1. **更新 path**：将 `.wiki-processed` 中匹配条目的 `path` 字段更新为当前文件的新路径
2. **修复 wiki 引用**：在 `.wiki/*.md` 中搜索旧路径引用，精确定位到 `## 来源信息` 区域内的 `- 文件路径:` 行，将该行路径更新为新路径。不修改任何正文内容
3. **不重新入库**：文件内容未变，不需要重复处理
4. **记录日志**：在 `.wiki/log.md` 记录移动事件

### 处理拷贝

1. **注册条目**：在 `.wiki-processed` 中添加新的条目，`path` 为当前路径，`hash` 和 `processed` 与匹配条目相同
2. **不重新入库**：文件内容已存在，跳过处理
3. **记录日志**：在 `.wiki/log.md` 记录拷贝检测

### 操作提示

- 可用 `jq`（`jq '.entries[] | select(.hash=="<hash>")'`）、Python 或 PowerShell 操作 `.wiki-processed` JSON
- 计算哈希：`sha256sum` / `shasum -a 256` / `Get-FileHash -Algorithm SHA256`
- 修复引用时仅在 `## 来源信息` 章节内替换 `- 文件路径:` 行的值，不做全文替换

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

## 输出格式

### 成功输出

```
✓ 已处理: articles/new-article.md
  - 创建实体页面: entities/作者名.md
  - 更新概念页面: concepts/核心概念.md
  - 创建摘要: sources/new-article-summary.md
  - 识别实体: 5 个
  - 识别概念: 3 个

---
共处理 1 个文件，创建 2 个页面，更新 3 个页面
```

### 无新文件

```
没有发现新文件需要处理。
所有文件均已处理，如需重新处理请使用 /wiki-update
```

### 发现矛盾

```
⚠ 发现矛盾信息: articles/new-article.md
  - 实体 "某人物" 的年龄信息与 entities/某人物.md 不一致
  - 已在相关页面添加争议说明
```

## 与其他命令的关系

- `/wiki-init`：批量初始化所有文件，适合首次使用
- `/wiki-ingest`：增量处理新文件，适合日常使用
- `/wiki-update`：重新处理已处理的文件，适合内容更新

## 与 wiki-capture 的协作

本 skill 执行期间，对话中可能出现对 skill 功能的说明性内容。这些内容属于基础设施域（Layer 0/Layer 1），不应被 wiki-capture 捕获。Agent 在执行本 skill 时应注意：
- 当本 skill 正在处理任务时，抑制 wiki-capture 的自动感知
- 本 skill 完成后，恢复 wiki-capture 的正常监听

## 错误处理

- **文件不存在**：报告错误，跳过该文件
- **文件已处理**：提示使用 `/wiki-update`
- **读取失败**：记录错误，继续处理其他文件
- **编码问题**：尝试多种编码，如均失败则跳过

## 示例场景

### 场景 1：添加新文章后全局检测

用户添加了 3 篇新文章到知识库：

```
/wiki-ingest
```

系统自动检测并处理这 3 篇文章。

### 场景 2：处理特定文件

用户只想处理一个特定的 PDF 转换后的 md 文件：

```
/wiki-ingest papers/my-paper.md
```

### 场景 3：批量指定

用户知道要处理哪些文件：

```
/wiki-ingest notes/note1.md notes/note2.md references/ref.json
```
