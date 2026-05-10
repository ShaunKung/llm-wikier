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
    echo "  -f, --force         强制覆盖已存在的文件"
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

check_existing_installation() {
    local wiki_dir="$TARGET_DIR/wiki"
    local agents_file="$TARGET_DIR/AGENTS.md"
    local skills_dir="$TARGET_DIR/.opencode/skills"
    
    if [[ -d "$wiki_dir" || -f "$agents_file" || -d "$skills_dir" ]]; then
        if [[ "$FORCE" == "true" ]]; then
            print_warning "检测到已有安装，将强制覆盖"
        else
            print_error "检测到已有安装，使用 --force 强制覆盖"
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
EOF
        print_success "创建默认 AGENTS.md: $agents_file"
    fi
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

main() {
    parse_args "$@"
    validate_target_dir
    check_existing_installation
    
    print_info "开始安装 LLM Wikier..."
    
    create_wiki_directory
    create_index_file
    create_log_file
    create_processed_file
    create_skills_directory
    create_agents_file
    
    print_completion_message
}

main "$@"
