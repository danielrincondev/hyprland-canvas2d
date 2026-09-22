local Geometry = require("grid.geometry")

local Engine = {}
Engine.__index = Engine

-- Every tiled target owns an independent world rectangle.  The monitor is only
-- a viewport into that world; it is never used as a packing surface.
local DEFAULTS = {
    layout_name = "grid",
    tile_width_ratio = 0.50,
    tile_height_ratio = 1.00,
    width_presets = { 0.34, 0.50, 0.67, 1.00 },
    -- Compatibility aliases from the earlier configuration API.
    default_width = 0.50,
    default_height = 1.00,
    min_width = 160,
    min_height = 100,
    pan_step = 300,
    resize_step = 60,
    viewport_margin = 0,
    row_gap = 0,
    fit_padding = 32,
    min_fit_scale = 0.10,
    max_fit_scale = 1.00,
    diagonal_weight = 2.00,
    edge_tolerance = 0.001,
    insertion = "auto",
    auto_reveal = true,
    reveal_new = true,
    scroll_mode = "rows",
}

local NUMBER_OPTIONS = {
    tile_width_ratio = { 0.05, 4.00 },
    tile_height_ratio = { 0.05, 4.00 },
    default_width = { 0.000001, 1.00 },
    default_height = { 0.05, 4.00 },
    min_width = { 1, math.huge },
    min_height = { 1, math.huge },
    pan_step = { 0, math.huge },
    resize_step = { 0, math.huge },
    viewport_margin = { 0, math.huge },
    row_gap = { 0, math.huge },
    fit_padding = { 0, math.huge },
    min_fit_scale = { 0.01, 1.00 },
    max_fit_scale = { 0.01, 4.00 },
    diagonal_weight = { 0, math.huge },
    edge_tolerance = { 0, math.huge },
}

local INSERTION_MODES = {
    auto = true,
    left = true,
    right = true,
    up = true,
    down = true,
}
local OVERVIEW_ACTIONS = {
    enter = true,
    exit = true,
    toggle = true,
    activate = true,
    cancel = true,
}

local DIRECTION_ALIASES = {
    l = "left",
    left = "left",
    r = "right",
    right = "right",
    u = "up",
    up = "up",
    d = "down",
    down = "down",
}

local CYCLE_DIRECTIONS = {
    fwd = "forward",
    forward = "forward",
    wider = "forward",
    back = "backward",
    backward = "backward",
    narrower = "backward",
}

local function copy_defaults()
    local config = {}
    for key, value in pairs(DEFAULTS) do
        config[key] = value
    end
    return config
end

local function numeric(value)
    return type(value) == "number" and value == value and value ~= math.huge and value ~= -math.huge
end

local function present(tile)
    return tile and tile.present ~= false
end

local function normalize_direction(direction)
    return type(direction) == "string" and DIRECTION_ALIASES[direction:lower()] or nil
end

local function normalize_cycle(direction)
    return type(direction) == "string" and CYCLE_DIRECTIONS[direction:lower()] or nil
end

local function tokenize(message)
    local tokens = {}
    for token in tostring(message):gmatch("%S+") do
        tokens[#tokens + 1] = token:lower():gsub("_", "-")
    end
    return tokens
end

local function expand_compound_command(tokens)
    local command = tokens[1]
    if not command then
        return tokens
    end

    local simple, direction = command:match("^(focus)%-([a-z]+)$")
    if not simple then
        simple, direction = command:match("^(pan)%-([a-z]+)$")
    end
    if not simple then
        simple, direction = command:match("^(resize)%-([a-z]+)$")
    end
    if not simple then
        simple, direction = command:match("^(swap)%-([a-z]+)$")
    end
    if not simple then
        simple, direction = command:match("^(insert)%-([a-z]+)$")
    end
    if not simple then
        direction = command:match("^move%-window%-([a-z]+)$")
        simple = direction and "move" or nil
    end

    if simple then
        local expanded = { simple, direction }
        for index = 2, #tokens do
            expanded[#expanded + 1] = tokens[index]
        end
        return expanded
    end
    if command == "cycle-width" or command == "cycle-wider" then
        return { "cycle", "width", "forward" }
    end
    if command == "cycle-narrower" then
        return { "cycle", "width", "backward" }
    end
    if command == "cycle-width-forward" or command == "cycle-width-fwd" then
        return { "cycle", "width", "forward" }
    end
    if command == "cycle-width-backward" or command == "cycle-width-back" then
        return { "cycle", "width", "backward" }
    end
    if #tokens == 1 then
        local overview_direction = command:match("^overview%-focus%-([a-z]+)$")
        if overview_direction then
            return { "overview", "focus", overview_direction }
        end
        local overview_action = command:match("^overview%-([a-z]+)$")
        if OVERVIEW_ACTIONS[overview_action] then
            return { "overview", overview_action }
        end
    end
    if #tokens == 1 and command == "center-focused" then
        return { "center", "focused" }
    end
    if #tokens == 1 and command == "fit-all" then
        return { "fit", "all" }
    end
    if #tokens == 1 and command == "reset-viewport" then
        return { "reset", "viewport" }
    end

    return tokens
end

local function normalize_width_presets(value)
    if type(value) ~= "table" or #value < 1 then
        error("grid option width_presets must be a non-empty array of numbers in (0, 1]", 3)
    end
    local presets = {}
    for index, preset in ipairs(value) do
        if type(preset) ~= "number" or preset ~= preset or preset <= 0 or preset > 1 then
            error("grid option width_presets entries must be numbers in (0, 1]", 3)
        end
        presets[index] = preset
    end
    table.sort(presets, function(a, b)
        return a < b
    end)
    return presets
end

local function validate_options(options)
    local config = copy_defaults()
    options = options or {}

    for key, value in pairs(options) do
        if config[key] == nil then
            error("unknown grid option: " .. tostring(key), 3)
        end

        if NUMBER_OPTIONS[key] then
            local range = NUMBER_OPTIONS[key]
            if not numeric(value) or value < range[1] or value > range[2] then
                error(string.format("grid option %s must be a number in [%s, %s]", key, range[1], range[2]), 3)
            end
        elseif key == "layout_name" then
            if type(value) ~= "string" or value == "" or value:find("%s") then
                error("grid option layout_name must be a non-empty name without whitespace", 3)
            end
        elseif key == "insertion" then
            if type(value) ~= "string" or not INSERTION_MODES[value] then
                error("grid option insertion must be auto, left, right, up, or down", 3)
            end
        elseif key == "scroll_mode" then
            if value ~= "rows" and value ~= "shared" then
                error("grid option scroll_mode must be rows or shared", 3)
            end
        elseif key == "auto_reveal" or key == "reveal_new" then
            if type(value) ~= "boolean" then
                error("grid option " .. key .. " must be boolean", 3)
            end
        end

        config[key] = value
    end

    -- Keep both names usable.  The explicit old names win when both aliases
    -- are supplied, so a configuration cannot silently use the wrong ratio.
    if options.tile_width_ratio ~= nil then
        config.default_width = config.tile_width_ratio
    else
        config.tile_width_ratio = config.default_width
    end
    if options.tile_height_ratio ~= nil then
        config.default_height = config.tile_height_ratio
    else
        config.tile_height_ratio = config.default_height
    end

    config.width_presets = normalize_width_presets(config.width_presets)

    if config.min_fit_scale > config.max_fit_scale then
        error("grid min_fit_scale must not exceed max_fit_scale", 3)
    end

    return config
end

function Engine.new(options)
    return setmetatable({
        config = validate_options(options),
        workspaces = {},
    }, Engine)
end

function Engine:workspace(workspace_id, area)
    local id = tostring(workspace_id)
    local state = self.workspaces[id]

    if not state then
        state = {
            id = id,
            viewport = {
                x = 0,
                y = 0,
                width = area and math.max(1, area.w) or 1,
                height = area and math.max(1, area.h) or 1,
                scale = 1,
            },
            tiles = {},
            rows = {},
            row_views = {},
            row_order = {},
            next_row_id = 0,
            active_row_id = nil,
            scroll_mode = self.config.scroll_mode,
            fitted = false,
            order = {},
            focus_key = nil,
            suppress_reveal_once = false,
            overview = {
                active = false,
                saved_viewport = nil,
                saved_focus_key = nil,
            },
            insertion = self.config.insertion,
        }
        self.workspaces[id] = state
    end

    if area then
        state.viewport.width = math.max(1, area.w)
        state.viewport.height = math.max(1, area.h)
    end

    return state
end

function Engine:last_present_key(state)
    for index = #state.order, 1, -1 do
        local key = state.order[index]
        if present(state.tiles[key]) then
            return key
        end
    end
    return nil
end

function Engine:_structural_last_key(state)
    return self:last_present_key(state)
end

function Engine:_anchor_location(state)
    if state.empty_row and state.empty_row.selected then return nil end
    if state.focus_key and present(state.tiles[state.focus_key]) then
        return {
            key = state.focus_key,
            tile = state.tiles[state.focus_key],
        }
    end

    local key = self:last_present_key(state)
    return key and { key = key, tile = state.tiles[key] } or nil
end

function Engine:present_count(state)
    local count = 0
    for _, tile in pairs(state.tiles) do
        if present(tile) then
            count = count + 1
        end
    end
    return count
end

local function new_row_id(state, anchor_id, direction)
    state.next_row_id = state.next_row_id + 1
    local id = state.next_row_id
    state.row_views[id] = { x = 0, focus_key = nil }
    local position = #state.row_order + 1
    for index, row_id in ipairs(state.row_order) do
        if row_id == anchor_id then
            position = index + (direction == "up" and 0 or 1)
            break
        end
    end
    table.insert(state.row_order, position, id)
    return id
end

local function rebuild_rows(state, epsilon)
    local entries = {}
    for key, tile in pairs(state.tiles) do
        if present(tile) then
            entries[#entries + 1] = { key = key, tile = tile }
        end
    end

    table.sort(entries, function(a, b)
        if a.tile.y == b.tile.y then
            if a.tile.x == b.tile.x then
                return tostring(a.key) < tostring(b.key)
            end
            return a.tile.x < b.tile.x
        end
        return a.tile.y < b.tile.y
    end)

    local rows, by_id = {}, {}
    for _, entry in ipairs(entries) do
        local tile = entry.tile
        -- Public set_tile callers can seed a row by its top edge. Normal
        -- insertion and movement assign explicit membership before this point.
        if not tile.row_id then
            local previous = rows[#rows]
            if previous and math.abs(previous.y - tile.y) <= epsilon then
                tile.row_id = previous.id
            else
                local next_id
                for _, existing in ipairs(state.rows) do
                    if existing.y > tile.y then
                        next_id = existing.id
                        break
                    end
                end
                tile.row_id = new_row_id(state, next_id, "up")
            end
        end
        local row = by_id[tile.row_id]
        if not row then
            row = { id = tile.row_id, y = tile.y, height = tile.h, cells = {} }
            rows[#rows + 1] = row
            by_id[row.id] = row
        else
            row.height = math.max(row.height, Geometry.bottom(tile) - row.y)
        end
        row.cells[#row.cells + 1] = {
            key = entry.key,
            width = entry.tile.w,
            height = entry.tile.h,
        }
    end
    for _, row in ipairs(rows) do
        table.sort(row.cells, function(a, b)
            local ax, bx = state.tiles[a.key].x, state.tiles[b.key].x
            return ax == bx and tostring(a.key) < tostring(b.key) or ax < bx
        end)
    end
    if state.scroll_mode == "rows" then
        local positions = {}
        for index, id in ipairs(state.row_order) do
            positions[id] = index
        end
        table.sort(rows, function(a, b) return positions[a.id] < positions[b.id] end)
    end
    state.rows = rows

    local retained = {}
    for _, tile in pairs(state.tiles) do
        if tile.row_id then
            retained[tile.row_id] = true
        end
    end
    for id in pairs(state.row_views) do
        if not retained[id] then
            state.row_views[id] = nil
        end
    end
    for index = #state.row_order, 1, -1 do
        if not retained[state.row_order[index]] then
            table.remove(state.row_order, index)
        end
    end
end

function Engine:_materialize(state)
    rebuild_rows(state, self.config.edge_tolerance)
    if state.scroll_mode == "rows" or self.config.row_gap > 0 then
        -- Independently translated rows need disjoint vertical bounds even
        -- when height resizing has left their members staggered.
        local bottom
        for _, row in ipairs(state.rows) do
            if bottom and row.y < bottom then
                local shift = bottom - row.y
                for _, cell in ipairs(row.cells) do
                    state.tiles[cell.key].y = state.tiles[cell.key].y + shift
                end
                row.y = bottom
            end
            bottom = row.y + row.height + self.config.row_gap
        end
    end
    return state.tiles
end

function Engine:_save_row_view(state)
    if state.empty_row and state.empty_row.selected then
        state.empty_row.x = state.viewport.x
        return
    end
    local view = state.row_views[state.active_row_id]
    if view and state.scroll_mode == "rows" and not state.overview.active and not state.fitted then
        view.x = state.viewport.x
    end
end

function Engine:_activate_row(state, key)
    local tile = state.tiles[key]
    if not present(tile) or state.overview.active or state.fitted then
        return false
    end
    local changed = state.active_row_id ~= tile.row_id
    if changed then
        self:_save_row_view(state)
        state.active_row_id = tile.row_id
        if state.scroll_mode == "rows" then
            state.viewport.x = state.row_views[tile.row_id].x
        end
    end
    if state.scroll_mode == "rows" then
        state.row_views[tile.row_id].focus_key = key
    end
    return changed
end

function Engine:set_scroll_mode(state, mode)
    if mode == "toggle" then
        mode = state.scroll_mode == "rows" and "shared" or "rows"
    end
    if mode ~= "rows" and mode ~= "shared" then
        return nil, "grid: scroll expects rows, shared, or toggle"
    end
    if state.overview.active or mode == state.scroll_mode then
        return false
    end
    self:_resume_rows(state)
    self:_save_row_view(state)
    state.scroll_mode = mode
    state.fitted = false
    state.viewport.scale = 1
    self:_materialize(state)
    local tile = state.tiles[state.focus_key]
    state.active_row_id = tile and tile.row_id or nil
    if mode == "rows" then
        local view = state.row_views[state.active_row_id]
        state.viewport.x = view and view.x or 0
    end
    return true
end


local function remove_from_order(order, key)
    for index = #order, 1, -1 do
        if order[index] == key then
            table.remove(order, index)
            return
        end
    end
end

local function make_rect(key, x, y, width, height)
    return {
        key = tostring(key),
        x = x,
        y = y,
        w = width,
        h = height,
        present = true,
    }
end

function Engine:_default_size(state)
    local width = math.max(1, state.viewport.width)
    local height = math.max(1, state.viewport.height)
    return math.max(self.config.min_width, width * self.config.tile_width_ratio),
        math.max(self.config.min_height, height * self.config.tile_height_ratio)
end

-- Push existing rectangles away from a fixed candidate.  This is the key
-- scrolling invariant: collisions translate windows; they never resize them.
function Engine:_push_collisions(state, candidate, direction)
    local ordered = {}
    local epsilon = self.config.edge_tolerance

    for key, tile in pairs(state.tiles) do
        if present(tile) and tile ~= candidate then
            ordered[#ordered + 1] = { key = key, tile = tile }
        end
    end

    table.sort(ordered, function(a, b)
        if direction == "right" then
            if a.tile.x == b.tile.x then
                return tostring(a.key) < tostring(b.key)
            end
            return a.tile.x < b.tile.x
        elseif direction == "left" then
            local ar = Geometry.right(a.tile)
            local br = Geometry.right(b.tile)
            if ar == br then
                return tostring(a.key) < tostring(b.key)
            end
            return ar > br
        elseif direction == "down" then
            if a.tile.y == b.tile.y then
                return tostring(a.key) < tostring(b.key)
            end
            return a.tile.y < b.tile.y
        else
            local ab = Geometry.bottom(a.tile)
            local bb = Geometry.bottom(b.tile)
            if ab == bb then
                return tostring(a.key) < tostring(b.key)
            end
            return ab > bb
        end
    end)

    local blockers = { candidate }
    for _, entry in ipairs(ordered) do
        local tile = entry.tile

        -- A tile can collide with a blocker after it has already moved away
        -- from a different blocker.  Recompute until it clears every blocker
        -- so collision propagation cannot create a new overlap in its wake.
        while true do
            local shift = 0
            for _, blocker in ipairs(blockers) do
                if Geometry.intersects(tile, blocker, epsilon) then
                    if direction == "right" then
                        shift = math.max(shift, Geometry.right(blocker) - tile.x)
                    elseif direction == "left" then
                        shift = math.max(shift, Geometry.right(tile) - blocker.x)
                    elseif direction == "down" then
                        shift = math.max(shift, Geometry.bottom(blocker) - tile.y)
                    else
                        shift = math.max(shift, Geometry.bottom(tile) - blocker.y)
                    end
                end
            end

            if shift <= epsilon then
                break
            end
            if direction == "right" then
                tile.x = tile.x + shift
            elseif direction == "left" then
                tile.x = tile.x - shift
            elseif direction == "down" then
                tile.y = tile.y + shift
            else
                tile.y = tile.y - shift
            end
        end

        blockers[#blockers + 1] = tile
    end
end

function Engine:_auto_insertion_rect(state, anchor, width, height)
    if not anchor then
        return make_rect("candidate", 0, 0, width, height), "right"
    end

    -- Automatic insertion follows the scroll layout horizontally without a
    -- viewport-relative packing limit.  Explicit vertical insertion and
    -- movement remain the ways to create additional rows.
    return make_rect("candidate", Geometry.right(anchor), anchor.y, width, height), "right"
end

local function directional_insertion_rect(anchor, direction, width, height, row_gap)
    if direction == "left" then
        return make_rect("candidate", anchor.x - width, anchor.y, width, height)
    elseif direction == "right" then
        return make_rect("candidate", Geometry.right(anchor), anchor.y, width, height)
    elseif direction == "up" then
        return make_rect("candidate", anchor.x, anchor.y - height - row_gap, width, height)
    else
        return make_rect("candidate", anchor.x, Geometry.bottom(anchor) + row_gap, width, height)
    end
end

function Engine:_insert_new(state, key)
    if state.empty_row and state.empty_row.selected then
        local empty = state.empty_row
        local width, height = self:_default_size(state)
        local rect = make_rect(tostring(key), empty.x or 0, empty.y, width, height)
        rect.row_id = new_row_id(state)
        state.empty_row = nil
        state.tiles[rect.key] = rect
        state.order[#state.order + 1] = rect.key
        state.focus_key = rect.key
        self:_materialize(state)
        return rect.key
    end
    if self:present_count(state) == 0 then
        -- A workspace with no live tiles has no meaningful viewport position.
        -- Start its next first tile at the world origin.
        state.viewport.x = 0
        state.viewport.y = 0
        state.suppress_reveal_once = false
    end
    local width, height = self:_default_size(state)
    local anchor = self:_anchor_location(state)
    local rect
    local push_direction
    local mode = state.insertion == "auto" and "auto" or state.insertion

    if mode == "auto" then
        rect, push_direction = self:_auto_insertion_rect(state, anchor and anchor.tile, width, height)
    elseif anchor then
        rect = directional_insertion_rect(anchor.tile, mode, width, height, self.config.row_gap)
        push_direction = mode
    else
        rect = make_rect("candidate", 0, 0, width, height)
        push_direction = "right"
    end

    rect.key = tostring(key)
    rect.row_id = anchor and (mode == "auto" or mode == "left" or mode == "right")
        and anchor.tile.row_id or new_row_id(state, anchor and anchor.tile.row_id, mode)
    state.tiles[rect.key] = rect
    state.order[#state.order + 1] = rect.key
    if state.scroll_mode == "rows" then
        self:_materialize(state)
    end
    self:_push_collisions(state, rect, push_direction)
    state.focus_key = rect.key
    return rect.key
end

local function lane_contains(tile, source, direction, epsilon)
    if direction == "left" or direction == "right" then
        return Geometry.overlap_1d(source.y, Geometry.bottom(source), tile.y, Geometry.bottom(tile)) > epsilon
    end
    return Geometry.overlap_1d(source.x, Geometry.right(source), tile.x, Geometry.right(tile)) > epsilon
end

local function sort_lane(entries, direction)
    table.sort(entries, function(a, b)
        local a_primary = (direction == "left" or direction == "right") and a.tile.x or a.tile.y
        local b_primary = (direction == "left" or direction == "right") and b.tile.x or b.tile.y
        if a_primary == b_primary then
            return tostring(a.key) < tostring(b.key)
        end
        return a_primary < b_primary
    end)
end

local function compact_horizontal_gap(state, removed, epsilon)
    for _, tile in pairs(state.tiles) do
        if present(tile) and tile ~= removed then
            local same_band = state.scroll_mode == "rows" and tile.row_id == removed.row_id
                or state.scroll_mode == "shared" and Geometry.overlap_1d(
                removed.y,
                Geometry.bottom(removed),
                tile.y,
                Geometry.bottom(tile)
            ) > epsilon
            if same_band and tile.x >= Geometry.right(removed) - epsilon then
                tile.x = tile.x - removed.w
            end
        end
    end
end

local function adjacent_row(state, source, direction, epsilon)
    rebuild_rows(state, epsilon)

    local source_index
    for index, row in ipairs(state.rows) do
        for _, cell in ipairs(row.cells) do
            if cell.key == source.key then
                source_index = index
                break
            end
        end
        if source_index then
            break
        end
    end
    if not source_index then
        return nil
    end

    local offset = direction == "down" and 1 or -1
    return state.rows[source_index + offset]
end
local function horizontal_band_entries(state, source, epsilon)
    local entries = {}
    for key, tile in pairs(state.tiles) do
        if present(tile)
            and (state.scroll_mode == "rows" and tile.row_id == source.row_id
            or state.scroll_mode == "shared" and Geometry.overlap_1d(
                source.y,
                Geometry.bottom(source),
                tile.y,
                Geometry.bottom(tile)
            ) > epsilon)
        then
            entries[#entries + 1] = { key = key, tile = tile }
        end
    end

    sort_lane(entries, "right")
    if #entries == 0 then
        return entries, nil, nil
    end

    return entries, entries[1].tile.x, Geometry.right(entries[#entries].tile)
end


local function reflow_horizontal_band(entries, edge, anchor)
    if #entries == 0 then
        return
    end

    if edge == "left" then
        local cursor = anchor
        for _, entry in ipairs(entries) do
            entry.tile.x = cursor
            cursor = cursor + entry.tile.w
        end
    else
        local cursor = anchor
        for index = #entries, 1, -1 do
            local tile = entries[index].tile
            tile.x = cursor - tile.w
            cursor = tile.x
        end
    end
end

local function horizontal_row_neighbor(state, source, direction, epsilon)
    local entries = horizontal_band_entries(state, source, epsilon)
    for index, entry in ipairs(entries) do
        if entry.tile == source then
            local neighbor = entries[index + (direction == "right" and 1 or -1)]
            return neighbor and neighbor.key or nil
        end
    end
end


-- Reorder the lane rather than swapping rectangle dimensions.  With equal
-- sizes this is the familiar one-slot swap; with unequal sizes it keeps every
-- window's own width/height and closes only the moved lane's gap.
function Engine:_swap_lane_positions(state, source_key, neighbor_key, direction)
    local source = state.tiles[source_key]
    local neighbor = state.tiles[neighbor_key]
    local epsilon = self.config.edge_tolerance
    local lane = state.scroll_mode == "rows" and horizontal_band_entries(state, source, epsilon) or {
        { key = source_key, tile = source },
        { key = neighbor_key, tile = neighbor },
    }

    if state.scroll_mode == "shared" and not lane_contains(neighbor, source, direction, epsilon) then
        local source_x, source_y = source.x, source.y
        source.x, source.y = neighbor.x, neighbor.y
        neighbor.x, neighbor.y = source_x, source_y
        self:_push_collisions(state, source, direction)
        return
    end

    -- Include the whole connected lane.  A resize can leave staggered
    -- perpendicular intervals, so checking only the source interval would
    -- let a reflowed tile collide with a later member of the same lane.
    local changed = state.scroll_mode == "shared"
    while changed do
        changed = false
        for key, tile in pairs(state.tiles) do
            if present(tile) then
                local in_lane = false
                for _, entry in ipairs(lane) do
                    if entry.tile == tile then
                        in_lane = true
                        break
                    end
                    if lane_contains(tile, entry.tile, direction, epsilon) then
                        in_lane = true
                        break
                    end
                end
                if in_lane then
                    local known = false
                    for _, entry in ipairs(lane) do
                        if entry.tile == tile then
                            known = true
                            break
                        end
                    end
                    if not known then
                        lane[#lane + 1] = { key = key, tile = tile }
                        changed = true
                    end
                end
            end
        end
    end

    sort_lane(lane, direction)

    local source_index
    local neighbor_index
    local start
    for index, entry in ipairs(lane) do
        local position = (direction == "left" or direction == "right") and entry.tile.x or entry.tile.y
        start = start and math.min(start, position) or position
        if entry.key == source_key then
            source_index = index
        elseif entry.key == neighbor_key then
            neighbor_index = index
        end
    end
    if not source_index or not neighbor_index then
        return
    end

    lane[source_index], lane[neighbor_index] = lane[neighbor_index], lane[source_index]

    local cursor = start
    for _, entry in ipairs(lane) do
        if direction == "left" or direction == "right" then
            entry.tile.x = cursor
            cursor = cursor + entry.tile.w
        else
            entry.tile.y = cursor
            cursor = cursor + entry.tile.h
        end
    end
end

function Engine:move(state, direction)
    local anchor = self:_anchor_location(state)
    if not anchor or not Geometry.valid_direction(direction) then
        return false
    end

    if direction == "up" or direction == "down" then
        local tile = anchor.tile
        local epsilon = self.config.edge_tolerance
        local destination_row = adjacent_row(state, tile, direction, epsilon)
        local bounds = Geometry.bounds(state.tiles)
        local row_start = bounds and bounds.x or 0

        -- A vertical move transfers the focused rectangle between rows
        -- instead of swapping it with a diagonal neighbor.  Remove its old
        -- horizontal slot before appending it to the destination row.
        compact_horizontal_gap(state, tile, epsilon)

        if destination_row then
            tile.row_id = destination_row.id
            local destination_x
            for _, cell in ipairs(destination_row.cells) do
                local candidate = state.tiles[cell.key]
                if present(candidate) then
                    destination_x = destination_x
                        and math.max(destination_x, Geometry.right(candidate))
                        or Geometry.right(candidate)
                end
            end
            tile.x = destination_x or row_start
            tile.y = destination_row.y
        else
            tile.row_id = new_row_id(state, tile.row_id, direction)
            tile.x = row_start
            if direction == "down" then
                tile.y = Geometry.bottom(tile) + self.config.row_gap
            else
                tile.y = tile.y - tile.h - self.config.row_gap
            end
        end

        self:_push_collisions(state, tile, direction)
        state.focus_key = anchor.key
        self:_materialize(state)
        self:reveal(state, anchor.key)
        return true
    end

    local neighbor
    if state.scroll_mode == "rows" then
        neighbor = horizontal_row_neighbor(state, anchor.tile, direction, self.config.edge_tolerance)
    else
        neighbor = Geometry.directional_neighbor(state.tiles, anchor.key, direction, {
            epsilon = self.config.edge_tolerance,
            diagonal_weight = self.config.diagonal_weight,
        })
    end
    if not neighbor then
        return false
    end

    self:_swap_lane_positions(state, anchor.key, neighbor, direction)
    state.focus_key = anchor.key
    self:_materialize(state)
    self:reveal(state, anchor.key)
    return true
end

local function nearest_preset(presets, ratio)
    local index = 1
    for position, preset in ipairs(presets) do
        if math.abs(preset - ratio) < math.abs(presets[index] - ratio) then
            index = position
        end
    end
    return index
end

function Engine:cycle_width(state, direction)
    local anchor = self:_anchor_location(state)
    if not anchor or (direction ~= "forward" and direction ~= "backward") then
        return false
    end

    local tile = anchor.tile
    local presets = self.config.width_presets
    local index = nearest_preset(presets, tile.w / math.max(1, state.viewport.width))
    local next_index = index + (direction == "forward" and 1 or -1)
    if next_index < 1 then
        next_index = #presets
    elseif next_index > #presets then
        next_index = 1
    end

    local new_width = math.max(self.config.min_width, state.viewport.width * presets[next_index])
    if math.abs(new_width - tile.w) <= self.config.edge_tolerance then
        return false
    end

    local entries, row_start = horizontal_band_entries(state, tile, self.config.edge_tolerance)
    tile.w = new_width

    -- Width cycles are row-local: keep the row's left edge and close the
    -- row from left to right without consulting any other row.
    reflow_horizontal_band(entries, "left", row_start)
    -- Reflow can push a tall member into a staggered tile outside the
    -- focused tile's band. Resolve those collisions as well.
    self:_push_collisions(state, tile, "right")
    self:_materialize(state)
    return true
end

function Engine:_resize_tile(state, key, direction, amount)
    local tile = state.tiles[key]
    if not present(tile) or not Geometry.valid_direction(direction) or not numeric(amount) or amount == 0 then
        return false
    end

    local delta = math.abs(amount)
    local growing = amount > 0
    local horizontal = direction == "left" or direction == "right"
    local old_width = tile.w
    local old_height = tile.h
    local entries
    local row_start
    local row_end

    if horizontal then
        entries, row_start, row_end = horizontal_band_entries(state, tile, self.config.edge_tolerance)
        if direction == "right" then
            tile.w = growing and tile.w + delta or math.max(self.config.min_width, tile.w - delta)
        elseif growing then
            tile.x = tile.x - delta
            tile.w = tile.w + delta
        else
            local shrink = math.min(delta, math.max(0, tile.w - self.config.min_width))
            tile.x = tile.x + shrink
            tile.w = tile.w - shrink
        end
    elseif direction == "down" then
        tile.h = growing and tile.h + delta or math.max(self.config.min_height, tile.h - delta)
    elseif growing then
        tile.y = tile.y - delta
        tile.h = tile.h + delta
    else
        local shrink = math.min(delta, math.max(0, tile.h - self.config.min_height))
        tile.y = tile.y + shrink
        tile.h = tile.h - shrink
    end

    if horizontal then
        local edge = direction == "right" and "left" or "right"
        reflow_horizontal_band(entries, edge, edge == "left" and row_start or row_end)
        self:_push_collisions(state, tile, direction)
    elseif growing then
        self:_push_collisions(state, tile, direction)
    end
    self:_materialize(state)
    return tile.w ~= old_width or tile.h ~= old_height
end

-- Kept as a compatibility name for callers of the old row-resize API.  Rows
-- no longer own height; only the focused rectangle changes height.
function Engine:resize_rows(state, direction, amount)
    local anchor = self:_anchor_location(state)
    return anchor and self:_resize_tile(state, anchor.key, direction, amount) or false
end

function Engine:resize(state, direction, amount)
    local anchor = self:_anchor_location(state)
    if not anchor then
        return false
    end
    return self:_resize_tile(state, anchor.key, direction, amount)
end

function Engine:world_viewport(state)
    local scale = state.viewport.scale
    return {
        x = state.viewport.x,
        y = state.viewport.y,
        w = state.viewport.width / scale,
        h = state.viewport.height / scale,
    }
end

function Engine:screen_box(state, tile, area)
    local scale = state.viewport.scale
    local x = state.viewport.x
    if state.scroll_mode == "rows" and not state.overview.active and not state.fitted then
        local view = state.row_views[tile.row_id]
        x = tile.row_id == state.active_row_id and state.viewport.x or (view and view.x or 0)
    end
    return {
        x = area.x + (tile.x - x) * scale,
        y = area.y + (tile.y - state.viewport.y) * scale,
        w = tile.w * scale,
        h = tile.h * scale,
    }
end

function Engine:pan(state, direction, amount)
    if state.overview.active then
        return false
    end
    amount = amount or self.config.pan_step
    if not numeric(amount) then
        return false
    end
    self:_resume_rows(state)
    self:_activate_row(state, state.focus_key)
    if direction == "left" then
        state.viewport.x = state.viewport.x - amount
    elseif direction == "right" then
        state.viewport.x = state.viewport.x + amount
    elseif direction == "up" then
        state.viewport.y = state.viewport.y - amount
    elseif direction == "down" then
        state.viewport.y = state.viewport.y + amount
    else
        return false
    end
    self:_save_row_view(state)
    return amount ~= 0
end

function Engine:_resume_rows(state)
    if state.scroll_mode == "rows" and state.fitted and not state.overview.active then
        state.fitted = false
        state.viewport.scale = 1
        local view = state.row_views[state.active_row_id]
        state.viewport.x = view and view.x or 0
    end
end

function Engine:_reveal_vertical(state, key)
    if state.overview.active or not present(state.tiles[key]) then
        return false
    end
    self:_resume_rows(state)
    self:_activate_row(state, key)
    local _, y = Geometry.reveal(self:world_viewport(state), state.tiles[key], 0)
    local changed = y ~= state.viewport.y
    state.viewport.y = y
    return changed
end

function Engine:reveal(state, key)
    if state.overview.active then
        return false
    end
    local tile = state.tiles[key]
    if not present(tile) then
        return false
    end
    self:_resume_rows(state)
    self:_activate_row(state, key)
    if state.suppress_reveal_once then
        state.suppress_reveal_once = false
        return false
    end

    local margin = self.config.viewport_margin / state.viewport.scale
    local epsilon = self.config.edge_tolerance
    local _, row_start = horizontal_band_entries(state, tile, epsilon)
    -- Never place a row's left edge behind an artificial reveal margin.
    -- Hyprland supplies the outer gap; the navigation margin is only useful
    -- between a row's windows.
    if row_start and math.abs(tile.x - row_start) <= epsilon then
        state.viewport.x = tile.x
        margin = 0
    end
    local viewport = self:world_viewport(state)
    local x, y = Geometry.reveal(viewport, tile, margin)
    local changed = x ~= state.viewport.x or y ~= state.viewport.y
    state.viewport.x = x
    state.viewport.y = y
    self:_save_row_view(state)
    return changed
end

function Engine:center(state, key)
    if state.overview.active then
        return false
    end
    local tile = state.tiles[key]
    if not present(tile) then
        return false
    end
    self:_resume_rows(state)
    self:_activate_row(state, key)

    local viewport = self:world_viewport(state)
    local x = tile.x + tile.w / 2 - viewport.w / 2
    local y = tile.y + tile.h / 2 - viewport.h / 2
    local changed = x ~= state.viewport.x or y ~= state.viewport.y
    state.viewport.x = x
    state.viewport.y = y
    self:_save_row_view(state)
    return changed
end

function Engine:fit_all(state)
    local bounds = Geometry.bounds(state.tiles)
    if not bounds then
        return false
    end
    self:_save_row_view(state)
    state.fitted = true

    local width = math.max(1, state.viewport.width - 2 * self.config.fit_padding)
    local height = math.max(1, state.viewport.height - 2 * self.config.fit_padding)
    local scale_x = bounds.w > 0 and width / bounds.w or self.config.max_fit_scale
    local scale_y = bounds.h > 0 and height / bounds.h or self.config.max_fit_scale
    local scale = math.min(self.config.max_fit_scale, scale_x, scale_y)
    if not state.overview.active then
        scale = math.max(self.config.min_fit_scale, scale)
    end
    local changed = scale ~= state.viewport.scale
    state.viewport.scale = scale

    local viewport = self:world_viewport(state)
    local x = bounds.x + bounds.w / 2 - viewport.w / 2
    local y = bounds.y + bounds.h / 2 - viewport.h / 2
    changed = changed or x ~= state.viewport.x or y ~= state.viewport.y
    state.viewport.x = x
    state.viewport.y = y
    return changed
end

function Engine:reset_viewport(state)
    if state.overview.active then
        return false
    end
    self:_resume_rows(state)
    self:_activate_row(state, state.focus_key)
    local changed = state.viewport.x ~= 0 or state.viewport.y ~= 0 or state.viewport.scale ~= 1
    state.viewport.x = 0
    state.viewport.y = 0
    state.viewport.scale = 1
    state.fitted = false
    self:_save_row_view(state)
    return changed
end

function Engine:enter_overview(state)
    local overview = state.overview
    if overview.active then
        return false
    end
    self:_save_row_view(state)
    overview.saved_row_id = state.active_row_id
    overview.saved_fitted = state.fitted

    overview.saved_viewport = {
        x = state.viewport.x,
        y = state.viewport.y,
        scale = state.viewport.scale,
    }
    overview.saved_focus_key = state.focus_key
    overview.active = true
    self:fit_all(state)
    return true
end

function Engine:leave_overview(state, cancel)
    local overview = state.overview
    if not overview.active then
        return false
    end

    local focus_key = state.focus_key
    if cancel and present(state.tiles[overview.saved_focus_key]) then
        focus_key = overview.saved_focus_key
    end

    local saved_viewport = overview.saved_viewport
    overview.active = false
    state.active_row_id = overview.saved_row_id
    state.fitted = overview.saved_fitted
    overview.saved_row_id = nil
    overview.saved_fitted = nil
    overview.saved_viewport = nil
    overview.saved_focus_key = nil
    state.focus_key = focus_key

    if saved_viewport then
        state.viewport.x = saved_viewport.x
        state.viewport.y = saved_viewport.y
        state.viewport.scale = saved_viewport.scale
    end
    if not cancel and focus_key then
        self:reveal(state, focus_key)
    end

    return true, focus_key
end

function Engine:select_empty_row(state)
    if not state.empty_row then return false end
    self:_save_row_view(state)
    state.empty_row.selected = true
    state.focus_key, state.active_row_id = nil, nil
    state.fitted = false
    state.viewport.scale = 1
    state.viewport.x = state.empty_row.x or 0
    state.viewport.y = state.empty_row.y
    return true
end

function Engine:focus(state, direction)
    if state.empty_row and state.empty_row.selected then
        if direction ~= "up" then return nil end
        local row = state.rows[#state.rows]
        if not row then return nil end
        self:_save_row_view(state)
        state.empty_row.selected = false
        local view = state.row_views[row.id]
        local key = view.focus_key
        if not present(state.tiles[key]) or state.tiles[key].row_id ~= row.id then key = row.cells[1].key end
        state.focus_key = key
        self:_activate_row(state, key)
        self:_reveal_vertical(state, key)
        return key
    end
    local anchor = self:_anchor_location(state)
    if not anchor or not Geometry.valid_direction(direction) then
        return nil
    end
    if state.scroll_mode == "rows" and not state.overview.active then
        self:_resume_rows(state)
        self:_activate_row(state, anchor.key)
        if direction == "up" or direction == "down" then
            local row = adjacent_row(state, anchor.tile, direction, self.config.edge_tolerance)
            if not row then
                if direction == "down" then self:select_empty_row(state) end
                return nil
            end
            local view = state.row_views[row.id]
            local key = view.focus_key
            if not present(state.tiles[key]) or state.tiles[key].row_id ~= row.id then
                local center = anchor.tile.x + anchor.tile.w / 2 - state.viewport.x
                local distance = math.huge
                for _, cell in ipairs(row.cells) do
                    local tile = state.tiles[cell.key]
                    local delta = math.abs(tile.x + tile.w / 2 - view.x - center)
                    if delta < distance then
                        key, distance = cell.key, delta
                    end
                end
            end
            state.focus_key = key
            self:_activate_row(state, key)
            -- Vertical navigation restores the exact horizontal position,
            -- including intentional panning away from the focused window.
            self:_reveal_vertical(state, key)
            return key
        end
        local key = horizontal_row_neighbor(state, anchor.tile, direction, self.config.edge_tolerance)
        if key then
            state.focus_key = key
            self:reveal(state, key)
        end
        return key
    end

    local next_key = Geometry.directional_neighbor(state.tiles, anchor.key, direction, {
        epsilon = self.config.edge_tolerance,
        diagonal_weight = self.config.diagonal_weight,
    })
    if not next_key then
        if direction == "down" then self:select_empty_row(state) end
        return nil
    end

    state.focus_key = next_key
    self:reveal(state, next_key)
    return next_key
end

function Engine:sync(workspace_id, descriptors, area)
    local state = self:workspace(workspace_id, area)
    local active_key
    local newly_added = {}
    local previously_present = {}

    -- A target missing from a recalculate context may be floating temporarily.
    -- Keep its rectangle until the close/move lifecycle callback removes it.
    for key, tile in pairs(state.tiles) do
        previously_present[key] = present(tile)
        tile.present = false
    end

    for _, descriptor in ipairs(descriptors) do
        local key = tostring(descriptor.key)
        if state.tiles[key] then
            state.tiles[key].present = true
        end
        if descriptor.active then
            active_key = key
        end
    end

    -- Parked rectangles may have had their old space occupied while absent.
    -- Restore them in stable insertion order, preserving their saved boxes
    -- and translating collisions before inserting any new targets.
    for _, key in ipairs(state.order) do
        local tile = state.tiles[key]
        if present(tile) and not previously_present[key] then
            self:_push_collisions(state, tile, "right")
        end
    end

    for _, descriptor in ipairs(descriptors) do
        local key = tostring(descriptor.key)
        if not state.tiles[key] then
            self:_insert_new(state, key)
            newly_added[key] = true
        end
    end

    if state.empty_row and state.empty_row.selected then
        state.focus_key = nil
    elseif active_key and present(state.tiles[active_key]) then
        state.focus_key = active_key
    elseif not present(state.tiles[state.focus_key or "\0"]) then
        state.focus_key = self:last_present_key(state)
    end

    self:_materialize(state)

    self:_activate_row(state, state.focus_key)
    if state.overview.active then
        self:fit_all(state)
    elseif self.config.reveal_new and active_key and newly_added[active_key] then
        self:reveal(state, active_key)
    end

    return state, newly_added
end

function Engine:command(state, message)
    local tokens = expand_compound_command(tokenize(message))
    local command = tokens[1]

    if not command then
        return nil, "grid: empty layout message"
    end
    if command == "scroll" or command == "scroll-mode" then
        local changed, reason = self:set_scroll_mode(state, tokens[2] or "toggle")
        if changed == nil then
            return nil, reason
        end
        return { changed = changed }
    end
    if command == "overview" then
        local action = tokens[2] or "toggle"
        if action == "focus" then
            local direction = normalize_direction(tokens[3])
            if not direction then
                return nil, "grid: overview focus expects left, right, up, or down"
            end
            if not state.overview.active then
                return { changed = false }
            end
            local key = self:focus(state, direction)
            return { changed = key ~= nil, focus_key = key }
        elseif action == "enter" then
            return { changed = self:enter_overview(state) }
        elseif action == "exit" or action == "activate" then
            local changed, focus_key = self:leave_overview(state, false)
            return { changed = changed, focus_key = changed and focus_key or nil }
        elseif action == "cancel" then
            local changed, focus_key = self:leave_overview(state, true)
            return { changed = changed, focus_key = changed and focus_key or nil }
        elseif action == "toggle" then
            if state.overview.active then
                local changed, focus_key = self:leave_overview(state, false)
                return { changed = changed, focus_key = focus_key }
            end
            return { changed = self:enter_overview(state) }
        end
        return nil, "grid: overview expects enter, exit, toggle, activate, cancel, or focus"
    end

    if command == "focus" then
        local direction = normalize_direction(tokens[2])
        if not direction then
            return nil, "grid: focus expects left, right, up, or down"
        end
        local was_empty = state.empty_row and state.empty_row.selected
        local key = self:focus(state, direction)
        local empty = state.empty_row and state.empty_row.selected
        return { changed = key ~= nil or (empty and not was_empty), focus_key = key, clear_focus = empty }
    elseif command == "pan" then
        local direction = normalize_direction(tokens[2])
        local amount = self.config.pan_step
        if tokens[3] ~= nil then
            amount = tonumber(tokens[3])
        end
        if not direction or not numeric(amount) then
            return nil, "grid: pan expects a direction and optional numeric amount"
        end
        return { changed = self:pan(state, direction, amount) }
    elseif command == "move" or command == "swap" then
        local direction = normalize_direction(tokens[2])
        if not direction then
            return nil, "grid: move expects left, right, up, or down"
        end
        return { changed = self:move(state, direction) }
    elseif command == "resize" then
        local direction = normalize_direction(tokens[2])
        if not direction then
            return nil, "grid: resize expects left, right, up, or down"
        end

        if (direction == "left" or direction == "right") and tokens[3] == nil then
            local cycle_direction = direction == "right" and "forward" or "backward"
            return { changed = self:cycle_width(state, cycle_direction) }
        end

        local amount = self.config.resize_step
        if tokens[3] ~= nil then
            amount = tonumber(tokens[3])
        end
        if not numeric(amount) or amount == 0 then
            return nil, "grid: resize expects an optional non-zero numeric amount"
        end
        return { changed = self:resize(state, direction, amount) }
    elseif command == "cycle" then
        if tokens[2] ~= nil and tokens[2] ~= "width" then
            return nil, "grid: cycle expects width forward or backward"
        end
        local direction = tokens[3] == nil and "forward" or normalize_cycle(tokens[3])
        if not direction then
            return nil, "grid: cycle expects width forward or backward"
        end
        return { changed = self:cycle_width(state, direction) }
    elseif command == "insert" then
        local mode = tokens[2] and normalize_direction(tokens[2]) or nil
        if tokens[2] == "auto" then
            mode = "auto"
        end
        if not mode then
            return nil, "grid: insert expects auto, left, right, up, or down"
        end
        return { changed = self:set_insertion(state, mode) }
    elseif command == "center" and (tokens[2] == nil or tokens[2] == "focused") then
        return { changed = self:center(state, state.focus_key) }
    elseif command == "fit" and tokens[2] == "all" then
        return { changed = self:fit_all(state) }
    elseif command == "reset" and (tokens[2] == nil or tokens[2] == "viewport") then
        return { changed = self:reset_viewport(state) }
    elseif command == "reveal" then
        return { changed = self:reveal(state, state.focus_key) }
    end

    return nil, "grid: unknown layout message: " .. tostring(message)
end

function Engine:set_insertion(state, mode)
    if not INSERTION_MODES[mode] then
        return false
    end
    local changed = state.insertion ~= mode
    state.insertion = mode
    return changed
end

function Engine:set_tile(workspace_id, key, rect, present_value)
    if not rect or not numeric(rect.x) or not numeric(rect.y) or not numeric(rect.w) or not numeric(rect.h) then
        error("set_tile expects a numeric rectangle", 2)
    end
    if rect.w < self.config.min_width or rect.h < self.config.min_height then
        error("set_tile rectangle is below configured minimum size", 2)
    end

    local state = self:workspace(workspace_id)
    key = tostring(key)
    if not state.tiles[key] then
        state.order[#state.order + 1] = key
    end
    local old_row_id = state.tiles[key] and state.tiles[key].row_id
    state.tiles[key] = make_rect(key, rect.x, rect.y, rect.w, rect.h)
    state.tiles[key].row_id = old_row_id
    state.tiles[key].present = present_value ~= false
    state.focus_key = state.focus_key or key
    self:_materialize(state)
    return state.tiles[key]
end

local function same_row_neighbor(state, source, epsilon)
    local candidates = {}
    for key, tile in pairs(state.tiles) do
        if present(tile)
            and tile ~= source
            and (state.scroll_mode == "rows" and tile.row_id == source.row_id
            or state.scroll_mode == "shared" and Geometry.overlap_1d(
                source.y,
                Geometry.bottom(source),
                tile.y,
                Geometry.bottom(tile)
            ) > epsilon)
        then
            candidates[#candidates + 1] = { key = key, tile = tile }
        end
    end

    table.sort(candidates, function(a, b)
        if a.tile.x == b.tile.x then
            return tostring(a.key) < tostring(b.key)
        end
        return a.tile.x < b.tile.x
    end)

    local source_right = Geometry.right(source)
    for _, entry in ipairs(candidates) do
        if entry.tile.x >= source_right - epsilon then
            return entry.key
        end
    end

    for index = #candidates, 1, -1 do
        local entry = candidates[index]
        if Geometry.right(entry.tile) <= source.x + epsilon then
            return entry.key
        end
    end

    return nil
end
local function other_row_neighbor(state, source, epsilon)
    rebuild_rows(state, epsilon)

    local source_index
    for index, row in ipairs(state.rows) do
        for _, cell in ipairs(row.cells) do
            if cell.key == source.key then
                source_index = index
                break
            end
        end
        if source_index then
            break
        end
    end
    if not source_index then
        return nil
    end

    -- Prefer the next row; when the removed row is the last one, use the
    -- preceding row instead.
    local row = state.rows[source_index + 1] or state.rows[source_index - 1]
    if not row then
        return nil
    end

    local source_center = source.x + source.w / 2
    local candidates = {}
    for _, cell in ipairs(row.cells) do
        local tile = state.tiles[cell.key]
        if present(tile) then
            candidates[#candidates + 1] = { key = cell.key, tile = tile }
        end
    end

    table.sort(candidates, function(a, b)
        local a_distance = math.abs(a.tile.x + a.tile.w / 2 - source_center)
        local b_distance = math.abs(b.tile.x + b.tile.w / 2 - source_center)
        if a_distance == b_distance then
            if a.tile.x == b.tile.x then
                return tostring(a.key) < tostring(b.key)
            end
            return a.tile.x < b.tile.x
        end
        return a_distance < b_distance
    end)

    return candidates[1] and candidates[1].key or nil
end



local function delete_empty_row(state, removed, epsilon, row_gap)
    local row_bottom = Geometry.bottom(removed)
    for _, tile in pairs(state.tiles) do
        if present(tile) and tile.y >= row_bottom - epsilon then
            tile.y = tile.y - removed.h - row_gap
        end
    end
end

function Engine:_compact_around(state, removed, delete_row)
    if not present(removed) then
        return
    end

    local epsilon = self.config.edge_tolerance
    local original = {}
    for key, tile in pairs(state.tiles) do
        if present(tile) then
            original[key] = { x = tile.x, y = tile.y }
        end
    end

    compact_horizontal_gap(state, removed, epsilon)
    if delete_row then
        delete_empty_row(state, removed, epsilon, self.config.row_gap)
    end

    local valid = Geometry.assert_non_overlapping(state.tiles, epsilon)
    if not valid then
        for key, position in pairs(original) do
            state.tiles[key].x = position.x
            state.tiles[key].y = position.y
        end
    end
end

function Engine:forget_window(key, keep_workspace_id)
    key = tostring(key)
    keep_workspace_id = keep_workspace_id and tostring(keep_workspace_id) or nil
    local replacement

    for workspace_id, state in pairs(self.workspaces) do
        if workspace_id ~= keep_workspace_id and state.tiles[key] then
            local removed = state.tiles[key]
            local epsilon = self.config.edge_tolerance
            local same_row = same_row_neighbor(state, removed, epsilon)
            local row_empty = same_row == nil
            local next_focus

            if state.focus_key == key then
                next_focus = same_row or (row_empty and other_row_neighbor(state, removed, epsilon))
                replacement = next_focus
                state.focus_key = next_focus
                if not next_focus then
                    state.suppress_reveal_once = true
                end
            end

            state.tiles[key] = nil
            remove_from_order(state.order, key)
            self:_compact_around(state, removed, row_empty)
            self:_materialize(state)

            local reveal_key = next_focus
            if not reveal_key and row_empty and present(state.tiles[state.focus_key or "\0"]) then
                reveal_key = state.focus_key
            end
            if reveal_key then
                if state.scroll_mode == "rows"
                    and (not next_focus or state.tiles[reveal_key].row_id ~= removed.row_id)
                then
                    self:_reveal_vertical(state, reveal_key)
                else
                    self:reveal(state, reveal_key)
                end
            end
            if state.overview.active then
                self:fit_all(state)
            end
        end
    end

    return replacement

end


function Engine:prune_workspaces(live_workspace_ids)
    local live = {}
    for _, id in ipairs(live_workspace_ids) do
        live[tostring(id)] = true
    end
    for id in pairs(self.workspaces) do
        if not live[id] then
            self.workspaces[id] = nil
        end
    end
end

function Engine:validate(state)
    for key, tile in pairs(state.tiles) do
        if present(tile) then
            if not numeric(tile.x) or not numeric(tile.y) or not numeric(tile.w) or not numeric(tile.h) then
                return false, "tile " .. tostring(key) .. " has non-finite geometry"
            end
            if tile.w < self.config.min_width - self.config.edge_tolerance then
                return false, "tile " .. tostring(key) .. " is below minimum width"
            end
            if tile.h < self.config.min_height - self.config.edge_tolerance then
                return false, "tile " .. tostring(key) .. " is below minimum height"
            end
        end
    end

    return Geometry.assert_non_overlapping(state.tiles, self.config.edge_tolerance)
end

Engine.defaults = DEFAULTS

return Engine
