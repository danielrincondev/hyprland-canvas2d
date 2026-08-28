# Architecture

## Boundary

`hyprland-grid` is a Hyprland 0.56 Lua tiled-layout provider. It owns fixed-size tiled world rectangles and viewport state. Hyprland continues to own:

- window and group targets;
- monitor/work-area discovery, including reserved layer-shell areas;
- gaps, borders, rounding, decorations, pseudotiling, and size configuration;
- floating, fullscreen, XWayland, focus, rendering, and animation;
- workspace creation, monitor assignment, and per-workspace layout selection.

The adapter uses public Lua facilities and does not hook compositor internals.

## Modules

```text
hypr/grid/
├── init.lua       Hyprland provider, event subscriptions, dispatcher adapter
├── engine.lua     workspace state, insertion, movement, resize, lifecycle
└── geometry.lua   rectangle predicates, directional neighbors, viewport math
```

`geometry.lua` and `engine.lua` have no Hyprland dependency. Tests run under a normal Lua interpreter. `init.lua` is covered by a fake `hl` surface matching the APIs used by the provider.

## State model

One engine contains a map keyed by Hyprland workspace ID:

```lua
workspaces[id] = {
    viewport = {
        x = 0,          -- world coordinate at viewport left
        y = 0,          -- world coordinate at viewport top
        width = 1920,   -- current monitor work-area width
        height = 1040,  -- current monitor work-area height
        scale = 1,
    },
    tiles = {
        ["window:42"] = {
            x = 0, y = 0, w = 960, h = 572,
            present = true,
        },
    },
    order = { "window:42" },
    focus_key = "window:42",
    insertion = "auto",
}
```

`tiles` is the source of truth. A tile's `x`, `y`, `w`, and `h` are world values and remain unchanged when another window is opened. `present = false` parks a temporarily absent target, such as a floating window, until a lifecycle callback deletes or moves it. `order` supplies deterministic fallback focus and insertion anchors.

`sync` marks all stored tiles absent, marks context targets present, inserts genuinely new targets, resolves active focus, and reveals an active newcomer. `window.close` removes a closed target. `window.move_to_workspace` removes the old-workspace record while allowing deterministic insertion in the destination workspace.

## Coordinate spaces

World coordinates are workspace-local and anchored at `(0, 0)` for the first tile. They are not clipped to the monitor. A viewport may show empty space or only part of the canvas.

For viewport scale `s`:

```text
screenX = area.x + (tile.x - viewport.x) × s
screenY = area.y + (tile.y - viewport.y) × s
screenW = tile.w × s
screenH = tile.h × s
```

Normal operation uses `s = 1`. Panning changes only `viewport.x` or `viewport.y`. `fit all` derives a temporary scale without changing tile rectangles. `reset viewport` restores `(x, y, scale) = (0, 0, 1)`.

A monitor migration updates viewport screen dimensions and the work-area origin. Existing world rectangles and viewport world coordinates survive; only newly inserted default sizes use the new monitor dimensions. Fractional monitor scaling is already represented by Hyprland's logical `ctx.area`.

Hyprland's `target:place` receives translated logical boxes. `misc:size_limits_tiled` must remain false: when enabled, Hyprland clamps target positions into the work area and defeats offscreen canvas coordinates.

## Geometry invariants

For every present tile:

1. `x`, `y`, `w`, and `h` are finite.
2. `w >= min_width` and `h >= min_height`.
3. `w > 0` and `h > 0`.
4. The positive-area intersection of any pair is empty.
5. Unresized default rectangles use the viewport height; explicit vertical resize may make a rectangle shorter or taller.
6. Abutting edges are allowed; resized rectangles are not required to fill the monitor.

The canvas is the bounding rectangle of live tiles. Its width and height can exceed the viewport in either axis. Panning does not alter these invariants.

## Insertion

New windows receive:

```text
width  = max(min_width, viewport.width  × tile_width_ratio)
height = max(min_height, viewport.height × tile_height_ratio)
```

The default ratios describe a rectangle, not a split. The default height ratio is `1.00`, so each new unresized horizontal band spans the viewport height. Ratios are evaluated only when that target is first inserted.

`auto` inserts to the right of the focused tile without a viewport-relative horizontal limit. Each new default window extends the canvas to the right; explicit `left`, `right`, `up`, and `down` modes insert at the corresponding focused edge.

Insertion and growth use directional collision propagation. A colliding rectangle is translated away, then becomes a blocker for later rectangles. Existing widths and heights are never reduced as a side effect of insertion or collision handling.

## Focus, movement, and viewport

Directional focus scores derived rectangle geometry. Horizontal focus and movement only consider candidates in the same visual lane, so reaching a row edge is a no-op instead of jumping to another row; vertical focus retains diagonal fallback. Vertical movement transfers the focused rectangle to the adjacent row, appends it after that row's existing rectangles, and compacts the source row; when no destination row exists, it creates one at the canvas' leading edge (the minimum world `x`). The focused target keeps focus and is minimally revealed at its new position. Movement cannot change a window's width or height.

`pan` translates the viewport only. It never changes focus or tile geometry. This is the free movement path shown by the reference design.

## Resize

Horizontal resize has two forms:

- `resize left/right` cycles the focused width through `width_presets` relative to the current monitor width;
- `resize left/right [signed amount]` changes the focused width by an explicit pixel amount.

Every horizontal resize reflows the affected band without changing any rectangle's dimensions other than the focused one. Width cycling is row-local: it keeps that band's own left edge and reflows its members left-to-right without consulting any other band. Explicit signed horizontal amounts retain their named-edge behavior. Vertical resize changes only the focused height by a signed pixel amount. Positive amounts grow toward the named edge; negative amounts shrink from that edge. Growth pushes collisions in that direction. All resize operations clamp the focused rectangle to configured minimum dimensions.

## Provider flow

```text
recalculate(ctx)
  ├─ descriptors = stable target keys + active flags
  ├─ engine:sync(workspace, descriptors, ctx.area)
  └─ target:place(engine:screen_box(state, tile, ctx.area))

layout_msg(ctx, message)
  ├─ sync the current context
  ├─ run one engine command
  ├─ dispatch explicit focus when a focus command selected a target
  └─ Hyprland calls recalculate with translated boxes
```

The provider never places a target absent from the current context. Floating and fullscreen behavior remains compositor-owned.

## Lifecycle and special states

- Workspace switches preserve state keyed by workspace ID.
- Workspace removal prunes state whose IDs are no longer live.
- Close callbacks delete rectangles; a row's last rectangle removes that row, shifts later rows upward, and focuses a window in the next row (or the preceding row at the bottom). Otherwise, focus stays with an adjacent same-row survivor. Temporary absence from a tiling context alone does not delete a rectangle.
- Groups use a process-local group identity exposed by Lua.
- Special workspaces and XWayland targets use the same placement path.
- Fullscreen may override the visible target box while the stored world rectangle remains intact.

## Animation and complexity

The viewport is a state translation, not a compositor render transform. A pan or reveal changes the goal boxes of present targets; Hyprland's normal move/resize animation machinery animates them. A viewport update therefore places every present target.

For `n` present targets, directional focus is `O(n)`. Collision propagation and lane reflow are `O(n²)` worst case and run only for insertion, movement, or resizing. Placement after sync is `O(n)`. The test suite includes non-overlap checks and repeated navigation.

## API limitations

The Lua adapter does not expose a reliable mouse tiled-resize delta or a layout-owned drag-to-reorder callback. Keyboard layout messages are the supported resize and movement interface. A native `Layout::ITiledAlgorithm` would be required only if those compositor-level interactions become mandatory.
