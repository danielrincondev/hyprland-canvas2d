-- A shared row has one owner. The adapter moves its real windows after this
-- module transfers the corresponding rectangles as a single layout operation.
local Shared = {}
Shared.__index = Shared

local function copy(value)
    if type(value) ~= "table" then return value end
    local result = {}
    for k, v in pairs(value) do result[k] = copy(v) end
    return result
end

local function row_for(state, id)
    for index, row in ipairs(state.rows) do
        if row.id == id then return row, index end
    end
end

local function anchor(state)
    local tile = state.tiles[state.focus_key]
    return tile and tile.present ~= false and { key = state.focus_key, y = tile.y - state.viewport.y } or nil
end

local function restore_anchor(engine, state, saved)
    if state.empty_row and state.empty_row.selected then
        engine:select_empty_row(state)
        return
    end
    local tile = saved and state.tiles[saved.key]
    if tile and tile.present ~= false then
        state.focus_key = saved.key
        engine:_activate_row(state, saved.key)
        state.viewport.y = tile.y - saved.y
    else
        state.focus_key = engine:last_present_key(state)
        if state.focus_key then engine:reveal(state, state.focus_key) end
    end
end

function Shared.new(engine)
    return setmetatable({ engine = engine, rows = {}, next_id = 0 }, Shared)
end

function Shared:keep_at_top(state)
    local rank = {}
    for id, record in pairs(self.rows) do
        if record.workspace_id == state.id then rank[record.row_id] = id end
    end
    if not next(rank) then return end
    local ordered = {}
    for i, row in ipairs(state.rows) do ordered[i] = row end
    local position = {}
    for i, row in ipairs(ordered) do position[row.id] = i end
    table.sort(ordered, function(a, b)
        local ar, br = rank[a.id], rank[b.id]
        if ar and br then return ar < br end
        if ar or br then return ar ~= nil end
        return position[a.id] < position[b.id]
    end)
    local changed = false
    for i, row in ipairs(ordered) do changed = changed or row ~= state.rows[i] end
    if not changed then return end

    self.engine:_save_row_view(state)
    local saved = anchor(state)
    local top = math.huge
    for _, row in ipairs(ordered) do top = math.min(top, row.y) end
    local live, order = {}, {}
    for _, row in ipairs(ordered) do
        local shift = top - row.y
        for _, tile in pairs(state.tiles) do
            if tile.row_id == row.id then tile.y = tile.y + shift end
        end
        live[row.id] = true
        order[#order + 1] = row.id
        top = top + row.height + self.engine.config.row_gap
    end
    for _, id in ipairs(state.row_order) do
        if not live[id] then order[#order + 1] = id end
    end
    state.row_order = order
    self.engine:_materialize(state)
    restore_anchor(self.engine, state, saved)
    if state.overview.active then self.engine:fit_all(state) end
end

function Shared:refresh()
    for id, record in pairs(self.rows) do
        local state = self.engine.workspaces[record.workspace_id]
        -- Layout replacement/reload can temporarily report no live targets.
        -- Retained row identity also covers temporarily floating windows.
        local view = state and state.row_views[record.row_id]
        if not view then self.rows[id] = nil end
    end
    for _, state in pairs(self.engine.workspaces) do
        self:keep_at_top(state)
        self:ensure_local_row(state)
    end
end

function Shared:ensure_local_row(state)
    local shared, any_shared = {}, false
    for _, record in pairs(self.rows) do
        if record.workspace_id == state.id then shared[record.row_id], any_shared = true, true end
    end
    local bottom = 0
    for _, row in ipairs(state.rows) do
        if not shared[row.id] then state.empty_row = nil; return end
        bottom = math.max(bottom, row.y + row.height + self.engine.config.row_gap)
    end
    if any_shared then
        state.empty_row = state.empty_row or { x = 0, selected = false }
        state.empty_row.y = bottom
        state.empty_row.height = state.viewport.height
        if state.empty_row.selected then self.engine:select_empty_row(state) end
    elseif not (state.empty_row and state.empty_row.selected and #state.rows == 0) then
        state.empty_row = nil
    end
end

function Shared:toggle(state, action, scope)
    action = action or "toggle"
    if action ~= "toggle" and action ~= "on" and action ~= "off" then
        return nil, "grid: share expects toggle, on, or off"
    end
    if scope and scope ~= "all" then
        local valid = scope:match("^%d+[,%d]*$") and not scope:find(",,") and scope:sub(-1) ~= ","
        if not valid then return nil, "grid: share scope must be all or comma-separated workspace numbers" end
        local allowed = false
        for id in scope:gmatch("%d+") do
            if tonumber(id) < 1 then return nil, "grid: shared workspace numbers must be positive" end
            allowed = allowed or tostring(tonumber(id)) == state.id
        end
        if not allowed then return nil, "grid: share scope must include this workspace" end
    end
    self:refresh()
    local tile = state.tiles[state.focus_key]
    local row = tile and row_for(state, tile.row_id)
    if not row then return { changed = false } end
    local current
    for id, record in pairs(self.rows) do
        if record.workspace_id == state.id and record.row_id == row.id then current = id; break end
    end
    local enable = action == "on" or (action == "toggle" and not current)
    if not enable then
        if current then self.rows[current] = nil end
        self:keep_at_top(state)
        self:ensure_local_row(state)
        return { changed = current ~= nil, shared = false }
    end
    if current then
        if scope then self.rows[current].scope = scope end
        return { changed = scope ~= nil, shared = true }
    end
    for _, cell in ipairs(row.cells) do
        if cell.key:match("^group:") then
            return nil, "grid: ungroup windows before sharing their row"
        end
    end
    self.next_id = self.next_id + 1
    self.rows[self.next_id] = {
        id = self.next_id, workspace_id = state.id, row_id = row.id,
        scope = scope or "all",
    }
    self:keep_at_top(state)
    self:ensure_local_row(state)
    return { changed = true, shared = true }
end

function Shared:eligible(record, workspace_id)
    if record.scope == "all" then return true end
    for id in record.scope:gmatch("%d+") do
        if tostring(tonumber(id)) == tostring(workspace_id) then return true end
    end
    return false
end

function Shared:pending(workspace_id)
    self:refresh()
    local result = {}
    for _, record in pairs(self.rows) do
        local row = row_for(self.engine.workspaces[record.workspace_id], record.row_id)
        if row and record.workspace_id ~= tostring(workspace_id) and self:eligible(record, workspace_id) then
            result[#result + 1] = record
        end
    end
    table.sort(result, function(a, b) return a.id < b.id end)
    return result
end

function Shared:transfer(record, destination)
    local engine = self.engine
    local source = assert(engine.workspaces[record.workspace_id])
    local row = row_for(source, record.row_id)
    assert(row and source ~= destination)
    engine:_save_row_view(source)
    local view = copy(source.row_views[row.id])
    if source.scroll_mode == "shared" then view.x = source.viewport.x end
    local source_anchor, destination_anchor = anchor(source), anchor(destination)
    local entries, keys = {}, {}
    for _, cell in ipairs(row.cells) do
        local tile = copy(source.tiles[cell.key])
        tile.y = tile.y - row.y
        entries[#entries + 1] = { key = cell.key, tile = tile }
        keys[cell.key] = true
        source.tiles[cell.key] = nil
    end
    for i = #source.order, 1, -1 do
        if keys[source.order[i]] then table.remove(source.order, i) end
    end
    local span = row.height + engine.config.row_gap
    for _, tile in pairs(source.tiles) do
        if tile.y >= row.y + row.height - engine.config.edge_tolerance then tile.y = tile.y - span end
    end
    engine:_materialize(source)
    restore_anchor(engine, source, source_anchor)

    local next_row = destination.rows[1]
    local top = next_row and next_row.y or 0
    if next_row then
        for _, tile in pairs(destination.tiles) do
            if tile.y >= top then tile.y = tile.y + span end
        end
    end
    destination.next_row_id = destination.next_row_id + 1
    local new_id = destination.next_row_id
    -- row_order can contain parked floating rows; insert before the live row.
    local order_position = #destination.row_order + 1
    if next_row then
        for i, id in ipairs(destination.row_order) do
            if id == next_row.id then order_position = i; break end
        end
    end
    table.insert(destination.row_order, order_position, new_id)
    destination.row_views[new_id] = view
    for _, entry in ipairs(entries) do
        entry.tile.row_id = new_id
        entry.tile.y = top + entry.tile.y
        destination.tiles[entry.key] = entry.tile
        destination.order[#destination.order + 1] = entry.key
    end
    record.workspace_id, record.row_id = destination.id, new_id
    engine:_materialize(destination)
    self:keep_at_top(destination)
    self:ensure_local_row(destination)
    self:ensure_local_row(source)
    if destination_anchor then
        restore_anchor(engine, destination, destination_anchor)
    elseif destination.empty_row and destination.empty_row.selected then
        engine:select_empty_row(destination)
    else
        destination.focus_key = keys[view.focus_key] and view.focus_key or entries[1].key
        engine:_activate_row(destination, destination.focus_key)
        engine:_reveal_vertical(destination, destination.focus_key)
    end
    return entries
end

function Shared:checkpoint()
    return copy({ workspaces = self.engine.workspaces, rows = self.rows, next_id = self.next_id })
end

function Shared:rollback(saved)
    self.engine.workspaces, self.rows, self.next_id = saved.workspaces, saved.rows, saved.next_id
end

return Shared
