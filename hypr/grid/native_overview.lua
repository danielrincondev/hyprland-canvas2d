-- Optional native scene zoom. Install with `make install-native-overview` first.
local M = {}

-- Returns a bind callback that switches to `workspace` with the plugin's
-- zoom-out transition, or a plain switch when the plugin (or a build with
-- zoomswitch) is not loaded.  Resolved at key press, so it works on the
-- config pass that runs before the plugin registers its Lua API.
function M.switch_workspace(workspace)
    workspace = tostring(workspace)
    return function()
        local overview = hl.plugin and hl.plugin.scrolloverview
        if overview and overview.zoomswitch then
            -- Inside a keybind the plugin dispatches immediately and returns
            -- nothing; elsewhere it returns a bind action to call.
            local action = overview.zoomswitch(workspace)
            if type(action) == "function" then action() end
        else
            hl.dispatch(hl.dsp.focus({ workspace = workspace }))
        end
    end
end

function M.setup(options)
    options = options or {}
    local path = options.path or (assert(os.getenv("HOME")) .. "/.local/lib/hyprland-grid/scrolloverview.so")
    -- This declares the desired plugin on EVERY config pass. Omitting it once
    -- the namespace exists makes Hyprland unload/reload it recursively.
    hl.plugin.load(path)
    -- Loading is deferred until after the first config pass; Hyprland then
    -- evaluates the config again with the plugin's Lua API registered.
    if not hl.plugin.scrolloverview then
        return
    end

    hl.config({ plugin = { scrolloverview = {
        scale = options.scale or 0.30,
        layout = "horizontal",
        workspace_gap = 100,
        wallpaper = 2,
        blur = false,
    } } })
    -- Older plugin builds reject unknown options; configure zoom-switch only
    -- when the loaded build provides it.
    if hl.plugin.scrolloverview.zoomswitch then
        hl.config({ plugin = { scrolloverview = { zoom_switch = {
            scale = options.zoom_switch_scale or 0.85,
            speed = options.zoom_switch_speed or 0,
        } } } })
    end

    -- Keep ordinary workspace changes as smooth as window movement.
    hl.curve("gridWorkspace", { type = "bezier", points = { { 0.23, 1 }, { 0.32, 1 } } })
    hl.animation({ leaf = "workspaces", enabled = true, speed = 3.79, bezier = "gridWorkspace", style = "slide" })

    local overview = hl.plugin.scrolloverview
    local grid = require("grid").setup()
    local menu = hl.dsp.exec_cmd(options.menu_command or "omarchy menu toggle")
    local menu_key = options.menu_key or "SUPER + SPACE"
    local key = options.key or "SUPER + TAB"
    -- Unbind before defining the submap: hl.unbind also removes matching
    -- shortcuts inside submaps.
    hl.unbind(key)
    -- A keyboard-focused launcher owns its input until it closes. The native
    -- focus listener switches here and restores overview capture afterwards.
    hl.define_submap("scrolloverview-layer", function()
        hl.bind(menu_key, menu)
    end)
    hl.define_submap("scrolloverview", function()
        for key, direction in pairs({
            LEFT = "left", H = "left", RIGHT = "right", L = "right",
            UP = "up", K = "up", DOWN = "down", J = "down",
        }) do
            -- Exact modifier matches keep move-window chords from also
            -- firing the select-window binding.
            local navigate = grid.overview_navigate(direction, function() overview.navigate(direction) end)
            hl.bind(key, navigate, { repeating = true })
            hl.bind("SUPER + " .. key, navigate, { repeating = true })
            hl.bind("SUPER + SHIFT + " .. key,
                grid.command("move " .. direction, hl.dsp.window.swap({ direction = direction })),
                { repeating = true })
        end
        for number = 1, 10 do
            hl.bind("SUPER + " .. (number % 10), hl.dsp.focus({ workspace = tostring(number) }))
        end
        -- Optional modifier clusters, e.g. { mod = "ALT", directions =
        -- { up = "W", ... }, workspaces = { "1", ... } }: mod+key navigates,
        -- mod+SHIFT+key moves the window, mod+workspace key pans there.
        for _, cluster in ipairs(options.clusters or {}) do
            for direction, cluster_key in pairs(cluster.directions or {}) do
                local navigate = grid.overview_navigate(direction, function() overview.navigate(direction) end)
                hl.bind(cluster.mod .. " + " .. cluster_key, navigate, { repeating = true })
                hl.bind(cluster.mod .. " + SHIFT + " .. cluster_key,
                    grid.command("move " .. direction, hl.dsp.window.swap({ direction = direction })),
                    { repeating = true })
            end
            for number, workspace_key in ipairs(cluster.workspaces or {}) do
                hl.bind(cluster.mod .. " + " .. workspace_key, hl.dsp.focus({ workspace = tostring(number) }))
            end
        end
        hl.bind(menu_key, menu)
        -- `select` means select under the pointer in this plugin. Closing
        hl.bind("SUPER + CTRL + SHIFT + P", grid.command("share toggle"))
        -- commits the keyboard selection without replacing it with a hover.
        hl.bind("RETURN", overview.overview("close"), { ignore_mods = true })
        hl.bind("ESCAPE", overview.overview("close"), { ignore_mods = true })
        hl.bind(key, overview.overview("close"))
        hl.bind("mouse:272", function()
            overview.overview("select")
            overview.window("select")
            overview.overview("close")
        end, { mouse = true })
        -- Unknown keys belong to the overview too, never the focused client.
        hl.bind("catchall", function() end, { ignore_mods = true })
    end)

    hl.bind(key, overview.overview("toggle"), { description = "Toggle native grid overview" })
end

return M
