local source_root = assert(os.getenv("CANVAS2D_SOURCE"), "CANVAS2D_SOURCE must point to the project root")
package.path = source_root .. "/hypr/?.lua;" .. source_root .. "/hypr/?/init.lua;" .. package.path

local canvas = require("canvas2d").setup({
    pan_step = 240,
    resize_step = 40,
    viewport_margin = 32,
})
-- Nested smoke tests invoke layout messages through `hyprctl eval`.
canvas2d_test = canvas

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
        layout = canvas.layout,
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

hl.workspace_rule({ workspace = "1", layout = canvas.layout })
hl.workspace_rule({ workspace = "2", layout = "scrolling" })
hl.workspace_rule({ workspace = "3", layout = "dwindle" })
hl.workspace_rule({ workspace = "4", layout = "monocle" })
hl.workspace_rule({ workspace = "special:canvas", layout = canvas.layout })

hl.bind("SUPER + H", canvas.command("focus left", hl.dsp.focus({ direction = "left" })))
hl.bind("SUPER + J", canvas.command("focus down", hl.dsp.focus({ direction = "down" })))
hl.bind("SUPER + K", canvas.command("focus up", hl.dsp.focus({ direction = "up" })))
hl.bind("SUPER + L", canvas.command("focus right", hl.dsp.focus({ direction = "right" })))
hl.bind("SUPER + CTRL + H", canvas.command("pan left"), { repeating = true })
hl.bind("SUPER + SHIFT + L", canvas.command("move right"))
hl.bind("SUPER + ALT + J", canvas.command("resize down"), { repeating = true })
hl.bind("SUPER + C", canvas.command("center focused"))
hl.bind("SUPER + F", canvas.command("fit all"))
hl.bind("SUPER + R", canvas.command("reset viewport"))
