local scoring = require("scoring")
local analysis = {}

function analysis.frequency(text)
    local result = {}
    for i = 1, 26 do
        result[i] = 0
    end
    for i = 1, #text do
        local position = string.byte(text, i) - 64
        result[position] = result[position] + 1
    end
    return result
end

function analysis.ioc(text)
    local length = #text
    if length < 2 then
        return 0
    end
    local sum = 0
    for _, count in ipairs(analysis.frequency(text)) do
        sum = sum + count * (count - 1)
    end
    return (100000 * sum) // (length * (length - 1))
end

function analysis.column(text, period, offset)
    local chars = {}
    for i = offset + 1, #text, period do
        chars[#chars + 1] = text:sub(i, i)
    end
    return table.concat(chars)
end

function analysis.column_iocs(text, period)
    local values = {}
    for i = 0, period - 1 do
        values[i + 1] = analysis.ioc(analysis.column(text, period, i))
    end
    return values
end

function analysis.average_ioc(text, period)
    local sum = 0
    for _, value in ipairs(analysis.column_iocs(text, period)) do
        sum = sum + value
    end
    return sum // period
end

local function gcd(first, second)
    while second ~= 0 do
        first, second = second, first % second
    end
    return first
end

function analysis.kasiski(text)
    local positions = {}
    for i = 1, #text - 2 do
        local triplet = text:sub(i, i + 2)
        if not positions[triplet] then
            positions[triplet] = {}
        end
        table.insert(positions[triplet], i)
    end
    local keys = {}
    for triplet, _ in pairs(positions) do
        keys[#keys + 1] = triplet
    end
    table.sort(keys)
    local repeats, all_gaps = {}, {}
    for _, triplet in ipairs(keys) do
        local points = positions[triplet]
        if #points >= 2 then
            local gaps, divisor = {}, 0
            for i = 2, #points do
                local gap = points[i] - points[i - 1]
                gaps[#gaps + 1] = gap
                all_gaps[#all_gaps + 1] = gap
                divisor = gcd(divisor, gap)
            end
            repeats[#repeats + 1] = {
                text = triplet, positions = points, gaps = gaps, gcd = divisor
            }
        end
    end
    return {repeats = repeats, gaps = all_gaps}
end

function analysis.kasiski_count(data, period)
    local result = 0
    for _, gap in ipairs(data.gaps) do
        if gap % period == 0 then
            result = result + 1
        end
    end
    return result
end

local function numbers(values)
    local result = {}
    for i, value in ipairs(values) do
        result[i] = tostring(value)
    end
    return table.concat(result, ",")
end

function analysis.period_table(text, maximum, data)
    local lines = {}
    for period = 1, maximum do
        local columns = analysis.column_iocs(text, period)
        local sum = 0
        for _, count in ipairs(columns) do
            sum = sum + count
        end
        lines[#lines + 1] = string.format("L=%d ioc=%d kasiski=%d cols=%s",
            period, sum // period, analysis.kasiski_count(data, period), numbers(columns))
    end
    return lines
end

function analysis.kasiski_table(data)
    local lines = {string.format("kasiski repeats=%d spacings=%d",
        #data.repeats, #data.gaps)}
    for _, item in ipairs(data.repeats) do
        lines[#lines + 1] = string.format("%s at=%s gaps=%s gcd=%d",
            item.text, numbers(item.positions), numbers(item.gaps), item.gcd)
    end
    return lines
end

function analysis.top_pairs(text, digraphs)
    local counts = {}
    local step = digraphs and 2 or 1
    for i = 1, #text - 1, step do
        local piece = text:sub(i, i + 1)
        counts[piece] = (counts[piece] or 0) + 1
    end
    local keys = {}
    for piece, _ in pairs(counts) do
        keys[#keys + 1] = piece
    end
    table.sort(keys, function(a, b)
        return counts[a] == counts[b] and a < b or counts[a] > counts[b]
    end)
    local result = {}
    for i = 1, math.min(10, #keys) do
        result[#result + 1] = keys[i] .. ":" .. counts[keys[i]]
    end
    return table.concat(result, " ")
end

local function percentage(count, total)
    local tenths = (2000 * count + total) // (2 * total)
    return string.format("%d.%d", tenths // 10, tenths % 10)
end

function analysis.report(job, source, text, mono, bi, maxlen)
    local data = analysis.kasiski(text)
    local counts, doubles, pair_doubles, distinct = analysis.frequency(text), 0, 0, 0
    for _, count in ipairs(counts) do
        if count > 0 then
            distinct = distinct + 1
        end
    end
    for i = 1, #text - 1 do
        if text:sub(i, i) == text:sub(i + 1, i + 1) then
            doubles = doubles + 1
            if i % 2 == 1 then
                pair_doubles = pair_doubles + 1
            end
        end
    end
    local result = {
        string.format("JOB %d ANALYZE source=%s", job, source),
        "letters=" .. #text,
        string.format("ioc=%d mono=%d bigram=%d",
            analysis.ioc(text), scoring.monogram(text, mono), scoring.bigram(text, bi)),
        string.format("doubles=%d pair_doubles=%d distinct=%d",
            doubles, pair_doubles, distinct)
    }
    for index, count in ipairs(counts) do
        result[#result + 1] = string.format("%s %d %s",
            scoring.upper(index - 1), count, percentage(count, #text))
    end
    result[#result + 1] = "bigrams " .. analysis.top_pairs(text, false)
    for _, line in ipairs(analysis.period_table(text, maxlen, data)) do
        result[#result + 1] = line
    end
    for _, line in ipairs(analysis.kasiski_table(data)) do
        result[#result + 1] = line
    end
    return result
end

return analysis
