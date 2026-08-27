# hyprland-canvas2d

A two-dimensional scrolling layout for Hyprland. Each configured workspace owns a flat set of world-space tile rectangles and an independent viewport. Tiles may exist outside the monitor, including at negative coordinates; the monitor shows only the translated portion of that canvas.

Verified against **Hyprland 0.56.2** (`efb50993780079460b0cbed1363e2166a2de1d9f`). Hyprland 0.55 or newer is required because this project uses the current Lua custom-layout API.

```text
     workspace-local world / canvas

  ┌ - - - - - - - - - - - - - - - - - - - ┐
  | ┌──────────┐┌────────┐┌────────────┐      |
  | │ focused  ││        ││            │      |
  | │ tile     ││        ││            │      |
  | └──────────┘└────────┘└────────────┘      |
  | ┌──────────────┐┌───────┐                 |
  | │              ││       │                 |
  | └──────────────┘└───────┘                 |
  └ - - - - - - - - - - - - - - - - - - - ┘
          ┌──────────────────┐
          │ monitor viewport │  ← pan left/right/up/down
          └──────────────────┘
```

The dashed boundary in the reference design is the virtual canvas. The green boundary is the monitor viewport. Focus changes select a spatial neighbor and move the viewport only when the focused tile would otherwise be outside its comfortable visible margin.

## Technical assessment

1. **Feasible:** yes on Hyprland 0.56.2. `hl.layout.register` can place tiled targets at arbitrary global boxes, including outside the monitor work area.
2. **Mechanism:** a Lua custom layout is the smallest supported implementation. A native plugin would add ABI coupling without improving keyboard-driven world geometry, focus, panning, insertion, movement, or resizing.
3. **Current APIs:** `hl.layout.register`, `target:place`, `ctx.area`, `ctx.targets`, `hl.dsp.layout`, `hl.dsp.focus`, `hl.dispatch`, `hl.on`, `hl.workspace_rule`, and Lua window/workspace objects.
4. **Native alternative:** Hyprland 0.56 exposes `HyprlandAPI::addTiledAlgo` and `Layout::ITiledAlgorithm`. It is only justified here if native mouse-resize deltas, drag-to-reorder, or a compositor-level viewport transform become mandatory.
5. **Serious API limitation:** the 0.56 Lua adapter's native `resizeTarget` callback discards the mouse delta and only recalculates. Keyboard resize is complete; native tiled mouse resize cannot be implemented correctly through Lua today.
6. **Data model:** `workspace ID → { viewport, tilesByStableTarget, deterministicOrder, insertionMode }`. Every tile is an independent `{x,y,w,h}` rectangle; there is no row/column matrix.
7. **Navigation:** directional half-plane filtering followed by a lexicographic spatial score. Perpendicular overlap always wins; then the algorithm minimizes primary edge distance, perpendicular center distance, and Euclidean distance. A weighted spatial-distance fallback handles diagonal candidates.

## Existing work considered

No maintained project found implements this exact combination: a tiled, workspace-local, two-dimensional world with a translated monitor viewport.

- Hyprland's [built-in scrolling layout](https://wiki.hypr.land/Configuring/Layouts/Scrolling-Layout/) is the closest stable base, but its canvas is a one-dimensional tape.
- [hyprscroller](https://github.com/dawsers/hyprscroller) is PaperWM-like and feature-rich, but one-dimensional and archived.
- [hypr-canvas](https://github.com/aaronsb/hypr-canvas) supplies map-like zoom/pan by hooking rendering and input internals; it explicitly describes itself as super-alpha and is not a tiled layout.
- [hyprland-canvas](https://github.com/zyrophix/hyprland-canvas) and [hyprland-infinitie-desktop-v2](https://github.com/sarodscommits/hyprland-infinitie-desktop-v2) pan floating windows through IPC/scripts rather than maintaining tiled world geometry.

The implementation reuses Hyprland's official target placement, work-area calculation, gaps, decorations, animation, fullscreen handling, focus dispatcher, and workspace rules instead of replacing compositor internals.

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
git clone https://github.com/danielrincondev/hyprland-canvas2d.git
cd hyprland-canvas2d
make test
make install
```

`make install` copies the Lua package to:

```text
${XDG_CONFIG_HOME:-$HOME/.config}/hypr/canvas2d/
```

Then load and configure it from `~/.config/hypr/hyprland.lua` (after the normal Omarchy/default configuration is loaded):

```lua
local canvas = require("canvas2d").setup({
    pan_step = 300,
    resize_step = 60,
    viewport_margin = 48,
})

hl.workspace_rule({ workspace = "1", layout = canvas.layout })
hl.workspace_rule({ workspace = "2", layout = "scrolling" })
hl.workspace_rule({ workspace = "3", layout = "dwindle" })
hl.workspace_rule({ workspace = "4", layout = "monocle" })
```

The full mixed-layout/keybinding example is [`examples/hyprland.lua`](examples/hyprland.lua). On Omarchy, inspect conflicts before copying it:

```sh
omarchy menu keybindings --print
```

After changing the live Hyprland Lua config:

```sh
hyprctl reload
hyprctl configerrors
```

`hyprctl configerrors` must be empty. Keep `misc:size_limits_tiled = false` (the Hyprland default): enabling that option clamps tiled positions to the monitor work area and conflicts with offscreen canvas coordinates.

## Layout messages

Use these through `hl.dsp.layout("...")` or `canvas.command("...")`. For a live one-off command on Hyprland 0.56, use `hyprctl eval 'hl.dispatch(hl.dsp.layout("pan right 300"))'`.

| Message | Behavior |
|---|---|
| `focus left/right/up/down` | Focus best spatial neighbor and minimally reveal it. |
| `pan left/right/up/down [amount]` | Move only the viewport; default is `pan_step`. |
| `move left/right/up/down` | Swap focused and neighboring world rectangles. |
| `swap left/right/up/down` | Alias of `move`. |
| `resize left/right/up/down [signed amount]` | Move one edge; positive grows toward that direction, negative shrinks. |
| `insert auto/left/right/up/down` | Set this workspace's policy for future tiled windows. |
| `center focused` | Center the focused tile without changing world geometry. |
| `fit all` | Derive a temporary viewport scale/translation that shows all live tiles. |
| `reset viewport` | Restore viewport `(0,0)` and scale `1`. |

Hyphenated forms such as `focus-left`, `move-window-down`, `center-focused`, `fit-all`, and `reset-viewport` are also accepted.

### Mixed-layout bindings

`canvas.command(message, fallback)` returns a Lua keybinding function. It sends the canvas message only when the active workspace uses `lua:canvas2d`; otherwise it invokes the supplied normal Hyprland dispatcher.

```lua
hl.bind("SUPER + H", canvas.command(
    "focus left",
    hl.dsp.focus({ direction = "left" })
))

hl.bind("SUPER + CTRL + H", canvas.command("pan left"), { repeating = true })
hl.bind("SUPER + SHIFT + H", canvas.command(
    "move left",
    hl.dsp.window.move({ direction = "left" })
))
```

## Insertion and resize rules

`auto` insertion places the new tile to the right of the focused tile and pushes intersecting tiles in that direction. Once the geometric span of that horizontal band would exceed `wrap_width_ratio × viewport width`, insertion starts a new band below the current canvas bounds. This is only an insertion policy: storage, navigation, movement, resize, and collision checks operate directly on rectangles, so boundaries between bands need not align.

Explicit insertion modes place beside the focused rectangle and propagate collisions away from the inserted tile. Left/up insertion may create negative coordinates.

Resize finds the nearest set of rectangles that overlap the focused tile on the perpendicular axis. Empty space is consumed first; further growth moves the shared boundary and shrinks all neighbors at that boundary, clamped by `min_width`/`min_height`. Shrink returns space to touching neighbors. The invariant is positive minimum size and no accidental overlap.

## Configuration

| Option | Default | Meaning |
|---|---:|---|
| `tile_width_ratio` | `0.50` | New tile width relative to current logical work-area width. |
| `tile_height_ratio` | `0.55` | New tile height relative to current logical work-area height. |
| `wrap_width_ratio` | `2.10` | Automatic insertion band span before wrapping downward. |
| `min_width` | `160` | Minimum world-space tile width. |
| `min_height` | `100` | Minimum world-space tile height. |
| `pan_step` | `300` | Default pan amount in world logical pixels. |
| `resize_step` | `60` | Default edge movement in world logical pixels. |
| `viewport_margin` | `48` | Comfortable reveal margin in screen logical pixels. |
| `fit_padding` | `32` | Screen-space padding used by `fit all`. |
| `min_fit_scale` | `0.10` | Lower fit-all scale bound. |
| `max_fit_scale` | `1.00` | Upper fit-all scale bound. |
| `diagonal_weight` | `2.00` | Penalty for perpendicular distance without lane overlap. |
| `insertion` | `"auto"` | Initial per-workspace insertion mode. |
| `auto_reveal` | `true` | Reveal tiled windows focused by clicks/default dispatchers. |
| `reveal_new` | `true` | Reveal a newly focused tile after insertion. |
| `layout_name` | `"canvas2d"` | Registered Lua layout name. |

Unknown or invalid options fail during config loading rather than being silently ignored.

## Development and verification

The source is dependency-free Lua. There is no build step.

```sh
make test       # deterministic geometry, state, lifecycle, adapter tests
make verify     # parse the API fixture with the installed Hyprland binary
make benchmark  # 10/25/50/100-window update benchmark
```

Measured on the development Ryzen 5 5500U with Lua 5.5.1:

| Windows | Initial bulk insertion | Focus + pan + translate-all update | Lua heap delta |
|---:|---:|---:|---:|
| 10 | 0.192 ms | 25.662 µs | 10.0 KiB |
| 25 | 1.147 ms | 56.646 µs | 15.2 KiB |
| 50 | 4.157 ms | 110.864 µs | 31.5 KiB |
| 100 | 18.077 ms | 216.692 µs | 63.3 KiB |

Normal viewport updates are linear in live tile count. Spatial neighbor searches are linear. Collision propagation and invariant checks are quadratic worst-case but run on insertion/test paths; even a one-shot 100-target rebuild remained below Hyprland 0.56's 50 ms Lua layout-callback watchdog on this machine.

## Known limitations

- **Hyprland version:** verified against 0.56.2. Lua layout APIs are new and can still change; 0.54 and older cannot load this project.
- **Mouse tiled resize:** unsupported by the current Lua adapter because it drops the resize delta before calling Lua. Keyboard resize messages are supported.
- **Mouse drag-to-reorder:** Hyprland's generic Lua adapter reorders its target list, not this project's world rectangles. Use directional keyboard movement. Click-to-focus and automatic reveal work.
- **Gestures:** no continuous pan-delta interface is exposed to this layout. Discrete gestures may invoke pan messages, but no default gesture is installed.
- **Animation:** panning uses normal Hyprland window geometry animations, not one compositor-level camera transform. A large canvas therefore updates every live tiled target.
- **Config reload/restart:** workspace state is in the Lua VM. Reloading the config or restarting Hyprland rebuilds a deterministic layout but does not persist prior world coordinates/viewports.
- **Groups:** a group is one layout target. Changing group topology can change the Lua-visible target identity and reinsert that target.
- **Fit all:** implemented by scaling target boxes/client sizes, not by a render-only zoom transform. `reset viewport` restores scale 1.
- **Fullscreen:** Hyprland's default fullscreen handler owns the visible fullscreen box; the world rectangle remains unchanged and returns after fullscreen exits. Unlike built-in scrolling, this layout has no custom layout-aware fullscreen handler that allows panning away from fullscreen.
- **Transient/dialog windows:** floating dialogs are excluded automatically. A dialog forced tiled is treated as a normal tile because the layout API provides no transient relationship on the target.
- **No `hyprpm` entry:** `hyprpm` manages ABI-sensitive binary plugins. This project is a Lua config module, so copying it into the config path is the appropriate install mechanism.

See [`docs/architecture.md`](docs/architecture.md) for invariants, lifecycle details, and the exact navigation score.

## License

MIT. See [`LICENSE`](LICENSE).
