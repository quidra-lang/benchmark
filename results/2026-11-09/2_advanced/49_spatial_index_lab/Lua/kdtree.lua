local M = {}
function M.less(first, second, axis)
    local a, b = axis == 0 and first.x or first.y, axis == 0 and second.x or second.y
    if a ~= b then
        return a < b
    end
    a, b = axis == 0 and first.y or first.x, axis == 0 and second.y or second.x
    if a ~= b then
        return a < b
    end
    return first.id < second.id
end
local function node(point, axis)
    return {point = point, axis = axis}
end
function M.build(points, depth)
    depth = depth or 0
    if #points == 0 then
        return nil
    end
    local axis, ordered = depth % 2, {table.unpack(points)}
    table.sort(ordered, function(a, b) return M.less(a, b, axis) end)
    local middle, left, right = #ordered // 2 + 1, {}, {}
    for i = 1, middle - 1 do
        left[#left + 1] = ordered[i]
    end
    for i = middle + 1, #ordered do
        right[#right + 1] = ordered[i]
    end
    local root = node(ordered[middle], axis)
    root.left, root.right = M.build(left, depth + 1), M.build(right, depth + 1)
    return root
end
function M.insert(root, point)
    if not root then
        return node(point, 0)
    end
    local current = root
    while true do
        local side = M.less(point, current.point, current.axis) and "left" or "right"
        if not current[side] then
            current[side] = node(point, 1 - current.axis)
            return root
        end
        current = current[side]
    end
end
function M.minimum(root, axis)
    local pending, best = {root}, nil
    while #pending > 0 do
        local current = table.remove(pending)
        if current.axis == axis and current.left then
            pending[#pending + 1] = current.left
        else
            if not best or M.less(current.point, best, axis) then
                best = current.point
            end
            if current.axis ~= axis then
                if current.right then
                    pending[#pending + 1] = current.right
                end
                if current.left then
                    pending[#pending + 1] = current.left
                end
            end
        end
    end
    return best
end
function M.delete(root, point)
    local current, parent, side = root, nil, nil
    while current do
        if current.point.id ~= point.id then
            parent = current
            side = M.less(point, current.point, current.axis) and "left" or "right"
            current = current[side]
        elseif current.right then
            point = M.minimum(current.right, current.axis)
            current.point = point
            parent, side, current = current, "right", current.right
        elseif current.left then
            point = M.minimum(current.left, current.axis)
            current.point = point
            current.right, current.left = current.left, nil
            parent, side, current = current, "right", current.right
        else
            if not parent then
                return nil
            end
            parent[side] = nil
            return root
        end
    end
    return root
end
return M
