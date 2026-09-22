# Architecture

## Boundary

The core of `hyprland-grid` is a Hyprland 0.56 Lua tiled-layout provider. It owns fixed-size tiled world rectangles and viewport state. The optional native ScrollOverview plugin renders a zoomed compositor scene without changing client geometry. Hyprland continues to own:

- window and group targets;
- monitor/work-area discovery, including reserved layer-shell areas;
- gaps, borders, rounding, decorations, pseudotiling, and size configuration;
- floating, fullscreen, XWayland, focus, rendering, and animation;
- workspace creation, monitor assignment, and per-workspace layout selection.

The adapter uses public Lua facilities and does not hook compositor internals. The native overview hooks compositor rendering and input, and must be rebuilt for the installed Hyprland ABI.

## Modules

```text
hypr/grid/
├── init.lua       Hyprland provider, event subscriptions, dispatcher adapter
├── engine.lua     workspace state, insertion, movement, resize, lifecycle
├── geometry.lua   rectangle predicates, directional neighbors, viewport math
├── shared.lua     shared-row ownership, workspace scopes and atomic transfers
├── session.lua    data checkpoints that preserve layout across config reloads
└── native_overview.lua  optional native plugin configuration and input submaps
native/
├── install.sh           pinned upstream build and versioned library installation
├── scrolloverview.patch  compositor compatibility and navigation fixes
└── input-smoke.py       isolated-compositor keyboard regression checks
```

`geometry.lua` and `engine.lua` have no Hyprland dependency. Tests run under a normal Lua interpreter. `init.lua` is covered by a fake `hl` surface matching the APIs used by the provider. The native plugin remains optional and is installed by `make install-native-overview`.

## State model

One engine contains a map keyed by Hyprland workspace ID. `scroll_mode` defaults to `rows` and is independently switchable per workspace:

```lua
workspaces[id] = {
    scroll_mode = "rows", -- or "shared"
    row_order = { 1 },
    row_views = { [1] = { x = 0, focus_key = "window:42" } },
    active_row_id = 1,
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
            row_id = 1,
            present = true,
        },
    },
    order = { "window:42" },
    focus_key = "window:42",
    overview = {
        active = false,
        saved_viewport = nil,
        saved_focus_key = nil,
    },
    insertion = "auto",
}
```

`tiles` owns world rectangles and explicit row membership. `row_order` and `row_views` retain stable row identity, horizontal scroll, and focus memory; `rows` is the derived list of live members and bounds. In row mode, `viewport.x` mirrors the active row's horizontal offset, and placement uses each other row's saved offset. Horizontal insertion joins its anchor's row; vertical insertion creates a row; vertical movement transfers membership. Resizing never changes membership. Independent rows have disjoint vertical bounds: if growth would overlap rows, later rows move down without resizing their windows. `present = false` parks a temporarily absent target, retaining its row memory until a lifecycle callback deletes or moves it. `order` supplies deterministic fallback focus and insertion anchors.

`sync` records which tiles were present, marks all stored tiles absent, and marks context targets present. Returning targets resolve collisions to the right in stable insertion order before genuinely new targets are inserted. This keeps parked rectangles reusable when live windows have occupied their old space. Sync then resolves active focus and reveals an active newcomer. `window.close` removes a closed target. `window.move_to_workspace` removes the old-workspace record while allowing deterministic insertion in the destination workspace.

## Coordinate spaces

World coordinates are workspace-local and anchored at `(0, 0)` for the first tile. They are not clipped to the monitor. A viewport may show empty space or only part of the canvas.

For viewport scale `s`:

```text
screenX = area.x + (tile.x - horizontalOffset) × s
screenY = area.y + (tile.y - viewport.y) × s
screenW = tile.w × s
screenH = tile.h × s
```

Normal operation uses `s = 1`. `horizontalOffset` is the row's offset in row mode and `viewport.x` in shared mode. Horizontal panning affects only the focused row in row mode; vertical panning always affects the workspace. `scroll toggle` switches modes at scale `1`, retaining row offsets while shared mode is in use. The shared view starts at the current horizontal offset; returning to rows restores their saved offsets.

`fit all` temporarily uses a shared transform and sets `fitted`, without overwriting row offsets or changing rectangles. Normal focus, reveal, center, or pan resumes row mode at scale `1`. Overview saves the transform, active row, fitted state, and focus, keeps all live rectangles fitted through focus and lifecycle changes, and restores the saved state on exit. Unlike one-shot fitting, overview can scale below `min_fit_scale` to keep the full live canvas visible. Mode changes are ignored during overview. `reset viewport` resets the active horizontal offset, workspace vertical offset, and scale; inactive row offsets survive.

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

In row mode, horizontal focus and movement follow explicit row membership ordered by `x`. Vertical focus restores the adjacent row's remembered live target and exact horizontal offset. On its first visit, the target closest to the source's horizontal screen position is selected. Shared mode scores derived rectangle geometry and retains diagonal fallback vertically. Vertical movement transfers the focused rectangle and membership to the adjacent row, appends it after that row's existing rectangles, and compacts the source row; when no destination row exists, it creates one at the canvas' leading edge (the minimum world `x`). The focused target keeps focus and is minimally revealed at its new position. Movement cannot change a window's width or height.

`pan` translates the viewport only. It never changes focus or tile geometry. This is the free movement path shown by the reference design.

Overview reuses directional focus scoring but suppresses reveal, panning, centering, and viewport reset while open. Activation restores the saved transform and minimally reveals the selected target. Cancellation restores the saved transform and restores the original target when it is still live. Synchronization and close/move lifecycle handling refit the remaining present rectangles.

## Resize

Horizontal resize has two forms:

- `resize left/right` cycles the focused width through `width_presets` relative to the current monitor width;
- `resize left/right [signed amount]` changes the focused width by an explicit pixel amount.

Every horizontal resize reflows the affected band without changing any rectangle's dimensions other than the focused one. Width cycling keeps that band's own left edge and reflows its members left-to-right. Collision propagation then clears any overlaps with staggered tiles outside the focused band; fully separated rows stay independent. Explicit signed horizontal amounts retain their named-edge behavior. Vertical resize changes only the focused height by a signed pixel amount. Positive amounts grow toward the named edge; negative amounts shrink from that edge. Growth pushes collisions in that direction. All resize operations clamp the focused rectangle to configured minimum dimensions.

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

## Shared row ownership

`shared.lua` manages stable shared-row IDs and workspace scopes. Shared rows form a stable prefix
above local rows in every workspace, ordered by their shared-row IDs. Each shared row still belongs to exactly one engine workspace. A
transfer detaches and compacts the source row, inserts its unchanged rectangles
at the top of the destination, and carries horizontal scroll and row focus memory.
Existing destination focus and its vertical screen position are preserved.

The adapter coalesces workspace/monitor events with a one-shot timer. It resolves
the final active normal grid workspace and moves each real window silently.
Intermediate compositor layout callbacks use the prepared model without syncing
partially moved target lists. On failure it attempts to return all moved windows
and restores the checkpoint, reconciling any client that could not return.

`session.lua` stores a length-prefixed data checkpoint in the private runtime
directory. The filename includes the actual process PID and start time, so
configuration verification and other compositor instances cannot consume the
live desktop's state. State is written after layout commands and coalesced
lifecycle changes, restored across config reloads, and removed on shutdown.
It contains only layout geometry and membership, not executable Lua or app
content. This is session state, not a persistent rule for newly launched apps.

## Native overview flow

`native_overview.lua` loads the plugin on every Hyprland configuration pass, then installs settings and submaps once the plugin exposes its Lua namespace. Skipping the load call on later passes makes Hyprland unload the plugin.

ScrollOverview transforms the compositor scene and arranges workspaces horizontally. Directional selection and wheel/finger navigation stop at the current workspace's boundary. Explicit workspace-number bindings switch workspaces while overview stays open. Grid movement bindings delegate to the existing Lua layout so row membership and scrolling retain one owner.

The overview submap consumes typing and handles selection/exit keys. When keyboard focus moves to a top-layer launcher, the native focus hook switches to a companion submap that allows launcher input. Closing the launcher restores overview capture; closing overview restores the previous submap. Workspace animation settings are temporarily overridden by the plugin and restored after the transition.

This mode is independent of the engine's geometry-based `overview` state. The installer keeps each native library under a content-derived filename to avoid truncating a binary mapped by a running compositor.

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

The Lua adapter does not expose a reliable mouse tiled-resize delta or a layout-owned drag-to-reorder callback. Keyboard layout messages remain the supported way to resize and reorder actual layout targets. The native overview supplies compositor-scene transforms and selection input, but grid-specific drag-to-reorder is not integrated.
