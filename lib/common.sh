#!/bin/bash

LIB_COMMON_SH_LOADED=true

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

print_error() {
    echo -e "${RED}[错误]${NC} $1"
}

print_success() {
    echo -e "${GREEN}[成功]${NC} $1"
}

print_info() {
    echo -e "${BLUE}[信息]${NC} $1"
}

print_warning() {
    echo -e "${YELLOW}[警告]${NC} $1"
}

is_valid_kb_dir() {
    local dir="$1"
    
    if [[ ! -d "$dir" ]]; then
        return 1
    fi
    
    local agents_file="$dir/AGENTS.md"
    local wiki_dir="$dir/wiki"
    
    if [[ ! -f "$agents_file" || ! -d "$wiki_dir" ]]; then
        return 1
    fi
    
    return 0
}

get_text_extensions() {
    echo "md txt json yaml yml csv xml html rst org tex py js ts java cpp c go rs rb php css scss sql sh bash zsh conf ini log"
}

get_image_extensions() {
    echo "png jpg jpeg gif webp svg bmp"
}

is_text_file() {
    local file="$1"
    local ext="${file##*.}"
    ext=$(echo "$ext" | tr '[:upper:]' '[:lower:]')
    
    local text_exts=$(get_text_extensions)
    for text_ext in $text_exts; do
        if [[ "$ext" == "$text_ext" ]]; then
            return 0
        fi
    done
    
    return 1
}

is_image_file() {
    local file="$1"
    local ext="${file##*.}"
    ext=$(echo "$ext" | tr '[:upper:]' '[:lower:]')
    
    local image_exts=$(get_image_extensions)
    for image_ext in $image_exts; do
        if [[ "$ext" == "$image_ext" ]]; then
            return 0
        fi
    done
    
    return 1
}

is_supported_file() {
    local file="$1"
    is_text_file "$file" || is_image_file "$file"
}

should_exclude_dir() {
    local dir="$1"
    
    local dir_name=$(basename "$dir")
    
    case "$dir_name" in
        wiki|.opencode|.git|node_modules|.venv|__pycache__|.idea|.vscode)
            return 0
            ;;
    esac
    
    return 1
}

find_raw_sources() {
    local kb_dir="$1"
    local find_cmd="find \"$kb_dir\" -type f"
    
    local text_exts=$(get_text_extensions)
    local image_exts=$(get_image_extensions)
    local all_exts="$text_exts $image_exts"
    
    local name_args=""
    for ext in $all_exts; do
        if [[ -z "$name_args" ]]; then
            name_args="-name \"*.$ext\""
        else
            name_args="$name_args -o -name \"*.$ext\""
        fi
    done
    
    eval "$find_cmd \\( $name_args \\)" | while read -r file; do
        local rel_path="${file#$kb_dir/}"
        local dir_path=$(dirname "$rel_path")
        
        local skip=false
        IFS='/' read -ra parts <<< "$dir_path"
        for part in "${parts[@]}"; do
            if should_exclude_dir "$part"; then
                skip=true
                break
            fi
        done
        
        if [[ "$skip" == "false" ]]; then
            echo "$rel_path"
        fi
    done
}

calculate_file_hash() {
    local file="$1"
    
    if command -v sha256sum &> /dev/null; then
        sha256sum "$file" | cut -d' ' -f1
    elif command -v shasum &> /dev/null; then
        shasum -a 256 "$file" | cut -d' ' -f1
    else
        md5sum "$file" | cut -d' ' -f1
    fi
}

get_current_timestamp() {
    date -u +"%Y-%m-%dT%H:%M:%SZ"
}

get_current_date() {
    date +"%Y-%m-%d"
}

read_processed_file() {
    local kb_dir="$1"
    local processed_file="$kb_dir/.wiki-processed"
    
    if [[ ! -f "$processed_file" ]]; then
        echo '{"version": 1, "entries": []}'
        return
    fi
    
    cat "$processed_file"
}

is_file_processed() {
    local kb_dir="$1"
    local file_path="$2"
    
    local processed=$(read_processed_file "$kb_dir")
    local rel_path="${file_path#$kb_dir/}"
    
    if echo "$processed" | grep -q "\"path\": \"$rel_path\""; then
        return 0
    fi
    
    return 1
}

get_file_hash_from_record() {
    local kb_dir="$1"
    local file_path="$2"
    local rel_path="${file_path#$kb_dir/}"
    
    local processed=$(read_processed_file "$kb_dir")
    echo "$processed" | grep -A1 "\"path\": \"$rel_path\"" | grep "\"hash\"" | sed 's/.*"hash": "\([^"]*\)".*/\1/'
}

add_to_processed() {
    local kb_dir="$1"
    local file_path="$2"
    local hash="$3"
    
    local processed_file="$kb_dir/.wiki-processed"
    local rel_path="${file_path#$kb_dir/}"
    local timestamp=$(get_current_timestamp)
    
    local processed=$(read_processed_file "$kb_dir")
    
    local new_entry="{\"path\": \"$rel_path\", \"hash\": \"$hash\", \"processed\": \"$timestamp\"}"
    
    if command -v jq &> /dev/null; then
        echo "$processed" | jq ".entries += [$new_entry]" > "$processed_file"
    else
        local entries=$(echo "$processed" | sed 's/.*"entries": \[/\[/' | sed 's/\] *}.*/\]/')
        if [[ "$entries" == "[]" ]]; then
            echo "{\"version\": 1, \"entries\": [$new_entry]}" > "$processed_file"
        else
            echo "{\"version\": 1, \"entries\": $entries, $new_entry]}" > "$processed_file"
        fi
    fi
}

append_to_log() {
    local kb_dir="$1"
    local operation="$2"
    local target="$3"
    local details="$4"
    
    local log_file="$kb_dir/wiki/log.md"
    local timestamp=$(date +"%Y-%m-%d %H:%M")
    
    {
        echo ""
        echo "## [$timestamp] $operation | $target"
        echo ""
        echo "$details"
        echo ""
        echo "---"
    } >> "$log_file"
}
