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
    local wiki_dir="$TARGET_DIR/wiki"
    local agents_file="$TARGET_DIR/AGENTS.md"
    local skills_dir="$TARGET_DIR/.opencode/skills"
    
    if [[ -d "$wiki_dir" || -f "$agents_file" || -d "$skills_dir" ]]; then
        if [[ "$FORCE" == "true" ]]; then
            print_warning "检测到已有安装，将强制覆盖"
        else
            print_error "检测到已有文件，若为更新安装请使用 --force，或移除已有文件后重试"
            exit 1
        fi
    fi
}

create_wiki_directory() {
    local wiki_dir="$TARGET_DIR/wiki"
    
    mkdir -p "$wiki_dir"
    print_success "创建 wiki 目录: $wiki_dir"
}

create_index_file() {
    local index_file="$TARGET_DIR/wiki/index.md"
    
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
    local log_file="$TARGET_DIR/wiki/log.md"
    
    cat > "$log_file" << 'EOF'
# Wiki 操作日志

此文件记录所有 wiki 操作的历史。

---

EOF
    
    print_success "创建日志文件: $log_file"
}

create_processed_file() {
    local processed_file="$TARGET_DIR/.wiki-processed"
    
    echo '{"version": 1, "entries": []}' > "$processed_file"
    print_success "创建处理记录文件: $processed_file"
}

create_skills_directory() {
    local skills_dir="$TARGET_DIR/.opencode/skills"
    
    mkdir -p "$skills_dir"
    
    local skills=("wiki-init" "wiki-ingest" "wiki-query" "wiki-lint" "wiki-update" "wiki-prune" "wiki-capture")
    
    for skill in "${skills[@]}"; do
        local src_dir="$SKILLS_SOURCE/$skill"
        local dst_dir="$skills_dir/$skill"
        
        if [[ -d "$src_dir" ]]; then
            mkdir -p "$dst_dir"
            cp "$src_dir/SKILL.md" "$dst_dir/SKILL.md"
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

## 用户偏好

<!-- 用户可以在此添加个人偏好 -->

## 自定义配置

<!-- 用户可以在此添加自定义配置 -->
EOF
        print_success "创建默认 AGENTS.md: $agents_file"
    fi
}

# === Update functions ===
update_skills() {
    local target="$1"
    local skills_dir="$target/.opencode/skills"

    mkdir -p "$skills_dir"

    local skills=("wiki-init" "wiki-ingest" "wiki-query" "wiki-lint" "wiki-update" "wiki-prune" "wiki-capture")
    local updated=0

    for skill in "${skills[@]}"; do
        local src="$SKILLS_SOURCE/$skill"
        local dst="$skills_dir/$skill"

        if [[ -d "$src" ]]; then
            mkdir -p "$dst"
            if [[ -f "$src/SKILL.md" ]]; then
                cp "$src/SKILL.md" "$dst/SKILL.md"
                print_success "更新 skill: $skill"
                ((updated++))
            fi
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
wiki/
├── index.md          # 内容索引
├── log.md            # 操作日志
├── entities/         # 实体页面
├── concepts/         # 概念页面
├── sources/          # 源文件摘要
└── analysis/         # 分析与综合页面
```

## 排除目录

以下目录不会被处理：
- `wiki/`
- `.opencode/`
- `.git/`

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
    print_info "更新安装将执行以下操作："
    print_info "  (1) 更新 skills — 从本仓库同步最新 skill 文件"
    print_info "  (2) 更新 AGENTS.md — 从模板更新，保留您的用户偏好和自定义配置"
    echo ""

    if prompt_user "Step (1/2): 是否更新 skills？（将覆盖现有 skill 文件）"; then
        update_skills "$target"
    else
        print_info "已跳过更新 skills"
    fi

    if prompt_user "Step (2/2): 是否更新 AGENTS.md？（模板章节将刷新，用户偏好和自定义配置章节将保留）"; then
        update_agents_file "$target"
    else
        print_info "已跳过更新 AGENTS.md"
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
        create_skills_directory
        create_agents_file

        print_completion_message

        configure_vision_reader "$TARGET_DIR"
    fi
}

main "$@"
