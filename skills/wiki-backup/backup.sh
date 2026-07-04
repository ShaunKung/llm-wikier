#!/bin/bash

set -e

# === Configuration (set by installer) ===
BACKUP_ROOT="__BACKUP_ROOT__"

# === Script location → KB root detection ===
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
KB_DIR="$(cd "$SCRIPT_DIR/../../.." 2>/dev/null && pwd || echo "")"

# === Defaults ===
MODE="manual"
CUSTOM_ROOT=""

# === Color output ===
RED='\033[0;31m'
NC='\033[0m'

print_error() {
    echo -e "${RED}[错误]${NC} $1" >&2
}

# === Parse arguments ===
while [[ $# -gt 0 ]]; do
    case "$1" in
        --auto) MODE="auto"; shift ;;
        --manual) MODE="manual"; shift ;;
        --root) CUSTOM_ROOT="$2"; shift 2 ;;
        --dry-run) DRY_RUN=true; shift ;;
        *) print_error "未知参数: $1"; exit 1 ;;
    esac
done

# === Resolve backup root ===
if [[ -n "$CUSTOM_ROOT" ]]; then
    BACKUP_ROOT="$CUSTOM_ROOT"
fi

if [[ "$BACKUP_ROOT" == "__BACKUP_ROOT__" ]]; then
    BACKUP_ROOT="$HOME/.knowledge_base"
fi

# === Validate KB directory ===
if [[ ! -d "$KB_DIR" ]]; then
    print_error "无法定位知识库目录。脚本不在预期的安装路径中。"
    echo "请使用 --root 参数显式指定备份根目录，或确认脚本位于 .opencode/skills/wiki-backup/、.claude/skills/wiki-backup/ 或 .agents/skills/wiki-backup/ 下" >&2
    exit 1
fi

if [[ ! -d "$KB_DIR/.wiki" && ! -f "$KB_DIR/AGENTS.md" ]]; then
    print_error "目录似乎不是有效的知识库：$KB_DIR"
    exit 1
fi

# === Resolve KB folder name (spaces → underscores) ===
KB_FOLDER_NAME="$(basename "$KB_DIR" | sed 's/ /_/g')"

# === Backup target directory ===
BACKUP_DIR="$BACKUP_ROOT/backup/$KB_FOLDER_NAME"

# === Auto mode: check for today's backup ===
if [[ "$MODE" == "auto" ]]; then
    TODAY="$(date +"%Y-%m-%d")"
    if ls "$BACKUP_DIR/${TODAY}_"* >/dev/null 2>&1; then
        exit 0
    fi
fi

# === Ensure target directory exists ===
mkdir -p "$BACKUP_DIR"

# === Build timestamp and filename ===
TIMESTAMP="$(date +"%Y-%m-%d_%H-%M")"
ARCHIVE_NAME="${TIMESTAMP}_${KB_FOLDER_NAME}.tar.gz"
ARCHIVE_PATH="$BACKUP_DIR/$ARCHIVE_NAME"

# === Dry run ===
if [[ "$DRY_RUN" == "true" ]]; then
    echo "备份根目录: $BACKUP_ROOT"
    echo "知识库目录: $KB_DIR"
    echo "输出文件: $ARCHIVE_PATH"
    echo "包含内容:"
    echo "  - .wiki/"
    echo "  - AGENTS.md"
    echo "  - CLAUDE.md（如存在）"
    echo "  - .wiki_ignore"
    exit 0
fi

# === Create archive ===
cd "$KB_DIR"

# Collect existing backup targets
TARGETS=""
for item in .wiki AGENTS.md CLAUDE.md .wiki_ignore; do
    if [[ -e "$item" ]]; then
        TARGETS="$TARGETS $item"
    fi
done

if [[ -z "$TARGETS" ]]; then
    print_error "没有可备份的内容"
    exit 1
fi

tar -czf "$ARCHIVE_PATH" $TARGETS
