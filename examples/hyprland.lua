-- Copy hypr/canvas2d to ~/.config/hypr/canvas2d, then load this after
-- Omarchy/default Hyprland configuration and before any conflicting binds.
local canvas = require("canvas2d").setup({
    tile_width_ratio = 0.50,
    tile_height_ratio = 0.55,
    wrap_width_ratio = 2.10,
    pan_step = 300,
    resize_step = 60,
    viewport_margin = 48,
    insertion = "auto",
    auto_reveal = true,
})

-- Hyprland 0.56 workspace-specific layout rules.
hl.workspace_rule({ workspace = "1", layout = canvas.layout })
hl.workspace_rule({ workspace = "2", layout = "scrolling" })
hl.workspace_rule({ workspace = "3", layout = "dwindle" })
hl.workspace_rule({ workspace = "4", layout = "monocle" })

local vim_directions = {
    H = "left",
    J = "down",
    K = "up",
    L = "right",
}

for key, direction in pairs(vim_directions) do
    -- Remove these four hl.unbind calls if the keys are unbound already. In
    -- Omarchy, inspect current assignments with:
    --   omarchy menu keybindings --print
    hl.unbind("SUPER + " .. key)
    hl.unbind("SUPER + CTRL + " .. key)
    hl.unbind("SUPER + SHIFT + " .. key)
    hl.unbind("SUPER + ALT + " .. key)

    -- Spatial focus on canvas workspaces; normal Hyprland focus elsewhere.
    hl.bind(
        "SUPER + " .. key,
        canvas.command(
            "focus " .. direction,
            hl.dsp.focus({ direction = direction })
        )
    )

    -- Viewport-only movement. Hold to repeat.
    hl.bind(
        "SUPER + CTRL + " .. key,
        canvas.command("pan " .. direction),
        { repeating = true }
    )

    -- Swap the focused tile's world rectangle with its spatial neighbor.
    -- The fallback keeps this binding useful on dwindle/scrolling/monocle.
    hl.bind(
        "SUPER + SHIFT + " .. key,
        canvas.command(
            "move " .. direction,
            hl.dsp.window.move({ direction = direction })
        )
    )

    -- Move the named edge and resize directly adjacent tiles with it.
    hl.bind(
        "SUPER + ALT + " .. key,
        canvas.command("resize " .. direction),
        { repeating = true }
    )
end

-- Viewport utilities. Change these keys freely.
hl.bind("SUPER + CTRL + C", canvas.command("center focused"))
hl.bind("SUPER + CTRL + F", canvas.command("fit all"))
hl.bind("SUPER + CTRL + R", canvas.command("reset viewport"))

-- Per-workspace insertion policy for subsequently opened tiled windows.
hl.bind("SUPER + CTRL + A", canvas.command("insert auto"))
hl.bind("SUPER + CTRL + LEFT", canvas.command("insert left"))
hl.bind("SUPER + CTRL + RIGHT", canvas.command("insert right"))
hl.bind("SUPER + CTRL + UP", canvas.command("insert up"))
hl.bind("SUPER + CTRL + DOWN", canvas.command("insert down"))
