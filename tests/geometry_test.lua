local Geometry = require("grid.geometry")

return function(T)
    T.case("spatial focus prefers perpendicular overlap", function()
        local tiles = {
            focused = { x = 0, y = 0, w = 100, h = 100 },
            lane = { x = 130, y = 20, w = 80, h = 60 },
            diagonal = { x = 105, y = 101, w = 80, h = 60 },
        }
        T.equal(Geometry.directional_neighbor(tiles, "focused", "right"), "lane")
    end)

    T.case("spatial focus finds all four directions", function()
        local tiles = {
            center = { x = 0, y = 0, w = 100, h = 100 },
            left = { x = -120, y = 10, w = 100, h = 80 },
            right = { x = 120, y = 10, w = 100, h = 80 },
            up = { x = 10, y = -120, w = 80, h = 100 },
            down = { x = 10, y = 120, w = 80, h = 100 },
        }
        T.equal(Geometry.directional_neighbor(tiles, "center", "left"), "left")
        T.equal(Geometry.directional_neighbor(tiles, "center", "right"), "right")
        T.equal(Geometry.directional_neighbor(tiles, "center", "up"), "up")
        T.equal(Geometry.directional_neighbor(tiles, "center", "down"), "down")
    end)

    T.case("spatial focus uses weighted diagonal fallback", function()
        local tiles = {
            focused = { x = 0, y = 0, w = 100, h = 100 },
            nearly_vertical = { x = 110, y = 300, w = 100, h = 100 },
            balanced = { x = 200, y = 120, w = 100, h = 100 },
        }
        T.equal(Geometry.directional_neighbor(tiles, "focused", "right", { diagonal_weight = 2 }), "balanced")
    end)

    T.case("viewport reveal moves only enough for margin", function()
        local x, y = Geometry.reveal(
            { x = 0, y = 0, w = 300, h = 200 },
            { x = 280, y = 50, w = 100, h = 100 },
            20
        )
        T.near(x, 100)
        T.near(y, 0)
    end)

    T.case("viewport reveal leaves comfortable tile unchanged", function()
        local x, y = Geometry.reveal(
            { x = -50, y = -30, w = 400, h = 300 },
            { x = 20, y = 20, w = 100, h = 100 },
            20
        )
        T.near(x, -50)
        T.near(y, -30)
    end)

    T.case("viewport reveal centers oversized tiles", function()
        local x, y = Geometry.reveal(
            { x = 0, y = 0, w = 200, h = 100 },
            { x = -300, y = -200, w = 500, h = 300 },
            20
        )
        T.near(x, -150)
        T.near(y, -100)
    end)

    T.case("grid bounds retain negative world coordinates", function()
        local bounds = Geometry.bounds({
            a = { x = -500, y = -200, w = 100, h = 100 },
            b = { x = 250, y = 300, w = 50, h = 75 },
        })
        T.near(bounds.x, -500)
        T.near(bounds.y, -200)
        T.near(bounds.w, 800)
        T.near(bounds.h, 575)
    end)
    T.case("distribute splits totals exactly and honors minimums", function()
        local sizes = Geometry.distribute({ 0.5, 0.5 }, 1000, 50)
        T.near(sizes[1] + sizes[2], 1000)
        T.near(sizes[1], 500)

        local pinned = Geometry.distribute({ 0.05, 0.95 }, 1000, 80)
        T.near(pinned[1] + pinned[2], 1000)
        T.near(pinned[1], 80)
        T.truthy(pinned[2] > 800)

        local even = Geometry.distribute({ 0.2, 0.3, 0.4 }, 300, 150)
        T.near(even[1] + even[2] + even[3], 300)
        T.near(even[1], 100)
    end)

    T.case("derive_grid makes the first tile fill the canvas", function()
        local tiles = Geometry.derive_grid(
            { { height = 1, cells = { { key = "a", width = 0.5 } } } },
            { x = 0, y = 0, w = 1000, h = 800 },
            { min_width = 160, min_height = 100 }
        )
        T.near(tiles.a.x, 0)
        T.near(tiles.a.y, 0)
        T.near(tiles.a.w, 1000)
        T.near(tiles.a.h, 800)
    end)

    T.case("derive_grid stacks rows across the full height", function()
        local rows = {
            { height = 1, cells = { { key = "t", width = 0.5 } } },
            { height = 1, cells = { { key = "b", width = 0.5 } } },
        }
        local tiles = Geometry.derive_grid(rows, { x = 0, y = 0, w = 1000, h = 900 }, {})
        T.near(tiles.t.h, 450)
        T.near(tiles.b.h, 450)
        T.near(tiles.b.y, 450)
        T.near(tiles.b.w, 1000)
    end)

    T.case("derive_grid lays out row cells contiguously across the width", function()
        local rows = {
            { height = 1, cells = { { key = "a", width = 0.34 }, { key = "b", width = 0.67 } } },
        }
        local tiles = Geometry.derive_grid(rows, { x = 0, y = 0, w = 1200, h = 800 }, {})
        T.near(tiles.a.x + tiles.a.w, tiles.b.x)
        T.near(tiles.a.x + tiles.a.w + tiles.b.w, 1200)
        T.truthy(tiles.b.w > tiles.a.w)
    end)

    T.case("aligned cell positions minimize distance to a target edge", function()
        local cells = { { key = "a", width = 0.5 }, { key = "b", width = 0.5 } }
        T.equal(Geometry.aligned_cell_index(cells, 0, 1000), 1)
        T.equal(Geometry.aligned_cell_index(cells, 990, 1000), 3)
        T.equal(Geometry.aligned_cell_index(cells, 480, 1000), 2)
        T.equal(Geometry.aligned_cell_index({}, 400, 1000), 1)
    end)
end
