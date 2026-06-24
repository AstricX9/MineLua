local math = require('math')
local string = require('string')
local table = require('table')

local json = {}

local function create_set(...)
    local res = {}
    for i = 1, select("#", ...) do
        res[select(i, ...)] = true
    end
    return res
end

local space_chars  = create_set(' ', '\t', '\r', '\n')
local delim_chars  = create_set(' ', '\t', '\r', '\n', ']', '}', ',')
local escape_chars = { ['\\'] = '\\', ['"'] = '"', ['b'] = '\b', ['f'] = '\f', ['n'] = '\n', ['r'] = '\r', ['t'] = '\t' }

local function decode_error(str, idx, msg)
    error(string.format("JSON Decode Error: %s at %d", msg, idx))
end

local function skip_spaces(str, idx)
    while space_chars[str:sub(idx, idx)] do
        idx = idx + 1
    end
    return idx
end

local function decode_string(str, idx)
    local res = ""
    idx = idx + 1
    local start = idx
    while true do
        local c = str:sub(idx, idx)
        if c == '"' then
            res = res .. str:sub(start, idx - 1)
            return res, idx + 1
        elseif c == '\\' then
            res = res .. str:sub(start, idx - 1)
            idx = idx + 1
            local esc = str:sub(idx, idx)
            if escape_chars[esc] then
                res = res .. escape_chars[esc]
            else
                decode_error(str, idx, "Invalid escape sequence")
            end
            start = idx + 1
        elseif c == "" then
            decode_error(str, idx, "Unterminated string")
        end
        idx = idx + 1
    end
end

local function decode_number(str, idx)
    local start = idx
    while not delim_chars[str:sub(idx, idx)] and str:sub(idx, idx) ~= "" do
        idx = idx + 1
    end
    local num = tonumber(str:sub(start, idx - 1))
    if not num then decode_error(str, start, "Invalid number") end
    return num, idx
end

local function decode_value(str, idx)
    idx = skip_spaces(str, idx)
    local c = str:sub(idx, idx)
    if c == '{' then
        local res = {}
        idx = skip_spaces(str, idx + 1)
        if str:sub(idx, idx) == '}' then return res, idx + 1 end
        while true do
            if str:sub(idx, idx) ~= '"' then decode_error(str, idx, "Expected string key") end
            local key
            key, idx = decode_string(str, idx)
            idx = skip_spaces(str, idx)
            if str:sub(idx, idx) ~= ':' then decode_error(str, idx, "Expected ':'") end
            local val
            val, idx = decode_value(str, idx + 1)
            if res[key] ~= nil then
                if type(res[key]) == "table" and res[key].__json_duplicate_keys then
                    res[key][#res[key] + 1] = val
                else
                    res[key] = {res[key], val, __json_duplicate_keys = true}
                end
            else
                res[key] = val
            end
            idx = skip_spaces(str, idx)
            local next_c = str:sub(idx, idx)
            if next_c == '}' then
                return res, idx + 1
            elseif next_c == ',' then
                idx = skip_spaces(str, idx + 1)
            else
                decode_error(str, idx, "Expected '}' or ','")
            end
        end
    elseif c == '[' then
        local res = {}
        idx = skip_spaces(str, idx + 1)
        if str:sub(idx, idx) == ']' then return res, idx + 1 end
        local i = 1
        while true do
            local val
            val, idx = decode_value(str, idx)
            res[i] = val
            i = i + 1
            idx = skip_spaces(str, idx)
            local next_c = str:sub(idx, idx)
            if next_c == ']' then
                return res, idx + 1
            elseif next_c == ',' then
                idx = skip_spaces(str, idx + 1)
            else
                decode_error(str, idx, "Expected ']' or ','")
            end
        end
    elseif c == '"' then
        return decode_string(str, idx)
    elseif c == 't' and str:sub(idx, idx + 3) == 'true' then
        return true, idx + 4
    elseif c == 'f' and str:sub(idx, idx + 4) == 'false' then
        return false, idx + 5
    elseif c == 'n' and str:sub(idx, idx + 3) == 'null' then
        return nil, idx + 4
    else
        return decode_number(str, idx)
    end
end

function json.decode(str)
    local val, idx = decode_value(str, 1)
    idx = skip_spaces(str, idx)
    if idx <= #str then decode_error(str, idx, "Trailing garbage") end
    return val
end

return json
