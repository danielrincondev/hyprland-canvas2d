# hyprland-grid

A two-dimensional scrolling layout for Hyprland. Each configured workspace owns a flat set of world-space tile rectangles and an independent viewport. 

## Features

- Independent canvas, viewport, insertion mode, and focus memory per workspace.
- Flat world-space rectangle model; unbounded positive and negative coordinates.
- Spatial focus in all four directions.
- Minimal automatic viewport reveal on keyboard focus or click focus.
- Explicit four-way panning with configurable/default amounts.
- Directional tile movement by swapping complete world rectangles.
- Coupled directional resize: a moved edge steals from or returns space to every split neighbor touching that edge.
- Automatic shelf wrapping plus persistent `insert left/right/up/down/auto` modes.
- `center focused`, `fit all`, and `reset viewport`.
- Mixed layouts through current `hl.workspace_rule({ layout = ... })` syntax.
- Floating windows remain outside the canvas; a temporarily floated tile recovers its prior world rectangle when retiled.
- Monitor work-area origin, logical size, resolution, and scale changes affect only viewport derivation, not world geometry.
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
