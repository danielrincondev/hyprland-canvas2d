-- Optional native scene zoom. Install with `make install-native-overview` first.
local M = {}

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

    -- Keep ordinary workspace changes as smooth as window movement.
    hl.curve("gridWorkspace", { type = "bezier", points = { { 0.23, 1 }, { 0.32, 1 } } })
    hl.animation({ leaf = "workspaces", enabled = true, speed = 3.79, bezier = "gridWorkspace", style = "slide" })

    local overview = hl.plugin.scrolloverview
    local grid = require("grid").setup()
    local menu = hl.dsp.exec_cmd(options.menu_command or "omarchy menu toggle")
    local key = options.key or "SUPER + TAB"
    -- Unbind before defining the submap: hl.unbind also removes matching
    -- shortcuts inside submaps.
    hl.unbind(key)
    -- A keyboard-focused launcher owns its input until it closes. The native
    -- focus listener switches here and restores overview capture afterwards.
    hl.define_submap("scrolloverview-layer", function()
        hl.bind("SUPER + SPACE", menu)
    end)
    hl.define_submap("scrolloverview", function()
        for key, direction in pairs({
            LEFT = "left", H = "left", RIGHT = "right", L = "right",
            UP = "up", K = "up", DOWN = "down", J = "down",
        }) do
            -- Exact modifier matches keep move-window chords from also
            -- firing the select-window binding.
            hl.bind(key, overview.navigate(direction), { repeating = true })
            hl.bind("SUPER + " .. key, overview.navigate(direction), { repeating = true })
            hl.bind("SUPER + SHIFT + " .. key,
                grid.command("move " .. direction, hl.dsp.window.swap({ direction = direction })),
                { repeating = true })
        end
        for number = 1, 10 do
            hl.bind("SUPER + " .. (number % 10), hl.dsp.focus({ workspace = tostring(number) }))
        end
        hl.bind("SUPER + SPACE", menu)
        -- `select` means select under the pointer in this plugin. Closing
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
