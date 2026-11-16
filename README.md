# Type to search

An [Omarchy](https://omarchy.org) shell plugin. When the current workspace has
no windows, start typing to open the Omarchy menu (the one on
<kbd>Super</kbd>+<kbd>Space</kbd>) with your text already in its search line.
You don't need to press a shortcut first.

Type `chr` on an empty desktop to open the menu filtered to Chrome, then press
<kbd>Enter</kbd>.

## Install

```bash
omarchy plugin add https://github.com/HaseebAzhar02/omarchy-type-to-search.git --enable
omarchy restart shell
```

The restart makes sure the new service starts. A plugin that was just added
does not always load until the shell restarts.

## How it works

- While the focused workspace is empty, an invisible 1×1 layer surface takes
  the keyboard. It uses on-demand focus, so it never blocks a window or another
  panel, and it ignores the mouse, so clicks go straight to the desktop.
- The first printable key opens the menu. Keys typed before the menu finishes
  opening are buffered. They go into the search line as soon as the menu has
  the keyboard, so nothing typed is lost and the menu opens where it always
  does.
- Opening a window gives that window the keyboard.
- The plugin stays out of the way:
  - It does nothing while a special workspace (scratchpad, console) is shown.
  - Keys with <kbd>Ctrl</kbd>, <kbd>Alt</kbd> or <kbd>Super</kbd> are ignored,
    so every Hyprland binding works as before.
  - A space on its own does not open the menu.

Nothing is logged or stored. Keys reach the plugin only while the desktop is
empty, and only the text you type goes to the menu.

## Uninstall

```bash
omarchy plugin remove io.github.haseebazhar02.type-to-search
```

To turn it off without removing it:
`omarchy plugin disable io.github.haseebazhar02.type-to-search`.

## Troubleshooting

```bash
omarchy-shell type-to-search state
```

On an empty workspace you should see `"armed":true,"mapped":true,"focused":true`.

- If `armed` is `false`, the plugin thinks the workspace has a window or that a
  special workspace is shown.
- If `focused` is `false`, the compositor did not give the surface the
  keyboard. Switching workspaces or closing and reopening a panel retries.

## Requirements

- Omarchy 4.5 or newer: Hyprland, and the Quickshell-based `omarchy-shell`.
- The plugin calls the menu's `setFilter` function. That function is internal
  to Omarchy, and an Omarchy update could rename it.

## License

MIT
