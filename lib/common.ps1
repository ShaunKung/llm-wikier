#!/usr/bin/env pwsh

$script:LibCommonPs1Loaded = $true

function Write-ErrorMessage {
    param([string]$Message)
    Write-Host "[错误] " -ForegroundColor Red -NoNewline
    Write-Host $Message
}

function Write-SuccessMessage {
    param([string]$Message)
    Write-Host "[成功] " -ForegroundColor Green -NoNewline
    Write-Host $Message
}

function Write-InfoMessage {
    param([string]$Message)
    Write-Host "[信息] " -ForegroundColor Blue -NoNewline
    Write-Host $Message
}

function Write-WarningMessage {
    param([string]$Message)
    Write-Host "[警告] " -ForegroundColor Yellow -NoNewline
    Write-Host $Message
}

function Test-ValidKbDir {
    param([string]$Dir)
    
    if (-not (Test-Path $Dir)) {
        return $false
    }
    
    $AgentsFile = Join-Path $Dir "AGENTS.md"
    $WikiDir = Join-Path $Dir "wiki"
    
    if (-not (Test-Path $AgentsFile) -or -not (Test-Path $WikiDir)) {
        return $false
    }
    
    return $true
}

function Get-TextExtensions {
    return @("md", "txt", "json", "yaml", "yml", "csv", "xml", "html", "rst", "org", "tex", "py", "js", "ts", "java", "cpp", "c", "go", "rs", "rb", "php", "css", "scss", "sql", "sh", "bash", "zsh", "conf", "ini", "log")
}

function Get-ImageExtensions {
    return @("png", "jpg", "jpeg", "gif", "webp", "svg", "bmp")
}

function Test-TextFile {
    param([string]$File)
    
    $Ext = [System.IO.Path]::GetExtension($File).TrimStart('.').ToLower()
    $TextExts = Get-TextExtensions
    
    return $TextExts -contains $Ext
}

function Test-ImageFile {
    param([string]$File)
    
    $Ext = [System.IO.Path]::GetExtension($File).TrimStart('.').ToLower()
    $ImageExts = Get-ImageExtensions
    
    return $ImageExts -contains $Ext
}

function Test-SupportedFile {
    param([string]$File)
    
    return (Test-TextFile $File) -or (Test-ImageFile $File)
}

function Test-ExcludeDir {
    param([string]$Dir)
    
    $DirName = Split-Path $Dir -Leaf
    
    $ExcludeDirs = @("wiki", ".opencode", ".git", "node_modules", ".venv", "__pycache__", ".idea", ".vscode")
    
    return $ExcludeDirs -contains $DirName
}

function Find-RawSources {
    param([string]$KbDir)
    
    $AllExts = Get-TextExtensions + Get-ImageExtensions
    $Sources = @()
    
    foreach ($Ext in $AllExts) {
        $Files = Get-ChildItem -Path $KbDir -Filter "*.$Ext" -Recurse -File -ErrorAction SilentlyContinue
        
        foreach ($File in $Files) {
            $RelPath = $File.FullName.Substring($KbDir.Length).TrimStart('\', '/')
            $DirPath = Split-Path $RelPath -Parent
            
            $Skip = $false
            $Parts = $DirPath -split '[\\/]'
            
            foreach ($Part in $Parts) {
                if (Test-ExcludeDir $Part) {
                    $Skip = $true
                    break
                }
            }
            
            if (-not $Skip) {
                $Sources += $File.FullName
            }
        }
    }
    
    return $Sources
}

function Get-FileHash {
    param([string]$File)
    
    $Hash = Get-FileHash -Path $File -Algorithm SHA256 -ErrorAction SilentlyContinue
    
    if ($Hash) {
        return $Hash.Hash.ToLower()
    }
    
    $Md5Hash = Get-FileHash -Path $File -Algorithm MD5 -ErrorAction SilentlyContinue
    
    if ($Md5Hash) {
        return $Md5Hash.Hash.ToLower()
    }
    
    return $null
}

function Get-CurrentTimestamp {
    return (Get-Date).ToUniversalTime().ToString("yyyy-MM-ddTHH:mm:ssZ")
}

function Get-CurrentDate {
    return (Get-Date).ToString("yyyy-MM-dd")
}

function Read-ProcessedFile {
    param([string]$KbDir)
    
    $ProcessedFile = Join-Path $KbDir ".wiki-processed"
    
    if (-not (Test-Path $ProcessedFile)) {
        return '{"version": 1, "entries": []}'
    }
    
    return Get-Content $ProcessedFile -Raw
}

function Test-FileProcessed {
    param(
        [string]$KbDir,
        [string]$FilePath
    )
    
    $Processed = Read-ProcessedFile $KbDir
    $RelPath = $FilePath.Substring($KbDir.Length).TrimStart('\', '/').Replace('\', '/')
    
    return $Processed -match "`"path`": `"$RelPath`""
}

function Get-FileHashFromRecord {
    param(
        [string]$KbDir,
        [string]$FilePath
    )
    
    $Processed = Read-ProcessedFile $KbDir
    $RelPath = $FilePath.Substring($KbDir.Length).TrimStart('\', '/').Replace('\', '/')
    
    if ($Processed -match "`"path`": `"$RelPath`"[,\s]+`"hash`": `"([^`"]+)`"") {
        return $Matches[1]
    }
    
    return $null
}

function Add-ToProcessed {
    param(
        [string]$KbDir,
        [string]$FilePath,
        [string]$Hash
    )
    
    $ProcessedFile = Join-Path $KbDir ".wiki-processed"
    $RelPath = $FilePath.Substring($KbDir.Length).TrimStart('\', '/').Replace('\', '/')
    $Timestamp = Get-CurrentTimestamp
    
    $Processed = Read-ProcessedFile $KbDir
    
    try {
        $Json = $Processed | ConvertFrom-Json
        $NewEntry = @{
            path = $RelPath
            hash = $Hash
            processed = $Timestamp
        }
        
        $Json.entries += $NewEntry
        $Json | ConvertTo-Json -Depth 10 | Set-Content $ProcessedFile -Encoding UTF8
    }
    catch {
        $NewJson = @{
            version = 1
            entries = @(
                @{
                    path = $RelPath
                    hash = $Hash
                    processed = $Timestamp
                }
            )
        }
        
        $NewJson | ConvertTo-Json -Depth 10 | Set-Content $ProcessedFile -Encoding UTF8
    }
}

function Append-ToLog {
    param(
        [string]$KbDir,
        [string]$Operation,
        [string]$Target,
        [string]$Details
    )
    
    $LogFile = Join-Path $KbDir "wiki\log.md"
    $Timestamp = (Get-Date).ToString("yyyy-MM-dd HH:mm")
    
    $Content = @"

## [$Timestamp] $Operation | $Target

$Details

---
"@
    
    Add-Content -Path $LogFile -Value $Content -Encoding UTF8
}
