-- Copy hypr/grid to ~/.config/hypr/grid, then load this after
-- Omarchy/default Hyprland configuration and before any conflicting binds.
local grid = require("grid").setup({
    -- Relative width presets cycled by Super+Alt+Left/Right. Displayed width
    -- is each cell's weight relative to row siblings, clamped to the screen.
    width_presets = { 0.34, 0.50, 0.67, 1.00 },
    default_width = 0.50,
    pan_step = 300,
    resize_step = 60,
    viewport_margin = 48,
    insertion = "auto",
    auto_reveal = true,
})

-- Hyprland 0.56 workspace-specific layout rules.
hl.workspace_rule({ workspace = "1", layout = grid.layout })
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

    -- Spatial focus on grid workspaces; normal Hyprland focus elsewhere.
    hl.bind(
        "SUPER + " .. key,
        grid.command(
            "focus " .. direction,
            hl.dsp.focus({ direction = direction })
        )
    )

    -- Viewport-only movement. Hold to repeat.
    hl.bind(
        "SUPER + CTRL + " .. key,
        grid.command("pan " .. direction),
        { repeating = true }
    )

    -- Horizontal moves reorder within the focused row (wrapping at its edges);
    -- vertical moves push/pull the whole window into the row below/above,
    -- creating that band when missing. The fallback keeps this binding useful
    -- on dwindle/scrolling/monocle.
    hl.bind(
        "SUPER + SHIFT + " .. key,
        grid.command(
            "move " .. direction,
            hl.dsp.window.move({ direction = direction })
        )
    )

    -- Up/down transfer height between neighbor rows, clamped at min_height;
    -- left/right cycle width through width_presets without exceeding the screen.
    hl.bind(
        "SUPER + ALT + " .. key,
        grid.command("resize " .. direction),
        { repeating = true }
    )
end

-- Viewport utilities. Change these keys freely.
hl.bind("SUPER + CTRL + C", grid.command("center focused"))
hl.bind("SUPER + CTRL + F", grid.command("fit all"))
hl.bind("SUPER + CTRL + R", grid.command("reset viewport"))

-- Per-workspace insertion policy for subsequently opened tiled windows.
hl.bind("SUPER + CTRL + A", grid.command("insert auto"))
hl.bind("SUPER + CTRL + LEFT", grid.command("insert left"))
hl.bind("SUPER + CTRL + RIGHT", grid.command("insert right"))
hl.bind("SUPER + CTRL + UP", grid.command("insert up"))
hl.bind("SUPER + CTRL + DOWN", grid.command("insert down"))
