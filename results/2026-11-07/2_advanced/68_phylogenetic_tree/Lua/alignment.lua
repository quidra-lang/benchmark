local M = {bases = 'ACGT', sets = {A = 1, C = 2, G = 4, T = 8, R = 5, Y = 10, S = 6, W = 9, K = 12, M = 3,
    B = 14, D = 13, H = 11, V = 7, N = 15, ['-'] = 15}, base = {A = true, C = true, G = true, T = true}}
function M.read()
    local out, current, line_number = {}, nil, 0
    for line in io.lines('input/alignment.fasta') do
        line_number = line_number + 1
        if line:sub(1, 1) == '>' then
            current = {line = line_number, name = line:sub(2):match('^([^ ]+)'), pieces = {}}; out[#out + 1] = current
        else current.pieces[#current.pieces + 1] = line end
    end
    for _, record in ipairs(out) do record.sequence = table.concat(record.pieces):upper(); record.pieces = nil end
    return out
end
function M.patterns(sequences)
    local out = {patterns = {}, columns = {}, weights = {}, encoded = {}}
    local indexes = {}
    for column = 1, #sequences[1] do
        local chars = {}; for i, sequence in ipairs(sequences) do chars[i] = sequence:sub(column, column) end
        local pattern = table.concat(chars)
        local index = indexes[pattern]
        if not index then
            index = #out.patterns + 1; indexes[pattern] = index; out.patterns[index] = pattern; out.weights[index] = 0
            out.encoded[index] = {}; for i, c in ipairs(chars) do out.encoded[index][i] = M.sets[c] end
        end
        out.columns[column] = index; out.weights[index] = out.weights[index] + 1
    end
    return out
end
function M.classify(sequences)
    local totals = {constant = 0, variable = 0, informative = 0, gapped = 0, empty = 0}
    for column = 1, #sequences[1] do
        local counts, gapped = {}, false
        for _, s in ipairs(sequences) do
            local c = s:sub(column, column)
            if M.base[c] then counts[c] = (counts[c] or 0) + 1 end
            if c == '-' then gapped = true end
        end
        local kinds, repeated = 0, 0
        for _, n in pairs(counts) do kinds = kinds + 1; if n >= 2 then repeated = repeated + 1 end end
        local kind = kinds == 0 and 'empty' or (kinds == 1 and 'constant' or 'variable')
        totals[kind] = totals[kind] + 1
        if repeated >= 2 then totals.informative = totals.informative + 1 end
        if gapped then totals.gapped = totals.gapped + 1 end
    end
    return totals
end
return M
