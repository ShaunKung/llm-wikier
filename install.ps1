#!/usr/bin/env pwsh

param(
    [Parameter(Mandatory=$true, Position=0)]
    [string]$TargetDir,
    
    [switch]$Force,
    [switch]$Help
)

$ScriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path
$SkillsSource = Join-Path $ScriptDir "skills"
$TemplatesSource = Join-Path $ScriptDir "templates"

$script:ClientMode = "opencode"
$script:LlmWikierSkills = @("wiki-init", "wiki-ingest", "wiki-query", "wiki-lint", "wiki-update", "wiki-prune", "wiki-capture", "wiki-backup")
$script:ClaudeManagedBegin = "<!-- LLM-WIKIER:CLAUDE-MANAGED:BEGIN -->"
$script:ClaudeManagedEnd = "<!-- LLM-WIKIER:CLAUDE-MANAGED:END -->"
$script:CodexAgentManaged = "LLM-WIKIER:CODEX-AGENT-MANAGED"

function Write-Error-Message {
    param([string]$Message)
    Write-Host "[错误] " -ForegroundColor Red -NoNewline
    Write-Host $Message
}

function Write-Success-Message {
    param([string]$Message)
    Write-Host "[成功] " -ForegroundColor Green -NoNewline
    Write-Host $Message
}

function Write-Info-Message {
    param([string]$Message)
    Write-Host "[信息] " -ForegroundColor Blue -NoNewline
    Write-Host $Message
}

function Write-Warning-Message {
    param([string]$Message)
    Write-Host "[警告] " -ForegroundColor Yellow -NoNewline
    Write-Host $Message
}

function Show-Help {
    Write-Host "LLM Wikier 安装脚本"
    Write-Host ""
    Write-Host "用法: .\install.ps1 <目标知识库路径> [选项]"
    Write-Host ""
    Write-Host "参数:"
    Write-Host "  <目标知识库路径>    要安装 LLM Wikier 的知识库目录路径"
    Write-Host ""
    Write-Host "选项:"
    Write-Host "  -Force              强制覆盖（更新安装时自动确认所有步骤）"
    Write-Host "  -Help               显示此帮助信息"
    Write-Host ""
    Write-Host "示例:"
    Write-Host "  .\install.ps1 'C:\Users\用户\my-knowledge-base'"
    Write-Host "  .\install.ps1 'C:\path\to\knowledge-base' -Force"
}

function Test-UpdateInstall {
    param([string]$TargetDir)

    $AgentsFile = Join-Path $TargetDir "AGENTS.md"
    if (-not (Test-Path $AgentsFile)) { return $false }

    $KeySkills = @("wiki-ingest", "wiki-lint", "wiki-query")
    $SkillRoots = @(
        (Join-Path $TargetDir ".opencode\skills"),
        (Join-Path $TargetDir ".claude\skills"),
        (Join-Path $TargetDir ".agents\skills")
    )

    foreach ($SkillRoot in $SkillRoots) {
        $Found = $true
        foreach ($Skill in $KeySkills) {
            $SkillFile = Join-Path $SkillRoot "$Skill\SKILL.md"
            if (-not (Test-Path $SkillFile)) {
                $Found = $false
                break
            }
        }
        if ($Found) { return $true }
    }

    return $false
}

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
    param([string]$Message)

    if ($Force) { return $true }

    Write-Host "`n[询问] " -ForegroundColor Yellow -NoNewline
    Write-Host "$Message [Y/n] " -NoNewline
    $Response = Read-Host

    return ($Response -notmatch '^[nN](o|O)?$')
}

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

function Get-ExistingBackupRoot {
    param([string]$TargetDir)

    $Candidates = @(
        (Join-Path $TargetDir ".opencode\skills\wiki-backup\backup.ps1"),
        (Join-Path $TargetDir ".claude\skills\wiki-backup\backup.ps1"),
        (Join-Path $TargetDir ".agents\skills\wiki-backup\backup.ps1"),
        (Join-Path $TargetDir ".opencode\skills\wiki-backup\backup.sh"),
        (Join-Path $TargetDir ".claude\skills\wiki-backup\backup.sh"),
        (Join-Path $TargetDir ".agents\skills\wiki-backup\backup.sh")
    )

    foreach ($File in $Candidates) {
        if (-not (Test-Path $File)) { continue }
        $Lines = Get-Content $File -ErrorAction SilentlyContinue
        foreach ($Line in $Lines) {
            $Value = $null
            if ($Line -match '^\$script:BackupRoot = "(.*)"$') {
                $Value = $matches[1]
            } elseif ($Line -match '^BACKUP_ROOT="(.*)"$') {
                $Value = $matches[1]
            }
            if (-not [string]::IsNullOrWhiteSpace($Value) -and $Value -ne "__BACKUP_ROOT__") {
                return $Value
            }
        }
    }

    return $null
}

function Set-BackupRootInScripts {
    param([string]$TargetDir, [string]$BackupRoot)

    $SkillsDir = Get-ActiveSkillsDir -TargetDir $TargetDir

    $BackupPs1 = Join-Path $SkillsDir "wiki-backup\backup.ps1"
    if (Test-Path $BackupPs1) {
        $Lines = Get-Content $BackupPs1
        $Lines = $Lines | ForEach-Object {
            if ($_ -match '^\$script:BackupRoot = ') {
                '$script:BackupRoot = "' + $BackupRoot + '"'
            } else {
                $_
            }
        }
        Set-Content -Path $BackupPs1 -Value $Lines -Encoding UTF8
    }

    $BackupSh = Join-Path $SkillsDir "wiki-backup\backup.sh"
    if (Test-Path $BackupSh) {
        $BackupRootForSh = $BackupRoot.Replace('\', '/')
        $Lines = Get-Content $BackupSh
        $Lines = $Lines | ForEach-Object {
            if ($_ -match '^BACKUP_ROOT=') {
                'BACKUP_ROOT="' + $BackupRootForSh + '"'
            } else {
                $_
            }
        }
        Set-Content -Path $BackupSh -Value $Lines -Encoding UTF8
    }
}

function Write-RenderedAgentsTemplate {
    param([string]$InputFile, [string]$OutputFile)
    $Content = Get-Content $InputFile -Raw -ErrorAction Stop
    $Content = $Content.Replace("__WIKI_BACKUP_AUTO_COMMAND__", (Get-BackupAutoCommand))
    Set-Content -Path $OutputFile -Value $Content -Encoding UTF8
}

function Remove-ManagedSkillsFromDir {
    param([string]$SkillsDir)
    if (-not (Test-Path $SkillsDir)) { return }

    foreach ($Skill in $script:LlmWikierSkills) {
        $SkillDir = Join-Path $SkillsDir $Skill
        if (Test-Path $SkillDir) {
            Remove-Item $SkillDir -Recurse -Force
            Write-Info-Message "已移除旧 skill: $SkillDir"
        }
    }

    if ((Test-Path $SkillsDir) -and -not (Get-ChildItem $SkillsDir -Force)) { Remove-Item $SkillsDir -Force }
    $ParentDir = Split-Path -Parent $SkillsDir
    if ((Test-Path $ParentDir) -and -not (Get-ChildItem $ParentDir -Force)) { Remove-Item $ParentDir -Force }
}

function Get-AgentsSection {
    param([string]$File, [string]$FromMarker, [string]$ToMarker)

    $Content = Get-Content $File -Raw -ErrorAction SilentlyContinue
    if (-not $Content) { return $null }

    $Parts = $Content -split [regex]::Escape($FromMarker)
    if ($Parts.Count -lt 2) { return $null }

    $AfterMarker = $Parts[1]
    $InnerParts = $AfterMarker -split [regex]::Escape($ToMarker)
    if ($InnerParts.Count -lt 2) { return $null }

    return $FromMarker + $InnerParts[0]
}

function Get-AgentsSectionToEnd {
    param([string]$File, [string]$FromMarker)

    $Content = Get-Content $File -Raw -ErrorAction SilentlyContinue
    if (-not $Content) { return $null }

    $Index = $Content.IndexOf($FromMarker)
    if ($Index -lt 0) { return $null }

    return $Content.Substring($Index)
}

function Merge-AgentsFile {
    param([string]$OldFile, [string]$NewTemplate, [string]$OutputFile)

    $UserSection = Get-AgentsSection -File $OldFile -FromMarker "## 用户偏好" -ToMarker "## 自定义配置"
    $CustomSection = Get-AgentsSectionToEnd -File $OldFile -FromMarker "## 自定义配置"

    $hasUser = ($null -ne $UserSection)
    $hasCustom = ($null -ne $CustomSection)

    if (-not $hasUser -or -not $hasCustom) {
        if (Invoke-PromptUser "现有 AGENTS.md 缺少标准章节，是否直接按新模板覆盖？") {
            Copy-Item $NewTemplate $OutputFile -Force
            Write-Info-Message "已按新模板覆盖 AGENTS.md"
        } else {
            Write-Info-Message "保留现有 AGENTS.md 不变"
        }
        return
    }

    $NewContent = Get-Content $NewTemplate -Raw -ErrorAction SilentlyContinue
    if (-not $NewContent) {
        Write-Warning-Message "无法读取新模板，保留现有 AGENTS.md"
        Copy-Item $OldFile $OutputFile -Force
        return
    }

    $newUserIndex = $NewContent.IndexOf("## 用户偏好")
    $newCustomIndex = $NewContent.IndexOf("## 自定义配置")

    if ($newUserIndex -lt 0 -or $newCustomIndex -lt 0) {
        Write-Warning-Message "新模板缺少标准章节，保留现有 AGENTS.md"
        Copy-Item $OldFile $OutputFile -Force
        return
    }

    $Header = $NewContent.Substring(0, $newUserIndex)
    $Result = $Header + $UserSection + $CustomSection

    Set-Content -Path $OutputFile -Value $Result -Encoding UTF8
    Write-Success-Message "已合并更新 AGENTS.md"
}

function Test-ExistingInstallation {
    $WikiDir = Join-Path $TargetDir ".wiki"
    $OldWikiDir = Join-Path $TargetDir "wiki"
    $AgentsFile = Join-Path $TargetDir "AGENTS.md"
    $SkillsDir = Join-Path $TargetDir ".opencode\skills"
    $ClaudeManaged = Test-ClaudeCodeSupport -TargetDir $TargetDir
    $CodexManaged = Test-CodexSupport -TargetDir $TargetDir
    
    if ((Test-Path $WikiDir) -or (Test-Path $OldWikiDir) -or (Test-Path $AgentsFile) -or (Test-Path $SkillsDir) -or $ClaudeManaged -or $CodexManaged) {
        if ($Force) {
            Write-Warning-Message "检测到已有安装，将强制覆盖"
        } else {
            Write-Error-Message "检测到已有文件，若为更新安装请使用 -Force，或移除已有文件后重试"
            exit 1
        }
    }
}

function New-WikiDirectory {
    $WikiDir = Join-Path $TargetDir ".wiki"
    New-Item -ItemType Directory -Path $WikiDir -Force | Out-Null
    Write-Success-Message "创建 wiki 目录: $WikiDir"
}

function New-IndexFile {
    $IndexFile = Join-Path $TargetDir ".wiki\index.md"
    
    $Content = @'
# Wiki 索引

这是 LLM Wikier 自动生成的 wiki 索引页面。

## 页面列表

### 实体页面
<!-- LLM 将在此添加实体页面链接 -->

### 概念页面
<!-- LLM 将在此添加概念页面链接 -->

### 源文件摘要
<!-- LLM 将在此添加源文件摘要链接 -->

### 分析与综合
<!-- LLM 将在此添加分析页面链接 -->

---
*最后更新: 待初始化*
'@
    
    Set-Content -Path $IndexFile -Value $Content -Encoding UTF8
    Write-Success-Message "创建索引文件: $IndexFile"
}

function New-LogFile {
    $LogFile = Join-Path $TargetDir ".wiki\log.md"
    
    $Content = @'
# Wiki 操作日志

此文件记录所有 wiki 操作的历史。

---

'@
    
    Set-Content -Path $LogFile -Value $Content -Encoding UTF8
    Write-Success-Message "创建日志文件: $LogFile"
}

function New-ProcessedFile {
    $ProcessedFile = Join-Path $TargetDir ".wiki\.wiki-processed"
    
    '{"version": 2, "entries": []}' | Set-Content -Path $ProcessedFile -Encoding UTF8
    Write-Success-Message "创建处理记录文件: $ProcessedFile"
}

function New-WikiIgnoreFile {
    $IgnoreFile = Join-Path $TargetDir ".wiki_ignore"

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

    $Content = "# LLM Wikier — 默认排除规则（由工具包管理，请勿修改此区域）`n"
    $Content += ($DefaultRules -join "`n")
    $Content += "`n`n# ——— 用户自定义规则（添加在此区域下方） ———"
    
    Set-Content -Path $IgnoreFile -Value $Content -Encoding UTF8
    Write-Success-Message "创建 .wiki_ignore: $IgnoreFile"
}

function New-OutputDirectory {
    $OutputDir = Join-Path $TargetDir "output"
    
    if (Test-Path $OutputDir) {
        Write-Info-Message "output/ 目录已存在，跳过创建"
        return
    }
    
    New-Item -ItemType Directory -Path $OutputDir -Force | Out-Null
    Write-Success-Message "创建 output/ 目录: $OutputDir"
}

function Merge-WikiIgnore {
    param([string]$TargetDir)
    
    $IgnoreFile = Join-Path $TargetDir ".wiki_ignore"
    
    if (-not (Test-Path $IgnoreFile)) {
        New-WikiIgnoreFile
        return
    }
    
    $Content = Get-Content $IgnoreFile -Raw -ErrorAction SilentlyContinue
    
    $MarkerIndex = $Content.IndexOf("# ——— 用户自定义规则")
    if ($MarkerIndex -ge 0) {
        $AfterMarker = $Content.Substring($MarkerIndex)
        $NewlineAfterMarker = $AfterMarker.IndexOf("`n")
        if ($NewlineAfterMarker -ge 0) {
            $UserCustom = $AfterMarker.Substring($NewlineAfterMarker + 1)
        } else {
            $UserCustom = ""
        }
    } else {
        $UserCustom = ""
    }
    
    New-WikiIgnoreFile
    
    if (-not [string]::IsNullOrWhiteSpace($UserCustom)) {
        Add-Content -Path $IgnoreFile -Value "`n$UserCustom" -Encoding UTF8
        Write-Success-Message "已合并更新 .wiki_ignore（保留用户自定义规则）"
    }
}

function New-SkillsDirectory {
    $SkillsDir = Get-ActiveSkillsDir -TargetDir $TargetDir
    $ExistingBackupRoot = Get-ExistingBackupRoot -TargetDir $TargetDir
    New-Item -ItemType Directory -Path $SkillsDir -Force | Out-Null

    foreach ($Skill in $script:LlmWikierSkills) {
        $SrcDir = Join-Path $SkillsSource $Skill
        $DstDir = Join-Path $SkillsDir $Skill
        
        if (Test-Path $SrcDir) {
            New-Item -ItemType Directory -Path $DstDir -Force | Out-Null
            Copy-Item "$SrcDir\*" $DstDir -Recurse -Force
            Write-Success-Message "安装 skill: $Skill"
        } else {
            Write-Warning-Message "找不到 skill 源文件: $Skill"
        }
    }

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
    $AgentsFile = Join-Path $TargetDir "AGENTS.md"
    $TemplateFile = Join-Path $TemplatesSource "AGENTS.md.tmpl"
    
    if (Test-Path $TemplateFile) {
        Write-RenderedAgentsTemplate -InputFile $TemplateFile -OutputFile $AgentsFile
        Write-Success-Message "创建 AGENTS.md: $AgentsFile"
    } else {
        Write-Warning-Message "找不到 AGENTS.md 模板，创建默认文件"
        
        $Content = @'
# AGENTS.md - LLM Wikier 配置文件

此文件定义知识库的结构、约定和工作流程。

> ⚠️ **重要提示**：本文档除「用户偏好」和「自定义配置」章节外，其余章节均由工具包在更新安装时从模板自动刷新。请勿在其他章节添加个人内容，否则更新安装时将被覆盖。您的自定义内容请仅存放在「用户偏好」和「自定义配置」章节中。

## 知识库概述

这是一个由 LLM Wikier 管理的个人知识库。

## Wiki 结构

```
.wiki/
├── index.md          # 内容索引
├── log.md            # 操作日志
├── entities/         # 实体页面
├── concepts/         # 概念页面
├── sources/          # 源文件摘要
└── analysis/         # 分析与综合页面
```

## 页面命名规范

- 使用小写字母和连字符
- 实体页面：`entities/实体名称.md`
- 概念页面：`concepts/概念名称.md`
- 源文件摘要：`sources/源文件名-summary.md`

## 支持的文件格式

文本格式：`.md`, `.txt`, `.json`, `.yaml`, `.yml`, `.csv`, `.xml`, `.html`, `.rst`, `.org`, `.tex`

办公文档格式：`.pdf`, `.docx`, `.doc`, `.pptx`, `.ppt`, `.xlsx`, `.xls`, `.odt`, `.odp`, `.ods`

图片格式：`.png`, `.jpg`, `.jpeg`, `.gif`, `.webp`, `.svg`, `.bmp`

网络链接格式：`.url`

## 视觉内容处理策略

主 agent 可能是纯文本模型。如已配置 `vision-reader` subagent，Agent 会在遇到视觉内容时自动调用。

### 处理流程

**纯图片文件**（`.png`, `.jpg`, `.jpeg`, `.gif`, `.webp`, `.svg`, `.bmp`）：
- 调用 `vision-reader` subagent 读取（OpenCode 通常使用 Task 工具；Claude Code 使用 Agent/subagent 调用）

**网络链接网页**（`.url`）：Read 取文本 + vision-reader 取视觉元素

**办公文档 & 网页**（`.pptx`, `.ppt`, `.pdf`, `.docx`, `.doc`, `.html`）：
- 两段式：Read 取文本 + vision-reader 取视觉元素

**Markdown**：文本优先，按需读取图片

如当前客户端未配置 `vision-reader`，Agent 跳过视觉处理。OpenCode 配置路径为 `.opencode/agents/vision-reader.md`，Claude Code 配置路径为 `.claude/agents/vision-reader.md`，Codex 配置路径为 `.codex/agents/vision-reader.toml`。

OpenCode 配置方式：`.\config_vision_reader.ps1 <知识库路径>`。启用 Claude Code 支持时安装器生成 Claude Code 版 `vision-reader`；启用 Codex 支持时安装器生成 Codex 版 `vision-reader`（不指定 model，由 Codex 自动选择）。

## 文件排除规则

知识库根目录的 `.wiki_ignore` 文件定义了被排除的文件和目录。
格式类似 `.gitignore`：每行一个模式，`#` 开头的行为注释。

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

### 用户自定义
用户可在 `.wiki_ignore` 的「用户自定义规则」区域添加自己的排除项。

### 对技能的影响
所有扫描 raw sources 的技能（wiki-init、wiki-ingest、wiki-update）在扫描文件前
必须读取 `.wiki_ignore` 并按其中规则排除匹配的文件和目录。

## 工作流程

1. 用户添加新的源文件到知识库
2. 运行 `/wiki-ingest` 处理新文件
3. LLM 更新 wiki 页面、索引和日志
4. 用户可通过 `/wiki-query` 查询知识库

## 贡献指南

- 提问时尽量具体
- 定期运行 `/wiki-lint` 检查 wiki 健康状态
- 重要的查询答案可以作为新页面沉淀

## 自动备份

每次新会话开始时，Agent 应以自动模式静默执行一次备份：

    __WIKI_BACKUP_AUTO_COMMAND__

- 不向用户显示执行过程和结果
- 同一会话内仅执行一次（自动模式的日级去重机制已覆盖此要求）
- 如脚本不存在，静默跳过

## 用户偏好

<!-- 用户可以在此添加个人偏好 -->

## 自定义配置

<!-- 用户可以在此添加自定义配置 -->
'@

        $DefaultTemplate = [System.IO.Path]::GetTempFileName()
        Set-Content -Path $DefaultTemplate -Value $Content -Encoding UTF8
        Write-RenderedAgentsTemplate -InputFile $DefaultTemplate -OutputFile $AgentsFile
        Remove-Item $DefaultTemplate -Force
        Write-Success-Message "创建默认 AGENTS.md: $AgentsFile"
    }
}

function Write-ClaudeFile {
    $ClaudeFile = Join-Path $TargetDir "CLAUDE.md"
    $Existing = ""
    if (Test-Path $ClaudeFile) {
        $Existing = Get-Content $ClaudeFile -Raw -ErrorAction SilentlyContinue
        $Pattern = [regex]::Escape($script:ClaudeManagedBegin) + '[\s\S]*?' + [regex]::Escape($script:ClaudeManagedEnd) + "`r?`n?"
        $Existing = [regex]::Replace($Existing, $Pattern, "")
    }

    $Managed = @"
$script:ClaudeManagedBegin
@AGENTS.md

## Claude Code

本知识库已启用 Claude Code 支持。LLM Wikier 的 Agent Skills 安装在 ``.claude/skills/``，OpenCode 也会通过兼容路径读取同一份 skills。
$script:ClaudeManagedEnd
"@

    if (-not [string]::IsNullOrWhiteSpace($Existing)) {
        $Content = $Existing.TrimEnd() + "`n`n" + $Managed
    } else {
        $Content = $Managed
    }

    Set-Content -Path $ClaudeFile -Value $Content -Encoding UTF8
    Write-Success-Message "已配置 Claude Code 入口: $ClaudeFile"
}

function Remove-ClaudeManagedBlock {
    $ClaudeFile = Join-Path $TargetDir "CLAUDE.md"
    if (-not (Test-Path $ClaudeFile)) { return }

    $Content = Get-Content $ClaudeFile -Raw -ErrorAction SilentlyContinue
    if (-not $Content -or -not $Content.Contains($script:ClaudeManagedBegin)) {
        Write-Info-Message "保留用户自定义 CLAUDE.md"
        return
    }

    $Pattern = [regex]::Escape($script:ClaudeManagedBegin) + '[\s\S]*?' + [regex]::Escape($script:ClaudeManagedEnd) + "`r?`n?"
    $Remaining = [regex]::Replace($Content, $Pattern, "")
    if ([string]::IsNullOrWhiteSpace($Remaining)) {
        Remove-Item $ClaudeFile -Force
        Write-Success-Message "已移除 LLM Wikier 托管的 CLAUDE.md"
    } else {
        Set-Content -Path $ClaudeFile -Value $Remaining.TrimEnd() -Encoding UTF8
        Write-Success-Message "已移除 CLAUDE.md 中的 LLM Wikier 托管区块"
    }
}

function Write-ClaudeVisionReader {
    $AgentDir = Join-Path $TargetDir ".claude\agents"
    $AgentFile = Join-Path $AgentDir "vision-reader.md"

    if (Test-Path $AgentFile) {
        $Existing = Get-Content $AgentFile -Raw -ErrorAction SilentlyContinue
        if (-not ($Existing -and $Existing.Contains("LLM-WIKIER:CLAUDE-AGENT-MANAGED"))) {
            Write-Info-Message "保留用户自定义 Claude Code vision-reader: $AgentFile"
            return
        }
    }

    New-Item -ItemType Directory -Path $AgentDir -Force | Out-Null

    $Content = @'
---
name: vision-reader
description: 读取图片、图表、截图、幻灯片、PDF 和文档排版等视觉元素，转化为文字描述
model: inherit
tools:
  - Read
---
<!-- LLM-WIKIER:CLAUDE-AGENT-MANAGED -->
你是一个视觉内容读取器。你的职责是读取文件中的视觉元素（图片、图表、截图、幻灯片、页面排版等），并将视觉内容转化为文字描述。

## 核心职责
- 只描述视觉元素（图片、图表、照片、插图、截图、幻灯片视觉内容、排版布局等）
- 不要重复已经由主 agent 处理的纯文本内容
- **兜底规则**：如果发现文档中文本提取明显不完整（如幻灯片缺失文字、表格数据丢失、图表中的数据标签等），请一并补充关键文本信息

## 输出格式
对每个视觉元素：

```
### [图片/图表/截图 序号]
**类型**: [图表/照片/截图/插图/排版]
**描述**: [视觉内容的文字描述]
**关键信息**: [图表数据、照片中的人物/场景、截图中的UI元素、幻灯片主题等]
```

主 agent 会通过文件路径告知你需要读取的文件，请直接读取并返回描述。
'@

    Set-Content -Path $AgentFile -Value $Content -Encoding UTF8
    Write-Success-Message "已配置 Claude Code vision-reader: $AgentFile"
}

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

# === Migration functions ===
function Invoke-MigrateProcessedFile {
    param([string]$TargetDir)

    $ProcessedFile = Join-Path $TargetDir ".wiki\.wiki-processed"
    if (-not (Test-Path $ProcessedFile)) { return }

    $Content = Get-Content $ProcessedFile -Raw -Encoding UTF8 -ErrorAction SilentlyContinue
    if (-not $Content) { return }

    try {
        $Data = $Content | ConvertFrom-Json
    } catch {
        Write-Warning-Message ".wiki-processed JSON 解析失败，跳过迁移"
        return
    }

    if ($Data.version -eq 2) {
        $Normalized = 0
        foreach ($Entry in @($Data.entries)) {
            $Hash = $Entry.hash
            if (-not [string]::IsNullOrEmpty($Hash)) {
                $NewHash = $Hash.ToLower()
                if ($NewHash.StartsWith('sha256:')) {
                    $NewHash = $NewHash.Substring(7)
                }
                if ($NewHash -ne $Hash) {
                    $Entry.hash = $NewHash
                    $Normalized++
                }
            }
        }

        if ($Normalized -gt 0) {
            Copy-Item $ProcessedFile "$ProcessedFile.hash-normalize.bak" -Force
            $Data | ConvertTo-Json -Depth 10 | Set-Content -Path $ProcessedFile -Encoding UTF8
            Write-Success-Message "已归一化 .wiki-processed hash: $Normalized 条"
            Write-Info-Message "回滚方法: Copy-Item '$ProcessedFile.hash-normalize.bak' '$ProcessedFile'"
        }
        return
    }

    if ($Data.version -ne 1) { return }

    Write-Info-Message "检测到 .wiki-processed v1，正在迁移至 v2..."

    # Backup
    Copy-Item $ProcessedFile "$ProcessedFile.bak" -Force
    Write-Info-Message "已备份: $ProcessedFile.bak"

    # Build hash→path map and path→hash map
    Write-Info-Message "正在扫描知识库文件..."
    $HashMap = @{}
    $PathMap = @{}
    $Now = (Get-Date -Format "yyyy-MM-ddTHH:mm:ssZ")

    Get-ChildItem -Path $TargetDir -Recurse -File -ErrorAction SilentlyContinue | ForEach-Object {
        $RelPath = $_.FullName.Substring($TargetDir.Length).TrimStart('\', '/').Replace('\', '/')
        # Skip ignored directories
        $PathParts = $RelPath.Split('/')
        if ($PathParts[0] -in @('.wiki', '.opencode', '.claude', '.git')) { return }

        try {
            $Hash = (Get-FileHash -Path $_.FullName -Algorithm SHA256 -ErrorAction SilentlyContinue).Hash.ToLower()
            if ($Hash) { $HashMap[$Hash] = $RelPath; $PathMap[$RelPath] = $Hash }
        } catch {
            try {
                $Hash = (Get-FileHash -Path $_.FullName -Algorithm MD5 -ErrorAction SilentlyContinue).Hash.ToLower()
                if ($Hash) { $HashMap[$Hash] = $RelPath; $PathMap[$RelPath] = $Hash }
            } catch {}
        }
    }

    Write-Info-Message "扫描完成: $($HashMap.Count) 个唯一哈希"

    # Process entries (use hashtables to avoid ConvertTo-Json PSCustomObject serialization bug)
    $Kept = 0; $Recovered = 0; $Removed = 0; $Filled = 0
    $NewEntries = @()

    foreach ($Entry in $Data.entries) {
        $Path = $Entry.path
        $FullPath = Join-Path $TargetDir $Path
        $Hash = $Entry.hash
        # Normalize: strip sha256: prefix if present
        if (-not [string]::IsNullOrEmpty($Hash)) {
            $Hash = $Hash.ToLower()
            if ($Hash.StartsWith('sha256:')) {
                $Hash = $Hash.Substring(7)
            }
        }

        # Fill missing hash from file
        if ([string]::IsNullOrEmpty($Hash) -and (Test-Path $FullPath)) {
            $Hash = $PathMap[$Path]
            if (-not $Hash) {
                try {
                    $Hash = (Get-FileHash -Path $FullPath -Algorithm SHA256 -ErrorAction SilentlyContinue).Hash.ToLower()
                } catch {
                    try {
                        $Hash = (Get-FileHash -Path $FullPath -Algorithm MD5 -ErrorAction SilentlyContinue).Hash.ToLower()
                    } catch {}
                }
            }
            if ($Hash) { $Filled++ }
        }

        $NewEntry = @{
            path = $Path
            hash = $Hash
            processed = $Entry.processed
        }

        if (Test-Path $FullPath) {
            $Kept++
            $NewEntries += $NewEntry
        } elseif ($Hash -and $HashMap.ContainsKey($Hash)) {
            $Recovered++
            $NewEntry.path = $HashMap[$Hash]
            $NewEntries += $NewEntry
        } else {
            $Removed++
        }
    }

    $NewData = @{ version = 2; entries = $NewEntries }
    $NewData | ConvertTo-Json -Depth 10 | Set-Content -Path $ProcessedFile -Encoding UTF8

    Write-Host ""
    Write-Success-Message "迁移完成: 保留 $Kept 条, 恢复 $Recovered 条, 移除 $Removed 条, 补填 $Filled 条"
    Write-Info-Message "回滚方法: Copy-Item '$ProcessedFile.bak' '$ProcessedFile'"
}

function Invoke-MigrateOldStructure {
    param([string]$TargetDir)

    $OldWikiDir = Join-Path $TargetDir "wiki"
    $NewWikiDir = Join-Path $TargetDir ".wiki"

    if (-not (Test-Path $OldWikiDir) -or (Test-Path $NewWikiDir)) {
        return
    }

    Write-Info-Message "检测到旧版 wiki/ 目录，正在自动迁移至 .wiki/..."

    # Step a: Move wiki/ → .wiki/
    Move-Item -Path $OldWikiDir -Destination $NewWikiDir -Force
    Write-Success-Message "已迁移 wiki/ → .wiki/"

    # Step b: Move .wiki-processed into .wiki/
    $OldProcessed = Join-Path $TargetDir ".wiki-processed"
    if (Test-Path $OldProcessed) {
        Move-Item -Path $OldProcessed -Destination (Join-Path $NewWikiDir ".wiki-processed") -Force
        Write-Success-Message "已迁移 .wiki-processed → .wiki/.wiki-processed"
    }

    # Step c: Replace wiki/ → .wiki/ in all migrated wiki pages
    Get-ChildItem -Path $NewWikiDir -Filter "*.md" -Recurse | ForEach-Object {
        (Get-Content $_.FullName -Raw) -replace 'wiki/', '.wiki/' | Set-Content $_.FullName -Encoding UTF8
    }
    Write-Success-Message "已修复 .wiki/ 内所有交叉引用链接"
}

function Set-HiddenAttributes {
    param([string]$TargetDir)

        $Dirs = @(
            Join-Path $TargetDir ".wiki"
            Join-Path $TargetDir ".opencode"
            Join-Path $TargetDir ".claude"
            Join-Path $TargetDir ".agents"
            Join-Path $TargetDir ".codex"
        )

    foreach ($Dir in $Dirs) {
        if (Test-Path $Dir) {
            $Item = Get-Item $Dir -Force
            if (-not ($Item.Attributes -band [System.IO.FileAttributes]::Hidden)) {
                $Item.Attributes = $Item.Attributes -bor [System.IO.FileAttributes]::Hidden
                Write-Info-Message "已设置隐藏属性: $Dir"
            }
        }
    }
}

# === Update functions ===
function Update-Skills {
    param([string]$TargetDir)

    $SkillsDir = Get-ActiveSkillsDir -TargetDir $TargetDir
    $ExistingBackupRoot = Get-ExistingBackupRoot -TargetDir $TargetDir
    New-Item -ItemType Directory -Path $SkillsDir -Force | Out-Null

    $Updated = 0

    foreach ($Skill in $script:LlmWikierSkills) {
        $SrcDir = Join-Path $SkillsSource $Skill
        $DstDir = Join-Path $SkillsDir $Skill

        if (Test-Path $SrcDir) {
            New-Item -ItemType Directory -Path $DstDir -Force | Out-Null
            Copy-Item "$SrcDir\*" $DstDir -Recurse -Force
            Write-Success-Message "更新 skill: $Skill"
            $Updated++
        } else {
            Write-Warning-Message "找不到 skill 源文件: $Skill"
        }
    }

    if ($Updated -gt 0) {
        Write-Info-Message "共更新 $Updated 个 skill"
    }

    $InactiveDirs = Get-InactiveSkillsDirs -TargetDir $TargetDir
    foreach ($InactiveDir in $InactiveDirs) {
        Remove-ManagedSkillsFromDir -SkillsDir $InactiveDir
    }

    if (-not [string]::IsNullOrWhiteSpace($ExistingBackupRoot)) {
        Set-BackupRootInScripts -TargetDir $TargetDir -BackupRoot $ExistingBackupRoot
        Write-Info-Message "已保留既有备份根目录: $ExistingBackupRoot"
    }
}

function Update-AgentsFile {
    param([string]$TargetDir)

    $AgentsFile = Join-Path $TargetDir "AGENTS.md"
    $TemplateFile = Join-Path $TemplatesSource "AGENTS.md.tmpl"

    if (Test-Path $TemplateFile) {
        $RenderedTemplate = [System.IO.Path]::GetTempFileName()
        Write-RenderedAgentsTemplate -InputFile $TemplateFile -OutputFile $RenderedTemplate
        Merge-AgentsFile -OldFile $AgentsFile -NewTemplate $RenderedTemplate -OutputFile $AgentsFile
        Remove-Item $RenderedTemplate -Force
    } else {
        Write-Warning-Message "找不到 AGENTS.md 模板，使用内置默认内容"
        $Content = @'
# AGENTS.md - LLM Wikier 配置文件

此文件定义知识库的结构、约定和工作流程。

> ⚠️ **重要提示**：本文档除「用户偏好」和「自定义配置」章节外，其余章节均由工具包在更新安装时从模板自动刷新。请勿在其他章节添加个人内容，否则更新安装时将被覆盖。您的自定义内容请仅存放在「用户偏好」和「自定义配置」章节中。

## 知识库概述

这是一个由 LLM Wikier 管理的个人知识库。

## Wiki 结构

```
.wiki/
├── index.md          # 内容索引
├── log.md            # 操作日志
├── entities/         # 实体页面
├── concepts/         # 概念页面
├── sources/          # 源文件摘要
└── analysis/         # 分析与综合页面
```

## 支持的文件格式

文本格式：`.md`, `.txt`, `.json`, `.yaml`, `.yml`, `.csv`, `.xml`, `.html`, `.rst`, `.org`, `.tex`

办公文档格式：`.pdf`, `.docx`, `.doc`, `.pptx`, `.ppt`, `.xlsx`, `.xls`, `.odt`, `.odp`, `.ods`

图片格式：`.png`, `.jpg`, `.jpeg`, `.gif`, `.webp`, `.svg`, `.bmp`

网络链接格式：`.url`

## 视觉内容处理策略

主 agent 可能是纯文本模型。如已配置 `vision-reader` subagent，Agent 会在遇到视觉内容时自动调用。

### 处理流程

**纯图片文件**（`.png`, `.jpg`, `.jpeg`, `.gif`, `.webp`, `.svg`, `.bmp`）：
- 调用 `vision-reader` subagent 读取（OpenCode 通常使用 Task 工具；Claude Code 使用 Agent/subagent 调用）

**网络链接网页**（`.url`）：Read 取文本 + vision-reader 取视觉元素

**办公文档 & 网页**（`.pptx`, `.ppt`, `.pdf`, `.docx`, `.doc`, `.html`）：
- 两段式：Read 取文本 + vision-reader 取视觉元素

**Markdown**：文本优先，按需读取图片

如当前客户端未配置 `vision-reader`，Agent 跳过视觉处理。OpenCode 配置路径为 `.opencode/agents/vision-reader.md`，Claude Code 配置路径为 `.claude/agents/vision-reader.md`，Codex 配置路径为 `.codex/agents/vision-reader.toml`。

OpenCode 配置方式：`.\config_vision_reader.ps1 <知识库路径>`。启用 Claude Code 支持时安装器生成 Claude Code 版 `vision-reader`；启用 Codex 支持时安装器生成 Codex 版 `vision-reader`（不指定 model，由 Codex 自动选择）。

## 文件排除规则

知识库根目录的 `.wiki_ignore` 文件定义了被排除的文件和目录。
格式类似 `.gitignore`：每行一个模式，`#` 开头的行为注释。

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

### 对技能的影响
所有扫描 raw sources 的技能在扫描文件前必须读取 `.wiki_ignore` 并按规则排除。

## 自动备份

每次新会话开始时，Agent 应以自动模式静默执行一次备份：

    __WIKI_BACKUP_AUTO_COMMAND__

- 不向用户显示执行过程和结果
- 同一会话内仅执行一次（自动模式的日级去重机制已覆盖此要求）
- 如脚本不存在，静默跳过

## 用户偏好

<!-- 用户可以在此添加个人偏好 -->

## 自定义配置

<!-- 用户可以在此添加自定义配置 -->
'@
        $DefaultTemplate = [System.IO.Path]::GetTempFileName()
        Set-Content -Path $DefaultTemplate -Value $Content -Encoding UTF8
        $RenderedTemplate = [System.IO.Path]::GetTempFileName()
        Write-RenderedAgentsTemplate -InputFile $DefaultTemplate -OutputFile $RenderedTemplate
        Merge-AgentsFile -OldFile $AgentsFile -NewTemplate $RenderedTemplate -OutputFile $AgentsFile
        Remove-Item $RenderedTemplate -Force
        Remove-Item $DefaultTemplate -Force
    }
}

function Update-Install {
    param([string]$TargetDir)

    Write-Host ""

    Invoke-MigrateOldStructure -TargetDir $TargetDir

    Invoke-MigrateProcessedFile -TargetDir $TargetDir

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

    if (Invoke-PromptUser "Step (5/5): 是否修改备份根目录？") {
        Invoke-BackupConfig -TargetDir $TargetDir
    } else {
        Write-Info-Message "已跳过备份配置"
    }

    Write-Host ""
    Write-Success-Message "更新安装完成！"

    Set-HiddenAttributes -TargetDir $TargetDir
    Invoke-VisionReaderConfig -TargetDir $TargetDir
}

function Write-CompletionMessage {
    Write-Host ""
    Write-Host "======================================"
    Write-Success-Message "LLM Wikier 安装完成！"
    Write-Host "======================================"
    Write-Host ""
    Write-Host "下一步操作："
    Write-Host ""
    Write-Host "1. 进入知识库目录："
    Write-Host "   cd `"$TargetDir`""
    Write-Host ""
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
    Write-Host ""
    Write-Host "详细文档请参考 README.md"
}

function Invoke-BackupConfig {
    param([string]$TargetDir)

    $SkillsDir = Get-ActiveSkillsDir -TargetDir $TargetDir

    if ($Force) {
        $BackupScript = Join-Path $SkillsDir "wiki-backup\backup.ps1"
        if (Test-Path $BackupScript) {
            Write-Info-Message "强制安装模式，保留现有备份配置"
        } else {
            Write-Info-Message "强制安装模式，备份使用默认路径: $HOME\.knowledge_base"
        }
        return
    }

    Write-Host ""
    Write-Info-Message "备份脚本的默认根目录为 $HOME\.knowledge_base"
    $BackupRoot = Read-Host "请输入备份根目录（留空使用默认值）"

    if ([string]::IsNullOrWhiteSpace($BackupRoot)) {
        $BackupRoot = "$HOME\.knowledge_base"
    }

    # Write into backup.ps1
    $BackupPs1 = Join-Path $SkillsDir "wiki-backup\backup.ps1"
    if (Test-Path $BackupPs1) {
        Set-BackupRootInScripts -TargetDir $TargetDir -BackupRoot $BackupRoot
        Write-Success-Message "已配置备份根目录: $BackupRoot"
    } else {
        Write-Warning-Message "找不到 backup.ps1，跳过备份配置"
    }

    # Write into backup.sh (if present)
    $BackupSh = Join-Path $SkillsDir "wiki-backup\backup.sh"
    if (Test-Path $BackupSh) {
        Set-BackupRootInScripts -TargetDir $TargetDir -BackupRoot $BackupRoot
        Write-Success-Message "已配置 backup.sh 备份根目录"
    }
}

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

if ($Help) {
    Show-Help
    exit 0
}

if (-not (Test-Path $TargetDir)) {
    Write-Error-Message "目标目录不存在: $TargetDir"
    exit 1
}

$TargetDir = (Resolve-Path $TargetDir).Path
Write-Info-Message "目标知识库路径: $TargetDir"

if (Test-UpdateInstall -TargetDir $TargetDir) {
    Write-Info-Message "检测到已有安装（AGENTS.md + 关键 skills），进入更新安装模式"
    Update-Install -TargetDir $TargetDir
} else {
    Test-ExistingInstallation

    Select-ClientSupport -TargetDir $TargetDir -IsUpdate $false

    Write-Info-Message "开始安装 LLM Wikier..."

    New-WikiDirectory
    New-IndexFile
    New-LogFile
    New-ProcessedFile
    New-WikiIgnoreFile
    New-OutputDirectory
    New-SkillsDirectory
    New-AgentsFile
    Sync-ClientSupportFiles

    Invoke-BackupConfig -TargetDir $TargetDir

    Set-HiddenAttributes -TargetDir $TargetDir

    Write-CompletionMessage

    Invoke-VisionReaderConfig -TargetDir $TargetDir
}
