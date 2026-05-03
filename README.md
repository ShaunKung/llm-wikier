# LLM Wikier

一个基于 OpenCode Skills 的个人知识库工具包，用于构建和维护 LLM 驱动的 Wiki 知识库。

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

## 支持的文件格式

**文本格式**：`.md`, `.txt`, `.json`, `.yaml`, `.yml`, `.csv`, `.xml`, `.html`, `.rst`, `.org`, `.tex` 以及各种代码文件

**图片格式**：`.png`, `.jpg`, `.jpeg`, `.gif`, `.webp`, `.svg`, `.bmp`

## 安装

### 前置要求

- [OpenCode](https://opencode.ai) 已安装
- 已有一个知识库文件夹（可包含多层子目录和现有文件）

### Mac / Linux

```bash
# 克隆仓库
git clone https://github.com/your-repo/llm-wikier.git
cd llm-wikier

# 添加执行权限
chmod +x install.sh

# 安装到目标知识库
./install.sh /path/to/your/knowledge-base
```

### Windows (PowerShell)

```powershell
# 克隆仓库
git clone https://github.com/your-repo/llm-wikier.git
cd llm-wikier

# 安装到目标知识库
.\install.ps1 "C:\path\to\your\knowledge-base"
```

## 安装后的目录结构

```
<知识库根目录>/
├── AGENTS.md                    # Schema 配置文件
├── .wiki-processed              # 已处理文件记录
├── wiki/
│   ├── index.md                 # Wiki 内容目录
│   ├── log.md                   # 操作日志
│   └── [其他 wiki 页面]
├── .opencode/skills/            # Skills 目录
│   ├── wiki-init/SKILL.md
│   ├── wiki-ingest/SKILL.md
│   ├── wiki-query/SKILL.md
│   ├── wiki-lint/SKILL.md
│   ├── wiki-update/SKILL.md
│   └── wiki-prune/SKILL.md
└── [原有的 raw sources]         # 保持不变
```

## 使用方法

### 1. 初始化 Wiki

如果你的知识库已有大量文件，首先运行批量构建：

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

## 配置

编辑 `AGENTS.md` 可以自定义：

- Wiki 页面命名规范
- 分类和标签体系
- 输出格式偏好
- 排除规则

## 原理说明

### 文件追踪

`.wiki-processed` 文件记录所有已处理的源文件及其哈希值：

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

### 图片处理

对于包含图片的 markdown 文件：
1. 先读取文本内容进行处理
2. 在需要时单独查看图片获取额外上下文

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
