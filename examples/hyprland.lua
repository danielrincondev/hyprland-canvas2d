-- Copy hypr/grid to ~/.config/hypr/grid, then load this after
-- Omarchy/default Hyprland configuration and before any conflicting binds.
local grid = require("grid").setup({
    -- New windows keep this fixed world size until explicitly resized.
    tile_width_ratio = 0.50,
    tile_height_ratio = 1.00,
    -- Relative width presets cycled by Super+Alt+Left/Right.
    width_presets = { 0.34, 0.50, 0.67, 1.00 },
    pan_step = 300,
    resize_step = 60,
    viewport_margin = 0,
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

    -- Move the focused window to the neighboring slot without changing
    -- either window's width or height. Vertical moves append to the adjacent
    -- row and compact the old row; an empty edge creates a new row at the
    -- canvas' leading edge. The fallback remains useful on dwindle/scrolling/
    -- monocle.
    hl.bind(
        "SUPER + SHIFT + " .. key,
        grid.command(
            "move " .. direction,
            hl.dsp.window.move({ direction = direction })
        )
    )

-- Width cycles keep each row independent and compact its members left-to-right.
-- Vertical and explicit horizontal resize still change only the focused
-- rectangle's size.
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
