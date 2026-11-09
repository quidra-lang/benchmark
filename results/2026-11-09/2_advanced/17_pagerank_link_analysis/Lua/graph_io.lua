local M = {}

function M.split(text, separator)
    local values, start = {}, 1
    while true do
        local position = text:find(separator, start, true)
        values[#values + 1] = text:sub(start, position and position - 1 or #text)
        if not position then return values end
        start = position + #separator
    end
end

function M.lines(path)
    local lines = {}
    for line in io.lines(path) do lines[#lines + 1] = line end
    return lines
end

function M.read()
    local pages, records, queries, settings = {}, {}, {}, {}
    for i, line in ipairs(M.lines("input/pages.csv")) do if i > 1 then
        local values = M.split(line, ",")
        pages[#pages + 1] = {id = tonumber(values[1]), host = values[2], title = values[3], words = M.split(values[3], " ")}
    end end
    table.sort(pages, function(a, b) return a.id < b.id end)
    for i, line in ipairs(M.lines("input/links.csv")) do if i > 1 then
        local values = M.split(line, ",")
        records[#records + 1] = {line = i, source = tonumber(values[1]), target = tonumber(values[2])}
    end end
    for i, line in ipairs(M.lines("input/queries.txt")) do
        local values = M.split(line, " | ")
        local seeds = M.split(values[2], " ")
        for j, value in ipairs(seeds) do seeds[j] = tonumber(value) end
        queries[i] = {number = i, words = M.split(values[1], " "), seeds = seeds}
    end
    for _, line in ipairs(M.lines("input/params.txt")) do
        local values = M.split(line, " ")
        local key = table.remove(values, 1)
        for i, value in ipairs(values) do values[i] = tonumber(value) end
        settings[key] = (key == "DAMPING_SWEEP" or key == "TRUSTED") and values or values[1]
    end
    return pages, records, queries, settings
end

return M
