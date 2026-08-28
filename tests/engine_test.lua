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

local function snapshot(tile)
    return { x = tile.x, y = tile.y, w = tile.w, h = tile.h }
end

local function assert_rect(T, actual, expected)
    T.near(actual.x, expected.x)
    T.near(actual.y, expected.y)
    T.near(actual.w, expected.w)
    T.near(actual.h, expected.h)
end

return function(T)
    T.case("first tiled window gets a fixed full-height default rectangle", function()
        local engine = new_engine()
        local state = engine:sync("1", descriptors({ { key = "w1", active = true } }), AREA)
        local tile = state.tiles.w1
        T.near(tile.x, 0)
        T.near(tile.y, 0)
        T.near(tile.w, 500)
        T.near(tile.h, 800)
        T.near(tile.h, AREA.h)
        T.near(state.viewport.x, 0)
        T.near(state.viewport.y, 0)
        T.truthy(tile.w < AREA.w)
        T.equal(state.focus_key, "w1")
    end)
    T.case("sole origin tile clears a stale viewport offset", function()
        local engine = new_engine()
        local state = engine:sync("1", descriptors({ { key = "w1", active = true } }), AREA)
        state.viewport.x = -48
        state.viewport.y = 24

        engine:reveal(state, "w1")
        T.near(state.viewport.x, 0)
        T.near(state.viewport.y, 0)
    end)

    T.case("new windows continue horizontally without a wrap limit", function()
        local engine = new_engine()
        local state = engine:sync("1", descriptors({ { key = "w1", active = true } }), AREA)
        local first = snapshot(state.tiles.w1)

        state = engine:sync("1", descriptors({ { key = "w1" }, "w2", "w3", "w4", "w5", "w6", "w7" }), AREA)
        T.near(state.tiles.w1.w, first.w)
        T.near(state.tiles.w1.h, first.h)
        T.near(state.tiles.w4.x, 1500)
        T.near(state.tiles.w4.y, 0)
        T.near(state.tiles.w5.x, 2000)
        T.near(state.tiles.w5.y, 0)
        T.near(state.tiles.w7.x, 3000)
        T.near(state.tiles.w7.y, 0)
        T.near(Geometry.bounds(state.tiles).w, 3500)
        T.near(Geometry.bounds(state.tiles).h, first.h)
        T.equal(#state.rows, 1)
        T.truthy(engine:validate(state))
    end)

    T.case("different workspaces keep independent canvases and viewports", function()
        local engine = new_engine()
        local first = engine:sync("1", descriptors({ { key = "a", active = true }, "b", "c" }), AREA)
        local second = engine:sync("2", descriptors({ { key = "x", active = true }, "y" }), AREA)
        local first_rect = snapshot(first.tiles.a)
        local second_x = second.viewport.x
        local second_y = second.viewport.y

        engine:pan(first, "right", 800)
        engine:pan(first, "down", 400)
        T.near(second.viewport.x, second_x)
        T.near(second.viewport.y, second_y)
        assert_rect(T, first.tiles.a, first_rect)
        T.equal(engine:present_count(first), 3)
        T.equal(engine:present_count(second), 2)
    end)

    T.case("focus moves the viewport without changing any tile rectangle", function()
        local engine = new_engine({ viewport_margin = 48 })
        local state = engine:sync("1", descriptors({ { key = "a", active = true }, "b", "c" }), AREA)
        state.focus_key = "c"
        T.truthy(engine:move(state, "down"))
        state.focus_key = "a"

        local before = {}
        for key, tile in pairs(state.tiles) do
            before[key] = snapshot(tile)
        end
        local old_viewport_x = state.viewport.x

        T.equal(engine:focus(state, "right"), "b")
        T.truthy(state.viewport.x ~= old_viewport_x)
        for key, tile in pairs(state.tiles) do
            assert_rect(T, tile, before[key])
        end

        T.equal(engine:focus(state, "down"), "c")
        T.truthy(state.viewport.y > 0)
    end)

    T.case("move swaps positions while preserving both windows' dimensions", function()
        local engine = new_engine()
        local state = engine:sync("1", descriptors({ { key = "a", active = true }, "b", "c", "d", "e", "f" }), AREA)
        state.tiles.a.w = 300
        state.tiles.a.h = 300
        state.tiles.b.w = 600
        state.tiles.b.h = 300
        local a_size = { w = state.tiles.a.w, h = state.tiles.a.h }
        local b_size = { w = state.tiles.b.w, h = state.tiles.b.h }
        engine:_materialize(state)

        T.truthy(engine:move(state, "right"))
        T.near(state.tiles.a.w, a_size.w)
        T.near(state.tiles.a.h, a_size.h)
        T.near(state.tiles.b.w, b_size.w)
        T.near(state.tiles.b.h, b_size.h)
        T.near(state.tiles.b.x, 0)
        T.near(state.tiles.a.x, state.tiles.b.x + state.tiles.b.w)
        T.truthy(engine:validate(state))

        state.focus_key = "b"
        local b_y = state.tiles.b.y
        T.truthy(engine:move(state, "down"))
        T.near(state.tiles.b.w, b_size.w)
        T.near(state.tiles.b.h, b_size.h)
        T.truthy(state.tiles.b.y > b_y)
        T.truthy(engine:validate(state))
    end)
    T.case("vertical edge move compacts the source row", function()
        local engine = new_engine()
        local state = engine:sync(
            "1",
            descriptors({ "left", { key = "middle", active = true }, "right" }),
            AREA
        )
        local row_start = Geometry.bounds(state.tiles).x
        local before_middle = snapshot(state.tiles.middle)
        local before_right = snapshot(state.tiles.right)

        T.truthy(engine:move(state, "down"))
        T.near(state.tiles.middle.x, row_start)
        T.near(state.tiles.middle.y, before_middle.y + before_middle.h)
        T.near(state.tiles.middle.w, before_middle.w)
        T.near(state.tiles.middle.h, before_middle.h)
        T.near(state.tiles.right.x, before_right.x - before_middle.w)
        T.near(state.tiles.right.y, before_right.y)
        T.truthy(engine:validate(state))

        engine:forget_window("middle")
        state = engine:sync(
            "1",
            descriptors({ "left", { key = "right", active = true } }),
            AREA
        )
        T.near(state.tiles.right.x, state.tiles.left.x + state.tiles.left.w)
        T.near(state.tiles.right.y, state.tiles.left.y)
        T.truthy(engine:validate(state))

        local up_state = engine:sync(
            "2",
            descriptors({ "left", { key = "middle", active = true }, "right" }),
            AREA
        )
        local up_row_start = Geometry.bounds(up_state.tiles).x
        local before_up_middle = snapshot(up_state.tiles.middle)
        local before_up_right = snapshot(up_state.tiles.right)

        T.truthy(engine:move(up_state, "up"))
        T.near(up_state.tiles.middle.x, up_row_start)
        T.near(up_state.tiles.middle.y, before_up_middle.y - before_up_middle.h)
        T.near(up_state.tiles.middle.w, before_up_middle.w)
        T.near(up_state.tiles.middle.h, before_up_middle.h)
        T.near(up_state.tiles.right.x, before_up_right.x - before_up_middle.w)
        T.near(up_state.tiles.right.y, before_up_right.y)
        T.truthy(engine:validate(up_state))
    end)
    T.case("vertical moves append to an existing destination row", function()
        local engine = new_engine()
        local state = engine:sync(
            "1",
            descriptors({ "a", { key = "b", active = true }, "c", "d" }),
            AREA
        )

        T.truthy(engine:move(state, "down"))
        T.near(state.tiles.a.x, 0)
        T.near(state.tiles.c.x, 500)
        T.near(state.tiles.d.x, 1000)
        T.near(state.tiles.b.x, 0)
        T.near(state.tiles.b.y, state.tiles.a.h)

        state.focus_key = "c"
        T.truthy(engine:move(state, "down"))
        T.near(state.tiles.a.x, 0)
        T.near(state.tiles.d.x, state.tiles.a.x + state.tiles.a.w)
        T.near(state.tiles.b.x, 0)
        T.near(state.tiles.c.x, state.tiles.b.x + state.tiles.b.w)
        T.near(state.tiles.b.y, state.tiles.c.y)
        T.near(state.tiles.d.y, state.tiles.a.y)
        T.truthy(engine:validate(state))

        local up_state = engine:sync(
            "2",
            descriptors({ "a", "b", { key = "c", active = true }, "d" }),
            AREA
        )
        T.truthy(engine:move(up_state, "up"))

        up_state.focus_key = "b"
        T.truthy(engine:move(up_state, "up"))
        T.near(up_state.tiles.a.x, 0)
        T.near(up_state.tiles.d.x, up_state.tiles.a.x + up_state.tiles.a.w)
        T.near(up_state.tiles.c.x, 0)
        T.near(up_state.tiles.b.x, up_state.tiles.c.x + up_state.tiles.c.w)
        T.near(up_state.tiles.c.y, up_state.tiles.b.y)
        T.near(up_state.tiles.d.y, up_state.tiles.a.y)
        T.truthy(engine:validate(up_state))
    end)
    T.case("horizontal resizing keeps the row contiguous in both directions", function()
        local engine = new_engine()
        local state = engine:sync(
            "1",
            descriptors({ "a", { key = "b", active = true }, "c" }),
            AREA
        )

        T.truthy(engine:command(state, "resize right").changed)
        T.near(state.tiles.c.x, state.tiles.b.x + state.tiles.b.w)
        T.truthy(engine:command(state, "resize right").changed)
        T.near(state.tiles.c.x, state.tiles.b.x + state.tiles.b.w)
        T.truthy(engine:command(state, "resize right").changed)
        T.near(state.tiles.c.x, state.tiles.b.x + state.tiles.b.w)
        T.near(state.tiles.a.x + state.tiles.a.w, state.tiles.b.x)

        local row_start = state.tiles.a.x
        T.truthy(engine:command(state, "resize left").changed)
        T.near(state.tiles.a.x + state.tiles.a.w, state.tiles.b.x)
        T.near(state.tiles.b.x + state.tiles.b.w, state.tiles.c.x)
        T.near(state.tiles.a.x, row_start)
        T.truthy(engine:validate(state))
    end)

    T.case("width cycling compacts each row independently from the left", function()
        local engine = new_engine()
        local state = engine:sync(
            "1",
            descriptors({ "top-left", "top-right", { key = "bottom", active = true } }),
            AREA
        )
        T.truthy(engine:move(state, "down"))

        local top_left_before = snapshot(state.tiles["top-left"])
        local top_right_before = snapshot(state.tiles["top-right"])
        local bottom_left = state.tiles.bottom.x
        T.truthy(engine:command(state, "cycle width backward").changed)

        T.near(state.tiles.bottom.x, bottom_left)
        T.near(state.tiles.bottom.w, 340)
        assert_rect(T, state.tiles["top-left"], top_left_before)
        assert_rect(T, state.tiles["top-right"], top_right_before)

        T.equal(engine:focus(state, "up"), "top-left")
        local top_row_start = state.tiles["top-left"].x
        T.truthy(engine:command(state, "cycle width backward").changed)
        T.near(state.tiles["top-left"].x, top_row_start)
        T.near(
            state.tiles["top-left"].x + state.tiles["top-left"].w,
            state.tiles["top-right"].x
        )
        T.truthy(engine:validate(state))
    end)

    T.case("explicit down insertion keeps the new row's fixed height", function()
        local engine = new_engine()
        local state = engine:sync("1", descriptors({ { key = "top", active = true } }), AREA)
        T.truthy(engine:command(state, "insert down").changed)
        state = engine:sync("1", descriptors({ "top", { key = "bottom", active = true } }), AREA)
        T.near(state.tiles.bottom.x, 0)
        T.near(state.tiles.bottom.y, state.tiles.top.h)
        T.near(state.tiles.bottom.w, state.tiles.top.w)
        T.near(state.tiles.bottom.h, state.tiles.top.h)
        T.truthy(engine:validate(state))
    end)

    T.case("horizontal resize changes only the focused width and pushes neighbors", function()
        local engine = new_engine()
        local state = engine:sync("1", descriptors({ { key = "a", active = true }, "b" }), AREA)
        local b = snapshot(state.tiles.b)
        T.truthy(engine:command(state, "resize right").changed)
        T.near(state.tiles.a.w, 670)
        T.near(state.tiles.a.h, b.h)
        T.near(state.tiles.b.w, b.w)
        T.near(state.tiles.b.h, b.h)
        T.near(state.tiles.b.x, state.tiles.a.x + state.tiles.a.w)
        T.truthy(engine:validate(state))

        T.truthy(engine:command(state, "resize left").changed)
        T.near(state.tiles.a.w, 500)
        T.near(state.tiles.b.w, b.w)
        T.truthy(engine:validate(state))
    end)

    T.case("vertical resize changes only the focused height", function()
        local engine = new_engine()
        local state = engine:sync("1", descriptors({ { key = "a", active = true }, "b" }), AREA)
        local before = snapshot(state.tiles.b)
        T.truthy(engine:command(state, "resize down").changed)
        T.near(state.tiles.a.h, 860)
        T.near(state.tiles.b.w, before.w)
        T.near(state.tiles.b.h, before.h)
        T.truthy(engine:validate(state))

        T.truthy(engine:command(state, "resize up -100").changed)
        T.near(state.tiles.a.h, 760)
        T.near(state.tiles.b.h, before.h)
        T.truthy(engine:validate(state))
    end)

    T.case("resizing stops at configured minimum dimensions", function()
        local engine = new_engine({ min_width = 100, min_height = 80 })
        local state = engine:sync("1", descriptors({ { key = "a", active = true } }), AREA)
        engine:resize(state, "right", -1000)
        engine:resize(state, "down", -1000)
        T.near(state.tiles.a.w, 100)
        T.near(state.tiles.a.h, 80)
        T.falsy(engine:resize(state, "right", -1))
        T.falsy(engine:resize(state, "down", -1))
        T.truthy(engine:validate(state))
    end)

    T.case("closing a window removes only that target and keeps fixed survivors", function()
        local engine = new_engine()
        local state = engine:sync("1", descriptors({ { key = "a", active = true }, "b", "c" }), AREA)
        local survivor = snapshot(state.tiles.c)
        engine:forget_window("b")
        state = engine:sync("1", descriptors({ { key = "a" }, { key = "c", active = true } }), AREA)
        T.equal(state.tiles.b, nil)
        T.near(state.tiles.c.x, 500)
        T.near(state.tiles.c.y, survivor.y)
        T.near(state.tiles.c.w, survivor.w)
        T.near(state.tiles.c.h, survivor.h)
        T.equal(state.focus_key, "c")
        T.truthy(engine:validate(state))
    end)
    T.case("closing focused windows selects a same-row neighbor", function()
        local engine = new_engine()
        local state = engine:sync(
            "1",
            descriptors({ "left", { key = "middle", active = true }, "right", "far", "bottom" }),
            AREA
        )
        local bottom_y = state.tiles.bottom.y
        state.viewport.y = bottom_y

        local replacement = engine:forget_window("middle")
        T.equal(replacement, "right")
        T.equal(state.focus_key, "right")
        T.equal(state.tiles.middle, nil)
        T.near(state.tiles.right.x, 500)
        T.near(state.tiles.bottom.y, bottom_y)
        T.truthy(engine:validate(state))
    end)

    T.case("closing the only window in a row deletes the row and focuses another row", function()
        local engine = new_engine()
        local state = engine:sync("2", descriptors({ { key = "top", active = true }, "bottom" }), AREA)
        state.tiles.bottom.x = 0
        state.tiles.bottom.y = state.tiles.top.h
        engine:_materialize(state)

        local replacement = engine:forget_window("top")
        T.equal(replacement, "bottom")
        T.equal(state.focus_key, "bottom")
        T.equal(state.tiles.top, nil)
        T.near(state.tiles.bottom.y, 0)
        T.equal(#state.rows, 1)

        state = engine:sync("2", descriptors({ { key = "bottom", active = true } }), AREA)
        T.equal(state.focus_key, "bottom")
        local reveal = engine:command(state, "reveal")
        T.falsy(reveal.changed)
        T.near(state.viewport.y, 0)
        T.truthy(engine:validate(state))
    end)

    T.case("floating targets can return to their previous rectangle", function()
        local engine = new_engine()
        local state = engine:sync("1", descriptors({ { key = "a", active = true }, "b" }), AREA)
        local before = snapshot(state.tiles.b)
        state = engine:sync("1", descriptors({ { key = "a", active = true } }), AREA)
        T.falsy(state.tiles.b.present)
        state = engine:sync("1", descriptors({ { key = "a" }, { key = "b", active = true } }), AREA)
        assert_rect(T, state.tiles.b, before)
        T.truthy(engine:validate(state))
    end)

    T.case("monitor changes preserve world rectangles while updating viewport size", function()
        local engine = new_engine()
        local state = engine:sync("1", descriptors({ { key = "a", active = true }, "b" }), AREA)
        local before = snapshot(state.tiles.b)
        state = engine:sync("1", descriptors({ "a", { key = "b", active = true } }), { x = 1920, y = 20, w = 1440, h = 900 })
        assert_rect(T, state.tiles.b, before)
        T.near(state.viewport.width, 1440)
        T.near(state.viewport.height, 900)
        local box = engine:screen_box(state, state.tiles.b, { x = 1920, y = 20, w = 1440, h = 900 })
        T.near(box.x, 1920 + before.x - state.viewport.x)
    end)

    T.case("fit and reset change only the viewport transform", function()
        local engine = new_engine({ min_fit_scale = 0.05 })
        local state = engine:workspace("1", AREA)
        engine:set_tile("1", "a", { x = 0, y = 0, w = 900, h = 700 })
        engine:set_tile("1", "b", { x = 2000, y = 1200, w = 900, h = 700 })
        local before = snapshot(state.tiles.b)
        T.truthy(engine:fit_all(state))
        T.truthy(state.viewport.scale < 1)
        assert_rect(T, state.tiles.b, before)
        T.truthy(engine:reset_viewport(state))
        T.near(state.viewport.x, 0)
        T.near(state.viewport.y, 0)
        T.near(state.viewport.scale, 1)
    end)

    T.case("rapid navigation and panning preserve geometry invariants", function()
        local engine = new_engine()
        local entries = {}
        for index = 1, 100 do
            entries[index] = { key = tostring(index), active = index == 1 }
        end
        local state = engine:sync("1", entries, AREA)
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

    T.case("layout message aliases expose the complete command vocabulary", function()
        local engine = new_engine()
        local state = engine:sync("1", descriptors({ { key = "w1", active = true }, "w2" }), AREA)
        local viewport_x = state.viewport.x
        T.truthy(engine:command(state, "pan-left 125").changed)
        T.near(state.viewport.x, viewport_x - 125)
        T.truthy(engine:command(state, "center-focused") ~= nil)
        T.truthy(engine:command(state, "fit-all") ~= nil)
        T.truthy(engine:command(state, "reset-viewport") ~= nil)
        T.truthy(engine:command(state, "insert-down").changed)
        T.truthy(engine:command(state, "cycle width backward") ~= nil)
        local result, command_error = engine:command(state, "not-a-command")
        T.equal(result, nil)
        T.match(command_error, "unknown layout message")
    end)
end
