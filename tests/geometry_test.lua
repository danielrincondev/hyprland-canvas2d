local Geometry = require("canvas2d.geometry")

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

    T.case("canvas bounds retain negative world coordinates", function()
        local bounds = Geometry.bounds({
            a = { x = -500, y = -200, w = 100, h = 100 },
            b = { x = 250, y = 300, w = 50, h = 75 },
        })
        T.near(bounds.x, -500)
        T.near(bounds.y, -200)
        T.near(bounds.w, 800)
        T.near(bounds.h, 575)
    end)

    T.case("edge candidates include split neighbors", function()
        local neighbors, gap = Geometry.edge_candidates({
            focused = { x = 0, y = 0, w = 100, h = 200 },
            top = { x = 110, y = 0, w = 100, h = 100 },
            bottom = { x = 110, y = 100, w = 100, h = 100 },
            farther = { x = 300, y = 0, w = 100, h = 200 },
        }, "focused", "right")
        T.equal(#neighbors, 2)
        T.equal(neighbors[1], "bottom")
        T.equal(neighbors[2], "top")
        T.near(gap, 10)
    end)
end
