# tmenu
[T]erminal [MENU]: A simple and elegant alternative to typing bash aliases. Easily configurable inline menu of commands that you navigate with arrow keys.

## Ergonomics

- Navigate with arrow keys only: less typing and distractions.
- Easy configuration via JSON files in `~/.tmenu` by default or place menu configs anywhere you want.
- Menu definition config is the only positional argument: `tmenu <path_to_menu_config>`.
- Define one short alias for a group of commands
  
  `
$ dim
  Set DP-1 brightness to 0.3
  Set DP-1 brightness to 0.4
  Set DP-1 brightness to 0.5
  Set DP-1 brightness to 0.6
  Set DP-1 brightness to 0.7
> Set DP-1 brightness to 0.8
  Set DP-1 brightness to 0.9
  Set DP-1 brightness to FULL
  Edit config...
  `

## Capabilities

- Build-in safety protection against running common destructive bash commands without confirmation.
- Configure menu items for commands that can collect command parameters.
- Configure menu items to require the [y/N] confirmation.
- Create nested sub-menus by configuring `tmenu <path_to_sub_menu_config>>` as run command in menus.

## Zero Dependencies

- No dependencies on any tools or commands whatsoever, pure bash runs on bare-bones Linux install.

## Follows Linux Phylosophy

- Does one thing and does it well.
