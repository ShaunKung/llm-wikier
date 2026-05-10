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
    Write-Host "  -Force              强制覆盖已存在的文件"
    Write-Host "  -Help               显示此帮助信息"
    Write-Host ""
    Write-Host "示例:"
    Write-Host "  .\install.ps1 'C:\Users\用户\my-knowledge-base'"
    Write-Host "  .\install.ps1 'C:\path\to\knowledge-base' -Force"
}

function Test-ExistingInstallation {
    $WikiDir = Join-Path $TargetDir "wiki"
    $AgentsFile = Join-Path $TargetDir "AGENTS.md"
    $SkillsDir = Join-Path $TargetDir ".opencode\skills"
    
    if ((Test-Path $WikiDir) -or (Test-Path $AgentsFile) -or (Test-Path $SkillsDir)) {
        if ($Force) {
            Write-Warning-Message "检测到已有安装，将强制覆盖"
        } else {
            Write-Error-Message "检测到已有安装，使用 -Force 强制覆盖"
            exit 1
        }
    }
}

function New-WikiDirectory {
    $WikiDir = Join-Path $TargetDir "wiki"
    New-Item -ItemType Directory -Path $WikiDir -Force | Out-Null
    Write-Success-Message "创建 wiki 目录: $WikiDir"
}

function New-IndexFile {
    $IndexFile = Join-Path $TargetDir "wiki\index.md"
    
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
    $LogFile = Join-Path $TargetDir "wiki\log.md"
    
    $Content = @'
# Wiki 操作日志

此文件记录所有 wiki 操作的历史。

---

'@
    
    Set-Content -Path $LogFile -Value $Content -Encoding UTF8
    Write-Success-Message "创建日志文件: $LogFile"
}

function New-ProcessedFile {
    $ProcessedFile = Join-Path $TargetDir ".wiki-processed"
    
    '{"version": 1, "entries": []}' | Set-Content -Path $ProcessedFile -Encoding UTF8
    Write-Success-Message "创建处理记录文件: $ProcessedFile"
}

function New-SkillsDirectory {
    $SkillsDir = Join-Path $TargetDir ".opencode\skills"
    New-Item -ItemType Directory -Path $SkillsDir -Force | Out-Null
    
    $Skills = @("wiki-init", "wiki-ingest", "wiki-query", "wiki-lint", "wiki-update", "wiki-prune", "wiki-capture")
    
    foreach ($Skill in $Skills) {
        $SrcDir = Join-Path $SkillsSource $Skill
        $DstDir = Join-Path $SkillsDir $Skill
        
        if (Test-Path $SrcDir) {
            New-Item -ItemType Directory -Path $DstDir -Force | Out-Null
            $SrcFile = Join-Path $SrcDir "SKILL.md"
            $DstFile = Join-Path $DstDir "SKILL.md"
            Copy-Item $SrcFile $DstFile -Force
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

## 知识库概述

这是一个由 LLM Wikier 管理的个人知识库。

## Wiki 结构

```
wiki/
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

## 排除目录

以下目录不会被处理：
- `wiki/`
- `.opencode/`
- `.git/`

## 工作流程

1. 用户添加新的源文件到知识库
2. 运行 `/wiki-ingest` 处理新文件
3. LLM 更新 wiki 页面、索引和日志
4. 用户可通过 `/wiki-query` 查询知识库

## 贡献指南

- 提问时尽量具体
- 定期运行 `/wiki-lint` 检查 wiki 健康状态
- 重要的查询答案可以作为新页面沉淀
'@
        
        Set-Content -Path $AgentsFile -Value $Content -Encoding UTF8
        Write-Success-Message "创建默认 AGENTS.md: $AgentsFile"
    }
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

Test-ExistingInstallation

Write-Info-Message "开始安装 LLM Wikier..."

New-WikiDirectory
New-IndexFile
New-LogFile
New-ProcessedFile
New-SkillsDirectory
New-AgentsFile

Write-CompletionMessage
