#!/bin/bash

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SKILLS_SOURCE="$SCRIPT_DIR/skills"
TEMPLATES_SOURCE="$SCRIPT_DIR/templates"

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

show_help() {
    echo "LLM Wikier 安装脚本"
    echo ""
    echo "用法: $0 <目标知识库路径> [选项]"
    echo ""
    echo "参数:"
    echo "  <目标知识库路径>    要安装 LLM Wikier 的知识库目录路径"
    echo ""
    echo "选项:"
    echo "  -h, --help          显示此帮助信息"
    echo "  -f, --force         强制覆盖（更新安装时自动确认所有步骤）"
    echo ""
    echo "示例:"
    echo "  $0 ~/my-knowledge-base"
    echo "  $0 /path/to/knowledge-base --force"
}

parse_args() {
    FORCE=false
    TARGET_DIR=""
    
    while [[ $# -gt 0 ]]; do
        case $1 in
            -h|--help)
                show_help
                exit 0
                ;;
            -f|--force)
                FORCE=true
                shift
                ;;
            *)
                if [[ -z "$TARGET_DIR" ]]; then
                    TARGET_DIR="$1"
                else
                    print_error "未知参数: $1"
                    show_help
                    exit 1
                fi
                shift
                ;;
        esac
    done
    
    if [[ -z "$TARGET_DIR" ]]; then
        print_error "请指定目标知识库路径"
        show_help
        exit 1
    fi
}

validate_target_dir() {
    TARGET_DIR="$(cd "$TARGET_DIR" 2>/dev/null && pwd)" || {
        print_error "目标目录不存在: $TARGET_DIR"
        exit 1
    }
    
    print_info "目标知识库路径: $TARGET_DIR"
}

# === Update detection ===
is_update_install() {
    local target="$1"

    [[ ! -f "$target/AGENTS.md" ]] && return 1

    local key_skills=("wiki-ingest" "wiki-lint" "wiki-query")
    for skill in "${key_skills[@]}"; do
        [[ ! -f "$target/.opencode/skills/$skill/SKILL.md" ]] && return 1
    done

    return 0
}

# === Prompt user ===
prompt_user() {
    local message="$1"

    if [[ "$FORCE" == "true" ]]; then
        return 0
    fi

    echo -e "${YELLOW}[询问]${NC} $message [Y/n] "
    read -r response

    case "$response" in
        [nN]|[nN][oO]) return 1 ;;
        *) return 0 ;;
    esac
}

# === Section extraction ===
extract_section_from_to() {
    local file="$1"
    local from_marker="$2"
    local to_marker="$3"

    local from_line
    from_line=$(grep -n "^${from_marker}$" "$file" | head -1 | cut -d: -f1) || true
    local to_line
    to_line=$(grep -n "^${to_marker}$" "$file" | head -1 | cut -d: -f1) || true

    [[ -z "$from_line" ]] && return 1
    [[ -z "$to_line" || "$to_line" -le "$from_line" ]] && return 1

    sed -n "${from_line},$((to_line - 1))p" "$file"
    return 0
}

extract_section_to_end() {
    local file="$1"
    local from_marker="$2"

    local from_line
    from_line=$(grep -n "^${from_marker}$" "$file" | head -1 | cut -d: -f1) || true
    [[ -z "$from_line" ]] && return 1

    sed -n "${from_line}"',$p' "$file"
    return 0
}

# === AGENTS.md merge ===
merge_agents_file() {
    local old_file="$1"
    local new_template="$2"
    local output_file="$3"

    local tmp_user
    tmp_user=$(mktemp) || true
    local tmp_custom
    tmp_custom=$(mktemp) || true

    local has_user=1
    local has_custom=1

    extract_section_from_to "$old_file" "## 用户偏好" "## 自定义配置" > "$tmp_user" && has_user=0
    extract_section_to_end "$old_file" "## 自定义配置" > "$tmp_custom" && has_custom=0

    if [[ $has_user -ne 0 || $has_custom -ne 0 ]]; then
        rm -f "$tmp_user" "$tmp_custom"
        if prompt_user "现有 AGENTS.md 缺少标准章节，是否直接按新模板覆盖？"; then
            cp "$new_template" "$output_file"
            print_info "已按新模板覆盖 AGENTS.md"
        else
            print_info "保留现有 AGENTS.md 不变"
        fi
        return
    fi

    local new_user_line
    new_user_line=$(grep -n "^## 用户偏好$" "$new_template" | head -1 | cut -d: -f1) || true
    local new_custom_line
    new_custom_line=$(grep -n "^## 自定义配置$" "$new_template" | head -1 | cut -d: -f1) || true

    if [[ -z "$new_user_line" || -z "$new_custom_line" ]]; then
        rm -f "$tmp_user" "$tmp_custom"
        print_warning "新模板缺少标准章节，保留现有 AGENTS.md"
        cp "$old_file" "$output_file"
        return
    fi

    sed -n "1,$((new_user_line - 1))p" "$new_template" > "$output_file"
    cat "$tmp_user" >> "$output_file"
    cat "$tmp_custom" >> "$output_file"

    rm -f "$tmp_user" "$tmp_custom"
    print_success "已合并更新 AGENTS.md"
}

check_existing_installation() {
    local wiki_dir="$TARGET_DIR/.wiki"
    local old_wiki_dir="$TARGET_DIR/wiki"
    local agents_file="$TARGET_DIR/AGENTS.md"
    local skills_dir="$TARGET_DIR/.opencode/skills"
    
    if [[ -d "$wiki_dir" || -d "$old_wiki_dir" || -f "$agents_file" || -d "$skills_dir" ]]; then
        if [[ "$FORCE" == "true" ]]; then
            print_warning "检测到已有安装，将强制覆盖"
        else
            print_error "检测到已有文件，若为更新安装请使用 --force，或移除已有文件后重试"
            exit 1
        fi
    fi
}

create_wiki_directory() {
    local wiki_dir="$TARGET_DIR/.wiki"
    
    mkdir -p "$wiki_dir"
    print_success "创建 wiki 目录: $wiki_dir"
}

create_index_file() {
    local index_file="$TARGET_DIR/.wiki/index.md"
    
    cat > "$index_file" << 'EOF'
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
EOF
    
    print_success "创建索引文件: $index_file"
}

create_log_file() {
    local log_file="$TARGET_DIR/.wiki/log.md"
    
    cat > "$log_file" << 'EOF'
# Wiki 操作日志

此文件记录所有 wiki 操作的历史。

---

EOF
    
    print_success "创建日志文件: $log_file"
}

create_processed_file() {
    local processed_file="$TARGET_DIR/.wiki/.wiki-processed"
    
    echo '{"version": 1, "entries": []}' > "$processed_file"
    print_success "创建处理记录文件: $processed_file"
}

create_wiki_ignore_file() {
    local ignore_file="$TARGET_DIR/.wiki_ignore"
    
    cat > "$ignore_file" << 'EOF'
# LLM Wikier — 默认排除规则（由工具包管理，请勿修改此区域）
.opencode/
.wiki/
.git/
AGENTS.md
output/

# ——— 用户自定义规则（添加在此区域下方） ———
EOF
    
    print_success "创建 .wiki_ignore: $ignore_file"
}

create_output_directory() {
    local output_dir="$TARGET_DIR/output"
    
    if [[ -d "$output_dir" ]]; then
        print_info "output/ 目录已存在，跳过创建"
        return 0
    fi
    
    mkdir -p "$output_dir"
    print_success "创建 output/ 目录: $output_dir"
}

create_skills_directory() {
    local skills_dir="$TARGET_DIR/.opencode/skills"
    
    mkdir -p "$skills_dir"
    
    local skills=("wiki-init" "wiki-ingest" "wiki-query" "wiki-lint" "wiki-update" "wiki-prune" "wiki-capture" "wiki-backup")
    
    for skill in "${skills[@]}"; do
        local src_dir="$SKILLS_SOURCE/$skill"
        local dst_dir="$skills_dir/$skill"
        
        if [[ -d "$src_dir" ]]; then
            mkdir -p "$dst_dir"
            cp -r "$src_dir/"* "$dst_dir/"
            print_success "安装 skill: $skill"
        else
            print_warning "找不到 skill 源文件: $skill"
        fi
    done
}

create_agents_file() {
    local agents_file="$TARGET_DIR/AGENTS.md"
    local template_file="$TEMPLATES_SOURCE/AGENTS.md.tmpl"
    
    if [[ -f "$template_file" ]]; then
        cp "$template_file" "$agents_file"
        print_success "创建 AGENTS.md: $agents_file"
    else
        print_warning "找不到 AGENTS.md 模板，创建默认文件"
        cat > "$agents_file" << 'EOF'
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

配置方式：`./config_vision_reader.sh <知识库路径>`

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
EOF
        print_success "创建默认 AGENTS.md: $agents_file"
    fi
}

# === Migration functions ===
migrate_processed_file() {
    local target="$1"
    local processed="$target/.wiki/.wiki-processed"

    [[ ! -f "$processed" ]] && return 0

    local version
    version=$(grep -o '"version": [[:digit:]]*' "$processed" | grep -o '[[:digit:]]*')
    [[ "$version" != "1" ]] && return 0

    print_info "检测到 .wiki-processed v1，正在迁移至 v2..."
    cp "$processed" "$processed.bak"
    print_info "已备份: $processed.bak"

    # Build hash→path map and migrate using python3 (primary) or jq (fallback)
    if command -v python3 &>/dev/null; then
        local result
        result=$(python3 - "$target" "$processed" << 'PYEOF'
import json, os, hashlib, sys, time
kb_dir = sys.argv[1]
processed_file = sys.argv[2]
with open(processed_file, 'r') as f:
    data = json.load(f)
if data.get('version') != 1:
    sys.exit(0)
hash_map = {}
path_map = {}
for root, dirs, files in os.walk(kb_dir):
    rel_root = os.path.relpath(root, kb_dir)
    if any(rel_root == d or rel_root.startswith(d + os.sep) for d in ['.wiki', '.opencode', '.git']):
        continue
    for fname in files:
        fpath = os.path.join(root, fname)
        rel_path = os.path.relpath(fpath, kb_dir).replace('\\', '/')
        if not os.path.isfile(fpath): continue
        try:
            h = hashlib.sha256(open(fpath, 'rb').read()).hexdigest()
            hash_map[h] = rel_path
            path_map[rel_path] = h
        except OSError: pass
kept = recovered = removed = 0
filled = 0
ts = time.strftime('%Y-%m-%dT%H:%M:%SZ', time.gmtime())
new_entries = []
for entry in data.get('entries', []):
    path = entry.get('path', '')
    h = entry.get('hash', '') or ''
    full = os.path.join(kb_dir, path)
    if not h and os.path.exists(full):
        # Fill missing hash from file
        h = path_map.get(path, '')
        if not h:
            try:
                h = hashlib.sha256(open(full, 'rb').read()).hexdigest()
            except OSError: pass
        if h:
            entry['hash'] = h
            entry['processed'] = ts
            filled += 1
    if not h and not os.path.exists(full):
        removed += 1
        continue
    if os.path.exists(full):
        kept += 1
        new_entries.append(entry)
    elif h in hash_map:
        recovered += 1
        entry['path'] = hash_map[h]
        new_entries.append(entry)
    else:
        removed += 1
data['version'] = 2
data['entries'] = new_entries
with open(processed_file, 'w') as f:
    json.dump(data, f, ensure_ascii=False, indent=2)
print(f"{kept}|{recovered}|{removed}|{filled}")
PYEOF
        )
        kept=$(echo "$result" | cut -d'|' -f1)
        recovered=$(echo "$result" | cut -d'|' -f2)
        removed=$(echo "$result" | cut -d'|' -f3)
        filled=$(echo "$result" | cut -d'|' -f4)

    elif command -v jq &>/dev/null; then
        # jq fallback: simplified migration (ghost cleanup only, no hash recovery)
        local tmp
        tmp=$(mktemp)
        echo '{"version": 2, "entries": []}' > "$tmp"
        local total=0 kept_j=0 removed_j=0 filled_j=0
        while IFS= read -r entry; do
            [[ -z "$entry" ]] && continue
            total=$((total + 1))
            local ep eh
            ep=$(echo "$entry" | jq -r '.path')
            eh=$(echo "$entry" | jq -r '.hash // ""')
            if [[ -f "$target/$ep" ]]; then
                kept_j=$((kept_j + 1))
                if [[ -z "$eh" ]]; then
                    # Fill missing hash
                    local new_hash
                    new_hash=$(sha256sum "$target/$ep" 2>/dev/null | cut -d' ' -f1) || \
                    new_hash=$(shasum -a 256 "$target/$ep" 2>/dev/null | cut -d' ' -f1) || \
                    new_hash=$(md5sum "$target/$ep" 2>/dev/null | cut -d' ' -f1) || true
                    if [[ -n "$new_hash" ]]; then
                        entry=$(echo "$entry" | jq --arg h "$new_hash" '.hash = $h')
                        filled_j=$((filled_j + 1))
                    fi
                fi
                jq --argjson e "$entry" '.entries += [$e]' "$tmp" > "${tmp}.new" && mv "${tmp}.new" "$tmp"
            else
                removed_j=$((removed_j + 1))
            fi
        done < <(jq -c '.entries[]' "$processed")
        cp "$tmp" "$processed"
        rm -f "$tmp"
        kept=$kept_j; recovered=0; removed=$removed_j; filled=$filled_j
    else
        print_warning "需要 python3 或 jq 来执行迁移，跳过迁移"
        print_info "保留原始 .wiki-processed（version 仍为 1），可稍后手动迁移"
        return 0
    fi

    echo ""
    print_success "迁移完成: 保留 ${kept:-0} 条, 恢复 ${recovered:-0} 条, 移除 ${removed:-0} 条, 补填 ${filled:-0} 条"
    print_info "回滚方法: cp \"$processed.bak\" \"$processed\""
}

migrate_old_structure() {
    local target="$1"

    if [[ ! -d "$target/wiki" || -d "$target/.wiki" ]]; then
        return 0
    fi

    print_info "检测到旧版 wiki/ 目录，正在自动迁移至 .wiki/..."

    # Step a: Move wiki/ → .wiki/
    mv "$target/wiki" "$target/.wiki"
    print_success "已迁移 wiki/ → .wiki/"

    # Step b: Move .wiki-processed into .wiki/
    if [[ -f "$target/.wiki-processed" ]]; then
        mv "$target/.wiki-processed" "$target/.wiki/.wiki-processed"
        print_success "已迁移 .wiki-processed → .wiki/.wiki-processed"
    fi

    # Step c: Replace wiki/ → .wiki/ in all migrated wiki pages
    if [[ "$(uname)" == "Darwin" ]]; then
        find "$target/.wiki" -name "*.md" -type f -exec sed -i '' 's|wiki/|.wiki/|g' {} +
    else
        find "$target/.wiki" -name "*.md" -type f -exec sed -i 's|wiki/|.wiki/|g' {} +
    fi
    print_success "已修复 .wiki/ 内所有交叉引用链接"
}

# === Update functions ===
merge_wiki_ignore() {
    local target="$1"
    local ignore_file="$target/.wiki_ignore"
    
    if [[ ! -f "$ignore_file" ]]; then
        create_wiki_ignore_file
        return
    fi
    
    local user_custom
    user_custom=$(sed -n '/^# ——— 用户自定义规则/,//p' "$ignore_file" 2>/dev/null | sed '1d') || true
    
    create_wiki_ignore_file
    
    if [[ -n "$user_custom" ]]; then
        echo "" >> "$ignore_file"
        echo "$user_custom" >> "$ignore_file"
        print_success "已合并更新 .wiki_ignore（保留用户自定义规则）"
    fi
}

update_skills() {
    local target="$1"
    local skills_dir="$target/.opencode/skills"

    mkdir -p "$skills_dir"

    local skills=("wiki-init" "wiki-ingest" "wiki-query" "wiki-lint" "wiki-update" "wiki-prune" "wiki-capture" "wiki-backup")
    local updated=0

    for skill in "${skills[@]}"; do
        local src="$SKILLS_SOURCE/$skill"
        local dst="$skills_dir/$skill"

        if [[ -d "$src" ]]; then
            mkdir -p "$dst"
            cp -r "$src/"* "$dst/"
            print_success "更新 skill: $skill"
            updated=$((updated + 1))
        else
            print_warning "找不到 skill 源文件: $skill"
        fi
    done

    if [[ $updated -gt 0 ]]; then
        print_info "共更新 $updated 个 skill"
    fi
}

update_agents_file() {
    local target="$1"
    local agents_file="$target/AGENTS.md"
    local template_file="$TEMPLATES_SOURCE/AGENTS.md.tmpl"

    if [[ -f "$template_file" ]]; then
        merge_agents_file "$agents_file" "$template_file" "$agents_file"
    else
        print_warning "找不到 AGENTS.md 模板，使用内置默认内容"
        local default_template
        default_template=$(mktemp) || true
        cat > "$default_template" << 'EOF'
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
EOF
        merge_agents_file "$agents_file" "$default_template" "$agents_file"
        rm -f "$default_template"
    fi
}

update_install() {
    local target="$1"

    echo ""

    migrate_processed_file "$target"

    migrate_old_structure "$target"

    echo ""
    print_info "更新安装将执行以下操作："
    print_info "  (1) 更新 skills — 从本仓库同步最新 skill 文件"
    print_info "  (2) 更新 AGENTS.md — 从模板更新，保留您的用户偏好和自定义配置"
    print_info "  (3) 更新 .wiki_ignore — 从模板更新，保留用户自定义规则"
    print_info "  (4) 配置备份根目录"
    echo ""

    if prompt_user "Step (1/4): 是否更新 skills？（将覆盖现有 skill 文件）"; then
        update_skills "$target"
    else
        print_info "已跳过更新 skills"
    fi

    if prompt_user "Step (2/4): 是否更新 AGENTS.md？（模板章节将刷新，用户偏好和自定义配置章节将保留）"; then
        update_agents_file "$target"
    else
        print_info "已跳过更新 AGENTS.md"
    fi

    if prompt_user "Step (3/4): 是否更新 .wiki_ignore？（默认规则将刷新，用户自定义规则将保留）"; then
        merge_wiki_ignore "$target"
    else
        print_info "已跳过更新 .wiki_ignore"
    fi

    if prompt_user "Step (4/4): 是否修改备份根目录？"; then
        configure_backup "$target"
    else
        print_info "已跳过备份配置"
    fi

    echo ""
    print_success "更新安装完成！"

    configure_vision_reader "$target"
}

print_completion_message() {
    echo ""
    echo "======================================"
    print_success "LLM Wikier 安装完成！"
    echo "======================================"
    echo ""
    echo "下一步操作："
    echo ""
    echo "1. 进入知识库目录："
    echo "   cd \"$TARGET_DIR\""
    echo ""
    echo "2. 启动 OpenCode："
    echo "   opencode"
    echo ""
    echo "3. 如果知识库已有文件，运行批量初始化："
    echo "   /wiki-init"
    echo ""
    echo "4. 或者添加新文件后运行增量处理："
    echo "   /wiki-ingest"
    echo ""
    echo "详细文档请参考 README.md"
}

configure_backup() {
    local target="$1"

    if [[ "$FORCE" == "true" ]]; then
        local backup_script="$target/.opencode/skills/wiki-backup/backup.sh"
        if [[ -f "$backup_script" && "$(grep -c 'BACKUP_ROOT=' "$backup_script")" -gt 0 ]]; then
            print_info "强制安装模式，保留现有备份配置"
        else
            print_info "强制安装模式，备份使用默认路径: ~/.knowledge_base"
        fi
        return 0
    fi

    echo ""
    print_info "备份脚本的默认根目录为 ~/.knowledge_base"
    echo -e "${YELLOW}[询问]${NC} 请输入备份根目录（留空使用默认值）: "
    read -r backup_root

    if [[ -z "$backup_root" ]]; then
        backup_root="$HOME/.knowledge_base"
    fi

    # Normalize path: expand ~
    backup_root="${backup_root/#\~/$HOME}"

    # Write into backup.sh
    local backup_sh="$target/.opencode/skills/wiki-backup/backup.sh"
    if [[ -f "$backup_sh" ]]; then
        if [[ "$(uname)" == "Darwin" ]]; then
            sed -i '' "s|^BACKUP_ROOT=.*|BACKUP_ROOT=\"$backup_root\"|" "$backup_sh"
        else
            sed -i "s|^BACKUP_ROOT=.*|BACKUP_ROOT=\"$backup_root\"|" "$backup_sh"
        fi
        print_success "已配置备份根目录: $backup_root"
    else
        print_warning "找不到 backup.sh，跳过备份配置"
    fi

    # Write into backup.ps1
    local backup_ps1="$target/.opencode/skills/wiki-backup/backup.ps1"
    if [[ -f "$backup_ps1" ]]; then
        if [[ "$(uname)" == "Darwin" ]]; then
            sed -i '' "s|^\\$script:BackupRoot =.*|\\$script:BackupRoot = \"$backup_root\"|" "$backup_ps1"
        else
            sed -i "s|^\\$script:BackupRoot =.*|\\$script:BackupRoot = \"$backup_root\"|" "$backup_ps1"
        fi
        print_success "已配置 backup.ps1 备份根目录"
    fi
}

configure_vision_reader() {
    local target="$1"

    if [[ "$FORCE" == "true" ]]; then
        print_info "强制安装模式，跳过 vision-reader 交互配置"
        print_info "稍后可手动运行: ./config_vision_reader.sh \"$target\""
        return 0
    fi

    echo ""
    if ! prompt_user "是否配置 vision-reader subagent？（用于读取图片/幻灯片/PDF 等视觉内容）"; then
        print_info "已跳过 vision-reader 配置"
        return 0
    fi

    local config_script="$SCRIPT_DIR/config_vision_reader.sh"
    if [[ ! -f "$config_script" ]]; then
        print_error "找不到配置脚本: $config_script"
        return 1
    fi

    echo ""
    print_info "正在配置 vision-reader..."
    bash "$config_script" "$target" -f
}

main() {
    parse_args "$@"
    validate_target_dir

    if is_update_install "$TARGET_DIR"; then
        print_info "检测到已有安装（AGENTS.md + 关键 skills），进入更新安装模式"
        update_install "$TARGET_DIR"
    else
        check_existing_installation

        print_info "开始安装 LLM Wikier..."

        create_wiki_directory
        create_index_file
        create_log_file
        create_processed_file
        create_wiki_ignore_file
        create_output_directory
        create_skills_directory
        create_agents_file

        configure_backup "$TARGET_DIR"

        print_completion_message

        configure_vision_reader "$TARGET_DIR"
    fi
}

main "$@"
