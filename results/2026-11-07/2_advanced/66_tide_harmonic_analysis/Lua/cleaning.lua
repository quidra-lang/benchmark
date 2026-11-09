local M = {}
local function median(a)
    table.sort(a)
    local n = #a
    if n % 2 == 1 then return a[(n + 1) // 2] end
    return (a[n // 2] + a[n // 2 + 1]) / 2
end
function M.prepare(record, minimum)
    local times = {}
    for t, v in pairs(record.values) do if v ~= false then times[#times + 1] = t end end
    table.sort(times)
    local c = {first = times[1], last = times[#times], numeric_times = times, values = record.values,
        rows = record.rows, reasons = {}, flat_runs = {}, candidates = {}}
    c.length = c.last - c.first
    for t = c.first, c.last do
        if record.values[t] == nil then c.reasons[t] = 'absent'
        elseif record.values[t] == false then c.reasons[t] = 'na' end
    end
    local i = 1
    while i <= #times do
        local a, b = times[i], times[i]
        while i < #times and times[i + 1] == b + 1 and record.millimetres[times[i + 1]] == record.millimetres[a] do
            i = i + 1; b = times[i]
        end
        if b - a + 1 >= minimum then
            c.flat_runs[#c.flat_runs + 1] = {start = a, finish = b, value = record.values[a]}
            for t = a + 1, b do c.reasons[t] = 'flat' end
        end
        i = i + 1
    end
    for _, t in ipairs(times) do if not c.reasons[t] then c.candidates[#c.candidates + 1] = t end end
    return c
end
function M.spikes(c, residuals, s)
    c.spikes, c.tested, c.usable, c.gaps = {}, 0, {}, {}
    local lo, hi = 1, 0
    for _, t in ipairs(c.candidates) do
        while lo <= #c.candidates and c.candidates[lo] < t - s.spike_window do lo = lo + 1 end
        while hi < #c.candidates and c.candidates[hi + 1] <= t + s.spike_window do hi = hi + 1 end
        if hi - lo + 1 >= s.spike_minimum then
            c.tested = c.tested + 1
            local neighbors = {}
            for j = lo, hi do neighbors[#neighbors + 1] = residuals[c.candidates[j]] end
            local center = median(neighbors)
            local deviations = {}
            for j, v in ipairs(neighbors) do deviations[j] = math.abs(v - center) end
            local mad = median(deviations)
            local limit = math.max(s.spike_factor * 1.4826 * mad, s.spike_floor)
            if math.abs(residuals[t] - center) > limit then
                c.reasons[t] = 'spike'
                c.spikes[#c.spikes + 1] = {time = t, value = c.values[t], residual = residuals[t], median = center, mad = mad, limit = limit}
            end
        end
    end
    for _, t in ipairs(c.candidates) do if not c.reasons[t] then c.usable[#c.usable + 1] = t end end
    local t = c.first
    while t <= c.last do
        if not c.reasons[t] then t = t + 1 else
            local a, cause = t, c.reasons[t]
            while t < c.last and c.reasons[t + 1] do
                t = t + 1
                if c.reasons[t] ~= cause then cause = 'mixed' end
            end
            c.gaps[#c.gaps + 1] = {start = a, finish = t, cause = cause}
            t = t + 1
        end
    end
end
return M
