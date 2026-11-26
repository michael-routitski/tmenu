#!/usr/bin/env bash
set -euo pipefail
IFS=$'\n\t'

readonly SCRIPT_DIR="$(cd "$(dirname "$(readlink -f "${BASH_SOURCE[0]}")")" && pwd)"
readonly TMENU_SCRIPT="${SCRIPT_DIR}/src/sh/tmenu.sh"
readonly INSTALL_MENU="${SCRIPT_DIR}/install.menu.json"

readonly SUCCESS_STATUS=0
readonly RUNTIME_ERROR_STATUS=1
readonly INVALID_ARGUMENT_STATUS=2
readonly ANSI_GREEN_PREFIX=$'\e[32m'
readonly ANSI_RESET=$'\e[0m'
readonly SIMPLE_DEFAULT_CONFIG="${SCRIPT_DIR}/src/sh/tmenu.default.json"

show_help() {
  cat <<EOF
Usage: $(basename "$0") [OPTIONS]

Interactively select a bundled tool and install it for the current Linux user.

Options:
  -n, --dry-run      Print the selected install command without executing it
  -h, --help         Show this help message and exit
EOF
}

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
  exec bash "$TMENU_SCRIPT" --dry-run "$INSTALL_MENU"
fi

readonly INSTALL_STATUS_MARKER="${HOME}/.local/bin/.tmenu-install-status"
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

readonly INSTALLED_EXECUTABLE="${HOME}/.local/bin/tmenu"
printf "${ANSI_GREEN_PREFIX}tmenu is installed successfully in %s${ANSI_RESET}\n" "$INSTALLED_EXECUTABLE"
printf 'Usage instructions:\n\n'
"${INSTALLED_EXECUTABLE}" --help
