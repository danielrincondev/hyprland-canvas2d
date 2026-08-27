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
        T.near(first.placed.x, 1968)
        T.near(first.placed.y, 78)

        provider.layout_msg(ctx, "pan right 300")
        provider.recalculate(ctx)
        T.near(first.placed.x, 1668)
        T.near(state.viewport.x, 252)
    end)

    T.case("adapter spatial focus dispatches the selected window object", function()
        local owner = workspace(102)
        local left = target(2001, true, owner)
        local right = target(2002, false, owner)
        local ctx = context(owner, { left, right })
        provider.recalculate(ctx)
        local state = grid.engine.workspaces["102"]
        grid.engine:set_tile("102", "window:2001", { x = 0, y = 0, w = 200, h = 200 })
        grid.engine:set_tile("102", "window:2002", { x = 250, y = 0, w = 200, h = 200 })
        state.focus_key = "window:2001"

        local result = provider.layout_msg(ctx, "focus right")
        T.equal(result, true)
        T.equal(dispatched[#dispatched].kind, "focus")
        T.equal(dispatched[#dispatched].window, right.window)
        T.truthy(right.window.active)
    end)

    T.case("click focus event minimally reveals an offscreen tiled window", function()
        local owner = workspace(103)
        local near = target(3001, false, owner)
        local far = target(3002, true, owner)
        local ctx = context(owner, { near, far }, { x = 0, y = 0, w = 500, h = 400 })
        provider.recalculate(ctx)
        local state = grid.engine.workspaces["103"]
        grid.engine:set_tile("103", "window:3001", { x = 0, y = 0, w = 200, h = 200 })
        grid.engine:set_tile("103", "window:3002", { x = 1200, y = 700, w = 200, h = 200 })
        state.focus_key = "window:3002"
        state.viewport.x = 0
        state.viewport.y = 0

        handlers["window.active"][1](far.window, 0)
        T.truthy(state.viewport.x > 800)
        T.truthy(state.viewport.y > 400)
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
        T.truthy(xwayland.placed.x > -1280)
    end)
end
