return function(T)
    local registered_name
    local provider
    local handlers = {}
    local workspaces = {}
    local active_workspace
    local current_context
    local dispatched = {}

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
        state.tiles["window:5202"].x = 0
        state.tiles["window:5202"].y = state.tiles["window:5201"].h
        grid.engine:_materialize(state)
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
end
