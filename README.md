# tmenu
[T]erminal [MENU]: A simple and elegant alternative to typing bash aliases. Easily configurable inline menu of commands that you navigate with arrow keys.

## Ergonomics

- Navigate with arrow keys only: less typing and distractions.
- Easy configuration via JSON files in `~/.tmenu` by default or place menu configs anywhere you want.
- Menu definition config is the only positional argument: `tmenu <path_to_menu_config>`.
- Define one short alias for a group of commands

## Capabilities

- Build-in safety protection against running common destructive bash commands without confirmation.
- Configure menu items for commands that can collect command parameters.
- Configure menu items to require the [y/N] confirmation.
- Create nested sub-menus by configuring `tmenu <path_to_sub_menu_config>>` as run command in menus.

## Zero Dependencies

- No dependencies on any tools or commands whatsoever, pure bash runs on bare-bones Linux install.

## Follows Linux Phylosophy

- Does one thing and does it well.


## Demo

A simple menu to dim the display

Step 1. Define menu config `~/.tmenu/tmenu.dp-1-brightness.json`:
   
```
[
  { "name": "Set DP-1 brightness to 0.3", "run": "xrandr --output DP-1 --brightness 0.3", "confirm": false },
  { "name": "Set DP-1 brightness to 0.4", "run": "xrandr --output DP-1 --brightness 0.4", "confirm": false },
  { "name": "Set DP-1 brightness to 0.5", "run": "xrandr --output DP-1 --brightness 0.5", "confirm": false },
  { "name": "Set DP-1 brightness to 0.6", "run": "xrandr --output DP-1 --brightness 0.6", "confirm": false },
  { "name": "Set DP-1 brightness to 0.7", "run": "xrandr --output DP-1 --brightness 0.7", "confirm": false },
  { "name": "Set DP-1 brightness to 0.8", "run": "xrandr --output DP-1 --brightness 0.8", "confirm": false },
  { "name": "Set DP-1 brightness to 0.9", "run": "xrandr --output DP-1 --brightness 0.9", "confirm": false },
  { "name": "Set DP-1 brightness to FULL", "run": "xrandr --output DP-1 --brightness 1.0", "confirm": false }
]
```

Step 2: Create a short alias in `~/.bashrc`:

```
alias dim="tmenu ~/.tmenu/tmenu.dp-1-brightness.json"
```

Step 3: Enjoy:

```
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
```

