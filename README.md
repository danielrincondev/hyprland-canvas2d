# hyprland-grid

A two-dimensional scrolling layout for Hyprland. By default, each workspace contains vertically stacked rows with independent horizontal scrolling and focus memory. A workspace-local toggle switches to a shared 2D canvas.

The layout is intentionally unlike a monitor split:

- The default rectangle uses the configured width and the full viewport height; explicit vertical resize can change it.
- Adding windows never redistributes or shrinks existing windows.
- Automatic insertion places windows to the right without a horizontal limit; explicit vertical operations create additional bands.
- Left/right/up/down insertion modes place a new fixed-size rectangle beside the focused one.
- Focus and window movement reveal the destination; explicit panning moves the viewport without changing focus or tile geometry.
- Resize commands are the only way to change a window's size. Width presets and signed pixel resizing are supported.
- Every workspace keeps its own canvas, viewport, insertion mode, and focus memory.
- Every row remembers its horizontal scroll position and last focused window. Up/down focus restores both, including an explicitly panned position.
- Overview mode fits every live tile, keeps directional selection zoomed out, and restores the prior viewport on exit.

## Installation

The Lua layout needs no compiler or native plugin. The optional native overview below requires a separate build.

```sh
git clone https://github.com/danielrincondev/hyprland-canvas2d.git
cd hyprland-canvas2d
make test
make install
```

`make install` copies the Lua package to:

```text
${XDG_CONFIG_HOME:-$HOME/.config}/hypr/grid/
```

Load and configure it from `~/.config/hypr/hyprland.lua` after the normal Omarchy/default configuration:

```lua
local grid = require("grid").setup({
    tile_width_ratio = 0.50,
    tile_height_ratio = 1.00,
    width_presets = { 0.34, 0.50, 0.67, 1.00 },
    new_window_position = "center", -- default; "reveal" scrolls only until the window is visible
    pan_step = 300,
    resize_step = 60,
    viewport_margin = 0,
    row_gap = 48, -- logical pixels between rows; keep larger than the reserved top bar
    scroll_mode = "rows", -- default; "shared" starts with one workspace canvas
})

hl.workspace_rule({ workspace = "1", layout = grid.layout })
hl.workspace_rule({ workspace = "2", layout = "scrolling" })
hl.workspace_rule({ workspace = "3", layout = "dwindle" })
hl.workspace_rule({ workspace = "4", layout = "monocle" })
```

After changing the live Hyprland Lua config:

```sh
hyprctl reload
hyprctl configerrors
```

`hyprctl configerrors` must be empty. Keep `misc:size_limits_tiled = false`: enabling it clamps tiled positions to the monitor work area and conflicts with offscreen canvas coordinates.

## Native zoom-out overview

For a Niri-style animated zoom of the actual desktop, use [ScrollOverview](https://github.com/yayuuu/hyprland-scroll-overview). Window buffers are rendered smaller without resizing applications, including grid windows outside the monitor and vertically stacked rows. Each row retains its own scrolling state.

```sh
make install-native-overview
```

This builds a pinned upstream revision against your installed Hyprland headers and applies the fixes in [`native/scrolloverview.patch`](native/scrolloverview.patch): safe closing after monitor removal, vertical navigation between rows that do not overlap horizontally, and keyboard submap activation through the current Hyprland API. It requires Git, Make, a C++23 compiler, and the development dependencies listed in upstream's Makefile (including Lua 5.4 and Hyprland).

Add this after your regular bindings:

```lua
require("grid.native_overview").setup({ scale = 0.30 })
```

`Super+Tab` opens/closes the overview, replacing the usual next-workspace shortcut. Workspaces are arranged horizontally in numeric order; rows stay vertical inside each workspace. Use `key = "SUPER + CTRL + SHIFT + O"` in setup to choose another overview shortcut.

- Arrows or `H/J/K/L`, optionally with Super, select a window inside the current workspace. Scrolling also stops at workspace boundaries.
- `Super+1…9/0` switches to workspace 1…9/10 while keeping overview open.
- `Super+Shift+Arrow` (or H/J/K/L) moves the selected window using the grid's row/column movement rules.
- `Super+Space` opens the Omarchy menu. The menu receives typing and navigation until it closes, then overview captures input again. Set `menu_command` in setup to use another launcher.
- Enter selects the window without sending Enter to the application. Escape closes with the current selection. Other typing is consumed while overview owns keyboard focus.

The integration also enables horizontal slide animations for ordinary workspace switching, using the same ease-out curve and speed as Omarchy's window movement. Overview temporarily controls its own transition and restores this animation after closing.

The scale is configurable from `0.1` to `0.9`; smaller values show more of the canvas. This is a fixed zoom level, not automatic fitting of an unlimited canvas. The native overview is separate from the Lua `overview`/`fit all` layout messages, which change client geometry; use the native shortcut for visual zoom. Grid-specific row reordering by dragging is not integrated.

Native plugins must match the running Hyprland ABI. Rebuild after Hyprland updates, then restart the session to use the new library. Versioned libraries avoid overwriting a loaded binary. To disable automatic loading, remove the setup line and restart Hyprland.

## Layout messages

### Shared rows across workspaces

`Super+Ctrl+Shift+P` in the example configuration toggles sharing for the
focused row. The same shortcut works in native overview. A notification confirms
whether the row is shared or local.

Shared rows follow the active **normal grid workspace**, carrying their real
windows, sizes, order, horizontal scroll and row focus memory. A destination's
existing focused window keeps focus. Shared rows always stay above
local rows, including when first shared and when new local rows are inserted.
Several rows can be shared; their order follows when sharing was enabled. Other layouts and special workspaces are skipped.

```lua
hl.bind("SUPER + CTRL + SHIFT + P", grid.command("share toggle"))
-- Optional explicit scope, including the workspace where sharing is enabled:
-- hl.bind("SUPER + CTRL + SHIFT + P", grid.command("share on 1,2,3"))
```

`share on` enables sharing, `share on 1,2,3` limits it to those workspace IDs,
and `share off` leaves the row in its current workspace. Windows inserted or
moved into a shared row join it; moving a window out makes that window local.
Closing the final window removes the shared row. Ungroup tabbed windows before
sharing. Floating windows are not moved with a tiled row.

There is one interactive copy: on multiple monitors the row follows the focused
grid workspace. In overview it appears in its current owning workspace and moves
when you explicitly switch workspaces; mirrored copies in inactive cards are not
implemented. Sharing and layout state survive config reloads within the same
Hyprland process. Restarting the desktop starts a new session.

### Commands

Use these through `hl.dsp.layout("...")` or `grid.command("...")`.

Toggle the active grid workspace with this binding (also included in the example config):

```lua
hl.bind("SUPER + CTRL + SHIFT + S", grid.command("scroll toggle"))
```

`scroll rows` and `scroll shared` select a mode explicitly. Switching to shared mode uses the current horizontal offset for every row; switching back restores each row's saved offset. Other workspaces keep their own modes. Mode changes are ignored while the built-in overview is open. Check existing bindings before assigning the shortcut.

| Message | Behavior |
|---|---|
| `share [toggle/on/off] [all/1,2,3]` | Share the focused row across grid workspaces, optionally restricting its scope. |
| `scroll rows/shared/toggle` | Select or toggle independent row scrolling and a shared 2D canvas for this workspace. |
| `focus left/right/up/down` | In row mode, left/right follows row order and up/down restores the adjacent row's focus and horizontal offset. Shared mode uses spatial neighbors. |
| `pan left/right/up/down [amount]` | In row mode, horizontal panning affects the focused row; vertical panning affects the workspace. Shared mode pans the whole canvas. Default is `pan_step`. |
| `move left/right/up/down` | Horizontal moves swap within a lane. Vertical moves transfer the focused window to the adjacent row, append it after that row's existing windows, and compact the old row; at an empty edge they create a row at the canvas' leading edge. `swap` is an alias. |
| `resize left/right` | Cycle the focused width through `width_presets`; the affected row is reflowed so shrinking never leaves a gap. |
| `resize left/right [signed amount]` | Grow or shrink the focused width by pixels while keeping the affected row contiguous. Growing or shrinking moves neighboring rectangles instead of changing their sizes. |
| `resize up/down [signed amount]` | Grow or shrink only the focused height by pixels; collisions are pushed vertically. |
| `cycle width [forward/backward]` | Explicit width-preset command. |
| `insert auto/left/right/up/down` | Set this workspace's policy for future tiled windows. |
| `center focused` | Center the focused tile without changing world geometry. |
| `fit all` | Apply a one-shot viewport scale and translation for all live tiles. Normal focus or viewport commands may replace it. |
| `overview enter/toggle` | Save the viewport and enter a persistent fit of all live tiles. `toggle` activates the selection when already open. |
| `overview focus left/right/up/down` | Select a spatial neighbor without leaving the fitted overview. The normal `focus` command has the same overview-aware behavior. |
| `overview activate/exit` | Close overview, restore the saved viewport, focus the selection, and minimally reveal it. |
| `overview cancel` | Close overview and restore the exact saved viewport and the original focus when that target is still live. |
| `reset viewport` | Reset the focused row's horizontal offset (or the shared canvas offset), workspace vertical offset, and scale to `(0,0,1)`. Other rows keep their offsets. Ignored while overview is open. |

Hyphenated forms such as `focus-left`, `move-window-down`, `center-focused`, `fit-all`, `overview-toggle`, `overview-focus-right`, and `reset-viewport` are accepted.

`grid.command(message, fallback)` sends the grid message only on grid workspaces and invokes the supplied normal Hyprland dispatcher elsewhere. See [`examples/hyprland.lua`](examples/hyprland.lua).

## Coordinate model

`row_gap` adds a minimum vertical separation between rows in logical pixels, without resizing tiles or changing horizontal scroll memory. It defaults to `0` for compatibility; the example uses `48` to clear the reserved top bar when focusing a full-height row. Increase it if your bar or navigation margin is taller. The spacing remains when switching to shared scrolling.

A workspace's rectangles live in world coordinates. In default row mode, `horizontalOffset` is the tile's row offset. In shared mode, and during a fitted overview, it is `viewport.x`:

```text
screenX = area.x + (tile.x - horizontalOffset) * viewport.scale
screenY = area.y + (tile.y - viewport.y) * viewport.scale
screenW = tile.w * viewport.scale
screenH = tile.h * viewport.scale
```

Panning is deliberately unrestricted, so a viewport may show empty canvas beyond every tile. Horizontal focus and window moves reveal their destination; vertical focus in row mode restores the exact saved horizontal offset and reveals only vertically. `pan` never changes focus or tile rectangles. `fit all` temporarily fits the shared world bounds without overwriting row offsets; the next normal focus, reveal, center, or pan resumes row mode at scale `1`. Overview makes the fit persistent: focus, automatic reveal, panning, centering, and reset cannot displace it, and target lifecycle changes recompute it. Unlike normal `fit all`, overview may scale below `min_fit_scale` when necessary to keep every live tile on screen.

The canvas bounds are the bounds of live rectangles. Negative coordinates are valid after left/up insertion or resizing. Monitor origin, resolution, and scale changes update viewport dimensions but preserve existing world rectangles; newly opened windows use the current monitor dimensions for their default size.

## Insertion and movement

`auto` inserts after the focused tile on its horizontal band without a horizontal span limit. Each new default window extends the canvas to the right; explicit vertical insertion or movement creates additional bands.

Explicit `left`, `right`, `up`, and `down` insertion uses the focused rectangle's edge and the new rectangle's own default width and height. Collision propagation translates existing rectangles in the requested direction. It never changes their dimensions.

Rows have stable identities that survive resizing and vertical compaction. In row mode, horizontal focus and movement follow explicit membership; up/down focus returns to the adjacent row's last live focused window, or the closest horizontal screen position on its first visit. Shared mode uses spatial focus. Vertical movement transfers the focused window between rows, appends it to the destination row, and compacts the source row. At an empty edge, it creates a row at the canvas' leading edge (the minimum world `x`). The focused window is minimally revealed after every move.

## Resizing

`tile_width_ratio` and `tile_height_ratio` determine the size of new windows. `new_window_position = "center"` (the default) scrolls the viewport so a newly opened window sits in the middle of the screen; `"reveal"` keeps the older behavior of scrolling only as far as needed, with a row's first window flush against the left edge. The default `tile_height_ratio = 1.00` makes each unresized horizontal band fill the viewport height. These values do not describe a split and do not change when more windows are opened. `min_width` and `min_height` clamp every live rectangle.

`resize left/right` cycles the focused width relative to the current monitor width. Width cycling reflows only the focused row from that row's own left edge, so its windows stay stacked left-to-right and rows remain independent. `resize up/down [amount]` changes only the focused rectangle's height. A signed horizontal amount retains the explicit named-edge behavior; vertical growth still pushes collisions in that direction. All geometry remains non-overlapping and horizontal rows have no resize gaps.

## Lifecycle

- Workspace state is keyed by Hyprland workspace ID.
- Closing a focused window selects a same-row neighbor when that row still has windows. If it was the row's last window, the row is deleted, later rows move up, and focus moves to the next row or the preceding row when no next row exists.
- Moving a window to another workspace removes it from the old workspace before destination insertion.
- Returning floating windows reuse their stored rectangles; occupied space is cleared by pushing collisions to the right without resizing windows.
- Floating and fullscreen handling remains owned by Hyprland.
- Standard Hyprland move/resize animations animate translated target boxes.

## Development and verification

The source is dependency-free Lua and has no compiler build step:

```sh
make test
make verify
make benchmark
```

`make test` covers geometry, fixed-size insertion, independent row scrolling, mode toggles, movement, resize, panning, lifecycle, overview transitions, focus dispatch, and the Lua adapter. The original shared-canvas behavior has its own regression coverage. `make verify` parses the API fixture with the installed Hyprland binary.

`python3 tests/shared-smoke.py --instance <nested-instance>` exercises real
shared-row keybindings, workspace ownership, focus, scrolling, scopes, reloads,
overview, and window closure in an empty isolated compositor with native overview
enabled. See [`native/README.md`](native/README.md) for starting that fixture.

The Lua custom-layout API does not expose a reliable mouse tiled-resize delta or drag-to-reorder hook. Keyboard layout messages are therefore the supported way to resize and move windows.

## License

MIT. See [`LICENSE`](LICENSE).
