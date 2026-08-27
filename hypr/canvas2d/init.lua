local Engine = require("canvas2d.engine")

local Canvas2D = {}
local active_api

local function target_key(target)
    local window = target.window
    if window then
        local group = window.group
        if group then
            return "group:" .. tostring(group)
        end
        if window.stable_id ~= nil then
            return "window:" .. tostring(window.stable_id)
        end
        if window.address then
            return "address:" .. tostring(window.address)
        end
    end
    return "target:" .. tostring(target.index)
end

local function context_workspace_id(ctx)
    for _, target in ipairs(ctx.targets) do
        local window = target.window
        if window and window.workspace and window.workspace.id ~= nil then
            return tostring(window.workspace.id)
        end
    end

    local workspace = hl.get_active_special_workspace and hl.get_active_special_workspace() or nil
    if not workspace and hl.get_active_workspace then
        workspace = hl.get_active_workspace()
    end
    return workspace and tostring(workspace.id) or "unknown"
end

local function context_descriptors(ctx)
    local descriptors = {}
    local references = {}

    for _, target in ipairs(ctx.targets) do
        local key = target_key(target)
        local window = target.window
        descriptors[#descriptors + 1] = {
            key = key,
            active = window and window.active == true or false,
        }
        references[key] = target
    end

    return descriptors, references
end

local function workspace_uses_layout(workspace, layout_name)
    return workspace and workspace.tiled_layout == layout_name
end

function Canvas2D.setup(options)
    if active_api then
        return active_api
    end
    if not hl or not hl.layout or not hl.layout.register then
        error("canvas2d requires Hyprland 0.55 or newer with hl.layout.register", 2)
    end

    local engine = Engine.new(options)
    local layout_name = "lua:" .. engine.config.layout_name
    local subscriptions = {}
    local suppress_auto_reveal = false

    local function sync_context(ctx)
        local descriptors, references = context_descriptors(ctx)
        local workspace_id = context_workspace_id(ctx)
        local state = engine:sync(workspace_id, descriptors, ctx.area)
        return state, references
    end

    local provider = {
        recalculate = function(ctx)
            local state, references = sync_context(ctx)
            for key, target in pairs(references) do
                local tile = state.tiles[key]
                if tile and tile.present ~= false then
                    target:place(engine:screen_box(state, tile, ctx.area))
                end
            end
        end,

        layout_msg = function(ctx, message)
            local state, references = sync_context(ctx)
            local result, command_error = engine:command(state, message)
            if not result then
                return command_error
            end

            if result.focus_key then
                local target = references[result.focus_key]
                local window = target and target.window or nil
                if window then
                    suppress_auto_reveal = true
                    local ok, dispatch_error = pcall(function()
                        hl.dispatch(hl.dsp.focus({ window = window }))
                    end)
                    suppress_auto_reveal = false
                    if not ok then
                        return "canvas2d: failed to focus spatial neighbor: " .. tostring(dispatch_error)
                    end
                end
            end

            return true
        end,
    }

    hl.layout.register(engine.config.layout_name, provider)

    local api = {
        engine = engine,
        layout = layout_name,
        provider = provider,
        subscriptions = subscriptions,
    }

    function api.is_active(window)
        local workspace = window and window.workspace or nil
        if not workspace and hl.get_active_special_workspace then
            workspace = hl.get_active_special_workspace()
        end
        if not workspace and hl.get_active_workspace then
            workspace = hl.get_active_workspace()
        end
        return workspace_uses_layout(workspace, layout_name)
    end

    function api.command(message, fallback)
        return function()
            if api.is_active() then
                return hl.dispatch(hl.dsp.layout(message))
            end
            if fallback then
                return hl.dispatch(fallback)
            end
        end
    end

    if hl.on then
        if engine.config.auto_reveal then
            subscriptions[#subscriptions + 1] = hl.on("window.active", function(window)
                if suppress_auto_reveal or not window or window.floating or not api.is_active(window) then
                    return
                end
                hl.dispatch(hl.dsp.layout("reveal"))
            end)
        end

        subscriptions[#subscriptions + 1] = hl.on("window.close", function(window)
            if not window or window.group then
                return
            end
            if window.stable_id ~= nil then
                engine:forget_window("window:" .. tostring(window.stable_id))
            elseif window.address then
                engine:forget_window("address:" .. tostring(window.address))
            end
        end)

        subscriptions[#subscriptions + 1] = hl.on("window.move_to_workspace", function(window, workspace)
            if not window or not workspace then
                return
            end
            local key
            if window.group then
                key = "group:" .. tostring(window.group)
            elseif window.stable_id ~= nil then
                key = "window:" .. tostring(window.stable_id)
            elseif window.address then
                key = "address:" .. tostring(window.address)
            end
            if key then
                engine:forget_window(key, workspace.id)
            end
        end)

        subscriptions[#subscriptions + 1] = hl.on("workspace.removed", function()
            local live_ids = {}
            if hl.get_workspaces then
                for _, workspace in ipairs(hl.get_workspaces()) do
                    if workspace.id ~= nil then
                        live_ids[#live_ids + 1] = workspace.id
                    end
                end
            end
            engine:prune_workspaces(live_ids)
        end)
    end

    active_api = api
    return api
end

return Canvas2D
