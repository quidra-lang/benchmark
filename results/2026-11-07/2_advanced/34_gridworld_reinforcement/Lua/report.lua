local M = {}
function M.fixed(value)
    return string.format("%s%d.%04d", value < 0 and "-" or "", math.abs(value) // 10000, math.abs(value) % 10000)
end
function M.average(total, count)
    return M.fixed(10000 * total // count)
end
function M.cell(world, cell)
    return (cell // world.cols) .. "," .. (cell % world.cols)
end
function M.cells(world, cells)
    local values = {}
    for i, cell in ipairs(cells) do
        values[i] = M.cell(world, cell)
    end
    return table.concat(values, " ")
end
function M.grid(world, fields, separator)
    local lines = {}
    for row = 0, world.rows - 1 do
        local parts = {}
        for column = 0, world.cols - 1 do
            local cell = row * world.cols + column
            local state = world.state_index[cell + 1]
            parts[#parts + 1] = state and fields[state] or world.kinds:sub(cell + 1, cell + 1)
        end
        lines[#lines + 1] = table.concat(parts, separator)
    end
    return lines
end
function M.values(world, values)
    local fields = {}
    for i, value in ipairs(values) do
        fields[i] = M.fixed(value)
    end
    return M.grid(world, fields, " ")
end
function M.policy(world, policy)
    local fields = {}
    for i, action in ipairs(policy) do
        fields[i] = ("^>v<"):sub(action + 1, action + 1)
    end
    return M.grid(world, fields, "")
end
function M.q_rows(world, name, q, visits)
    local result = {}
    for state, cell in ipairs(world.states) do
        for action = 0, 3 do
            result[#result + 1] = table.concat({name, cell // world.cols, cell % world.cols, ("NESW"):sub(action + 1, action + 1), M.fixed(q[state][action + 1]), visits and visits[state][action + 1] or "-"}, ",")
        end
    end
    return result
end
function M.join_parts(parts)
    local lines = {}
    for i, part in ipairs(parts) do
        if i > 1 then
            lines[#lines + 1] = ""
        end
        for _, line in ipairs(part) do
            lines[#lines + 1] = line
        end
    end
    return lines
end
function M.write(name, lines)
    local file = assert(io.open("output/" .. name, "w"))
    for _, line in ipairs(lines) do
        file:write(line, "\n")
    end
    file:close()
end
return M
