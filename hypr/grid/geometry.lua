local Geometry = {}

local DIRECTIONS = {
    left = true,
    right = true,
    up = true,
    down = true,
}

local function is_present(tile)
    return tile and tile.present ~= false
end

local function rect_right(rect)
    return rect.x + rect.w
end

local function rect_bottom(rect)
    return rect.y + rect.h
end

local function overlap_1d(a0, a1, b0, b1)
    return math.max(0, math.min(a1, b1) - math.max(a0, b0))
end

local function stable_key_less(a, b)
    return tostring(a) < tostring(b)
end

local function score_less(a, b)
    for i = 1, #a do
        if a[i] < b[i] then
            return true
        end
        if a[i] > b[i] then
            return false
        end
    end
    return false
end

function Geometry.valid_direction(direction)
    return DIRECTIONS[direction] == true
end

function Geometry.copy(rect)
    return {
        x = rect.x,
        y = rect.y,
        w = rect.w,
        h = rect.h,
    }
end

function Geometry.center(rect)
    return rect.x + rect.w / 2, rect.y + rect.h / 2
end

function Geometry.right(rect)
    return rect_right(rect)
end

function Geometry.bottom(rect)
    return rect_bottom(rect)
end

function Geometry.overlap_1d(a0, a1, b0, b1)
    return overlap_1d(a0, a1, b0, b1)
end

function Geometry.intersects(a, b, epsilon)
    epsilon = epsilon or 0
    return a.x < rect_right(b) - epsilon
        and rect_right(a) > b.x + epsilon
        and a.y < rect_bottom(b) - epsilon
        and rect_bottom(a) > b.y + epsilon
end

function Geometry.bounds(tiles)
    local min_x, min_y, max_x, max_y

    for _, tile in pairs(tiles) do
        if is_present(tile) then
            min_x = min_x and math.min(min_x, tile.x) or tile.x
            min_y = min_y and math.min(min_y, tile.y) or tile.y
            max_x = max_x and math.max(max_x, rect_right(tile)) or rect_right(tile)
            max_y = max_y and math.max(max_y, rect_bottom(tile)) or rect_bottom(tile)
        end
    end

    if not min_x then
        return nil
    end

    return {
        x = min_x,
        y = min_y,
        w = max_x - min_x,
        h = max_y - min_y,
    }
end

function Geometry.directional_neighbor(tiles, source_key, direction, options)
    if not DIRECTIONS[direction] then
        return nil
    end

    local source = tiles[source_key]
    if not is_present(source) then
        return nil
    end

    options = options or {}
    local epsilon = options.epsilon or 0.001
    local diagonal_weight = options.diagonal_weight or 2
    local source_cx, source_cy = Geometry.center(source)
    local best_key, best_score

    for key, candidate in pairs(tiles) do
        if key ~= source_key and is_present(candidate) then
            local candidate_cx, candidate_cy = Geometry.center(candidate)
            local primary_delta
            local primary_gap
            local perpendicular_gap
            local perpendicular_center_delta
            local overlap

            if direction == "right" then
                primary_delta = candidate_cx - source_cx
                primary_gap = math.max(0, candidate.x - rect_right(source))
                overlap = overlap_1d(source.y, rect_bottom(source), candidate.y, rect_bottom(candidate))
                perpendicular_gap = overlap > epsilon and 0
                    or math.max(source.y - rect_bottom(candidate), candidate.y - rect_bottom(source), 0)
                perpendicular_center_delta = math.abs(candidate_cy - source_cy)
            elseif direction == "left" then
                primary_delta = source_cx - candidate_cx
                primary_gap = math.max(0, source.x - rect_right(candidate))
                overlap = overlap_1d(source.y, rect_bottom(source), candidate.y, rect_bottom(candidate))
                perpendicular_gap = overlap > epsilon and 0
                    or math.max(source.y - rect_bottom(candidate), candidate.y - rect_bottom(source), 0)
                perpendicular_center_delta = math.abs(candidate_cy - source_cy)
            elseif direction == "down" then
                primary_delta = candidate_cy - source_cy
                primary_gap = math.max(0, candidate.y - rect_bottom(source))
                overlap = overlap_1d(source.x, rect_right(source), candidate.x, rect_right(candidate))
                perpendicular_gap = overlap > epsilon and 0
                    or math.max(source.x - rect_right(candidate), candidate.x - rect_right(source), 0)
                perpendicular_center_delta = math.abs(candidate_cx - source_cx)
            else
                primary_delta = source_cy - candidate_cy
                primary_gap = math.max(0, source.y - rect_bottom(candidate))
                overlap = overlap_1d(source.x, rect_right(source), candidate.x, rect_right(candidate))
                perpendicular_gap = overlap > epsilon and 0
                    or math.max(source.x - rect_right(candidate), candidate.x - rect_right(source), 0)
                perpendicular_center_delta = math.abs(candidate_cx - source_cx)
            end

            if primary_delta > epsilon then
                local lane_penalty = overlap > epsilon and 0 or 1
                local weighted_distance = primary_gap + diagonal_weight * perpendicular_gap
                local center_distance = math.sqrt((candidate_cx - source_cx) ^ 2 + (candidate_cy - source_cy) ^ 2)
                local score = {
                    lane_penalty,
                    lane_penalty == 0 and primary_gap or weighted_distance,
                    perpendicular_center_delta,
                    center_distance,
                }

                if not best_score
                    or score_less(score, best_score)
                    or (not score_less(best_score, score) and stable_key_less(key, best_key))
                then
                    best_key = key
                    best_score = score
                end
            end
        end
    end

    return best_key, best_score
end

-- Distribute `total` pixels across positive weights so that:
--   * sizes sum to exactly `total`;
--   * every size is >= minimum whenever feasible;
--   * weights below the minimum threshold are pinned at exactly `minimum`.
-- When count × minimum exceeds total, falls back to an even split because the
-- constraint is physically unsatisfiable on that axis.
function Geometry.distribute(weights, total, minimum)
    local count = #weights
    local sizes = {}
    if count == 0 then
        return sizes
    end

    if count * minimum >= total then
        local even = total / count
        for index = 1, count do
            sizes[index] = even
        end
        return sizes
    end

    local order = {}
    for index = 1, count do
        order[index] = index
    end
    table.sort(order, function(a, b)
        if weights[a] == weights[b] then
            return a < b
        end
        return weights[a] < weights[b]
    end)

    local active_weight = 0
    for _, weight in ipairs(weights) do
        active_weight = active_weight + weight
    end

    local pinned = {}
    local active_space = total
    for step = 1, count - 1 do
        local index = order[step]
        local share = active_weight > 0 and active_space * weights[index] / active_weight or 0
        if share < minimum then
            pinned[index] = true
            sizes[index] = minimum
            active_space = active_space - minimum
            active_weight = active_weight - weights[index]
        else
            break
        end
    end

    local unpinned = {}
    local unpinned_weight = 0
    for index = 1, count do
        if not pinned[index] then
            unpinned[#unpinned + 1] = index
            unpinned_weight = unpinned_weight + weights[index]
        end
    end

    if #unpinned == 0 or unpinned_weight <= 0 then
        local even = total / count
        for index = 1, count do
            sizes[index] = even
        end
        return sizes
    end

    local assigned = 0
    for position, index in ipairs(unpinned) do
        if position == #unpinned then
            sizes[index] = active_space - assigned
        else
            local size = active_space * weights[index] / unpinned_weight
            sizes[index] = size
            assigned = assigned + size
        end
    end

    return sizes
end

-- Derive world-space tile rectangles from row/cell structure. Rows always span
-- the full canvas height (weights split it); cells always span the full canvas
-- width within their row. The canvas starts at world origin (0, 0).
function Geometry.derive_grid(rows, area, options)
    options = options or {}
    local width = math.max(1, area.w)
    local height = math.max(1, area.h)
    local min_width = math.max(options.min_width or 0, 0)
    local min_height = math.max(options.min_height or 0, 0)

    local row_weights = {}
    for index, row in ipairs(rows) do
        row_weights[index] = row.height and row.height > 0 and row.height or 1
    end
    local row_sizes = Geometry.distribute(row_weights, height, min_height)

    local tiles = {}
    local y = 0
    for index, row in ipairs(rows) do
        local cell_weights = {}
        for cell_index, cell in ipairs(row.cells) do
            cell_weights[cell_index] = cell.width and cell.width > 0 and cell.width or 1
        end
        local cell_sizes = Geometry.distribute(cell_weights, width, min_width)

        local x = 0
        for cell_index, cell in ipairs(row.cells) do
            tiles[cell.key] = {
                x = x,
                y = y,
                w = cell_sizes[cell_index],
                h = row_sizes[index],
                present = true,
            }
            x = x + cell_sizes[cell_index]
        end

        y = y + row_sizes[index]
    end

    return tiles
end

-- Best-effort horizontal alignment for cross-row insertions: returns the
-- insertion position (1..count+1) whose resulting left edge is closest to
-- target_left, using proportional widths as the estimate.
function Geometry.aligned_cell_index(cells, target_left, area_width)
    local count = #cells
    if count == 0 then
        return 1
    end

    local weight_total = 0
    local weights = {}
    for index, cell in ipairs(cells) do
        weights[index] = cell.width and cell.width > 0 and cell.width or 1
        weight_total = weight_total + weights[index]
    end

    local best_position = 1
    local best_distance = math.huge
    local prefix = 0
    for position = 1, count + 1 do
        local distance = math.abs(prefix - target_left)
        if distance < best_distance then
            best_distance = distance
            best_position = position
        end
        if position <= count then
            prefix = prefix + area_width * weights[position] / weight_total
        end
    end

    return best_position
end

function Geometry.reveal(viewport, rect, margin)
    margin = math.max(0, margin or 0)
    local x = viewport.x
    local y = viewport.y
    local margin_x = math.min(margin, math.max(0, (viewport.w - math.min(rect.w, viewport.w)) / 2))
    local margin_y = math.min(margin, math.max(0, (viewport.h - math.min(rect.h, viewport.h)) / 2))

    if rect.w + 2 * margin_x <= viewport.w then
        if rect.x < x + margin_x then
            x = rect.x - margin_x
        elseif rect_right(rect) > x + viewport.w - margin_x then
            x = rect_right(rect) + margin_x - viewport.w
        end
    elseif rect.w <= viewport.w then
        if rect.x < x then
            x = rect.x
        elseif rect_right(rect) > x + viewport.w then
            x = rect_right(rect) - viewport.w
        end
    else
        x = rect.x + rect.w / 2 - viewport.w / 2
    end

    if rect.h + 2 * margin_y <= viewport.h then
        if rect.y < y + margin_y then
            y = rect.y - margin_y
        elseif rect_bottom(rect) > y + viewport.h - margin_y then
            y = rect_bottom(rect) + margin_y - viewport.h
        end
    elseif rect.h <= viewport.h then
        if rect.y < y then
            y = rect.y
        elseif rect_bottom(rect) > y + viewport.h then
            y = rect_bottom(rect) - viewport.h
        end
    else
        y = rect.y + rect.h / 2 - viewport.h / 2
    end

    return x, y
end

function Geometry.assert_non_overlapping(tiles, epsilon)
    epsilon = epsilon or 0.001
    local keys = {}
    for key, tile in pairs(tiles) do
        if is_present(tile) then
            keys[#keys + 1] = key
        end
    end
    table.sort(keys, stable_key_less)

    for i = 1, #keys do
        for j = i + 1, #keys do
            if Geometry.intersects(tiles[keys[i]], tiles[keys[j]], epsilon) then
                return false, string.format("tiles %s and %s overlap", tostring(keys[i]), tostring(keys[j]))
            end
        end
    end

    return true
end

return Geometry
