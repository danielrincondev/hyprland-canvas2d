# hyprland-grid

A two-dimensional scrolling layout for Hyprland built on a **structural model**: each workspace owns ordered rows of cells and an independent viewport. Window rectangles are derived from that structure (`rows × cells`, weighted) rather than stored per window, so closing any window automatically makes its former neighbors adjacent, rows always split the full screen height, and cell widths can never exceed the screen. The viewport pans freely across the canvas and reveals focused windows minimally.

## Features

- Independent canvas, viewport, insertion mode, and focus memory per workspace.
- Structural row/cell model; placement is derived, so closing any window automatically makes its former neighbors adjacent and every row/cell always spans its axis fully.
- First window fills the work area; subsequent windows stack right of focus at default-width presets.
- `Super+Shift+Down` demotes the whole focused window into the row below (creating it when absent) aligned near its source edge; `Up` promotes symmetrically. Horizontal moves reorder within the row and wrap at its edges.
- Vertical resize transfers height between neighbor rows and is clamped so no row can shrink below the minimum; single-row workspaces refuse it.
- Widths cycle through configurable presets relative to siblings and are clamped so total width never exceeds the screen.
- Spatial focus in all four directions over derived geometry.
- Minimal automatic viewport reveal on keyboard focus or click focus.
- Explicit four-way panning with configurable/default amounts.
- Persistent `insert left/right/up/down/auto` modes.
- `center focused`, `fit all`, and `reset viewport`.
- Mixed layouts through current `hl.workspace_rule({ layout = ... })` syntax.
- Floating windows remain outside the canvas; retitling a floated window inserts it fresh at the current anchor.
- Monitor work-area origin, logical size, resolution, and scale changes rescale the derived canvas while preserving structure proportions.
- Standard Hyprland window movement/resize animations apply to viewport translations.

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

Then load and configure it from `~/.config/hypr/hyprland.lua` (after the normal Omarchy/default configuration is loaded):

```lua
local grid = require("grid").setup({
    pan_step = 300,
    resize_step = 60,
    viewport_margin = 48,
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

`hyprctl configerrors` must be empty. Keep `misc:size_limits_tiled = false` (the Hyprland default): enabling that option clamps tiled positions to the monitor work area and conflicts with offscreen canvas coordinates.


## License

MIT. See [`LICENSE`](LICENSE).
