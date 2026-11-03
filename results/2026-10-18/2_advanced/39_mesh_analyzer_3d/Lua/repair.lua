local measure = require("measure")
local M = {}
function M.split(polygons)
    local triangles = {}
    for _, polygon in ipairs(polygons) do
        for index = 2, #polygon.vertices - 1 do
            triangles[#triangles + 1] = {triangle = #triangles + 1, polygon = polygon.number, line = polygon.line, group = polygon.group,
                vertices = {polygon.vertices[1], polygon.vertices[index], polygon.vertices[index + 1]}}
        end
    end
    return triangles
end
function M.snap(vertices, spacing)
    local points, changed = {}, {}
    for number, point in ipairs(vertices) do
        local snapped = {}
        for axis = 1, 3 do
            snapped[axis] = spacing * ((2 * point[axis] + spacing) // (2 * spacing))
        end
        points[number] = snapped
        if snapped[1] ~= point[1] or snapped[2] ~= point[2] or snapped[3] ~= point[3] then
            changed[#changed + 1] = {number = number, before = point, after = snapped}
        end
    end
    return points, changed
end
function M.representatives(points, merge)
    local owner, representatives = {}, {}
    for number, point in ipairs(points) do
        local key = table.concat(point, ",")
        if not merge then
            representatives[number] = number
        else
            owner[key] = owner[key] or number
            representatives[number] = owner[key]
        end
    end
    return representatives
end
function M.clean(triangles, points, representative, remove_zero, remove_duplicate)
    local faces, removed, seen = {}, {}, {}
    for _, triangle in ipairs(triangles) do
        local a, b, c = representative[triangle.vertices[1]], representative[triangle.vertices[2]], representative[triangle.vertices[3]]
        local reason
        if a == b or b == c or c == a then
            reason = "repeated"
        elseif remove_zero then
            local normal = measure.cross(measure.subtract(points[b], points[a]), measure.subtract(points[c], points[a]))
            if normal[1] == 0 and normal[2] == 0 and normal[3] == 0 then
                reason = "zero_area"
            end
        end
        if not reason then
            local key_vertices = {a, b, c}
            table.sort(key_vertices)
            local key = table.concat(key_vertices, ",")
            if remove_duplicate and seen[key] then
                reason = "duplicate"
            else
                seen[key] = true
            end
        end
        if reason then
            removed[#removed + 1] = {triangle = triangle.triangle, polygon = triangle.polygon, line = triangle.line, reason = reason}
        else
            faces[#faces + 1] = {triangle = triangle.triangle, polygon = triangle.polygon, line = triangle.line, group = triangle.group, vertices = {a, b, c}}
        end
    end
    return faces, removed
end
function M.fill(faces, loops, maximum, permitted)
    local added = 0
    for _, loop in ipairs(loops) do
        local distinct, count = {}, 0
        for _, vertex in ipairs(loop.vertices) do
            if not distinct[vertex] then
                distinct[vertex], count = true, count + 1
            end
        end
        if loop.kind == "coherent" and loop.length >= 3 and loop.length <= maximum and count == loop.length and permitted[loop.component] then
            for index = 3, #loop.vertices do
                faces[#faces + 1] = {group = "fill", vertices = {loop.vertices[1], loop.vertices[index], loop.vertices[index - 1]}}
                added = added + 1
            end
            loop.filled = true
        end
    end
    return added
end
return M
