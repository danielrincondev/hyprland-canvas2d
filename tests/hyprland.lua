local source_root = assert(os.getenv("GRID_SOURCE"), "GRID_SOURCE must point to the project root")
package.path = source_root .. "/hypr/?.lua;" .. source_root .. "/hypr/?/init.lua;" .. package.path

local grid = require("grid").setup({
    pan_step = 240,
    resize_step = 40,
    viewport_margin = 32,
    scroll_mode = "rows",
})
-- Nested smoke tests invoke layout messages through `hyprctl eval`.
grid_test = grid

hl.monitor({
    output = "",
    mode = "1280x720@60",
    position = "0x0",
    scale = 1,
})

-- Used only when the nested multi-monitor smoke test creates this output.
hl.monitor({
    output = "HEADLESS-1",
    mode = "800x600@60",
    position = "1280x0",
    scale = 1,
})

hl.config({
    debug = {
        enable_stdout_logs = true,
    },
    general = {
        layout = grid.layout,
    },
    misc = {
        size_limits_tiled = false,
        disable_hyprland_logo = true,
        disable_splash_rendering = true,
        disable_xdg_env_checks = true,
        disable_hyprland_guiutils_check = true,
        disable_watchdog_warning = true,
    },
})

hl.workspace_rule({ workspace = "1", layout = grid.layout })
hl.workspace_rule({ workspace = "2", layout = "scrolling" })
hl.workspace_rule({ workspace = "3", layout = "dwindle" })
hl.workspace_rule({ workspace = "4", layout = "monocle" })
hl.workspace_rule({ workspace = "special:grid", layout = grid.layout })

hl.bind("SUPER + H", grid.command("focus left", hl.dsp.focus({ direction = "left" })))
hl.bind("SUPER + J", grid.command("focus down", hl.dsp.focus({ direction = "down" })))
hl.bind("SUPER + K", grid.command("focus up", hl.dsp.focus({ direction = "up" })))
hl.bind("SUPER + L", grid.command("focus right", hl.dsp.focus({ direction = "right" })))
hl.bind("SUPER + CTRL + H", grid.command("pan left"), { repeating = true })
hl.bind("SUPER + SHIFT + L", grid.command("move right"))
hl.bind("SUPER + ALT + J", grid.command("resize down"), { repeating = true })
hl.bind("SUPER + C", grid.command("center focused"))
hl.bind("SUPER + F", grid.command("fit all"))
hl.bind("SUPER + R", grid.command("reset viewport"))
hl.bind("SUPER + CTRL + SHIFT + S", grid.command("scroll toggle"))
hl.bind("SUPER + CTRL + SHIFT + P", grid.command("share toggle"))
local native_plugin = os.getenv("GRID_NATIVE_OVERVIEW")
if native_plugin then
    require("grid.native_overview").setup({ path = native_plugin })
end
