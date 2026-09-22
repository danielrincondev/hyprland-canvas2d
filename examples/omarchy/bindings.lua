-- Keep only your personal keybinding overrides here. Add new bindings or
-- unbind defaults before replacing them.

-- See current bindings and descriptions:
--   omarchy menu keybindings --print

-- To disable every Omarchy default binding, set this in
-- ~/.config/hypr/hyprland.lua before require("default.hypr.omarchy"), then add
-- only the bindings you want below:
--   omarchy_default_bindings = false

-- To disable all preinstalled app/webapp bindings, set:
--   omarchy_preinstalled_bindings = false

-- Add a new binding.
-- o.bind("SUPER + SHIFT + R", "SSH", "alacritty -e ssh your-server")

-- Change an existing binding by unbinding it first, then binding the key again.
-- This example changes SUPER+SPACE from the launcher to the Omarchy root menu.
-- hl.unbind("SUPER + SPACE")
-- o.bind("SUPER + SPACE", "Omarchy menu", "omarchy-menu toggle root")

-- Disable a default binding without replacing it.
-- hl.unbind("SUPER + SHIFT + B")

-- Logitech MX Keys examples:
-- o.bind("SUPER + SHIFT + S", nil, "omarchy-capture-screenshot")
-- o.bind("SUPER + H", nil, "voxtype record toggle")
-- o.bind("SUPER + PERIOD", nil, "omarchy-shell shell toggle omarchy.emojis")

-- Workspace-local structural grid layout (rows x cells, niri-style).
local grid = require("grid").setup({
  -- New windows open at the third width preset, centered in the viewport.
  tile_width_ratio = 0.67,
  new_window_position = "center",
  tile_height_ratio = 1.00,
  width_presets = { 0.34, 0.50, 0.67, 1.00 },
  pan_step = 300,
  resize_step = 60,
  viewport_margin = 0,
  scroll_mode = "rows",
  row_gap = 48,
})

hl.workspace_rule({ workspace = "1", layout = grid.layout })
hl.workspace_rule({ workspace = "2", layout = grid.layout })
hl.workspace_rule({ workspace = "3", layout = grid.layout })
hl.workspace_rule({ workspace = "4", layout = grid.layout })
hl.workspace_rule({ workspace = "5", layout = grid.layout })

-- Movement lives on Alt only, mirrored for each hand; Super is for apps and
-- window actions.  Left Alt is ALT; Right Alt is isolated to MOD5 via
-- lv3:ralt_switch in input.lua.  A combination taken here never reaches
-- applications, so rebind it inside the app if one needs it.
--
--   Alt + direction          focus (grid-aware)
--   Alt + SHIFT + direction  move the window
--   Alt + CTRL + direction   resize (height / width presets), hold to repeat
--   Alt + workspace key      switch workspace (zoom transition)
--   Alt + SHIFT + ws key     move the window to that workspace
local alt_clusters = {
  {
    mod = "ALT",
    hand = "Left Alt",
    directions = { up = "W", left = "A", down = "S", right = "D" },
    -- Key names, used where key codes do not match (inside submaps).
    workspace_keys = { "1", "2", "3", "4", "5" },
    last_window = "TAB",
    center = "C",
    close = "X",
    -- Physical keys 1 2 3 4 5, independent of Shift and layout.
    workspaces = { "code:10", "code:11", "code:12", "code:13", "code:14" },
  },
  {
    mod = "MOD5",
    hand = "Right Alt",
    directions = { up = "O", left = "K", down = "L", right = "semicolon" },
    workspace_keys = { "minus", "0", "9", "8", "7" },
    last_window = "backslash",
    center = "M",
    close = "comma",
    -- Physical keys - 0 9 8 7.
    workspaces = { "code:20", "code:19", "code:18", "code:17", "code:16" },
  },
}

-- Workspace switches zoom out slightly, pan, and zoom back in (native plugin);
-- a plain switch is used when the plugin is not loaded.
local native_overview = require("grid.native_overview")

-- Alt + Tab (or Right Alt + \\) arms a mode while Alt stays held:
--   release Alt            jump to the last focused window, any workspace
--   press a workspace key  move the focused window there, following it
-- The move is silent so the zoom transition, not Hyprland, does the switching.
local MOVE_SUBMAP = "move-window"
local move_mode_armed = false

-- Jump to the previously focused window, following it to its workspace.
local function focus_last_window()
  for _, window in ipairs(hl.get_windows()) do
    if window.focus_history_id == 1 and window.mapped and not window.hidden then
      hl.dispatch(hl.dsp.focus({ window = window }))
      return
    end
  end
end

local function arm_move_mode()
  move_mode_armed = true
  hl.dispatch(hl.dsp.submap(MOVE_SUBMAP))
end

local function move_window_to(number)
  return function()
    move_mode_armed = false
    hl.dispatch(hl.dsp.submap("reset"))
    hl.dispatch(hl.dsp.window.move({ workspace = tostring(number), follow = false }))
    native_overview.switch_workspace(number)()
  end
end

local function leave_move_mode()
  -- The release bindings are universal, so ignore ordinary Alt releases and
  -- releases after a workspace move or Escape has already completed the mode.
  if not move_mode_armed then return end
  move_mode_armed = false
  hl.dispatch(hl.dsp.submap("reset"))
  focus_last_window()
end

hl.define_submap(MOVE_SUBMAP, function()
  for _, cluster in ipairs(alt_clusters) do
    for number, key in ipairs(cluster.workspace_keys) do
      -- Works whether or not Alt is still held.
      hl.bind(key, move_window_to(number))
      hl.bind(cluster.mod .. " + " .. key, move_window_to(number))
    end
    -- The arming key itself must not fall through and end the mode.
    hl.bind(cluster.last_window, function() end, { ignore_mods = true })
  end
  -- Releasing either Alt ends the mode; with no workspace key pressed it
  -- means plain Alt+Tab: go to the last focused window. Hyprland 0.56 matches
  -- releases against the submap at KEY PRESS, before Tab arms this submap.
  -- Universal matching is therefore required on the first Alt release.
  for _, modifier in ipairs({ "code:64", "code:108" }) do
    hl.bind(modifier, leave_move_mode, {
      release = true, ignore_mods = true, submap_universal = true,
      non_consuming = true,
    })
  end
  -- No catchall here: the arming key's own event would trip it immediately.
  hl.bind("ESCAPE", function()
    move_mode_armed = false
    hl.dispatch(hl.dsp.submap("reset"))
  end, { ignore_mods = true })
end)

-- Remove Super movement: Omarchy's focus/swap arrows, workspace switching
-- and moving windows between workspaces.
for _, arrow in ipairs({ "LEFT", "RIGHT", "UP", "DOWN" }) do
  hl.unbind("SUPER + " .. arrow)
  hl.unbind("SUPER + SHIFT + " .. arrow)
end
for workspace = 1, 10 do
  local key = "code:" .. tostring(workspace + 9)
  hl.unbind("SUPER + " .. key)
  hl.unbind("SUPER + SHIFT + " .. key)
  hl.unbind("SUPER + SHIFT + ALT + " .. key)
end
hl.unbind("SUPER + SHIFT + TAB")
hl.unbind("SUPER + CTRL + TAB")
hl.unbind("ALT + TAB")

-- Super only opens things; every other Super binding is filtered out in
-- hyprland.lua (add new Super keys to super_allowed there).
o.bind("SUPER + code:10", "Terminal", { omarchy = "terminal" })
o.bind("SUPER + code:11", "Browser", { omarchy = "browser" })
o.bind("SUPER + grave", "Omarchy menu", "omarchy-menu toggle")

for _, cluster in ipairs(alt_clusters) do
  local mod, hand = cluster.mod, " (" .. cluster.hand .. ")"

  for _, direction in ipairs({ "up", "left", "down", "right" }) do
    local key = cluster.directions[direction]
    o.bind(
      mod .. " + " .. key,
      "Grid focus " .. direction .. hand,
      grid.command("focus " .. direction, hl.dsp.focus({ direction = direction }))
    )
    -- Horizontal reorders cells in the row (wrapping at its edges);
    -- vertical moves the whole window into the row below/above.
    o.bind(
      mod .. " + SHIFT + " .. key,
      "Move grid window " .. direction .. hand,
      grid.command("move " .. direction, hl.dsp.window.swap({ direction = direction }))
    )
    -- Up/down transfer row height (clamped); left/right step through the
    -- width presets without ever exceeding the screen.
    o.bind(
      mod .. " + CTRL + " .. key,
      "Resize grid " .. direction .. hand,
      grid.command("resize " .. direction),
      { repeating = true }
    )
  end

  o.bind(mod .. " + " .. cluster.center, "Center grid focus" .. hand,
    grid.command("center focused", hl.dsp.window.center()))
  o.bind(mod .. " + " .. cluster.last_window,
    "Last window, or hold for move-to-workspace" .. hand, arm_move_mode)
  if cluster.close then
    o.bind(mod .. " + " .. cluster.close, "Close window" .. hand, hl.dsp.window.close())
  end

  for number, key in ipairs(cluster.workspaces) do
    o.bind(mod .. " + " .. key, "Switch to workspace " .. number .. hand,
      native_overview.switch_workspace(number))
    o.bind(mod .. " + SHIFT + " .. key, "Move window to workspace " .. number .. hand,
      hl.dsp.window.move({ workspace = tostring(number) }))
  end
end

-- Native desktop zoom on Alt+Space; the Alt clusters navigate inside it.
native_overview.setup({
  scale = 0.30,
  key = "ALT + SPACE",
  menu_key = "SUPER + grave",
  clusters = alt_clusters,
})
