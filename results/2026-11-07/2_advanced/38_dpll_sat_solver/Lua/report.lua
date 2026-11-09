local M = {}
function M.named(items)
    local fields = {}
    for i, item in ipairs(items) do
        fields[i] = item[1] .. "=" .. tostring(item[2])
    end
    return table.concat(fields, " ")
end
function M.number_list(values)
    local fields = {}
    for i, value in ipairs(values) do
        fields[i] = tostring(value)
    end
    return #fields > 0 and table.concat(fields, ",") or "-"
end
function M.frequency(values)
    local counts, order, fields = {}, {}, {}
    for _, value in ipairs(values) do
        if not counts[value] then
            order[#order + 1] = value
            counts[value] = 0
        end
        counts[value] = counts[value] + 1
    end
    table.sort(order)
    for _, value in ipairs(order) do
        fields[#fields + 1] = value .. ":" .. counts[value]
    end
    return #fields > 0 and table.concat(fields, ",") or "-"
end
function M.queens_board(columns)
    local lines = {}
    for i, column in ipairs(columns) do
        lines[i] = string.rep(".", column - 1) .. "Q" .. string.rep(".", #columns - column)
    end
    return lines
end
function M.save_lines(filename, lines)
    local file = assert(io.open("output/" .. filename, "w"))
    for _, line in ipairs(lines) do
        file:write(line, "
")
    end
    file:close()
end
function M.save_paragraphs(filename, paragraphs)
    local lines = {}
    for i, paragraph in ipairs(paragraphs) do
        if i > 1 then
            lines[#lines + 1] = ""
        end
        for _, line in ipairs(paragraph) do
            lines[#lines + 1] = line
        end
    end
    M.save_lines(filename, lines)
end
return M
