local LITERAL_DOLLAR = "\1"
local ESCAPES = { ["\\"] = "\\", ['"'] = '"', n = "\n", t = "\t", ["$"] = LITERAL_DOLLAR }

local function fail(line, code, message)
    if line.error == nil then
        line.error = { code = code, message = message }
    end
end

local function logical_lines(physical_lines)
    local lines = {}
    local index = 1
    while index <= #physical_lines do
        local line = { number = index, segments = {} }
        local source = physical_lines[index]
        index = index + 1
        local position = 1
        local quoted = false
        local current = {}
        while position <= #source do
            local char = source:sub(position, position)
            if char == "\\" and position == #source then
                source = physical_lines[index]:match("^ *(.*)$")
                index = index + 1
                position = 1
            elseif quoted and char == "\\" then
                local follower = source:sub(position + 1, position + 1)
                if ESCAPES[follower] then
                    table.insert(current, ESCAPES[follower])
                else
                    fail(line, "E_ESCAPE", "invalid escape sequence \\" .. follower)
                end
                position = position + 2
            elseif char == '"' then
                table.insert(line.segments, table.concat(current))
                current = {}
                quoted = not quoted
                position = position + 1
            elseif not quoted and (char == ";" or char == "#") then
                break
            else
                table.insert(current, char)
                position = position + 1
            end
        end
        if quoted then
            fail(line, "E_UNTERMINATED", "unterminated string")
        end
        table.insert(line.segments, table.concat(current))
        table.insert(lines, line)
    end
    return lines
end

return { LITERAL_DOLLAR = LITERAL_DOLLAR, logical_lines = logical_lines }
