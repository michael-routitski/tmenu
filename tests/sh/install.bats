#!/usr/bin/env bats

setup() {
  export HOME="${BATS_TEST_TMPDIR}/home"
  export TMENU_INSTALL_ROOT="${HOME}/install-root"
  mkdir -p "$HOME"
  mkdir -p "$BATS_TEST_TMPDIR/bin"
  cat > "$BATS_TEST_TMPDIR/bin/sudo" <<'EOF'
#!/usr/bin/env bash
exec "$@"
EOF
  chmod +x "$BATS_TEST_TMPDIR/bin/sudo"
  export PATH="$BATS_TEST_TMPDIR/bin:$PATH"
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
  run grep -F 'bash install.sh --install-selected simple' "$MENU_PATH"
  [ "$status" -eq 0 ]
  run grep -F 'bash install.sh --install-selected aliases' "$MENU_PATH"
  [ "$status" -eq 0 ]
  run grep -F '"confirm": true' "$MENU_PATH"
  [ "$status" -eq 0 ]
}

@test "dry-run prints selection prompt and install command" {
  cd "$BATS_TEST_TMPDIR"

  run bash "$SCRIPT_PATH" --dry-run <<< $'\ny\n'

  [ "$status" -eq 0 ]
  [[ "$output" == *"Select the tool to install"* ]]
  [[ "$output" == *"[dry-run] sudo install -D -m 755"* ]]
  [[ "$output" == *"$TMENU_INSTALL_ROOT/bin/tmenu"* ]]
  [[ "$output" == *"$TMENU_INSTALL_ROOT/share/man/man1/tmenu.1"* ]]
  [[ "$output" != *"is installed successfully"* ]]
  [[ "$output" != *"Usage instructions:"* ]]
  [[ "$output" != *"$TMENU_INSTALL_ROOT/bin/tmenu --help
Usage:"* ]]
}

@test "normal installation copies tmenu and prints help" {
  cd "$BATS_TEST_TMPDIR"

  run bash "$SCRIPT_PATH" <<< $'\ny\n'

  [ "$status" -eq 0 ]
  [[ "$output" == *"Select the tool to install"* ]]
  [ -x "$TMENU_INSTALL_ROOT/bin/tmenu" ]
  [ -f "$TMENU_INSTALL_ROOT/share/man/man1/tmenu.1" ]
  [ ! -e "$HOME/.tmenu/.tmenu-install-status" ]
  [ -f "$HOME/.tmenu/tmenu.default.json" ]
  cmp "$BATS_TEST_DIRNAME/../../src/sh/tmenu.default.json" "$HOME/.tmenu/tmenu.default.json"
  [[ "$output" == *$'\033[32mtmenu is installed successfully in '"$TMENU_INSTALL_ROOT"'/bin/tmenu\033[0m'* ]]
  [[ "$output" == *"Usage instructions:

Usage:"* ]]
  [[ "$output" == *"Usage: tmenu [OPTIONS] [JSON_FILE]"* ]]
}

@test "alias installation generates tmenu default from Bash aliases" {
  cd "$BATS_TEST_TMPDIR"
  printf "alias ll='ls -lh'\nalias test-alias=\"echo hello\"\n" > "$HOME/.bash_aliases"

  run bash "$SCRIPT_PATH" < <(printf '\033[B\ny\n')

  [ "$status" -eq 0 ]
  [ -x "$TMENU_INSTALL_ROOT/bin/tmenu" ]
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

  run bash "$SCRIPT_PATH" <<< $'\ny\n'

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
  [ ! -e "$TMENU_INSTALL_ROOT/bin/tmenu" ]
}
