local Test = {
    cases = {},
}

local function render(value)
    if type(value) == "table" then
        local parts = {}
        for key, item in pairs(value) do
            parts[#parts + 1] = tostring(key) .. "=" .. render(item)
        end
        table.sort(parts)
        return "{" .. table.concat(parts, ",") .. "}"
    end
    return tostring(value)
end

function Test.case(name, fn)
    Test.cases[#Test.cases + 1] = { name = name, fn = fn }
end

function Test.equal(actual, expected, message)
    if actual ~= expected then
        error((message and message .. ": " or "") .. "expected " .. render(expected) .. ", got " .. render(actual), 2)
    end
end

function Test.near(actual, expected, epsilon, message)
    epsilon = epsilon or 0.000001
    if math.abs(actual - expected) > epsilon then
        error((message and message .. ": " or "") .. "expected " .. render(expected) .. ", got " .. render(actual), 2)
    end
end

function Test.truthy(value, message)
    if not value then
        error(message or "expected truthy value", 2)
    end
end

function Test.falsy(value, message)
    if value then
        error(message or "expected falsy value", 2)
    end
end

function Test.match(value, pattern, message)
    if type(value) ~= "string" or not value:match(pattern) then
        error((message and message .. ": " or "") .. "expected " .. render(value) .. " to match " .. pattern, 2)
    end
end

function Test.run()
    local passed = 0
    for _, case in ipairs(Test.cases) do
        local ok, failure = xpcall(case.fn, debug.traceback)
        if not ok then
            io.stderr:write("FAIL ", case.name, "\n", failure, "\n")
            os.exit(1)
        end
        passed = passed + 1
        io.write("PASS ", case.name, "\n")
    end
    io.write(string.format("%d tests passed\n", passed))
end

return Test
