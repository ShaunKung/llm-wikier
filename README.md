# LLM Wikier

一个基于 OpenCode Skills 的个人知识库工具包，用于构建和维护 LLM 驱动的 Wiki 知识库。

该项目受 Andrej Karpathy 的 [llm-wiki](https://gist.github.com/karpathy/442a6bf555914893e9891c11519de94f) 启发而开发。

## 核心理念

传统 RAG 系统在每次查询时都从原始文档重新检索和推理，知识无法累积。LLM Wikier 采用不同的方式：

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

## 安装

### 前置要求

- [OpenCode](https://opencode.ai) 已安装
- 已有一个知识库文件夹（可包含多层子目录和现有文件）

### Mac / Linux

```bash
# 克隆仓库
git clone https://github.com/ShaunKung/llm-wikier.git
cd llm-wikier

# 添加执行权限
chmod +x install.sh

# 安装到目标知识库
./install.sh /path/to/your/knowledge-base
```

### Windows (PowerShell)

```powershell
# 克隆仓库
git clone https://github.com/ShaunKung/llm-wikier.git
cd llm-wikier

# 安装到目标知识库
.\install.ps1 "C:\path\to\your\knowledge-base"
```

## 安装后的目录结构

```
<知识库根目录>/
├── AGENTS.md                    # Schema 配置文件
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
│   │   └── wiki-capture/SKILL.md
│   └── agents/                  # Subagent 配置（可选）
│       └── vision-reader.md     # 视觉读取 subagent
└── [原有的 raw sources]         # 保持不变
```

## 使用方法

### 1. 初始化 Wiki

安装完成后，**建议先编辑目标知识库根目录下的 `AGENTS.md`**，完善以下内容：

- **用户偏好**：回答风格、输出格式偏好、语言偏好等
- **自定义配置**：内容侧重点、知识领域范围、Wiki 页面命名规范、分类和标签体系等
- **角色定位**：你希望知识库 agent 扮演的角色（如研究助手、学习伙伴、项目文档维护者等）

这样 wiki-init 生成的内容将更贴合你的实际需求。

完成配置后，运行批量构建：

```
/wiki-init
```

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

```bash
# Mac/Linux
./config_vision_reader.sh /path/to/your/knowledge-base

# Windows (PowerShell)
.\config_vision_reader.ps1 "C:\path\to\your\knowledge-base"
```

配置完成后，使用知识库时 Agent 会在遇到视觉内容时自动调用 `vision-reader` 读取。

### 工作原理

| 文件类型 | 处理方式 |
|---------|---------|
| 纯图片 | 委托 `vision-reader` 读取 |
| 办公文档（PPTX/PDF/DOCX） | 两段式：Read 取文本 + vision-reader 取视觉 |
| 网页（HTML） | 两段式：Read 取文本 + vision-reader 取视觉 |
| Markdown | 文本优先，按需读取图片 |

如未配置 `vision-reader`，Agent 跳过视觉处理，仅处理文本内容。

## 配置

编辑 `AGENTS.md` 可以自定义：

- Wiki 页面命名规范
- 分类和标签体系
- 输出格式偏好
- 排除规则

## 原理说明

### 文件追踪

`.wiki/.wiki-processed` 文件记录所有已处理的源文件及其哈希值：

```json
{
  "version": 1,
  "entries": [
    {
      "path": "articles/foo.md",
      "hash": "sha256:abc123...",
      "processed": "2026-05-03T10:00:00Z"
    }
  ]
}
```

### 视觉内容读取

对于需要视觉能力的文件类型（图片、办公文档、网页），LLM Wikier 支持通过 `vision-reader` subagent 处理视觉内容。纯图片文件委托 subagent 读取描述，办公文档和网页采用两段式处理（Read 取文本 + vision-reader 取视觉元素）。

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
