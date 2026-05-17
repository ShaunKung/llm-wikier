# AGENTS.md — LLM Wikier 仓库

## 项目定位

这是一个 OpenCode Skills 工具包仓库，提供安装脚本将技能安装到任意**已有**的知识库目录。
不是知识库本身——本仓库的 `templates/AGENTS.md.tmpl` 是知识库的 schema 模板。

## 文件约定

| 约定 | 说明 |
|------|------|
| **编码** | 所有文本文件 UTF-8，已通过 `.gitattributes` 强制 |
| **换行符** | `.sh` / `.md` / `.py` / `.js` → LF；`.bat` / `.cmd` → CRLF |
| **语言** | 所有文档、注释、skill 描述使用**中文** |
| **许可证** | 仓库整体 GPL-3.0，但 `skills/*/SKILL.md` frontmatter 中 license 字段为 MIT（skills 会被安装到用户的知识库目录，不应强制 GPL） |

## 核心架构

```
skills/                     ← 7 个 OpenCode skill 定义（安装到 .opencode/skills/）
  wiki-init/SKILL.md        ← 批量初始化 wiki
  wiki-ingest/SKILL.md      ← 增量入库（自动检测新文件）
  wiki-query/SKILL.md       ← 基于 wiki 问答
  wiki-lint/SKILL.md        ← 健康检查
  wiki-update/SKILL.md      ← 重新处理已处理源文件
  wiki-prune/SKILL.md       ← 清理无效内容
  wiki-capture/SKILL.md     ← 对话知识抓取（自动感知 + 冲突裁决）
templates/AGENTS.md.tmpl    ← 安装到目标知识库的 schema 模板
lib/common.sh               ← Mac/Linux 安装脚本的共享函数
lib/common.ps1              ← Windows 安装脚本的共享函数
install.sh                  ← Mac/Linux 安装器
install.ps1                 ← Windows PowerShell 安装器
config_vision_reader.sh     ← Mac/Linux vision-reader subagent 配置器
config_vision_reader.ps1    ← Windows vision-reader subagent 配置器
```

## SKILL.md 格式

每个 SKILL.md 必须以 YAML frontmatter 开头：

```yaml
---
name: wiki-xxx
description: 中文功能描述（1-1024 字符）
license: MIT
compatibility: opencode
---
```

`name` 必须匹配目录名（如 `skills/wiki-init/SKILL.md` 中 name 必须是 `wiki-init`）。
规则：小写字母+数字+单连字符，不以 `-` 开头结尾，不包含 `--`。

## 安装脚本职责（修改 install.sh/ps1 时注意）

两版脚本行为必须一致：
1. 验证目标目录存在
2. 创建 `.wiki/`、`.wiki/index.md`、`.wiki/log.md`
3. 创建 `.wiki/.wiki-processed`（JSON：`{"version":1,"entries":[]}`）
4. 复制 `skills/*` → 目标目录 `.opencode/skills/`
5. 从 `templates/AGENTS.md.tmpl` 生成目标 `AGENTS.md`
6. 输出完成提示

**安装后的目标目录不包含本仓库的 `lib/`、`README.md`、`templates/`、`install.*`、`config_vision_reader.*`、`skills/` 源文件。**

## vision-reader subagent 配置脚本（config_vision_reader.sh/ps1）

独立于 install.sh/ps1 的配置脚本，用于在目标 KB 的 `.opencode/agents/` 下生成 `vision-reader.md`。

两版脚本行为必须一致：
1. 验证目标 KB 有效（`is_valid_kb_dir`）
2. 检测已有配置 → 存在则进入更新模式
3. 通过 `opencode models` 交互式选择 provider 和 model
4. 如 opencode 不可用或无法解析，fallback 到手动输入模式
5. 强制校验 provider + model 均非空，否则不保存
6. 生成 `.opencode/agents/vision-reader.md`（YAML frontmatter + 视觉读取 system prompt）
7. 输出完成提示（含 .gitignore 建议）

## 安装脚本内部生成的 AGENTS.md 默认内容

install.sh/ps1 内置一份硬编码的默认 AGENTS.md（当 `templates/AGENTS.md.tmpl` 不可用时使用）。
修改支持的文件格式列表时，需同步更新三处：
- `README.md`
- `install.sh` 默认 AGENTS.md 内容
- `install.ps1` 默认 AGENTS.md 内容

`lib/common.sh` 中的 `get_text_extensions` / `get_image_extensions` / `get_office_extensions` 及对应的 `lib/common.ps1` 函数也需同步更新。

## 支持的文件格式列表（权威源：lib/）

- 文本：`md txt json yaml yml csv xml html rst org tex` + 代码文件
- 办公：`pdf docx doc pptx ppt xlsx xls odt odp ods`
- 图片：`png jpg jpeg gif webp svg bmp`

## install.sh 执行权限

`install.sh` 已通过 `git update-index --chmod=+x` 设置执行位。
克隆到 Unix 系统后自动可用 `./install.sh` 运行。
不要移除该执行位。

## 无构建/测试/类型检查

本仓库是纯文档+脚本仓库，没有代码需要编译、测试或类型检查。
无需运行 lint、typecheck、test 命令。
修改后只需验证：
- `bash -n install.sh`（检查 shell 语法）
- `bash -n config_vision_reader.sh`（检查 shell 语法）
- PowerShell 语法可通过人工审查
- SKILL.md frontmatter 格式正确（name/description 必填）

## 常见陷阱

- **不要混淆 AGENTS.md**：仓库根目录的 AGENTS.md 是关于本工具包仓库的，`templates/AGENTS.md.tmpl` 是安装到目标知识库的模板
- **不要混淆 7 个 skill**：wiki-ingest 是增量检测新文件，wiki-update 是重新处理已有文件，wiki-init 是一次性批量处理，wiki-capture 是从对话中抓取知识（不涉及文件）
- **不要混淆 skill 和 subagent**：`skills/` 下的 SKILL.md 是给主 agent 加载的工作流指令；`vision-reader` 是 `.opencode/agents/` 下的 subagent，由主 agent 通过 Task 工具调用，用于读取视觉内容
- **`.wiki/.wiki-processed` 不是本仓库的文件**：它只存在于安装后的目标知识库中
- **SKILL.md 中的 license: MIT 与仓库 License 不同是故意的**：skills 会被复制到用户的知识库目录
- **vision-reader subagent 不是强制的**：如用户未配置，Agent 跳过视觉处理，仅处理文本内容
