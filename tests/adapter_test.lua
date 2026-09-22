return function(T)
    local registered_name
    local provider
    local handlers = {}
    local workspaces = {}
    local active_workspace
    local current_context
    local dispatched = {}
    local all_targets, timers = {}, {}
    local fail_move_on, move_count

    local function workspace(id, layout)
        local value = {
            id = id,
            tiled_layout = layout or "lua:grid",
        }
        workspaces[tostring(id)] = value
        return value
    end

    local function target(id, is_active, owner)
        local window = {
            stable_id = id,
            address = "0x" .. tostring(id),
            active = is_active == true,
            floating = false,
            mapped = true,
            workspace = owner,
            group = nil,
        }
        local value = {
            index = id,
            window = window,
            box = { x = 0, y = 0, w = 1, h = 1 },
        }
        function value:place(box)
            self.placed = box
            self.box = box
        end
        all_targets[id] = value
        return value
    end

    local function context(owner, targets, area)
        active_workspace = owner
        current_context = {
            targets = targets,
            area = area or { x = 0, y = 0, w = 1000, h = 800 },
        }
        return current_context
    end

    _G.hl = {
        layout = {
            register = function(name, value)
                registered_name = name
                provider = value
            end,
        },
        dsp = {
            window = { move = function(options) return { kind = "move", options = options } end },
            focus = function(options)
                return { kind = "focus", window = options.window }
            end,
            layout = function(message)
                return { kind = "layout", message = message }
            end,
        },
        dispatch = function(action)
            dispatched[#dispatched + 1] = action
            if action.kind == "focus" then
                if current_context then
                    for _, item in ipairs(current_context.targets) do
                        item.window.active = item.window == action.window
                    end
                end
                return true
            elseif action.kind == "move" then
                move_count = (move_count or 0) + 1
                if move_count == fail_move_on then error("simulated move failure") end
                local options = action.options
                local destination = workspaces[options.workspace] or workspace(tonumber(options.workspace))
                options.window.workspace = destination
                handlers["window.move_to_workspace"][1](options.window, destination)
                current_context.targets = {}
                for _, item in pairs(all_targets) do
                    if item.window.workspace == active_workspace then
                        current_context.targets[#current_context.targets + 1] = item
                    end
                end
                provider.recalculate(current_context)
                return true
            elseif action.kind == "layout" then
                local result = provider.layout_msg(current_context, action.message)
                provider.recalculate(current_context)
                return result
            end
            return action
        end,
        on = function(name, handler)
            handlers[name] = handlers[name] or {}
            handlers[name][#handlers[name] + 1] = handler
            return { name = name, handler = handler }
        end,
        timer = function(callback)
            timers[#timers + 1] = callback
            return {}
        end,
        get_windows = function()
            local result = {}
            for _, item in pairs(all_targets) do result[#result + 1] = item.window end
            return result
        end,
        get_active_workspace = function()
            return active_workspace
        end,
        get_active_special_workspace = function()
            return nil
        end,
        get_workspaces = function()
            local result = {}
            for _, value in pairs(workspaces) do
                result[#result + 1] = value
            end
            return result
        end,
    }

    package.loaded["grid"] = nil
    package.loaded["grid.init"] = nil
    local grid = require("grid").setup({
        min_width = 50,
        min_height = 40,
        new_window_position = "reveal",
    })

    T.case("adapter registers the current Lua custom layout API", function()
        T.equal(registered_name, "grid")
        T.equal(grid.layout, "lua:grid")
        T.truthy(provider.recalculate)
        T.truthy(provider.layout_msg)
    end)

    T.case("adapter translates world rectangles through a workspace viewport", function()
        local owner = workspace(101)
        local first = target(1001, true, owner)
        local ctx = context(owner, { first }, { x = 1920, y = 30, w = 1000, h = 800 })
        provider.recalculate(ctx)
        local state = grid.engine.workspaces["101"]
        T.near(state.tiles["window:1001"].x, 0)
        T.near(state.tiles["window:1001"].y, 0)
        T.near(first.placed.x, 1920)
        T.near(first.placed.y, 30)
        handlers["window.active"][1](first.window, 0)
        T.near(state.viewport.x, 0)
        T.near(first.placed.x, 1920)

        provider.layout_msg(ctx, "pan right 300")
        provider.recalculate(ctx)
        T.near(first.placed.x, 1620)
        T.near(state.viewport.x, 300)
    end)

    T.case("adapter keeps a new window centered through its focus reveal", function()
        grid.engine.config.new_window_position = "center"
        local owner = workspace(104)
        local first = target(4001, true, owner)
        local ctx = context(owner, { first }, { x = 0, y = 0, w = 1000, h = 800 })
        provider.recalculate(ctx)
        local state = grid.engine.workspaces["104"]
        handlers["window.active"][1](first.window, 0)
        provider.recalculate(ctx)
        grid.engine.config.new_window_position = "reveal"
        T.near(state.viewport.x, -250)
        T.near(first.placed.x, 250)
    end)

    T.case("adapter spatial focus dispatches the selected window object", function()
        local owner = workspace(102)
        local left = target(2001, true, owner)
        local right = target(2002, false, owner)
        local ctx = context(owner, { left, right })
        provider.recalculate(ctx)
        local state = grid.engine.workspaces["102"]
        state.focus_key = "window:2001"

        local result = provider.layout_msg(ctx, "focus right")
        T.equal(result, true)
        T.equal(dispatched[#dispatched].kind, "focus")
        T.equal(dispatched[#dispatched].window, right.window)
        T.truthy(right.window.active)
    end)

    T.case("adapter keeps row scrolling through focus dispatch and mode toggles", function()
        local owner = workspace(111)
        local a = target(6101, true, owner)
        local b = target(6102, false, owner)
        local c = target(6103, false, owner)
        local ctx = context(owner, { a, b, c })
        provider.recalculate(ctx)
        local state = grid.engine.workspaces["111"]
        state.focus_key = "window:6103"
        grid.engine:move(state, "down")
        provider.layout_msg(ctx, "focus right")
        provider.layout_msg(ctx, "pan right 125")
        provider.layout_msg(ctx, "focus down")
        provider.layout_msg(ctx, "pan right 77")
        provider.recalculate(ctx)
        T.near(a.placed.x, -125)
        T.near(c.placed.x, -77)
        provider.layout_msg(ctx, "focus up")
        T.equal(dispatched[#dispatched].window, b.window)
        T.near(state.viewport.x, 125)
        provider.layout_msg(ctx, "scroll toggle")
        provider.recalculate(ctx)
        T.near(a.placed.x, -125)
        T.near(c.placed.x, -125)
        provider.layout_msg(ctx, "scroll toggle")
        provider.recalculate(ctx)
        T.near(c.placed.x, -77)
    end)

    T.case("click focus event keeps a row's left edge flush", function()
        local owner = workspace(103)
        local near = target(3001, false, owner)
        local far = target(3002, true, owner)
        local ctx = context(owner, { near, far }, { x = 0, y = 0, w = 500, h = 400 })
        provider.recalculate(ctx)
        local state = grid.engine.workspaces["103"]
        state.viewport.x = 250 -- pan right so the first window is cut off
        -- mirror the compositor having already applied click-focus to `near`
        far.window.active = false
        near.window.active = true

        handlers["window.active"][1](near.window, 0)
        T.near(state.viewport.x, 0)
    end)

    T.case("adapter overview focus and cancel dispatch real focus changes", function()
        local owner = workspace(111)
        local left = target(3101, true, owner)
        local middle = target(3102, false, owner)
        local right = target(3103, false, owner)
        local ctx = context(owner, { left, middle, right }, { x = 0, y = 0, w = 500, h = 400 })
        provider.recalculate(ctx)
        local state = grid.engine.workspaces["111"]
        state.viewport.x = 125
        state.viewport.y = 40

        grid.command("overview enter")()
        T.truthy(state.overview.active)
        local fitted_x = state.viewport.x
        local fitted_scale = state.viewport.scale

        grid.command("focus right")()
        T.equal(dispatched[#dispatched].kind, "focus")
        T.equal(dispatched[#dispatched].window, middle.window)
        T.truthy(middle.window.active)
        T.near(state.viewport.x, fitted_x)
        T.near(state.viewport.scale, fitted_scale)

        grid.command("overview cancel")()
        T.equal(dispatched[#dispatched].kind, "focus")
        T.equal(dispatched[#dispatched].window, left.window)
        T.truthy(left.window.active)
        T.falsy(state.overview.active)
        T.near(state.viewport.x, 125)
        T.near(state.viewport.y, 40)
        T.near(state.viewport.scale, 1)
    end)

    T.case("mixed-layout command falls back outside grid workspaces", function()
        local fallback = { kind = "fallback" }
        local command = grid.command("focus left", fallback)
        local grid_workspace = workspace(104, "lua:grid")
        local normal_workspace = workspace(105, "dwindle")
        local first = target(4001, true, grid_workspace)
        context(grid_workspace, { first })
        provider.recalculate(current_context)
        command()
        T.equal(dispatched[#dispatched].kind, "layout")

        context(normal_workspace, {})
        command()
        T.equal(dispatched[#dispatched], fallback)
    end)

    T.case("window lifecycle callbacks preserve float state and purge closed windows", function()
        local owner = workspace(106)
        local first = target(5001, true, owner)
        local ctx = context(owner, { first })
        provider.recalculate(ctx)
        T.truthy(grid.engine.workspaces["106"].tiles["window:5001"])
        handlers["window.close"][1](first.window)
        T.equal(grid.engine.workspaces["106"].tiles["window:5001"], nil)
    end)
    T.case("closing focused windows focuses the same-row neighbor", function()
        local owner = workspace(109)
        local left = target(5101, false, owner)
        local middle = target(5102, true, owner)
        local right = target(5103, false, owner)
        local ctx = context(owner, { left, middle, right })
        provider.recalculate(ctx)
        local state = grid.engine.workspaces["109"]

        handlers["window.close"][1](middle.window)

        T.equal(state.focus_key, "window:5103")
        T.equal(state.tiles["window:5102"], nil)
        T.equal(dispatched[#dispatched].kind, "focus")
        T.equal(dispatched[#dispatched].window, right.window)
        T.truthy(right.window.active)
        T.near(state.tiles["window:5103"].x, 500)
        T.truthy(grid.engine:validate(state))
    end)
    T.case("closing the only window in a row deletes the row and focuses another row", function()
        local owner = workspace(110)
        local top = target(5201, true, owner)
        local bottom = target(5202, false, owner)
        local ctx = context(owner, { top, bottom })
        provider.recalculate(ctx)
        local state = grid.engine.workspaces["110"]
        state.focus_key = "window:5202"
        grid.engine:move(state, "down")
        grid.engine:focus(state, "up")
        local dispatch_count = #dispatched

        handlers["window.close"][1](top.window)

        T.equal(#dispatched, dispatch_count + 1)
        T.equal(dispatched[#dispatched].kind, "focus")
        T.equal(dispatched[#dispatched].window, bottom.window)
        T.equal(state.focus_key, "window:5202")
        T.equal(state.tiles["window:5201"], nil)
        T.near(state.tiles["window:5202"].y, 0)
        T.near(state.viewport.y, 0)
        T.truthy(bottom.window.active)

        ctx.targets = { bottom }
        provider.recalculate(ctx)
        T.near(state.tiles["window:5202"].y, 0)
        T.truthy(grid.engine:validate(state))
    end)

    T.case("workspace removal prunes only destroyed workspace state", function()
        local removed = workspace(107)
        local survivor = workspace(108)
        local first = target(6001, true, removed)
        provider.recalculate(context(removed, { first }))
        local second = target(6002, true, survivor)
        provider.recalculate(context(survivor, { second }))
        workspaces["107"] = nil
        handlers["workspace.removed"][1](removed)
        T.equal(grid.engine.workspaces["107"], nil)
        T.truthy(grid.engine.workspaces["108"])
    end)

    T.case("special-workspace XWayland targets use the same grid path", function()
        local owner = workspace(-99)
        owner.special = true
        local xwayland = target(7001, true, owner)
        xwayland.window.xwayland = true
        provider.recalculate(context(owner, { xwayland }, { x = -1280, y = 25, w = 1280, h = 695 }))
        T.truthy(grid.engine.workspaces["-99"].tiles["window:7001"])
        T.truthy(xwayland.placed)
        T.near(xwayland.placed.x, -1280)
        T.near(xwayland.placed.y, 25)
        T.near(xwayland.placed.w, 640)
        T.near(xwayland.placed.h, 695)
    end)

    T.case("shared adapter coalesces switches and tolerates partial layout callbacks", function()
        local source, destination, skipped = workspace(201), workspace(202), workspace(203, "dwindle")
        local a, b, private = target(8101, false, source), target(8102, true, source), target(8103, true, destination)
        provider.recalculate(context(destination, {private}))
        local ctx = context(source, {a, b})
        provider.recalculate(ctx)
        provider.layout_msg(ctx, "share on")
        context(skipped, {})
        handlers["workspace.active"][1](skipped)
        context(destination, {private})
        handlers["workspace.active"][1](destination)
        T.equal(#timers, 1)
        local callback = table.remove(timers, 1)
        callback()
        T.equal(a.window.workspace, destination)
        T.equal(b.window.workspace, destination)
        T.falsy(grid.engine.workspaces["201"].tiles["window:8101"])
        T.equal(grid.engine.workspaces["202"].focus_key, "window:8103")
        T.truthy(grid.engine:validate(grid.engine.workspaces["202"]))
        T.equal(#grid.shared:pending("201"), 1)
        provider.layout_msg(context(destination, {a, b, private}), "share off") -- local focus, no effect
        a.window.active, b.window.active, private.window.active = true, false, false
        provider.layout_msg(context(destination, {a, b, private}), "share off")
        T.equal(#grid.shared:pending("201"), 0)
    end)

    T.case("shared adapter rolls back a partially completed window move", function()
        local source, destination = workspace(204), workspace(205)
        local a, b = target(8201, true, source), target(8202, false, source)
        local ctx = context(source, {a, b})
        provider.recalculate(ctx)
        provider.layout_msg(ctx, "share on")
        move_count, fail_move_on = 0, 2
        context(destination, {})
        handlers["workspace.active"][1](destination)
        table.remove(timers, 1)()
        fail_move_on = nil
        T.equal(a.window.workspace, source)
        T.equal(b.window.workspace, source)
        T.truthy(grid.engine.workspaces["204"].tiles["window:8201"])
        T.truthy(grid.engine.workspaces["204"].tiles["window:8202"])
        T.falsy(grid.engine.workspaces["205"] and grid.engine.workspaces["205"].tiles["window:8201"])
        T.equal(#grid.shared:pending("205"), 1)
    end)
end
