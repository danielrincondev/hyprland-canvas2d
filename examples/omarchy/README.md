# Omarchy setup

The author's live Omarchy configuration for this layout, copied from
`~/.config/hypr/`:

- `hyprland.lua` drops every Super binding except a short allow-list, so
  movement lives on Alt and Super only opens things.
- `bindings.lua` sets up the grid on workspaces 1–5 and mirrors every
  movement key for both hands (Left Alt and Right Alt, isolated to `MOD5` via
  `lv3:ralt_switch`).

| Action | Left Alt | Right Alt |
|---|---|---|
| Focus up / left / down / right | W A S D | O K L ; |
| + Shift: move window | W A S D | O K L ; |
| + Ctrl: resize (hold to repeat) | W A S D | O K L ; |
| Switch workspace 1–5 (zoom transition) | 1 2 3 4 5 | - 0 9 8 7 |
| + Shift: move window to workspace | 1 2 3 4 5 | - 0 9 8 7 |
| Center window | C | M |
| Last focused window (any workspace) | Tab | \ |
| Close window | X | , |
| Native overview | Space | |

Super: `1` terminal, `2` browser, `` ` `` Omarchy menu.
