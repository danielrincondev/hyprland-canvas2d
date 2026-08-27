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

function Geometry.edge_candidates(tiles, source_key, direction, epsilon)
    epsilon = epsilon or 0.001
    local source = tiles[source_key]
    if not is_present(source) or not DIRECTIONS[direction] then
        return {}, nil
    end

    local candidates = {}
    local nearest_gap

    for key, candidate in pairs(tiles) do
        if key ~= source_key and is_present(candidate) then
            local overlap
            local gap

            if direction == "right" then
                overlap = overlap_1d(source.y, rect_bottom(source), candidate.y, rect_bottom(candidate))
                gap = candidate.x - rect_right(source)
            elseif direction == "left" then
                overlap = overlap_1d(source.y, rect_bottom(source), candidate.y, rect_bottom(candidate))
                gap = source.x - rect_right(candidate)
            elseif direction == "down" then
                overlap = overlap_1d(source.x, rect_right(source), candidate.x, rect_right(candidate))
                gap = candidate.y - rect_bottom(source)
            else
                overlap = overlap_1d(source.x, rect_right(source), candidate.x, rect_right(candidate))
                gap = source.y - rect_bottom(candidate)
            end

            if overlap > epsilon and gap >= -epsilon then
                gap = math.max(0, gap)
                if nearest_gap == nil or gap < nearest_gap - epsilon then
                    nearest_gap = gap
                    candidates = { key }
                elseif math.abs(gap - nearest_gap) <= epsilon then
                    candidates[#candidates + 1] = key
                end
            end
        end
    end

    table.sort(candidates, stable_key_less)
    return candidates, nearest_gap
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
