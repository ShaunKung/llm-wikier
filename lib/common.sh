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
    local wiki_dir="$dir/.wiki"
    local old_wiki_dir="$dir/wiki"
    
    if [[ ! -f "$agents_file" ]]; then
        return 1
    fi
    
    if [[ ! -d "$wiki_dir" && ! -d "$old_wiki_dir" ]]; then
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

get_office_extensions() {
    echo "pdf docx doc pptx ppt xlsx xls odt odp ods"
}

get_link_extensions() {
    echo "url"
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

is_office_file() {
    local file="$1"
    local ext="${file##*.}"
    ext=$(echo "$ext" | tr '[:upper:]' '[:lower:]')
    
    local office_exts=$(get_office_extensions)
    for office_ext in $office_exts; do
        if [[ "$ext" == "$office_ext" ]]; then
            return 0
        fi
    done
    
    return 1
}

is_link_file() {
    local file="$1"
    local ext="${file##*.}"
    ext=$(echo "$ext" | tr '[:upper:]' '[:lower:]')
    
    local link_exts=$(get_link_extensions)
    for link_ext in $link_exts; do
        if [[ "$ext" == "$link_ext" ]]; then
            return 0
        fi
    done
    
    return 1
}

parse_url_from_link_file() {
    local file="$1"
    
    if [[ ! -f "$file" ]]; then
        return 1
    fi
    
    local url
    url=$(grep -i '^URL=' "$file" | head -1 | sed 's/^[Uu][Rr][Ll]=//' | tr -d '\r')
    
    if [[ -z "$url" ]]; then
        return 1
    fi
    
    echo "$url"
    return 0
}

is_supported_file() {
    local file="$1"
    is_text_file "$file" || is_image_file "$file" || is_office_file "$file" || is_link_file "$file"
}

# DEPRECATED: 将在未来版本移除，请改用 .wiki_ignore 机制
should_exclude_dir() {
    local dir="$1"
    
    local dir_name=$(basename "$dir")
    
    case "$dir_name" in
            wiki|.wiki|.opencode|.claude|.agents|.codex|.git|node_modules|.venv|__pycache__|.idea|.vscode)
            return 0
            ;;
    esac
    
    return 1
}

read_wiki_ignore() {
    local kb_dir="$1"
    local ignore_file="$kb_dir/.wiki_ignore"
    
    if [[ ! -f "$ignore_file" ]]; then
        return
    fi
    
    while IFS= read -r line; do
        line="${line##[[:space:]]}"
        line="${line%%[[:space:]]}"
        if [[ -z "$line" || "$line" == \#* ]]; then
            continue
        fi
        echo "$line"
    done < "$ignore_file"
}

is_path_ignored() {
    local rel_path="$1"
    local pattern="$2"
    
    local filename="${rel_path##*/}"
    local clean_pattern="${pattern%/}"
    
    # Pattern: *.ext (extension match)
    if [[ "$clean_pattern" == \*.* ]]; then
        local ext="${clean_pattern#\*}"
        case "$filename" in
            *"$ext") return 0 ;;
        esac
        return 1
    fi
    
    # Pattern contains "/" — path prefix matching
    if [[ "$clean_pattern" == */* ]]; then
        case "$rel_path" in
            "$clean_pattern"/*) return 0 ;;
            "$clean_pattern")   return 0 ;;
        esac
        return 1
    fi
    
    # Pattern without "/" — component matching
    IFS='/' read -ra parts <<< "$rel_path"
    for part in "${parts[@]}"; do
        if [[ "$part" == "$clean_pattern" ]]; then
            return 0
        fi
    done
    
    return 1
}

find_raw_sources() {
    local kb_dir="$1"
    local find_cmd="find \"$kb_dir\" -type f"
    
    local text_exts=$(get_text_extensions)
    local image_exts=$(get_image_extensions)
    local link_exts=$(get_link_extensions)
    local all_exts="$text_exts $image_exts $link_exts"
    
    local name_args=""
    for ext in $all_exts; do
        if [[ -z "$name_args" ]]; then
            name_args="-name \"*.$ext\""
        else
            name_args="$name_args -o -name \"*.$ext\""
        fi
    done
    
    mapfile -t ignore_patterns < <(read_wiki_ignore "$kb_dir")
    
    eval "$find_cmd \\( $name_args \\)" | while read -r file; do
        local rel_path="${file#$kb_dir/}"
        
        local skip=false
        for pattern in "${ignore_patterns[@]}"; do
            if is_path_ignored "$rel_path" "$pattern"; then
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
    local processed_file="$kb_dir/.wiki/.wiki-processed"
    
    if [[ ! -f "$processed_file" ]]; then
        echo '{"version": 2, "entries": []}'
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
    
    local processed_file="$kb_dir/.wiki/.wiki-processed"
    local rel_path="${file_path#$kb_dir/}"
    local timestamp=$(get_current_timestamp)
    
    local processed=$(read_processed_file "$kb_dir")
    
    local new_entry="{\"path\": \"$rel_path\", \"hash\": \"$hash\", \"processed\": \"$timestamp\"}"
    
    if command -v jq &> /dev/null; then
        echo "$processed" | jq ".entries += [$new_entry]" > "$processed_file"
    else
        local entries=$(echo "$processed" | sed 's/.*"entries": \[/\[/' | sed 's/\] *}.*/\]/')
        if [[ "$entries" == "[]" ]]; then
            echo "{\"version\": 2, \"entries\": [$new_entry]}" > "$processed_file"
        else
            echo "{\"version\": 2, \"entries\": $entries, $new_entry]}" > "$processed_file"
        fi
    fi
}

append_to_log() {
    local kb_dir="$1"
    local operation="$2"
    local target="$3"
    local details="$4"
    
    local log_file="$kb_dir/.wiki/log.md"
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
