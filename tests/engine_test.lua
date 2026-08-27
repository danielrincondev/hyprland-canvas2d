local Engine = require("canvas2d.engine")
local Geometry = require("canvas2d.geometry")

local AREA = { x = 0, y = 0, w = 1000, h = 800 }

local function new_engine(options)
    options = options or {}
    options.min_width = options.min_width or 50
    options.min_height = options.min_height or 40
    return Engine.new(options)
end

local function descriptors(count, active)
    local result = {}
    for index = 1, count do
        result[index] = { key = tostring(index), active = index == active }
    end
    return result
end

local function rect_snapshot(rect)
    return { x = rect.x, y = rect.y, w = rect.w, h = rect.h }
end

local function assert_rect(T, actual, expected)
    T.near(actual.x, expected.x)
    T.near(actual.y, expected.y)
    T.near(actual.w, expected.w)
    T.near(actual.h, expected.h)
end

return function(T)
    T.case("first tiled window starts at world origin", function()
        local engine = new_engine()
        local state = engine:sync("1", descriptors(1, 1), AREA)
        T.near(state.tiles["1"].x, 0)
        T.near(state.tiles["1"].y, 0)
        T.near(state.tiles["1"].w, 500)
        T.near(state.tiles["1"].h, 440)
        T.equal(state.focus_key, "1")
    end)

    T.case("many-window insertion creates a two-dimensional canvas", function()
        local engine = new_engine()
        local state = engine:sync("1", descriptors(25, 25), AREA)
        local bounds = Geometry.bounds(state.tiles)
        T.truthy(bounds.w > AREA.w)
        T.truthy(bounds.h > state.tiles["1"].h)
        local valid, reason = engine:validate(state)
        T.truthy(valid, reason)
        T.equal(engine:present_count(state), 25)
    end)

    T.case("closing the focused tile selects a surviving tile", function()
        local engine = new_engine()
        local state = engine:sync("1", descriptors(3, 2), AREA)
        engine:forget_window("2")
        state = engine:sync("1", {
            { key = "1", active = false },
            { key = "3", active = true },
        }, AREA)
        T.equal(state.tiles["2"], nil)
        T.equal(state.focus_key, "3")
        T.truthy(engine:validate(state))
    end)

    T.case("closing a non-focused tile preserves focus", function()
        local engine = new_engine()
        local state = engine:sync("1", descriptors(3, 2), AREA)
        engine:forget_window("1")
        state = engine:sync("1", {
            { key = "2", active = true },
            { key = "3", active = false },
        }, AREA)
        T.equal(state.focus_key, "2")
        T.equal(state.tiles["1"], nil)
    end)

    T.case("engine focus navigates in all four spatial directions", function()
        local engine = new_engine()
        local state = engine:workspace("1", AREA)
        engine:set_tile("1", "center", { x = 0, y = 0, w = 100, h = 100 })
        engine:set_tile("1", "left", { x = -120, y = 0, w = 100, h = 100 })
        engine:set_tile("1", "right", { x = 120, y = 0, w = 100, h = 100 })
        engine:set_tile("1", "up", { x = 0, y = -120, w = 100, h = 100 })
        engine:set_tile("1", "down", { x = 0, y = 120, w = 100, h = 100 })

        for direction, expected in pairs({ left = "left", right = "right", up = "up", down = "down" }) do
            state.focus_key = "center"
            T.equal(engine:focus(state, direction), expected)
        end
    end)

    T.case("directional move swaps complete world rectangles", function()
        local directions = {
            left = { x = -120, y = 0 },
            right = { x = 120, y = 0 },
            up = { x = 0, y = -120 },
            down = { x = 0, y = 120 },
        }

        for direction, neighbor_position in pairs(directions) do
            local engine = new_engine()
            local state = engine:workspace(direction, AREA)
            engine:set_tile(direction, "focus", { x = 0, y = 0, w = 100, h = 100 })
            engine:set_tile(direction, "neighbor", {
                x = neighbor_position.x,
                y = neighbor_position.y,
                w = 80,
                h = 90,
            })
            state.focus_key = "focus"
            T.truthy(engine:move(state, direction))
            assert_rect(T, state.tiles.focus, { x = neighbor_position.x, y = neighbor_position.y, w = 80, h = 90 })
            assert_rect(T, state.tiles.neighbor, { x = 0, y = 0, w = 100, h = 100 })
            T.truthy(engine:validate(state))
        end
    end)

    T.case("directional resize moves a split neighboring boundary", function()
        local engine = new_engine({ min_width = 50, min_height = 40 })
        local state = engine:workspace("1", AREA)
        engine:set_tile("1", "focus", { x = 0, y = 0, w = 200, h = 200 })
        engine:set_tile("1", "top", { x = 200, y = 0, w = 200, h = 100 })
        engine:set_tile("1", "bottom", { x = 200, y = 100, w = 200, h = 100 })
        state.focus_key = "focus"

        T.truthy(engine:resize(state, "right", 60))
        T.near(state.tiles.focus.w, 260)
        T.near(state.tiles.top.x, 260)
        T.near(state.tiles.top.w, 140)
        T.near(state.tiles.bottom.x, 260)
        T.near(state.tiles.bottom.w, 140)

        T.truthy(engine:resize(state, "right", -20))
        T.near(state.tiles.focus.w, 240)
        T.near(state.tiles.top.x, 240)
        T.near(state.tiles.top.w, 160)
        T.truthy(engine:validate(state))
    end)

    T.case("viewport pans in all four directions", function()
        local engine = new_engine()
        local state = engine:workspace("1", AREA)
        engine:pan(state, "right", 300)
        engine:pan(state, "down", 200)
        T.near(state.viewport.x, 300)
        T.near(state.viewport.y, 200)
        engine:pan(state, "left", 300)
        engine:pan(state, "up", 200)
        T.near(state.viewport.x, 0)
        T.near(state.viewport.y, 0)
    end)

    T.case("directional insertion supports negative world coordinates", function()
        local engine = new_engine({ insertion = "left" })
        local state = engine:sync("1", descriptors(1, 1), AREA)
        state = engine:sync("1", descriptors(2, 2), AREA)
        T.truthy(state.tiles["2"].x < 0)
        engine:set_insertion(state, "up")
        state = engine:sync("1", descriptors(3, 3), AREA)
        T.truthy(state.tiles["3"].y < state.tiles["2"].y)
        T.truthy(engine:validate(state))
    end)

    T.case("workspace canvas and viewport state are independent", function()
        local engine = new_engine()
        local first = engine:sync("1", descriptors(3, 3), AREA)
        local second = engine:sync("5", descriptors(2, 2), AREA)
        local second_x = second.viewport.x
        local second_y = second.viewport.y
        engine:pan(first, "right", 800)
        engine:pan(first, "down", 300)
        T.near(second.viewport.x, second_x)
        T.near(second.viewport.y, second_y)
        T.equal(engine:present_count(first), 3)
        T.equal(engine:present_count(second), 2)
    end)

    T.case("cross-workspace moves remove stale source geometry", function()
        local engine = new_engine()
        engine:sync("1", { { key = "moving", active = true } }, AREA)
        engine:sync("2", { { key = "resident", active = true } }, AREA)
        engine:forget_window("moving", "2")
        local destination = engine:sync("2", {
            { key = "resident", active = false },
            { key = "moving", active = true },
        }, AREA)
        T.equal(engine.workspaces["1"].tiles.moving, nil)
        T.truthy(destination.tiles.moving)
        T.truthy(engine:validate(destination))
    end)

    T.case("workspace monitor migration preserves world and viewport coordinates", function()
        local engine = new_engine()
        local state = engine:sync("1", descriptors(4, 4), AREA)
        engine:pan(state, "right", 725)
        engine:pan(state, "down", 180)
        local viewport_x = state.viewport.x
        local viewport_y = state.viewport.y
        local tile_before = rect_snapshot(state.tiles["1"])
        state = engine:sync("1", descriptors(4, 4), { x = 1920, y = 0, w = 1440, h = 900 })
        assert_rect(T, state.tiles["1"], tile_before)
        T.near(state.viewport.x, viewport_x)
        T.near(state.viewport.y, viewport_y)
        T.near(state.viewport.width, 1440)
        T.near(state.viewport.height, 900)
        local box = engine:screen_box(state, state.tiles["1"], { x = 1920, y = 0, w = 1440, h = 900 })
        T.near(box.x, 1920 + tile_before.x - viewport_x)
    end)

    T.case("monitor disconnect and reconnect leaves workspace state intact", function()
        local engine = new_engine()
        local state = engine:sync("7", descriptors(5, 5), AREA)
        engine:pan(state, "down", 1200)
        local viewport_y = state.viewport.y
        local first = rect_snapshot(state.tiles["1"])
        state = engine:sync("7", descriptors(5, 5), { x = -1280, y = 0, w = 1280, h = 720 })
        assert_rect(T, state.tiles["1"], first)
        T.near(state.viewport.y, viewport_y)
    end)

    T.case("fullscreen metadata does not mutate world geometry", function()
        local engine = new_engine()
        local state = engine:sync("1", {
            { key = "full", active = true, fullscreen = 2 },
            { key = "other", active = false },
        }, AREA)
        local before = rect_snapshot(state.tiles.full)
        state = engine:sync("1", {
            { key = "full", active = true, fullscreen = 0 },
            { key = "other", active = false },
        }, AREA)
        assert_rect(T, state.tiles.full, before)
        T.truthy(engine:validate(state))
    end)

    T.case("temporarily floating a tile restores its world rectangle", function()
        local engine = new_engine()
        local state = engine:sync("1", descriptors(2, 2), AREA)
        local before = rect_snapshot(state.tiles["2"])
        state = engine:sync("1", { { key = "1", active = true } }, AREA)
        T.falsy(state.tiles["2"].present)
        state = engine:sync("1", descriptors(2, 2), AREA)
        assert_rect(T, state.tiles["2"], before)
        T.truthy(state.tiles["2"].present)
    end)

    T.case("tiled transient targets receive deterministic geometry", function()
        local engine = new_engine()
        local state = engine:sync("1", {
            { key = "parent", active = false },
            { key = "dialog", active = true, transient = true },
        }, AREA)
        T.truthy(state.tiles.dialog)
        T.truthy(engine:validate(state))
    end)

    T.case("monitor resolution changes only derived viewport dimensions", function()
        local engine = new_engine()
        local state = engine:sync("1", descriptors(3, 3), AREA)
        local before = rect_snapshot(state.tiles["2"])
        state = engine:sync("1", descriptors(3, 3), { x = 0, y = 0, w = 2560, h = 1440 })
        assert_rect(T, state.tiles["2"], before)
        T.near(state.viewport.width, 2560)
        T.near(state.viewport.height, 1440)
    end)

    T.case("fit all derives a zoomed viewport without changing world rectangles", function()
        local engine = new_engine({ min_fit_scale = 0.05 })
        local state = engine:workspace("1", AREA)
        engine:set_tile("1", "a", { x = 0, y = 0, w = 900, h = 700 })
        engine:set_tile("1", "b", { x = 2000, y = 1200, w = 900, h = 700 })
        local before = rect_snapshot(state.tiles.b)
        T.truthy(engine:fit_all(state))
        T.truthy(state.viewport.scale < 1)
        assert_rect(T, state.tiles.b, before)
        local box = engine:screen_box(state, state.tiles.b, AREA)
        T.truthy(box.w < before.w)
    end)

    T.case("fresh engine reload is deterministic and isolated", function()
        local first = new_engine()
        local second = new_engine()
        local first_state = first:sync("1", descriptors(10, 10), AREA)
        local second_state = second:sync("1", descriptors(10, 10), AREA)
        for key, tile in pairs(first_state.tiles) do
            assert_rect(T, second_state.tiles[key], tile)
        end
        local second_viewport_x = second_state.viewport.x
        first:pan(first_state, "right", 500)
        T.near(second_state.viewport.x, second_viewport_x)
    end)

    T.case("rapid navigation and panning preserve geometry invariants", function()
        local engine = new_engine()
        local state = engine:sync("1", descriptors(100, 100), AREA)
        local directions = { "left", "up", "right", "down" }
        for index = 1, 1000 do
            local direction = directions[(index - 1) % #directions + 1]
            engine:focus(state, direction)
            engine:pan(state, direction, 7)
        end
        local valid, reason = engine:validate(state)
        T.truthy(valid, reason)
        T.equal(engine:present_count(state), 100)
    end)

    T.case("layout message aliases expose requested command vocabulary", function()
        local engine = new_engine()
        local state = engine:sync("1", descriptors(5, 5), AREA)
        local viewport_x = state.viewport.x
        T.truthy(engine:command(state, "pan-left 125").changed)
        T.near(state.viewport.x, viewport_x - 125)
        T.truthy(engine:command(state, "center-focused") ~= nil)
        T.truthy(engine:command(state, "fit-all") ~= nil)
        T.truthy(engine:command(state, "reset-viewport") ~= nil)
        T.truthy(engine:command(state, "insert-down").changed)
        local result, command_error = engine:command(state, "not-a-command")
        T.equal(result, nil)
        T.match(command_error, "unknown layout message")
    end)

    T.case("resizing stops at configured minimum dimensions", function()
        local engine = new_engine({ min_width = 100, min_height = 80 })
        local state = engine:workspace("1", AREA)
        engine:set_tile("1", "focus", { x = 0, y = 0, w = 150, h = 100 })
        state.focus_key = "focus"
        engine:resize(state, "right", -1000)
        T.near(state.tiles.focus.w, 100)
        engine:resize(state, "down", -1000)
        T.near(state.tiles.focus.h, 80)
        T.truthy(engine:validate(state))
    end)
end
