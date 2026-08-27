local Geometry = require("canvas2d.geometry")

local Engine = {}
Engine.__index = Engine

local DEFAULTS = {
    layout_name = "canvas2d",
    tile_width_ratio = 0.50,
    tile_height_ratio = 0.55,
    wrap_width_ratio = 2.10,
    min_width = 160,
    min_height = 100,
    pan_step = 300,
    resize_step = 60,
    viewport_margin = 48,
    fit_padding = 32,
    min_fit_scale = 0.10,
    max_fit_scale = 1.00,
    diagonal_weight = 2.00,
    edge_tolerance = 0.001,
    insertion = "auto",
    auto_reveal = true,
    reveal_new = true,
}

local NUMBER_OPTIONS = {
    tile_width_ratio = { 0.05, 4.00 },
    tile_height_ratio = { 0.05, 4.00 },
    wrap_width_ratio = { 0.10, 20.00 },
    min_width = { 1, math.huge },
    min_height = { 1, math.huge },
    pan_step = { 0, math.huge },
    resize_step = { 0, math.huge },
    viewport_margin = { 0, math.huge },
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

local function copy_defaults()
    local config = {}
    for key, value in pairs(DEFAULTS) do
        config[key] = value
    end
    return config
end

local function copy_rect(rect)
    return {
        x = rect.x,
        y = rect.y,
        w = rect.w,
        h = rect.h,
    }
end

local function remove_from_order(order, key)
    for index = #order, 1, -1 do
        if order[index] == key then
            table.remove(order, index)
        end
    end
end

local function numeric(value)
    return type(value) == "number" and value == value and value ~= math.huge and value ~= -math.huge
end

local function present(tile)
    return tile and tile.present ~= false
end

local function normalize_direction(direction)
    return direction and DIRECTION_ALIASES[direction:lower()] or nil
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

local function validate_options(options)
    local config = copy_defaults()
    options = options or {}

    for key, value in pairs(options) do
        if config[key] == nil then
            error("unknown canvas2d option: " .. tostring(key), 3)
        end

        if NUMBER_OPTIONS[key] then
            local range = NUMBER_OPTIONS[key]
            if not numeric(value) or value < range[1] or value > range[2] then
                error(string.format("canvas2d option %s must be a number in [%s, %s]", key, range[1], range[2]), 3)
            end
        elseif key == "layout_name" then
            if type(value) ~= "string" or value == "" or value:find("%s") then
                error("canvas2d option layout_name must be a non-empty name without whitespace", 3)
            end
        elseif key == "insertion" then
            if type(value) ~= "string" or not INSERTION_MODES[value] then
                error("canvas2d option insertion must be auto, left, right, up, or down", 3)
            end
        elseif key == "auto_reveal" or key == "reveal_new" then
            if type(value) ~= "boolean" then
                error("canvas2d option " .. key .. " must be boolean", 3)
            end
        end

        config[key] = value
    end

    if config.min_fit_scale > config.max_fit_scale then
        error("canvas2d min_fit_scale must not exceed max_fit_scale", 3)
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
                width = area and area.w or 0,
                height = area and area.h or 0,
                scale = 1,
            },
            tiles = {},
            order = {},
            focus_key = nil,
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

function Engine:present_count(state)
    local count = 0
    for _, tile in pairs(state.tiles) do
        if present(tile) then
            count = count + 1
        end
    end
    return count
end

function Engine:_default_size(area)
    return math.max(self.config.min_width, area.w * self.config.tile_width_ratio),
        math.max(self.config.min_height, area.h * self.config.tile_height_ratio)
end

function Engine:_push_collisions(state, candidate, direction)
    local ordered = {}
    for key, tile in pairs(state.tiles) do
        if present(tile) then
            ordered[#ordered + 1] = { key = key, tile = tile }
        end
    end

    table.sort(ordered, function(a, b)
        if direction == "right" then
            return a.tile.x == b.tile.x and tostring(a.key) < tostring(b.key) or a.tile.x < b.tile.x
        elseif direction == "left" then
            local ar = Geometry.right(a.tile)
            local br = Geometry.right(b.tile)
            return ar == br and tostring(a.key) < tostring(b.key) or ar > br
        elseif direction == "down" then
            return a.tile.y == b.tile.y and tostring(a.key) < tostring(b.key) or a.tile.y < b.tile.y
        else
            local ab = Geometry.bottom(a.tile)
            local bb = Geometry.bottom(b.tile)
            return ab == bb and tostring(a.key) < tostring(b.key) or ab > bb
        end
    end)

    local blockers = { candidate }
    for _, entry in ipairs(ordered) do
        local tile = entry.tile
        local shift = 0

        for _, blocker in ipairs(blockers) do
            if Geometry.intersects(tile, blocker, self.config.edge_tolerance) then
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

        if shift > 0 then
            if direction == "right" then
                tile.x = tile.x + shift
            elseif direction == "left" then
                tile.x = tile.x - shift
            elseif direction == "down" then
                tile.y = tile.y + shift
            else
                tile.y = tile.y - shift
            end
            blockers[#blockers + 1] = tile
        end
    end
end

function Engine:_auto_insertion_rect(state, anchor, area, width, height)
    if not anchor then
        return { x = 0, y = 0, w = width, h = height }, "right"
    end

    local row_min = anchor.x
    local row_max = Geometry.right(anchor)
    for _, tile in pairs(state.tiles) do
        if present(tile)
            and Geometry.overlap_1d(anchor.y, Geometry.bottom(anchor), tile.y, Geometry.bottom(tile)) > self.config.edge_tolerance
        then
            row_min = math.min(row_min, tile.x)
            row_max = math.max(row_max, Geometry.right(tile))
        end
    end

    local wrap_width = math.max(width, area.w * self.config.wrap_width_ratio)
    if row_max + width - row_min <= wrap_width + self.config.edge_tolerance then
        return {
            x = Geometry.right(anchor),
            y = anchor.y,
            w = width,
            h = anchor.h,
        }, "right"
    end

    local bounds = Geometry.bounds(state.tiles)
    return {
        x = bounds and bounds.x or 0,
        y = bounds and Geometry.bottom(bounds) or 0,
        w = width,
        h = height,
    }, "down"
end

function Engine:_directional_insertion_rect(anchor, direction, width, height)
    if direction == "left" then
        return { x = anchor.x - width, y = anchor.y, w = width, h = anchor.h }
    elseif direction == "right" then
        return { x = Geometry.right(anchor), y = anchor.y, w = width, h = anchor.h }
    elseif direction == "up" then
        return { x = anchor.x, y = anchor.y - height, w = anchor.w, h = height }
    else
        return { x = anchor.x, y = Geometry.bottom(anchor), w = anchor.w, h = height }
    end
end

function Engine:_insert_new(state, key, area)
    local width, height = self:_default_size(area)
    local anchor_key = present(state.tiles[state.focus_key]) and state.focus_key or self:last_present_key(state)
    local anchor = anchor_key and state.tiles[anchor_key] or nil
    local rect
    local push_direction

    if not anchor then
        rect = { x = 0, y = 0, w = width, h = height }
        push_direction = "right"
    elseif state.insertion == "auto" then
        rect, push_direction = self:_auto_insertion_rect(state, anchor, area, width, height)
    else
        rect = self:_directional_insertion_rect(anchor, state.insertion, width, height)
        push_direction = state.insertion
    end

    self:_push_collisions(state, rect, push_direction)
    rect.key = key
    rect.present = true
    state.tiles[key] = rect
    state.order[#state.order + 1] = key
    state.focus_key = key
    return rect
end

function Engine:sync(workspace_id, descriptors, area)
    local state = self:workspace(workspace_id, area)
    local active_key
    local newly_added = {}

    for _, tile in pairs(state.tiles) do
        tile.present = false
    end

    for _, descriptor in ipairs(descriptors) do
        local key = tostring(descriptor.key)
        local tile = state.tiles[key]
        if tile then
            tile.present = true
        end
        if descriptor.active then
            active_key = key
        end
    end

    if not present(state.tiles[state.focus_key]) then
        state.focus_key = self:last_present_key(state)
    end

    for _, descriptor in ipairs(descriptors) do
        local key = tostring(descriptor.key)
        if not state.tiles[key] then
            self:_insert_new(state, key, area)
            newly_added[key] = true
        end
    end

    if active_key and present(state.tiles[active_key]) then
        state.focus_key = active_key
    elseif not present(state.tiles[state.focus_key]) then
        state.focus_key = self:last_present_key(state)
    end

    if self.config.reveal_new and active_key and newly_added[active_key] then
        self:reveal(state, active_key)
    end

    return state, newly_added
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
    state.tiles[key] = copy_rect(rect)
    state.tiles[key].key = key
    state.tiles[key].present = present_value ~= false
    state.focus_key = state.focus_key or key
    return state.tiles[key]
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
    return {
        x = area.x + (tile.x - state.viewport.x) * scale,
        y = area.y + (tile.y - state.viewport.y) * scale,
        w = tile.w * scale,
        h = tile.h * scale,
    }
end

function Engine:pan(state, direction, amount)
    amount = amount or self.config.pan_step
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
    return amount ~= 0
end

function Engine:reveal(state, key)
    local tile = state.tiles[key]
    if not present(tile) then
        return false
    end

    local viewport = self:world_viewport(state)
    local margin = self.config.viewport_margin / state.viewport.scale
    local x, y = Geometry.reveal(viewport, tile, margin)
    local changed = x ~= state.viewport.x or y ~= state.viewport.y
    state.viewport.x = x
    state.viewport.y = y
    return changed
end

function Engine:center(state, key)
    local tile = state.tiles[key]
    if not present(tile) then
        return false
    end

    local viewport = self:world_viewport(state)
    local x = tile.x + tile.w / 2 - viewport.w / 2
    local y = tile.y + tile.h / 2 - viewport.h / 2
    local changed = x ~= state.viewport.x or y ~= state.viewport.y
    state.viewport.x = x
    state.viewport.y = y
    return changed
end

function Engine:fit_all(state)
    local bounds = Geometry.bounds(state.tiles)
    if not bounds then
        return false
    end

    local width = math.max(1, state.viewport.width - 2 * self.config.fit_padding)
    local height = math.max(1, state.viewport.height - 2 * self.config.fit_padding)
    local scale_x = bounds.w > 0 and width / bounds.w or self.config.max_fit_scale
    local scale_y = bounds.h > 0 and height / bounds.h or self.config.max_fit_scale
    local scale = math.max(self.config.min_fit_scale, math.min(self.config.max_fit_scale, scale_x, scale_y))
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
    local changed = state.viewport.x ~= 0 or state.viewport.y ~= 0 or state.viewport.scale ~= 1
    state.viewport.x = 0
    state.viewport.y = 0
    state.viewport.scale = 1
    return changed
end

function Engine:focus(state, direction)
    local current = present(state.tiles[state.focus_key]) and state.focus_key or self:last_present_key(state)
    if not current then
        return nil
    end

    local next_key = Geometry.directional_neighbor(state.tiles, current, direction, {
        epsilon = self.config.edge_tolerance,
        diagonal_weight = self.config.diagonal_weight,
    })
    if not next_key then
        return nil
    end

    state.focus_key = next_key
    self:reveal(state, next_key)
    return next_key
end

function Engine:move(state, direction)
    local current = present(state.tiles[state.focus_key]) and state.focus_key or self:last_present_key(state)
    if not current then
        return false
    end

    local neighbor = Geometry.directional_neighbor(state.tiles, current, direction, {
        epsilon = self.config.edge_tolerance,
        diagonal_weight = self.config.diagonal_weight,
    })
    if not neighbor then
        return false
    end

    local current_rect = copy_rect(state.tiles[current])
    local neighbor_rect = copy_rect(state.tiles[neighbor])
    state.tiles[current].x = neighbor_rect.x
    state.tiles[current].y = neighbor_rect.y
    state.tiles[current].w = neighbor_rect.w
    state.tiles[current].h = neighbor_rect.h
    state.tiles[neighbor].x = current_rect.x
    state.tiles[neighbor].y = current_rect.y
    state.tiles[neighbor].w = current_rect.w
    state.tiles[neighbor].h = current_rect.h
    self:reveal(state, current)
    return true
end

function Engine:_apply_positive_resize(state, key, direction, amount)
    local tile = state.tiles[key]
    local neighbors, gap = Geometry.edge_candidates(state.tiles, key, direction, self.config.edge_tolerance)

    if #neighbors == 0 then
        gap = amount
    end

    local available = math.huge
    if #neighbors > 0 then
        for _, neighbor_key in ipairs(neighbors) do
            local neighbor = state.tiles[neighbor_key]
            local size = (direction == "left" or direction == "right") and neighbor.w or neighbor.h
            local minimum = (direction == "left" or direction == "right") and self.config.min_width or self.config.min_height
            available = math.min(available, math.max(0, size - minimum))
        end
    end

    local total = math.min(amount, (gap or 0) + available)
    if #neighbors == 0 then
        total = amount
    end
    if total <= 0 then
        return false
    end

    local steal = #neighbors > 0 and math.max(0, total - (gap or 0)) or 0
    if direction == "right" then
        tile.w = tile.w + total
        for _, neighbor_key in ipairs(neighbors) do
            local neighbor = state.tiles[neighbor_key]
            neighbor.x = neighbor.x + steal
            neighbor.w = neighbor.w - steal
        end
    elseif direction == "left" then
        tile.x = tile.x - total
        tile.w = tile.w + total
        for _, neighbor_key in ipairs(neighbors) do
            state.tiles[neighbor_key].w = state.tiles[neighbor_key].w - steal
        end
    elseif direction == "down" then
        tile.h = tile.h + total
        for _, neighbor_key in ipairs(neighbors) do
            local neighbor = state.tiles[neighbor_key]
            neighbor.y = neighbor.y + steal
            neighbor.h = neighbor.h - steal
        end
    else
        tile.y = tile.y - total
        tile.h = tile.h + total
        for _, neighbor_key in ipairs(neighbors) do
            state.tiles[neighbor_key].h = state.tiles[neighbor_key].h - steal
        end
    end

    return true
end

function Engine:_apply_negative_resize(state, key, direction, amount)
    local tile = state.tiles[key]
    local horizontal = direction == "left" or direction == "right"
    local size = horizontal and tile.w or tile.h
    local minimum = horizontal and self.config.min_width or self.config.min_height
    local shrink = math.min(amount, math.max(0, size - minimum))
    if shrink <= 0 then
        return false
    end

    local neighbors, gap = Geometry.edge_candidates(state.tiles, key, direction, self.config.edge_tolerance)
    local touching = gap ~= nil and gap <= self.config.edge_tolerance
    if not touching then
        neighbors = {}
    end

    if direction == "right" then
        tile.w = tile.w - shrink
        for _, neighbor_key in ipairs(neighbors) do
            local neighbor = state.tiles[neighbor_key]
            neighbor.x = neighbor.x - shrink
            neighbor.w = neighbor.w + shrink
        end
    elseif direction == "left" then
        tile.x = tile.x + shrink
        tile.w = tile.w - shrink
        for _, neighbor_key in ipairs(neighbors) do
            state.tiles[neighbor_key].w = state.tiles[neighbor_key].w + shrink
        end
    elseif direction == "down" then
        tile.h = tile.h - shrink
        for _, neighbor_key in ipairs(neighbors) do
            local neighbor = state.tiles[neighbor_key]
            neighbor.y = neighbor.y - shrink
            neighbor.h = neighbor.h + shrink
        end
    else
        tile.y = tile.y + shrink
        tile.h = tile.h - shrink
        for _, neighbor_key in ipairs(neighbors) do
            state.tiles[neighbor_key].h = state.tiles[neighbor_key].h + shrink
        end
    end

    return true
end

function Engine:resize(state, direction, amount)
    local key = present(state.tiles[state.focus_key]) and state.focus_key or self:last_present_key(state)
    if not key or not Geometry.valid_direction(direction) or amount == 0 then
        return false
    end

    local changed
    if amount > 0 then
        changed = self:_apply_positive_resize(state, key, direction, amount)
    else
        changed = self:_apply_negative_resize(state, key, direction, -amount)
    end

    if changed then
        self:reveal(state, key)
    end
    return changed
end

function Engine:set_insertion(state, mode)
    if not INSERTION_MODES[mode] then
        return false
    end
    local changed = state.insertion ~= mode
    state.insertion = mode
    return changed
end

function Engine:command(state, message)
    local tokens = expand_compound_command(tokenize(message))
    local command = tokens[1]

    if not command then
        return nil, "canvas2d: empty layout message"
    end

    if command == "focus" then
        local direction = normalize_direction(tokens[2])
        if not direction then
            return nil, "canvas2d: focus expects left, right, up, or down"
        end
        local key = self:focus(state, direction)
        return { changed = key ~= nil, focus_key = key }
    elseif command == "pan" then
        local direction = normalize_direction(tokens[2])
        local amount = tokens[3] and tonumber(tokens[3]) or self.config.pan_step
        if not direction or not numeric(amount) then
            return nil, "canvas2d: pan expects a direction and optional numeric amount"
        end
        return { changed = self:pan(state, direction, amount) }
    elseif command == "move" or command == "swap" then
        local direction = normalize_direction(tokens[2])
        if not direction then
            return nil, "canvas2d: move expects left, right, up, or down"
        end
        return { changed = self:move(state, direction) }
    elseif command == "resize" then
        local direction = normalize_direction(tokens[2])
        local amount = tokens[3] and tonumber(tokens[3]) or self.config.resize_step
        if not direction or not numeric(amount) then
            return nil, "canvas2d: resize expects a direction and optional signed numeric amount"
        end
        return { changed = self:resize(state, direction, amount) }
    elseif command == "insert" then
        local mode = tokens[2] and normalize_direction(tokens[2]) or nil
        if tokens[2] == "auto" then
            mode = "auto"
        end
        if not mode then
            return nil, "canvas2d: insert expects auto, left, right, up, or down"
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

    return nil, "canvas2d: unknown layout message: " .. tostring(message)
end

function Engine:forget_window(key, keep_workspace_id)
    key = tostring(key)
    keep_workspace_id = keep_workspace_id and tostring(keep_workspace_id) or nil

    for workspace_id, state in pairs(self.workspaces) do
        if workspace_id ~= keep_workspace_id and state.tiles[key] then
            state.tiles[key] = nil
            remove_from_order(state.order, key)
            if state.focus_key == key then
                state.focus_key = self:last_present_key(state)
            end
        end
    end
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
