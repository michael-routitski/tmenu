#!/usr/bin/env bats

setup() {
  export HOME="${BATS_TEST_TMPDIR}/home"
  mkdir -p "$HOME"
  SCRIPT_PATH="${BATS_TEST_DIRNAME}/../../install.sh"
  MENU_PATH="${BATS_TEST_DIRNAME}/../../install.menu.json"
}

@test "install.sh exists and is executable" {
  [ -x "$SCRIPT_PATH" ]
}

@test "install.sh help documents dry-run" {
  run bash "$SCRIPT_PATH" --help

  [ "$status" -eq 0 ]
  [[ "$output" == *"Usage: install.sh"* ]]
  [[ "$output" == *"--dry-run"* ]]
}

@test "install.sh rejects unknown options" {
  run bash "$SCRIPT_PATH" --unknown

  [ "$status" -eq 2 ]
  [[ "$output" == *"Unknown option"* ]]
}

@test "installer menu contains tmenu paths" {
  run grep -F '"name": "tmenu [with simple default menu]"' "$MENU_PATH"
  [ "$status" -eq 0 ]
  run grep -F '"name": "tmenu [with default menu from current aliases]"' "$MENU_PATH"
  [ "$status" -eq 0 ]
  run grep -F 'src/sh/tmenu.sh ~/.local/bin/tmenu' "$MENU_PATH"
  [ "$status" -eq 0 ]
  run grep -F '.tmenu-install-status' "$MENU_PATH"
  [ "$status" -eq 0 ]
}

@test "dry-run prints selection prompt and install command" {
  cd "$BATS_TEST_TMPDIR"

  run bash "$SCRIPT_PATH" --dry-run <<< $'\n'

  [ "$status" -eq 0 ]
  [[ "$output" == *"Select the tool to install"* ]]
  [[ "$output" == *"[dry-run] mkdir -p ~/.local/bin ~/.local/share/man/man1"* ]]
  [[ "$output" != *"is installed successfully"* ]]
  [[ "$output" != *"Usage instructions:"* ]]
  [[ "$output" != *"~/.local/bin/tmenu --help
Usage:"* ]]
}

@test "normal installation copies tmenu and prints help" {
  cd "$BATS_TEST_TMPDIR"

  run bash "$SCRIPT_PATH" <<< $'\n'

  [ "$status" -eq 0 ]
  [[ "$output" == *"Select the tool to install"* ]]
  [ -x "$HOME/.local/bin/tmenu" ]
  [ -f "$HOME/.local/share/man/man1/tmenu.1" ]
  [ ! -e "$HOME/.local/bin/.tmenu-install-status" ]
  [ -f "$HOME/.tmenu/tmenu.default.json" ]
  cmp "$BATS_TEST_DIRNAME/../../src/sh/tmenu.default.json" "$HOME/.tmenu/tmenu.default.json"
  [[ "$output" == *$'\033[32mtmenu is installed successfully in '"$HOME"'/.local/bin/tmenu\033[0m'* ]]
  [[ "$output" == *"Usage instructions:

Usage:"* ]]
  [[ "$output" == *"Usage: tmenu [OPTIONS] [JSON_FILE]"* ]]
}

@test "alias installation generates tmenu default from Bash aliases" {
  cd "$BATS_TEST_TMPDIR"
  printf "alias ll='ls -lh'\nalias test-alias=\"echo hello\"\n" > "$HOME/.bash_aliases"

  run bash "$SCRIPT_PATH" < <(printf '\033[B\n')

  [ "$status" -eq 0 ]
  [ -x "$HOME/.local/bin/tmenu" ]
  [ -f "$HOME/.tmenu/tmenu.default.json" ]
  run python3 -m json.tool "$HOME/.tmenu/tmenu.default.json"
  [ "$status" -eq 0 ]
  run grep -F '"name": "ll"' "$HOME/.tmenu/tmenu.default.json"
  [ "$status" -eq 0 ]
  run grep -F '"run": "ls -lh"' "$HOME/.tmenu/tmenu.default.json"
  [ "$status" -eq 0 ]
  run grep -F '"name": "test-alias"' "$HOME/.tmenu/tmenu.default.json"
  [ "$status" -eq 0 ]
}

@test "existing default menu is preserved when .tmenu exists" {
  cd "$BATS_TEST_TMPDIR"
  mkdir -p "$HOME/.tmenu"
  printf '[{"name":"custom","run":"printf custom","confirm":false}]' > "$HOME/.tmenu/tmenu.default.json"

  run bash "$SCRIPT_PATH" <<< $'\n'

  [ "$status" -eq 0 ]
  run grep -F '"name": "custom"' "$HOME/.tmenu/tmenu.default.json"
  [ "$status" -eq 0 ]
  run grep -F '"name": "List files"' "$HOME/.tmenu/tmenu.default.json"
  [ "$status" -eq 1 ]
}

@test "canceling installation does not print success or usage instructions" {
  cd "$BATS_TEST_TMPDIR"

  run bash "$SCRIPT_PATH" < <(printf '\033[D')

  [ "$status" -eq 0 ]
  [[ "$output" == *"Select the tool to install"* ]]
  [[ "$output" != *"is installed successfully"* ]]
  [[ "$output" != *"Usage instructions:"* ]]
  [ ! -e "$HOME/.local/bin/tmenu" ]
}
