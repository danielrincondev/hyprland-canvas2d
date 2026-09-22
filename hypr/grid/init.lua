local Engine = require("grid.engine")
local Shared = require("grid.shared")
local Session = require("grid.session")

local Grid = {}
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

function Grid.setup(options)
    if active_api then
        return active_api
    end
    if not hl or not hl.layout or not hl.layout.register then
        error("grid requires Hyprland 0.55 or newer with hl.layout.register", 2)
    end

    local engine = Engine.new(options)
    local shared = Shared.new(engine)
    local session_path = hl.version and Session.path() or nil
    local saved_session = Session.read(session_path)
    if saved_session then
        local original = shared:checkpoint()
        local restored = pcall(function()
            assert(type(saved_session.next_id) == "number" and type(saved_session.rows) == "table")
            shared:rollback(saved_session)
            for _, state in pairs(engine.workspaces) do
                engine:_materialize(state)
                assert(engine:validate(state))
            end
            shared:refresh()
        end)
        if not restored then shared:rollback(original) end
    end
    local layout_name = "lua:" .. engine.config.layout_name
    local subscriptions = {}
    local suppress_auto_reveal = false
    local references_by_workspace = {}
    local moving_shared = false
    local shared_timer
    local save_timer

    local function save_session()
        for _, state in pairs(engine.workspaces) do engine:_save_row_view(state) end
        local ok, reason = pcall(Session.write, session_path, shared:checkpoint())
        if not ok then print("grid: could not save reload state: " .. tostring(reason)) end
    end

    local function schedule_save()
        if session_path and not save_timer and not moving_shared then
            save_timer = hl.timer(function()
                save_timer = nil
                save_session()
            end, { timeout = 10, type = "oneshot" })
        end
    end

    local function notify(text)
        if hl.notification then hl.notification.create({ text = text, timeout = 2200 }) end
    end

    local function clear_empty_focus(state)
        if not (state and state.empty_row and state.empty_row.selected) then return end
        local native = hl.plugin and hl.plugin.scrolloverview
        if native and native.empty_row then
            native.empty_row()
        else
            engine:focus(state, "up")
            notify("Rebuild the native overview plugin to enter an empty row")
        end
    end

    local function sync_context(ctx)
        local descriptors, references = context_descriptors(ctx)
        local workspace_id = context_workspace_id(ctx)
        -- Window moves trigger intermediate layout callbacks. The complete
        -- row model is already transferred; don't reinsert departing targets.
        local state = moving_shared and engine:workspace(workspace_id, ctx.area)
            or engine:sync(workspace_id, descriptors, ctx.area)
        references_by_workspace[workspace_id] = references
        if not moving_shared then shared:refresh() end
        schedule_save()
        return state, references
    end

    local function dispatch_focus(window)
        suppress_auto_reveal = true
        local ok, dispatch_error = pcall(function()
            hl.dispatch(hl.dsp.focus({ window = window }))
        end)
        suppress_auto_reveal = false
        return ok, dispatch_error
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
            if moving_shared then return true end
            local state, references = sync_context(ctx)
            local result, command_error
            local action, scope = message:match("^share%s+(%S+)%s*(.-)%s*$")
            if message == "shared-refresh" then
                result = { changed = true }
            elseif action or message == "share" then
                local ws = hl.get_active_special_workspace and hl.get_active_special_workspace()
                if ws then return "grid: shared rows require a normal workspace" end
                result, command_error = shared:toggle(state, action, scope ~= "" and scope or nil)
                if result and result.changed then
                    notify(result.shared and "Row shared across grid workspaces" or "Row is local to this workspace")
                elseif command_error then notify(command_error) end
            else
                result, command_error = engine:command(state, message)
                shared:refresh()
            end
            if not result then
                return command_error
            end

            if result.focus_key then
                local target = references[result.focus_key]
                local window = target and target.window or nil
                if window then
                    local ok, dispatch_error = dispatch_focus(window)
                    if not ok then
                        return "grid: failed to focus spatial neighbor: " .. tostring(dispatch_error)
                    end
                end
            end
            if result.clear_focus then clear_empty_focus(state) end

            if session_path then save_session() end

            return true
        end,
    }

    hl.layout.register(engine.config.layout_name, provider)

    local api = {
        engine = engine,
        shared = shared,
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

    function api.overview_navigate(direction, fallback)
        return function()
            local ws = hl.get_active_workspace()
            local state = ws and engine.workspaces[tostring(ws.id)]
            if api.is_active() and state and state.empty_row then
                local tile = state.tiles[state.focus_key]
                local last = state.rows[#state.rows]
                if state.empty_row.selected or (direction == "down" and tile and last and tile.row_id == last.id) then
                    return hl.dispatch(hl.dsp.layout("focus " .. direction))
                end
            end
            return fallback()
        end
    end

    local function move_shared_rows()
        shared_timer = nil
        local workspace = hl.get_active_workspace()
        if moving_shared or not workspace or workspace.special or not workspace_uses_layout(workspace, layout_name)
            or (hl.get_active_special_workspace and hl.get_active_special_workspace()) then return end
        local records = shared:pending(workspace.id)
        if #records == 0 then clear_empty_focus(engine.workspaces[tostring(workspace.id)]); return end
        local windows = {}
        for _, window in ipairs(hl.get_windows()) do
            if window.mapped and not window.floating and not window.group then
                windows[target_key({ window = window })] = window
            end
        end
        local saved = shared:checkpoint()
        local destination = engine:workspace(workspace.id)
        local originals = {}
        moving_shared, suppress_auto_reveal = true, true
        local ok, reason = pcall(function()
            for _, record in ipairs(records) do
                local source_id = record.workspace_id
                local source = engine.workspaces[source_id]
                -- Validate the complete row before changing any ownership.
                for _, row in ipairs(source.rows) do
                    if row.id == record.row_id then
                        for _, cell in ipairs(row.cells) do
                            assert(windows[cell.key], "shared window is no longer tiled; retry after the layout updates")
                            originals[#originals + 1] = { key = cell.key, window = windows[cell.key], source = source_id }
                        end
                    end
                end
                local entries = shared:transfer(record, destination)
                for _, entry in ipairs(entries) do
                    local window = windows[entry.key]
                    hl.dispatch(hl.dsp.window.move({ window = window, workspace = tostring(workspace.id), follow = false }))
                    assert(window.workspace and tostring(window.workspace.id) == destination.id, "window move failed")
                end
            end
        end)
        if not ok then
            for i = #originals, 1, -1 do
                local item = originals[i]
                if item.window.workspace and tostring(item.window.workspace.id) ~= item.source then
                    pcall(function()
                        hl.dispatch(hl.dsp.window.move({ window = item.window, workspace = item.source, follow = false }))
                    end)
                end
            end
            shared:rollback(saved)
            -- If a client vanished or refused rollback, remove its old model
            -- entry. The next context inserts it wherever it actually lives.
            for _, item in ipairs(originals) do
                local actual = item.window.workspace and item.window.workspace.id
                if not actual or tostring(actual) ~= item.source then engine:forget_window(item.key, actual) end
            end
            shared:refresh()
            notify("Could not move shared row: " .. tostring(reason))
        end
        moving_shared, suppress_auto_reveal = false, false
        local state = engine.workspaces[tostring(workspace.id)]
        local focus = state and windows[state.focus_key]
        if focus then dispatch_focus(focus) end
        clear_empty_focus(state)
        -- Also recalculate an empty destination after the transaction ends.
        hl.dispatch(hl.dsp.layout("shared-refresh"))
    end

    local function schedule_shared_rows()
        if moving_shared or shared_timer or not next(shared.rows) then return end
        -- Coalesce workspace/monitor events and resolve the final active
        -- workspace after Hyprland has finished switching and restoring focus.
        shared_timer = hl.timer(move_shared_rows, { timeout = 1, type = "oneshot" })
    end

    if hl.on then
        if engine.config.auto_reveal then
            subscriptions[#subscriptions + 1] = hl.on("window.active", function(window, reason)
                if suppress_auto_reveal or not window or window.floating or not api.is_active(window) then
                    return
                end
                local state = engine.workspaces[tostring(window.workspace.id)]
                if state and state.empty_row and state.empty_row.selected then
                    -- Focus restoration and mouse-follow during a slide must
                    -- not send input back into an offscreen shared window.
                    if reason == 1 or reason == 7 or reason == 11 then
                        hl.timer(function() clear_empty_focus(state) end, { timeout = 1, type = "oneshot" })
                        return
                    end
                    state.empty_row.selected = false
                end
                hl.dispatch(hl.dsp.layout("reveal"))
            end)
        end

        subscriptions[#subscriptions + 1] = hl.on("window.close", function(window)
            if not window or window.group then
                return
            end

            local key
            if window.stable_id ~= nil then
                key = "window:" .. tostring(window.stable_id)
            elseif window.address then
                key = "address:" .. tostring(window.address)
            end
            if not key then
                return
            end

            local workspace_id = window.workspace
                and window.workspace.id ~= nil
                and tostring(window.workspace.id)
                or nil
            local next_key = engine:forget_window(key)
            shared:refresh()
            schedule_save()
            if not next_key then
                return
            end

            local workspace_references = workspace_id and references_by_workspace[workspace_id] or nil
            local target = workspace_references and workspace_references[next_key] or nil
            if not target then
                for _, references in pairs(references_by_workspace) do
                    target = references[next_key]
                    if target then
                        break
                    end
                end
            end
            if target and target.window then
                dispatch_focus(target.window)
            end
        end)

        subscriptions[#subscriptions + 1] = hl.on("window.move_to_workspace", function(window, workspace)
            if moving_shared or not window or not workspace then
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
                shared:refresh()
                schedule_save()
            end
        end)

        subscriptions[#subscriptions + 1] = hl.on("workspace.removed", function()
            if moving_shared then return end
            local live_ids = {}
            if hl.get_workspaces then
                for _, workspace in ipairs(hl.get_workspaces()) do
                    if workspace.id ~= nil then
                        live_ids[#live_ids + 1] = workspace.id
                    end
                end
            end
            engine:prune_workspaces(live_ids)
            shared:refresh()
            schedule_save()
        end)
        subscriptions[#subscriptions + 1] = hl.on("workspace.active", schedule_shared_rows)
        subscriptions[#subscriptions + 1] = hl.on("monitor.focused", schedule_shared_rows)
        subscriptions[#subscriptions + 1] = hl.on("workspace.special_active", schedule_shared_rows)
        subscriptions[#subscriptions + 1] = hl.on("config.reloaded", schedule_shared_rows)
        subscriptions[#subscriptions + 1] = hl.on("hyprland.shutdown", function()
            if session_path then os.remove(session_path) end
        end)
    end

    active_api = api
    return api
end

return Grid
