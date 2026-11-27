#!/usr/bin/env bash
set -euo pipefail

readonly SCRIPT_DIR="$(cd "$(dirname "$(readlink -f "${BASH_SOURCE[0]}")")" && pwd)"

# ==============================================================================
# Configuration
# ==============================================================================
# Fallback file path used if no CLI argument is set.
readonly DEFAULT_CONFIG_FILE="${HOME}/.tmenu/tmenu.default.json"

# Numeric behavior constants
readonly SUCCESS_STATUS=0
readonly ERROR_STATUS=1
readonly INTERRUPTED_STATUS=130
readonly WORLD_WRITABLE_PERMISSION="0002"
readonly ROOT_UID=0
readonly INITIAL_SELECTION_INDEX=0
readonly ONE_ITEM=1
readonly READ_ONE_CHAR=1
readonly READ_ESCAPE_CHARS=2
readonly ARROW_KEY_READ_TIMEOUT="0.1"
readonly PROMPT_ESCAPE_READ_TIMEOUT="0.05"
readonly ANSI_BOLD_PREFIX=$'\e[1m'
readonly ANSI_RED_PREFIX=$'\e[31m'
readonly ANSI_YELLOW_PREFIX=$'\e[33m'
readonly ANSI_CYAN_PREFIX=$'\e[36m'
readonly ANSI_GREY_PREFIX=$'\e[90m'
readonly ANSI_RESET=$'\e[0m'
readonly ANSI_MOVE_UP_FORMAT=$'\e[%dA'
readonly ANSI_CLEAR_TO_END=$'\e[0J'
readonly DESTRUCTIVE_COMMAND_PATTERN='(^|[;&|(`$[:space:]])(rm|rmdir|dd|mkfs(\.[a-z0-9]+)?|fdisk|parted|gdisk|wipefs|shred|srm|truncate|shutdown|reboot|halt|poweroff|init|telinit|kill|killall|pkill|chmod|chown|chgrp|mv|sudo|su|doas|crontab|systemctl|service|iptables|ufw|nft)([[:space:]]|$)'
readonly DESTRUCTIVE_REDIRECT_PATTERN='>[[:space:]]*/dev/'
readonly EDIT_CONFIG_NAME="Edit config..."
readonly EDIT_CONFIG_SENTINEL="__TMENU_EDIT_CONFIG__"

# ==============================================================================
# Interactive JSON Command Launcher
# ==============================================================================
#
# SECURITY & SAFETY MEASURES APPLIED:
#
# 1. Configuration File Integrity Checks:
#    - Permission Validation: Rejects world-writable JSON files (`o+w`) to
#      prevent untrusted local users from tampering with commands.
#    - Ownership Validation: Ensures the JSON file is owned by the current user
#      (`$EUID`) or `root` (`UID 0`) before parsing.
#
# 2. Destructive Command Detection & Interactive Confirmation:
#    - Scans commands for high-risk utilities (e.g., rm, dd, mkfs, fdisk,
#      parted, wipefs, shred, shutdown, reboot, halt, poweroff, kill, killall,
#      pkill, chmod, chown, mv, sudo, su, doas, truncate) or raw block device
#      redirects (`> /dev/...`).
#    - Standard items with `"confirm": true` prompt with `[Y/n]` (default Yes).
#    - Destructive commands automatically override `"confirm": false` and force
#      an explicit `[y/N]` prompt (default No on Enter) before execution.
#
# 3. Clean Process Replacement & Environment Hygiene:
#    - Uses `exec bash -c -- "$final_cmd"` instead of `eval` so the menu process
#      is completely replaced, preventing side effects in the script's scope.
#    - Unsets all internal script variables before `exec` so internal state
#      does not leak into the executed command's environment.
#
# 4. Safe Input Parsing & Output Formatting:
#    - Strict Mode (`set -euo pipefail`): Aborts immediately on unexpected
#      errors, unset variables, or failed pipeline stages.
#    - Format-String Safety: Uses `printf "%s"` for all dynamic JSON text so
#      `%` characters cannot be interpreted as format specifiers.
#    - Terminal State Restoration: Traps `EXIT`, `INT`, and `TERM` to guarantee
#      the terminal cursor (`tput cnorm`) is always restored on exit.
# ==============================================================================

show_help() {
    cat <<EOF
Usage: $(basename "$0") [OPTIONS] [JSON_FILE]

An interactive terminal command launcher driven by a JSON configuration file.

Arguments:
  JSON_FILE          Path to the menu JSON file
                     (defaults to ${DEFAULT_CONFIG_FILE})

Options:
  -n, --dry-run      Print the selected command instead of executing it
  -h, --help         Show this help message and exit

Controls:
  Up / Down Arrow     Move selection highlight
  Right Arrow / Enter Execute (or print in dry-run) the selected command and exit
  Left Arrow / Esc / Q / Ctrl+C
                      Quit without running any command
  Y / N / Enter       Respond to single-keypress confirmation prompts
                      ([Y/n] defaults to Yes; [y/N] defaults to No on Enter)

Expected JSON Format:
  [
    { "name": "dir listing", "run": "ls -a", "confirm": false, "safe": true },
    { "name": "create directory", "run": "mkdir \${dir_name}", "confirm": true }
  ]

  Optional "safe": true bypasses destructive-command pattern matching for that item.

Menu Config Path:
  Pass the menu JSON path as the positional argument:
    $(basename "$0") /absolute/path/to/menu.json
EOF
}

dry_run=false
cli_json_file=""

# Parse CLI flags and positional arguments
while [[ $# -gt 0 ]]; do
    case "$1" in
        -h|--help)
            show_help
            exit "$SUCCESS_STATUS"
            ;;
        -n|--dry-run)
            dry_run=true
            shift
            ;;
        --)
            shift
            if [[ $# -gt 0 ]]; then
                cli_json_file="$1"
                shift
            fi
            break
            ;;
        -*)
            echo "Error: Unknown option '$1'. Run '$(basename "$0") --help' for usage." >&2
            exit "$ERROR_STATUS"
            ;;
        *)
            if [[ -n "$cli_json_file" ]]; then
                echo "Error: Unexpected extra argument '$1'. Run '$(basename "$0") --help' for usage." >&2
                exit "$ERROR_STATUS"
            fi
            cli_json_file="$1"
            shift
            ;;
    esac
done

# Precedence: CLI argument > DEFAULT_CONFIG_FILE
json_file="${cli_json_file:-$DEFAULT_CONFIG_FILE}"

# 1. Config file integrity checks
if [[ ! -f "$json_file" || ! -r "$json_file" ]]; then
    if [[ "$json_file" == /* ]]; then
        json_file_display="$json_file"
    else
        json_file_display="$(pwd -P)/$json_file"
    fi
    printf "${ANSI_RED_PREFIX}Error: Readable file '\''%s'\'' not found. Run '\''%s --help'\'' for usage.${ANSI_RESET}\n" "$json_file_display" "$(basename "$0")" >&2
    show_help >&2
    exit "$ERROR_STATUS"
fi

if find "$json_file" -perm "-${WORLD_WRITABLE_PERMISSION}" 2>/dev/null | grep -q .; then
    echo "Security Error: '$json_file' is world-writable. Run 'chmod o-w $json_file' first." >&2
    exit "$ERROR_STATUS"
fi

file_uid=$(stat -c '%u' "$json_file" 2>/dev/null || stat -f '%u' "$json_file" 2>/dev/null)
if [[ -n "$file_uid" && "$file_uid" -ne "$EUID" && "$file_uid" -ne "$ROOT_UID" ]]; then
    echo "Security Error: '$json_file' is not owned by you or root." >&2
    exit "$ERROR_STATUS"
fi

validate_json_placeholders() {
    local file="$1"
    local line=""
    local line_number="$INITIAL_SELECTION_INDEX"
    local rest=""

    while IFS= read -r line || [[ -n "$line" ]]; do
        line_number=$((line_number + ONE_ITEM))
        if [[ "$line" =~ \"run\"[[:space:]]*: ]]; then
            rest="${line#*:}"
            while [[ "$rest" == *'$'* ]]; do
                rest="${rest#*'$'}"
                if [[ "$rest" == \{* ]]; then
                    if [[ "$rest" =~ ^\{([A-Za-z_][A-Za-z0-9_]*)\}(.*)$ ]]; then
                        rest="${BASH_REMATCH[2]}"
                    else
                        echo "Error: Invalid JSON in '$file': invalid placeholder syntax." >&2
                        printf 'Line %d: %s\n' "$line_number" "$line" >&2
                        return "$ERROR_STATUS"
                    fi
                fi
            done
        fi
    done < "$file"
    return "$SUCCESS_STATUS"
}

if ! validate_json_placeholders "$json_file"; then
    exit "$ERROR_STATUS"
fi

names=()
cmds=()
confirms=()
safes=()

# 3. Pure Bash JSON parser supporting name, run, boolean confirm, and safe
while IFS= read -r token; do
    if [[ "$token" =~ ^\"name\"[[:space:]]*:[[:space:]]*\"(.*)\"$ ]]; then
        val="${BASH_REMATCH[1]}"
        val="${val//\\\"/\"}"
        val="${val//\\\\/\\}"
        names+=("$val")
        confirms+=("false")
        safes+=("false")
    elif [[ "$token" =~ ^\"run\"[[:space:]]*:[[:space:]]*\"(.*)\"$ ]]; then
        val="${BASH_REMATCH[1]}"
        val="${val//\\\"/\"}"
        val="${val//\\\\/\\}"
        cmds+=("$val")
    elif [[ "$token" =~ ^\"confirm\"[[:space:]]*:[[:space:]]*(true|false)$ ]]; then
        if [[ ${#names[@]} -gt 0 ]]; then
            confirms[$((${#names[@]} - ONE_ITEM))]="${BASH_REMATCH[1]}"
        fi
    elif [[ "$token" =~ ^\"safe\"[[:space:]]*:[[:space:]]*(true|false)$ ]]; then
        if [[ ${#names[@]} -gt 0 ]]; then
            safes[$((${#names[@]} - ONE_ITEM))]="${BASH_REMATCH[1]}"
        fi
    fi
done < <(grep -oE '"(name|run)"[[:space:]]*:[[:space:]]*"([^"\\]|\\.)*"|"confirm"[[:space:]]*:[[:space:]]*(true|false)|"safe"[[:space:]]*:[[:space:]]*(true|false)' "$json_file")

count=${#names[@]}
if [[ $count -eq "$INITIAL_SELECTION_INDEX" || $count -ne ${#cmds[@]} ]]; then
    echo "Error: Invalid or empty JSON menu in '$json_file'." >&2
    exit "$ERROR_STATUS"
fi

names+=("$EDIT_CONFIG_NAME")
cmds+=("$EDIT_CONFIG_SENTINEL")
confirms+=("false")
safes+=("true")
count=${#names[@]}

selected=$INITIAL_SELECTION_INDEX

# 4. Terminal state protection
tput civis 2>/dev/null || true
cleanup() {
    tput cnorm 2>/dev/null || true
}
trap cleanup EXIT
trap 'exit_menu "$INTERRUPTED_STATUS"' INT TERM

is_destructive() {
    local cmd="$1"
    local safe="${2:-false}"
    if [[ "$safe" == "true" ]]; then
        return "$ERROR_STATUS"
    fi
    if [[ "$cmd" =~ $DESTRUCTIVE_COMMAND_PATTERN ]]; then
        return "$SUCCESS_STATUS"
    fi
    if [[ "$cmd" =~ $DESTRUCTIVE_REDIRECT_PATTERN ]]; then
        return "$SUCCESS_STATUS"
    fi
    return "$ERROR_STATUS"
}

command_collects_parameters() {
    local cmd="$1"
    if [[ "$cmd" =~ \$\{[A-Za-z_][A-Za-z0-9_]*\} ]]; then
        return "$SUCCESS_STATUS"
    fi
    return "$ERROR_STATUS"
}

open_menu_config() {
    local os_name=""
    local config_dir=""
    local config_name=""
    local previous_dir="$PWD"
    local candidate=""
    local editor=""
    local editor_status=0

    config_dir="$(cd -- "$(dirname -- "$json_file")" 2>/dev/null && pwd -P)" || {
        printf "Error: Unable to open menu config directory: %s\n" "$(dirname -- "$json_file")" >&2
        return "$ERROR_STATUS"
    }
    config_name="$(basename -- "$json_file")"
    cd -- "$config_dir" || return "$ERROR_STATUS"

    os_name="$(uname -s 2>/dev/null || printf 'Unknown')"
    case "$os_name" in
        MINGW*|MSYS*|CYGWIN*)
            if command -v notepad.exe >/dev/null 2>&1; then
                notepad.exe "$config_name" || editor_status=$?
            elif command -v notepad >/dev/null 2>&1; then
                notepad "$config_name" || editor_status=$?
            else
                printf "Error: notepad is not available on this system.\n" >&2
                cd -- "$previous_dir" || true
                return "$ERROR_STATUS"
            fi
            ;;
        *)
            for candidate in micro nano vim; do
                if command -v "$candidate" >/dev/null 2>&1; then
                    editor="$candidate"
                    break
                fi
            done
            if [[ -z "$editor" ]]; then
                printf "Error: No supported terminal editor found (tried micro, nano, vim).\n" >&2
                cd -- "$previous_dir" || true
                return "$ERROR_STATUS"
            fi
            "$editor" "$config_name" || editor_status=$?
            ;;
    esac
    cd -- "$previous_dir" || true
    return "$editor_status"
}

draw_menu() {
    local color=""
    for i in "${!names[@]}"; do
        color=""
        if [[ "${cmds[$i]}" == "$EDIT_CONFIG_SENTINEL" ]]; then
            color="$ANSI_GREY_PREFIX"
        elif is_destructive "${cmds[$i]}" "${safes[$i]}"; then
            color="$ANSI_RED_PREFIX"
        elif [[ "${confirms[$i]}" == "true" ]]; then
            color="$ANSI_YELLOW_PREFIX"
        elif command_collects_parameters "${cmds[$i]}"; then
            color="$ANSI_CYAN_PREFIX"
        fi

        if [[ $i -eq $selected ]]; then
            printf "${ANSI_BOLD_PREFIX}%s> %s${ANSI_RESET}\n" "$color" "${names[$i]}"
        else
            printf "%s  %s${ANSI_RESET}\n" "$color" "${names[$i]}"
        fi
    done
}

clear_menu() {
    printf "$ANSI_MOVE_UP_FORMAT" "$count"
    printf '\r%s' "$ANSI_CLEAR_TO_END"
}

exit_menu() {
    local exit_status="${1:-$SUCCESS_STATUS}"
    clear_menu
    exit "$exit_status"
}

draw_menu

while true; do
    while true; do
        IFS= read -rsn"$READ_ONE_CHAR" key || exit_menu "$SUCCESS_STATUS"

        if [[ $key == $'\x1b' ]]; then
            read -rsn"$READ_ESCAPE_CHARS" -t "$ARROW_KEY_READ_TIMEOUT" key2 || true
            key+="$key2"

            case "$key" in
                $'\x1b') # Escape
                    exit_menu "$SUCCESS_STATUS"
                    ;;
                $'\x1b[A') # Up arrow
                    ((selected--)) || true
                    [[ $selected -lt "$INITIAL_SELECTION_INDEX" ]] && selected=$((count - ONE_ITEM))
                    ;;
                $'\x1b[B') # Down arrow
                    ((selected++)) || true
                    [[ $selected -ge $count ]] && selected=$INITIAL_SELECTION_INDEX
                    ;;
                $'\x1b[C') # Right (forward) arrow
                    break
                    ;;
                $'\x1b[D') # Left (back) arrow
                    exit_menu "$SUCCESS_STATUS"
                    ;;
            esac
        elif [[ $key == "q" || $key == "Q" ]]; then
            exit_menu "$SUCCESS_STATUS"
        elif [[ $key == "" ]]; then
            break
        fi

        printf "$ANSI_MOVE_UP_FORMAT" "$count"
        draw_menu
    done

    cleanup

    final_cmd="${cmds[$selected]}"
    item_confirm="${confirms[$selected]}"
    item_safe="${safes[$selected]}"

    if [[ "$final_cmd" == "$EDIT_CONFIG_SENTINEL" ]]; then
        clear_menu
        if [[ "$dry_run" == true ]]; then
            printf "[dry-run] Edit config: %s\n" "$json_file"
            exit "$SUCCESS_STATUS"
        fi

        tput cnorm 2>/dev/null || true
        open_menu_config || true
        tput civis 2>/dev/null || true
        draw_menu
        continue
    fi

    clear_menu

prompt_placeholder_value() {
    local name="$1"
    local label="${name//_/ }"
    local value=""
    local key=""
    local key2=""

    printf '%s: ' "$label"
    while true; do
        IFS= read -rsn"$READ_ONE_CHAR" key || { printf '\n'; return "$ERROR_STATUS"; }
        if [[ "$key" == $'\x1b' ]]; then
            read -rsn"$READ_ESCAPE_CHARS" -t "$ARROW_KEY_READ_TIMEOUT" key2 || true
            printf '\n'
            return "$ERROR_STATUS"
        elif [[ "$key" == "" ]]; then
            printf '\n'
            COLLECTED_VALUE="$value"
            return "$SUCCESS_STATUS"
        elif [[ "$key" == $'\x7f' || "$key" == $'\b' ]]; then
            if [[ -n "$value" ]]; then
                value="${value%?}"
                printf '\b \b'
            fi
        else
            value+="$key"
            printf '%s' "$key"
        fi
    done
}

collect_placeholders() {
    local command="$1"
    local remaining="$command"
    local seen_names=""
    local placeholder=""
    local name=""
    local result=""
    local prefix=""
    declare -A placeholder_values=()

    while [[ "$remaining" =~ \$\{([A-Za-z_][A-Za-z0-9_]*)\} ]]; do
        placeholder="${BASH_REMATCH[0]}"
        name="${BASH_REMATCH[1]}"
        if [[ " $seen_names " != *" $name "* ]]; then
            seen_names+=" $name"
            if ! prompt_placeholder_value "$name"; then
                return "$ERROR_STATUS"
            fi
            placeholder_values["$name"]="$COLLECTED_VALUE"
        fi
        remaining="${remaining#*"${placeholder}"}"
    done

    remaining="$command"
    while [[ "$remaining" =~ \$\{([A-Za-z_][A-Za-z0-9_]*)\} ]]; do
        placeholder="${BASH_REMATCH[0]}"
        name="${BASH_REMATCH[1]}"
        prefix="${remaining%%"$placeholder"*}"
        remaining="${remaining#*"$placeholder"}"
        result="${result}${prefix}${placeholder_values[$name]}"
    done
    RESOLVED_COMMAND="${result}${remaining}"
    return "$SUCCESS_STATUS"
}

if ! collect_placeholders "$final_cmd"; then
    tput civis 2>/dev/null || true
    draw_menu
    continue
fi

final_cmd="$RESOLVED_COMMAND"

# 5. Destructive command detection
# Single-keypress confirmation helper
# Usage: prompt_confirm <message> <default: "Y" | "N">
prompt_confirm() {
    local prompt_msg="$1"
    local default_choice="${2:-Y}"
    local reply=""

    printf "%s" "$prompt_msg"
    while true; do
        IFS= read -rsn"$READ_ONE_CHAR" reply || { printf "\n"; exit "$ERROR_STATUS"; }
        case "$reply" in
            [Yy])
                printf "y\n"
                return "$SUCCESS_STATUS"
                ;;
            [Nn])
                printf "n\n"
                return "$ERROR_STATUS"
                ;;
            "")
                # Enter key follows the prompt's default choice
                if [[ "$default_choice" == "Y" ]]; then
                    printf "Y\n"
                    return "$SUCCESS_STATUS"
                else
                    printf "N\n"
                    return "$ERROR_STATUS"
                fi
                ;;
            $'\x1b')
                # Consume any trailing escape sequence bytes (e.g. arrow keys) and cancel
                read -rsn"$READ_ESCAPE_CHARS" -t "$PROMPT_ESCAPE_READ_TIMEOUT" _ || true
                printf "n\n"
                return "$ERROR_STATUS"
                ;;
        esac
    done
}

# 6. Dry-run output or confirmation + clean subshell execution
if [[ "$dry_run" == true ]]; then
    printf "[dry-run] %s\n" "$final_cmd"
    exit "$SUCCESS_STATUS"
fi

printf 'Command: %s\n' "$final_cmd"

if is_destructive "$final_cmd" "$item_safe"; then
    if ! prompt_confirm $'You are about to run a destructive command.\nProceed? [y/N]: ' "N"; then
        exit "$SUCCESS_STATUS"
    fi
elif [[ "$item_confirm" == "true" ]]; then
    if ! prompt_confirm $'Proceed? [Y/n]: ' "Y"; then
        exit "$SUCCESS_STATUS"
    fi
fi

unset names cmds confirms safes selected count json_file cli_json_file dry_run item_confirm item_safe
exec bash -c -- "$final_cmd"
done