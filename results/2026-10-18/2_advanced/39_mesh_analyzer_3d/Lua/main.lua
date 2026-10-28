local obj = require("obj_io")
local topology = require("topology")
local orientation = require("orientation")
local measure = require("measure")
local repair = require("repair")
local function append(target, values)
    for _, value in ipairs(values) do
        target[#target + 1] = value
    end
end
local function listing(values)
    return #values == 0 and "-" or table.concat(values, " ")
end
local function yes(value)
    return value and "yes" or "no"
end
local function increment(counts, key)
    counts[key] = (counts[key] or 0) + 1
end
local function keys(values)
    local result = {}
    for value in pairs(values) do
        result[#result + 1] = value
    end
    table.sort(result)
    return result
end
local function contains(values, target)
    for _, value in ipairs(values) do
        if value == target then
            return true
        end
    end
    return false
end
local function read_parameters()
    local settings = {snap = 1, merge = true, degenerate = true, duplicates = true, orient = true, outward = true,
        fill_holes = 0, keep_unused = true, sections = {"summary", "components"}, queries = {}}
    for line in io.lines("input/params.txt") do
        if line ~= "" and line:sub(1, 1) ~= "#" then
            local words = obj.words(line)
            local name = table.remove(words, 1)
            if name == "query" then
                local kind = table.remove(words, 1)
                for index, value in ipairs(words) do
                    words[index] = tonumber(value)
                end
                settings.queries[#settings.queries + 1] = {kind = kind, args = words}
            elseif name == "sections" then
                settings.sections = words
            elseif name == "snap" or name == "fill_holes" then
                settings[name] = tonumber(words[1])
            else
                settings[name] = words[1] == "on"
            end
        end
    end
    return settings
end
local function nonplanar(polygon, points)
    local vertices, total = polygon.vertices, {0, 0, 0}
    local origin = points[vertices[1]]
    for index = 2, #vertices - 1 do
        local normal = measure.cross(measure.subtract(points[vertices[index]], origin), measure.subtract(points[vertices[index + 1]], origin))
        for axis = 1, 3 do
            total[axis] = total[axis] + normal[axis]
        end
    end
    for _, vertex in ipairs(vertices) do
        if measure.dot(measure.subtract(points[vertex], origin), total) ~= 0 then
            return true
        end
    end
    return false
end
local function edge_shape(edge, faces, points)
    if #edge.faces ~= 2 then
        return "-"
    end
    local first, second = faces[edge.faces[1]], faces[edge.faces[2]]
    if orientation.has_directed(first.vertices, edge.a, edge.b) == orientation.has_directed(second.vertices, edge.a, edge.b) then
        return "inconsistent"
    end
    local third
    for _, vertex in ipairs(second.vertices) do
        if vertex ~= edge.a and vertex ~= edge.b then
            third = vertex
        end
    end
    local sign = measure.dot(measure.subtract(points[third], points[first.vertices[1]]), measure.normal(first, points))
    return sign < 0 and "convex" or sign > 0 and "concave" or "flat"
end
local function mark_solids(faces, mesh)
    local inconsistent = {}
    for _, edge in ipairs(orientation.inconsistent(faces, mesh.edges)) do
        inconsistent[topology.key(edge.a, edge.b)] = true
    end
    for _, component in ipairs(mesh.components) do
        component.closed = #component.boundary == 0
        component.manifold = #component.nonmanifold == 0 and #component.nonmanifold_vertices == 0
        component.consistent = true
        for _, edge in ipairs(component.edges) do
            if inconsistent[topology.key(edge.a, edge.b)] then
                component.consistent = false
            end
        end
        component.solid = component.closed and component.manifold and component.consistent
    end
end
local function analyze(source, settings)
    local d = {source = source, settings = settings}
    d.snapped, d.snap_records = repair.snap(source.vertices, settings.snap)
    d.representative = repair.representatives(d.snapped, settings.merge)
    d.triangles = repair.split(source.polygons)
    local kept
    kept, d.removed = repair.clean(d.triangles, d.snapped, d.representative, settings.degenerate, settings.duplicates)
    local present = {}
    if settings.keep_unused then
        for number, representative in ipairs(d.representative) do
            if representative == number then
                present[number] = true
            end
        end
    else
        for _, face in ipairs(kept) do
            for _, vertex in ipairs(face.vertices) do
                present[vertex] = true
            end
        end
    end
    d.points, d.renumber, d.faces, d.original_to_reps = {}, {}, {}, {}
    for number, representative in ipairs(d.representative) do
        d.original_to_reps[representative] = d.original_to_reps[representative] or {}
        local members = d.original_to_reps[representative]
        members[#members + 1] = number
    end
    for _, original in ipairs(keys(present)) do
        d.points[#d.points + 1] = d.snapped[original]
        d.renumber[original] = #d.points
    end
    local initial = {}
    for _, face in ipairs(kept) do
        local v = face.vertices
        local vertices = {d.renumber[v[1]], d.renumber[v[2]], d.renumber[v[3]]}
        d.faces[#d.faces + 1] = {triangle = face.triangle, polygon = face.polygon, line = face.line, group = face.group, vertices = vertices}
        initial[#initial + 1] = {vertices[1], vertices[2], vertices[3]}
    end
    d.initial_faces = #d.faces
    d.before = topology.analyze(d.faces)
    d.inconsistent_before = #orientation.inconsistent(d.faces, d.before.edges)
    if settings.orient then
        orientation.repair(d.faces, d.before)
    end
    d.inconsistent_after = orientation.inconsistent(d.faces, d.before.edges)
    d.loops_before = topology.loops(d.faces, d.before)
    local permitted = {}
    for _, component in ipairs(d.before.components) do
        local consistent = true
        for _, edge in ipairs(d.inconsistent_after) do
            if d.before.face_components[edge.faces[1]] == component.number then
                consistent = false
            end
        end
        permitted[component.number] = #component.nonmanifold == 0 and consistent
    end
    d.added = repair.fill(d.faces, d.loops_before, settings.fill_holes, permitted)
    d.mesh = topology.analyze(d.faces)
    mark_solids(d.faces, d.mesh)
    d.outward_components = 0
    for _, component in ipairs(d.mesh.components) do
        component.inside = {}
        if component.solid then
            for _, other in ipairs(d.mesh.components) do
                if other.solid and other.number ~= component.number then
                    local sample
                    for _, vertex in ipairs(component.vertices) do
                        if not contains(other.vertices, vertex) then
                            sample = vertex
                            break
                        end
                    end
                    if sample and measure.winding(other.faces, d.faces, d.points, d.points[sample]) ~= 0 then
                        component.inside[#component.inside + 1] = other.number
                    end
                end
            end
        end
    end
    if settings.outward then
        for _, component in ipairs(d.mesh.components) do
            if component.solid then
                local signed = measure.volume6(component.faces, d.faces, d.points)
                if signed ~= 0 and ((#component.inside % 2 == 0 and signed < 0) or (#component.inside % 2 == 1 and signed > 0)) then
                    for _, id in ipairs(component.faces) do
                        orientation.flip(d.faces[id])
                    end
                    d.outward_components = d.outward_components + 1
                end
            end
        end
    end
    d.flipped_faces = 0
    for id = 1, d.initial_faces do
        if d.faces[id].vertices[2] ~= initial[id][2] then
            d.flipped_faces = d.flipped_faces + 1
        end
    end
    local copied = {}
    for id, face in ipairs(d.faces) do
        copied[id] = {vertices = {table.unpack(face.vertices)}}
    end
    orientation.repair(copied, d.mesh)
    local not_orientable = {}
    for _, edge in ipairs(orientation.inconsistent(copied, d.mesh.edges)) do
        not_orientable[d.mesh.face_components[edge.faces[1]]] = true
    end
    local loop_counts = {}
    for _, loop in ipairs(topology.loops(d.faces, d.mesh)) do
        increment(loop_counts, loop.component)
    end
    d.nonplanar, d.groups, d.group_faces = {}, {}, {}
    local known = {}
    for _, polygon in ipairs(source.polygons) do
        if nonplanar(polygon, d.snapped) then
            d.nonplanar[polygon.number] = true
        end
        if not known[polygon.group] then
            d.groups[#d.groups + 1], known[polygon.group] = polygon.group, true
        end
    end
    if d.added > 0 then
        d.groups[#d.groups + 1] = "fill"
    end
    for id, face in ipairs(d.faces) do
        d.group_faces[face.group] = d.group_faces[face.group] or {}
        local ids = d.group_faces[face.group]
        ids[#ids + 1] = id
    end
    for _, component in ipairs(d.mesh.components) do
        component.orientable = not not_orientable[component.number]
        component.loops = loop_counts[component.number] or 0
        component.euler = #component.vertices - #component.edges + #component.faces
        if component.manifold then
            if component.orientable then
                component.genus = (2 - component.euler - component.loops) // 2
            else
                component.crosscaps = 2 - component.euler - component.loops
            end
        end
        component.volume6 = measure.volume6(component.faces, d.faces, d.points)
        component.area = measure.area(component.faces, d.faces, d.points)
        component.bbox = measure.bbox(component.vertices, d.points)
        component.normal_sum, component.angles, component.shapes = {0, 0, 0}, {}, {}
        if component.solid and component.volume6 ~= 0 then
            component.centroid = measure.centroid(component.faces, d.faces, d.points, component.volume6)
        end
        for _, id in ipairs(component.faces) do
            local normal = measure.normal(d.faces[id], d.points)
            for axis = 1, 3 do
                component.normal_sum[axis] = component.normal_sum[axis] + normal[axis]
            end
            increment(component.angles, measure.angle(d.faces[id], d.points))
        end
        local degree = {}
        for _, edge in ipairs(component.edges) do
            increment(component.shapes, edge_shape(edge, d.faces, d.points))
            increment(degree, edge.a)
            increment(degree, edge.b)
            local length = measure.length2(edge, d.points)
            component.edge_min = not component.edge_min and length or math.min(component.edge_min, length)
            component.edge_max = not component.edge_max and length or math.max(component.edge_max, length)
        end
        for _, value in pairs(degree) do
            component.valence_min = not component.valence_min and value or math.min(component.valence_min, value)
            component.valence_max = not component.valence_max and value or math.max(component.valence_max, value)
        end
    end
    return d
end
local function boundaries(d)
    local lines = {"loops " .. #d.loops_before}
    for _, loop in ipairs(d.loops_before) do
        lines[#lines + 1] = "loop " .. loop.number .. " component " .. loop.component .. " length " .. loop.length .. " " .. loop.kind .. " " .. (loop.filled and "filled" or "kept") .. " vertices " .. listing(loop.vertices)
    end
    local nonmanifold = {}
    for _, edge in ipairs(d.before.edges) do
        if #edge.faces >= 3 then
            nonmanifold[#nonmanifold + 1] = edge
        end
    end
    lines[#lines + 1] = "nonmanifold_edges " .. #nonmanifold
    for _, edge in ipairs(nonmanifold) do
        lines[#lines + 1] = "edge " .. edge.a .. " " .. edge.b .. " faces " .. listing(edge.faces)
    end
    lines[#lines + 1] = "nonmanifold_vertices " .. #d.before.nonmanifold_vertices
    for _, vertex in ipairs(d.before.nonmanifold_vertices) do
        local components = {}
        for _, fan in ipairs(d.before.fans[vertex]) do
            components[d.before.face_components[fan[1]]] = true
        end
        lines[#lines + 1] = "vertex " .. vertex .. " fans " .. #d.before.fans[vertex] .. " components " .. listing(keys(components))
    end
    lines[#lines + 1] = "inconsistent_edges " .. #d.inconsistent_after
    for _, edge in ipairs(d.inconsistent_after) do
        lines[#lines + 1] = "edge " .. edge.a .. " " .. edge.b .. " faces " .. listing(edge.faces)
    end
    return lines
end
local function summary(d)
    local source, removals, sizes = d.source, {}, {}
    local merged, solids, volume = 0, 0, 0
    for number, representative in ipairs(d.representative) do
        if number ~= representative then
            merged = merged + 1
        end
    end
    for _, removed in ipairs(d.removed) do
        increment(removals, removed.reason)
    end
    for _, polygon in ipairs(source.polygons) do
        increment(sizes, #polygon.vertices)
    end
    for _, component in ipairs(d.mesh.components) do
        if component.solid then
            solids, volume = solids + 1, volume + component.volume6
        end
    end
    local lines = {"[summary]", "lines " .. source.lines, "vertices " .. #source.vertices, "polygons " .. #source.polygons,
        "errors " .. #source.errors, "ignored " .. source.ignored, "nonplanar_polygons " .. #keys(d.nonplanar)}
    for _, size in ipairs(keys(sizes)) do
        lines[#lines + 1] = "polygon_size " .. size .. " " .. sizes[size]
    end
    local filled = 0
    for _, loop in ipairs(d.loops_before) do
        if loop.filled then
            filled = filled + 1
        end
    end
    local all_faces = {}
    for id = 1, #d.faces do
        all_faces[id] = id
    end
    append(lines, {"triangles " .. #d.triangles, "snapped " .. #d.snap_records, "merged " .. merged,
        "removed_repeated " .. (removals.repeated or 0), "removed_zero_area " .. (removals.zero_area or 0), "removed_duplicate " .. (removals.duplicate or 0),
        "faces " .. d.initial_faces, "inconsistent_before " .. d.inconsistent_before, "flipped_faces " .. d.flipped_faces,
        "outward_components " .. d.outward_components, "boundary_loops " .. #d.loops_before, "holes_filled " .. filled, "fill_faces " .. d.added,
        "final_vertices " .. #d.points, "final_faces " .. #d.faces, "components " .. #d.mesh.components, "solids " .. solids,
        "total_area " .. measure.real(measure.area(all_faces, d.faces, d.points)), "total_volume " .. measure.fraction(volume, 6)})
    return lines
end
local function warnings(d)
    local lines = {"[warnings]"}
    for _, item in ipairs(d.source.errors) do
        lines[#lines + 1] = "line " .. item.line .. " " .. item.kind
    end
    return lines
end
local function cleanup(d)
    local lines = {"[cleanup]", "snapped " .. #d.snap_records}
    for _, record in ipairs(d.snap_records) do
        lines[#lines + 1] = "snap " .. record.number .. " " .. listing(record.before) .. " to " .. listing(record.after)
    end
    local merged = 0
    for number, representative in ipairs(d.representative) do
        if number ~= representative then
            merged = merged + 1
        end
    end
    lines[#lines + 1] = "merged " .. merged
    for _, representative in ipairs(keys(d.original_to_reps)) do
        local members = d.original_to_reps[representative]
        if #members > 1 then
            lines[#lines + 1] = "merge " .. (d.renumber[representative] or "-") .. " " .. listing(members)
        end
    end
    lines[#lines + 1] = "removed " .. #d.removed
    for _, item in ipairs(d.removed) do
        lines[#lines + 1] = "remove " .. item.triangle .. " polygon " .. item.polygon .. " line " .. item.line .. " " .. item.reason
    end
    return lines
end
local function components(d)
    local lines = {}
    for _, c in ipairs(d.mesh.components) do
        local groups, present = {}, {}
        for _, id in ipairs(c.faces) do
            present[d.faces[id].group] = true
        end
        for _, group in ipairs(d.groups) do
            if present[group] then
                groups[#groups + 1] = group
            end
        end
        append(lines, {"[component " .. c.number .. "]", "groups " .. listing(groups), "faces " .. #c.faces, "vertices " .. #c.vertices,
            "edges " .. #c.edges, "boundary_edges " .. #c.boundary, "nonmanifold_edges " .. #c.nonmanifold, "nonmanifold_vertices " .. #c.nonmanifold_vertices,
            "boundary_loops " .. c.loops, "closed " .. yes(c.closed), "manifold " .. yes(c.manifold), "orientable " .. yes(c.orientable),
            "consistent " .. yes(c.consistent), "solid " .. yes(c.solid), "euler " .. c.euler})
        lines[#lines + 1] = c.genus and "genus " .. c.genus or c.crosscaps and "crosscaps " .. c.crosscaps or "genus -"
        append(lines, {"volume " .. (c.solid and measure.fraction(c.volume6, 6) or "-"), "area " .. measure.real(c.area),
            "normal_sum " .. listing(c.normal_sum), "bbox " .. listing(c.bbox), "inside " .. listing(c.inside), "centroid " .. (c.centroid and listing(c.centroid) or "-"),
            "convex " .. (c.shapes.convex or 0), "concave " .. (c.shapes.concave or 0), "flat " .. (c.shapes.flat or 0),
            "acute " .. (c.angles.acute or 0), "right " .. (c.angles.right or 0), "obtuse " .. (c.angles.obtuse or 0),
            "edge_len2 " .. c.edge_min .. " " .. c.edge_max, "valence " .. c.valence_min .. " " .. c.valence_max})
    end
    return lines
end
local function groups(d)
    local lines = {}
    for _, name in ipairs(d.groups) do
        local polygons, triangles, warped, parts = 0, 0, 0, {}
        for _, polygon in ipairs(d.source.polygons) do
            if polygon.group == name then
                polygons = polygons + 1
                if d.nonplanar[polygon.number] then
                    warped = warped + 1
                end
            end
        end
        for _, triangle in ipairs(d.triangles) do
            if triangle.group == name then
                triangles = triangles + 1
            end
        end
        local ids = d.group_faces[name] or {}
        for _, id in ipairs(ids) do
            parts[d.mesh.face_components[id]] = true
        end
        append(lines, {"[group " .. name .. "]", "polygons " .. polygons, "triangles " .. triangles, "nonplanar " .. warped, "faces " .. #ids,
            "area " .. measure.real(measure.area(ids, d.faces, d.points)), "components " .. listing(keys(parts))})
    end
    return lines
end
local function contacts(d)
    local lines = {"[contacts]"}
    for i, first in ipairs(d.mesh.components) do
        for j = i + 1, #d.mesh.components do
            local second, intersects = d.mesh.components[j], true
            for axis = 1, 3 do
                if first.bbox[axis] > second.bbox[axis + 3] or second.bbox[axis] > first.bbox[axis + 3] then
                    intersects = false
                end
            end
            if intersects then
                local shared, gap = 0, nil
                for _, a in ipairs(first.vertices) do
                    if contains(second.vertices, a) then
                        shared = shared + 1
                    end
                    for _, b in ipairs(second.vertices) do
                        if a ~= b then
                            local delta = measure.subtract(d.points[a], d.points[b])
                            local distance = measure.dot(delta, delta)
                            gap = not gap and distance or math.min(gap, distance)
                        end
                    end
                end
                lines[#lines + 1] = "contact " .. i .. " " .. j .. " shared " .. shared .. " gap2 " .. gap
            end
        end
    end
    return lines
end
local function edges(d)
    local counts, shapes, maximum = {}, {}, 0
    local shortest, longest, low, high
    for _, edge in ipairs(d.mesh.edges) do
        increment(counts, #edge.faces == 1 and "boundary" or #edge.faces == 2 and "manifold" or "nonmanifold")
        increment(shapes, edge_shape(edge, d.faces, d.points))
        maximum = math.max(maximum, #edge.faces)
        local length = measure.length2(edge, d.points)
        if not shortest or length < low then
            shortest, low = edge, length
        end
        if not longest or length > high then
            longest, high = edge, length
        end
    end
    return {"[edges]", "edges " .. #d.mesh.edges, "boundary " .. (counts.boundary or 0), "manifold " .. (counts.manifold or 0),
        "nonmanifold " .. (counts.nonmanifold or 0), "max_faces " .. maximum, "convex " .. (shapes.convex or 0), "concave " .. (shapes.concave or 0),
        "flat " .. (shapes.flat or 0), "inconsistent " .. (shapes.inconsistent or 0),
        "shortest " .. shortest.a .. " " .. shortest.b .. " len2 " .. low, "longest " .. longest.a .. " " .. longest.b .. " len2 " .. high}
end
local function valence(d)
    local degree, histogram, minimum, maximum, total = {}, {}, nil, nil, 0
    for _, edge in ipairs(d.mesh.edges) do
        increment(degree, edge.a)
        increment(degree, edge.b)
    end
    for _, value in pairs(degree) do
        increment(histogram, value)
        minimum, maximum, total = not minimum and value or math.min(minimum, value), not maximum and value or math.max(maximum, value), total + value
    end
    local used = #keys(degree)
    local lines = {"[valence]", "used " .. used, "isolated " .. (#d.points - used), "min " .. minimum, "max " .. maximum, "mean " .. measure.fraction(total, used)}
    for _, value in ipairs(keys(histogram)) do
        lines[#lines + 1] = "degree " .. value .. " " .. histogram[value]
    end
    return lines
end
local function query_vertex(number, d)
    local prefix = "vertex " .. number
    if number < 1 or number > #d.points then
        return prefix .. " invalid"
    end
    local count, degree, boundary, parts = 0, 0, false, {}
    for id, face in ipairs(d.faces) do
        if contains(face.vertices, number) then
            count = count + 1
            parts[d.mesh.face_components[id]] = true
        end
    end
    for _, edge in ipairs(d.mesh.edges) do
        if edge.a == number or edge.b == number then
            degree = degree + 1
            boundary = boundary or #edge.faces == 1
        end
    end
    return prefix .. " at " .. listing(d.points[number]) .. " faces " .. count .. " valence " .. degree .. " fans " .. #(d.mesh.fans[number] or {}) .. " boundary " .. yes(boundary) .. " components " .. listing(keys(parts))
end
local function query_face(number, d)
    local prefix = "face " .. number
    if number < 1 or number > #d.faces then
        return prefix .. " invalid"
    end
    local face, neighbors = d.faces[number], {}
    for _, pair in ipairs(topology.directed(face.vertices)) do
        local adjacent = d.mesh.by_key[topology.key(pair[1], pair[2])].faces
        neighbors[#neighbors + 1] = #adjacent == 1 and "-" or #adjacent >= 3 and "*" or adjacent[1] == number and adjacent[2] or adjacent[1]
    end
    return prefix .. " vertices " .. listing(face.vertices) .. " group " .. face.group .. " polygon " .. (face.polygon or "-") .. " line " .. (face.line or "-") .. " component " .. d.mesh.face_components[number]
        .. " normal " .. listing(measure.normal(face, d.points)) .. " area " .. measure.real(measure.area({number}, d.faces, d.points)) .. " neighbors " .. listing(neighbors)
end
local function query_edge(a, b, d)
    a, b = math.min(a, b), math.max(a, b)
    local prefix, edge = "edge " .. a .. " " .. b, d.mesh.by_key[topology.key(a, b)]
    if not edge then
        return prefix .. " none"
    end
    local kind = #edge.faces == 1 and "boundary" or #edge.faces == 2 and "manifold" or "nonmanifold"
    return prefix .. " faces " .. listing(edge.faces) .. " kind " .. kind .. " shape " .. edge_shape(edge, d.faces, d.points) .. " len2 " .. measure.length2(edge, d.points)
end
local function query_point(point, d)
    local inside, total = {}, 0
    for _, component in ipairs(d.mesh.components) do
        if component.solid then
            local winding = measure.winding(component.faces, d.faces, d.points, point)
            if winding ~= 0 then
                inside[#inside + 1], total = component.number, total + winding
            end
        end
    end
    return "point " .. listing(point) .. " inside " .. listing(inside) .. " winding " .. total
end
local function query_path(start, target, d)
    local prefix = "path " .. start .. " " .. target
    if start < 1 or start > #d.points or target < 1 or target > #d.points then
        return prefix .. " invalid"
    end
    local neighbors = {}
    for number = 1, #d.points do
        neighbors[number] = {}
    end
    for _, edge in ipairs(d.mesh.edges) do
        neighbors[edge.a][#neighbors[edge.a] + 1] = edge.b
        neighbors[edge.b][#neighbors[edge.b] + 1] = edge.a
    end
    for _, values in ipairs(neighbors) do
        table.sort(values)
    end
    local queue, parent, head = {start}, {[start] = 0}, 1
    while head <= #queue do
        local current = queue[head]
        head = head + 1
        for _, other in ipairs(neighbors[current]) do
            if parent[other] == nil then
                parent[other], queue[#queue + 1] = current, other
            end
        end
    end
    if parent[target] == nil then
        return prefix .. " none"
    end
    local reversed, path, current = {}, {}, target
    while current ~= 0 do
        reversed[#reversed + 1], current = current, parent[current]
    end
    for index = #reversed, 1, -1 do
        path[#path + 1] = reversed[index]
    end
    return prefix .. " hops " .. (#path - 1) .. " vertices " .. listing(path)
end
local function query_view(direction, d)
    local scores, front, back, side, silhouette = {}, 0, 0, 0, 0
    for id, face in ipairs(d.faces) do
        local score = measure.dot(measure.normal(face, d.points), direction)
        scores[id] = score
        if score > 0 then
            front = front + 1
        elseif score < 0 then
            back = back + 1
        else
            side = side + 1
        end
    end
    for _, edge in ipairs(d.mesh.edges) do
        if #edge.faces == 2 and scores[edge.faces[1]] * scores[edge.faces[2]] < 0 then
            silhouette = silhouette + 1
        end
    end
    return "view " .. listing(direction) .. " front " .. front .. " back " .. back .. " side " .. side .. " silhouette " .. silhouette
end
local function queries(d)
    local lines = {"[queries]"}
    for _, query in ipairs(d.settings.queries) do
        local a, answer = query.args, nil
        if query.kind == "vertex" then
            answer = query_vertex(a[1], d)
        elseif query.kind == "face" then
            answer = query_face(a[1], d)
        elseif query.kind == "edge" then
            answer = query_edge(a[1], a[2], d)
        elseif query.kind == "point" then
            answer = query_point(a, d)
        elseif query.kind == "path" then
            answer = query_path(a[1], a[2], d)
        else
            answer = query_view(a, d)
        end
        lines[#lines + 1] = answer
    end
    return lines
end
local function components_csv(d)
    local lines = {"component,faces,vertices,closed,euler,genus,volume6,area"}
    for _, c in ipairs(d.mesh.components) do
        lines[#lines + 1] = table.concat({c.number, #c.faces, #c.vertices, yes(c.closed), c.euler, c.genus or "-", c.solid and c.volume6 or "-", measure.real(c.area)}, ",")
    end
    return lines
end
local function save(name, lines)
    local file = assert(io.open("output/" .. name, "w"))
    for _, line in ipairs(lines) do
        file:write(line, "\n")
    end
    file:close()
end
local d = analyze(obj.read(), read_parameters())
local sections = {summary = summary, warnings = warnings, cleanup = cleanup, components = components, groups = groups, contacts = contacts,
    edges = edges, valence = valence, queries = queries}
local lines = {}
for _, name in ipairs(d.settings.sections) do
    append(lines, sections[name](d))
end
os.execute('mkdir -p output')
save("report.txt", lines)
save("components.csv", components_csv(d))
save("boundaries.txt", boundaries(d))
save("repaired.obj", obj.repaired(d.points, d.faces))
