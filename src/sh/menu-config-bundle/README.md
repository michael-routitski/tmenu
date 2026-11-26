# tmenu Use-Case JSON Configurations

Use-case JSON configurations for the Linux `tmenu.sh` command launcher.
The default configuration is `~/.tmenu/tmenu.default.json`. This directory
contains use-case-specific configurations.

## Bundled Configurations

- `tmenu.git.json` provides a menu for common Git operations.

## Run Menu With Each Configuration

From the repository root:

```bash
# Use the default configuration
bash src/sh/tmenu.sh

# Use the default configuration explicitly
bash src/sh/tmenu.sh ~/.tmenu/tmenu.default.json

# Use the Git configuration
bash src/sh/tmenu.sh src/sh/menu-config-bundle/tmenu.git.json
```

Add `-n` or `--dry-run` before the JSON path to print the selected command
instead of executing it:

```bash
bash src/sh/tmenu.sh --dry-run src/sh/menu-config-bundle/tmenu.git.json
```

## Command Placeholders

Use `${variable_name}` in a `run` value to collect a value after selecting the
item:

```json
{"name":"Create directory","run":"mkdir ${dir_name}","confirm":true}
```

This prompts for `dir name:` and uses the exact entered value in the command.
Empty values are accepted. Press Escape or the left arrow to abort collection
and return to the menu.

Only `${variable_name}` syntax is supported. Bare `$variable_name` syntax is
invalid and reports the JSON source line.

