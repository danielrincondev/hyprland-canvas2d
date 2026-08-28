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

    T.case("horizontal focus never falls through to another row", function()
        local tiles = {
            focused = { x = 0, y = 0, w = 100, h = 100 },
            nearly_vertical = { x = 110, y = 300, w = 100, h = 100 },
            balanced = { x = 200, y = 120, w = 100, h = 100 },
            balanced_left = { x = -200, y = 120, w = 100, h = 100 },
        }
        T.equal(Geometry.directional_neighbor(tiles, "focused", "right", { diagonal_weight = 2 }), nil)
        T.equal(Geometry.directional_neighbor(tiles, "focused", "left", { diagonal_weight = 2 }), nil)
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

    T.case("derive_grid keeps fixed cell dimensions as rows grow", function()
        local rows = {
            { height = 440, cells = { { key = "a", width = 500, height = 440 } } },
        }
        local tiles = Geometry.derive_grid(rows, { x = 0, y = 0, w = 1000, h = 800 }, { min_width = 160, min_height = 100 })
        T.near(tiles.a.x, 0)
        T.near(tiles.a.y, 0)
        T.near(tiles.a.w, 500)
        T.near(tiles.a.h, 440)

        rows[1].cells[#rows[1].cells + 1] = { key = "b", width = 500, height = 440 }
        tiles = Geometry.derive_grid(rows, { x = 0, y = 0, w = 1000, h = 800 }, { min_width = 160, min_height = 100 })
        T.near(tiles.a.w, 500)
        T.near(tiles.b.w, 500)
        T.near(tiles.b.x, 500)
    end)

    T.case("derive_grid stacks fixed-height rows without splitting the height", function()
        local rows = {
            { height = 440, cells = { { key = "top", width = 500, height = 440 } } },
            { height = 440, cells = { { key = "bottom", width = 500, height = 440 } } },
        }
        local tiles = Geometry.derive_grid(rows, { x = 0, y = 0, w = 1000, h = 800 }, {})
        T.near(tiles.top.h, 440)
        T.near(tiles.bottom.h, 440)
        T.near(tiles.bottom.y, 440)
    end)

    T.case("aligned cell positions use fixed widths", function()
        local cells = { { key = "a", width = 500 }, { key = "b", width = 500 } }
        T.equal(Geometry.aligned_cell_index(cells, 0, 1000), 1)
        T.equal(Geometry.aligned_cell_index(cells, 990, 1000), 3)
        T.equal(Geometry.aligned_cell_index(cells, 480, 1000), 2)
        T.equal(Geometry.aligned_cell_index({}, 400, 1000), 1)
    end)
end
