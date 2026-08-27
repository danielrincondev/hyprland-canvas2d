# Architecture

## Boundary

`hyprland-canvas2d` is a Hyprland 0.56 Lua tiled-layout provider. It owns tiled world geometry and viewport state. Hyprland continues to own:

- window and group targets;
- monitor/work-area discovery, including reserved layer-shell areas;
- gaps, borders, rounding, decorations, pseudotiling, and size configuration;
- floating, fullscreen, XWayland, focus, rendering, and animation;
- workspace creation, monitor assignment, and per-workspace layout selection.

The adapter uses only public/current Lua facilities. It does not hook compositor internals.

## Modules

```text
hypr/canvas2d/
├── init.lua       Hyprland provider, event subscriptions, dispatcher adapter
├── engine.lua     workspace state, insertion, commands, lifecycle, resize
└── geometry.lua   rectangle predicates, bounds, neighbors, reveal heuristic
```

`geometry.lua` and `engine.lua` have no Hyprland dependency. Tests run them under a normal Lua interpreter. `init.lua` is covered with a fake `hl` surface matching the 0.56 APIs used by the provider.

## State model

One engine contains a map keyed by Hyprland workspace ID:

```lua
workspaces[id] = {
    viewport = {
        x = 0,          -- world coordinate at viewport left
        y = 0,          -- world coordinate at viewport top
        width = 1920,   -- current screen/work-area logical width
        height = 1040,  -- current screen/work-area logical height
        scale = 1,
    },
    tiles = {
        [targetKey] = {
            x = 0,
            y = 0,
            w = 960,
            h = 572,
            present = true,
        },
    },
    order = { targetKey, ... },
    focus_key = targetKey,
    insertion = "auto",
}
```

`tiles` is a flat map of independent rectangles. `order` exists only for deterministic insertion/fallback selection; it does not encode rows or columns.

Window targets use `window.stable_id`. Group targets use the Lua group's stable process-local identity. A temporarily absent target is marked `present = false`, retaining its world box for a float→tile round trip while being ignored by geometry and rendering. `window.close` deletes non-group target state. Moving a window to another workspace deletes its old-workspace state before deterministic destination insertion.

## Coordinate spaces

World geometry is monitor-independent and uses Hyprland logical units. The current `ctx.area` provides the global work-area origin and logical screen size.

For viewport scale $s$:

```text
screenX = area.x + (worldX - viewport.x) × s
screenY = area.y + (worldY - viewport.y) × s
screenW = worldW × s
screenH = worldH × s
```

Normal operation uses `s = 1`. `fit all` derives a temporary scale without modifying world rectangles. `reset viewport` restores `(x, y, s) = (0, 0, 1)`.

A monitor migration changes `area.x`, `area.y`, viewport screen width, and viewport screen height. It does not rewrite tile rectangles or viewport world position. Fractional monitor scaling is already represented by Hyprland's logical `ctx.area`, so the engine does not apply physical-pixel scaling.

Negative world positions and viewport positions are valid. No origin clamp exists.

## Geometry invariants

For every present tile:

1. `x`, `y`, `w`, and `h` are finite.
2. `w ≥ min_width` and `h ≥ min_height` in world units.
3. The positive-area intersection of any pair is empty.
4. Abutting edges are allowed and expected.

The viewport may intersect no tiles. The canvas has no finite bounds; bounds are computed only for insertion wrapping and `fit all`.

Hyprland's `target:place` receives translated logical boxes. It then applies standard gaps, reserved window areas, pseudotiling, decorations, and client configuration. `misc:size_limits_tiled` must remain false: Hyprland's current implementation clamps target positions into the work area when that global option is true.

## Spatial navigation

Given focused rectangle $F$, direction $d$, and candidate $C$:

1. Compute centers $f$ and $c$.
2. Reject $C$ unless its center lies in the requested directional half-plane. For right: $c_x > f_x + \epsilon$; the other directions are symmetric.
3. Compute overlap on the perpendicular axis.
4. Assign a lexicographic score:

```text
[
  lanePenalty,
  primaryMetric,
  perpendicularCenterDistance,
  EuclideanCenterDistance,
  stableTargetKey (tie break)
]
```

`lanePenalty` is `0` for positive perpendicular overlap and `1` otherwise. This means any candidate in the same visual lane wins over a diagonal candidate, matching the requested behavior.

For an overlapping candidate, `primaryMetric` is the non-negative gap between facing edges. For a diagonal candidate:

```text
primaryMetric = primaryEdgeGap + diagonal_weight × perpendicularEdgeGap
```

The default `diagonal_weight` is `2`. The remaining score fields produce stable results when candidates share an edge or have equivalent gaps.

Focusing the winner updates `focus_key`, computes a minimal reveal translation, and invokes `hl.dsp.focus({ window = target.window })`. The event subscription suppresses its own nested reveal during this explicit focus dispatch.

## Minimal reveal

The visible world rectangle is:

```text
{
  x = viewport.x,
  y = viewport.y,
  w = viewport.width / viewport.scale,
  h = viewport.height / viewport.scale,
}
```

`viewport_margin` is configured in screen logical pixels and divided by scale for world comparison.

For each axis independently:

- If the focused tile plus two margins fits, move only the violated edge to the margin.
- If the tile fits but the margins do not, move only enough to expose the tile.
- If the tile is larger than the viewport, center it on that axis.
- If it is already comfortable, do not move that axis.

Click/default focus is observed through `hl.on("window.active", ...)`; an internal `reveal` layout message executes the same rule.

## Insertion

Insertion is deterministic and workspace-local.

### Automatic

1. First tile: place at `(0, 0)` using configured viewport-relative default size.
2. Otherwise propose a rectangle immediately right of the focused/last tile.
3. Compute the geometric horizontal band intersecting the anchor.
4. If the projected span remains within `wrap_width_ratio × current viewport width`, accept it.
5. Otherwise place at `x = canvasBounds.left`, `y = canvasBounds.bottom`.
6. Push every intersecting rectangle along the insertion direction, in coordinate order, until the new rectangle and propagated chain are clear.

This creates a useful initial two-dimensional arrangement but does not create row objects. Resized bands and vertical boundaries remain independent.

### Explicit

`insert left/right/up/down` persists as the workspace's insertion mode. The proposal abuts the named edge of the focus rectangle. Collision propagation moves existing rectangles away from that edge. Left and up naturally create negative coordinates.

## Movement

`move`/`swap` finds the same spatial neighbor used by focus, then exchanges the two complete `{x,y,w,h}` boxes. Window identity remains fixed while layout position and size move. Because the pre-operation boxes do not overlap, exchanging them preserves the non-overlap invariant.

## Resize

For the named focused edge:

1. Find the nearest set of candidates with positive perpendicular overlap.
2. Consume any empty edge gap first.
3. For positive resize beyond that gap, move the shared boundary. The focused tile grows; every neighbor on that split boundary moves/shrinks by the same delta.
4. Clamp the delta against the smallest remaining neighbor capacity.
5. For negative resize, shrink the focused tile to its minimum and expand every touching neighbor into the released strip.
6. If there is no candidate in that direction, resizing expands into the unbounded empty canvas.

This supports non-aligned split neighbors, such as one tall tile adjacent to two independently sized stacked tiles.

## Lifecycle and special states

- **Workspace switch:** engine state remains keyed by workspace ID; only the visible workspace is recalculated.
- **Workspace destruction:** `workspace.removed` scans live workspace IDs and prunes removed state.
- **Window close:** close callback removes the stable window key; the provider also marks absent targets non-present.
- **Window move:** `window.move_to_workspace` removes source geometry while preserving any already-created destination record.
- **Monitor move/resolution/scale:** the next `ctx.area` updates viewport screen dimensions and global placement offset.
- **Floating/pinned:** not supplied to the tiled algorithm. A temporarily absent stable target keeps a parked rectangle; pinned windows therefore remain outside the canvas.
- **Fullscreen/maximized:** the default Hyprland fullscreen handler overrides visible target geometry while fullscreen. The stored world rectangle is not mutated.
- **Special workspace:** works when assigned `layout = "lua:canvas2d"`; Hyprland applies its special-workspace visual scale after target placement.
- **XWayland:** no separate path. Hyprland's window target handles protocol coordinates after layout placement.
- **Transient dialog:** floating dialogs are excluded. Forced-tiled dialogs are ordinary targets because transient relationships are not exposed in the layout context.
- **Groups:** one target/rectangle. Lua exposes the current group window and group object but no stable layout-target identifier; group topology changes can cause deterministic reinsertion.

## Animation

The viewport is a state translation, not a compositor render transform. A pan changes the goal boxes of all present tiled targets. Hyprland's normal window move/resize animation machinery animates those goals. This reuses configured animation curves but costs one placement per visible or offscreen live target.

## Complexity

Let $n$ be present targets.

- Recalculate/viewport translation: $O(n)$.
- Directional focus: $O(n)$.
- Edge-neighbor resize query: $O(n)$.
- Collision propagation on insertion: $O(n^2)$ worst-case with a chain of overlapping candidates.
- Test-only full overlap validation: $O(n^2)$.

The benchmark includes focus, pan, and translation of every tile. At 100 targets it measured about `217 µs` per update under standalone Lua 5.5.1 on the development Ryzen 5 5500U. Bulk creation of 100 previously unseen targets took `18.1 ms`, below Hyprland 0.56's `50 ms` Lua layout callback watchdog on that machine.

## Why Lua, and the native escalation point

Hyprland 0.56's Lua layout provider exposes everything required for keyboard-first 2D tiling: target boxes, work area, active/window/workspace metadata, layout messages, focus dispatch, lifecycle events, and per-workspace layout rules.

The missing surface is native interactive manipulation. In Hyprland 0.56.2, `CLuaTiledAlgorithm::resizeTarget` discards `Δ` and `corner`; `moveTargetInDirection` swaps adapter target order without consulting Lua world geometry. Continuous gesture deltas and layout-owned fullscreen handlers are likewise unavailable.

If those become required, the clean escalation is a native `Layout::ITiledAlgorithm` registered with `HyprlandAPI::addTiledAlgo`. The pure rectangle engine and tests define the behavior to port. Function hooks or render-coordinate interception are not required for a scale-1 tiled viewport and should remain a last resort.
