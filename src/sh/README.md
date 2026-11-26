# tmenu

`tmenu.sh` is the Linux implementation of the interactive terminal command
launcher.

## Run

From the repository root:

```bash
bash src/sh/tmenu.sh
bash src/sh/tmenu.sh --dry-run
bash src/sh/tmenu.sh src/sh/menu-config-bundle/tmenu.git.json
```

The default configuration is `~/.tmenu/tmenu.default.json`, created by
`install.sh` from the simple menu or from Bash aliases.
Use-case JSON configurations are documented in
[`menu-config-bundle/README.md`](./menu-config-bundle/README.md).

## Controls

- Up/down arrows: change the highlighted item.
- Right arrow or Enter: select the item.
- Left arrow or Ctrl+C: cancel.
- Escape or left arrow: cancel placeholder collection and return to the menu.

## Bash Aliases

Replace `$HOME/path/to/dev-workflow-script-bundle` with the actual repository
path. Add these lines to `~/.bashrc` or `~/.bash_aliases`:

```bash
alias tmenu='bash "$HOME/path/to/dev-workflow-script-bundle/src/sh/tmenu.sh"'
alias tmenu-git='bash "$HOME/path/to/dev-workflow-script-bundle/src/sh/tmenu.sh" "$HOME/path/to/dev-workflow-script-bundle/src/sh/menu-config-bundle/tmenu.git.json"'
```

Reload:

```bash
source ~/.bashrc
# or: source ~/.bash_aliases
```

Nested menus are supported. A menu item may invoke `tmenu.sh` with another JSON
configuration, allowing hierarchical menu structures. The nested menu executes
only the item selected by the user.
