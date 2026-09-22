-- Private, per-compositor reload state. Length-prefixed data, never Lua code.
local Session = {}
local MAGIC = "grid-session-v1\n"
local LIMIT = 5 * 1024 * 1024

local function finite(n)
    return type(n) == "number" and n == n and n ~= math.huge and n ~= -math.huge
end

local function encode(value)
    local kind = type(value)
    if kind == "string" then return "s" .. #value .. ":" .. value end
    if kind == "number" then
        assert(finite(value))
        return "n" .. string.format("%.17g", value) .. ";"
    end
    if kind == "boolean" then return value and "b1" or "b0" end
    assert(kind == "table", "unsupported session value")
    local entries, count = {}, 0
    for key, item in pairs(value) do
        count = count + 1
        entries[#entries + 1] = encode(key) .. encode(item)
    end
    return "t" .. count .. ":" .. table.concat(entries)
end

function Session.encode(value)
    return MAGIC .. encode(value)
end

function Session.decode(data)
    assert(#data <= LIMIT and data:sub(1, #MAGIC) == MAGIC, "invalid session header")
    local offset = #MAGIC + 1
    local function parse(depth)
        assert(depth < 32 and offset <= #data, "invalid session nesting")
        local kind = data:sub(offset, offset)
        offset = offset + 1
        if kind == "b" then
            local b = data:sub(offset, offset)
            assert(b == "0" or b == "1")
            offset = offset + 1
            return b == "1"
        end
        local ending = assert(data:find(kind == "n" and ";" or ":", offset, true))
        local value = tonumber(data:sub(offset, ending - 1))
        assert(finite(value), "invalid session number")
        offset = ending + 1
        if kind == "n" then return value end
        assert(value >= 0 and value % 1 == 0 and value <= LIMIT, "invalid session length")
        if kind == "s" then
            assert(offset + value - 1 <= #data, "truncated session string")
            local result = data:sub(offset, offset + value - 1)
            offset = offset + value
            return result
        end
        assert(kind == "t" and value <= 10000, "invalid session table")
        local result = {}
        for _ = 1, value do
            local key = parse(depth + 1)
            assert(type(key) == "number" or type(key) == "string", "invalid session key")
            result[key] = parse(depth + 1)
        end
        return result
    end
    local result = parse(0)
    assert(offset == #data + 1, "trailing session data")
    return result
end

function Session.path()
    local runtime = os.getenv("XDG_RUNTIME_DIR")
    if not runtime then return end
    -- A verify-config process may inherit the live instance's environment.
    -- PID plus process start time isolates it and prevents PID-reuse restores.
    local file = io.open("/proc/self/stat", "r")
    if not file then return end
    local stat = file:read("*a")
    file:close()
    local pid, fields = stat:match("^(%d+) %b() (.*)$")
    local tokens = {}
    for token in (fields or ""):gmatch("%S+") do tokens[#tokens + 1] = token end
    if pid and tokens[20] and tokens[20]:match("^%d+$") then
        return runtime .. "/grid-layout-" .. pid .. "-" .. tokens[20] .. ".state"
    end
end

function Session.read(path)
    if not path then return end
    local file = io.open(path, "rb")
    if not file then return end
    local data = file:read(LIMIT + 1)
    file:close()
    os.remove(path)
    local ok, value = pcall(Session.decode, data)
    if ok then return value end
end

function Session.write(path, value)
    if not path then return end
    local data = Session.encode(value)
    assert(#data <= LIMIT, "grid session is too large")
    local file = assert(io.open(path .. ".tmp", "wb"))
    assert(file:write(data))
    assert(file:close())
    assert(os.rename(path .. ".tmp", path))
end

return Session
