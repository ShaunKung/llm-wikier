#!/bin/bash

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# Source common functions
if [[ -f "$SCRIPT_DIR/lib/common.sh" ]]; then
    source "$SCRIPT_DIR/lib/common.sh"
else
    RED='\033[0;31m'
    GREEN='\033[0;32m'
    YELLOW='\033[1;33m'
    BLUE='\033[0;34m'
    NC='\033[0m'

    print_error() { echo -e "${RED}[错误]${NC} $1"; }
    print_success() { echo -e "${GREEN}[成功]${NC} $1"; }
    print_info() { echo -e "${BLUE}[信息]${NC} $1"; }
    print_warning() { echo -e "${YELLOW}[警告]${NC} $1"; }
fi

TARGET_DIR=""
FORCE=false
OPENCODE_CLI=""

# === Locate opencode CLI or read from config ===
# Returns "cli:<path>" for CLI binary, "config:<model>" from config file, or empty on failure
find_opencode_cli_or_config() {
    # Layer 1: CLI binary via PATH first
    if command -v opencode &>/dev/null; then
        echo "cli:opencode"
        return 0
    fi
    # Layer 1: CLI binary via common install paths
    local candidates=(
        "$HOME/.opencode/opencode"
        "$HOME/.npm-global/bin/opencode"
        "$HOME/.local/bin/opencode"
        "$HOME/bin/opencode"
        "/usr/local/bin/opencode"
        "/opt/homebrew/bin/opencode"
    )
    local c
    for c in "${candidates[@]}"; do
        if [[ -x "$c" ]]; then
            echo "cli:$c"
            return 0
        fi
    done

    # Layer 2: Read model from opencode config file (covers Desktop app users)
    local config_files=(
        "$HOME/.config/opencode/opencode.json"
        "$HOME/.config/opencode/opencode.jsonc"
    )
    if [[ -n "$TARGET_DIR" ]]; then
        config_files+=("$TARGET_DIR/opencode.json" "$TARGET_DIR/opencode.jsonc")
    fi
    local f model
    for f in "${config_files[@]}"; do
        if [[ -f "$f" ]]; then
            model=$(grep -o '"model"[[:space:]]*:[[:space:]]*"[^"]*"' "$f" 2>/dev/null | head -1 | sed 's/.*"model"[[:space:]]*:[[:space:]]*"\([^"]*\)".*/\1/')
            if [[ -n "$model" && "$model" == *"/"* ]]; then
                echo "config:$model"
                return 0
            fi
        fi
    done

    # Layer 3: npx fallback for CLI
    if command -v npx &>/dev/null; then
        if npx --yes @opencode/cli --help &>/dev/null 2>&1; then
            echo "cli:npx --yes @opencode/cli"
            return 0
        fi
    fi

    return 1
}

show_help() {
    echo "LLM Wikier vision-reader 配置脚本"
    echo ""
    echo "用法: $0 <目标知识库路径> [选项]"
    echo ""
    echo "参数:"
    echo "  <目标知识库路径>    已安装 LLM Wikier 的知识库目录路径"
    echo ""
    echo "选项:"
    echo "  -h, --help          显示此帮助信息"
    echo "  -f, --force         更新模式跳过确认"
    echo ""
    echo "示例:"
    echo "  $0 ~/my-knowledge-base"
    echo "  $0 /path/to/knowledge-base --force"
}

parse_args() {
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

    if ! is_valid_kb_dir "$TARGET_DIR"; then
        print_error "目标目录不是有效的 LLM Wikier 知识库（缺少 AGENTS.md 或 .wiki/ 目录）"
        print_info "请先运行 install.sh 安装 LLM Wikier"
        exit 1
    fi
}

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

read_user_input() {
    local prompt="$1"
    local var_name="$2"
    echo -e -n "${BLUE}[输入]${NC} $prompt: "
    read -r value
    eval "$var_name=\"$value\""
}

# === Parse existing config to preserve model/apiKey on update ===
parse_existing_config() {
    local config_file="$1"

    if [[ ! -f "$config_file" ]]; then
        return 1
    fi

    # Extract model from YAML frontmatter
    local model
    model=$(sed -n '/^---$/,/^---$/p' "$config_file" | grep "^model:" | head -1 | sed 's/^model:[[:space:]]*//')

    if [[ -z "$model" || "$model" == "/" ]]; then
        return 1
    fi

    SELECTED_MODEL="$model"

    # Extract apiKey env var from provider section (optional)
    local provider_section
    provider_section=$(sed -n '/^---$/,/^---$/p' "$config_file" | sed -n '/^provider:/,/^[a-z]/p' | head -n -1)

    if [[ -n "$provider_section" ]]; then
        local api_key_env
        api_key_env=$(echo "$provider_section" | grep "apiKey:" | sed 's/.*{env:\([^}]*\)}.*/\1/')
        if [[ -n "$api_key_env" ]]; then
            API_KEY_ENV="$api_key_env"
            PROVIDER="${model%%/*}"
        fi
    fi

    print_info "从已有配置中检测到模型: $SELECTED_MODEL"
    return 0
}

# === Parse opencode models output ===
parse_opencode_models() {
    local output="$1"

    # Each non-empty line is a model identifier like "provider/model" or "provider/sub/model"
    local parsed
    parsed=$(echo "$output" | grep -E '^[a-zA-Z0-9_./-]+$' | head -30)

    if [[ -z "$parsed" ]]; then
        return 1
    fi

    echo "$parsed"
    return 0
}

# === Model selection: CLI interactive or config auto-detect ===
select_model_opencode() {
    local result="$OPENCODE_CLI"

    if [[ -z "$result" ]]; then
        print_warning "未找到 opencode CLI 或配置文件，将切换到手动配置"
        return 1
    fi

    # Handle config-based model (Desktop app user — no CLI binary)
    if [[ "$result" == config:* ]]; then
        SELECTED_MODEL="${result#config:}"
        print_info "从 opencode 配置文件中检测到模型: $SELECTED_MODEL"
        return 0
    fi

    # Handle CLI-based model selection
    local cli_path="${result#cli:}"

    print_info "正在获取可用 provider 和模型列表..."

    local models_output
    models_output=$($cli_path models 2>&1) || {
        print_warning "无法执行 '$cli_path models'"
        return 1
    }

    local models
    models=$(parse_opencode_models "$models_output") || {
        print_warning "无法解析 opencode 模型输出，将切换到手动配置"
        return 1
    }

    local model_count
    model_count=$(echo "$models" | wc -l | tr -d ' ')

    if [[ "$model_count" -eq 0 ]]; then
        print_warning "未检测到可用模型，将切换到手动配置"
        return 1
    fi

    echo ""
    print_info "检测到以下可用模型:"
    echo ""

    local index=1
    local -a model_array
    while IFS= read -r line; do
        printf "  [%2d] %s\n" "$index" "$line"
        model_array+=("$line")
        ((index++))
    done <<< "$models"

    echo ""
    echo "  [ 0] 手动输入 provider 和 model"

    local choice
    while true; do
        echo -e -n "${BLUE}[选择]${NC} 请输入序号选择模型 (0-${model_count}): "
        read -r choice

        if [[ "$choice" == "0" ]]; then
            return 1
        fi

        if [[ "$choice" =~ ^[0-9]+$ ]] && [[ "$choice" -ge 1 ]] && [[ "$choice" -le "$model_count" ]]; then
            SELECTED_MODEL="${model_array[$((choice - 1))]}"
            print_success "已选择模型: $SELECTED_MODEL"
            return 0
        fi

        print_error "无效选择，请重试"
    done
}

# === Manual model configuration ===
manual_model_config() {
    print_info "手动配置 vision-reader subagent:"
    echo ""

    while [[ -z "$PROVIDER" ]]; do
        read_user_input "Provider ID (如 anthropic, openai, deepseek)" "PROVIDER"
        if [[ -z "$PROVIDER" ]]; then
            print_error "Provider 不能为空"
        fi
    done

    while [[ -z "$MODEL_ID" ]]; do
        read_user_input "Model ID (如 claude-sonnet-4-20250514, gpt-4o)" "MODEL_ID"
        if [[ -z "$MODEL_ID" ]]; then
            print_error "Model ID 不能为空"
        fi
    done

    SELECTED_MODEL="${PROVIDER}/${MODEL_ID}"

    echo ""
    read_user_input "API Key 环境变量名 (如 ANTHROPIC_API_KEY，如已全局配置可留空)" "API_KEY_ENV"
    echo ""
    print_success "已配置模型: $SELECTED_MODEL"
}

# === Write config file ===
write_agent_config() {
    local config_dir="$TARGET_DIR/.opencode/agents"
    local config_file="$config_dir/vision-reader.md"

    mkdir -p "$config_dir"

    # Write config without heredoc to avoid escaping issues
    {
        echo "---"
        echo "description: 视觉内容读取器，读取文件中的图片、图表、截图、幻灯片、文档排版等视觉元素，转化为文字描述"
        echo "mode: subagent"
        echo "model: ${SELECTED_MODEL}"
        echo "permission:"
        echo "  edit: deny"
        echo "  bash: deny"
        echo "  task: deny"
        echo "  webfetch: deny"
        echo "  skill: deny"
        if [[ -n "$API_KEY_ENV" ]]; then
            echo "provider:"
            echo "  ${PROVIDER:-unknown}:"
            echo "    options:"
            echo "      apiKey: \"{env:${API_KEY_ENV}}\""
        fi
        echo "---"
        echo "你是一个视觉内容读取器。你的职责是读取文件中的视觉元素（图片、图表、截图、幻灯片、页面排版等），并将视觉内容转化为文字描述。"
        echo ""
        echo "## 核心职责"
        echo "- 只描述视觉元素（图片、图表、照片、插图、截图、幻灯片视觉内容、排版布局等）"
        echo "- 不要重复已经由主 agent 处理的纯文本内容"
        echo "- **兜底规则**：如果发现文档中文本提取明显不完整（如幻灯片缺失文字、表格数据丢失、图表中的数据标签等），请一并补充关键文本信息"
        echo ""
        echo "## 输出格式"
        echo "对每个视觉元素："
        echo ""
        printf '```\n'
        echo "### [图片/图表/截图 序号]"
        echo "**类型**: [图表/照片/截图/插图/排版]"
        echo "**描述**: [视觉内容的文字描述]"
        echo "**关键信息**: [图表数据、照片中的人物/场景、截图中的UI元素、幻灯片主题等]"
        printf '```\n'
        echo ""
        echo "主 agent 会通过文件路径告知你需要读取的文件，请直接读取并返回描述。"
    } > "$config_file"

    print_success "已保存配置: $config_file"
}

print_completion() {
    echo ""
    echo "======================================"
    print_success "vision-reader subagent 配置完成！"
    echo "======================================"
    echo ""
    echo "模型: $SELECTED_MODEL"
    if [[ -n "$API_KEY_ENV" ]]; then
        echo "API Key: 环境变量 $API_KEY_ENV"
    fi
    echo ""
    echo "配置文件: $TARGET_DIR/.opencode/agents/vision-reader.md"
    echo ""
    echo "提示: 你可能需要将此文件添加到 .gitignore（如果包含敏感配置）:"
    echo "  echo '.opencode/agents/vision-reader.md' >> $TARGET_DIR/.gitignore"
    echo ""
    echo "配置完成后，使用知识库时 Agent 会自动在遇到视觉内容时调用 vision-reader。"
    echo ""
    echo "注：本脚本仅配置 OpenCode 版 vision-reader。Claude Code 版（.claude/agents/vision-reader.md）与 Codex 版（.codex/agents/vision-reader.toml）由安装器在启用对应客户端支持时自动生成。"
    echo ""
}

main() {
    parse_args "$@"
    validate_target_dir

    local config_file="$TARGET_DIR/.opencode/agents/vision-reader.md"
    local config_exists=false
    local existing_model=""

    # === S2: Detect existing config ===
    if [[ -f "$config_file" ]]; then
        config_exists=true

        echo ""
        print_info "检测到已有 vision-reader 配置"
        echo ""
        echo "当前配置:"
        echo "----------------------------------------"
        cat "$config_file"
        echo "----------------------------------------"
        echo ""

        if ! prompt_user "是否更新此配置？"; then
            print_info "已取消，保留现有配置"
            exit 0
        fi

        # Extract existing model info for S2.2 fallback
        if parse_existing_config "$config_file"; then
            existing_model="$SELECTED_MODEL"
        fi
    fi

    echo ""
    print_info "开始配置 vision-reader subagent..."
    echo ""

    # === S2.1 / S2.2: Model selection ===
    if [[ "$config_exists" == "true" ]]; then
        # Always prompt for this choice, regardless of --force
        local update_model=true
        echo -e "${YELLOW}[询问]${NC} 是否更新模型选择？ [Y/n] "
        read -r response_update
        case "$response_update" in
            [nN]|[nN][oO]) update_model=false ;;
        esac

        if [[ "$update_model" == "true" ]]; then
            # S2.1: full model selection
            SELECTED_MODEL=""
            PROVIDER=""
            MODEL_ID=""
            API_KEY_ENV=""
            OPENCODE_CLI="$(find_opencode_cli_or_config || true)"

            if ! select_model_opencode; then
                manual_model_config
            fi
        else
            # S2.2: preserve existing model
            if [[ -n "$existing_model" ]]; then
                print_info "保留现有模型: $existing_model"
            else
                print_warning "无法从现有配置中提取模型，将进入模型选择"
                SELECTED_MODEL=""
                PROVIDER=""
                MODEL_ID=""
                API_KEY_ENV=""
                OPENCODE_CLI="$(find_opencode_cli_or_config || true)"

                if ! select_model_opencode; then
                    manual_model_config
                fi
            fi
        fi
    else
        # No existing config: always do model selection
        SELECTED_MODEL=""
        PROVIDER=""
        MODEL_ID=""
        API_KEY_ENV=""
        OPENCODE_CLI="$(find_opencode_cli_or_config || true)"

        if ! select_model_opencode; then
            manual_model_config
        fi
    fi

    # === Validate ===
    if [[ -z "$SELECTED_MODEL" ]] || [[ "$SELECTED_MODEL" == "/" ]]; then
        print_error "配置不完整（模型信息缺失），未保存"
        exit 1
    fi

    # Extract provider for extra fields
    if [[ "$SELECTED_MODEL" == *"/"* ]]; then
        PROVIDER="${SELECTED_MODEL%%/*}"
        MODEL_ID="${SELECTED_MODEL#*/}"
    fi

    write_agent_config
    print_completion
}

main "$@"
