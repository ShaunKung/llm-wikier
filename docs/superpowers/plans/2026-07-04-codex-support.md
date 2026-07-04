# Codex CLI 客户端支持 实施计划

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 为 LLM Wikier 安装后个人知识库新增 OpenAI Codex CLI 作为第三客户端选项，形成 OpenCode-only / OpenCode+Claude / OpenCode+Codex 三态互斥安装模式。

**Architecture:** 安装器变量从布尔 `ENABLE_CLAUDE_CODE` 改为 tri-state `CLIENT_MODE ∈ {opencode, claude, codex}`。Codex 模式以 `.agents/skills/` 作为 OpenCode+Codex 共享 skills 目录（两者均原生扫描此路径），AGENTS.md 被 OpenCode/Codex 同时原生读取无需托管入口文件，vision-reader 预生成 `.codex/agents/vision-reader.toml`（不指定 model 由 Codex 自动选择，`sandbox_mode=read-only`）。

**Tech Stack:** Bash（install.sh、lib/common.sh、config_vision_reader.sh、backup.sh）、PowerShell（install.ps1、lib/common.ps1、config_vision_reader.ps1、backup.ps1）、Markdown（templates、skills、README、AGENTS.md）。

## Global Constraints

- 所有文本文件 UTF-8（已由 `.gitattributes` 强制）
- 换行符：`.sh`/`.md`/`.py`/`.js` → LF；`.bat`/`.cmd` → CRLF；PowerShell `.ps1` 保持仓库默认
- 所有文档、注释、skill 描述使用**中文**
- Git 提交信息英文，遵循 Conventional Commits（`type(scope): description`）
- `SKILL.md` frontmatter 中 `license: MIT`（与仓库 GPL-3.0 不同是故意的）
- Codex 与 Claude 互斥：知识库支持 Codex 时关闭 Claude Code 支持，但 **OpenCode 始终保留**
- `install.sh` 已通过 `git update-index --chmod=+x` 设置执行位，不要移除
- 三处同步约定：修改 AGENTS.md 模板内容时需同步 `templates/AGENTS.md.tmpl`、`install.sh` 内置 fallback、`install.ps1` 内置 fallback
- 本仓库无构建/测试/类型检查；验证手段为 `bash -n`、PowerShell 人工审查、SKILL.md frontmatter 校验、三模式端到端手动测试
- Codex agent 托管标记为 `# LLM-WIKIER:CODEX-AGENT-MANAGED`（TOML 注释行，合法）
- Codex 模式 skills 目录 `.agents/skills/` 与 OpenCode/Codex 双方原生扫描路径一致，**不复制双份、不软链**
- **不提交** `.opencode/`、`openspec/`、`.tmp*`（已未跟踪或已忽略）

---

## File Structure

| 文件 | 责任 | 改动类型 |
|------|------|---------| 
| `lib/common.sh` | 共享 shell 函数；`should_exclude_dir` 排除目录表 | 小补丁 |
| `lib/common.ps1` | 共享 PowerShell 函数；`Test-ExcludeDir` 排除目录表 | 小补丁 |
| `skills/*/SKILL.md`（8 个） | skill 定义；frontmatter `compatibility` + 视觉/capture/backup 文案 | 小补丁 |
| `templates/AGENTS.md.tmpl` | 安装到 KB 的 schema 模板 | 已有章节补 Codex |
| `install.sh` | Mac/Linux 安装器主逻辑 | 大改 |
| `install.ps1` | Windows 安装器主逻辑（镜像 install.sh） | 大改 |
| `skills/wiki-backup/backup.sh` | 备份脚本；错误提示中的有效路径列表 | 小补丁 |
| `skills/wiki-backup/backup.ps1` | 备份脚本（PS 镜像） | 小补丁 |
| `config_vision_reader.sh` | OpenCode vision-reader 配置脚本；完成提示文案 | 小补丁 |
| `config_vision_reader.ps1` | PS 镜像 | 小补丁 |
| `README.md` | 项目文档 | 已有章节补 Codex |
| `AGENTS.md`（仓库根） | 本工具包仓库说明 | 已有章节补 Codex |

---

### Task 1: lib/common.{sh,ps1} — 排除目录表补 `.agents`/`.codex`

**Files:**
- Modify: `lib/common.sh:149-161`（`should_exclude_dir` 函数）
- Modify: `lib/common.ps1:126-135`（`Test-ExcludeDir` 函数）

**Interfaces:**
- Produces: `should_exclude_dir`/`Test-ExcludeDir` 返回 true 对 `.agents`/`.codex` 目录（deprecated 函数；`.wiki_ignore` 仍是主机制）

- [ ] **Step 1: 修改 `lib/common.sh` 的 `should_exclude_dir`**

将 `case` 模式列表加入 `.agents`、`.codex`：

oldString:
```
            wiki|.wiki|.opencode|.claude|.git|node_modules|.venv|__pycache__|.idea|.vscode)
```

newString:
```
            wiki|.wiki|.opencode|.claude|.agents|.codex|.git|node_modules|.venv|__pycache__|.idea|.vscode)
```

- [ ] **Step 2: 修改 `lib/common.ps1` 的 `Test-ExcludeDir`**

oldString:
```
    $ExcludeDirs = @("wiki", ".wiki", ".opencode", ".claude", ".git", "node_modules", ".venv", "__pycache__", ".idea", ".vscode")
```

newString:
```
    $ExcludeDirs = @("wiki", ".wiki", ".opencode", ".claude", ".agents", ".codex", ".git", "node_modules", ".venv", "__pycache__", ".idea", ".vscode")
```

- [ ] **Step 3: 验证**

Run: `bash -n lib/common.sh`
Expected: 无输出（语法 OK）

人工审查 PowerShell：确认 `Test-ExcludeDir` 函数语法正确。

- [ ] **Step 4: Commit**

```bash
git add lib/common.sh lib/common.ps1
git commit -m "feat(lib): add .agents and .codex to exclude dir lists"
```

---

### Task 2: SKILL.md frontmatter（8 个文件）— `compatibility` 加 `codex`

**Files:**
- Modify: 8 个 `skills/wiki-*/SKILL.md`（均第 5 行 frontmatter `compatibility`）

**Interfaces:**
- Produces: 所有 8 个 SKILL.md 的 `compatibility: opencode, claude-code, codex`

- [ ] **Step 1: 对每个 SKILL.md 将 `compatibility: opencode, claude-code` 改为 `compatibility: opencode, claude-code, codex`**

对 8 个文件逐一执行相同的 oldString→newString 编辑（每个文件中此行唯一，可安全替换）：

oldString: `compatibility: opencode, claude-code`
newString: `compatibility: opencode, claude-code, codex`

- [ ] **Step 2: 验证 frontmatter**

Run: `grep -n "^compatibility:" skills/*/SKILL.md`
Expected: 8 行，每行均为 `compatibility: opencode, claude-code, codex`

- [ ] **Step 3: Commit**

```bash
git add skills/*/SKILL.md
git commit -m "feat(skills): add codex to compatibility frontmatter"
```

---

### Task 3: SKILL.md 内容补丁（视觉/capture/backup 文案）

**Files:**
- Modify: `skills/wiki-init/SKILL.md`、`skills/wiki-ingest/SKILL.md`、`skills/wiki-update/SKILL.md`（视觉调用说明 + vision-reader 配置路径）
- Modify: `skills/wiki-capture/SKILL.md`（基础设施排除清单）
- Modify: `skills/wiki-backup/SKILL.md`（Codex 模式备份路径 + 备份范围说明）

**Interfaces:**
- Produces: 所有 skill 视觉/capture/backup 文案覆盖 Codex 模式

- [ ] **Step 1: wiki-init/SKILL.md — vision-reader 配置路径（第 55 行）**

oldString:
```
如果当前客户端未配置 `vision-reader` subagent，则跳过视觉读取，仅处理文本内容。OpenCode 配置路径为 `.opencode/agents/vision-reader.md`，Claude Code 配置路径为 `.claude/agents/vision-reader.md`。
```

newString:
```
如果当前客户端未配置 `vision-reader` subagent，则跳过视觉读取，仅处理文本内容。OpenCode 配置路径为 `.opencode/agents/vision-reader.md`，Claude Code 配置路径为 `.claude/agents/vision-reader.md`，Codex 配置路径为 `.codex/agents/vision-reader.toml`。
```

- [ ] **Step 2: wiki-init/SKILL.md — 视觉调用说明（第 60 行）**

oldString:
```
2. 再调用 `vision-reader` subagent 读取同一文件，获取视觉元素描述（OpenCode 通常使用 Task 工具；Claude Code 使用 Agent/subagent 调用）
```

newString:
```
2. 再调用 `vision-reader` subagent 读取同一文件，获取视觉元素描述（OpenCode 通常使用 Task 工具；Claude Code 使用 Agent/subagent 调用；Codex 通过 spawn `vision-reader` 自定义 agent 调用）
```

- [ ] **Step 3: wiki-ingest/SKILL.md — 与 Step 1/2 相同的两处补丁**

wiki-ingest 第 310 行段落与 wiki-init Step 1 的 oldString 相同，应用相同替换得到相同 newString。
wiki-ingest 第 315 行段落与 wiki-init Step 2 的 oldString 相同，应用相同替换。

- [ ] **Step 4: wiki-update/SKILL.md — vision-reader 配置路径（第 68 行）**

oldString 与 Step 1 相同，newString 与 Step 1 相同。

- [ ] **Step 5: wiki-capture/SKILL.md — Layer 0 表格行（第 18 行）**

oldString:
```
| Layer 0 | 来自 `.opencode/skills/` 或 `.claude/skills/` 的 SKILL.md 定义、脚本等基础设施内容 | wiki-ingest 的功能说明 | ❌ |
```

newString:
```
| Layer 0 | 来自 `.opencode/skills/`、`.claude/skills/` 或 `.agents/skills/` 的 SKILL.md 定义、脚本等基础设施内容 | wiki-ingest 的功能说明 | ❌ |
```

- [ ] **Step 6: wiki-capture/SKILL.md — 自排除原则（第 39 行）**

oldString:
```
- 对话内容来自 `.opencode/skills/` 或 `.claude/skills/` 下的 SKILL.md 定义（包括本 skill 自身——自排除原则）
```

newString:
```
- 对话内容来自 `.opencode/skills/`、`.claude/skills/` 或 `.agents/skills/` 下的 SKILL.md 定义（包括本 skill 自身——自排除原则）
```

- [ ] **Step 7: wiki-backup/SKILL.md — 备份范围说明（第 10 行）**

oldString:
```
`wiki-backup` 提供知识库数据的备份和恢复能力。备份范围包括 `.wiki/`（排除 `.wiki/cache/` 缓存目录及其中的 `.meta.json` 元数据文件）、`AGENTS.md`、`CLAUDE.md`（如存在）、`.wiki_ignore`。
```

newString:
```
`wiki-backup` 提供知识库数据的备份和恢复能力。备份范围包括 `.wiki/`（排除 `.wiki/cache/` 缓存目录及其中的 `.meta.json` 元数据文件）、`AGENTS.md`、`CLAUDE.md`（仅 Claude 模式，如存在）、`.wiki_ignore`。Codex 模式无托管入口文件，备份范围不包含 `CLAUDE.md`。
```

- [ ] **Step 8: wiki-backup/SKILL.md — 备份脚本位置（第 12-15 行）**

oldString:
```
备份由独立的 `backup.sh`（Linux/Mac）或 `backup.ps1`（Windows）脚本执行，位于当前安装模式的 skills 目录下：

- OpenCode-only 模式：`.opencode/skills/wiki-backup/`
- OpenCode + Claude Code 模式：`.claude/skills/wiki-backup/`
```

newString:
```
备份由独立的 `backup.sh`（Linux/Mac）或 `backup.ps1`（Windows）脚本执行，位于当前安装模式的 skills 目录下：

- OpenCode-only 模式：`.opencode/skills/wiki-backup/`
- OpenCode + Claude Code 模式：`.claude/skills/wiki-backup/`
- OpenCode + Codex 模式：`.agents/skills/wiki-backup/`
```

- [ ] **Step 9: wiki-backup/SKILL.md — 手动备份示例（第 29-33 行后追加 Codex 示例）**

oldString:
```
OpenCode + Claude Code 模式：

```bash
bash .claude/skills/wiki-backup/backup.sh
```

或强制备份（即使当天已备份过）：
```

newString:
```
OpenCode + Claude Code 模式：

```bash
bash .claude/skills/wiki-backup/backup.sh
```

OpenCode + Codex 模式：

```bash
bash .agents/skills/wiki-backup/backup.sh
```

或强制备份（即使当天已备份过）：
```

- [ ] **Step 10: wiki-backup/SKILL.md — 恢复验证清单（第 97 行）**

oldString:
```
5. 验证 `.wiki/`、`AGENTS.md`、`CLAUDE.md`（如备份中存在）、`.wiki_ignore` 已正确恢复
```

newString:
```
5. 验证 `.wiki/`、`AGENTS.md`、`CLAUDE.md`（仅 Claude 模式，如备份中存在）、`.wiki_ignore` 已正确恢复
```

- [ ] **Step 11: wiki-backup/SKILL.md — 恢复覆盖范围（第 102 行）**

oldString:
```
- 恢复仅覆盖 `.wiki/`、`AGENTS.md`、`CLAUDE.md`、`.wiki_ignore`，不影响知识库中其他文件
```

newString:
```
- 恢复仅覆盖 `.wiki/`、`AGENTS.md`、`CLAUDE.md`（如备份中存在）、`.wiki_ignore`，不影响知识库中其他文件
```

- [ ] **Step 12: 验证**

Run: `grep -rn "claude-code, codex\|\.agents/skills\|\.codex/agents/vision-reader" skills/*/SKILL.md`
Expected: 命中 wiki-init/ingest/update/capture/backup 中相应行。

SKILL.md frontmatter 人工审查：8 个文件 frontmatter `compatibility` 仍为 `opencode, claude-code, codex`（由 Task 2 完成）。

- [ ] **Step 13: Commit**

```bash
git add skills/*/SKILL.md
git commit -m "docs(skills): add codex mode to vision/capture/backup references"
```

---

### Task 4: templates/AGENTS.md.tmpl — 补 Codex 视觉/排除/capture

**Files:**
- Modify: `templates/AGENTS.md.tmpl:83-87`（vision-reader 配置说明）
- Modify: `templates/AGENTS.md.tmpl:94-102`（默认排除项）
- Modify: `templates/AGENTS.md.tmpl:127` 与 `:135-138`（主动知识抓取 - 基础设施排除清单）

**Interfaces:**
- Produces: 模板的视觉/排除/capture 章节覆盖 Codex 模式（由 install.sh/ps1 渲染时按 `CLIENT_MODE` 动态生成 `.wiki_ignore`；模板的「默认排除项」段落为静态说明文本，列举所有可能项）

- [ ] **Step 1: vision-reader 配置说明（第 83-87 行）**

oldString:
```
### vision-reader 配置

如当前客户端未配置 `vision-reader`，Agent 应跳过视觉处理，仅处理文本内容。OpenCode 配置路径为 `.opencode/agents/vision-reader.md`，Claude Code 配置路径为 `.claude/agents/vision-reader.md`。

配置方式：使用 LLM Wikier 提供的 `config_vision_reader` 脚本配置 OpenCode subagent；启用 Claude Code 支持时安装器会生成 Claude Code 版 `vision-reader`。
```

newString:
```
### vision-reader 配置

如当前客户端未配置 `vision-reader`，Agent 应跳过视觉处理，仅处理文本内容。各客户端配置路径：

- OpenCode：`.opencode/agents/vision-reader.md`
- Claude Code：`.claude/agents/vision-reader.md`
- Codex：`.codex/agents/vision-reader.toml`

配置方式：使用 LLM Wikier 提供的 `config_vision_reader` 脚本配置 OpenCode subagent；启用 Claude Code 支持时安装器会生成 Claude Code 版 `vision-reader`（`model: inherit`）；启用 Codex 支持时安装器会生成 Codex 版 `vision-reader`（`.codex/agents/vision-reader.toml`，不指定 `model` 由 Codex 自动选择，`sandbox_mode = "read-only"`）。Codex 仅在被显式要求时 spawn subagent，故 SKILL.md 视觉处理指令须明确告知 Codex 主 agent "遇到视觉内容时 spawn `vision-reader` 自定义 agent 读取"。
```

- [ ] **Step 2: 默认排除项（第 94-102 行）**

oldString:
```
### 默认排除项
- `.opencode/` — skills 配置目录
- `.claude/` — Claude Code 配置目录（仅启用 Claude Code 支持时）
- `.wiki/` — wiki 内容本身
- `.wiki/cache/` — 链接文档缓存（不计入备份）
- `.git/` — 版本控制
- `AGENTS.md` — 知识库配置文件
- `CLAUDE.md` — Claude Code 入口文件（仅启用 Claude Code 支持时）
- `output/` — 用户自产文件（展示文档、报告等），不会被作为源文件处理
```

newString:
```
### 默认排除项
- `.opencode/` — skills 配置目录
- `.claude/` — Claude Code 配置目录（仅启用 Claude Code 支持时）
- `.agents/` — 共享 skills 配置目录（仅启用 Codex 支持时）
- `.codex/` — Codex 配置目录（仅启用 Codex 支持时）
- `.wiki/` — wiki 内容本身
- `.wiki/cache/` — 链接文档缓存（不计入备份）
- `.git/` — 版本控制
- `AGENTS.md` — 知识库配置文件
- `CLAUDE.md` — Claude Code 入口文件（仅启用 Claude Code 支持时）
- `output/` — 用户自产文件（展示文档、报告等），不会被作为源文件处理
```

- [ ] **Step 3: 主动知识抓取 - 基础设施排除（第 127 行）**

oldString:
```
- **基础设施内容除外**：来自 `.opencode/skills/` 或 `.claude/skills/` 的 SKILL.md 定义、Agent 对系统功能的解释性输出等基础设施/元内容不属于捕获对象
```

newString:
```
- **基础设施内容除外**：来自 `.opencode/skills/`、`.claude/skills/` 或 `.agents/skills/` 的 SKILL.md 定义、Agent 对系统功能的解释性输出等基础设施/元内容不属于捕获对象
```

- [ ] **Step 4: 内容域边界 - 不应捕获清单（第 135-138 行）**

oldString:
```
以下内容不应被视为捕获对象：
- 来自 `.opencode/skills/` 或 `.claude/skills/` 的 SKILL.md 定义
- Agent 对知识库功能或流程的解释
- 任何关于知识库工具本身的话题（安装、配置、维护）
```

newString:
```
以下内容不应被视为捕获对象：
- 来自 `.opencode/skills/`、`.claude/skills/` 或 `.agents/skills/` 的 SKILL.md 定义
- Agent 对知识库功能或流程的解释
- 任何关于知识库工具本身的话题（安装、配置、维护）
```

- [ ] **Step 5: 验证**

Run: `grep -n "\.agents/\|\.codex/agents/vision-reader" templates/AGENTS.md.tmpl`
Expected: 命中 vision-reader 配置、默认排除项、capture 排除清单多处。

- [ ] **Step 6: Commit**

```bash
git add templates/AGENTS.md.tmpl
git commit -m "docs(templates): add codex mode to AGENTS.md template"
```

---

### Task 5: install.sh — 三态客户端模式结构性改动

**Files:**
- Modify: `install.sh`（多处函数）

**Interfaces:**
- Produces（导出给 Task 6/7/12 使用的函数签名）：
  - `CLIENT_MODE` 全局变量，取值 `"opencode"` / `"claude"` / `"codex"`
  - `has_codex_support <target>` → 返回 0 若检测到 Codex 托管文件
  - `detect_current_mode <target>` → echo `"opencode"` / `"claude"` / `"codex"`
  - `get_active_skills_dir <target>` → echo 当前模式 skills 目录绝对路径
  - `get_inactive_skills_dirs <target>` → 输出多行，每行一个需清理的 skills 目录
  - `get_backup_auto_command` → echo 当前模式自动备份 shell 命令
  - `write_codex_vision_reader` / `remove_codex_vision_reader`
  - `sync_client_support_files`（由 `sync_claude_support_files` 重命名）
- Consumes: Task 1 的 `should_exclude_dir`、Task 2/3 的 SKILL.md、Task 4 的模板

- [ ] **Step 1: 顶部变量替换（第 15 行）**

oldString:
```
ENABLE_CLAUDE_CODE=false
LLM_WIKIER_SKILLS=("wiki-init" "wiki-ingest" "wiki-query" "wiki-lint" "wiki-update" "wiki-prune" "wiki-capture" "wiki-backup")
CLAUDE_MANAGED_BEGIN="<!-- LLM-WIKIER:CLAUDE-MANAGED:BEGIN -->"
CLAUDE_MANAGED_END="<!-- LLM-WIKIER:CLAUDE-MANAGED:END -->"
```

newString:
```
CLIENT_MODE="opencode"
LLM_WIKIER_SKILLS=("wiki-init" "wiki-ingest" "wiki-query" "wiki-lint" "wiki-update" "wiki-prune" "wiki-capture" "wiki-backup")
CLAUDE_MANAGED_BEGIN="<!-- LLM-WIKIER:CLAUDE-MANAGED:BEGIN -->"
CLAUDE_MANAGED_END="<!-- LLM-WIKIER:CLAUDE-MANAGED:END -->"
CODEX_AGENT_MANAGED="LLM-WIKIER:CODEX-AGENT-MANAGED"
```

- [ ] **Step 2: `is_update_install` 候选 skills 根增加 `.agents/skills`（第 104 行）**

oldString:
```
    for skills_root in "$target/.opencode/skills" "$target/.claude/skills"; do
```

newString:
```
    for skills_root in "$target/.opencode/skills" "$target/.claude/skills" "$target/.agents/skills"; do
```

- [ ] **Step 3: 新增 `has_codex_support` 与 `detect_current_mode`（在 `has_claude_code_support` 之后插入）**

oldString:
```
has_claude_code_support() {
    local target="$1"

    [[ -f "$target/.claude/skills/wiki-ingest/SKILL.md" ]] && return 0
    if [[ -f "$target/CLAUDE.md" ]] && grep -q "$CLAUDE_MANAGED_BEGIN" "$target/CLAUDE.md"; then
        return 0
    fi

    return 1
}

select_client_support() {
```

newString:
```
has_claude_code_support() {
    local target="$1"

    [[ -f "$target/.claude/skills/wiki-ingest/SKILL.md" ]] && return 0
    if [[ -f "$target/CLAUDE.md" ]] && grep -q "$CLAUDE_MANAGED_BEGIN" "$target/CLAUDE.md"; then
        return 0
    fi

    return 1
}

has_codex_support() {
    local target="$1"

    [[ -f "$target/.agents/skills/wiki-ingest/SKILL.md" ]] && return 0
    if [[ -f "$target/.codex/agents/vision-reader.toml" ]] && grep -q "$CODEX_AGENT_MANAGED" "$target/.codex/agents/vision-reader.toml"; then
        return 0
    fi

    return 1
}

detect_current_mode() {
    local target="$1"

    if has_codex_support "$target"; then
        echo "codex"
    elif has_claude_code_support "$target"; then
        echo "claude"
    else
        echo "opencode"
    fi
}

select_client_support() {
```

- [ ] **Step 4: `select_client_support` 改为三选一交互（整个函数替换）**

oldString:
```
select_client_support() {
    local target="$1"
    local update_mode="$2"

    if [[ "$FORCE" == "true" ]]; then
        if [[ "$update_mode" == "true" ]] && has_claude_code_support "$target"; then
            ENABLE_CLAUDE_CODE=true
        else
            ENABLE_CLAUDE_CODE=false
        fi
        return 0
    fi

    echo ""
    if [[ "$update_mode" == "true" ]] && has_claude_code_support "$target"; then
        if prompt_user "检测到当前知识库已支持 Claude Code，是否继续支持？"; then
            ENABLE_CLAUDE_CODE=true
        else
            ENABLE_CLAUDE_CODE=false
        fi
    else
        echo -e "${YELLOW}[询问]${NC} 是否需要支持除 OpenCode 之外的其它客户端？当前可选：Claude Code [y/N] "
        read -r response
        case "$response" in
            [yY]|[yY][eE][sS]) ENABLE_CLAUDE_CODE=true ;;
            *) ENABLE_CLAUDE_CODE=false ;;
        esac
    fi

    if [[ "$ENABLE_CLAUDE_CODE" == "true" ]]; then
        print_info "客户端模式: OpenCode + Claude Code"
    else
        print_info "客户端模式: OpenCode-only"
    fi
}
```

newString:
```
select_client_support() {
    local target="$1"
    local update_mode="$2"

    if [[ "$FORCE" == "true" ]]; then
        if [[ "$update_mode" == "true" ]]; then
            CLIENT_MODE=$(detect_current_mode "$target")
        else
            CLIENT_MODE="opencode"
        fi
        return 0
    fi

    echo ""
    if [[ "$update_mode" == "true" ]]; then
        local current_mode
        current_mode=$(detect_current_mode "$target")
        case "$current_mode" in
            claude) print_info "检测到当前知识库已支持 Claude Code" ;;
            codex)  print_info "检测到当前知识库已支持 Codex" ;;
            *)      print_info "检测到当前知识库为 OpenCode-only" ;;
        esac
        echo -e "${YELLOW}[询问]${NC} 选择客户端模式："
        echo "  1) 保持不变（$current_mode）"
        echo "  2) OpenCode + Codex"
        echo "  3) OpenCode + Claude Code"
        echo "  4) 仅 OpenCode（移除其他支持）"
        read -r response
        case "$response" in
            1|"") CLIENT_MODE="$current_mode" ;;
            2) CLIENT_MODE="codex" ;;
            3) CLIENT_MODE="claude" ;;
            4) CLIENT_MODE="opencode" ;;
            *)
                print_warning "无效选择，保持当前模式"
                CLIENT_MODE="$current_mode"
                ;;
        esac
    else
        echo -e "${YELLOW}[询问]${NC} 是否需要支持除 OpenCode 之外的其它客户端？"
        echo "  1) 仅 OpenCode（默认）"
        echo "  2) OpenCode + Claude Code"
        echo "  3) OpenCode + Codex"
        read -r response
        case "$response" in
            2) CLIENT_MODE="claude" ;;
            3) CLIENT_MODE="codex" ;;
            *) CLIENT_MODE="opencode" ;;
        esac
    fi

    case "$CLIENT_MODE" in
        claude) print_info "客户端模式: OpenCode + Claude Code" ;;
        codex)  print_info "客户端模式: OpenCode + Codex" ;;
        *)      print_info "客户端模式: OpenCode-only" ;;
    esac
}
```

- [ ] **Step 5: `get_active_skills_dir` / `get_inactive_skills_dirs` / `get_backup_auto_command` 三函数**

oldString:
```
get_active_skills_dir() {
    local target="$1"

    if [[ "$ENABLE_CLAUDE_CODE" == "true" ]]; then
        echo "$target/.claude/skills"
    else
        echo "$target/.opencode/skills"
    fi
}

get_inactive_skills_dir() {
    local target="$1"

    if [[ "$ENABLE_CLAUDE_CODE" == "true" ]]; then
        echo "$target/.opencode/skills"
    else
        echo "$target/.claude/skills"
    fi
}

get_backup_auto_command() {
    if [[ "$ENABLE_CLAUDE_CODE" == "true" ]]; then
        echo "bash .claude/skills/wiki-backup/backup.sh --auto"
    else
        echo "bash .opencode/skills/wiki-backup/backup.sh --auto"
    fi
}
```

newString:
```
get_active_skills_dir() {
    local target="$1"

    case "$CLIENT_MODE" in
        claude) echo "$target/.claude/skills" ;;
        codex)  echo "$target/.agents/skills" ;;
        *)      echo "$target/.opencode/skills" ;;
    esac
}

get_inactive_skills_dirs() {
    local target="$1"

    case "$CLIENT_MODE" in
        claude) echo "$target/.opencode/skills"; echo "$target/.agents/skills" ;;
        codex)  echo "$target/.opencode/skills"; echo "$target/.claude/skills" ;;
        *)      echo "$target/.claude/skills";   echo "$target/.agents/skills" ;;
    esac
}

get_backup_auto_command() {
    case "$CLIENT_MODE" in
        claude) echo "bash .claude/skills/wiki-backup/backup.sh --auto" ;;
        codex)  echo "bash .agents/skills/wiki-backup/backup.sh --auto" ;;
        *)      echo "bash .opencode/skills/wiki-backup/backup.sh --auto" ;;
    esac
}
```

- [ ] **Step 6: `get_existing_backup_root` 候选文件列表增加 `.agents/skills/...`**

oldString:
```
    local files=(
        "$target/.opencode/skills/wiki-backup/backup.sh"
        "$target/.claude/skills/wiki-backup/backup.sh"
        "$target/.opencode/skills/wiki-backup/backup.ps1"
        "$target/.claude/skills/wiki-backup/backup.ps1"
    )
```

newString:
```
    local files=(
        "$target/.opencode/skills/wiki-backup/backup.sh"
        "$target/.claude/skills/wiki-backup/backup.sh"
        "$target/.agents/skills/wiki-backup/backup.sh"
        "$target/.opencode/skills/wiki-backup/backup.ps1"
        "$target/.claude/skills/wiki-backup/backup.ps1"
        "$target/.agents/skills/wiki-backup/backup.ps1"
    )
```

- [ ] **Step 7: `check_existing_installation` 增加 Codex 托管检测**

oldString:
```
    local claude_managed=false
    if has_claude_code_support "$TARGET_DIR"; then
        claude_managed=true
    fi
    
    if [[ -d "$wiki_dir" || -d "$old_wiki_dir" || -f "$agents_file" || -d "$skills_dir" || "$claude_managed" == "true" ]]; then
```

newString:
```
    local claude_managed=false
    local codex_managed=false
    if has_claude_code_support "$TARGET_DIR"; then
        claude_managed=true
    fi
    if has_codex_support "$TARGET_DIR"; then
        codex_managed=true
    fi
    
    if [[ -d "$wiki_dir" || -d "$old_wiki_dir" || -f "$agents_file" || -d "$skills_dir" || "$claude_managed" == "true" || "$codex_managed" == "true" ]]; then
```

- [ ] **Step 8: `create_wiki_ignore_file` 按 `CLIENT_MODE` 生成默认规则**

oldString:
```
    cat > "$ignore_file" << EOF
# LLM Wikier — 默认排除规则（由工具包管理，请勿修改此区域）
.opencode/
$(if [[ "$ENABLE_CLAUDE_CODE" == "true" ]]; then echo ".claude/"; fi)
.wiki/
.wiki/cache/
.git/
AGENTS.md
$(if [[ "$ENABLE_CLAUDE_CODE" == "true" ]]; then echo "CLAUDE.md"; fi)
output/

# ——— 用户自定义规则（添加在此区域下方） ———
EOF
```

newString:
```
    cat > "$ignore_file" << EOF
# LLM Wikier — 默认排除规则（由工具包管理，请勿修改此区域）
.opencode/
$(if [[ "$CLIENT_MODE" == "claude" ]]; then echo ".claude/"; fi)
$(if [[ "$CLIENT_MODE" == "codex" ]]; then echo ".agents/"; echo ".codex/"; fi)
.wiki/
.wiki/cache/
.git/
AGENTS.md
$(if [[ "$CLIENT_MODE" == "claude" ]]; then echo "CLAUDE.md"; fi)
output/

# ——— 用户自定义规则（添加在此区域下方） ———
EOF
```

- [ ] **Step 9: `create_skills_directory` 使用 `get_inactive_skills_dirs`（复数）**

oldString:
```
create_skills_directory() {
    local skills_dir
    skills_dir=$(get_active_skills_dir "$TARGET_DIR")
    local inactive_skills_dir
    inactive_skills_dir=$(get_inactive_skills_dir "$TARGET_DIR")
    
    mkdir -p "$skills_dir"

    for skill in "${LLM_WIKIER_SKILLS[@]}"; do
        local src_dir="$SKILLS_SOURCE/$skill"
        local dst_dir="$skills_dir/$skill"
        
        if [[ -d "$src_dir" ]]; then
            mkdir -p "$dst_dir"
            cp -r "$src_dir/"* "$dst_dir/"
            print_success "安装 skill: $skill"
        else
            print_warning "找不到 skill 源文件: $skill"
        fi
    done

    remove_managed_skills_from_dir "$inactive_skills_dir"
}
```

newString:
```
create_skills_directory() {
    local skills_dir
    skills_dir=$(get_active_skills_dir "$TARGET_DIR")
    
    mkdir -p "$skills_dir"

    for skill in "${LLM_WIKIER_SKILLS[@]}"; do
        local src_dir="$SKILLS_SOURCE/$skill"
        local dst_dir="$skills_dir/$skill"
        
        if [[ -d "$src_dir" ]]; then
            mkdir -p "$dst_dir"
            cp -r "$src_dir/"* "$dst_dir/"
            print_success "安装 skill: $skill"
        else
            print_warning "找不到 skill 源文件: $skill"
        fi
    done

    local inactive_dir
    while IFS= read -r inactive_dir; do
        remove_managed_skills_from_dir "$inactive_dir"
    done < <(get_inactive_skills_dirs "$TARGET_DIR")
}
```

- [ ] **Step 10: 新增 Codex vision-reader 函数 + 重命名 `sync_claude_support_files` → `sync_client_support_files`**

oldString:
```
remove_claude_vision_reader() {
    local agent_file="$TARGET_DIR/.claude/agents/vision-reader.md"
    [[ ! -f "$agent_file" ]] && return 0
    if grep -q "LLM-WIKIER:CLAUDE-AGENT-MANAGED" "$agent_file"; then
        rm -f "$agent_file"
        rmdir "$TARGET_DIR/.claude/agents" 2>/dev/null || true
        rmdir "$TARGET_DIR/.claude" 2>/dev/null || true
        print_success "已移除 LLM Wikier 托管的 Claude Code vision-reader"
    else
        print_info "保留用户自定义 Claude Code vision-reader"
    fi
}

sync_claude_support_files() {
    if [[ "$ENABLE_CLAUDE_CODE" == "true" ]]; then
        write_claude_file
        write_claude_vision_reader
    else
        remove_claude_file_managed_block
        remove_claude_vision_reader
    fi
}
```

newString:
```
remove_claude_vision_reader() {
    local agent_file="$TARGET_DIR/.claude/agents/vision-reader.md"
    [[ ! -f "$agent_file" ]] && return 0
    if grep -q "LLM-WIKIER:CLAUDE-AGENT-MANAGED" "$agent_file"; then
        rm -f "$agent_file"
        rmdir "$TARGET_DIR/.claude/agents" 2>/dev/null || true
        rmdir "$TARGET_DIR/.claude" 2>/dev/null || true
        print_success "已移除 LLM Wikier 托管的 Claude Code vision-reader"
    else
        print_info "保留用户自定义 Claude Code vision-reader"
    fi
}

write_codex_vision_reader() {
    local agent_dir="$TARGET_DIR/.codex/agents"
    local agent_file="$agent_dir/vision-reader.toml"

    if [[ -f "$agent_file" ]] && ! grep -q "$CODEX_AGENT_MANAGED" "$agent_file"; then
        print_info "保留用户自定义 Codex vision-reader: $agent_file"
        return 0
    fi

    mkdir -p "$agent_dir"
    cat > "$agent_file" << 'EOF'
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
EOF
    print_success "已配置 Codex vision-reader: $agent_file"
}

remove_codex_vision_reader() {
    local agent_file="$TARGET_DIR/.codex/agents/vision-reader.toml"
    [[ ! -f "$agent_file" ]] && return 0
    if grep -q "$CODEX_AGENT_MANAGED" "$agent_file"; then
        rm -f "$agent_file"
        rmdir "$TARGET_DIR/.codex/agents" 2>/dev/null || true
        rmdir "$TARGET_DIR/.codex" 2>/dev/null || true
        print_success "已移除 LLM Wikier 托管的 Codex vision-reader"
    else
        print_info "保留用户自定义 Codex vision-reader"
    fi
}

sync_client_support_files() {
    case "$CLIENT_MODE" in
        claude)
            write_claude_file
            write_claude_vision_reader
            remove_codex_vision_reader
            ;;
        codex)
            write_codex_vision_reader
            remove_claude_file_managed_block
            remove_claude_vision_reader
            ;;
        *)
            remove_claude_file_managed_block
            remove_claude_vision_reader
            remove_codex_vision_reader
            ;;
    esac
}
```

- [ ] **Step 11: `update_skills` 使用 `get_inactive_skills_dirs`（复数）**

oldString:
```
update_skills() {
    local target="$1"
    local skills_dir
    skills_dir=$(get_active_skills_dir "$target")
    local inactive_skills_dir
    inactive_skills_dir=$(get_inactive_skills_dir "$target")
    local existing_backup_root
    existing_backup_root=$(get_existing_backup_root "$target" || true)

    mkdir -p "$skills_dir"

    local updated=0

    for skill in "${LLM_WIKIER_SKILLS[@]}"; do
        local src="$SKILLS_SOURCE/$skill"
        local dst="$skills_dir/$skill"

        if [[ -d "$src" ]]; then
            mkdir -p "$dst"
            cp -r "$src/"* "$dst/"
            print_success "更新 skill: $skill"
            updated=$((updated + 1))
        else
            print_warning "找不到 skill 源文件: $skill"
        fi
    done

    if [[ $updated -gt 0 ]]; then
        print_info "共更新 $updated 个 skill"
    fi

    remove_managed_skills_from_dir "$inactive_skills_dir"

    if [[ -n "$existing_backup_root" ]]; then
        write_backup_root "$target" "$existing_backup_root"
        print_info "已保留既有备份根目录: $existing_backup_root"
    fi
}
```

newString:
```
update_skills() {
    local target="$1"
    local skills_dir
    skills_dir=$(get_active_skills_dir "$target")
    local existing_backup_root
    existing_backup_root=$(get_existing_backup_root "$target" || true)

    mkdir -p "$skills_dir"

    local updated=0

    for skill in "${LLM_WIKIER_SKILLS[@]}"; do
        local src="$SKILLS_SOURCE/$skill"
        local dst="$skills_dir/$skill"

        if [[ -d "$src" ]]; then
            mkdir -p "$dst"
            cp -r "$src/"* "$dst/"
            print_success "更新 skill: $skill"
            updated=$((updated + 1))
        else
            print_warning "找不到 skill 源文件: $skill"
        fi
    done

    if [[ $updated -gt 0 ]]; then
        print_info "共更新 $updated 个 skill"
    fi

    local inactive_dir
    while IFS= read -r inactive_dir; do
        remove_managed_skills_from_dir "$inactive_dir"
    done < <(get_inactive_skills_dirs "$target")

    if [[ -n "$existing_backup_root" ]]; then
        write_backup_root "$target" "$existing_backup_root"
        print_info "已保留既有备份根目录: $existing_backup_root"
    fi
}
```

- [ ] **Step 12: `update_install` 用 `detect_current_mode` 替换 `had_claude`，调用 `sync_client_support_files`**

oldString:
```
    local had_claude=false
    if has_claude_code_support "$target"; then
        had_claude=true
    fi

    select_client_support "$target" true

    local mode_changed=false
    if [[ "$had_claude" != "$ENABLE_CLAUDE_CODE" ]]; then
        mode_changed=true
    fi

    echo ""
    print_info "更新安装将执行以下操作："
    print_info "  (1) 更新 skills — 从本仓库同步最新 skill 文件"
    print_info "  (2) 更新 AGENTS.md — 从模板更新，保留您的用户偏好和自定义配置"
    print_info "  (3) 更新 .wiki_ignore — 从模板更新，保留用户自定义规则"
    print_info "  (4) 同步客户端配置 — 根据选择创建或移除 Claude Code 托管文件"
    print_info "  (5) 配置备份根目录"
    echo ""

    if [[ "$mode_changed" == "true" ]]; then
        print_info "客户端模式已变化，自动同步 skills 目录"
        update_skills "$target"
    elif prompt_user "Step (1/5): 是否更新 skills？（将覆盖现有 skill 文件）"; then
        update_skills "$target"
    else
        print_info "已跳过更新 skills"
    fi

    if [[ "$mode_changed" == "true" ]]; then
        print_info "客户端模式已变化，自动更新 AGENTS.md 以修正备份路径"
        update_agents_file "$target"
    elif prompt_user "Step (2/5): 是否更新 AGENTS.md？（模板章节将刷新，用户偏好和自定义配置章节将保留）"; then
        update_agents_file "$target"
    else
        print_info "已跳过更新 AGENTS.md"
    fi

    if prompt_user "Step (3/5): 是否更新 .wiki_ignore？（默认规则将刷新，用户自定义规则将保留）"; then
        merge_wiki_ignore "$target"
    else
        print_info "已跳过更新 .wiki_ignore"
    fi

    print_info "Step (4/5): 同步客户端配置"
    sync_claude_support_files
```

newString:
```
    local previous_mode
    previous_mode=$(detect_current_mode "$target")

    select_client_support "$target" true

    local mode_changed=false
    if [[ "$previous_mode" != "$CLIENT_MODE" ]]; then
        mode_changed=true
    fi

    echo ""
    print_info "更新安装将执行以下操作："
    print_info "  (1) 更新 skills — 从本仓库同步最新 skill 文件"
    print_info "  (2) 更新 AGENTS.md — 从模板更新，保留您的用户偏好和自定义配置"
    print_info "  (3) 更新 .wiki_ignore — 从模板更新，保留用户自定义规则"
    print_info "  (4) 同步客户端配置 — 根据选择创建或移除客户端托管文件"
    print_info "  (5) 配置备份根目录"
    echo ""

    if [[ "$mode_changed" == "true" ]]; then
        print_info "客户端模式已变化（$previous_mode → $CLIENT_MODE），自动同步 skills 目录"
        update_skills "$target"
    elif prompt_user "Step (1/5): 是否更新 skills？（将覆盖现有 skill 文件）"; then
        update_skills "$target"
    else
        print_info "已跳过更新 skills"
    fi

    if [[ "$mode_changed" == "true" ]]; then
        print_info "客户端模式已变化，自动更新 AGENTS.md 以修正备份路径"
        update_agents_file "$target"
    elif prompt_user "Step (2/5): 是否更新 AGENTS.md？（模板章节将刷新，用户偏好和自定义配置章节将保留）"; then
        update_agents_file "$target"
    else
        print_info "已跳过更新 AGENTS.md"
    fi

    if prompt_user "Step (3/5): 是否更新 .wiki_ignore？（默认规则将刷新，用户自定义规则将保留）"; then
        merge_wiki_ignore "$target"
    else
        print_info "已跳过更新 .wiki_ignore"
    fi

    print_info "Step (4/5): 同步客户端配置"
    sync_client_support_files
```

- [ ] **Step 13: `print_completion_message` 三态启动提示 + Codex 调用方式**

oldString:
```
    echo "2. 启动 OpenCode："
    echo "   opencode"
    if [[ "$ENABLE_CLAUDE_CODE" == "true" ]]; then
        echo "   或启动 Claude Code："
        echo "   claude"
    fi
    echo ""
    echo "3. 如果知识库已有文件，运行批量初始化："
    echo "   /wiki-init"
    echo ""
    echo "4. 或者添加新文件后运行增量处理："
    echo "   /wiki-ingest"
```

newString:
```
    echo "2. 启动 OpenCode："
    echo "   opencode"
    case "$CLIENT_MODE" in
        claude)
            echo "   或启动 Claude Code："
            echo "   claude"
            ;;
        codex)
            echo "   或启动 Codex："
            echo "   codex"
            ;;
    esac
    echo ""
    echo "3. 如果知识库已有文件，运行批量初始化："
    echo "   OpenCode: /wiki-init"
    case "$CLIENT_MODE" in
        codex) echo "   Codex: \$wiki-init 或 /skills 选择 wiki-init" ;;
    esac
    echo ""
    echo "4. 或者添加新文件后运行增量处理："
    echo "   OpenCode: /wiki-ingest"
    case "$CLIENT_MODE" in
        codex) echo "   Codex: \$wiki-ingest 或 /skills 选择 wiki-ingest" ;;
    esac
```

- [ ] **Step 14: `configure_vision_reader` 区分 Codex 模式提示**

oldString:
```
configure_vision_reader() {
    local target="$1"

    if [[ "$FORCE" == "true" ]]; then
        print_info "强制安装模式，跳过 vision-reader 交互配置"
        print_info "稍后可手动运行: ./config_vision_reader.sh \"$target\""
        return 0
    fi

    echo ""
    if ! prompt_user "是否配置 vision-reader subagent？（用于读取图片/幻灯片/PDF 等视觉内容）"; then
        print_info "已跳过 vision-reader 配置"
        return 0
    fi

    local config_script="$SCRIPT_DIR/config_vision_reader.sh"
    if [[ ! -f "$config_script" ]]; then
        print_error "找不到配置脚本: $config_script"
        return 1
    fi

    echo ""
    print_info "正在配置 vision-reader..."
    bash "$config_script" "$target" -f
}
```

newString:
```
configure_vision_reader() {
    local target="$1"

    if [[ "$FORCE" == "true" ]]; then
        print_info "强制安装模式，跳过 vision-reader 交互配置"
        print_info "稍后可手动运行: ./config_vision_reader.sh \"$target\""
        if [[ "$CLIENT_MODE" == "codex" ]]; then
            print_info "Codex 版 vision-reader 已由安装器预生成（.codex/agents/vision-reader.toml）"
        fi
        return 0
    fi

    echo ""
    if [[ "$CLIENT_MODE" == "codex" ]]; then
        print_info "Codex 版 vision-reader 已由安装器预生成（.codex/agents/vision-reader.toml），不指定模型由 Codex 自动选择"
    fi
    if ! prompt_user "是否配置 OpenCode 版 vision-reader subagent？（用于在 OpenCode 中读取图片/幻灯片/PDF 等视觉内容）"; then
        print_info "已跳过 OpenCode 版 vision-reader 配置"
        return 0
    fi

    local config_script="$SCRIPT_DIR/config_vision_reader.sh"
    if [[ ! -f "$config_script" ]]; then
        print_error "找不到配置脚本: $config_script"
        return 1
    fi

    echo ""
    print_info "正在配置 OpenCode 版 vision-reader..."
    bash "$config_script" "$target" -f
}
```

- [ ] **Step 15: `main` 中调用 `sync_claude_support_files` → `sync_client_support_files`**

oldString:
```
        create_skills_directory
        create_agents_file
        sync_claude_support_files
```

newString:
```
        create_skills_directory
        create_agents_file
        sync_client_support_files
```

- [ ] **Step 16: 验证 shell 语法**

Run: `bash -n install.sh`
Expected: 无输出（语法 OK）

Run: `grep -n "ENABLE_CLAUDE_CODE" install.sh`
Expected: 无输出（变量已全部替换）

Run: `grep -n "sync_claude_support_files\|get_inactive_skills_dir[^s]" install.sh`
Expected: 无输出（旧函数名已全部替换）

- [ ] **Step 17: Commit**

```bash
git add install.sh
git commit -m "feat(install): add codex client mode to install.sh"
```

---

### Task 6: install.sh — 内置 fallback AGENTS.md 内容补丁（两处）

**Files:**
- Modify: `install.sh` 中 `create_agents_file` 的 fallback（约 519-630 行）与 `update_agents_file` 的 fallback（约 1063-1149 行）

**Interfaces:**
- Consumes: Task 4 已完成的模板内容补丁（保持一致）
- Produces: install.sh 两份内置 fallback 与 templates/AGENTS.md.tmpl 内容同步

- [ ] **Step 1: 两份 fallback 的 vision-reader 配置路径说明（各一处，共 2 处）**

两份 fallback 中均有此段（`create_agents_file` 约 574 行；`update_agents_file` 约 1112 行）。先在 `create_agents_file` 中编辑（用更多上下文唯一定位），再在 `update_agents_file` 中编辑。

oldString:
```
如当前客户端未配置 `vision-reader`，Agent 跳过视觉处理。OpenCode 配置路径为 `.opencode/agents/vision-reader.md`，Claude Code 配置路径为 `.claude/agents/vision-reader.md`。

OpenCode 配置方式：`./config_vision_reader.sh <知识库路径>`。启用 Claude Code 支持时，安装器会生成 Claude Code 版 `vision-reader`。
```

newString:
```
如当前客户端未配置 `vision-reader`，Agent 跳过视觉处理。OpenCode 配置路径为 `.opencode/agents/vision-reader.md`，Claude Code 配置路径为 `.claude/agents/vision-reader.md`，Codex 配置路径为 `.codex/agents/vision-reader.toml`。

OpenCode 配置方式：`./config_vision_reader.sh <知识库路径>`。启用 Claude Code 支持时安装器生成 Claude Code 版 `vision-reader`；启用 Codex 支持时安装器生成 Codex 版 `vision-reader`（不指定 model，由 Codex 自动选择）。
```

（注：两份 fallback 中此段内容相同但存在于不同函数，需分别编辑——`edit` 工具会因 `replaceAll` 同时替换两处，或分别用更长上下文定位。建议用 `replaceAll: true` 一次替换两处。）

- [ ] **Step 2: 两份 fallback 的默认排除项（各一处，共 2 处）**

oldString:
```
### 默认排除项
- `.opencode/` — skills 配置目录
- `.claude/` — Claude Code 配置目录（仅启用 Claude Code 支持时）
- `.wiki/` — wiki 内容本身
- `.wiki/cache/` — 链接文档缓存（不计入备份）
- `.git/` — 版本控制
- `AGENTS.md` — 知识库配置文件
- `CLAUDE.md` — Claude Code 入口文件（仅启用 Claude Code 支持时）
- `output/` — 用户自产文件（展示文档、报告等），不会被作为源文件处理
```

newString:
```
### 默认排除项
- `.opencode/` — skills 配置目录
- `.claude/` — Claude Code 配置目录（仅启用 Claude Code 支持时）
- `.agents/` — 共享 skills 配置目录（仅启用 Codex 支持时）
- `.codex/` — Codex 配置目录（仅启用 Codex 支持时）
- `.wiki/` — wiki 内容本身
- `.wiki/cache/` — 链接文档缓存（不计入备份）
- `.git/` — 版本控制
- `AGENTS.md` — 知识库配置文件
- `CLAUDE.md` — Claude Code 入口文件（仅启用 Claude Code 支持时）
- `output/` — 用户自产文件（展示文档、报告等），不会被作为源文件处理
```

（两份 fallback 内容相同，用 `replaceAll: true` 一次替换两处。）

- [ ] **Step 3: 验证**

Run: `bash -n install.sh`
Expected: 无输出

Run: `grep -c "\.codex/agents/vision-reader\.toml" install.sh`
Expected: 4（templates 不被算入；两份 fallback 各 2 处 = vision-reader 配置段 + OpenCode 配置方式段）

Run: `grep -c "\.agents/ — 共享 skills" install.sh`
Expected: 2（两份 fallback 各 1 处）

- [ ] **Step 4: Commit**

```bash
git add install.sh
git commit -m "docs(install): sync fallback AGENTS.md content with codex mode"
```

---

### Task 7: install.ps1 — 镜像 install.sh 三态改动

**Files:**
- Modify: `install.ps1`（多处函数，镜像 Task 5）

**Interfaces:**
- Produces（与 install.sh 对等的 PowerShell 函数）：
  - `$script:ClientMode` 取值 `"opencode"` / `"claude"` / `"codex"`
  - `Test-CodexSupport`、`Get-CurrentMode`、`Get-ActiveSkillsDir`、`Get-InactiveSkillsDirs`（复数）、`Get-BackupAutoCommand`、`Write-CodexVisionReader`、`Remove-CodexVisionReader`、`Sync-ClientSupportFiles`（由 `Sync-ClaudeSupportFiles` 改名）

- [ ] **Step 1: 顶部变量替换（第 15-18 行）**

oldString:
```
$script:EnableClaudeCode = $false
$script:LlmWikierSkills = @("wiki-init", "wiki-ingest", "wiki-query", "wiki-lint", "wiki-update", "wiki-prune", "wiki-capture", "wiki-backup")
$script:ClaudeManagedBegin = "<!-- LLM-WIKIER:CLAUDE-MANAGED:BEGIN -->"
$script:ClaudeManagedEnd = "<!-- LLM-WIKIER:CLAUDE-MANAGED:END -->"
```

newString:
```
$script:ClientMode = "opencode"
$script:LlmWikierSkills = @("wiki-init", "wiki-ingest", "wiki-query", "wiki-lint", "wiki-update", "wiki-prune", "wiki-capture", "wiki-backup")
$script:ClaudeManagedBegin = "<!-- LLM-WIKIER:CLAUDE-MANAGED:BEGIN -->"
$script:ClaudeManagedEnd = "<!-- LLM-WIKIER:CLAUDE-MANAGED:END -->"
$script:CodexAgentManaged = "LLM-WIKIER:CODEX-AGENT-MANAGED"
```

- [ ] **Step 2: `Test-UpdateInstall` 候选 skill 根增加 `.agents\skills`（第 68-71 行）**

oldString:
```
    $SkillRoots = @(
        (Join-Path $TargetDir ".opencode\skills"),
        (Join-Path $TargetDir ".claude\skills")
    )
```

newString:
```
    $SkillRoots = @(
        (Join-Path $TargetDir ".opencode\skills"),
        (Join-Path $TargetDir ".claude\skills"),
        (Join-Path $TargetDir ".agents\skills")
    )
```

- [ ] **Step 3: 新增 `Test-CodexSupport` 与 `Get-CurrentMode`（在 `Test-ClaudeCodeSupport` 之后插入）**

oldString:
```
function Test-ClaudeCodeSupport {
    param([string]$TargetDir)

    $ClaudeSkill = Join-Path $TargetDir ".claude\skills\wiki-ingest\SKILL.md"
    if (Test-Path $ClaudeSkill) { return $true }

    $ClaudeFile = Join-Path $TargetDir "CLAUDE.md"
    if (Test-Path $ClaudeFile) {
        $Content = Get-Content $ClaudeFile -Raw -ErrorAction SilentlyContinue
        if ($Content -and $Content.Contains($script:ClaudeManagedBegin)) { return $true }
    }

    return $false
}

function Invoke-PromptUser {
```

newString:
```
function Test-ClaudeCodeSupport {
    param([string]$TargetDir)

    $ClaudeSkill = Join-Path $TargetDir ".claude\skills\wiki-ingest\SKILL.md"
    if (Test-Path $ClaudeSkill) { return $true }

    $ClaudeFile = Join-Path $TargetDir "CLAUDE.md"
    if (Test-Path $ClaudeFile) {
        $Content = Get-Content $ClaudeFile -Raw -ErrorAction SilentlyContinue
        if ($Content -and $Content.Contains($script:ClaudeManagedBegin)) { return $true }
    }

    return $false
}

function Test-CodexSupport {
    param([string]$TargetDir)

    $CodexSkill = Join-Path $TargetDir ".agents\skills\wiki-ingest\SKILL.md"
    if (Test-Path $CodexSkill) { return $true }

    $CodexAgent = Join-Path $TargetDir ".codex\agents\vision-reader.toml"
    if (Test-Path $CodexAgent) {
        $Content = Get-Content $CodexAgent -Raw -ErrorAction SilentlyContinue
        if ($Content -and $Content.Contains($script:CodexAgentManaged)) { return $true }
    }

    return $false
}

function Get-CurrentMode {
    param([string]$TargetDir)

    if (Test-CodexSupport -TargetDir $TargetDir) { return "codex" }
    if (Test-ClaudeCodeSupport -TargetDir $TargetDir) { return "claude" }
    return "opencode"
}

function Invoke-PromptUser {
```

- [ ] **Step 4: `Select-ClientSupport` 改为三选一（整个函数替换）**

oldString:
```
function Select-ClientSupport {
    param([string]$TargetDir, [bool]$IsUpdate)

    if ($Force) {
        $script:EnableClaudeCode = ($IsUpdate -and (Test-ClaudeCodeSupport -TargetDir $TargetDir))
        return
    }

    Write-Host ""
    if ($IsUpdate -and (Test-ClaudeCodeSupport -TargetDir $TargetDir)) {
        if (Invoke-PromptUser "检测到当前知识库已支持 Claude Code，是否继续支持？") {
            $script:EnableClaudeCode = $true
        } else {
            $script:EnableClaudeCode = $false
        }
    } else {
        Write-Host "[询问] " -ForegroundColor Yellow -NoNewline
        Write-Host "是否需要支持除 OpenCode 之外的其它客户端？当前可选：Claude Code [y/N] " -NoNewline
        $Response = Read-Host
        $script:EnableClaudeCode = ($Response -match '^[yY](es|ES)?$')
    }

    if ($script:EnableClaudeCode) {
        Write-Info-Message "客户端模式: OpenCode + Claude Code"
    } else {
        Write-Info-Message "客户端模式: OpenCode-only"
    }
}
```

newString:
```
function Select-ClientSupport {
    param([string]$TargetDir, [bool]$IsUpdate)

    if ($Force) {
        if ($IsUpdate) {
            $script:ClientMode = Get-CurrentMode -TargetDir $TargetDir
        } else {
            $script:ClientMode = "opencode"
        }
        return
    }

    Write-Host ""
    if ($IsUpdate) {
        $CurrentMode = Get-CurrentMode -TargetDir $TargetDir
        switch ($CurrentMode) {
            "claude" { Write-Info-Message "检测到当前知识库已支持 Claude Code" }
            "codex"  { Write-Info-Message "检测到当前知识库已支持 Codex" }
            default  { Write-Info-Message "检测到当前知识库为 OpenCode-only" }
        }
        Write-Host "[询问] " -ForegroundColor Yellow -NoNewline
        Write-Host "选择客户端模式："
        Write-Host "  1) 保持不变（$CurrentMode）"
        Write-Host "  2) OpenCode + Codex"
        Write-Host "  3) OpenCode + Claude Code"
        Write-Host "  4) 仅 OpenCode（移除其他支持）"
        $Response = (Read-Host).Trim()
        switch ($Response) {
            "1" { $script:ClientMode = $CurrentMode }
            ""  { $script:ClientMode = $CurrentMode }
            "2" { $script:ClientMode = "codex" }
            "3" { $script:ClientMode = "claude" }
            "4" { $script:ClientMode = "opencode" }
            default {
                Write-Warning-Message "无效选择，保持当前模式"
                $script:ClientMode = $CurrentMode
            }
        }
    } else {
        Write-Host "[询问] " -ForegroundColor Yellow -NoNewline
        Write-Host "是否需要支持除 OpenCode 之外的其它客户端？"
        Write-Host "  1) 仅 OpenCode（默认）"
        Write-Host "  2) OpenCode + Claude Code"
        Write-Host "  3) OpenCode + Codex"
        $Response = (Read-Host).Trim()
        switch ($Response) {
            "2" { $script:ClientMode = "claude" }
            "3" { $script:ClientMode = "codex" }
            default { $script:ClientMode = "opencode" }
        }
    }

    switch ($script:ClientMode) {
        "claude" { Write-Info-Message "客户端模式: OpenCode + Claude Code" }
        "codex"  { Write-Info-Message "客户端模式: OpenCode + Codex" }
        default  { Write-Info-Message "客户端模式: OpenCode-only" }
    }
}
```

- [ ] **Step 5: `Get-ActiveSkillsDir` / `Get-InactiveSkillsDirs`（复数） / `Get-BackupAutoCommand` 三函数**

oldString:
```
function Get-ActiveSkillsDir {
    param([string]$TargetDir)
    if ($script:EnableClaudeCode) {
        return (Join-Path $TargetDir ".claude\skills")
    }
    return (Join-Path $TargetDir ".opencode\skills")
}

function Get-InactiveSkillsDir {
    param([string]$TargetDir)
    if ($script:EnableClaudeCode) {
        return (Join-Path $TargetDir ".opencode\skills")
    }
    return (Join-Path $TargetDir ".claude\skills")
}

function Get-BackupAutoCommand {
    if ($script:EnableClaudeCode) {
        return "powershell -NoProfile -ExecutionPolicy Bypass -File .claude\skills\wiki-backup\backup.ps1 -Auto"
    }
    return "powershell -NoProfile -ExecutionPolicy Bypass -File .opencode\skills\wiki-backup\backup.ps1 -Auto"
}
```

newString:
```
function Get-ActiveSkillsDir {
    param([string]$TargetDir)
    switch ($script:ClientMode) {
        "claude" { return (Join-Path $TargetDir ".claude\skills") }
        "codex"  { return (Join-Path $TargetDir ".agents\skills") }
        default  { return (Join-Path $TargetDir ".opencode\skills") }
    }
}

function Get-InactiveSkillsDirs {
    param([string]$TargetDir)
    switch ($script:ClientMode) {
        "claude" { return @((Join-Path $TargetDir ".opencode\skills"), (Join-Path $TargetDir ".agents\skills")) }
        "codex"  { return @((Join-Path $TargetDir ".opencode\skills"), (Join-Path $TargetDir ".claude\skills")) }
        default  { return @((Join-Path $TargetDir ".claude\skills"), (Join-Path $TargetDir ".agents\skills")) }
    }
}

function Get-BackupAutoCommand {
    switch ($script:ClientMode) {
        "claude" { return "powershell -NoProfile -ExecutionPolicy Bypass -File .claude\skills\wiki-backup\backup.ps1 -Auto" }
        "codex"  { return "powershell -NoProfile -ExecutionPolicy Bypass -File .agents\skills\wiki-backup\backup.ps1 -Auto" }
        default  { return "powershell -NoProfile -ExecutionPolicy Bypass -File .opencode\skills\wiki-backup\backup.ps1 -Auto" }
    }
}
```

- [ ] **Step 6: `Get-ExistingBackupRoot` 候选增加 `.agents\skills\...`（第 170-175 行）**

oldString:
```
    $Candidates = @(
        (Join-Path $TargetDir ".opencode\skills\wiki-backup\backup.ps1"),
        (Join-Path $TargetDir ".claude\skills\wiki-backup\backup.ps1"),
        (Join-Path $TargetDir ".opencode\skills\wiki-backup\backup.sh"),
        (Join-Path $TargetDir ".claude\skills\wiki-backup\backup.sh")
    )
```

newString:
```
    $Candidates = @(
        (Join-Path $TargetDir ".opencode\skills\wiki-backup\backup.ps1"),
        (Join-Path $TargetDir ".claude\skills\wiki-backup\backup.ps1"),
        (Join-Path $TargetDir ".agents\skills\wiki-backup\backup.ps1"),
        (Join-Path $TargetDir ".opencode\skills\wiki-backup\backup.sh"),
        (Join-Path $TargetDir ".claude\skills\wiki-backup\backup.sh"),
        (Join-Path $TargetDir ".agents\skills\wiki-backup\backup.sh")
    )
```

- [ ] **Step 7: `Test-ExistingInstallation` 增加 Codex 检测（第 328 行附近）**

oldString:
```
    $ClaudeManaged = Test-ClaudeCodeSupport -TargetDir $TargetDir
    
    if ((Test-Path $WikiDir) -or (Test-Path $OldWikiDir) -or (Test-Path $AgentsFile) -or (Test-Path $SkillsDir) -or $ClaudeManaged) {
```

newString:
```
    $ClaudeManaged = Test-ClaudeCodeSupport -TargetDir $TargetDir
    $CodexManaged = Test-CodexSupport -TargetDir $TargetDir
    
    if ((Test-Path $WikiDir) -or (Test-Path $OldWikiDir) -or (Test-Path $AgentsFile) -or (Test-Path $SkillsDir) -or $ClaudeManaged -or $CodexManaged) {
```

- [ ] **Step 8: `New-WikiIgnoreFile` 按 `ClientMode` 生成默认规则**

oldString:
```
    $DefaultRules = @(".opencode/")
    if ($script:EnableClaudeCode) {
        $DefaultRules += ".claude/"
    }
    $DefaultRules += @(".wiki/", ".wiki/cache/", ".git/", "AGENTS.md")
    if ($script:EnableClaudeCode) {
        $DefaultRules += "CLAUDE.md"
    }
    $DefaultRules += "output/"
```

newString:
```
    $DefaultRules = @(".opencode/")
    if ($script:ClientMode -eq "claude") {
        $DefaultRules += ".claude/"
    }
    if ($script:ClientMode -eq "codex") {
        $DefaultRules += ".agents/"
        $DefaultRules += ".codex/"
    }
    $DefaultRules += @(".wiki/", ".wiki/cache/", ".git/", "AGENTS.md")
    if ($script:ClientMode -eq "claude") {
        $DefaultRules += "CLAUDE.md"
    }
    $DefaultRules += "output/"
```

- [ ] **Step 9: `New-SkillsDirectory` 与 `Update-Skills` 使用 `Get-InactiveSkillsDirs`（复数）**

`New-SkillsDirectory` 开头删除 `$InactiveSkillsDir` 局部变量：

oldString:
```
function New-SkillsDirectory {
    $SkillsDir = Get-ActiveSkillsDir -TargetDir $TargetDir
    $InactiveSkillsDir = Get-InactiveSkillsDir -TargetDir $TargetDir
    $ExistingBackupRoot = Get-ExistingBackupRoot -TargetDir $TargetDir
    New-Item -ItemType Directory -Path $SkillsDir -Force | Out-Null
```

newString:
```
function New-SkillsDirectory {
    $SkillsDir = Get-ActiveSkillsDir -TargetDir $TargetDir
    $ExistingBackupRoot = Get-ExistingBackupRoot -TargetDir $TargetDir
    New-Item -ItemType Directory -Path $SkillsDir -Force | Out-Null
```

`New-SkillsDirectory` 末尾：

oldString:
```
    Remove-ManagedSkillsFromDir -SkillsDir $InactiveSkillsDir

    if (-not [string]::IsNullOrWhiteSpace($ExistingBackupRoot)) {
        Set-BackupRootInScripts -TargetDir $TargetDir -BackupRoot $ExistingBackupRoot
        Write-Info-Message "已保留既有备份根目录: $ExistingBackupRoot"
    }
}

function New-AgentsFile {
```

newString:
```
    $InactiveDirs = Get-InactiveSkillsDirs -TargetDir $TargetDir
    foreach ($InactiveDir in $InactiveDirs) {
        Remove-ManagedSkillsFromDir -SkillsDir $InactiveDir
    }

    if (-not [string]::IsNullOrWhiteSpace($ExistingBackupRoot)) {
        Set-BackupRootInScripts -TargetDir $TargetDir -BackupRoot $ExistingBackupRoot
        Write-Info-Message "已保留既有备份根目录: $ExistingBackupRoot"
    }
}

function New-AgentsFile {
```

`Update-Skills` 开头同样删除 `$InactiveSkillsDir`：

oldString:
```
function Update-Skills {
    param([string]$TargetDir)

    $SkillsDir = Get-ActiveSkillsDir -TargetDir $TargetDir
    $InactiveSkillsDir = Get-InactiveSkillsDir -TargetDir $TargetDir
    $ExistingBackupRoot = Get-ExistingBackupRoot -TargetDir $TargetDir
    New-Item -ItemType Directory -Path $SkillsDir -Force | Out-Null
```

newString:
```
function Update-Skills {
    param([string]$TargetDir)

    $SkillsDir = Get-ActiveSkillsDir -TargetDir $TargetDir
    $ExistingBackupRoot = Get-ExistingBackupRoot -TargetDir $TargetDir
    New-Item -ItemType Directory -Path $SkillsDir -Force | Out-Null
```

`Update-Skills` 末尾：

oldString:
```
    Remove-ManagedSkillsFromDir -SkillsDir $InactiveSkillsDir

    if (-not [string]::IsNullOrWhiteSpace($ExistingBackupRoot)) {
        Set-BackupRootInScripts -TargetDir $TargetDir -BackupRoot $ExistingBackupRoot
        Write-Info-Message "已保留既有备份根目录: $ExistingBackupRoot"
    }
}
```

newString:
```
    $InactiveDirs = Get-InactiveSkillsDirs -TargetDir $TargetDir
    foreach ($InactiveDir in $InactiveDirs) {
        Remove-ManagedSkillsFromDir -SkillsDir $InactiveDir
    }

    if (-not [string]::IsNullOrWhiteSpace($ExistingBackupRoot)) {
        Set-BackupRootInScripts -TargetDir $TargetDir -BackupRoot $ExistingBackupRoot
        Write-Info-Message "已保留既有备份根目录: $ExistingBackupRoot"
    }
}
```

- [ ] **Step 10: 新增 `Write-CodexVisionReader` / `Remove-CodexVisionReader`，重命名 `Sync-ClaudeSupportFiles` → `Sync-ClientSupportFiles`**

oldString:
```
function Remove-ClaudeVisionReader {
    $AgentFile = Join-Path $TargetDir ".claude\agents\vision-reader.md"
    if (-not (Test-Path $AgentFile)) { return }

    $Content = Get-Content $AgentFile -Raw -ErrorAction SilentlyContinue
    if ($Content -and $Content.Contains("LLM-WIKIER:CLAUDE-AGENT-MANAGED")) {
        Remove-Item $AgentFile -Force
        $AgentDir = Split-Path -Parent $AgentFile
        if ((Test-Path $AgentDir) -and -not (Get-ChildItem $AgentDir -Force)) { Remove-Item $AgentDir -Force }
        $ClaudeDir = Join-Path $TargetDir ".claude"
        if ((Test-Path $ClaudeDir) -and -not (Get-ChildItem $ClaudeDir -Force)) { Remove-Item $ClaudeDir -Force }
        Write-Success-Message "已移除 LLM Wikier 托管的 Claude Code vision-reader"
    } else {
        Write-Info-Message "保留用户自定义 Claude Code vision-reader"
    }
}

function Sync-ClaudeSupportFiles {
    if ($script:EnableClaudeCode) {
        Write-ClaudeFile
        Write-ClaudeVisionReader
    } else {
        Remove-ClaudeManagedBlock
        Remove-ClaudeVisionReader
    }
}
```

newString:
```
function Remove-ClaudeVisionReader {
    $AgentFile = Join-Path $TargetDir ".claude\agents\vision-reader.md"
    if (-not (Test-Path $AgentFile)) { return }

    $Content = Get-Content $AgentFile -Raw -ErrorAction SilentlyContinue
    if ($Content -and $Content.Contains("LLM-WIKIER:CLAUDE-AGENT-MANAGED")) {
        Remove-Item $AgentFile -Force
        $AgentDir = Split-Path -Parent $AgentFile
        if ((Test-Path $AgentDir) -and -not (Get-ChildItem $AgentDir -Force)) { Remove-Item $AgentDir -Force }
        $ClaudeDir = Join-Path $TargetDir ".claude"
        if ((Test-Path $ClaudeDir) -and -not (Get-ChildItem $ClaudeDir -Force)) { Remove-Item $ClaudeDir -Force }
        Write-Success-Message "已移除 LLM Wikier 托管的 Claude Code vision-reader"
    } else {
        Write-Info-Message "保留用户自定义 Claude Code vision-reader"
    }
}

function Write-CodexVisionReader {
    $AgentDir = Join-Path $TargetDir ".codex\agents"
    $AgentFile = Join-Path $AgentDir "vision-reader.toml"

    if (Test-Path $AgentFile) {
        $Existing = Get-Content $AgentFile -Raw -ErrorAction SilentlyContinue
        if ($Existing -and -not ($Existing.Contains($script:CodexAgentManaged))) {
            Write-Info-Message "保留用户自定义 Codex vision-reader: $AgentFile"
            return
        }
    }

    New-Item -ItemType Directory -Path $AgentDir -Force | Out-Null

    $Content = @'
# LLM-WIKIER:CODEX-AGENT-MANAGED
name = "vision-reader"
description = "读取图片、图表、截图、幻灯片、PDF 和文档排版等视觉元素,转化为文字描述"
sandbox_mode = "read-only"

developer_instructions = """
你是一个视觉内容读取器。你的职责是读取文件中的视觉元素(图片、图表、截图、幻灯片、页面排版等),并将视觉内容转化为文字描述。

## 核心职责
- 只描述视觉元素(图片、图表、照片、插图、截图、幻灯片视觉内容、排版布局等)
- 不要重复已经由主 agent 处理的纯文本内容
- **兜底规则**:如果发现文档中文本提取明显不完整(如幻灯片缺失文字、表格数据丢失、图表中的数据标签等),请一并补充关键文本信息

## 输出格式
对每个视觉元素:

### [图片/图表/截图 序号]
**类型**: [图表/照片/截图/插图/排版]
**描述**: [视觉内容的文字描述]
**关键信息**: [图表数据、照片中的人物/场景、截图中的UI元素、幻灯片主题等]

主 agent 会通过文件路径告知你需要读取的文件,请直接读取并返回描述。
"""
'@

    Set-Content -Path $AgentFile -Value $Content -Encoding UTF8
    Write-Success-Message "已配置 Codex vision-reader: $AgentFile"
}

function Remove-CodexVisionReader {
    $AgentFile = Join-Path $TargetDir ".codex\agents\vision-reader.toml"
    if (-not (Test-Path $AgentFile)) { return }

    $Content = Get-Content $AgentFile -Raw -ErrorAction SilentlyContinue
    if ($Content -and $Content.Contains($script:CodexAgentManaged)) {
        Remove-Item $AgentFile -Force
        $AgentDir = Split-Path -Parent $AgentFile
        if ((Test-Path $AgentDir) -and -not (Get-ChildItem $AgentDir -Force)) { Remove-Item $AgentDir -Force }
        $CodexDir = Join-Path $TargetDir ".codex"
        if ((Test-Path $CodexDir) -and -not (Get-ChildItem $CodexDir -Force)) { Remove-Item $CodexDir -Force }
        Write-Success-Message "已移除 LLM Wikier 托管的 Codex vision-reader"
    } else {
        Write-Info-Message "保留用户自定义 Codex vision-reader"
    }
}

function Sync-ClientSupportFiles {
    switch ($script:ClientMode) {
        "claude" {
            Write-ClaudeFile
            Write-ClaudeVisionReader
            Remove-CodexVisionReader
        }
        "codex" {
            Write-CodexVisionReader
            Remove-ClaudeManagedBlock
            Remove-ClaudeVisionReader
        }
        default {
            Remove-ClaudeManagedBlock
            Remove-ClaudeVisionReader
            Remove-CodexVisionReader
        }
    }
}
```

> 注意：Codex TOML here-string 中为避免 PowerShell 解析问题，TOML 字符串内全角中文标点保留，半角标点用 ASCII（逗号、括号）以确保 TOML 合法。

- [ ] **Step 11: `Update-Install` 用 `Get-CurrentMode` 替换 `Test-ClaudeCodeSupport`，调用 `Sync-ClientSupportFiles`（第 1086-1124 行附近）**

oldString:
```
    $HadClaude = Test-ClaudeCodeSupport -TargetDir $TargetDir
    Select-ClientSupport -TargetDir $TargetDir -IsUpdate $true
    $ModeChanged = ($HadClaude -ne $script:EnableClaudeCode)

    Write-Host ""
    Write-Info-Message "更新安装将执行以下操作："
    Write-Info-Message "  (1) 更新 skills — 从本仓库同步最新 skill 文件"
    Write-Info-Message "  (2) 更新 AGENTS.md — 从模板更新，保留您的用户偏好和自定义配置"
    Write-Info-Message "  (3) 更新 .wiki_ignore — 从模板更新，保留用户自定义规则"
    Write-Info-Message "  (4) 同步客户端配置 — 根据选择创建或移除 Claude Code 托管文件"
    Write-Info-Message "  (5) 配置备份根目录"
    Write-Host ""

    if ($ModeChanged) {
        Write-Info-Message "客户端模式已变化，自动同步 skills 目录"
        Update-Skills -TargetDir $TargetDir
    } elseif (Invoke-PromptUser "Step (1/5): 是否更新 skills？（将覆盖现有 skill 文件）") {
        Update-Skills -TargetDir $TargetDir
    } else {
        Write-Info-Message "已跳过更新 skills"
    }

    if ($ModeChanged) {
        Write-Info-Message "客户端模式已变化，自动更新 AGENTS.md 以修正备份路径"
        Update-AgentsFile -TargetDir $TargetDir
    } elseif (Invoke-PromptUser "Step (2/5): 是否更新 AGENTS.md？（模板章节将刷新，用户偏好和自定义配置章节将保留）") {
        Update-AgentsFile -TargetDir $TargetDir
    } else {
        Write-Info-Message "已跳过更新 AGENTS.md"
    }

    if (Invoke-PromptUser "Step (3/5): 是否更新 .wiki_ignore？（默认规则将刷新，用户自定义规则将保留）") {
        Merge-WikiIgnore -TargetDir $TargetDir
    } else {
        Write-Info-Message "已跳过更新 .wiki_ignore"
    }

    Write-Info-Message "Step (4/5): 同步客户端配置"
    Sync-ClaudeSupportFiles
```

newString:
```
    $PreviousMode = Get-CurrentMode -TargetDir $TargetDir
    Select-ClientSupport -TargetDir $TargetDir -IsUpdate $true
    $ModeChanged = ($PreviousMode -ne $script:ClientMode)

    Write-Host ""
    Write-Info-Message "更新安装将执行以下操作："
    Write-Info-Message "  (1) 更新 skills — 从本仓库同步最新 skill 文件"
    Write-Info-Message "  (2) 更新 AGENTS.md — 从模板更新，保留您的用户偏好和自定义配置"
    Write-Info-Message "  (3) 更新 .wiki_ignore — 从模板更新，保留用户自定义规则"
    Write-Info-Message "  (4) 同步客户端配置 — 根据选择创建或移除客户端托管文件"
    Write-Info-Message "  (5) 配置备份根目录"
    Write-Host ""

    if ($ModeChanged) {
        Write-Info-Message "客户端模式已变化（$PreviousMode → $($script:ClientMode)），自动同步 skills 目录"
        Update-Skills -TargetDir $TargetDir
    } elseif (Invoke-PromptUser "Step (1/5): 是否更新 skills？（将覆盖现有 skill 文件）") {
        Update-Skills -TargetDir $TargetDir
    } else {
        Write-Info-Message "已跳过更新 skills"
    }

    if ($ModeChanged) {
        Write-Info-Message "客户端模式已变化，自动更新 AGENTS.md 以修正备份路径"
        Update-AgentsFile -TargetDir $TargetDir
    } elseif (Invoke-PromptUser "Step (2/5): 是否更新 AGENTS.md？（模板章节将刷新，用户偏好和自定义配置章节将保留）") {
        Update-AgentsFile -TargetDir $TargetDir
    } else {
        Write-Info-Message "已跳过更新 AGENTS.md"
    }

    if (Invoke-PromptUser "Step (3/5): 是否更新 .wiki_ignore？（默认规则将刷新，用户自定义规则将保留）") {
        Merge-WikiIgnore -TargetDir $TargetDir
    } else {
        Write-Info-Message "已跳过更新 .wiki_ignore"
    }

    Write-Info-Message "Step (4/5): 同步客户端配置"
    Sync-ClientSupportFiles
```

- [ ] **Step 12: `Write-CompletionMessage` 三态启动提示**

oldString:
```
    Write-Host "2. 启动 OpenCode："
    Write-Host "   opencode"
    if ($script:EnableClaudeCode) {
        Write-Host "   或启动 Claude Code："
        Write-Host "   claude"
    }
    Write-Host ""
    Write-Host "3. 如果知识库已有文件，运行批量初始化："
    Write-Host "   /wiki-init"
    Write-Host ""
    Write-Host "4. 或者添加新文件后运行增量处理："
    Write-Host "   /wiki-ingest"
```

newString:
```
    Write-Host "2. 启动 OpenCode："
    Write-Host "   opencode"
    switch ($script:ClientMode) {
        "claude" {
            Write-Host "   或启动 Claude Code："
            Write-Host "   claude"
        }
        "codex" {
            Write-Host "   或启动 Codex："
            Write-Host "   codex"
        }
    }
    Write-Host ""
    Write-Host "3. 如果知识库已有文件，运行批量初始化："
    Write-Host "   OpenCode: /wiki-init"
    switch ($script:ClientMode) {
        "codex" { Write-Host "   Codex: `$wiki-init 或 /skills 选择 wiki-init" }
    }
    Write-Host ""
    Write-Host "4. 或者添加新文件后运行增量处理："
    Write-Host "   OpenCode: /wiki-ingest"
    switch ($script:ClientMode) {
        "codex" { Write-Host "   Codex: `$wiki-ingest 或 /skills 选择 wiki-ingest" }
    }
```

- [ ] **Step 13: `Invoke-VisionReaderConfig` 区分 Codex 模式提示**

oldString:
```
function Invoke-VisionReaderConfig {
    param([string]$TargetDir)

    if ($Force) {
        Write-Info-Message "强制安装模式，跳过 vision-reader 交互配置"
        Write-Info-Message "稍后可手动运行: .\config_vision_reader.ps1 `"$TargetDir`""
        return
    }

    Write-Host ""
    if (-not (Invoke-PromptUser "是否配置 vision-reader subagent？（用于读取图片/幻灯片/PDF 等视觉内容）")) {
        Write-Info-Message "已跳过 vision-reader 配置"
        return
    }

    $ConfigScript = Join-Path $ScriptDir "config_vision_reader.ps1"
    if (-not (Test-Path $ConfigScript)) {
        Write-Error-Message "找不到配置脚本: $ConfigScript"
        return
    }

    Write-Host ""
    Write-Info-Message "正在配置 vision-reader..."
    & $ConfigScript -TargetDir $TargetDir -Force
}
```

newString:
```
function Invoke-VisionReaderConfig {
    param([string]$TargetDir)

    if ($Force) {
        Write-Info-Message "强制安装模式，跳过 vision-reader 交互配置"
        Write-Info-Message "稍后可手动运行: .\config_vision_reader.ps1 `"$TargetDir`""
        if ($script:ClientMode -eq "codex") {
            Write-Info-Message "Codex 版 vision-reader 已由安装器预生成（.codex\agents\vision-reader.toml）"
        }
        return
    }

    Write-Host ""
    if ($script:ClientMode -eq "codex") {
        Write-Info-Message "Codex 版 vision-reader 已由安装器预生成（.codex\agents\vision-reader.toml），不指定模型由 Codex 自动选择"
    }
    if (-not (Invoke-PromptUser "是否配置 OpenCode 版 vision-reader subagent？（用于在 OpenCode 中读取图片/幻灯片/PDF 等视觉内容）")) {
        Write-Info-Message "已跳过 OpenCode 版 vision-reader 配置"
        return
    }

    $ConfigScript = Join-Path $ScriptDir "config_vision_reader.ps1"
    if (-not (Test-Path $ConfigScript)) {
        Write-Error-Message "找不到配置脚本: $ConfigScript"
        return
    }

    Write-Host ""
    Write-Info-Message "正在配置 OpenCode 版 vision-reader..."
    & $ConfigScript -TargetDir $TargetDir -Force
}
```

- [ ] **Step 14: 主流程末尾 `Sync-ClaudeSupportFiles` → `Sync-ClientSupportFiles`**

oldString:
```
    New-SkillsDirectory
    New-AgentsFile
    Sync-ClaudeSupportFiles
```

newString:
```
    New-SkillsDirectory
    New-AgentsFile
    Sync-ClientSupportFiles
```

- [ ] **Step 15: 验证**

PowerShell 语法人工审查（无 `bash -n` 等价命令；可在 PowerShell 中运行 `powershell -NoProfile -Command "& { . ./install.ps1 -Help }" 2>&1 | Out-String"` 测试解析；或直接 `powershell -NoProfile -File install.ps1 -Help`）。

Run: `grep -n "EnableClaudeCode" install.ps1`
Expected: 无输出（变量已全部替换）

Run: `grep -n "Sync-ClaudeSupportFiles\|Get-InactiveSkillsDir[^s]" install.ps1`
Expected: 无输出（旧函数名已全部替换）

- [ ] **Step 16: Commit**

```bash
git add install.ps1
git commit -m "feat(install): add codex client mode to install.ps1"
```

---

### Task 8: install.ps1 — 内置 fallback AGENTS.md 内容补丁（两处）

**Files:**
- Modify: `install.ps1` 中 `New-AgentsFile` 的 fallback（约 502-614 行）与 `Update-AgentsFile` 的 fallback（约 980-1066 行）

**Interfaces:**
- Consumes: Task 4 模板内容补丁（保持一致）
- Produces: install.ps1 两份内置 fallback 与模板同步

- [ ] **Step 1: 两份 fallback 的 vision-reader 配置路径说明（各一处，共 2 处）**

两份 fallback（`New-AgentsFile` 约 558 行；`Update-AgentsFile` 约 1029 行）均有此段。内容相同，可用 `replaceAll: true` 一次替换两处。

oldString:
```
如当前客户端未配置 `vision-reader`，Agent 跳过视觉处理。OpenCode 配置路径为 `.opencode/agents/vision-reader.md`，Claude Code 配置路径为 `.claude/agents/vision-reader.md`。

OpenCode 配置方式：`.\config_vision_reader.ps1 <知识库路径>`。启用 Claude Code 支持时，安装器会生成 Claude Code 版 `vision-reader`。
```

newString:
```
如当前客户端未配置 `vision-reader`，Agent 跳过视觉处理。OpenCode 配置路径为 `.opencode/agents/vision-reader.md`，Claude Code 配置路径为 `.claude/agents/vision-reader.md`，Codex 配置路径为 `.codex/agents/vision-reader.toml`。

OpenCode 配置方式：`.\config_vision_reader.ps1 <知识库路径>`。启用 Claude Code 支持时安装器生成 Claude Code 版 `vision-reader`；启用 Codex 支持时安装器生成 Codex 版 `vision-reader`（不指定 model，由 Codex 自动选择）。
```

- [ ] **Step 2: 两份 fallback 的默认排除项（各一处，共 2 处）**

oldString（与 Task 6 Step 2 相同）：
```
### 默认排除项
- `.opencode/` — skills 配置目录
- `.claude/` — Claude Code 配置目录（仅启用 Claude Code 支持时）
- `.wiki/` — wiki 内容本身
- `.wiki/cache/` — 链接文档缓存（不计入备份）
- `.git/` — 版本控制
- `AGENTS.md` — 知识库配置文件
- `CLAUDE.md` — Claude Code 入口文件（仅启用 Claude Code 支持时）
- `output/` — 用户自产文件（展示文档、报告等），不会被作为源文件处理
```

newString（与 Task 6 Step 2 相同，含 `.agents/`、`.codex/` 两行）：用 `replaceAll: true` 一次替换两处。

- [ ] **Step 3: 验证**

Run: `grep -c "\.codex/agents/vision-reader\.toml" install.ps1`
Expected: 4（两份 fallback 各 2 处）

Run: `grep -c "\.agents/ — 共享 skills" install.ps1`
Expected: 2

- [ ] **Step 4: Commit**

```bash
git add install.ps1
git commit -m "docs(install): sync ps1 fallback AGENTS.md content with codex mode"
```

---

### Task 9: backup.sh / backup.ps1 — 错误提示路径列表补 `.agents/skills/wiki-backup/`

**Files:**
- Modify: `skills/wiki-backup/backup.sh:47`
- Modify: `skills/wiki-backup/backup.ps1:35`

**Interfaces:**
- Produces: 备份脚本错误提示列举所有有效安装路径（含 `.agents/skills/wiki-backup/`）

- [ ] **Step 1: backup.sh 错误提示路径列表**

oldString:
```
    echo "请使用 --root 参数显式指定备份根目录，或确认脚本位于 .opencode/skills/wiki-backup/ 或 .claude/skills/wiki-backup/ 下" >&2
```

newString:
```
    echo "请使用 --root 参数显式指定备份根目录，或确认脚本位于 .opencode/skills/wiki-backup/、.claude/skills/wiki-backup/ 或 .agents/skills/wiki-backup/ 下" >&2
```

- [ ] **Step 2: backup.ps1 错误提示路径列表**

oldString:
```
    Write-Host "请使用 -Root 参数显式指定备份根目录，或确认脚本位于 .opencode\skills\wiki-backup\ 或 .claude\skills\wiki-backup\ 下"
```

newString:
```
    Write-Host "请使用 -Root 参数显式指定备份根目录，或确认脚本位于 .opencode\skills\wiki-backup\、.claude\skills\wiki-backup\ 或 .agents\skills\wiki-backup\ 下"
```

- [ ] **Step 3: 验证**

Run: `bash -n skills/wiki-backup/backup.sh`
Expected: 无输出

人工审查 backup.ps1 语法。

- [ ] **Step 4: Commit**

```bash
git add skills/wiki-backup/backup.sh skills/wiki-backup/backup.ps1
git commit -m "docs(backup): add .agents/skills path to error messages"
```

---

### Task 10: config_vision_reader.{sh,ps1} — 完成提示文案补 Codex 说明

**Files:**
- Modify: `config_vision_reader.sh:386-387`（完成提示最后一句后补一段说明）
- Modify: `config_vision_reader.ps1:376-377`

**Interfaces:**
- Produces: 脚本完成提示说明 Codex 版 vision-reader 由安装器托管，本脚本仅配置 OpenCode 版

- [ ] **Step 1: config_vision_reader.sh 完成提示补一段**

oldString:
```
    echo "配置完成后，使用知识库时 Agent 会自动在遇到视觉内容时调用 vision-reader。"
    echo ""
}
```

newString:
```
    echo "配置完成后，使用知识库时 Agent 会自动在遇到视觉内容时调用 vision-reader。"
    echo ""
    echo "注：本脚本仅配置 OpenCode 版 vision-reader。Claude Code 版（.claude/agents/vision-reader.md）与 Codex 版（.codex/agents/vision-reader.toml）由安装器在启用对应客户端支持时自动生成。"
    echo ""
}
```

- [ ] **Step 2: config_vision_reader.ps1 完成提示补一段**

oldString:
```
    Write-Host "配置完成后，使用知识库时 Agent 会自动在遇到视觉内容时调用 vision-reader。"
    Write-Host ""
}
```

newString:
```
    Write-Host "配置完成后，使用知识库时 Agent 会自动在遇到视觉内容时调用 vision-reader。"
    Write-Host ""
    Write-Host "注：本脚本仅配置 OpenCode 版 vision-reader。Claude Code 版（.claude/agents/vision-reader.md）与 Codex 版（.codex/agents/vision-reader.toml）由安装器在启用对应客户端支持时自动生成。"
    Write-Host ""
}
```

- [ ] **Step 3: 验证**

Run: `bash -n config_vision_reader.sh`
Expected: 无输出

- [ ] **Step 4: Commit**

```bash
git add config_vision_reader.sh config_vision_reader.ps1
git commit -m "docs(config): note codex vision-reader is installer-managed"
```

---

### Task 11: README.md — 补 Codex 模式文档

**Files:**
- Modify: `README.md`（多处章节）

**Interfaces:**
- Produces: README 客户端模式表、目录结构图、切换说明、视觉/备份/排除表、Codex 调用方式完整

- [ ] **Step 1: 第 3 行项目简介加 Codex**

oldString:
```
一个面向 OpenCode 的个人知识库工具包，用于构建和维护 LLM 驱动的 Wiki 知识库。安装时可选启用 Claude Code 支持，同一个个人知识库可以被 OpenCode 和 Claude Code 混合使用。
```

newString:
```
一个以 OpenCode 为主的个人知识库工具包，用于构建和维护 LLM 驱动的 Wiki 知识库。安装时可选启用 Claude Code 或 Codex 支持（二者互斥），同一个个人知识库可以被 OpenCode 与 Claude Code 或 OpenCode 与 Codex 混合使用。
```

- [ ] **Step 2: 第 39-41 行前置要求加 Codex**

oldString:
```
- [OpenCode](https://opencode.ai) 已安装
- 如需混合使用：[Claude Code](https://docs.anthropic.com/en/docs/claude-code) 已安装
- 已有一个知识库文件夹（可包含多层子目录和现有文件）
```

newString:
```
- [OpenCode](https://opencode.ai) 已安装
- 如需混合使用：[Claude Code](https://docs.anthropic.com/en/docs/claude-code) 或 [OpenAI Codex CLI](https://developers.openai.com/codex) 已安装
- 已有一个知识库文件夹（可包含多层子目录和现有文件）
```

- [ ] **Step 3: 第 57 行 Mac/Linux 安装说明改为三选一**

oldString:
```
安装过程中会询问是否需要支持除 OpenCode 之外的其它客户端。当前可选客户端为 Claude Code，默认不启用，保持 OpenCode-only 模式。
```

newString:
```
安装过程中会询问是否需要支持除 OpenCode 之外的其它客户端。当前可选 Claude Code 或 Codex（二者互斥），默认不启用，保持 OpenCode-only 模式。
```

- [ ] **Step 4: 第 70 行 PowerShell 安装说明**

oldString:
```
PowerShell 安装器与 Mac/Linux 安装器行为一致，也会在安装或更新时询问是否启用 Claude Code 支持。
```

newString:
```
PowerShell 安装器与 Mac/Linux 安装器行为一致，也会在安装或更新时询问是否启用 Claude Code 或 Codex 支持。
```

- [ ] **Step 5: 第 72-79 行客户端模式表加 Codex 行**

oldString:
```
### 客户端模式

| 模式 | 选择 | skills 安装位置 | 说明 |
|------|------|----------------|------| 
| OpenCode-only | 不启用其它客户端 | `.opencode/skills/wiki-*` | 当前默认方案，主要服务 OpenCode |
| OpenCode + Claude Code | 启用 Claude Code | `.claude/skills/wiki-*` | Claude Code 原生读取 `.claude/skills`；OpenCode 通过 Claude-compatible skill discovery 读取同一份 skills |

混合模式不会复制两份 skills，也不会创建软链接，避免 OpenCode 同时发现 `.opencode/skills` 和 `.claude/skills` 中的同名 skill。
```

newString:
```
### 客户端模式

| 模式 | 选择 | skills 安装位置 | 说明 |
|------|------|----------------|------| 
| OpenCode-only | 不启用其它客户端 | `.opencode/skills/wiki-*` | 当前默认方案，主要服务 OpenCode |
| OpenCode + Claude Code | 启用 Claude Code | `.claude/skills/wiki-*` | Claude Code 原生读取 `.claude/skills`；OpenCode 通过 Claude-compatible skill discovery 读取同一份 skills |
| OpenCode + Codex | 启用 Codex | `.agents/skills/wiki-*` | Codex 原生读取 `.agents/skills`（open agent skills 标准）；OpenCode 通过 agent-compatible skill discovery 读取同一份 skills |

Claude Code 和 Codex 互斥：知识库启用 Codex 时关闭 Claude Code 支持，但 OpenCode 始终保留。混合模式不会复制两份 skills，也不会创建软链接，避免 OpenCode 同时发现 `.opencode/skills`、`.claude/skills`、`.agents/skills` 中的同名 skill。
```

- [ ] **Step 6: 第 81-89 行更新安装与模式切换扩展为三模式双向切换**

oldString:
```
### 更新安装与模式切换

对已安装的知识库再次运行安装脚本会进入更新安装模式：

- 已支持 Claude Code 的知识库，默认继续支持 Claude Code
- 未支持 Claude Code 的知识库，默认保持 OpenCode-only
- 从 OpenCode-only 切换到混合模式时，LLM Wikier 管理的 `wiki-*` skills 会从 `.opencode/skills` 切换到 `.claude/skills`
- 从混合模式切回 OpenCode-only 时，LLM Wikier 管理的 `wiki-*` skills 会回到 `.opencode/skills`，并移除 LLM Wikier 托管的 Claude Code 配置
- 安装器只移除 LLM Wikier 管理的 `.claude/skills/wiki-*`、托管 `CLAUDE.md` 区块和托管 `vision-reader`，不会递归删除用户自己的 `.claude/` 内容
```

newString:
```
### 更新安装与模式切换

对已安装的知识库再次运行安装脚本会进入更新安装模式：

- 已支持 Claude Code 的知识库，默认继续支持 Claude Code
- 已支持 Codex 的知识库，默认继续支持 Codex
- 未支持其它客户端的知识库，默认保持 OpenCode-only
- 任意两种模式间可双向切换；切换时 LLM Wikier 管理的 `wiki-*` skills 会从旧目录迁移到新目录
- 切换到 OpenCode-only 时，移除 LLM Wikier 托管的 Claude Code 和 Codex 配置
- Claude ↔ Codex 切换：skills 在 `.claude/skills` 与 `.agents/skills` 间迁移，同时清理对应托管文件（CLAUDE.md 区块 / `.claude/agents/vision-reader.md` ↔ `.codex/agents/vision-reader.toml`）
- 安装器只移除 LLM Wikier 管理的 `.claude/`、`.codex/`、`.agents/` 中的托管文件，不会递归删除用户自定义内容
```

- [ ] **Step 7: 在混合模式目录结构（第 122-151 行）之后追加"OpenCode + Codex 模式"目录结构**

定位锚点为混合模式目录树结束的 ` ``` ` 后紧跟 `## 使用方法`：

oldString:
```
└── [原有的 raw sources]         # 保持不变
```

## 使用方法
```

newString:
```
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
├── .agents/skills/              # 唯一 LLM Wikier skills 目录（OpenCode 与 Codex 共享）
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
```

> 注意：上面 oldString 中的`└── [原有的 raw sources]         # 保持不变`在 README 中可能出现两次（OpenCode-only 模式图末尾 + 混合模式图末尾）。需用 `replaceAll: false` 并提供更长上下文唯一定位混合模式图末尾——即在它后面紧跟空行 + `## 使用方法`。上面 oldString 已包含 `## 使用方法` 作为锚点，应能唯一定位。

- [ ] **Step 8: 第 241 行视觉配置说明加 Codex**

oldString:
```
混合模式下，安装器会自动生成 Claude Code 版 `.claude/agents/vision-reader.md`。如果也希望 OpenCode 使用专门的视觉 subagent，仍可运行上述 `config_vision_reader` 脚本，它会生成 `.opencode/agents/vision-reader.md`。
```

newString:
```
混合模式下（Claude Code），安装器会自动生成 Claude Code 版 `.claude/agents/vision-reader.md`。Codex 模式下，安装器会自动生成 Codex 版 `.codex/agents/vision-reader.toml`（不指定 `model`，由 Codex 自动选择；`sandbox_mode = "read-only"`；Codex 仅在被显式要求时 spawn subagent）。如果也希望 OpenCode 使用专门的视觉 subagent，仍可运行上述 `config_vision_reader` 脚本，它会生成 `.opencode/agents/vision-reader.md`。
```

- [ ] **Step 9: 第 269-277 行文件排除规则表加 Codex 列**

oldString:
```
| 排除项 | 说明 |
|--------|------|
| `.opencode/` | Skills 配置目录 |
| `.claude/` | Claude Code 配置目录（启用 Claude Code 支持时） |
| `.wiki/` | Wiki 内容本身 |
| `.git/` | 版本控制 |
| `AGENTS.md` | 知识库配置文件 |
| `CLAUDE.md` | Claude Code 入口文件（启用 Claude Code 支持时） |
| `output/` | 用户自产文件（ppt、报告等），不会被 ingest |
```

newString:
```
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
```

- [ ] **Step 10: 第 289-294 行自动备份表加 Codex 行 + 修订备份范围说明**

oldString:
```
| 模式 | Mac/Linux 自动备份脚本 | Windows 自动备份脚本 |
|------|----------------------|--------------------|
| OpenCode-only | `bash .opencode/skills/wiki-backup/backup.sh --auto` | `powershell -NoProfile -ExecutionPolicy Bypass -File .opencode\skills\wiki-backup\backup.ps1 -Auto` |
| OpenCode + Claude Code | `bash .claude/skills/wiki-backup/backup.sh --auto` | `powershell -NoProfile -ExecutionPolicy Bypass -File .claude\skills\wiki-backup\backup.ps1 -Auto` |

备份范围包括 `.wiki/`、`AGENTS.md`、`.wiki_ignore`，混合模式下还会在存在时包含 `CLAUDE.md`。不会备份整个 `.opencode/` 或 `.claude/`，这些工具配置可通过重新运行安装器恢复，且可能包含用户自定义配置。
```

newString:
```
| 模式 | Mac/Linux 自动备份脚本 | Windows 自动备份脚本 |
|------|----------------------|--------------------|
| OpenCode-only | `bash .opencode/skills/wiki-backup/backup.sh --auto` | `powershell -NoProfile -ExecutionPolicy Bypass -File .opencode\skills\wiki-backup\backup.ps1 -Auto` |
| OpenCode + Claude Code | `bash .claude/skills/wiki-backup/backup.sh --auto` | `powershell -NoProfile -ExecutionPolicy Bypass -File .claude\skills\wiki-backup\backup.ps1 -Auto` |
| OpenCode + Codex | `bash .agents/skills/wiki-backup/backup.sh --auto` | `powershell -NoProfile -ExecutionPolicy Bypass -File .agents\skills\wiki-backup\backup.ps1 -Auto` |

备份范围包括 `.wiki/`、`AGENTS.md`、`.wiki_ignore`，Claude 模式下还会在存在时包含 `CLAUDE.md`。Codex 模式无托管入口文件，备份范围不包含 `CLAUDE.md`。不会备份整个 `.opencode/`、`.claude/`、`.agents/` 或 `.codex/`，这些工具配置可通过重新运行安装器恢复，且可能包含用户自定义配置。
```

- [ ] **Step 11: 第 165-169 行使用方法加 Codex 调用方式**

oldString:
```
完成配置后，在 OpenCode 或 Claude Code 中运行批量构建：

```
/wiki-init
```

这将处理所有 raw sources 并构建初始 wiki。
```

newString:
```
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
```

- [ ] **Step 12: 验证**

Run: `grep -c "\.agents/skills\|\.codex/agents/vision-reader" README.md`
Expected: ≥ 4（目录结构图、客户端模式表说明、视觉配置、自动备份表）

人工审查 README 渲染（代码块闭合正确、目录树缩进正确）。

- [ ] **Step 13: Commit**

```bash
git add README.md
git commit -m "docs(readme): add codex client mode documentation"
```

---

### Task 12: AGENTS.md（仓库根）— skill 格式说明与安装脚本职责补 Codex

**Files:**
- Modify: `AGENTS.md`（仓库根）

**Interfaces:**
- Produces: 仓库根 AGENTS.md 的 SKILL.md 格式示例、架构、安装脚本职责、vision-reader 章节、常见陷阱完整覆盖 Codex

- [ ] **Step 1: 第 5 行项目定位加 Codex**

oldString:
```
这是一个以 OpenCode 为主的 Agent Skills 工具包仓库，提供安装脚本将技能安装到任意**已有**的知识库目录。安装器可选启用 Claude Code 支持，同一个个人知识库可以被 OpenCode 和 Claude Code 混合使用。
```

newString:
```
这是一个以 OpenCode 为主的 Agent Skills 工具包仓库，提供安装脚本将技能安装到任意**已有的**知识库目录。安装器可选启用 Claude Code 或 Codex 支持（二者互斥），同一个个人知识库可以被 OpenCode 与 Claude Code 或 OpenCode 与 Codex 混合使用。
```

- [ ] **Step 2: 第 21 行核心架构注释加 Codex 模式**

oldString:
```
skills/                     ← 8 个 Agent Skills 定义（OpenCode-only 安装到 .opencode/skills/；混合模式安装到 .claude/skills/）
```

newString:
```
skills/                     ← 8 个 Agent Skills 定义（OpenCode-only 安装到 .opencode/skills/；+Claude 模式安装到 .claude/skills/；+Codex 模式安装到 .agents/skills/）
```

- [ ] **Step 3: 第 48 行 SKILL.md 格式示例 compatibility 加 codex**

oldString:
```
```yaml
---
name: wiki-xxx
description: 中文功能描述（1-1024 字符）
license: MIT
compatibility: opencode, claude-code
---
```
```

newString:
```
```yaml
---
name: wiki-xxx
description: 中文功能描述（1-1024 字符）
license: MIT
compatibility: opencode, claude-code, codex
---
```
```

- [ ] **Step 4: 第 61-65 行安装脚本职责第 4-8 步扩展为三模式**

oldString:
```
4. 询问是否支持除 OpenCode 之外的其它客户端（当前仅 Claude Code；默认不启用）
5. OpenCode-only 模式复制 `skills/*` → 目标目录 `.opencode/skills/`
6. OpenCode + Claude Code 混合模式复制 `skills/*` → 目标目录 `.claude/skills/`，并生成托管 `CLAUDE.md` 与 `.claude/agents/vision-reader.md`
7. 从 `templates/AGENTS.md.tmpl` 生成目标 `AGENTS.md`，其中 `__WIKI_BACKUP_AUTO_COMMAND__` 必须替换为当前模式的 backup 脚本路径
8. 输出完成提示
```

newString:
```
4. 询问是否支持除 OpenCode 之外的其它客户端（可选 Claude Code 或 Codex；二者互斥；默认不启用）
5. OpenCode-only 模式复制 `skills/*` → 目标目录 `.opencode/skills/`
6. OpenCode + Claude Code 混合模式复制 `skills/*` → 目标目录 `.claude/skills/`，并生成托管 `CLAUDE.md` 与 `.claude/agents/vision-reader.md`
7. OpenCode + Codex 混合模式复制 `skills/*` → 目标目录 `.agents/skills/`（OpenCode 与 Codex 均原生扫描此路径），并生成 `.codex/agents/vision-reader.toml`（无托管入口文件——Codex 原生读 AGENTS.md）
8. 从 `templates/AGENTS.md.tmpl` 生成目标 `AGENTS.md`，其中 `__WIKI_BACKUP_AUTO_COMMAND__` 必须替换为当前模式的 backup 脚本路径
9. 输出完成提示
```

- [ ] **Step 5: 第 67-70 行更新安装模式切换扩展为三模式双向切换**

oldString:
```
更新安装时必须支持双向模式切换：
- OpenCode-only → 混合模式：安装 `.claude/skills/wiki-*`，移除 LLM Wikier 管理的 `.opencode/skills/wiki-*`
- 混合模式 → OpenCode-only：安装 `.opencode/skills/wiki-*`，移除 LLM Wikier 管理的 `.claude/skills/wiki-*`、托管 `CLAUDE.md` 区块和托管 `.claude/agents/vision-reader.md`
- 只删除 LLM Wikier 管理的 Claude Code 文件，不递归删除用户自定义 `.claude/` 内容
```

newString:
```
更新安装时必须支持三模式间双向切换：
- OpenCode-only → +Claude：安装 `.claude/skills/wiki-*`，移除 LLM Wikier 管理的 `.opencode/skills/wiki-*`
- OpenCode-only → +Codex：安装 `.agents/skills/wiki-*`，移除 LLM Wikier 管理的 `.opencode/skills/wiki-*`
- +Claude → OpenCode-only：安装 `.opencode/skills/wiki-*`，移除 LLM Wikier 管理的 `.claude/skills/wiki-*`、托管 `CLAUDE.md` 区块和托管 `.claude/agents/vision-reader.md`
- +Codex → OpenCode-only：安装 `.opencode/skills/wiki-*`，移除 LLM Wikier 管理的 `.agents/skills/wiki-*` 和托管 `.codex/agents/vision-reader.toml`
- +Claude ↔ +Codex：skills 在 `.claude/skills` 与 `.agents/skills` 间迁移，同时清理对应托管文件（`CLAUDE.md` 区块 + `.claude/agents/vision-reader.md` ↔ `.codex/agents/vision-reader.toml`）
- 只删除 LLM Wikier 管理的 Claude Code / Codex 文件，不递归删除用户自定义 `.claude/`、`.codex/`、`.agents/` 内容
```

- [ ] **Step 6: 第 76 行 vision-reader 章节加 Codex**

oldString:
```
独立于 install.sh/ps1 的配置脚本，用于在目标 KB 的 `.opencode/agents/` 下生成 OpenCode 版 `vision-reader.md`。混合模式下 Claude Code 版 `.claude/agents/vision-reader.md` 由安装器生成，默认 `model: inherit`。
```

newString:
```
独立于 install.sh/ps1 的配置脚本，用于在目标 KB 的 `.opencode/agents/` 下生成 OpenCode 版 `vision-reader.md`。+Claude 模式下 Claude Code 版 `.claude/agents/vision-reader.md` 由安装器生成，默认 `model: inherit`。+Codex 模式下 Codex 版 `.codex/agents/vision-reader.toml` 由安装器生成，不指定 `model`（由 Codex 自动选择），`sandbox_mode = "read-only"`，格式为 TOML（必填 `name`/`description`/`developer_instructions`）。
```

- [ ] **Step 7: 第 129 行常见陷阱 — skill 与 subagent 路径补 Codex + 新增 Codex 专属陷阱**

oldString:
```
- **不要混淆 skill 和 subagent**：`skills/` 下的 SKILL.md 是给主 agent 加载的工作流指令；`vision-reader` 是客户端专属 subagent，OpenCode 路径为 `.opencode/agents/`，Claude Code 路径为 `.claude/agents/`
```

newString:
```
- **不要混淆 skill 和 subagent**：`skills/` 下的 SKILL.md 是给主 agent 加载的工作流指令；`vision-reader` 是客户端专属 subagent，OpenCode 路径为 `.opencode/agents/`，Claude Code 路径为 `.claude/agents/`，Codex 路径为 `.codex/agents/`（TOML 格式）
- **Codex skills 路径不是 `.codex/skills/`**：Codex 扫描 `.agents/skills/`（open agent skills 标准），与 OpenCode 的 agent-compatible 路径一致，故 +Codex 模式下两者共享 `.agents/skills/` 一份 skills
- **Codex 仅在被显式要求时 spawn subagent**：与 OpenCode/Claude 不同，SKILL.md / AGENTS.md 的视觉处理指令须明确告知 Codex 主 agent "遇到视觉内容时 spawn `vision-reader` 自定义 agent 读取"
```

- [ ] **Step 8: 验证**

Run: `grep -ci "codex" AGENTS.md`
Expected: ≥ 10

人工审查：所有章节覆盖 Codex，无遗留 `ENABLE_CLAUDE_CODE` 相关表述。

- [ ] **Step 9: Commit**

```bash
git add AGENTS.md
git commit -m "docs(agents): document codex client mode in repo AGENTS.md"
```

---

### Task 13: 端到端三模式安装与切换手动验证

**Files:**
- 无文件改动（仅验证）

**Interfaces:**
- Consumes: Task 1-12 全部完成

- [ ] **Step 1: 准备临时 KB 测试目录**

```bash
mkdir -p /tmp/llm-wikier-codex-test/kb
echo "# Test" > /tmp/llm-wikier-codex-test/kb/test.md
```

- [ ] **Step 2: 验证 OpenCode-only 新装**

```bash
cd <repo-root>
echo "1" | bash install.sh /tmp/llm-wikier-codex-test/kb -f
```

Expected 输出包含：
- `[信息] 客户端模式: OpenCode-only`
- skills 安装到 `.opencode/skills/`

验证：
```bash
ls /tmp/llm-wikier-codex-test/kb/.opencode/skills/wiki-ingest/SKILL.md
test ! -e /tmp/llm-wikier-codex-test/kb/.agents
test ! -e /tmp/llm-wikier-codex-test/kb/.codex
grep -c ".opencode/" /tmp/llm-wikier-codex-test/kb/.wiki_ignore  # ≥1
grep -c ".agents/" /tmp/llm-wikier-codex-test/kb/.wiki_ignore     # 0
grep -c "bash .opencode/skills/wiki-backup/backup.sh --auto" /tmp/llm-wikier-codex-test/kb/AGENTS.md  # 1
```

- [ ] **Step 3: 验证 OpenCode-only → +Codex 切换**

```bash
echo "2" | bash install.sh /tmp/llm-wikier-codex-test/kb -f
```

Expected：
- `[信息] 客户端模式: OpenCode + Codex`
- skills 从 `.opencode/skills/` 迁移到 `.agents/skills/`
- 生成 `.codex/agents/vision-reader.toml`，含 `LLM-WIKIER:CODEX-AGENT-MANAGED` 标记
- `.wiki_ignore` 含 `.agents/` 和 `.codex/`
- `AGENTS.md` 备份命令变为 `bash .agents/skills/wiki-backup/backup.sh --auto`

验证：
```bash
ls /tmp/llm-wikier-codex-test/kb/.agents/skills/wiki-ingest/SKILL.md
test ! -e /tmp/llm-wikier-codex-test/kb/.opencode/skills
ls /tmp/llm-wikier-codex-test/kb/.codex/agents/vision-reader.toml
grep "LLM-WIKIER:CODEX-AGENT-MANAGED" /tmp/llm-wikier-codex-test/kb/.codex/agents/vision-reader.toml
grep -c ".agents/" /tmp/llm-wikier-codex-test/kb/.wiki_ignore   # ≥1
grep -c ".codex/" /tmp/llm-wikier-codex-test/kb/.wiki_ignore    # ≥1
grep -c "bash .agents/skills/wiki-backup/backup.sh --auto" /tmp/llm-wikier-codex-test/kb/AGENTS.md  # 1
```

- [ ] **Step 4: 验证 +Codex → +Claude 切换**

```bash
echo "3" | bash install.sh /tmp/llm-wikier-codex-test/kb -f
```

Expected：
- `[信息] 客户端模式: OpenCode + Claude Code`
- skills 从 `.agents/skills/` 迁移到 `.claude/skills/`
- `.codex/agents/vision-reader.toml` 已移除（`.codex/` 空则一并删除）
- `CLAUDE.md` 生成含托管区块
- `.claude/agents/vision-reader.md` 生成含 `LLM-WIKIER:CLAUDE-AGENT-MANAGED`
- `.wiki_ignore` 含 `.claude/` 和 `CLAUDE.md`，不含 `.agents/`、`.codex/`

验证：
```bash
ls /tmp/llm-wikier-codex-test/kb/.claude/skills/wiki-ingest/SKILL.md
test ! -e /tmp/llm-wikier-codex-test/kb/.agents
test ! -e /tmp/llm-wikier-codex-test/kb/.codex
grep "LLM-WIKIER:CLAUDE-MANAGED:BEGIN" /tmp/llm-wikier-codex-test/kb/CLAUDE.md
grep "LLM-WIKIER:CLAUDE-AGENT-MANAGED" /tmp/llm-wikier-codex-test/kb/.claude/agents/vision-reader.md
grep -c ".claude/" /tmp/llm-wikier-codex-test/kb/.wiki_ignore   # ≥1
grep -c "CLAUDE.md" /tmp/llm-wikier-codex-test/kb/.wiki_ignore   # ≥1
```

- [ ] **Step 5: 验证 +Claude → OpenCode-only 切换**

```bash
echo "4" | bash install.sh /tmp/llm-wikier-codex-test/kb -f
```

Expected：
- `[信息] 客户端模式: OpenCode-only`
- skills 回到 `.opencode/skills/`
- `CLAUDE.md` 托管区块移除（若文件变空则删除）
- `.claude/agents/vision-reader.md` 移除
- `.wiki_ignore` 不含 `.claude/`、`CLAUDE.md`、`.agents/`、`.codex/`

验证：
```bash
ls /tmp/llm-wikier-codex-test/kb/.opencode/skills/wiki-ingest/SKILL.md
test ! -e /tmp/llm-wikier-codex-test/kb/.claude
test ! -e /tmp/llm-wikier-codex-test/kb/CLAUDE.md
```

- [ ] **Step 6: 验证 Codex 模式下 AGENTS.md 备份命令执行可用**

```bash
echo "2" | bash install.sh /tmp/llm-wikier-codex-test/kb -f
bash /tmp/llm-wikier-codex-test/kb/.agents/skills/wiki-backup/backup.sh --auto
```

Expected：备份成功执行，无"无法定位知识库目录"错误。

- [ ] **Step 7: PowerShell 镜像验证（Windows 环境）**

在 Windows 上对同一测试 KB（或新 KB）用 `install.ps1 -Force` 重复 Step 2-6，确认 PowerShell 行为与 bash 一致（路径用 `\` 分隔）。输入方式：交互式三选一，或先设置 `$script:ClientMode` 后用 `-Force`（`-Force` 会保留检测到的当前模式）。

- [ ] **Step 8: 清理测试目录**

```bash
rm -rf /tmp/llm-wikier-codex-test
```

- [ ] **Step 9: 最终全量验证**

```bash
bash -n install.sh
bash -n config_vision_reader.sh
bash -n lib/common.sh
bash -n skills/wiki-backup/backup.sh
grep -rn "ENABLE_CLAUDE_CODE" install.sh install.ps1                 # 应无输出
grep -rn "sync_claude_support_files\|Sync-ClaudeSupportFiles" install.sh install.ps1  # 应无输出
grep -rn "get_inactive_skills_dir[^s]\|Get-InactiveSkillsDir[^s]" install.sh install.ps1  # 应无输出
grep -rn "compatibility: opencode, claude-code$" skills/             # 应无输出（全部已加 codex）
grep -rn "compatibility: opencode, claude-code, codex" skills/ | wc -l  # 应为 8
```

- [ ] **Step 10: Commit（如有修复）**

本任务无文件改动；如 Step 1-9 发现 bug 并修复，单独 commit：

```bash
git add <修复的文件>
git commit -m "fix(install): <具体修复说明>"
```

否则跳过。

---

## Self-Review 结果

**1. Spec 覆盖检查：**

- 三态模式模型 → Task 5/7（安装器变量与 Select-ClientSupport）、Task 1（排除目录）、Task 4（模板排除项）、Task 11/12（文档模式表）
- 安装器交互（三选一、更新检测当前模式）→ Task 5 Step 3-4 / Task 7 Step 3-4
- 检测函数（`has_codex_support` / `Test-CodexSupport`）→ Task 5 Step 3 / Task 7 Step 3
- `Get-ActiveSkillsDir` / `Get-InactiveSkillsDirs`（复数）/ `Get-BackupAutoCommand` → Task 5 Step 5 / Task 7 Step 5
- Codex vision-reader 预生成（TOML、不指定 model、sandbox_mode=read-only、托管标记）→ Task 5 Step 10 / Task 7 Step 10
- `Sync-ClientSupportFiles` 三态分支 → Task 5 Step 10 / Task 7 Step 10
- SKILL.md frontmatter `compatibility` + 视觉/capture/backup 文案 → Task 2 + Task 3
- AGENTS.md 模板视觉/排除/capture 章节 → Task 4
- 三处同步（templates/AGENTS.md.tmpl + install.sh fallback + install.ps1 fallback）→ Task 4 + Task 6 + Task 8
- lib/common.{sh,ps1} 排除目录 → Task 1
- backup.sh/backup.ps1 错误提示路径列表 → Task 9
- config_vision_reader.{sh,ps1} 完成提示 → Task 10
- README 模式表/目录结构/切换/视觉/备份/排除表/Codex 调用 → Task 11
- 仓库根 AGENTS.md skill 格式/架构/安装脚本职责/vision-reader/陷阱 → Task 12
- 模式切换矩阵（opencode↔claude、opencode↔codex、claude↔codex）→ Task 5 Step 10-12 / Task 7 Step 10-11 / Task 13 Step 2-5 端到端验证
- 端到端验证 → Task 13

**2. Placeholder 扫描：** 无 TBD/TODO/"implement later"；所有步骤含具体 oldString/newString 或具体命令与期望输出。

**3. 类型/命名一致性：**
- `CLIENT_MODE`（sh）与 `$script:ClientMode`（ps1）取值一致：`"opencode"` / `"claude"` / `"codex"`
- `has_codex_support` ↔ `Test-CodexSupport`；`detect_current_mode` ↔ `Get-CurrentMode`
- `get_active_skills_dir` ↔ `Get-ActiveSkillsDir`；`get_inactive_skills_dirs`（复数）↔ `Get-InactiveSkillsDirs`（复数）
- `write_codex_vision_reader` ↔ `Write-CodexVisionReader`；`remove_codex_vision_reader` ↔ `Remove-CodexVisionReader`
- `sync_client_support_files` ↔ `Sync-ClientSupportFiles`
- `CODEX_AGENT_MANAGED`（sh）↔ `$script:CodexAgentManaged`（ps1）= `"LLM-WIKIER:CODEX-AGENT-MANAGED"`
- 三模式 skills 目录映射一致：opencode→`.opencode/skills`，claude→`.claude/skills`，codex→`.agents/skills`

**4. Spec 一致性：** 设计文档第 60-67 行表格、第 109-116 行模式切换矩阵、第 121-148 行 vision-reader TOML 内容与本计划 Task 5 Step 10 / Task 7 Step 10 的 heredoc 内容完全一致。

---

## Execution Handoff

Plan complete and saved to `docs/superpowers/plans/2026-07-04-codex-support.md`.



