#!/usr/bin/env bats

setup() {
  export XDG_CONFIG_HOME="${BATS_TEST_TMPDIR}/config"
  export HOME="${BATS_TEST_TMPDIR}/home"
  mkdir -p "$HOME"
  SCRIPT_PATH="${BATS_TEST_DIRNAME}/../../src/sh/tmenu.sh"
}

@test "tmenu.sh exists and is executable" {
  [ -x "$SCRIPT_PATH" ]
}

@test "tmenu.sh uses the bundled default from outside the tool directory" {
  cd "$BATS_TEST_TMPDIR"
  mkdir -p "$HOME/.tmenu"
  cp "${BATS_TEST_DIRNAME}/../../src/sh/tmenu.default.json" "$HOME/.tmenu/tmenu.default.json"

  run bash "$SCRIPT_PATH" --dry-run </dev/null

  [ "$status" -eq 0 ]
  [[ "$output" == *"List files"* ]]
  [[ "$output" == *"Print working directory"* ]]
}

@test "help documents menu config paths" {
  run bash "$SCRIPT_PATH" --help

  [ "$status" -eq 0 ]
  [[ "$output" == *"Menu Config Path:"* ]]
  [[ "$output" == *"tmenu.sh /absolute/path/to/menu.json"* ]]
  [[ "$output" != *"MR_DEV_WORKFLOW_TMENU_CONFIG"* ]]
}

@test "environment variable is ignored" {
  env_config="$BATS_TEST_TMPDIR/ignored.json"
  printf '[{"name":"ignored","run":"echo ignored","confirm":false}]' > "$env_config"

  MR_DEV_WORKFLOW_TMENU_CONFIG="$env_config" run bash "$SCRIPT_PATH" --dry-run </dev/null

  [ "$status" -eq 0 ]
  [[ "$output" == *"List files"* ]]
  [[ "$output" != *"ignored"* ]]
}

@test "bundled default contains common Linux commands" {
  default_config="${BATS_TEST_DIRNAME}/../../src/sh/tmenu.default.json"

  run grep -F '"name": "List files"' "$default_config"

  [ "$status" -eq 0 ]
  run grep -F '"run": "ls -la"' "$default_config"
  [ "$status" -eq 0 ]
  run grep -F '"run": "pwd"' "$default_config"
  [ "$status" -eq 0 ]
}

@test "bundled git menu includes safe undo local commit action" {
  git_config="${BATS_TEST_DIRNAME}/../../src/sh/menu-config-bundle/tmenu.git.json"

  run grep -F '"name": "Undo local commit"' "$git_config"
  [ "$status" -eq 0 ]
  run grep -F 'git reset --soft HEAD^' "$git_config"
  [ "$status" -eq 0 ]
  run grep -F 'refs/remotes/' "$git_config"
  [ "$status" -eq 0 ]
}

@test "bundled git menu includes commit and commit-with-push actions" {
  git_config="${BATS_TEST_DIRNAME}/../../src/sh/menu-config-bundle/tmenu.git.json"

  run grep -F '"name": "Stage all + Commit"' "$git_config"
  [ "$status" -eq 0 ]
  run grep -F 'git add -A && git commit -m "${commit_message}"' "$git_config"
  [ "$status" -eq 0 ]
  run grep -F '"name": "Stage all + Commit + Push"' "$git_config"
  [ "$status" -eq 0 ]
  run grep -F 'git push -u origin HEAD' "$git_config"
  [ "$status" -eq 0 ]
}

@test "destructive menu items are red" {
  config="$BATS_TEST_TMPDIR/colors.json"
  printf '[{"name":"delete file","run":"rm -f old.txt","confirm":false}]' > "$config"

  run bash "$SCRIPT_PATH" --dry-run "$config" </dev/null

  [ "$status" -eq 0 ]
  [[ "$output" == *$'\033[1m\033[31m> delete file\033[0m'* ]]
}

@test "safe items bypass destructive pattern matching" {
  config="$BATS_TEST_TMPDIR/colors.json"
  printf '[{"name":"open remote editor","run":"printf safe >/dev/null","confirm":false,"safe":true}]' > "$config"

  run bash "$SCRIPT_PATH" "$config" <<< $'\n'

  [ "$status" -eq 0 ]
  [[ "$output" != *"destructive command"* ]]
  [[ "$output" != *$'\033[31m'* ]]
  [[ "$output" == *"open remote editor"* ]]
}

@test "safe items with confirm still require confirmation" {
  config="$BATS_TEST_TMPDIR/colors.json"
  printf '[{"name":"open remote editor","run":"printf safe >/dev/null","confirm":true,"safe":true}]' > "$config"

  run bash "$SCRIPT_PATH" "$config" <<< $'\nn'

  [ "$status" -eq 0 ]
  [[ "$output" == *$'\033[33m'* ]]
  [[ "$output" == *"Proceed? [Y/n]"* ]]
  [[ "$output" != *"destructive command"* ]]
}

@test "confirmed menu items are yellow" {
  config="$BATS_TEST_TMPDIR/colors.json"
  printf '[{"name":"restart service","run":"printf restarted","confirm":true}]' > "$config"

  run bash "$SCRIPT_PATH" --dry-run "$config" </dev/null

  [ "$status" -eq 0 ]
  [[ "$output" == *$'\033[1m\033[33m> restart service\033[0m'* ]]
}

@test "parameterized menu items are cyan" {
  config="$BATS_TEST_TMPDIR/colors.json"
  printf '[{"name":"create directory","run":"mkdir ${dir_name}","confirm":false}]' > "$config"

  run bash "$SCRIPT_PATH" --dry-run "$config" </dev/null

  [ "$status" -eq 0 ]
  [[ "$output" == *$'\033[1m\033[36m> create directory\033[0m'* ]]
}

@test "edit config item is appended in dim grey" {
  config="$BATS_TEST_TMPDIR/edit-menu.json"
  printf '[{"name":"hello","run":"printf hello","confirm":false}]' > "$config"

  run bash "$SCRIPT_PATH" --dry-run "$config" < <(printf '\033[B\n')

  [ "$status" -eq 0 ]
  [[ "$output" == *$'\033[90m  Edit config...\033[0m'* ]]
  [[ "$output" == *"[dry-run] Edit config: $config"* ]]
}

@test "Linux edit config prefers micro" {
  config="$BATS_TEST_TMPDIR/edit-menu.json"
  printf '[{"name":"hello","run":"printf hello","confirm":false}]' > "$config"
  editor_bin="$BATS_TEST_TMPDIR/bin"
  mkdir -p "$editor_bin"
  cat >"$editor_bin/micro" <<'EOF'
#!/bin/sh
printf '%s\n' "$PWD|$*" > "$TMENU_EDITOR_OUTPUT"
EOF
  chmod +x "$editor_bin/micro"

  run env PATH="$editor_bin:/usr/bin:/bin" TMENU_EDITOR_OUTPUT="$BATS_TEST_TMPDIR/editor-output" bash "$SCRIPT_PATH" "$config" < <(printf '\033[B\n')

  [ "$status" -eq 0 ]
  [ "$(cat "$BATS_TEST_TMPDIR/editor-output")" = "$BATS_TEST_TMPDIR|edit-menu.json" ]
  [[ "$output" == *"Edit config..."* ]]
}

@test "Windows edit config opens notepad" {
  config="$BATS_TEST_TMPDIR/edit-menu.json"
  printf '[{"name":"hello","run":"printf hello","confirm":false}]' > "$config"
  editor_bin="$BATS_TEST_TMPDIR/bin"
  mkdir -p "$editor_bin"
  cat >"$editor_bin/uname" <<'EOF'
#!/bin/sh
printf 'MINGW64_NT-10.0\n'
EOF
  cat >"$editor_bin/notepad.exe" <<'EOF'
#!/bin/sh
printf '%s\n' "$PWD|$*" > "$TMENU_EDITOR_OUTPUT"
EOF
  chmod +x "$editor_bin/uname" "$editor_bin/notepad.exe"

  run env PATH="$editor_bin:/usr/bin:/bin" TMENU_EDITOR_OUTPUT="$BATS_TEST_TMPDIR/editor-output" bash "$SCRIPT_PATH" "$config" < <(printf '\033[B\n')

  [ "$status" -eq 0 ]
  [ "$(cat "$BATS_TEST_TMPDIR/editor-output")" = "$BATS_TEST_TMPDIR|edit-menu.json" ]
  [[ "$output" == *"Edit config..."* ]]
}

@test "left arrow clears the menu and exits" {
  config="$BATS_TEST_TMPDIR/exit-menu.json"
  printf '[{"name":"hello","run":"printf hello","confirm":false}]' > "$config"

  run bash "$SCRIPT_PATH" "$config" < <(printf '\033[D')

  [ "$status" -eq 0 ]
  [[ "$output" == *$'\033[2A\r\033[0J'* ]]
  [[ "$output" != *"Command:"* ]]
}

@test "q clears the menu and exits" {
  config="$BATS_TEST_TMPDIR/exit-menu.json"
  printf '[{"name":"hello","run":"printf hello","confirm":false}]' > "$config"

  run bash "$SCRIPT_PATH" "$config" <<< 'q'

  [ "$status" -eq 0 ]
  [[ "$output" == *$'\033[2A\r\033[0J'* ]]
  [[ "$output" != *"Command:"* ]]
}

@test "escape clears the menu and exits" {
  config="$BATS_TEST_TMPDIR/exit-menu.json"
  printf '[{"name":"hello","run":"printf hello","confirm":false}]' > "$config"

  run bash "$SCRIPT_PATH" "$config" < <(printf '\033')

  [ "$status" -eq 0 ]
  [[ "$output" == *$'\033[2A\r\033[0J'* ]]
  [[ "$output" != *"Command:"* ]]
}

@test "execution clears the menu and prints the command at the menu position" {
  config="$BATS_TEST_TMPDIR/menu.json"
  printf '[{"name":"hello","run":"printf hello","confirm":false}]' > "$config"

  run env COLUMNS=100 bash "$SCRIPT_PATH" "$config" <<< $'\n'

  [ "$status" -eq 0 ]
  [[ "$output" == *$'\033[2A\r\033[0JCommand: printf hello'* ]]
  [[ "$output" == *"hello"* ]]
  [[ "$output" != *"----------------------------------------------------------------"* ]]
}

@test "execution clears a multi-item menu before printing the command" {
  config="$BATS_TEST_TMPDIR/menu.json"
  printf '[{"name":"hello","run":"printf hello","confirm":false},{"name":"world","run":"printf world","confirm":false}]' > "$config"

  run env COLUMNS=20 bash "$SCRIPT_PATH" "$config" <<< $'\n'

  [ "$status" -eq 0 ]
  [[ "$output" == *$'\033[3A\r\033[0JCommand: printf hello'* ]]
  [[ "$output" != *"----------------------------------------------------------------"* ]]
}

@test "placeholder value is collected and resolved for execution" {
  config="$BATS_TEST_TMPDIR/placeholders.json"
  printf '[{"name":"print value","run":"printf ${dir_name}","confirm":false}]' > "$config"

  run env COLUMNS=100 bash "$SCRIPT_PATH" "$config" <<< $'\n"project files"\n'

  [ "$status" -eq 0 ]
  [[ "$output" == *"dir name:"* ]]
  [[ "$output" == *'Command: printf "project files"'* ]]
}

@test "placeholder value is collected and resolved in dry-run mode" {
  config="$BATS_TEST_TMPDIR/placeholders.json"
  printf '[{"name":"print value","run":"printf %%s ${input_value}","confirm":false}]' > "$config"

  run env COLUMNS=100 bash "$SCRIPT_PATH" --dry-run "$config" <<< $'\nhello\n'

  [ "$status" -eq 0 ]
  [[ "$output" == *"input value:"* ]]
  [[ "$output" == *"[dry-run] printf %s hello"* ]]
  [[ "$output" != *"Command:"* ]]
}

@test "escape aborts placeholder collection and returns to the menu" {
  config="$BATS_TEST_TMPDIR/placeholders.json"
  printf '[{"name":"print value","run":"printf %s ${input_value}","confirm":false}]' > "$config"

  run env COLUMNS=100 bash "$SCRIPT_PATH" "$config" < <(printf '\n\033')

  [ "$status" -eq 0 ]
  [[ "$output" == *"input value:"* ]]
  [[ "$output" != *"Command:"* ]]
  [[ "$output" != *"[dry-run]"* ]]
}

@test "left arrow aborts placeholder collection and returns to the menu" {
  config="$BATS_TEST_TMPDIR/placeholders.json"
  printf '[{"name":"print value","run":"printf %%s ${input_value}","confirm":false}]' > "$config"

  run env COLUMNS=100 bash "$SCRIPT_PATH" "$config" < <(printf '\n\033[D')

  [ "$status" -eq 0 ]
  [[ "$output" == *"input value:"* ]]
  [[ "$output" != *"Command:"* ]]
  [[ "$output" != *"[dry-run]"* ]]
}

@test "empty placeholder input is passed to the command" {
  config="$BATS_TEST_TMPDIR/placeholders.json"
  printf '[{"name":"print value","run":"printf ${input_value}","confirm":false}]' > "$config"

  run env COLUMNS=100 bash "$SCRIPT_PATH" --dry-run "$config" <<< $'\n\n'

  [ "$status" -eq 0 ]
  [[ "$output" == *"input value:"* ]]
  [[ "$output" == *"[dry-run] printf "* ]]
}

@test "shell environment variables pass through to Bash" {
  config="$BATS_TEST_TMPDIR/shell-variables.json"
  printf '%s\n' '[{"name":"print environment value","run":"printf %s \"$TMENU_TEST_ROOT\"","confirm":false}]' > "$config"

  run env TMENU_TEST_ROOT="atv2 root" bash "$SCRIPT_PATH" "$config" <<< $'\n'

  [ "$status" -eq 0 ]
  [[ "$output" == *"atv2 root"* ]]
}

@test "invalid braced placeholder syntax is rejected with the source line" {
  config="$BATS_TEST_TMPDIR/invalid-placeholders.json"
  printf '[\n  {"name":"bad","run":"mkdir ${dir-name}","confirm":false}\n]\n' > "$config"

  run bash "$SCRIPT_PATH" "$config" </dev/null

  [ "$status" -eq 1 ]
  [[ "$output" == *"Invalid JSON"* ]]
  [[ "$output" == *"invalid placeholder syntax"* ]]
  [[ "$output" == *"Line 2:"* ]]
  [[ "$output" == *'mkdir ${dir-name}'* ]]
}

@test "nested tmenu invocations are supported" {
  child_config="$BATS_TEST_TMPDIR/child-menu.json"
  parent_config="$BATS_TEST_TMPDIR/parent-menu.json"
  printf '[{"name":"child action","run":"printf child","confirm":false}]' > "$child_config"
  printf '[{"name":"child menu","run":"bash %s %s","confirm":false}]' "$SCRIPT_PATH" "$child_config" > "$parent_config"

  run bash "$SCRIPT_PATH" "$parent_config" <<< $'\n\n'

  [ "$status" -eq 0 ]
  [[ "$output" == *"child menu"* ]]
  [[ "$output" == *"child action"* ]]
  [[ "$output" == *"Command: printf child"* ]]
  [[ "$output" == *"child"* ]]
}

@test "missing default config prints a red error followed by help" {
  tool_dir="$BATS_TEST_TMPDIR/tmenu-tool"
  mkdir "$tool_dir"
  cp "$SCRIPT_PATH" "$tool_dir/tmenu.sh"

  run bash "$tool_dir/tmenu.sh" </dev/null

  [ "$status" -eq 1 ]
  [[ "$output" == *$'\033[31mError: Readable file'* ]]
  [[ "$output" == *"$HOME/.tmenu/tmenu.default.json"* ]]
  [[ "$output" == *"Usage: tmenu.sh [OPTIONS] [JSON_FILE]"* ]]
  [[ "$output" == *"Expected JSON Format:"* ]]
}
