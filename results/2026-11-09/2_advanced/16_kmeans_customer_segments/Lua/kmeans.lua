local M = {}

function M.distance(first, second)
    local total = 0.0
    for i, value in ipairs(first) do local delta = value - second[i]; total = total + delta * delta end
    return total
end

function M.mean(points)
    local totals = {}
    for i = 1, #points[1] do totals[i] = 0.0 end
    for _, point in ipairs(points) do for i, value in ipairs(point) do totals[i] = totals[i] + value end end
    for i, total in ipairs(totals) do totals[i] = total / #points end
    return totals
end

function M.groups(labels, k)
    local groups = {}
    for j = 1, k do groups[j] = {} end
    for i, label in ipairs(labels) do table.insert(groups[label], i) end
    return groups
end

function M.center(points, labels, label)
    local selected = {}
    for i, point in ipairs(points) do if labels[i] == label then selected[#selected + 1] = point end end
    return M.mean(selected)
end

function M.centers(points, labels, k)
    local centers = {}
    for j = 1, k do centers[j] = M.center(points, labels, j) end
    return centers
end

function M.assign(points, centers)
    local labels, errors = {}, {}
    for i, point in ipairs(points) do
        local chosen, best = 1, M.distance(point, centers[1])
        for j = 2, #centers do
            local distance = M.distance(point, centers[j])
            if distance < best then chosen, best = j, distance end
        end
        labels[i], errors[i] = chosen, best
    end
    return labels, errors
end

function M.refill(labels, errors, k)
    local sizes, reseeds = {}, 0
    for j = 1, k do sizes[j] = 0 end
    for _, label in ipairs(labels) do sizes[label] = sizes[label] + 1 end
    for j = 1, k do
        if sizes[j] == 0 then
            local chosen
            for i, label in ipairs(labels) do
                if sizes[label] >= 2 and (not chosen or errors[i] > errors[chosen]) then chosen = i end
            end
            sizes[labels[chosen]] = sizes[labels[chosen]] - 1
            sizes[j], labels[chosen], errors[chosen] = sizes[j] + 1, j, 0.0
            reseeds = reseeds + 1
        end
    end
    return reseeds
end

function M.sse(points, labels, centers)
    local total = 0.0
    for i, point in ipairs(points) do total = total + M.distance(point, centers[labels[i]]) end
    return total
end

function M.lloyd(points, initial, limit)
    local labels, errors = M.assign(points, initial)
    local iterations, reseeds, converged, centers = 0, 0, false, initial
    while iterations < limit do
        reseeds = reseeds + M.refill(labels, errors, #initial)
        centers = M.centers(points, labels, #initial)
        iterations = iterations + 1
        local updated
        updated, errors = M.assign(points, centers)
        converged = true
        for i, label in ipairs(labels) do if updated[i] ~= label then converged = false; break end end
        labels = updated
        if converged then break end
    end
    reseeds = reseeds + M.refill(labels, errors, #initial)
    centers = M.centers(points, labels, #initial)
    return {labels = labels, centers = centers, iterations = iterations, reseeds = reseeds, converged = converged, sse = M.sse(points, labels, centers)}
end

return M
