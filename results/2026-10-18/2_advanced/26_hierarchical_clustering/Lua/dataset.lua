local M = {}

function M.lines(path)
    local lines = {}
    for line in io.lines(path) do lines[#lines + 1] = line end
    return lines
end

function M.split(line, separator)
    local fields = {}
    for field in (line .. separator):gmatch("(.-)" .. separator) do
        fields[#fields + 1] = field
    end
    return fields
end

function M.read_observations(path)
    local lines = M.lines(path)
    local header = M.split(lines[1], ",")
    local names, observations = {}, {}
    for i = 3, #header do names[#names + 1] = header[i] end
    for i = 2, #lines do
        local fields = M.split(lines[i], ",")
        local values = {}
        for f = 3, #fields do values[#values + 1] = tonumber(fields[f]) end
        observations[#observations + 1] = {ident = fields[1], label = fields[2], values = values}
    end
    return names, observations
end

function M.read_settings(path)
    local entries = {}
    for _, line in ipairs(M.lines(path)) do
        local fields = M.split(line, " ")
        local keyword = table.remove(fields, 1)
        entries[keyword] = fields
    end
    local function numbers(values)
        local result = {}
        for _, value in ipairs(values) do result[#result + 1] = tonumber(value) end
        return result
    end
    return {
        distance = entries.DISTANCE[1], standardize = entries.STANDARDIZE[1],
        linkages = entries.LINKAGES, cut_heights = numbers(entries.CUT_HEIGHTS),
        cut_counts = numbers(entries.CUT_K),
        inconsistency_depth_text = entries.INCONSISTENCY[1],
        inconsistency_depth = #entries.INCONSISTENCY[1] > 3 and 120 or math.min(120, tonumber(entries.INCONSISTENCY[1])),
        inconsistency_count = tonumber(entries.INCONSISTENCY[2]),
        gap_max_k = tonumber(entries.GAP_MAX_K[1]), list_size = tonumber(entries.LIST_SIZE[1]),
        width = tonumber(entries.DENDROGRAM_WIDTH[1]), compare_linkage = entries.COMPARE_LINKAGE[1],
        replicates = tonumber(entries.SUBSAMPLES[1]), percent = tonumber(entries.SUBSAMPLES[2]),
        seed = tonumber(entries.SUBSAMPLES[3]), refine_iterations = tonumber(entries.REFINE_ITERATIONS[1])
    }
end

function M.write_lines(path, lines)
    local file = assert(io.open(path, "w"))
    for _, line in ipairs(lines) do file:write(line, "\n") end
    file:close()
end

return M
