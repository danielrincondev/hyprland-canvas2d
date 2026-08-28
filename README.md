# hyprland-grid

A two-dimensional scrolling layout for Hyprland. Each workspace owns a set of fixed-size world rectangles and an independent viewport. The monitor shows only the translated portion of that workspace canvas.

The layout is intentionally unlike a monitor split:

- The default rectangle uses the configured width and the full viewport height; explicit vertical resize can change it.
- Adding windows never redistributes or shrinks existing windows.
- Automatic insertion places windows to the right without a horizontal limit; explicit vertical operations create additional bands.
- Left/right/up/down insertion modes place a new fixed-size rectangle beside the focused one.
- Focus and window movement reveal the destination; explicit panning moves the viewport without changing focus or tile geometry.
- Resize commands are the only way to change a window's size. Width presets and signed pixel resizing are supported.
- Every workspace keeps its own canvas, viewport, insertion mode, and focus memory.

## Installation

No compiler, plugin ABI, or `hyprpm` package is involved.

```sh
git clone https://github.com/danielrincondev/hyprland-grid.git
cd hyprland-grid
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
    pan_step = 300,
    resize_step = 60,
    viewport_margin = 0,
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

## Layout messages

Use these through `hl.dsp.layout("...")` or `grid.command("...")`.

| Message | Behavior |
|---|---|
| `focus left/right/up/down` | Focus the best spatial neighbor; horizontal focus stays in the current row and minimally reveals the destination. |
| `pan left/right/up/down [amount]` | Move only the viewport; default is `pan_step`. |
| `move left/right/up/down` | Horizontal moves swap within a lane. Vertical moves transfer the focused window to the adjacent row, append it after that row's existing windows, and compact the old row; at an empty edge they create a row at the canvas' leading edge. `swap` is an alias. |
| `resize left/right` | Cycle the focused width through `width_presets`; the affected row is reflowed so shrinking never leaves a gap. |
| `resize left/right [signed amount]` | Grow or shrink the focused width by pixels while keeping the affected row contiguous. Growing or shrinking moves neighboring rectangles instead of changing their sizes. |
| `resize up/down [signed amount]` | Grow or shrink only the focused height by pixels; collisions are pushed vertically. |
| `cycle width [forward/backward]` | Explicit width-preset command. |
| `insert auto/left/right/up/down` | Set this workspace's policy for future tiled windows. |
| `center focused` | Center the focused tile without changing world geometry. |
| `fit all` | Temporarily scale the viewport to show all live tiles. |
| `reset viewport` | Restore viewport `(0,0)` and scale `1`. |

Hyphenated forms such as `focus-left`, `move-window-down`, `center-focused`, `fit-all`, and `reset-viewport` are accepted.

`grid.command(message, fallback)` sends the grid message only on grid workspaces and invokes the supplied normal Hyprland dispatcher elsewhere. See [`examples/hyprland.lua`](examples/hyprland.lua).

## Coordinate model

A workspace's rectangles live in world coordinates. The viewport is independent:

```text
screenX = area.x + (tile.x - viewport.x) * viewport.scale
screenY = area.y + (tile.y - viewport.y) * viewport.scale
screenW = tile.w * viewport.scale
screenH = tile.h * viewport.scale
```

Panning is deliberately unrestricted, so a viewport may show empty canvas beyond every tile. `focus` and `move` call the minimal reveal rule; `pan` never changes focus or tile rectangles. `fit all` changes only viewport scale and translation.

The canvas bounds are the bounds of live rectangles. Negative coordinates are valid after left/up insertion or resizing. Monitor origin, resolution, and scale changes update viewport dimensions but preserve existing world rectangles; newly opened windows use the current monitor dimensions for their default size.

## Insertion and movement

`auto` inserts after the focused tile on its horizontal band without a horizontal span limit. Each new default window extends the canvas to the right; explicit vertical insertion or movement creates additional bands.

Explicit `left`, `right`, `up`, and `down` insertion uses the focused rectangle's edge and the new rectangle's own default width and height. Collision propagation translates existing rectangles in the requested direction. It never changes their dimensions.

Directional focus uses derived rectangle geometry; horizontal focus and movement stay in the current visual lane instead of falling through to another row. Vertical movement transfers the focused window between rows instead of swapping it with a diagonal neighbor, appends it to the destination row, and compacts the source row. At an empty edge, it creates a row at the canvas' leading edge (the minimum world `x`). The focused window is minimally revealed after every move.

## Resizing

`tile_width_ratio` and `tile_height_ratio` determine the size of new windows. The default `tile_height_ratio = 1.00` makes each unresized horizontal band fill the viewport height. These values do not describe a split and do not change when more windows are opened. `min_width` and `min_height` clamp every live rectangle.

`resize left/right` cycles the focused width relative to the current monitor width. Width cycling reflows only the focused row from that row's own left edge, so its windows stay stacked left-to-right and rows remain independent. `resize up/down [amount]` changes only the focused rectangle's height. A signed horizontal amount retains the explicit named-edge behavior; vertical growth still pushes collisions in that direction. All geometry remains non-overlapping and horizontal rows have no resize gaps.

## Lifecycle

- Workspace state is keyed by Hyprland workspace ID.
- Closing a focused window selects a same-row neighbor when that row still has windows. If it was the row's last window, the row is deleted, later rows move up, and focus moves to the next row or the preceding row when no next row exists.
- Moving a window to another workspace removes it from the old workspace before destination insertion.
- Floating and fullscreen handling remains owned by Hyprland.
- Standard Hyprland move/resize animations animate translated target boxes.

## Development and verification

The source is dependency-free Lua and has no compiler build step:

```sh
make test
make verify
make benchmark
```

`make test` covers geometry, fixed-size insertion, multi-row scrolling, movement, resize, panning, lifecycle, and the Lua adapter. `make verify` parses the API fixture with the installed Hyprland binary.

The Lua custom-layout API does not expose a reliable mouse tiled-resize delta or drag-to-reorder hook. Keyboard layout messages are therefore the supported way to resize and move windows.

## License

MIT. See [`LICENSE`](LICENSE).
