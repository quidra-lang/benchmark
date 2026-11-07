local M = {}
function M.copy(values)
    local result = {}
    for i, value in ipairs(values) do result[i] = value end
    return result
end
function M.local_event(process, own)
    process.lamport = process.lamport + 1
    process.vector[own] = process.vector[own] + 1
end
function M.receive_event(process, own, sending)
    process.lamport = math.max(process.lamport, sending.lamport) + 1
    for i, value in ipairs(sending.vector) do process.vector[i] = math.max(process.vector[i], value) end
    process.vector[own] = process.vector[own] + 1
end
function M.less_equal(first, second)
    for i, value in ipairs(first) do if value > second[i] then return false end end
    return true
end
function M.before(first, second)
    local different = false
    for i, value in ipairs(first) do
        if value > second[i] then return false end
        if value ~= second[i] then different = true end
    end
    return different
end
function M.relation(first, second)
    if M.before(first, second) then return '->' end
    if M.before(second, first) then return '<-' end
    return '||'
end
function M.deliverable(stamp, broadcast, source)
    for i, value in ipairs(stamp) do
        if i == source then
            if value ~= broadcast[i] + 1 then return false end
        elseif value > broadcast[i] then return false end
    end
    return true
end
function M.missing(stamp, broadcast, source)
    local result = {}
    for i, value in ipairs(stamp) do
        if value > broadcast[i] + (i == source and 1 or 0) then result[#result + 1] = i end
    end
    return result
end
function M.text(vector)
    local result = {}
    for i, value in ipairs(vector) do result[i] = tostring(value) end
    return table.concat(result, ',')
end
return M
