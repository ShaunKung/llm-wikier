---
name: wiki-ingest
description: 增量处理新添加到知识库的 raw source 文件，自动检测或手动指定
license: MIT
compatibility: opencode, claude-code, codex
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

0. **文件类型判断**：检查文件扩展名，`.url` 文件进入链接文件处理流程（参见上文「链接文件处理」章节），其他文件按原有流程处理

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
      "hash": "abc123...",
     "processed": "2026-05-03T14:30:00Z"
   }
   ```

## 链接文件处理

`.url` 文件是网络链接的虚拟映射，文件内容为最小 INI 格式：

```ini
[InternetShortcut]
URL=https://example.com
```

链接文件的处理流程与普通文件不同：Agent 需要先获取远程文档内容，再进行知识提取。

### 缓存元数据

`.wiki/cache/` 目录中除缓存内容文件外，还存储对应的元数据文件 `.meta.json`，用于高效变更检测。

**元数据文件路径**：`.wiki/cache/{url_hash}.meta.json`

**格式**：

```json
{
  "url_hash": "sha256-of-url",
  "content_hash": "sha256-of-content",
  "etag": "\"abc123\"",
  "last_modified": "Wed, 21 Oct 2015 07:28:00 GMT",
  "content_type": "text/html",
  "cached_at": "2026-01-01T00:00:00Z"
}
```

- `url_hash`：目标 URL 的 SHA-256 哈希，用于索引缓存文件
- `content_hash`：缓存内容的 SHA-256 哈希，与 `.wiki-processed` 中 `hash` 字段一致
- `etag` / `last_modified`：服务器返回的 HTTP 响应头，用于条件请求；不存在则为 `null`
- `.meta.json` 不计入备份范围（与 `.wiki/cache/` 整体排除规则一致）

### HTTP 条件请求（优化变更检测）

为避免每次处理都完整下载远程内容，采用三级检测策略，优先使用轻量级 HTTP 条件请求判断内容是否变化：

**三级检测流程**：

```
检查 .meta.json 是否存在？
├── 存在且有 etag
│   └── 发送 GET + If-None-Match: <etag>
│       ├── 304 Not Modified → 内容未变，直接使用缓存内容，跳过下载
│       └── 200 OK → 内容已变，使用返回的新内容
│
├── 存在且有 last_modified（无 etag）
│   └── 发送 GET + If-Modified-Since: <last_modified>
│       ├── 304 Not Modified → 内容未变，使用缓存内容
│       └── 200 OK → 内容已变，使用新内容
│
└── 不存在或服务器不支持条件请求
    └── 完整下载 → 计算哈希 → 与缓存哈希比对
        ├── 哈希相同 → 内容未变（更新 .meta.json）
        └── 哈希不同 → 内容已变
```

**实现注意**：
- 对于支持 MCP 工具的环境，优先使用 MCP 工具发送条件请求
- 对于 webfetch 工具，通过其提供的 HTTP 头参数设置条件请求头
- 如所用工具不支持自定义请求头，回退到完整下载 + 哈希比对

### 链接文件处理步骤

1. **解析 URL**：读取 `.url` 文件，提取 `URL=` 后的值
2. **计算 URL 哈希**：对提取的 URL 计算 SHA-256 哈希，用于定位缓存文件和元数据
3. **尝试条件请求**（如上文「HTTP 条件请求」流程）：
   - 读取 `.wiki/cache/{url_hash}.meta.json`（如存在）
   - 按三级检测流程判断内容是否变化
   - 304 → 直接使用缓存内容，跳至步骤 5
   - 200 或需完整下载 → 获取新内容
   - 获取失败时，检查缓存内容作为兜底
4. **缓存内容与元数据**：
   - 将文档内容写入 `.wiki/cache/{url_hash}.{ext}`（扩展名从 Content-Type 推断）
   - 写入 `.wiki/cache/{url_hash}.meta.json`（含 etag、last_modified、content_hash 等）
5. **计算内容哈希**：对文档内容计算 SHA-256 哈希（不是对 `.url` 文件本身计算哈希）
6. **两阶段识别**：使用计算出的内容哈希与 `.wiki-processed` 中的 `hash` 字段比对
7. **知识提取**：与普通文本文件相同的提取流程（识别实体、概念、创建 wiki 页面等）
8. **更新处理状态**：在 `.wiki-processed` 中添加条目，`path` 为 `.url` 文件的相对路径，`hash` 为文档内容的哈希值

### 并行处理（多链接文件加速）

当需要处理多个 `.url` 文件时（`/wiki-ingest` 自动检测模式、`/wiki-init` 批量初始化、`/wiki-update --all-changed`），将链接文件的获取阶段并行化以大幅提升处理速度。

**并行策略**：按阶段拆分——获取阶段并行，知识提取阶段串行。

**步骤**：
1. **分组**：将所有待处理的 `.url` 文件归为一组
2. **并行获取**：为每个 `.url` 文件分派一个 subagent，各自独立执行：
   - 解析 URL
   - 执行条件请求（优先 304 检测）
   - 必要时下载完整内容
   - 缓存内容和写入 `.meta.json`
   - 计算内容哈希
   - 返回结果：`{ url_file_path, status: "unchanged|updated|new|failed", content_hash, cache_path, error }`
3. **收集结果**：主 agent 等待所有 subagent 返回
4. **串行提取**：主 agent 对 `status` 为 `updated` 或 `new` 的结果，按顺序执行知识提取（步骤 5-8）

**效率提升**：N 个 URL 文件的网络获取时间从 O(N × 平均下载时间) 降至 O(max(各 URL 下载时间))，在 5+ 个链接文件时效果显著。

**subagent 需返回的关键信息**：
- `.url` 文件路径（用于 `.wiki-processed` 记录）
- 处理状态：`unchanged`（304/哈希不变）、`updated`（已变化）、`new`（首次处理）、`failed`（获取失败）
- 内容哈希（用于两阶段识别）
- 缓存文件路径
- 错误信息（如失败）

### 链接文件命名

Agent 在首次成功获取链接内容后，应根据文档标题（`<title>` 或 Markdown 的一级标题）重命名 `.url` 文件，使其更具可读性。需同步更新 `.wiki-processed` 中的 `path` 字段。

### 获取失败处理

当 URL 不可达（超时、404、需要认证、反爬等）时：
- 检查 `.wiki/cache/` 中是否有该 URL 的历史缓存
  - **有缓存**：提示用户「链接不可达，是否使用最近一次缓存（<缓存时间>）继续处理？[Y/n]」
  - **无缓存**：提示用户「链接不可达，请选择：[1] 重试 [2] 更新认证信息后重试 [3] 放弃此链接」
- 用户选择放弃时，跳过该链接文件，记录到日志
- 用户选择更新认证时，等待用户操作后重试

### 链接文件移动与拷贝

链接文件的移动/拷贝判定逻辑与普通文件相同（按 path → 按 hash），但 hash 比较的是文档内容哈希而非 `.url` 文件本身。

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

**网络链接格式**：`.url`（Windows Internet Shortcut，内存放目标 URL）

## 视觉内容处理策略

主 agent 可能是纯文本模型，不具备图像/视觉能力。当处理以下需要视觉能力的文件时，应借助 `vision-reader` subagent。

### 触发条件

以下文件类型需要视觉能力处理：
- 纯图片文件：`.png`, `.jpg`, `.jpeg`, `.gif`, `.webp`, `.svg`, `.bmp`
- 办公文档的视觉元素：`.pptx`, `.ppt`, `.pdf`, `.docx`, `.doc`
- 网页和 Markdown 中的嵌入图片

如果当前客户端未配置 `vision-reader` subagent，则跳过视觉读取，仅处理文本内容。OpenCode 配置路径为 `.opencode/agents/vision-reader.md`，Claude Code 配置路径为 `.claude/agents/vision-reader.md`。

### 两段式处理流程（办公文档 & 网页）

1. 先用 **Read 工具**直接读取文件，获取全部文本内容
2. 再调用 `vision-reader` subagent 读取同一文件，获取视觉元素描述（OpenCode 通常使用 Task 工具；Claude Code 使用 Agent/subagent 调用）
   - `vision-reader` 的 system prompt 已明确指令只描述视觉元素、不重复文本
   - 兜底规则：如文档文本提取明显不完整，subagent 会补充关键文本信息
3. 合并两段结果进行知识提取

### 完整委托（纯图片）

- 纯图片文件直接调用 `vision-reader` subagent 读取，获得图片文字描述
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
