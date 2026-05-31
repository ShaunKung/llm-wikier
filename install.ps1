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
    foreach ($Skill in $KeySkills) {
        $SkillFile = Join-Path $TargetDir ".opencode\skills\$Skill\SKILL.md"
        if (-not (Test-Path $SkillFile)) { return $false }
    }

    return $true
}

function Invoke-PromptUser {
    param([string]$Message)

    if ($Force) { return $true }

    Write-Host "`n[询问] " -ForegroundColor Yellow -NoNewline
    Write-Host "$Message [Y/n] " -NoNewline
    $Response = Read-Host

    return ($Response -notmatch '^[nN](o|O)?$')
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
    
    if ((Test-Path $WikiDir) -or (Test-Path $OldWikiDir) -or (Test-Path $AgentsFile) -or (Test-Path $SkillsDir)) {
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
    
    '{"version": 1, "entries": []}' | Set-Content -Path $ProcessedFile -Encoding UTF8
    Write-Success-Message "创建处理记录文件: $ProcessedFile"
}

function New-WikiIgnoreFile {
    $IgnoreFile = Join-Path $TargetDir ".wiki_ignore"
    
    $Content = @'
# LLM Wikier — 默认排除规则（由工具包管理，请勿修改此区域）
.opencode/
.wiki/
.git/
AGENTS.md
output/

# ——— 用户自定义规则（添加在此区域下方） ———
'@
    
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
    $SkillsDir = Join-Path $TargetDir ".opencode\skills"
    New-Item -ItemType Directory -Path $SkillsDir -Force | Out-Null
    
    $Skills = @("wiki-init", "wiki-ingest", "wiki-query", "wiki-lint", "wiki-update", "wiki-prune", "wiki-capture", "wiki-backup")
    
    foreach ($Skill in $Skills) {
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
}

function New-AgentsFile {
    $AgentsFile = Join-Path $TargetDir "AGENTS.md"
    $TemplateFile = Join-Path $TemplatesSource "AGENTS.md.tmpl"
    
    if (Test-Path $TemplateFile) {
        Copy-Item $TemplateFile $AgentsFile -Force
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

## 视觉内容处理策略

主 agent 可能是纯文本模型。如已配置 `vision-reader` subagent，Agent 会在遇到视觉内容时自动调用。

### 处理流程

**纯图片文件**（`.png`, `.jpg`, `.jpeg`, `.gif`, `.webp`, `.svg`, `.bmp`）：
- 使用 Task 工具调用 `vision-reader` subagent 读取

**办公文档 & 网页**（`.pptx`, `.ppt`, `.pdf`, `.docx`, `.doc`, `.html`）：
- 两段式：Read 取文本 + vision-reader 取视觉元素

**Markdown**：文本优先，按需读取图片

如未配置 `vision-reader`（`.opencode/agents/vision-reader.md` 不存在），Agent 跳过视觉处理。

配置方式：`.\config_vision_reader.ps1 <知识库路径>`

## 文件排除规则

知识库根目录的 `.wiki_ignore` 文件定义了被排除的文件和目录。
格式类似 `.gitignore`：每行一个模式，`#` 开头的行为注释。

### 默认排除项
- `.opencode/` — skills 配置目录
- `.wiki/` — wiki 内容本身
- `.git/` — 版本控制
- `AGENTS.md` — 知识库配置文件
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

## 用户偏好

<!-- 用户可以在此添加个人偏好 -->

## 自定义配置

<!-- 用户可以在此添加自定义配置 -->
'@
         
        Set-Content -Path $AgentsFile -Value $Content -Encoding UTF8
        Write-Success-Message "创建默认 AGENTS.md: $AgentsFile"
    }
}

# === Migration functions ===
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
    )

    foreach ($Dir in $Dirs) {
        if (Test-Path $Dir) {
            $Item = Get-Item $Dir -Force
            if (-not ($Item.Attributes -band [System.IO.FileAttributes]::Hidden)) {
                Set-ItemProperty -Path $Dir -Name Attributes -Value ($Item.Attributes -bor [System.IO.FileAttributes]::Hidden)
                Write-Info-Message "已设置隐藏属性: $Dir"
            }
        }
    }
}

# === Update functions ===
function Update-Skills {
    param([string]$TargetDir)

    $SkillsDir = Join-Path $TargetDir ".opencode\skills"
    New-Item -ItemType Directory -Path $SkillsDir -Force | Out-Null

    $Skills = @("wiki-init", "wiki-ingest", "wiki-query", "wiki-lint", "wiki-update", "wiki-prune", "wiki-capture", "wiki-backup")
    $Updated = 0

    foreach ($Skill in $Skills) {
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
}

function Update-AgentsFile {
    param([string]$TargetDir)

    $AgentsFile = Join-Path $TargetDir "AGENTS.md"
    $TemplateFile = Join-Path $TemplatesSource "AGENTS.md.tmpl"

    if (Test-Path $TemplateFile) {
        Merge-AgentsFile -OldFile $AgentsFile -NewTemplate $TemplateFile -OutputFile $AgentsFile
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

## 文件排除规则

知识库根目录的 `.wiki_ignore` 文件定义了被排除的文件和目录。
格式类似 `.gitignore`：每行一个模式，`#` 开头的行为注释。

### 默认排除项
- `.opencode/` — skills 配置目录
- `.wiki/` — wiki 内容本身
- `.git/` — 版本控制
- `AGENTS.md` — 知识库配置文件
- `output/` — 用户自产文件（展示文档、报告等），不会被作为源文件处理

### 对技能的影响
所有扫描 raw sources 的技能在扫描文件前必须读取 `.wiki_ignore` 并按规则排除。

## 用户偏好

<!-- 用户可以在此添加个人偏好 -->

## 自定义配置

<!-- 用户可以在此添加自定义配置 -->
'@
        $DefaultTemplate = [System.IO.Path]::GetTempFileName()
        Set-Content -Path $DefaultTemplate -Value $Content -Encoding UTF8
        Merge-AgentsFile -OldFile $AgentsFile -NewTemplate $DefaultTemplate -OutputFile $AgentsFile
        Remove-Item $DefaultTemplate -Force
    }
}

function Update-Install {
    param([string]$TargetDir)

    Write-Host ""

    Invoke-MigrateOldStructure -TargetDir $TargetDir

    Write-Host ""
    Write-Info-Message "更新安装将执行以下操作："
    Write-Info-Message "  (1) 更新 skills — 从本仓库同步最新 skill 文件"
    Write-Info-Message "  (2) 更新 AGENTS.md — 从模板更新，保留您的用户偏好和自定义配置"
    Write-Info-Message "  (3) 更新 .wiki_ignore — 从模板更新，保留用户自定义规则"
    Write-Info-Message "  (4) 配置备份根目录"
    Write-Host ""

    if (Invoke-PromptUser "Step (1/4): 是否更新 skills？（将覆盖现有 skill 文件）") {
        Update-Skills -TargetDir $TargetDir
    } else {
        Write-Info-Message "已跳过更新 skills"
    }

    if (Invoke-PromptUser "Step (2/4): 是否更新 AGENTS.md？（模板章节将刷新，用户偏好和自定义配置章节将保留）") {
        Update-AgentsFile -TargetDir $TargetDir
    } else {
        Write-Info-Message "已跳过更新 AGENTS.md"
    }

    if (Invoke-PromptUser "Step (3/4): 是否更新 .wiki_ignore？（默认规则将刷新，用户自定义规则将保留）") {
        Merge-WikiIgnore -TargetDir $TargetDir
    } else {
        Write-Info-Message "已跳过更新 .wiki_ignore"
    }

    if (Invoke-PromptUser "Step (4/4): 是否修改备份根目录？") {
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
    Write-Host ""
    Write-Host "3. 如果知识库已有文件，运行批量初始化："
    Write-Host "   /wiki-init"
    Write-Host ""
    Write-Host "4. 或者添加新文件后运行增量处理："
    Write-Host "   /wiki-ingest"
    Write-Host ""
    Write-Host "详细文档请参考 README.md"
}

function Invoke-BackupConfig {
    param([string]$TargetDir)

    if ($Force) {
        $BackupScript = Join-Path $TargetDir ".opencode\skills\wiki-backup\backup.ps1"
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
    $BackupPs1 = Join-Path $TargetDir ".opencode\skills\wiki-backup\backup.ps1"
    if (Test-Path $BackupPs1) {
        $Content = Get-Content $BackupPs1 -Raw
        $Content = $Content -replace '(?<=^\$script:BackupRoot = ").*(?=")', $BackupRoot.Replace('\', '\\')
        Set-Content -Path $BackupPs1 -Value $Content -Encoding UTF8
        Write-Success-Message "已配置备份根目录: $BackupRoot"
    } else {
        Write-Warning-Message "找不到 backup.ps1，跳过备份配置"
    }

    # Write into backup.sh (if present)
    $BackupSh = Join-Path $TargetDir ".opencode\skills\wiki-backup\backup.sh"
    if (Test-Path $BackupSh) {
        $Content = Get-Content $BackupSh -Raw
        $Content = $Content -replace '(?<=^BACKUP_ROOT=").*(?=")', $BackupRoot.Replace('\', '/')
        Set-Content -Path $BackupSh -Value $Content -Encoding UTF8
        Write-Success-Message "已配置 backup.sh 备份根目录"
    }
}

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

    Write-Info-Message "开始安装 LLM Wikier..."

    New-WikiDirectory
    New-IndexFile
    New-LogFile
    New-ProcessedFile
    New-WikiIgnoreFile
    New-OutputDirectory
    New-SkillsDirectory
    New-AgentsFile

    Invoke-BackupConfig -TargetDir $TargetDir

    Set-HiddenAttributes -TargetDir $TargetDir

    Write-CompletionMessage

    Invoke-VisionReaderConfig -TargetDir $TargetDir
}
