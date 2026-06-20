# Task 2 Report: lib/common.ps1 — 链接文件基础函数（PowerShell 版）

## Summary

Added link file (`.url`) support to `lib/common.ps1`, mirroring the bash implementation from Task 1. Four new functions and two updates to existing functions.

## Changes Made

### New Functions

1. **`Get-LinkExtensions`** (line 63-65) — Returns `@("url")`, the list of link file extensions recognized by the install scripts.

2. **`Test-LinkFile`** (line 94-101) — Checks whether a file path has a `.url` extension (case-insensitive), returning `$true`/`$false`.

3. **`Get-UrlFromLinkFile`** (line 103-118) — Parses a `.url` file in `[InternetShortcut]` INI format and extracts the `URL=` value. Returns `$null` if the file doesn't exist or no URL is found. Uses case-insensitive regex `^[Uu][Rr][Ll]=(.+)$`.

### Updated Functions

4. **`Test-SupportedFile`** (line 120-124) — Now also calls `Test-LinkFile`, so `.url` files are recognized as supported sources.

5. **`Find-RawSources`** (line 196) — Now includes `Get-LinkExtensions` in the extension list, so `.url` files are scanned and collected alongside text and image files.

## Verification

- PowerShell syntax reviewed manually — all functions follow existing patterns (param blocks, `-contains`, regex matching, `SilentlyContinue`)
- Function organization: new functions placed alongside their text/image/office counterparts
- Consistency with bash `common.sh`: `is_link_file()` ↔ `Test-LinkFile`, `parse_url_from_link_file()` ↔ `Get-UrlFromLinkFile`

## No Concerns
