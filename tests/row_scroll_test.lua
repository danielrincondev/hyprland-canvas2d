local Engine = require("grid.engine")
local Geometry = require("grid.geometry")

local AREA = { x = 1920, y = 30, w = 1000, h = 800 }

local function fixture(options)
    local engine = Engine.new(options)
    local descriptors = {}
    for index, key in ipairs({ "a", "b", "c", "d", "e", "f" }) do
        engine:set_tile("1", key, {
            x = ((index - 1) % 3) * 500,
            y = index > 3 and 800 or 0,
            w = 500, h = 800,
        })
        descriptors[index] = { key = key, active = key == "a" }
    end
    return engine, engine:sync("1", descriptors, AREA), descriptors
end

local function check_geometry(T, engine, state)
    local valid, reason = engine:validate(state)
    T.truthy(valid, reason)
    local screen = {}
    for key, tile in pairs(state.tiles) do
        if tile.present ~= false then
            screen[key] = engine:screen_box(state, tile, AREA)
        end
    end
    valid, reason = Geometry.assert_non_overlapping(screen)
    T.truthy(valid, reason)
end

return function(T)
    T.case("row gap clears the reserved bar and preserves row scroll memory", function()
        local engine, state, descriptors = fixture()
        engine:pan(state, "right", 123)
        engine.config.row_gap = 48
        engine:sync("1", descriptors, AREA)
        T.near(state.tiles.d.y - Geometry.bottom(state.tiles.a), 48)
        engine:focus(state, "down")
        local above = engine:screen_box(state, state.tiles.a, AREA)
        T.truthy(above.y + above.h <= 0, "previous row must clear the bar above the work area")
        engine:focus(state, "up")
        T.near(state.viewport.x, 123)
        engine:command(state, "scroll shared")
        T.near(state.tiles.d.y - Geometry.bottom(state.tiles.a), 48)
        engine:command(state, "scroll rows")
        T.near(state.viewport.x, 123)
        check_geometry(T, engine, state)
    end)

    T.case("row gap survives insertion resizing and empty-row removal", function()
        for _, mode in ipairs({ "rows", "shared" }) do
            local engine = Engine.new({ row_gap = 48, scroll_mode = mode })
            local state = engine:sync("1", { { key = "a", active = true } }, AREA)
            engine:set_insertion(state, "down")
            engine:sync("1", { { key = "a" }, { key = "b", active = true } }, AREA)
            engine:sync("1", { { key = "a" }, { key = "b" }, { key = "c", active = true } }, AREA)
            T.near(state.tiles.b.y - Geometry.bottom(state.tiles.a), 48)
            T.near(state.tiles.c.y - Geometry.bottom(state.tiles.b), 48)
            local old_y = state.tiles.c.y
            local height = state.tiles.b.h
            engine:forget_window("b")
            T.near(state.tiles.c.y, old_y - height - 48)
            T.near(state.tiles.c.y - Geometry.bottom(state.tiles.a), 48)
            state.focus_key = "a"
            engine:resize(state, "down", 100)
            T.truthy(state.tiles.c.y - Geometry.bottom(state.tiles.a) >= 48)
            check_geometry(T, engine, state)
        end
    end)

    T.case("rows are the default and preserve independent scroll and focus", function()
        local engine, state = fixture()
        T.equal(state.scroll_mode, "rows")
        engine:focus(state, "right")
        engine:focus(state, "right")
        T.near(state.viewport.x, 500)
        local top_x = engine:screen_box(state, state.tiles.a, AREA).x
        T.equal(engine:focus(state, "down"), "e")
        T.near(state.viewport.x, 0)
        engine:focus(state, "right")
        engine:pan(state, "right", 123)
        T.near(engine:screen_box(state, state.tiles.a, AREA).x, top_x)
        T.equal(engine:focus(state, "up"), "c")
        T.near(state.viewport.x, 500)
        engine:pan(state, "right", 77)
        T.equal(engine:focus(state, "down"), "f")
        T.near(state.viewport.x, 623)
        T.equal(engine:focus(state, "up"), "c")
        T.near(state.viewport.x, 577)
        check_geometry(T, engine, state)
    end)

    T.case("workspace mode toggle preserves row offsets and restores shared placement", function()
        local engine, state = fixture()
        engine:pan(state, "right", 200)
        engine:focus(state, "down")
        engine:pan(state, "right", 700)
        local other = engine:workspace("2", AREA)
        T.truthy(engine:command(state, "scroll toggle").changed)
        T.equal(state.scroll_mode, "shared")
        T.equal(other.scroll_mode, "rows")
        T.near(engine:screen_box(state, state.tiles.a, AREA).x, AREA.x - 700)
        T.near(engine:screen_box(state, state.tiles.d, AREA).x, AREA.x - 700)
        engine:pan(state, "right", 300)
        T.truthy(engine:command(state, "scroll rows").changed)
        T.near(state.viewport.x, 700)
        T.near(engine:screen_box(state, state.tiles.a, AREA).x, AREA.x - 200)
        engine:focus(state, "up")
        T.near(state.viewport.x, 200)
        T.falsy(engine:command(state, "scroll rows").changed)
        T.equal(engine:command(state, "scroll invalid"), nil)
        T.equal(state.scroll_mode, "rows")
        check_geometry(T, engine, state)
    end)

    T.case("shared mode can be configured as the startup default", function()
        local engine, state = fixture({ scroll_mode = "shared" })
        T.equal(state.scroll_mode, "shared")
        engine:pan(state, "right", 350)
        T.near(engine:screen_box(state, state.tiles.a, AREA).x, AREA.x - 350)
        T.near(engine:screen_box(state, state.tiles.d, AREA).x, AREA.x - 350)
        T.falsy(pcall(Engine.new, { scroll_mode = "invalid" }))
    end)

    T.case("row memory survives recalculation and monitor migration", function()
        local engine, state, descriptors = fixture()
        engine:pan(state, "right", 275)
        for _ = 1, 3 do engine:sync("1", descriptors, AREA) end
        T.near(state.viewport.x, 275)
        engine:sync("1", descriptors, { x = -1440, y = 0, w = 1440, h = 900 })
        T.near(state.viewport.x, 275)
        T.near(state.viewport.width, 1440)
        engine:focus(state, "down")
        engine:focus(state, "up")
        T.near(state.viewport.x, 275)
    end)

    T.case("row identities and scroll survive height resizing and row deletion", function()
        local engine, state = fixture()
        local top_id, bottom_id = state.tiles.a.row_id, state.tiles.d.row_id
        engine:pan(state, "right", 175)
        engine:focus(state, "down")
        engine:pan(state, "right", 325)
        engine:resize(state, "up", 1000)
        T.equal(state.tiles.d.row_id, bottom_id)
        T.equal(state.rows[1].id, top_id)
        T.equal(state.rows[2].id, bottom_id)
        T.equal(#state.rows, 2)
        engine:focus(state, "up")
        T.near(state.viewport.x, 175)
        engine:focus(state, "down")
        T.near(state.viewport.x, 325)
        for _, key in ipairs({ "a", "b", "c" }) do engine:forget_window(key) end
        T.equal(state.tiles.d.row_id, bottom_id)
        T.equal(state.row_views[top_id], nil)
        T.near(state.row_views[bottom_id].x, 325)
        check_geometry(T, engine, state)
    end)

    T.case("window moves transfer row membership and retain destination memory", function()
        local engine, state = fixture()
        local top_id, bottom_id = state.tiles.a.row_id, state.tiles.d.row_id
        engine:pan(state, "right", 100)
        engine:move(state, "down")
        T.equal(state.tiles.a.row_id, bottom_id)
        T.equal(state.tiles.b.row_id, top_id)
        T.near(state.row_views[top_id].x, 100)
        engine:focus(state, "up")
        T.truthy(state.focus_key ~= "a")
        T.near(state.viewport.x, 100)
        check_geometry(T, engine, state)
    end)

    T.case("floating a whole row retains its identity and scroll memory", function()
        local engine, state, descriptors = fixture()
        local id = state.tiles.a.row_id
        engine:pan(state, "right", 250)
        engine:sync("1", { { key = "d", active = true }, { key = "e" }, { key = "f" } }, AREA)
        T.near(state.row_views[id].x, 250)
        engine:sync("1", descriptors, AREA)
        T.equal(state.tiles.a.row_id, id)
        T.near(state.viewport.x, 250)
        check_geometry(T, engine, state)
    end)

    T.case("overview and one-shot fit preserve independent row transforms", function()
        local engine, state = fixture()
        engine:pan(state, "right", 200)
        engine:focus(state, "down")
        engine:pan(state, "right", 450)
        engine:enter_overview(state)
        T.falsy(engine:command(state, "scroll toggle").changed)
        for _, tile in pairs(state.tiles) do
            local box = engine:screen_box(state, tile, AREA)
            T.truthy(box.x >= AREA.x and box.y >= AREA.y)
            T.truthy(box.x + box.w <= AREA.x + AREA.w + 0.001)
            T.truthy(box.y + box.h <= AREA.y + AREA.h + 0.001)
        end
        engine:focus(state, "up")
        engine:leave_overview(state, true)
        T.near(state.viewport.x, 450)
        T.near(engine:screen_box(state, state.tiles.a, AREA).x, AREA.x - 200)
        engine:fit_all(state)
        engine:pan(state, "right", 25)
        T.near(state.viewport.scale, 1)
        T.near(state.viewport.x, 475)
        engine:focus(state, "up")
        T.near(state.viewport.x, 200)
        engine:reset_viewport(state)
        T.near(state.viewport.x, 0)
        engine:focus(state, "down")
        T.near(state.viewport.x, 475)
        check_geometry(T, engine, state)
    end)

    T.case("vertical insertion creates ordered rows and horizontal insertion joins a row", function()
        local engine, state, descriptors = fixture()
        local top_id = state.tiles.a.row_id
        engine:set_insertion(state, "up")
        descriptors[#descriptors + 1] = { key = "above" }
        engine:sync("1", descriptors, AREA)
        T.equal(state.rows[1].id, state.tiles.above.row_id)
        T.equal(state.rows[2].id, top_id)
        engine:set_insertion(state, "right")
        descriptors[#descriptors + 1] = { key = "beside" }
        engine:sync("1", descriptors, AREA)
        T.equal(state.tiles.beside.row_id, top_id)
        T.equal(#state.rows, 3)
        check_geometry(T, engine, state)
    end)

    T.case("horizontal focus follows row membership after vertical resizing", function()
        local engine, state = fixture()
        engine:resize(state, "up", 1000)
        engine:resize(state, "down", -1700)
        T.equal(engine:focus(state, "right"), "b")
        T.equal(engine:focus(state, "left"), "a")
        T.truthy(engine:move(state, "right"))
        T.equal(state.tiles.a.row_id, state.tiles.b.row_id)
        check_geometry(T, engine, state)
    end)

    T.case("mixed row and shared commands preserve geometry across recalculation", function()
        local directions = { "left", "right", "up", "down" }
        for initial_seed = 1, 10 do
            local seed = initial_seed
            local function random(limit)
                seed = seed * 48271 % 2147483647
                return seed % limit + 1
            end
            local engine, state, descriptors = fixture()
            for _ = 1, 150 do
                local direction = directions[random(4)]
                local commands = {
                    "resize " .. direction .. " " .. (random(600) - 300),
                    "move " .. direction,
                    "focus " .. direction,
                    "pan " .. direction .. " 75",
                    "scroll toggle",
                    "fit all",
                    "cycle width forward",
                }
                engine:command(state, commands[random(#commands)])
                for _, descriptor in ipairs(descriptors) do
                    descriptor.active = descriptor.key == state.focus_key
                end
                engine:sync("1", descriptors, AREA)
                check_geometry(T, engine, state)
            end
        end
    end)
end
