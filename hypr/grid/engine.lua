local Geometry = require("grid.geometry")

local Engine = {}
Engine.__index = Engine

local DEFAULTS = {
    layout_name = "grid",
    width_presets = { 0.34, 0.50, 0.67, 1.00 },
    default_width = 0.50,
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
    default_width = { 0.000001, 1.00 },
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
    return direction and DIRECTION_ALIASES[direction:lower()] or nil
end

local function normalize_cycle(direction)
    return direction and CYCLE_DIRECTIONS[direction:lower()] or nil
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
        elseif key == "auto_reveal" or key == "reveal_new" then
            if type(value) ~= "boolean" then
                error("grid option " .. key .. " must be boolean", 3)
            end
        end

        config[key] = value
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
                width = area and area.w or 0,
                height = area and area.h or 0,
                scale = 1,
            },
            rows = {},
            tiles = {},
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

function Engine:_locate(state, key)
    key = tostring(key)
    for row_index, row in ipairs(state.rows) do
        for cell_index, cell in ipairs(row.cells) do
            if cell.key == key then
                return { row_index = row_index, cell_index = cell_index, row = row, cell = cell }
            end
        end
    end
    return nil
end

function Engine:_structural_last_key(state)
    local row = state.rows[#state.rows]
    local cell = row and row.cells[#row.cells] or nil
    return cell and cell.key or nil
end

function Engine:_anchor_location(state)
    if state.focus_key then
        local location = self:_locate(state, state.focus_key)
        if location then
            return location
        end
    end

    local last_row_index = #state.rows
    local row = state.rows[last_row_index]
    if not row or #row.cells == 0 then
        return nil
    end

    return {
        row_index = last_row_index,
        cell_index = #row.cells,
        row = row,
        cell = row.cells[#row.cells],
    }
end

function Engine:_remove_cell(state, key)
    local location = self:_locate(state, key)
    if not location then
        return false
    end

    table.remove(location.row.cells, location.cell_index)
    if #location.row.cells == 0 then
        table.remove(state.rows, location.row_index)
    end
    return true
end

function Engine:present_count(state)
    local count = 0
    for _, row in ipairs(state.rows) do
        count = count + #row.cells
    end
    return count
end

function Engine:_materialize(state)
    state.tiles = Geometry.derive_grid(state.rows, {
        x = 0,
        y = 0,
        w = state.viewport.width,
        h = state.viewport.height,
    }, {
        min_width = self.config.min_width,
        min_height = self.config.min_height,
    })
    return state.tiles
end

local function make_cell(key)
    return { key = tostring(key), width = nil }
end

local function make_row(cell)
    return { height = 1, cells = { cell } }
end

local EDGE_ORDER = { right = true, left = true, up = true, down = true }

-- Place a new cell relative to the focused anchor. "right"/"left" insert into
-- the anchor's own row; "down"/"up" join the adjacent row below/above
-- (creating it when missing) aligned as closely as possible to the anchor's
-- left edge.
function Engine:_insert_new(state, key)
    local mode = state.insertion == "auto" and "right" or state.insertion
    local anchor = self:_anchor_location(state)
    local cell = make_cell(key)
    cell.width = self.config.default_width

    if not anchor then
        state.rows[1] = make_row(cell)
        state.focus_key = cell.key
        return cell.key
    end

    if mode ~= "right" and mode ~= "left" and mode ~= "up" and mode ~= "down" then
        mode = "right"
    end

    if mode == "right" then
        table.insert(anchor.row.cells, anchor.cell_index + 1, cell)
    elseif mode == "left" then
        table.insert(anchor.row.cells, anchor.cell_index, cell)
    else
        local delta = mode == "down" and 1 or -1
        local target_row = state.rows[anchor.row_index + delta]
        local left_edge = 0
        local anchor_tile = state.tiles and state.tiles[anchor.cell.key]
        if anchor_tile then
            left_edge = anchor_tile.x
        end

        if target_row then
            local position = Geometry.aligned_cell_index(target_row.cells, left_edge, state.viewport.width)
            table.insert(target_row.cells, position, cell)
        elseif delta > 0 then
            table.insert(state.rows, anchor.row_index + 1, make_row(cell))
        else
            table.insert(state.rows, 1, make_row(cell))
        end
    end

    state.focus_key = cell.key
    return cell.key
end-- Horizontal movement reorders within the focused row and wraps at the row
-- edges. Vertical movement is literal demotion/promotion: the whole window
-- leaves its row and joins (or creates) the adjacent band below/above.
function Engine:move(state, direction)
    local location = self:_anchor_location(state)
    if not location then
        return false
    end

    local rows = state.rows

    if direction == "left" or direction == "right" then
        local row = location.row
        if #row.cells < 2 then
            return false
        end

        local target_index = location.cell_index + (direction == "left" and -1 or 1)
        if target_index < 1 then
            target_index = #row.cells
        elseif target_index > #row.cells then
            target_index = 1
        end

        local moving = table.remove(row.cells, location.cell_index)
        table.insert(row.cells, target_index, moving)
        state.focus_key = moving.key
        return true
    end

    if direction ~= "up" and direction ~= "down" then
        return false
    end

    local delta = direction == "down" and 1 or -1
    local left_edge = 0
    local source_tile = state.tiles and state.tiles[location.cell.key]
    if source_tile then
        left_edge = source_tile.x
    end

    local moving = location.cell
    table.remove(location.row.cells, location.cell_index)

    local removed_source_row = false
    if #location.row.cells == 0 then
        table.remove(rows, location.row_index)
        removed_source_row = true
    end

    -- Removing the emptied source row shifts every row below it up by one slot,
    -- so only downward targets need their index corrected; upward targets point
    -- at rows that never moved.
    local target_index = location.row_index + delta
    if removed_source_row and delta > 0 then
        target_index = target_index - 1
    end
    local target_row = rows[target_index]

    if target_row then
        local position = Geometry.aligned_cell_index(target_row.cells, left_edge, state.viewport.width)
        table.insert(target_row.cells, position, moving)
    elseif target_index >= 1 then
        table.insert(rows, math.min(target_index, #rows + 1), make_row(moving))
    else
        table.insert(rows, 1, make_row(moving))
    end

    state.focus_key = moving.key
    self:_materialize(state)
    self:reveal(state, moving.key)
    return true
end-- Width cycling walks the configured preset list. Cell widths are relative
-- weights inside their row, so the displayed width can never exceed the screen.
function Engine:cycle_width(state, direction)
    local location = self:_anchor_location(state)
    if not location then
        return false
    end

    local presets = self.config.width_presets
    local current = location.cell.width or self.config.default_width

    local index = 1
    for position, preset in ipairs(presets) do
        if math.abs(preset - current) < math.abs(presets[index] - current) then
            index = position
        end
    end

    local next_index = index + (direction == "forward" and 1 or -1)
    if next_index < 1 then
        next_index = #presets
    elseif next_index > #presets then
        next_index = 1
    end

    local changed = presets[next_index] ~= current
    location.cell.width = presets[next_index]
    return changed
end

-- Vertical resize transfers height between the focused row and one adjacent
-- row, clamped so no row falls below min_height. Rows always split the full
-- work-area height, so unbounded growth is impossible by construction.
function Engine:resize_rows(state, direction, amount)
    local rows = state.rows
    local location = self:_anchor_location(state)
    if not location or #rows < 2 then
        return false
    end
    if direction ~= "up" and direction ~= "down" then
        return false
    end

    local grow = amount > 0
    local desired = math.abs(amount)
    if desired <= 0 then
        return false
    end

    local primary_delta
    local secondary_delta
    if grow then
        primary_delta = direction == "down" and 1 or -1
        secondary_delta = -primary_delta
    else
        primary_delta = direction == "down" and -1 or 1
        secondary_delta = -primary_delta
    end

    local donor_index = location.row_index + primary_delta
    local donor = rows[donor_index]
    if not donor then
        donor_index = location.row_index + secondary_delta
        donor = rows[donor_index]
    end
    if not donor then
        return false
    end

    local tiles = state.tiles
    local receiver_tile = tiles and tiles[location.cell.key]
    local donor_tile = tiles and tiles[donor.cells[#donor.cells].key]
    if not receiver_tile or not donor_tile then
        return false
    end

    local step = math.min(desired, math.max(0, donor_tile.h - self.config.min_height))
    if step <= 0 then
        return false
    end

    local weight_total = 0
    for _, row in ipairs(rows) do
        weight_total = weight_total + (row.height and row.height > 0 and row.height or 1)
    end

    local weight_step = step * weight_total / math.max(1, state.viewport.height)
    local receiving = location.row
    receiving.height = (receiving.height and receiving.height > 0 and receiving.height or 1)
        + (grow and weight_step or -weight_step)
    donor.height = (donor.height and donor.height > 0 and donor.height or 1)
        - (grow and weight_step or -weight_step)

    return true
end

function Engine:resize(state, direction, amount)
    local key = present(state.tiles[state.focus_key]) and state.focus_key or self:_structural_last_key(state)
    if not key or not Geometry.valid_direction(direction) or amount == 0 then
        return false
    end

    local changed
    if direction == "up" or direction == "down" then
        changed = self:resize_rows(state, direction, amount)
    else
        -- Left/right name the cycling edge; a signed explicit amount may flip it.
        local cycle_direction = direction == "right" and "forward" or "backward"
        if amount < 0 then
            cycle_direction = cycle_direction == "forward" and "backward" or "forward"
        end
        changed = self:cycle_width(state, cycle_direction)
    end

    if changed then
        self:_materialize(state)
        self:reveal(state, key)
    end
    return changed
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
    local current = present(state.tiles[state.focus_key]) and state.focus_key or self:_structural_last_key(state)
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

function Engine:sync(workspace_id, descriptors, area)
    local state = self:workspace(workspace_id, area)
    local wanted = {}
    local active_key

    for _, descriptor in ipairs(descriptors) do
        local key = tostring(descriptor.key)
        wanted[key] = true
        if descriptor.active then
            active_key = key
        end
    end

    -- Structural removal. Departed targets are deleted from their rows; because
    -- all placement is derived afterwards, survivors automatically become
    -- neighbors instead of leaving holes behind.
    for row_index = #state.rows, 1, -1 do
        local row = state.rows[row_index]
        for cell_index = #row.cells, 1, -1 do
            if not wanted[row.cells[cell_index].key] then
                table.remove(row.cells, cell_index)
            end
        end
        if #row.cells == 0 then
            table.remove(state.rows, row_index)
        end
    end

    -- Insert newcomers relative to the current focus.
    local newly_added = {}
    for _, descriptor in ipairs(descriptors) do
        local key = tostring(descriptor.key)
        if not self:_locate(state, key) then
            self:_insert_new(state, key)
            newly_added[key] = true
        end
    end

    -- Focus resolution: the active window wins, otherwise keep a valid focus,
    -- otherwise fall back to the structurally last cell.
    if active_key and self:_locate(state, active_key) then
        state.focus_key = active_key
    elseif not self:_locate(state, state.focus_key or "\0") then
        state.focus_key = self:_structural_last_key(state)
    end

    self:_materialize(state)

    if self.config.reveal_new and active_key and newly_added[active_key] then
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

    if command == "focus" then
        local direction = normalize_direction(tokens[2])
        if not direction then
            return nil, "grid: focus expects left, right, up, or down"
        end
        local key = self:focus(state, direction)
        return { changed = key ~= nil, focus_key = key }
    elseif command == "pan" then
        local direction = normalize_direction(tokens[2])
        local amount = tokens[3] and tonumber(tokens[3]) or self.config.pan_step
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
        local amount = tokens[3] and tonumber(tokens[3]) or self.config.resize_step
        if not direction or not numeric(amount) or amount == 0 then
            return nil, "grid: resize expects up/down with an optional signed amount, or left/right to cycle width"
        end
        return { changed = self:resize(state, direction, amount) }
    elseif command == "cycle" then
        if tokens[2] ~= nil and tokens[2] ~= "width" then
            return nil, "grid: cycle expects width forward or backward"
        end
        local direction = normalize_cycle(tokens[3]) or "forward"
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

function Engine:forget_window(key, keep_workspace_id)
    key = tostring(key)
    keep_workspace_id = keep_workspace_id and tostring(keep_workspace_id) or nil

    for workspace_id, state in pairs(self.workspaces) do
        if workspace_id ~= keep_workspace_id and self:_remove_cell(state, key) then
            if state.focus_key == key then
                state.focus_key = self:_structural_last_key(state)
            end
            self:_materialize(state)
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
    for key, tile in pairs(state.tiles or {}) do
        if not numeric(tile.x) or not numeric(tile.y) or not numeric(tile.w) or not numeric(tile.h) then
            return false, "tile " .. tostring(key) .. " has non-finite geometry"
        end
        if tile.w <= 0 or tile.h <= 0 then
            return false, "tile " .. tostring(key) .. " has non-positive size"
        end
    end

    for _, row in ipairs(state.rows) do
        for _, cell in ipairs(row.cells) do
            if not state.tiles[cell.key] then
                return false, "cell " .. tostring(cell.key) .. " has no derived tile"
            end
        end
    end

    local non_overlapping, reason = Geometry.assert_non_overlapping(state.tiles or {}, self.config.edge_tolerance)
    if not non_overlapping then
        return false, reason
    end

    return true
end

Engine.defaults = DEFAULTS

return Engine