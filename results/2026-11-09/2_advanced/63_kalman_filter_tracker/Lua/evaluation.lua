local A = require("association")
local E = {}
function E.squared_distance(a, b) local dx, dy = a[1] - b[1], a[2] - b[2]; return dx * dx + dy * dy end
function E.distance(a, b) return math.sqrt(E.squared_distance(a, b)) end
function E.ospa(first, second, cutoff)
    if #first == 0 and #second == 0 then return 0.0 end
    if #first == 0 or #second == 0 then return cutoff end
    local smaller, larger = first, second
    if #first > #second then smaller, larger = second, first end
    local costs = {}
    for i, point in ipairs(smaller) do
        costs[i] = {}
        for j, other in ipairs(larger) do local clipped = math.min(cutoff, E.distance(point, other)); costs[i][j] = clipped * clipped end
    end
    local cost = 0.0
    for _, pair in ipairs(A.minimum_matching(costs)) do cost = cost + costs[pair[1]][pair[2]] end
    return math.sqrt((cost + cutoff * cutoff * (#larger - #smaller)) / #larger)
end
function E.continuity(labels)
    local result = { covered = 0, breaks = 0, swaps = 0 }
    local groups, previous_label, previous_covered = 0, nil, false
    for offset, label in ipairs(labels) do
        if not label then previous_covered = false
        else
            result.covered = result.covered + 1
            if result.delay == nil then result.delay = offset - 1 end
            if not previous_covered then groups = groups + 1 end
            if previous_label and label ~= previous_label then result.swaps = result.swaps + 1 end
            previous_label, previous_covered = label, true
        end
    end
    result.breaks = math.max(0, groups - 1)
    return result
end
function E.real(value)
    if value == nil or value == false then return "-" end
    local text = string.format("%.4f", value)
    return text:sub(1, 1) == "-" and tonumber(text) == 0 and text:sub(2) or text
end
return E
