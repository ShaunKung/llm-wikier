#!/usr/bin/env pwsh

param(
    [Parameter(Mandatory=$true, Position=0)]
    [string]$TargetDir,

    [switch]$Force,
    [switch]$Help
)

$ScriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path

function Write-Error-Message { param([string]$Message) Write-Host "[错误] " -ForegroundColor Red -NoNewline; Write-Host $Message }
function Write-Success-Message { param([string]$Message) Write-Host "[成功] " -ForegroundColor Green -NoNewline; Write-Host $Message }
function Write-Info-Message { param([string]$Message) Write-Host "[信息] " -ForegroundColor Blue -NoNewline; Write-Host $Message }
function Write-Warning-Message { param([string]$Message) Write-Host "[警告] " -ForegroundColor Yellow -NoNewline; Write-Host $Message }

$LibPs1 = Join-Path $ScriptDir "lib\common.ps1"
if (Test-Path $LibPs1) {
    . $LibPs1
}

# === Locate opencode CLI ===
function Find-OpencodeCli {
    $candidates = @(
        'opencode',
        "$env:LOCALAPPDATA\OpenCode\opencode-cli.exe",
        "$env:APPDATA\npm\opencode.cmd",
        "$env:APPDATA\npm\opencode",
        [System.IO.Path]::Combine($env:USERPROFILE, 'AppData', 'Local', 'OpenCode', 'opencode-cli.exe')
    )
    foreach ($candidate in $candidates) {
        $cmd = Get-Command $candidate -ErrorAction SilentlyContinue
        if ($cmd) { return $cmd.Source }
    }
    return $null
}

$script:OpencodeCli = Find-OpencodeCli

# === Read model from opencode config (covers Desktop app users) ===
function Read-OpencodeConfigModel {
    $configCandidates = @(
        Join-Path $HOME ".config\opencode\opencode.json"
        Join-Path $HOME ".config\opencode\opencode.jsonc"
        Join-Path $HOME ".config\opencode\opencode.yml"
        Join-Path $HOME ".config\opencode\opencode.yaml"
    )
    if ($TargetDir) {
        $configCandidates += Join-Path $TargetDir "opencode.json"
        $configCandidates += Join-Path $TargetDir "opencode.jsonc"
    }
    foreach ($cfg in $configCandidates) {
        if (Test-Path $cfg) {
            try {
                $content = Get-Content -Path $cfg -Raw -ErrorAction Stop
                $json = $content | ConvertFrom-Json -ErrorAction Stop
                if ($json.model -and $json.model -match '/') {
                    return $json.model
                }
            } catch {
                continue
            }
        }
    }
    return $null
}

function Show-Help {
    Write-Host "LLM Wikier vision-reader 配置脚本"
    Write-Host ""
    Write-Host "用法: .\config_vision_reader.ps1 <目标知识库路径> [选项]"
    Write-Host ""
    Write-Host "参数:"
    Write-Host "  <目标知识库路径>    已安装 LLM Wikier 的知识库目录路径"
    Write-Host ""
    Write-Host "选项:"
    Write-Host "  -Force              更新模式跳过确认"
    Write-Host "  -Help               显示此帮助信息"
    Write-Host ""
    Write-Host "示例:"
    Write-Host "  .\config_vision_reader.ps1 'C:\Users\用户\my-knowledge-base'"
    Write-Host "  .\config_vision_reader.ps1 'C:\path\to\knowledge-base' -Force"
}

function Invoke-PromptUser {
    param([string]$Message)

    if ($Force) { return $true }

    Write-Host "[询问] " -ForegroundColor Yellow -NoNewline
    Write-Host "$Message [Y/n] " -NoNewline
    $Response = Read-Host

    return ($Response -notmatch '^[nN](o|O)?$')
}

function Read-UserInput {
    param([string]$Prompt)

    Write-Host "[输入] " -ForegroundColor Blue -NoNewline
    Write-Host "${Prompt}: " -NoNewline
    return (Read-Host).Trim()
}

# === Validate target dir ===
function Test-TargetDir {
    if (-not (Test-Path $TargetDir)) {
        Write-Error-Message "目标目录不存在: $TargetDir"
        exit 1
    }

    $TargetDir = (Resolve-Path $TargetDir).Path
    Write-Info-Message "目标知识库路径: $TargetDir"

    if (Get-Command Test-ValidKbDir -ErrorAction SilentlyContinue) {
        if (-not (Test-ValidKbDir $TargetDir)) {
            Write-Error-Message "目标目录不是有效的 LLM Wikier 知识库（缺少 AGENTS.md 或 .wiki/ 目录）"
            Write-Info-Message "请先运行 install.ps1 安装 LLM Wikier"
            exit 1
        }
    } else {
        $AgentsFile = Join-Path $TargetDir "AGENTS.md"
        $WikiDir = Join-Path $TargetDir ".wiki"
        $OldWikiDir = Join-Path $TargetDir "wiki"
        if (-not (Test-Path $AgentsFile) -or (-not (Test-Path $WikiDir) -and -not (Test-Path $OldWikiDir))) {
            Write-Error-Message "目标目录不是有效的 LLM Wikier 知识库（缺少 AGENTS.md 或 .wiki/ 目录）"
            Write-Info-Message "请先运行 install.ps1 安装 LLM Wikier"
            exit 1
        }
    }
}

# === Check existing config ===
function Test-ExistingConfig {
    $ConfigFile = Join-Path $TargetDir ".opencode\agents\vision-reader.md"

    if (Test-Path $ConfigFile) {
        Write-Info-Message "检测到已有 vision-reader 配置"
        Write-Host ""
        Write-Host "当前配置:"
        Write-Host "----------------------------------------"
        Get-Content $ConfigFile
        Write-Host "----------------------------------------"
        Write-Host ""

        if (-not (Invoke-PromptUser "是否更新此配置？")) {
            Write-Info-Message "已取消，保留现有配置"
            exit 0
        }
        Write-Info-Message "将更新现有配置"
    }
}

# === Parse opencode models ===
function Invoke-OpencodeModels {
    if (-not $script:OpencodeCli) {
        return @()
    }

    Write-Info-Message "正在获取可用 provider 和模型列表..."

    try {
        $Output = & $script:OpencodeCli models 2>&1
    } catch {
        Write-Warning-Message "无法执行 '$($script:OpencodeCli) models'"
        return @()
    }

    if ($LASTEXITCODE -ne 0 -and $LASTEXITCODE -ne $null) {
        Write-Warning-Message "'$($script:OpencodeCli) models' 执行失败，将切换到手动配置"
        return @()
    }

    $Models = @()
    foreach ($Line in $Output) {
        $Trimmed = "$Line".Trim()
        if ($Trimmed -ne '') {
            $Models += $Trimmed
        }
    }

    return $Models
}

# === Interactive selection ===
function Select-ModelOpencode {
    if (-not $script:OpencodeCli) {
        $configModel = Read-OpencodeConfigModel
        if ($configModel) {
            Write-Info-Message "从 opencode 配置文件中检测到模型: $configModel"
            return $configModel
        }
        Write-Warning-Message "未找到 opencode CLI 或配置文件，将切换到手动配置"
        return $null
    }

    $Models = Invoke-OpencodeModels

    if ($Models.Count -eq 0) {
        Write-Warning-Message "未检测到可用模型，将切换到手动配置"
        return $null
    }

    Write-Host ""
    Write-Info-Message "检测到以下可用模型:"
    Write-Host ""

    for ($i = 0; $i -lt $Models.Count; $i++) {
        $Num = $i + 1
        Write-Host ("  [{0,2}] {1}" -f $Num, $Models[$i])
    }

    Write-Host ""
    Write-Host "  [ 0] 手动输入 provider 和 model"

    while ($true) {
        Write-Host "[选择] " -ForegroundColor Blue -NoNewline
        Write-Host "请输入序号选择模型 (0-$($Models.Count)): " -NoNewline
        $Choice = Read-Host

        if ($Choice -eq "0") {
            return $null
        }

        $Idx = [int]::TryParse($Choice, [ref]$null)
        if ([int]::TryParse($Choice, [ref]$Idx)) {
            if ($Idx -ge 1 -and $Idx -le $Models.Count) {
                $Selected = $Models[$Idx - 1]
                Write-Success-Message "已选择模型: $Selected"
                return $Selected
            }
        }

        Write-Error-Message "无效选择，请重试"
    }
}

# === Manual config ===
function Invoke-ManualConfig {
    Write-Info-Message "手动配置 vision-reader subagent:"
    Write-Host ""

    $script:Provider = ""
    $script:ModelId = ""
    $script:ApiKeyEnv = ""

    while ([string]::IsNullOrWhiteSpace($script:Provider)) {
        $script:Provider = Read-UserInput "Provider ID (如 anthropic, openai, deepseek)"
        if ([string]::IsNullOrWhiteSpace($script:Provider)) {
            Write-Error-Message "Provider 不能为空"
        }
    }

    while ([string]::IsNullOrWhiteSpace($script:ModelId)) {
        $script:ModelId = Read-UserInput "Model ID (如 claude-sonnet-4-20250514, gpt-4o)"
        if ([string]::IsNullOrWhiteSpace($script:ModelId)) {
            Write-Error-Message "Model ID 不能为空"
        }
    }

    Write-Host ""
    $script:ApiKeyEnv = Read-UserInput "API Key 环境变量名 (如 ANTHROPIC_API_KEY，如已全局配置可留空)"
    Write-Host ""

    $Selected = "$script:Provider/$script:ModelId"
    Write-Success-Message "已配置模型: $Selected"
    return $Selected
}

# === Write config ===
function Write-AgentConfig {
    param([string]$Model)

    $ConfigDir = Join-Path $TargetDir ".opencode\agents"
    $ConfigFile = Join-Path $ConfigDir "vision-reader.md"

    if (-not (Test-Path $ConfigDir)) {
        New-Item -ItemType Directory -Path $ConfigDir -Force | Out-Null
    }

    $ExtraFields = ""
    if ($script:ApiKeyEnv) {
        $ExtraFields = @"

provider:
  ${script:Provider}:
    options:
      apiKey: "{env:$script:ApiKeyEnv}"
"@
    }

    $Content = @"
---
description: 视觉内容读取器，读取文件中的图片、图表、截图、幻灯片、文档排版等视觉元素，转化为文字描述
mode: subagent
model: ${Model}
permission:
  edit: deny
  bash: deny
  task: deny
  webfetch: deny
  skill: deny${ExtraFields}
---
你是一个视觉内容读取器。你的职责是读取文件中的视觉元素（图片、图表、截图、幻灯片、页面排版等），并将视觉内容转化为文字描述。

## 核心职责
- 只描述视觉元素（图片、图表、照片、插图、截图、幻灯片视觉内容、排版布局等）
- 不要重复已经由主 agent 处理的纯文本内容
- **兜底规则**：如果发现文档中文本提取明显不完整（如幻灯片缺失文字、表格数据丢失、图表中的数据标签等），请一并补充关键文本信息

## 输出格式
对每个视觉元素：

\`\`\`
### [图片/图表/截图 序号]
**类型**: [图表/照片/截图/插图/排版]
**描述**: [视觉内容的文字描述]
**关键信息**: [图表数据、照片中的人物/场景、截图中的UI元素、幻灯片主题等]
\`\`\`

主 agent 会通过文件路径告知你需要读取的文件，请直接读取并返回描述。
"@

    $Content | Set-Content -Path $ConfigFile -Encoding UTF8
    Write-Success-Message "已保存配置: $ConfigFile"
}

function Write-Completion {
    Write-Host ""
    Write-Host "======================================"
    Write-Success-Message "vision-reader subagent 配置完成！"
    Write-Host "======================================"
    Write-Host ""
    Write-Host "模型: $SelectedModel"
    if ($script:ApiKeyEnv) {
        Write-Host "API Key: 环境变量 $script:ApiKeyEnv"
    }
    Write-Host ""
    Write-Host "配置文件: $TargetDir\.opencode\agents\vision-reader.md"
    Write-Host ""
    Write-Host "提示: 你可能需要将此文件添加到 .gitignore（如果包含敏感配置）:"
    Write-Host "  echo '.opencode/agents/vision-reader.md' >> '$TargetDir\.gitignore'"
    Write-Host ""
    Write-Host "配置完成后，使用知识库时 Agent 会自动在遇到视觉内容时调用 vision-reader。"
    Write-Host ""
}

if ($Help) {
    Show-Help
    exit 0
}

Test-TargetDir
Test-ExistingConfig

Write-Host ""
Write-Info-Message "开始配置 vision-reader subagent..."
Write-Host ""

$SelectedModel = Select-ModelOpencode
if (-not $SelectedModel) {
    $SelectedModel = Invoke-ManualConfig
}

if ([string]::IsNullOrWhiteSpace($SelectedModel) -or $SelectedModel -eq "/") {
    Write-Error-Message "配置不完整（模型信息缺失），未保存"
    exit 1
}

Write-AgentConfig -Model $SelectedModel
Write-Completion
