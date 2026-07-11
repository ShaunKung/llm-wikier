# 知微 (zhiwei)

知微（zhiwei）—— 见微知著，Agent Skills 驱动的个人知识库构建工具。安装时可选启用 Claude Code 或 Codex 支持（二者互斥），同一个个人知识库可以被 OpenCode 与 Claude Code 或 OpenCode 与 Codex 混合使用。

该项目受 Andrej Karpathy 的 [llm-wiki](https://gist.github.com/karpathy/442a6bf555914893e9891c11519de94f) 启发而开发。

## 核心理念

传统 RAG 系统在每次查询时都从原始文档重新检索和推理，知识无法累积。知微采用不同的方式：

- **持久化 Wiki**：LLM 增量构建并维护一个结构化的 markdown wiki
- **知识复利**：每次添加新源时，自动提取关键信息、更新相关页面、标注矛盾
- **编译一次，持续更新**：知识只编译一次，而非每次查询重新推导

## 功能特性

- **wiki-init**：批量处理现有所有 raw sources，构建初始 wiki
- **wiki-ingest**：增量处理新添加的文件，自动检测或手动指定
- **wiki-query**：基于 wiki 回答问题，答案可沉淀为新页面
- **wiki-lint**：健康检查（矛盾、孤立页、缺失链接等）
- **wiki-update**：重新处理指定的已处理源文件
- **wiki-prune**：清理无效引用、删除孤立页面
- **wiki-capture**：从对话中主动抓取新知识，检测冲突并邀请用户裁决

## 支持的文件格式

**文本格式**：`.md`, `.txt`, `.json`, `.yaml`, `.yml`, `.csv`, `.xml`, `.html`, `.rst`, `.org`, `.tex` 以及各种代码文件

**办公文档格式**：`.pdf`, `.docx`, `.doc`, `.pptx`, `.ppt`, `.xlsx`, `.xls`, `.odt`, `.odp`, `.ods`

**图片格式**：`.png`, `.jpg`, `.jpeg`, `.gif`, `.webp`, `.svg`, `.bmp`

**网络链接格式**：`.url`（Windows Internet Shortcut 格式，内存网页 URL）

## 安装

### 前置要求

- [OpenCode](https://opencode.ai) 已安装
- 如需混合使用：[Claude Code](https://docs.anthropic.com/en/docs/claude-code) 或 [OpenAI Codex CLI](https://developers.openai.com/codex) 已安装
- 已有一个知识库文件夹（可包含多层子目录和现有文件）

### 推荐方式：npm CLI（跨平台）

```bash
# 从 npm 全局安装知微 CLI
npm install -g @shaunkung/zhiwei

# 安装到目标知识库
zhiwei init /path/to/your/knowledge-base
```

安装过程中会询问是否需要支持除 OpenCode 之外的其它客户端。当前可选 Claude Code 或 Codex（二者互斥），默认不启用，保持 OpenCode-only 模式。

#### 强制覆盖 / 更新安装

```bash
# 强制模式：自动确认所有步骤（适合更新安装）
zhiwei init /path/to/your/knowledge-base --force

# 指定客户端模式（跳过交互选择）
zhiwei init /path/to/your/knowledge-base --mode codex
# 或
zhiwei init /path/to/your/knowledge-base -m claude
```

### 备用方式：Shell / PowerShell 脚本（无需 npm）

#### Mac / Linux

```bash
# 克隆仓库
git clone https://github.com/ShaunKung/zhiwei.git
cd zhiwei

# 添加执行权限
chmod +x install.sh

# 安装到目标知识库
./install.sh /path/to/your/knowledge-base
```

#### Windows (PowerShell)

```powershell
# 克隆仓库
git clone https://github.com/ShaunKung/zhiwei.git
cd zhiwei

# 安装到目标知识库
.\install.ps1 "C:\path\to\your\knowledge-base"
```

PowerShell 安装器与 Mac/Linux 安装器行为一致，也会在安装或更新时询问是否启用 Claude Code 或 Codex 支持。

### 客户端模式

| 模式 | 选择 | skills 安装位置 | 说明 |
|------|------|----------------|------|
| OpenCode-only | 不启用其它客户端 | `.opencode/skills/wiki-*` | 当前默认方案，主要服务 OpenCode |
| OpenCode + Claude Code | 启用 Claude Code | `.claude/skills/wiki-*` | Claude Code 原生读取 `.claude/skills`；OpenCode 通过 Claude-compatible skill discovery 读取同一份 skills |
| OpenCode + Codex | 启用 Codex | `.agents/skills/wiki-*` | Codex 原生读取 `.agents/skills`（open agent skills 标准）；OpenCode 通过 agent-compatible skill discovery 读取同一份 skills |

Claude Code 和 Codex 互斥：知识库启用 Codex 时关闭 Claude Code 支持，但 OpenCode 始终保留。混合模式不会复制两份 skills，也不会创建软链接，避免 OpenCode 同时发现 `.opencode/skills`、`.claude/skills`、`.agents/skills` 中的同名 skill。

### 更新安装与模式切换

对已安装的知识库再次运行安装脚本会进入更新安装模式：

- 已支持 Claude Code 的知识库，默认继续支持 Claude Code
- 已支持 Codex 的知识库，默认继续支持 Codex
- 未支持其它客户端的知识库，默认保持 OpenCode-only
- 任意两种模式间可双向切换；切换时 知微管理的 `wiki-*` skills 会从旧目录迁移到新目录
- 切换到 OpenCode-only 时，移除知微托管的 Claude Code 和 Codex 配置
- Claude ↔ Codex 切换：skills 在 `.claude/skills` 与 `.agents/skills` 间迁移，同时清理对应托管文件（CLAUDE.md 区块 / `.claude/agents/vision-reader.md` ↔ `.codex/agents/vision-reader.toml`）
- 安装器只移除知微管理的 `.claude/`、`.codex/`、`.agents/` 中的托管文件，不会递归删除用户自定义内容

## 安装后的目录结构

### OpenCode-only 模式

```
<知识库根目录>/
├── AGENTS.md                    # Schema 配置文件
├── .wiki_ignore                 # 文件排除规则（类 .gitignore）
├── output/                      # 用户自产文件目录（不会被 ingest）
├── .wiki/
│   ├── index.md                 # Wiki 内容目录
│   ├── log.md                   # 操作日志
│   ├── .wiki-processed          # 已处理文件记录
│   ├── entities/                # 实体页面
│   ├── concepts/                # 概念页面
│   ├── sources/                 # 源文件摘要
│   └── analysis/                # 分析与综合页面
├── .opencode/
│   ├── skills/                  # Skills 目录
│   │   ├── wiki-init/SKILL.md
│   │   ├── wiki-ingest/SKILL.md
│   │   ├── wiki-query/SKILL.md
│   │   ├── wiki-lint/SKILL.md
│   │   ├── wiki-update/SKILL.md
│   │   ├── wiki-prune/SKILL.md
│   │   ├── wiki-capture/SKILL.md
│   │   └── wiki-backup/
│   └── agents/                  # Subagent 配置（可选）
│       └── vision-reader.md     # 视觉读取 subagent
└── [原有的 raw sources]         # 保持不变
```

### OpenCode + Claude Code 模式

```
<知识库根目录>/
├── AGENTS.md                    # Schema 配置文件，OpenCode 直接读取
├── CLAUDE.md                    # Claude Code 入口，托管区块通过 @AGENTS.md 引入 schema
├── .wiki_ignore                 # 文件排除规则（类 .gitignore）
├── output/                      # 用户自产文件目录（不会被 ingest）
├── .wiki/
│   ├── index.md
│   ├── log.md
│   └── .wiki-processed
├── .claude/
│   ├── skills/                  # 混合模式下的唯一知微 skills 目录
│   │   ├── wiki-init/SKILL.md
│   │   ├── wiki-ingest/SKILL.md
│   │   ├── wiki-query/SKILL.md
│   │   ├── wiki-lint/SKILL.md
│   │   ├── wiki-update/SKILL.md
│   │   ├── wiki-prune/SKILL.md
│   │   ├── wiki-capture/SKILL.md
│   │   └── wiki-backup/
│   └── agents/
│       └── vision-reader.md     # Claude Code 视觉读取 subagent
├── .opencode/
│   └── agents/                  # OpenCode vision-reader 配置（可选）
│       └── vision-reader.md
└── [原有的 raw sources]         # 保持不变
```

### OpenCode + Codex 模式

```
<知识库根目录>/
├── AGENTS.md                    # Schema 配置文件，OpenCode 和 Codex 同时原生读取（无需托管入口）
├── .wiki_ignore                 # 文件排除规则（类 .gitignore）
├── output/                      # 用户自产文件目录（不会被 ingest）
├── .wiki/
│   ├── index.md
│   ├── log.md
│   └── .wiki-processed
├── .agents/skills/              # 唯一知微 skills 目录（OpenCode 与 Codex 共享）
│   ├── wiki-init/SKILL.md
│   ├── wiki-ingest/SKILL.md
│   ├── wiki-query/SKILL.md
│   ├── wiki-lint/SKILL.md
│   ├── wiki-update/SKILL.md
│   ├── wiki-prune/SKILL.md
│   ├── wiki-capture/SKILL.md
│   └── wiki-backup/
├── .codex/agents/
│   └── vision-reader.toml       # Codex 视觉读取 subagent（安装器托管）
└── .opencode/agents/            # OpenCode vision-reader 配置（可选，由 config_vision_reader 生成）
    └── vision-reader.md
```

## 使用方法

### 1. 初始化 Wiki

安装完成后，**建议先编辑目标知识库根目录下的 `AGENTS.md`**，完善以下内容：

- **用户偏好**：回答风格、输出格式偏好、语言偏好等
- **自定义配置**：内容侧重点、知识领域范围、Wiki 页面命名规范、分类和标签体系等
- **角色定位**：你希望知识库 agent 扮演的角色（如研究助手、学习伙伴、项目文档维护者等）

这样 wiki-init 生成的内容将更贴合你的实际需求。

完成配置后，在 OpenCode、Claude Code 或 Codex 中运行批量构建：

OpenCode / Claude Code：

```
/wiki-init
```

Codex：

```
$wiki-init
```

（或在 Codex 中通过 `/skills` 选择器选择 `wiki-init` skill）

这将处理所有 raw sources 并构建初始 wiki。

### 2. 增量添加新文件

添加新文件到知识库后，运行：

```
/wiki-ingest
```

工具会自动检测新添加的未处理文件，或你可以指定特定文件：

```
/wiki-ingest articles/new-article.md
```

### 3. 查询 Wiki

直接提问，LLM 会基于 wiki 内容回答：

```
/wiki-query 这篇文章的核心观点是什么？
```

### 4. 健康检查

定期运行 lint 检查 wiki 健康状态：

```
/wiki-lint
```

### 5. 更新已处理的源

如果某个源文件内容有更新：

```
/wiki-update articles/updated-article.md
```

### 6. 清理无效引用

```
/wiki-prune
```

### 7. 自动知识抓取

Agent 会在所有对话中自动感知你提供的新知识——新事实、纠正、观点或决定——并主动提议沉淀到 wiki。如有冲突会请你裁决，无需手动调用。

## 视觉内容读取（可选）

如果你的主 agent 是纯文本模型，可以配置 `vision-reader` subagent 来读取：

- 纯图片文件（`.png`, `.jpg`, `.jpeg`, `.gif`, `.webp`, `.svg`, `.bmp`）
- 办公文档中的视觉元素（PPTX 幻灯片、PDF 图表、DOCX 图片等）
- HTML/Markdown 中的嵌入图片

### 配置

推荐方式（npm CLI）：

```bash
# 跨平台
zhiwei config-vision-reader /path/to/your/knowledge-base
```

备用方式（Shell / PowerShell 脚本）：

```bash
# Mac/Linux
./config_vision_reader.sh /path/to/your/knowledge-base

# Windows (PowerShell)
.\config_vision_reader.ps1 "C:\path\to\your\knowledge-base"
```

配置完成后，使用知识库时 Agent 会在遇到视觉内容时自动调用 `vision-reader` 读取。

混合模式下（Claude Code），安装器会自动生成 Claude Code 版 `.claude/agents/vision-reader.md`。Codex 模式下，安装器会自动生成 Codex 版 `.codex/agents/vision-reader.toml`（不指定 `model`，由 Codex 自动选择；`sandbox_mode = "read-only"`；Codex 仅在被显式要求时 spawn subagent）。如果也希望 OpenCode 使用专门的视觉 subagent，仍可运行上述 `config_vision_reader` 脚本，它会生成 `.opencode/agents/vision-reader.md`。

### 工作原理

| 文件类型 | 处理方式 |
|---------|---------|
| 纯图片 | 委托 `vision-reader` 读取 |
| 办公文档（PPTX/PDF/DOCX） | 两段式：Read 取文本 + vision-reader 取视觉 |
| 网页（HTML） | 两段式：Read 取文本 + vision-reader 取视觉 |
| Markdown | 文本优先，按需读取图片 |

如未配置 `vision-reader`，Agent 跳过视觉处理，仅处理文本内容。

## 配置

### AGENTS.md

编辑 `AGENTS.md` 可以自定义：

- Wiki 页面命名规范
- 分类和标签体系
- 输出格式偏好

### 文件排除规则

知识库根目录的 `.wiki_ignore` 文件定义了不被扫描的文件和目录（类似于 `.gitignore`）。
安装脚本会自动创建默认排除规则：

| 排除项 | 说明 |
|--------|------|
| `.opencode/` | Skills 配置目录 |
| `.claude/` | Claude Code 配置目录（启用 Claude Code 支持时） |
| `.agents/` | 共享 skills 配置目录（启用 Codex 支持时） |
| `.codex/` | Codex 配置目录（启用 Codex 支持时） |
| `.wiki/` | Wiki 内容本身 |
| `.git/` | 版本控制 |
| `AGENTS.md` | 知识库配置文件 |
| `CLAUDE.md` | Claude Code 入口文件（启用 Claude Code 支持时） |
| `output/` | 用户自产文件（ppt、报告等），不会被 ingest |

如果用户自产了 PPTX 等展示类文档，可放在 `output/` 目录下避免被误处理。
如需更多自定义排除项，编辑 `.wiki_ignore` 文件的「用户自定义规则」区域即可，
例如添加 `*.pptx` 或 `drafts/`。

更新安装时，默认规则会刷新，用户自定义规则会被保留。

### 自动备份

安装器会在 `AGENTS.md` 的「自动备份」章节写入当前模式和平台对应的备份脚本路径：

| 模式 | Mac/Linux 自动备份脚本 | Windows 自动备份脚本 |
|------|----------------------|--------------------|
| OpenCode-only | `bash .opencode/skills/wiki-backup/backup.sh --auto` | `powershell -NoProfile -ExecutionPolicy Bypass -File .opencode\skills\wiki-backup\backup.ps1 -Auto` |
| OpenCode + Claude Code | `bash .claude/skills/wiki-backup/backup.sh --auto` | `powershell -NoProfile -ExecutionPolicy Bypass -File .claude\skills\wiki-backup\backup.ps1 -Auto` |
| OpenCode + Codex | `bash .agents/skills/wiki-backup/backup.sh --auto` | `powershell -NoProfile -ExecutionPolicy Bypass -File .agents\skills\wiki-backup\backup.ps1 -Auto` |

备份范围包括 `.wiki/`、`AGENTS.md`、`.wiki_ignore`，Claude 模式下还会在存在时包含 `CLAUDE.md`。Codex 模式无托管入口文件，备份范围不包含 `CLAUDE.md`。不会备份整个 `.opencode/`、`.claude/`、`.agents/` 或 `.codex/`，这些工具配置可通过重新运行安装器恢复，且可能包含用户自定义配置。

## 原理说明

### 文件追踪

`.wiki/.wiki-processed` 文件记录所有已处理的源文件及内容哈希（SHA-256）。
`hash` 是文件的稳定标识，`path` 是可变属性——当用户整理文件（移动/重命名）时，
系统自动通过 hash 匹配新旧位置，无需重新入库。

```json
{
  "version": 2,
  "entries": [
    {
      "path": "articles/foo.md",
      "hash": "abc123...",
      "processed": "2026-05-03T10:00:00Z"
    }
  ]
}
```

### 视觉内容读取

对于需要视觉能力的文件类型（图片、办公文档、网页），知微支持通过 `vision-reader` subagent 处理视觉内容。纯图片文件委托 subagent 读取描述，办公文档和网页采用两段式处理（Read 取文本 + vision-reader 取视觉元素）。

如未配置，Agent 跳过视觉处理，仅处理文本内容。

### 知识累积

每次 ingest 操作可能会：
- 创建新的实体页面
- 更新现有的概念页面
- 添加跨页面引用
- 标注与新信息矛盾的旧信息
- 更新 index.md 和 log.md

## 贡献

欢迎提交 Issue 和 Pull Request。

## 许可证

GNU General Public License v3.0 (GPL-3.0)
