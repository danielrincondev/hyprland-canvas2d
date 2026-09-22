-- Learn how to configure Hyprland: https://wiki.hypr.land/Configuring/Start/

-- Omarchy's bootstrap keeps path setup out of this user config.
dofile((os.getenv("OMARCHY_PATH") or "/usr/share/omarchy") .. "/default/hypr/bootstrap.lua")

-- Disable all Omarchy default bindings. Add your own in hypr/bindings.lua.
-- omarchy_default_bindings = false
--
-- Or disable only bindings for Omarchy's preinstalled apps/web apps while
-- keeping core window-manager bindings:
-- omarchy_preinstalled_bindings = false

-- Super is reserved for a few launchers (bound in hypr/bindings.lua); movement
-- lives on Alt.  Drop every other Super binding, including Omarchy's defaults
-- and ones added by future Omarchy updates.  Installed before defaults load.
local super_allowed = {
  ["SUPER+CODE:10"] = true, -- 1: terminal
  ["SUPER+CODE:11"] = true, -- 2: browser
  ["SUPER+GRAVE"] = true,   -- `: Omarchy menu
}
local unfiltered_bind = hl.bind
hl.bind = function(keys, ...)
  local normalized = tostring(keys):upper():gsub("%s+", "")
  if normalized:find("SUPER", 1, true) and not super_allowed[normalized] then
    return nil
  end
  return unfiltered_bind(keys, ...)
end

-- Load Omarchy defaults.
require("default.hypr.omarchy")

-- Put your personal overrides in these files. They're loaded after Omarchy's
-- defaults so package updates can improve the defaults without rewriting your
-- ~/.config/hypr files.
require("hypr.monitors")
require("hypr.input")
require("hypr.looknfeel")
require("hypr.autostart")

-- Toggle config flags dynamically.
require("default.hypr.toggles")

-- Load bindings after persisted workspace-layout toggles so explicit
-- workspace rules take precedence.
require("hypr.bindings")

-- Add any other personal Hyprland configuration below.

-- Make every application window fully opaque.
o.window(".*", { tag = "-default-opacity", opacity = "1.0 1.0" })
-- o.window("qemu", { workspace = "5" })
