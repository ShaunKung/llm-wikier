param(
    [switch]$Auto,
    [switch]$Manual,
    [string]$Root = "",
    [switch]$DryRun
)

# === Configuration (set by installer) ===
$script:BackupRoot = "__BACKUP_ROOT__"

# === Script location → KB root detection ===
$ScriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path
$KbDir = $null
try {
    $KbDir = (Resolve-Path "$ScriptDir\..\..\..").Path
} catch {
    $KbDir = $null
}

# === Defaults ===
$Mode = if ($Auto) { "auto" } else { "manual" }

# === Resolve backup root ===
if (-not [string]::IsNullOrEmpty($Root)) {
    $script:BackupRoot = $Root
}

if ($script:BackupRoot -eq "__BACKUP_ROOT__") {
    $script:BackupRoot = "$HOME\.knowledge_base"
}

# === Validate KB directory ===
if ([string]::IsNullOrEmpty($KbDir) -or -not (Test-Path $KbDir)) {
    Write-Host "[错误] 无法定位知识库目录。脚本不在预期的安装路径中。" -ForegroundColor Red
    Write-Host "请使用 -Root 参数显式指定备份根目录，或确认脚本位于 .opencode\skills\wiki-backup\ 或 .claude\skills\wiki-backup\ 下"
    exit 1
}

$HasWiki = Test-Path (Join-Path $KbDir ".wiki")
$HasAgents = Test-Path (Join-Path $KbDir "AGENTS.md")
if (-not $HasWiki -and -not $HasAgents) {
    Write-Host "[错误] 目录似乎不是有效的知识库：$KbDir" -ForegroundColor Red
    exit 1
}

# === Resolve KB folder name (spaces → underscores) ===
$KbFolderName = (Split-Path $KbDir -Leaf) -replace ' ', '_'

# === Backup target directory ===
$BackupDir = Join-Path $script:BackupRoot "backup" $KbFolderName

# === Auto mode: check for today's backup ===
if ($Mode -eq "auto") {
    $Today = (Get-Date).ToString("yyyy-MM-dd")
    $Existing = Get-ChildItem -Path $BackupDir -Filter "${Today}_*" -ErrorAction SilentlyContinue
    if ($Existing) {
        exit 0
    }
}

# === Ensure target directory exists ===
New-Item -ItemType Directory -Path $BackupDir -Force | Out-Null

# === Build timestamp and filename ===
$Timestamp = (Get-Date).ToString("yyyy-MM-dd_HH-mm")
$ArchiveName = "${Timestamp}_${KbFolderName}.zip"
$ArchivePath = Join-Path $BackupDir $ArchiveName

# === Dry run ===
if ($DryRun) {
    Write-Host "备份根目录: $script:BackupRoot"
    Write-Host "知识库目录: $KbDir"
    Write-Host "输出文件: $ArchivePath"
    Write-Host "包含内容:"
    Write-Host "  - .wiki/"
    Write-Host "  - AGENTS.md"
    Write-Host "  - CLAUDE.md（如存在）"
    Write-Host "  - .wiki_ignore"
    exit 0
}

# === Collect existing backup targets ===
$Targets = @()
if (Test-Path (Join-Path $KbDir ".wiki")) { $Targets += ".wiki" }
if (Test-Path (Join-Path $KbDir "AGENTS.md")) { $Targets += "AGENTS.md" }
if (Test-Path (Join-Path $KbDir "CLAUDE.md")) { $Targets += "CLAUDE.md" }
if (Test-Path (Join-Path $KbDir ".wiki_ignore")) { $Targets += ".wiki_ignore" }

if ($Targets.Count -eq 0) {
    Write-Host "[错误] 没有可备份的内容" -ForegroundColor Red
    exit 1
}

# === Create archive ===
$PushLocation = Get-Location
try {
    Set-Location $KbDir
    Compress-Archive -Path $Targets -DestinationPath $ArchivePath -Force
} finally {
    Set-Location $PushLocation
}
