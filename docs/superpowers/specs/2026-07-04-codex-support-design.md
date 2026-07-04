# Codex CLI 客户端支持 — 设计文档

## 概述

为 LLM Wikier 安装后个人知识库增加 OpenAI Codex CLI 客户端支持，形成三态互斥安装模式：

- **OpenCode-only**（已有，默认）
- **OpenCode + Claude Code**（已有）
- **OpenCode + Codex**（新增）

约束（用户明确要求）：

- Codex 与 Claude 互斥：知识库支持 Codex 时关闭 Claude Code 支持，但 **OpenCode 始终保留**
- 参考官方文档：OpenAI Codex（developers.openai.com/codex）、OpenCode（opencode.ai/docs）、open agent skills 标准

---

## 背景调研（权威来源）

### Codex CLI 关键事实

| 能力 | Codex 行为 | 来源 |
|------|-----------|------|
| 指令文件 | **原生读取 `AGENTS.md`**（无需 `CODEX.md` 入口），按目录链从仓库根到 CWD 合并 | developers.openai.com/codex/guides/agents-md |
| Skills 路径 | 扫描 **`.agents/skills/`**（open agent skills 标准），从 CWD 向上到仓库根；用户级 `~/.agents/skills/` | developers.openai.com/codex/skills |
| Skill 格式 | `SKILL.md` + YAML frontmatter（`name` + `description` 必填）——与 OpenCode/Claude 完全一致 | 同上 |
| Skill 调用 | `/skills` 选择器 或 `$skill-name` 显式触发；亦可按 description 隐式触发 | developers.openai.com/codex/cli/slash-commands |
| 自定义 subagent | **`.codex/agents/*.toml`**（项目级）或 `~/.codex/agents/*.toml`（用户级）；必填 `name`/`description`/`developer_instructions`，可选 `model`/`model_reasoning_effort`/`sandbox_mode`/`mcp_servers`/`skills.config` | developers.openai.com/codex/subagents |
| Subagent 触发 | **仅在被显式要求时 spawn**（"spawn one agent per point" 这类指令）| developers.openai.com/codex/concepts/subagents |
| 项目配置 | `.codex/config.toml`（可选）| developers.openai.com/codex/config-reference |
| Custom prompts | **已废弃**，官方推荐改用 skills | developers.openai.com/codex/custom-prompts |

### OpenCode 关键事实（验证共享可行性）

OpenCode 扫描以下 skills 路径（opencode.ai/docs/skills 权威确认）：

- Project：`.opencode/skills/<name>/SKILL.md`
- Project Claude-compatible：`.claude/skills/<name>/SKILL.md`
- **Project agent-compatible：`.agents/skills/<name>/SKILL.md`** ← 与 Codex 共享点
- Global：`~/.config/opencode/skills/`、`~/.claude/skills/`、`~/.agents/skills/`

> OpenCode 从 CWD 向上遍历到 git worktree，沿途加载 `.opencode/skills/`、`.claude/skills/`、`.agents/skills/` 中任一匹配的 `*/SKILL.md`。因此 `.agents/skills/` 是 OpenCode 与 Codex 的天然共享目录，**无需复制或软链**，与现有 `+Claude` 模式以 `.claude/skills/` 作共享目录的架构完全对称。

### 方案对比与选择

| 方案 | 说明 | 结论 |
|------|------|------|
| **A（采纳）** | `.agents/skills/` 作为 OpenCode+Codex 共享 skills 目录 | OpenCode/Codex 均原生扫描，零复制 |
| B | skills 放 `.codex/skills/` + `[[skills.config]]` 注册 path | Codex **不**扫描 `.codex/skills/`；config 字段语义非"注册新目录"，脆弱，否决 |
| C | 双份复制到 `.opencode/skills/` + `.agents/skills/` | OpenCode 同时发现两处同名 skill，违反"避免重复发现"原则，否决 |

### vision-reader 配置方式（用户已决）

用户选择：**安装器预生成默认** `.codex/agents/vision-reader.toml`（不指定 `model`，让 Codex 自动选择；`sandbox_mode = "read-only"`），`config_vision_reader` 脚本仍只管 OpenCode——与现有 Claude 流程（安装器预生成 `.claude/agents/vision-reader.md` 用 `model: inherit`）对称。

> 注意：Codex 仅在被显式要求时 spawn subagent。因此 SKILL.md / AGENTS.md 的视觉处理指令须明确告诉 Codex 主 agent："遇到视觉内容时，spawn `vision-reader` 自定义 agent 读取"。

---

## 三态客户端模式模型

| 模式 | skills 目录 | 入口文件 | vision-reader 目录 | .wiki_ignore 额外排除 |
|------|------------|---------|--------------------|----------------------|
| OpenCode-only（默认） | `.opencode/skills/` | `AGENTS.md` | `.opencode/agents/`（脚本配置） | `.opencode/` |
| OpenCode + Claude Code | `.claude/skills/` | `AGENTS.md` + 托管 `CLAUDE.md` | `.claude/agents/` + 可选 `.opencode/agents/` | `.opencode/` `.claude/` `CLAUDE.md` |
| **OpenCode + Codex（新）** | **`.agents/skills/`** | **`AGENTS.md`**（Codex 原生读，无托管入口） | **`.codex/agents/` + 可选 `.opencode/agents/`** | `.opencode/` `.agents/` `.codex/` |

> Codex 模式无托管 `CODEX.md`：Codex 直接读 `AGENTS.md`，比 Claude 模式更简单。

---

## 安装器改动（install.sh / install.ps1，两版行为一致）

### 变量替换

```
ENABLE_CLAUDE_CODE=false       →  CLIENT_MODE="opencode"
$script:EnableClaudeCode       →  $script:ClientMode
```

取值：`"opencode"` / `"claude"` / `"codex"`

### 新增/修改函数（sh / ps1 镜像）

| 函数 | 说明 |
|------|------|
| `Test-CodexSupport` / `has_codex_support` | 检测 `.agents/skills/wiki-ingest/SKILL.md` 或带托管标记的 `.codex/agents/vision-reader.toml` |
| `Select-ClientSupport` / `select_client_support` | 从 bool 提示改为三选一交互；更新模式检测当前模式作默认 |
| `Get-ActiveSkillsDir` / `get_active_skills_dir` | opencode→`.opencode/skills`，claude→`.claude/skills`，codex→`.agents/skills` |
| `Get-InactiveSkillsDirs` / `get_inactive_skills_dirs` | **改为复数**，返回其余两个候选目录数组，安装后从中移除 LLM-Wikier 管理的 `wiki-*` |
| `Get-BackupAutoCommand` / `get_backup_auto_command` | 新增 codex 分支 → `.agents/skills/wiki-backup/backup.{sh,ps1}` |
| `Write-CodexVisionReader` / `write_codex_vision_reader` | 预生成 `.codex/agents/vision-reader.toml`（见下节） |
| `Remove-CodexVisionReader` / `remove_codex_vision_reader` | 移除托管文件，含空目录清理 |
| `Sync-ClientSupportFiles`（由 `Sync-ClaudeSupportFiles` 改名） | 按模式同步：Claude 写 CLAUDE.md + Claude agent；Codex 写 Codex agent；opencode 两者皆清 |

### 检测函数扩展

- `Test-UpdateInstall`：候选 skill 根增加 `.agents/skills`
- `Test-ExistingInstallation`：增加 Codex 托管标记判定，避免新装误覆盖

### `.wiki_ignore` 默认规则

```
OpenCode-only:  .opencode/  .wiki/  .wiki/cache/  .git/  AGENTS.md  output/
Claude:         + .claude/  CLAUDE.md
Codex:          + .agents/  .codex/
```

### 模式切换矩阵（更新安装）

| 从 → 到 | skills 迁移 | Claude 托管 | Codex 托管 |
|---------|------------|------------|-----------|
| opencode↔claude | 已有逻辑 | 写/清 | — |
| opencode↔codex | `.opencode/skills` ↔ `.agents/skills` | — | 写/清 `.codex/agents/vision-reader.toml` |
| claude↔codex | `.claude/skills` ↔ `.agents/skills` | 清 CLAUDE.md 托管块 + `.claude/agents/vision-reader.md` | 写/清 Codex agent |

仅移除 LLM-Wikier 托管文件，不递归删用户自定义 `.claude/`、`.codex/`、`.opencode/`、`.agents/` 内容。

### 完成提示

```
OpenCode:   "opencode"
Claude:     "opencode" 或 "claude"
Codex:      "opencode" 或 "codex"
```

---

## Codex vision-reader（安装器预生成）

文件：`.codex/agents/vision-reader.toml`，托管标记 `# LLM-WIKIER:CODEX-AGENT-MANAGED`：

```toml
# LLM-WIKIER:CODEX-AGENT-MANAGED
name = "vision-reader"
description = "读取图片、图表、截图、幻灯片、PDF 和文档排版等视觉元素，转化为文字描述"
sandbox_mode = "read-only"

developer_instructions = """
你是一个视觉内容读取器。你的职责是读取文件中的视觉元素（图片、图表、截图、幻灯片、页面排版等），并将视觉内容转化为文字描述。

## 核心职责
- 只描述视觉元素（图片、图表、照片、插图、截图、幻灯片视觉内容、排版布局等）
- 不要重复已经由主 agent 处理的纯文本内容
- **兜底规则**：如果发现文档中文本提取明显不完整（如幻灯片缺失文字、表格数据丢失、图表中的数据标签等），请一并补充关键文本信息

## 输出格式
对每个视觉元素：

### [图片/图表/截图 序号]
**类型**: [图表/照片/截图/插图/排版]
**描述**: [视觉内容的文字描述]
**关键信息**: [图表数据、照片中的人物/场景、截图中的UI元素、幻灯片主题等]

主 agent 会通过文件路径告知你需要读取的文件，请直接读取并返回描述。
"""
```

- 不指定 `model` → Codex 自动选择（对称于 Claude 的 `model: inherit`）
- `sandbox_mode = "read-only"` → 可读文件、不可写
- `Write-CodexVisionReader` 含"用户自定义保留"逻辑：若已有文件且不含托管标记，跳过并提示（镜像 Claude 版行为）
- `Remove-CodexVisionReader` 仅删托管文件，空目录清理到 `.codex/agents/`、`.codex/`
- `config_vision_reader.sh/ps1` 逻辑不变（仅 OpenCode）；其完成提示与 AGENTS.md 说明 Codex 版由安装器托管

---

## SKILL.md（8 个 skill）

- frontmatter `compatibility: opencode, claude-code` → `compatibility: opencode, claude-code, codex`
- 视觉处理调用说明：现有"OpenCode 用 Task 工具；Claude Code 用 Agent/subagent 调用" → 增加"Codex 通过 spawn `vision-reader` 自定义 agent 调用"
- `wiki-capture` 的基础设施排除清单（`.opencode/skills/`、`.claude/skills/`） → 增加 `.agents/skills/`
- `wiki-backup`：补充 Codex 模式备份路径（`.agents/skills/wiki-backup/backup.{sh,ps1}`）与备份范围说明（Codex 无托管入口文件，备份范围仍为 `.wiki/`、`AGENTS.md`、`.wiki_ignore`）

---

## AGENTS.md 模板（templates/AGENTS.md.tmpl）

- 「视觉内容处理策略 / vision-reader 配置」：增加 Codex 路径 `.codex/agents/vision-reader.toml`，并说明 Codex 由安装器预生成、不指定 model
- 「默认排除项」：增加 `.agents/`（Codex 模式）、`.codex/`（Codex 模式）
- 「主动知识抓取 / 内容域边界」：排除清单增加 `.agents/skills/`
- `__WIKI_BACKUP_AUTO_COMMAND__` 占位符逻辑不变（由安装器按模式替换为 `.agents/...` 路径）
- **三处同步**（按仓库 AGENTS.md 约定）：`templates/AGENTS.md.tmpl`、`install.sh` 内置 fallback、`install.ps1` 内置 fallback

---

## lib/common.{sh,ps1} 与杂项

- `Test-ExcludeDir`（deprecated）排除目录表增加 `.agents`、`.codex`
- `Set-HiddenAttributes`（Windows）增加 `.agents`、`.codex`
- `Get-ExistingBackupRoot` 候选增加 `.agents/skills/wiki-backup/backup.{ps1,sh}`

---

## 安装后目录结构（Codex 模式）

```
<KB>/
├── AGENTS.md                 # OpenCode + Codex 同时原生读取
├── .wiki_ignore
├── output/
├── .wiki/ ...
├── .agents/skills/           # 唯一 LLM Wikier skills 目录
│   └── wiki-*/SKILL.md
├── .codex/agents/
│   └── vision-reader.toml    # 安装器托管
└── .opencode/agents/         # 可选（config_vision_reader 生成）
    └── vision-reader.md
```

---

## 备份命令路径

| 模式 | Mac/Linux | Windows |
|------|-----------|---------|
| OpenCode-only | `bash .opencode/skills/wiki-backup/backup.sh --auto` | `powershell -NoProfile -ExecutionPolicy Bypass -File .opencode\skills\wiki-backup\backup.ps1 -Auto` |
| OpenCode + Claude Code | `bash .claude/skills/wiki-backup/backup.sh --auto` | `powershell -NoProfile -ExecutionPolicy Bypass -File .claude\skills\wiki-backup\backup.ps1 -Auto` |
| **OpenCode + Codex** | **`bash .agents/skills/wiki-backup/backup.sh --auto`** | **`powershell -NoProfile -ExecutionPolicy Bypass -File .agents\skills\wiki-backup\backup.ps1 -Auto`** |

备份范围不变：`.wiki/`、`AGENTS.md`、`.wiki_ignore`（Codex 模式无托管入口文件，不加 `CLAUDE.md`）。

---

## 待改文件清单

| 文件 | 改动 |
|------|------|
| `install.sh` | 大改：变量三态、检测/sync/备份函数、vision-reader TOML 生成、模式切换矩阵 |
| `install.ps1` | 镜像 install.sh |
| `lib/common.sh` | `Test-ExcludeDir` 增加 `.agents`/`.codex` |
| `lib/common.ps1` | `Test-ExcludeDir` 增加 `.agents`/`.codex` |
| `templates/AGENTS.md.tmpl` | 视觉/排除/capture 章节补 Codex |
| `install.sh` 内置 fallback AGENTS.md | 同步（三处同步约定） |
| `install.ps1` 内置 fallback AGENTS.md | 同步（三处同步约定） |
| `README.md` | 模式表、目录结构图、切换说明、视觉/备份/排除表、Codex 调用方式 |
| `AGENTS.md`（仓库根） | skill 格式说明中 compatibility 示例补 codex；常见陷阱补 Codex |
| `skills/wiki-*/SKILL.md`（8 个） | frontmatter + 视觉/capture/backup 文案 |
| `config_vision_reader.{sh,ps1}` | 仅完成提示文案（说明 Codex 版由安装器托管） |

---

## 三态安装交互

首次安装：

```
[询问] 是否需要支持除 OpenCode 之外的其它客户端？
  1) 仅 OpenCode（默认）
  2) OpenCode + Claude Code
  3) OpenCode + Codex
请输入编号 [1/2/3]:
```

更新安装时检测当前模式：

```
检测到当前知识库已支持 [Claude Code / Codex / 仅 OpenCode]。
是否切换客户端模式？
  1) 保持不变（默认）
  2) 切换为 OpenCode + Codex
  3) 切换为 OpenCode + Claude Code
  4) 仅 OpenCode（移除其他支持）
```

`-Force` 模式：保持当前检测到的模式。

---

## 兼容性

- 已有用户从旧版升级：`Test-UpdateInstall` 增加 `.agents/skills` 候选，检测到即进入更新模式
- `CLIENT_MODE` 变量不持久化到 KB，每次更新安装重新检测当前模式
- 旧 `ENABLE_CLAUDE_CODE` 仅存于安装器内存，无需迁移
- `config_vision_reader` 的 `is_valid_kb_dir` 检测 `AGENTS.md` + `.wiki/`，Codex 模式 KB 同样满足，无需改
- 既有 `.wiki-processed` v1→v2 迁移、旧 `wiki/` → `.wiki/` 结构迁移逻辑与客户端模式无关，不动

---

## 验证手段（无构建/测试/类型检查，纯脚本+文档仓库）

按仓库 AGENTS.md 约定：

- `bash -n install.sh`（shell 语法）
- `bash -n config_vision_reader.sh`（shell 语法）
- PowerShell 语法人工审查
- SKILL.md frontmatter 格式校验（`name`/`description` 必填、`name` 匹配目录名、小写+数字+单连字符规则）
- 三模式安装/更新/切换的手动端到端验证（在临时 KB 目录）
