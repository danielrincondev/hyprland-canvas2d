# Native overview integration

`install.sh` builds yayuuu/hyprland-scroll-overview at commit
`5e96ae20ec73c320248bcf3ff68b330bc1ed4152` with the small patch beside it.
The installed binary has a content-derived filename so rebuilding never
truncates a library mapped into Hyprland. The stable symlink is used on the
next compositor start.

The patch handles these cases:

- Closing after the associated output has disappeared must remove the
  overview immediately instead of dereferencing an expired monitor.
- Vertical spatial navigation must allow candidates without horizontal
  overlap. Independent row offsets can otherwise make an adjacent row
  unreachable. Overlapping candidates still take precedence.
- Entering/restoring the overview submap must use `Config::Actions::setSubmap`.
  The legacy `submap` dispatcher is absent on the current Lua compositor.
  Without this fix, the overview falls back to partial keyboard handling and
  application input remains active.
- Arrow navigation stops at the current workspace's edge. Wheel and finger
  scrolling select windows within that workspace; they do not traverse the
  overview's workspace strip. Finger motion accumulates before selecting to
  avoid stepping on every tiny input event.
- Keyboard-focused top-layer launchers temporarily use `scrolloverview-layer`,
  allowing menu input through. When keyboard focus returns, the native focus
  listener restores the overview submap. Closing overview restores the original
  submap from either mode.

The Lua integration declares `hl.plugin.load(path)` on every config pass.
Hyprland reconciles that declaration after parsing and runs another pass
with the native Lua API registered. Conditionally omitting the declaration
when the plugin is loaded causes an unload/reload loop.

The integration defines the plugin's supported input submap. Enter
closes with the keyboard selection; the upstream `select` action instead
selects the workspace under the mouse pointer, so it belongs only in the
mouse binding. Escape also commits the current selection; it does not
promise restoration of the original focus.

The submap consumes unmatched keys with an `ignore_mods` catch-all binding.
Navigation has explicit plain and Super bindings; Super+Shift moves windows.
Exact modifier matching prevents one chord from both selecting and moving.
Super+number changes workspaces explicitly and keeps overview active.

Workspace previews run horizontally. Ordinary workspace transitions use a
horizontal slide with the window-movement ease-out curve; the plugin restores
this setting after its close animation finishes.

## Validation

Use an isolated Hyprland instance, never the active desktop for lifecycle
tests. `tests/hyprland.lua` accepts `GRID_NATIVE_OVERVIEW=/absolute/plugin.so`
to load this integration. Set `GRID_SOURCE` to the repository directory.
Always address its explicit instance signature in `hyprctl -i ...`.

Exercise these cases after updating the upstream revision or patch:

1. Create six terminals and move three into a second grid row. Compare
   client positions and sizes before opening and while zoomed out.
2. Independently pan the rows until their ends do not overlap. Navigate up
   from the lower row's rightmost window, close, and check that the selected
   upper-row window is focused. Compare final client geometry with ordinary
   focusing of that window: Hyprland's edge gaps may change when a row moves
   on/off the monitor, even without overview.
3. Repeat open/navigation/close, close a selected client while zoomed out,
   and open an empty workspace.
4. Create a second virtual output, open overview on the first, remove the
   first output, and close. The compositor must remain responsive.
5. Reload the Lua config twice and check `hyprctl configerrors`, plugin list,
   and overview submap bindings.
6. Run `python3 native/input-smoke.py --instance <nested-instance>` in an empty
   isolated compositor with this integration loaded. It uses Foot terminals
   with raw input loggers and `wtype` to verify the actual shortcut, navigation,
   suppression of typing and Enter, and restoration of application input.
   It enables symbol-based bind resolution in that test instance for wtype's
   synthetic keymap. IPC navigation alone cannot validate keyboard capture.
7. With two populated workspaces, send repeated wheel and finger axis events
   in both directions. The selected workspace must not change. Verify pointer
   motion still changes cursor position, and that the workspace slide animation
   is enabled again after overview has finished closing.
8. Open a keyboard-exclusive layer-shell menu using Super+Space. Verify typing
   reaches the menu, arrows do not select overview windows, and Escape closes
   only the menu and restores overview capture. Super+Shift+Arrow must move the
   selected window without also changing selection; Super+number must keep the
   overview submap active on the destination workspace.

A nested Wayland output may stop drawing when its host window is offscreen.
For screenshot tests, create a headless output in the isolated compositor,
place it at `0x0`, then remove the nested Wayland output before testing.
Do not infer visual failures from an output that is not receiving frames.
