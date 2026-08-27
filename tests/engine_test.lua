local Engine = require("grid.engine")
local Geometry = require("grid.geometry")

local AREA = { x = 0, y = 0, w = 1000, h = 800 }

local function new_engine(options)
    options = options or {}
    options.min_width = options.min_width or 50
    options.min_height = options.min_height or 40
    return Engine.new(options)
end

local function descriptors(entries)
    local result = {}
    for index, entry in ipairs(entries) do
        if type(entry) == "string" then
            result[index] = { key = entry, active = false }
        else
            result[index] = { key = entry.key, active = entry.active == true }
        end
    end
    return result
end

local function assert_neighbors(T, left, right)
    T.near(left.x + left.w, right.x, 0.001, "windows must be neighbors")
end

return function(T)
    T.case("first tiled window fills the work area", function()
        local engine = new_engine()
        local state = engine:sync("1", descriptors({ { key = "w1", active = true } }), AREA)
        T.near(state.tiles.w1.x, 0)
        T.near(state.tiles.w1.y, 0)
        T.near(state.tiles.w1.w, AREA.w)
        T.near(state.tiles.w1.h, AREA.h)
        T.equal(state.focus_key, "w1")
    end)

    T.case("new windows always stack to the right as full-height neighbors", function()
        local engine = new_engine()
        local state = engine:sync("1", descriptors({ { key = "w1", active = true }, "w2", "w3" }), AREA)
        assert_neighbors(T, state.tiles.w1, state.tiles.w2)
        assert_neighbors(T, state.tiles.w2, state.tiles.w3)
        T.near(state.tiles.w3.x + state.tiles.w3.w, AREA.w)
        T.near(state.tiles.w1.h, AREA.h)
        T.near(state.tiles.w3.h, AREA.h)
    end)

    T.case("closing the middle window makes its neighbors adjacent", function()
        local engine = new_engine()
        engine:sync("1", descriptors({ { key = "w1", active = true }, "w2", "w3" }), AREA)
        local state = engine:sync("1", descriptors({ { key = "w1" }, "w3" }), AREA)
        T.equal(state.tiles.w2, nil)
        assert_neighbors(T, state.tiles.w1, state.tiles.w3)
        T.near(state.tiles.w1.w, AREA.w / 2)
        T.near(state.tiles.w1.h, AREA.h)
        T.equal(engine:present_count(state), 2)
        local valid, reason = engine:validate(state)
        T.truthy(valid, reason)
    end)

    T.case("closing windows keeps a surviving focus and heals both axes", function()
        local engine = new_engine()
        local state = engine:sync("1", descriptors({ { key = "w1" }, { key = "w2", active = true }, "w3" }), AREA)
        engine:move(state, "down") -- w2 -> second row
        T.equal(#state.rows, 2)
        state = engine:sync("1", descriptors({ "w1", "w3" }), AREA) -- w2 closed
        T.equal(engine:present_count(state), 2)
        T.equal(#state.rows, 1)
        assert_neighbors(T, state.tiles.w1, state.tiles.w3)
        T.truthy(state.focus_key == "w1" or state.focus_key == "w3")
        local valid, reason = engine:validate(state)
        T.truthy(valid, reason)
    end)
    T.case("engine focus navigates over derived rows", function()
        local engine = new_engine()
        local state = engine:sync("1", descriptors({ { key = "top", active = true } }), AREA)
        engine:command(state, "insert down")
        state = engine:sync("1", descriptors({ { key = "bottom" }, { key = "top" } }), AREA)
        T.equal(#state.rows, 2)
        state.focus_key = "top"
        T.equal(engine:focus(state, "down"), "bottom")
        T.equal(engine:focus(state, "up"), "top")

        local second_row_cells = state.rows[2].cells
        second_row_cells[#second_row_cells + 1] = { key = "bottom-right", width = 0.5 }
        engine:_materialize(state)
        state.focus_key = "bottom"
        T.equal(engine:focus(state, "right"), "bottom-right")
        state.focus_key = "bottom-right"
        T.equal(engine:focus(state, "left"), "bottom")
    end)
    T.case("move down pushes the whole window into a new row", function()
        local engine = new_engine()
        local state = engine:sync("1", descriptors({ { key = "w1" }, { key = "w2", active = true }, "w3" }), AREA)
        T.truthy(engine:move(state, "down"))
        engine:_materialize(state)
        T.equal(#state.rows, 2)
        T.equal(state.focus_key, "w2")
        T.near(state.tiles.w2.y, 400)
        T.near(state.tiles.w2.h, 400)
        T.near(state.tiles.w2.w, AREA.w)
        T.near(state.tiles.w1.h, 400)
        T.near(state.tiles.w3.x, 500)
        T.near(state.tiles.w3.h, 400)
        local valid, reason = engine:validate(state)
        T.truthy(valid, reason)
    end)

    T.case("move up joins the existing row above near the source edge", function()
        local engine = new_engine()
        local state = engine:sync("1", descriptors({ { key = "w1" }, { key = "w2", active = true }, "w3" }), AREA)
        engine:move(state, "down")
        T.truthy(engine:move(state, "up"))
        engine:_materialize(state)
        T.equal(#state.rows, 1)
        T.near(state.tiles.w2.x, 0)
        T.near(state.tiles.w2.y, 0)
        T.near(state.tiles.w2.h, AREA.h)
        assert_neighbors(T, state.tiles.w2, state.tiles.w1)
        assert_neighbors(T, state.tiles.w1, state.tiles.w3)
    end)

    T.case("horizontal movement reorders the row and wraps at its edges", function()
        local engine = new_engine()
        local state = engine:sync("1", descriptors({ { key = "a" }, "b", { key = "c", active = true } }), AREA)
        T.truthy(engine:move(state, "right"))
        engine:_materialize(state)
        T.near(state.tiles.c.x, 0)
        assert_neighbors(T, state.tiles.c, state.tiles.a)
        assert_neighbors(T, state.tiles.a, state.tiles.b)

        local solo_engine = new_engine()
        local solo = solo_engine:sync("9", descriptors({ { key = "solo", active = true } }), AREA)
        T.falsy(solo_engine:move(solo, "right"))
        T.falsy(solo_engine:move(solo, "left"))
    end)
    T.case("width cycling walks presets without exceeding the screen", function()
        local engine = new_engine()
        local state = engine:sync("1", descriptors({ { key = "a", active = true }, "b" }), AREA)
        T.near(state.tiles.a.w, 500)

        T.truthy(engine:command(state, "resize right").changed)
        engine:_materialize(state)
        assert_neighbors(T, state.tiles.a, state.tiles.b)
        T.near(state.tiles.a.w + state.tiles.b.w, AREA.w)
        T.near(state.tiles.a.w, 1000 * 0.67 / 1.17, 0.01)
        T.near(state.tiles.b.w, 1000 * 0.50 / 1.17, 0.01)

        T.truthy(engine:command(state, "resize left").changed)
        engine:_materialize(state)
        T.near(state.tiles.a.w, 500)

        T.truthy(engine:command(state, "resize left").changed)
        engine:_materialize(state)
        T.near(state.tiles.a.w, 1000 * 0.34 / 0.84, 0.01)

        -- stepping below the smallest preset wraps around to the widest one
        T.truthy(engine:command(state, "resize left").changed)
        engine:_materialize(state)
        T.near(state.tiles.a.w, 1000 * 1.00 / 1.50, 0.01)
        T.near(state.tiles.b.w, 1000 * 0.50 / 1.50, 0.01)
        assert_neighbors(T, state.tiles.a, state.tiles.b)
    end)

    T.case("vertical resize transfers height between rows and stops at the minimum", function()
        local engine = new_engine()
        local state = engine:sync("1", descriptors({ { key = "top", active = true }, "mid", "bot" }), AREA)
        engine:move(state, "down") -- top -> second row
        engine:_materialize(state)

        T.truthy(engine:command(state, "resize up").changed) -- top's row grows, row above donates
        engine:_materialize(state)
        T.near(state.tiles.top.y, 340)
        T.near(state.tiles.top.h, 460)
        T.near(state.tiles.mid.h, 340)

        for _ = 1, 12 do
            engine:command(state, "resize up 500")
        end
        engine:_materialize(state)
        T.near(state.tiles.top.h, 760)
        T.near(state.tiles.mid.h, 40) -- clamped at min_height
        T.near(state.tiles.bot.h, 40)
        T.falsy(engine:resize_rows(state, "up", 500))
        local valid, reason = engine:validate(state)
        T.truthy(valid, reason)
    end)

    T.case("single-row vertical resize is a no-op", function()
        local engine = new_engine()
        local state = engine:sync("1", descriptors({ { key = "a", active = true }, "b" }), AREA)
        T.falsy(engine:resize_rows(state, "down", 100))
        T.falsy(engine:resize_rows(state, "up", 100))
        T.near(state.tiles.a.h, AREA.h)
    end)
    T.case("insert down opens the next window into a lower band", function()
        local engine = new_engine()
        local state = engine:sync("1", descriptors({ { key = "top", active = true } }), AREA)
        T.truthy(engine:command(state, "insert down").changed)
        state = engine:sync("1", descriptors({ { key = "bottom" }, { key = "top" } }), AREA)
        T.equal(#state.rows, 2)
        T.near(state.tiles.bottom.y, 400)
        T.near(state.tiles.bottom.h, 400)
        T.near(state.tiles.top.h, 400)
        T.equal(engine:present_count(state), 2)
    end)

    T.case("insert left prepends into the anchor row", function()
        local engine = new_engine()
        local state = engine:sync("1", descriptors({ { key = "a", active = true } }), AREA)
        T.truthy(engine:command(state, "insert left").changed)
        state = engine:sync("1", descriptors({ { key = "b" }, { key = "a" } }), AREA)
        T.equal(#state.rows, 1)
        T.near(state.tiles.b.x, 0)
        T.near(state.tiles.a.x, 500)
        assert_neighbors(T, state.tiles.b, state.tiles.a)
    end)

    T.case("monitor dimension changes rescale the derived canvas proportionally", function()
        local engine = new_engine()
        local state = engine:sync("1", descriptors({ { key = "a", active = true }, "b" }), AREA)
        state = engine:sync("1", descriptors({ { key = "a" }, "b" }), { x = 0, y = 0, w = 2000, h = 1600 })
        T.near(state.viewport.width, 2000)
        T.near(state.viewport.height, 1600)
        T.near(state.tiles.a.w, 1000)
        T.near(state.tiles.b.x, 1000)
        T.near(state.tiles.a.h, 1600)
    end)

    T.case("rapid structural edits preserve grid invariants", function()
        local engine = new_engine()
        local keys = {}
        for index = 1, 12 do
            keys[#keys + 1] = "t" .. index
        end
        local live = {}
        for _, key in ipairs(keys) do
            live[#live + 1] = { key = key, active = true }
            local state = engine:sync("1", descriptors(live), AREA)
            local valid, reason = engine:validate(state)
            T.truthy(valid, reason)
        end

        local ops = { "down", "down", "up", "left", "right", "down", "left" }
        for _, direction in ipairs(ops) do
            local state = engine.workspaces["1"]
            engine:move(state, direction)
            engine:_materialize(state)
            local valid, reason = engine:validate(state)
            T.truthy(valid, reason)
            T.equal(engine:present_count(state), 12)
        end

        table.remove(live, #live - 3)
        table.remove(live, #live - 3)
        local state = engine:sync("1", live, AREA)
        T.equal(engine:present_count(state), 10)
        local valid, reason = engine:validate(state)
        T.truthy(valid, reason)

        -- auto-reveal may have panned to follow newcomers; the canvas itself
        -- never moves, so resetting must restore the zeroed origin
        T.truthy(engine:command(state, "reset viewport").changed or state.viewport.x == 0)
        T.near(state.viewport.x, 0)
        T.near(state.viewport.y, 0)
    end)

    T.case("layout message aliases expose requested command vocabulary", function()
        local engine = new_engine()
        local state = engine:sync("1", descriptors({ { key = "w1", active = true }, "w2" }), AREA)
        local viewport_x = state.viewport.x
        T.truthy(engine:command(state, "pan-left 125").changed)
        T.near(state.viewport.x, viewport_x - 125)
        T.truthy(engine:command(state, "center-focused") ~= nil)
        T.truthy(engine:command(state, "fit-all") ~= nil)
        T.truthy(engine:command(state, "reset-viewport") ~= nil)
        T.truthy(engine:command(state, "insert-down").changed)
        T.truthy(engine:command(state, "cycle width backward").changed)
        local result, command_error = engine:command(state, "not-a-command")
        T.equal(result, nil)
        T.match(command_error, "unknown layout message")
    end)
end
