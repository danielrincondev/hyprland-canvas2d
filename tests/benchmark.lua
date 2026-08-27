package.path = "./hypr/?.lua;./hypr/?/init.lua;" .. package.path

local Engine = require("canvas2d.engine")

local area = { x = 0, y = 0, w = 1920, h = 1080 }
local counts = { 10, 25, 50, 100 }
local iterations = 500
local directions = { "left", "up", "right", "down" }

io.write("windows\tinsert_ms\tupdate_us\theap_kib\n")

for _, count in ipairs(counts) do
    collectgarbage("collect")
    local heap_before = collectgarbage("count")
    local engine = Engine.new({ min_width = 50, min_height = 40 })
    local descriptors = {}
    for index = 1, count do
        descriptors[index] = { key = tostring(index), active = index == count }
    end

    local insert_start = os.clock()
    local state = engine:sync("1", descriptors, area)
    local insert_ms = (os.clock() - insert_start) * 1000

    local checksum = 0
    local update_start = os.clock()
    for iteration = 1, iterations do
        local direction = directions[(iteration - 1) % #directions + 1]
        engine:focus(state, direction)
        engine:pan(state, direction, 3)
        for _, tile in pairs(state.tiles) do
            if tile.present ~= false then
                local box = engine:screen_box(state, tile, area)
                checksum = checksum + box.x * 0.0000001 + box.y * 0.00000001
            end
        end
    end
    local update_us = (os.clock() - update_start) * 1000000 / iterations
    local heap_kib = collectgarbage("count") - heap_before

    assert(checksum == checksum)
    local valid, reason = engine:validate(state)
    assert(valid, reason)
    io.write(string.format("%d\t%.3f\t%.3f\t%.1f\n", count, insert_ms, update_us, heap_kib))
end
