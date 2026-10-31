local M = {}
function M.display_line(pieces, slack, alignment, last)
    local displayed = {}
    for i, piece in ipairs(pieces) do
        displayed[i] = piece:gsub("~", " ")
    end
    local text = table.concat(displayed, " ")
    if slack <= 0 then
        return text
    end
    local gaps = #pieces - 1
    if alignment == "justify" and not last and gaps > 0 then
        text = displayed[1]
        for i = 2, #displayed do
            local spaces = slack // gaps + 1 + (i - 2 < slack % gaps and 1 or 0)
            text = text .. string.rep(" ", spaces) .. displayed[i]
        end
        return text
    elseif alignment == "right" then
        return string.rep(" ", slack) .. text
    elseif alignment == "center" then
        return string.rep(" ", slack // 2) .. text
    end
    return text
end
function M.format_table(rows, columns, caption, number)
    local widths = {}
    for i = 1, #columns do
        widths[i] = 0
        for _, row in ipairs(rows) do
            widths[i] = math.max(widths[i], #row[i])
        end
    end
    local lines = {}
    if caption ~= "" then
        lines[#lines + 1] = "Table " .. number .. ". " .. caption
    end
    for index, row in ipairs(rows) do
        local cells = {}
        for i, text in ipairs(row) do
            local missing, alignment = widths[i] - #text, columns:sub(i, i)
            if alignment == "l" then
                cells[i] = text .. string.rep(" ", missing)
            elseif alignment == "r" then
                cells[i] = string.rep(" ", missing) .. text
            else
                cells[i] = string.rep(" ", missing // 2) .. text .. string.rep(" ", missing - missing // 2)
            end
        end
        lines[#lines + 1] = (table.concat(cells, " | "):gsub(" +$", ""))
        if index == 1 then
            local rule = {}
            for i, width in ipairs(widths) do
                rule[i] = string.rep("-", width)
            end
            lines[#lines + 1] = table.concat(rule, "-+-")
        end
    end
    return lines
end
function M.running_head(fields, values, width, serial)
    local expanded = {}
    for i, field in ipairs(fields) do
        for _, name in ipairs({"page", "pages", "chapter", "section"}) do
            field = field:gsub("{" .. name .. "}", function() return values[name] end)
        end
        expanded[i] = field
    end
    if serial % 2 == 0 then
        expanded[1], expanded[3] = expanded[3], expanded[1]
    end
    local line = {}
    for i = 1, width do
        line[i] = " "
    end
    local starts = {0, (width - #expanded[2]) // 2, width - #expanded[3]}
    for i, text in ipairs(expanded) do
        for position = 1, #text do
            line[starts[i] + position] = text:sub(position, position)
        end
    end
    return (table.concat(line):gsub(" +$", ""))
end
function M.pages_lines(pages)
    local lines = {}
    for _, page in ipairs(pages) do
        lines[#lines + 1] = "--- page " .. page.serial .. " ---"
        lines[#lines + 1] = page.header
        lines[#lines + 1] = ""
        for _, text in ipairs(page.body) do
            lines[#lines + 1] = text
        end
        lines[#lines + 1] = ""
        lines[#lines + 1] = page.footer
    end
    return lines
end
return M
