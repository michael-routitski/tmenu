#!/usr/bin/env bash
set -euo pipefail
IFS=$'\n\t'

readonly SCRIPT_DIR="$(cd "$(dirname "$(readlink -f "${BASH_SOURCE[0]}")")" && pwd)"
readonly TMENU_SCRIPT="${SCRIPT_DIR}/src/sh/tmenu.sh"
readonly TMENU_MAN_PAGE="${SCRIPT_DIR}/src/sh/tmenu.1"
readonly INSTALL_MENU="${SCRIPT_DIR}/install.menu.json"
readonly INSTALL_ROOT="${TMENU_INSTALL_ROOT:-/usr/local}"
readonly INSTALL_BIN_DIR="${INSTALL_ROOT%/}/bin"
readonly INSTALL_MAN_DIR="${INSTALL_ROOT%/}/share/man/man1"

readonly SUCCESS_STATUS=0
readonly RUNTIME_ERROR_STATUS=1
readonly INVALID_ARGUMENT_STATUS=2
readonly ANSI_GREEN_PREFIX=$'\e[32m'
readonly ANSI_RESET=$'\e[0m'
readonly SIMPLE_DEFAULT_CONFIG="${SCRIPT_DIR}/src/sh/tmenu.default.json"

show_help() {
  cat <<EOF
Usage: $(basename "$0") [OPTIONS]

Interactively select a bundled tool and install it system-wide on this Linux machine.

Options:
  -n, --dry-run      Print the selected install command without executing it
  -h, --help         Show this help message and exit
EOF
}

install_selected_tool() {
  local install_mode="$1"

  if [[ "$install_mode" != "simple" && "$install_mode" != "aliases" ]]; then
    printf "Error: Invalid install mode '%s'.\n" "$install_mode" >&2
    return "$INVALID_ARGUMENT_STATUS"
  fi

  if [[ -z "${HOME:-}" ]]; then
    printf "Error: HOME is not set.\n" >&2
    return "$RUNTIME_ERROR_STATUS"
  fi

  for dependency in sudo install; do
    if ! command -v "$dependency" >/dev/null 2>&1; then
      printf "Error: Missing required dependency '%s'.\n" "$dependency" >&2
      return "$INVALID_ARGUMENT_STATUS"
    fi
  done

  if [[ "${TMENU_INSTALL_DRY_RUN:-false}" == true ]]; then
    printf '[dry-run] sudo install -D -m 755 %s %s\n' "$TMENU_SCRIPT" "${INSTALL_BIN_DIR}/tmenu"
    printf '[dry-run] sudo install -D -m 644 %s %s\n' "$TMENU_MAN_PAGE" "${INSTALL_MAN_DIR}/tmenu.1"
    return "$SUCCESS_STATUS"
  fi

  if ! sudo install -D -m 755 "$TMENU_SCRIPT" "${INSTALL_BIN_DIR}/tmenu"; then
    printf "Error: Failed to install tmenu to %s.\n" "${INSTALL_BIN_DIR}/tmenu" >&2
    return "$RUNTIME_ERROR_STATUS"
  fi

  if ! sudo install -D -m 644 "$TMENU_MAN_PAGE" "${INSTALL_MAN_DIR}/tmenu.1"; then
    printf "Error: Failed to install the tmenu man page to %s.\n" "${INSTALL_MAN_DIR}/tmenu.1" >&2
    return "$RUNTIME_ERROR_STATUS"
  fi

  mkdir -p -- "${HOME}/.tmenu"
  printf '%s\n' "$install_mode" > "${HOME}/.tmenu/.tmenu-install-status"
}

if [[ "${1:-}" == "--install-selected" ]]; then
  if [[ $# -ne 2 ]]; then
    printf "Error: Internal install mode requires a selection.\n" >&2
    exit "$INVALID_ARGUMENT_STATUS"
  fi
  install_selected_tool "$2"
  exit $?
fi

dry_run=false

while [[ $# -gt 0 ]]; do
  case "$1" in
    -n|--dry-run)
      dry_run=true
      shift
      ;;
    -h|--help)
      show_help
      exit "$SUCCESS_STATUS"
      ;;
    -*)
      printf "Error: Unknown option '%s'. Run '%s --help' for usage.\n" "$1" "$(basename "$0")" >&2
      exit "$INVALID_ARGUMENT_STATUS"
      ;;
    *)
      printf "Error: Unexpected argument '%s'. Run '%s --help' for usage.\n" "$1" "$(basename "$0")" >&2
      exit "$INVALID_ARGUMENT_STATUS"
      ;;
  esac
done

for dependency in bash mkdir cp readlink rm; do
  if ! command -v "$dependency" >/dev/null 2>&1; then
    printf "Error: Missing required dependency '%s'.\n" "$dependency" >&2
    exit "$INVALID_ARGUMENT_STATUS"
  fi
done

if [[ ! -f "$TMENU_SCRIPT" || ! -r "$TMENU_SCRIPT" ]]; then
  printf "Error: tmenu implementation not found or unreadable: %s\n" "$TMENU_SCRIPT" >&2
  exit "$RUNTIME_ERROR_STATUS"
fi

if [[ ! -f "$INSTALL_MENU" || ! -r "$INSTALL_MENU" ]]; then
  printf "Error: Installer menu not found or unreadable: %s\n" "$INSTALL_MENU" >&2
  exit "$RUNTIME_ERROR_STATUS"
fi

if [[ -z "${HOME:-}" ]]; then
  printf "Error: HOME is not set.\n" >&2
  exit "$RUNTIME_ERROR_STATUS"
fi

readonly TMENU_CONFIG_DIR="${HOME}/.tmenu"
mkdir -p -- "$TMENU_CONFIG_DIR"
readonly DEFAULT_CONFIG="${TMENU_CONFIG_DIR}/tmenu.default.json"

printf 'Select the tool to install\n' >&2

cd "$SCRIPT_DIR"

if [[ "$dry_run" == true ]]; then
  TMENU_INSTALL_DRY_RUN=true bash "$TMENU_SCRIPT" "$INSTALL_MENU"
  exit $?
fi

readonly INSTALL_STATUS_MARKER="${HOME}/.tmenu/.tmenu-install-status"
rm -f -- "$INSTALL_STATUS_MARKER"

if bash "$TMENU_SCRIPT" "$INSTALL_MENU"; then
  menu_status="$SUCCESS_STATUS"
else
  menu_status=$?
fi

if [[ "$menu_status" -ne "$SUCCESS_STATUS" ]]; then
  rm -f -- "$INSTALL_STATUS_MARKER"
  exit "$menu_status"
fi

if [[ ! -f "$INSTALL_STATUS_MARKER" ]]; then
  exit "$SUCCESS_STATUS"
fi

install_mode="$(cat -- "$INSTALL_STATUS_MARKER")"
rm -f -- "$INSTALL_STATUS_MARKER"

if [[ ! -e "$DEFAULT_CONFIG" && "$install_mode" == "simple" ]]; then
  cp -p -- "$SIMPLE_DEFAULT_CONFIG" "$DEFAULT_CONFIG"
elif [[ ! -e "$DEFAULT_CONFIG" && "$install_mode" == "aliases" ]]; then
  : > "$DEFAULT_CONFIG"
  printf '[\n' >> "$DEFAULT_CONFIG"

  alias_count=0
  declare -A generated_aliases=()
  for alias_file in "${HOME}/.bashrc" "${HOME}/.bash_aliases"; do
    [[ -f "$alias_file" && -r "$alias_file" ]] || continue
    while IFS= read -r line || [[ -n "$line" ]]; do
      line="${line#"${line%%[![:space:]]*}"}"
      [[ "$line" == alias\ * ]] || continue

      alias_definition="${line#alias }"
      alias_name="${alias_definition%%=*}"
      alias_value="${alias_definition#*=}"
      alias_name="${alias_name//[[:space:]]/}"
      [[ -n "$alias_name" && "$alias_value" != "$alias_definition" ]] || continue
      [[ "$alias_name" =~ ^[A-Za-z_][A-Za-z0-9_-]*$ ]] || continue
      [[ -z "${generated_aliases[$alias_name]+x}" ]] || continue
      generated_aliases[$alias_name]=1

      if [[ "$alias_value" =~ ^\'(.*)\'$ ]]; then
        alias_value="${BASH_REMATCH[1]}"
      elif [[ "$alias_value" =~ ^\"(.*)\"$ ]]; then
        alias_value="${BASH_REMATCH[1]}"
      fi

      alias_value="${alias_value//\\\\/\\}"
      alias_value="${alias_value//\"/\\\"}"

      if [[ "$alias_count" -gt 0 ]]; then
        printf ',\n' >> "$DEFAULT_CONFIG"
      fi
      printf '  { "name": "%s", "run": "%s", "confirm": false }' \
        "$alias_name" "$alias_value" >> "$DEFAULT_CONFIG"
      alias_count=$((alias_count + 1))
    done < "$alias_file"
  done

  printf '\n]\n' >> "$DEFAULT_CONFIG"
fi

readonly INSTALLED_EXECUTABLE="${INSTALL_BIN_DIR}/tmenu"
printf "${ANSI_GREEN_PREFIX}tmenu is installed successfully in %s${ANSI_RESET}\n" "$INSTALLED_EXECUTABLE"
printf 'Usage instructions:\n\n'
"${INSTALLED_EXECUTABLE}" --help
