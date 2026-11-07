local dataset = require("dataset")
local kdtree = require("kdtree")
local quadtree = require("quadtree")
local rtree = require("rtree")
local grid = require("grid")
local report = require("report")
local names = {"kdtree", "quadtree", "rtree", "str", "grid", "rtree_rect", "str_rect"}
local command_order = {"RANGE", "RADIUS", "KNN", "WINDOWCOUNT", "CONTAINS", "NEAREST", "JOIN"}
local function words(values)
    return table.concat(values, " ")
end
local function append(target, values)
    for _, value in ipairs(values) do
        target[#target + 1] = value
    end
end
local function less(first, second)
    for i = 1, #first do
        if first[i] ~= second[i] then
            return first[i] < second[i]
        end
    end
    return false
end
local function equal(first, second)
    if type(first) ~= type(second) then
        return false
    elseif type(first) ~= "table" then
        return first == second
    elseif #first ~= #second then
        return false
    end
    for i = 1, #first do
        if not equal(first[i], second[i]) then
            return false
        end
    end
    return true
end
local function minimum_distance(query, box)
    local dx, dy = 0, 0
    if query[1] < box[1] then
        dx = box[1] - query[1]
    elseif query[1] > box[3] then
        dx = query[1] - box[3]
    end
    if query[2] < box[2] then
        dy = box[2] - query[2]
    elseif query[2] > box[4] then
        dy = query[2] - box[4]
    end
    return dx * dx + dy * dy
end
local function preorder(root)
    local result, pending = {}, {root}
    while #pending > 0 do
        local current = table.remove(pending)
        result[#result + 1] = current
        for i = #current.children, 1, -1 do
            pending[#pending + 1] = current.children[i]
        end
    end
    return result
end
local function common_view(name, source, world, lookup)
    local root = {source = source, name = name, box = {0, 0, world - 1, world - 1}, depth = 0, mark = "root", directory = name == "grid"}
    local pending, ordered = {root}, {}
    while #pending > 0 do
        local current = table.remove(pending)
        local original = current.source
        current.objects, current.children = {}, {}
        ordered[#ordered + 1] = current
        local function child(child_source, box, mark)
            current.children[#current.children + 1] = {source = child_source, name = name, box = box,
                depth = current.depth + 1, mark = mark, directory = false}
        end
        if name == "kdtree" then
            current.objects = {original.point}
            local split = original.axis == 0 and original.point.x or original.point.y
            if original.left then
                local box = {table.unpack(current.box)}
                box[original.axis == 0 and 3 or 4] = split
                child(original.left, box, "L")
            end
            if original.right then
                local box = {table.unpack(current.box)}
                box[original.axis == 0 and 1 or 2] = split
                child(original.right, box, "R")
            end
        elseif name == "quadtree" then
            current.box = {original.x, original.y, original.x + original.size - 1, original.y + original.size - 1}
            if #original.children == 0 then
                current.objects = original.points
            else
                for i, descendant in ipairs(original.children) do
                    child(descendant, nil, quadtree.names[i])
                end
            end
        elseif name == "grid" then
            if current.directory then
                for _, cell in ipairs(original.cells) do
                    child(cell, cell.box, "")
                end
            else
                current.box, current.objects = original.box, original.points
            end
        else
            current.box = original:box()
            if original.level == 0 then
                for _, entry in ipairs(original.entries) do
                    current.objects[#current.objects + 1] = lookup[entry.id]
                end
            else
                for _, entry in ipairs(original.entries) do
                    child(entry.child, entry.box, "")
                end
            end
        end
        for i = #current.children, 1, -1 do
            pending[#pending + 1] = current.children[i]
        end
    end
    for i = #ordered, 1, -1 do
        local current = ordered[i]
        current.count = #current.objects
        for _, child in ipairs(current.children) do
            current.count = current.count + child.count
        end
    end
    return root
end
local function object_condition(command, values, object)
    if command == "RADIUS" then
        return minimum_distance(values, object.box) <= values[3] * values[3]
    elseif command == "CONTAINS" then
        return rtree.contains(object.box, {values[1], values[2], values[1], values[2]})
    end
    return rtree.contains(values, object.box)
end
local function region_condition(command, values, box)
    if command == "RADIUS" then
        return minimum_distance(values, box) <= values[3] * values[3]
    elseif command == "CONTAINS" then
        return rtree.contains(box, {values[1], values[2], values[1], values[2]})
    end
    return rtree.intersects(box, values)
end
local function conditional_search(root, command, values)
    local pending, ids, count, nodes, tests = {root}, {}, 0, 0, 0
    while #pending > 0 do
        local current = table.remove(pending)
        nodes = nodes + 1
        if command == "WINDOWCOUNT" and rtree.contains(values, current.box) then
            count = count + current.count
        else
            tests = tests + #current.objects
            for _, object in ipairs(current.objects) do
                if object_condition(command, values, object) then
                    ids[#ids + 1] = object.id
                    count = count + 1
                end
            end
            for i = #current.children, 1, -1 do
                local child = current.children[i]
                if region_condition(command, values, child.box) then
                    pending[#pending + 1] = child
                end
            end
        end
    end
    table.sort(ids)
    return command == "WINDOWCOUNT" and count or ids, nodes, tests
end
local function heap_push(heap, item)
    local index = #heap + 1
    while index > 1 do
        local parent = index // 2
        if not less(item.key, heap[parent].key) then
            break
        end
        heap[index] = heap[parent]
        index = parent
    end
    heap[index] = item
end
local function heap_pop(heap)
    local result, last = heap[1], table.remove(heap)
    if #heap == 0 then
        return result
    end
    local index = 1
    while index * 2 <= #heap do
        local child = index * 2
        if child < #heap and less(heap[child + 1].key, heap[child].key) then
            child = child + 1
        end
        if not less(heap[child].key, last.key) then
            break
        end
        heap[index] = heap[child]
        index = child
    end
    heap[index] = last
    return result
end
local function nearest_search(root, values)
    local heap, answer, serial, nodes, tests = {}, {}, 1, 0, 0
    heap_push(heap, {key = {minimum_distance(values, root.box), 0, 0}, node = root})
    while #heap > 0 do
        local item = heap_pop(heap)
        if item.object then
            answer[#answer + 1] = {item.object.id, item.key[1]}
            if #answer == values[3] then
                break
            end
        else
            local current = item.node
            nodes, tests = nodes + 1, tests + #current.objects
            for _, object in ipairs(current.objects) do
                heap_push(heap, {key = {minimum_distance(values, object.box), 1, object.id}, object = object})
            end
            for _, child in ipairs(current.children) do
                heap_push(heap, {key = {minimum_distance(values, child.box), 0, serial}, node = child})
                serial = serial + 1
            end
        end
    end
    return answer, nodes, tests
end
local function join_search(first, second)
    local answer, nodes, tests = {}, 0, 0
    local function visit(a, b)
        nodes = nodes + 1
        if #a.children == 0 and #b.children == 0 then
            tests = tests + #a.objects * #b.objects
            for _, point in ipairs(a.objects) do
                for _, rectangle in ipairs(b.objects) do
                    if rtree.contains(rectangle.box, point.box) then
                        answer[#answer + 1] = {rectangle.id, point.id}
                    end
                end
            end
        elseif #a.children == 0 then
            for _, child in ipairs(b.children) do
                if rtree.intersects(a.box, child.box) then
                    visit(a, child)
                end
            end
        elseif #b.children == 0 then
            for _, child in ipairs(a.children) do
                if rtree.intersects(child.box, b.box) then
                    visit(child, b)
                end
            end
        else
            for _, left in ipairs(a.children) do
                for _, right in ipairs(b.children) do
                    if rtree.intersects(left.box, right.box) then
                        visit(left, right)
                    end
                end
            end
        end
    end
    visit(first, second)
    table.sort(answer, less)
    return answer, nodes, tests
end
local Lab = {}
Lab.__index = Lab
local function lab(data)
    local points, rectangles = {}, {}
    for _, point in ipairs(data.points) do
        points[point.id] = point
    end
    for _, rectangle in ipairs(data.rectangles) do
        rectangles[rectangle.id] = rectangle
    end
    local params = data.params
    local trees = {}
    trees[3] = rtree.build(data.points, params.maximum, params.minimum, false)
    trees[4] = rtree.build(data.points, params.maximum, params.minimum, true)
    trees[6] = rtree.build(data.rectangles, params.maximum, params.minimum, false)
    trees[7] = rtree.build(data.rectangles, params.maximum, params.minimum, true)
    return setmetatable({data = data, params = params, points = points, rectangles = rectangles, point_count = #data.points,
        kd = kdtree.build(data.points), quad = quadtree.build(data.points, params.world, params.bucket), trees = trees,
        grid = grid.build(data.points, params.world, params.cell_size), answers = {}, visits = {"query,command,structure,nodes,tests"},
        joins = {"query,rect,point"}, structures = {}, stats = {}, totals = {}, snapshot_count = 0}, Lab)
end
function Lab:views()
    local result, world = {}, self.params.world
    result[1] = common_view(names[1], self.kd, world, self.points)
    result[2] = common_view(names[2], self.quad, world, self.points)
    result[3] = common_view(names[3], self.trees[3].root, world, self.points)
    result[4] = common_view(names[4], self.trees[4].root, world, self.points)
    result[5] = common_view(names[5], self.grid, world, self.points)
    result[6] = common_view(names[6], self.trees[6].root, world, self.rectangles)
    result[7] = common_view(names[7], self.trees[7].root, world, self.rectangles)
    return result
end
function Lab:current_points()
    local result = {}
    for _, point in pairs(self.points) do
        result[#result + 1] = point
    end
    table.sort(result, function(a, b) return a.id < b.id end)
    return result
end
function Lab:brute(command, values)
    local points = self:current_points()
    if command == "JOIN" then
        local answer = {}
        for _, rectangle in ipairs(self.data.rectangles) do
            for _, point in ipairs(points) do
                if rtree.contains(rectangle.box, point.box) then
                    answer[#answer + 1] = {rectangle.id, point.id}
                end
            end
        end
        table.sort(answer, less)
        return answer
    end
    local objects = points
    if command == "CONTAINS" or command == "NEAREST" then
        objects = self.data.rectangles
    end
    local answer, count = {}, 0
    for _, object in ipairs(objects) do
        if command == "KNN" or command == "NEAREST" then
            answer[#answer + 1] = {object.id, minimum_distance(values, object.box)}
        elseif object_condition(command, values, object) then
            answer[#answer + 1], count = object.id, count + 1
        end
    end
    if command == "KNN" or command == "NEAREST" then
        table.sort(answer, function(a, b)
            return a[2] < b[2] or a[2] == b[2] and a[1] < b[1]
        end)
        local selected = {}
        for i = 1, values[3] do
            selected[i] = answer[i]
        end
        return selected
    end
    table.sort(answer)
    return command == "WINDOWCOUNT" and count or answer
end
function Lab:record_visit(number, command, structure, nodes, tests)
    self.visits[#self.visits + 1] = table.concat({number, command, names[structure], nodes, tests}, ",")
    self.totals[command] = self.totals[command] or {}
    local total = self.totals[command][structure]
    if not total then
        total = {queries = 0, nodes = 0, tests = 0, maximum = 0}
        self.totals[command][structure] = total
    end
    total.queries, total.nodes, total.tests = total.queries + 1, total.nodes + nodes, total.tests + tests
    total.maximum = math.max(total.maximum, nodes)
end
function Lab:search(number, command, values)
    local roots, brute, mismatches = self:views(), self:brute(command, values), {}
    local structures = {1, 2, 3, 4, 5}
    if command == "CONTAINS" or command == "NEAREST" then
        structures = {6, 7}
    elseif command == "JOIN" then
        structures = {3, 4}
    end
    for _, structure in ipairs(structures) do
        local answer, nodes, tests
        if command == "JOIN" then
            answer, nodes, tests = join_search(roots[structure], roots[structure + 3])
        elseif command == "KNN" or command == "NEAREST" then
            answer, nodes, tests = nearest_search(roots[structure], values)
        else
            answer, nodes, tests = conditional_search(roots[structure], command, values)
        end
        self:record_visit(number, command, structure, nodes, tests)
        if not equal(answer, brute) then
            mismatches[#mismatches + 1] = names[structure]
        end
    end
    local check = #mismatches == 0 and "ok" or "mismatch " .. words(mismatches)
    local line = number .. " " .. command .. " count "
    if command == "WINDOWCOUNT" then
        line = line .. brute
    else
        line = line .. #brute
        if command == "KNN" or command == "NEAREST" then
            line = line .. " ids " .. report.distances(brute)
        elseif command ~= "JOIN" then
            line = line .. " ids " .. report.ids(brute)
        end
    end
    self.answers[#self.answers + 1] = line .. " check " .. check
    if command == "JOIN" then
        for _, pair in ipairs(brute) do
            self.joins[#self.joins + 1] = number .. "," .. pair[1] .. "," .. pair[2]
        end
    end
end
local function object_ids(objects)
    local result = {}
    for _, object in ipairs(objects) do
        result[#result + 1] = object.id
    end
    return result
end
local function dump_tree(root)
    local lines = {}
    for _, current in ipairs(preorder(root)) do
        local source, name, line = current.source, root.name, nil
        if name == "kdtree" then
            local point = source.point
            line = current.mark .. " " .. (source.axis == 0 and "x" or "y") .. " " .. point.id .. " " .. point.x .. " " .. point.y .. " box " .. words(current.box)
        elseif name == "quadtree" then
            line = current.mark .. " " .. source.x .. " " .. source.y .. " " .. source.size
            if #current.children > 0 then
                line = line .. " node count " .. current.count
            else
                line = line .. " leaf " .. report.ids(object_ids(current.objects))
            end
        elseif source.level == 0 then
            line = "leaf " .. words(current.box) .. " ids " .. report.ids(object_ids(current.objects))
        else
            line = "node " .. source.level .. " " .. words(current.box) .. " entries " .. #source.entries
        end
        lines[#lines + 1] = string.rep(" ", 2 * (current.depth + 1)) .. line
    end
    return lines
end
local function kd_stats(root)
    local levels, nodes, leaves, one_child, depth_sum = {}, 0, 0, 0, 0
    for _, current in ipairs(preorder(root)) do
        local depth, children = current.depth, #current.children
        levels[depth + 1] = levels[depth + 1] or {nodes = 0, leaves = 0, one = 0}
        local level = levels[depth + 1]
        level.nodes, nodes, depth_sum = level.nodes + 1, nodes + 1, depth_sum + depth
        if children == 0 then
            level.leaves, leaves = level.leaves + 1, leaves + 1
        elseif children == 1 then
            level.one, one_child = level.one + 1, one_child + 1
        end
    end
    local ideal, capacity = 0, 0
    while capacity < nodes do
        ideal, capacity = ideal + 1, capacity * 2 + 1
    end
    local lines = {"kdtree height " .. #levels .. " ideal " .. ideal .. " nodes " .. nodes .. " leaves " .. leaves ..
        " one_child " .. one_child .. " depth_sum " .. depth_sum .. " avg_depth " .. report.fraction(depth_sum, nodes)}
    for i, level in ipairs(levels) do
        lines[#lines + 1] = "  depth " .. i - 1 .. " nodes " .. level.nodes .. " leaves " .. level.leaves .. " one_child " .. level.one
    end
    return lines
end
local function quad_stats(root, capacity)
    local levels, internal, leaves, empty, maximum = {}, 0, 0, 0, 0
    for _, current in ipairs(preorder(root)) do
        local index = current.depth + 1
        levels[index] = levels[index] or {internal = 0, leaves = 0, points = 0}
        local level = levels[index]
        if #current.children > 0 then
            level.internal, internal = level.internal + 1, internal + 1
        else
            local count = #current.objects
            level.leaves, leaves, level.points = level.leaves + 1, leaves + 1, level.points + count
            empty = empty + (count == 0 and 1 or 0)
            maximum = math.max(maximum, count)
        end
    end
    local lines = {"quadtree height " .. #levels .. " internal " .. internal .. " leaves " .. leaves .. " empty " .. empty ..
        " max_leaf " .. maximum .. " fill " .. report.fraction(root.count, leaves * capacity)}
    for i, level in ipairs(levels) do
        lines[#lines + 1] = "  depth " .. i - 1 .. " internal " .. level.internal .. " leaves " .. level.leaves .. " points " .. level.points
    end
    return lines
end
local function rtree_stats(root, maximum, minimum)
    local levels, nodes, leaves, entries = {}, 0, 0, 0
    for _, current in ipairs(preorder(root)) do
        local level = current.source.level
        levels[level + 1] = levels[level + 1] or {}
        levels[level + 1][#levels[level + 1] + 1] = current
        nodes, entries = nodes + 1, entries + #current.source.entries
        leaves = leaves + (level == 0 and 1 or 0)
    end
    local lines = {root.name .. " height " .. root.source.level + 1 .. " nodes " .. nodes .. " leaves " .. leaves ..
        " entries " .. entries .. " fill " .. report.fraction(entries, nodes * maximum)}
    for level = root.source.level, 0, -1 do
        local values = levels[level + 1]
        local sum, low, high, under, area, overlap = 0, nil, 0, 0, 0, 0
        for i, current in ipairs(values) do
            local count = #current.source.entries
            sum, high, under, area = sum + count, math.max(high, count), under + (count < minimum and 1 or 0), area + rtree.area(current.box)
            low = low and math.min(low, count) or count
            for j = i + 1, #values do
                overlap = overlap + rtree.overlap(current.box, values[j].box)
            end
        end
        lines[#lines + 1] = "  level " .. level .. " nodes " .. #values .. " entries " .. sum .. " min " .. low .. " max " .. high ..
            " under " .. under .. " area " .. area .. " overlap " .. overlap
    end
    return lines
end
local function grid_stats(root)
    local occupancy, keys, used, maximum = {}, {}, 0, 0
    for _, cell in ipairs(root.children) do
        local count = #cell.objects
        if not occupancy[count] then
            occupancy[count], keys[#keys + 1] = 0, count
        end
        occupancy[count] = occupancy[count] + 1
        used = used + (count > 0 and 1 or 0)
        maximum = math.max(maximum, count)
    end
    table.sort(keys)
    local entries = {}
    for _, count in ipairs(keys) do
        entries[#entries + 1] = count .. ":" .. occupancy[count]
    end
    return {"grid cells " .. #root.children .. " used " .. used .. " max " .. maximum, "  occupancy " .. words(entries)}
end
function Lab:snapshot(query)
    local roots = self:views()
    if #self.structures > 0 then
        self.structures[#self.structures + 1], self.stats[#self.stats + 1] = "", ""
    end
    local header = "snapshot " .. self.snapshot_count .. " query " .. query .. " points " .. self.point_count .. " rects " .. #self.data.rectangles
    self.structures[#self.structures + 1], self.stats[#self.stats + 1] = header, header
    for _, structure in ipairs({1, 2, 3, 4, 6, 7}) do
        self.structures[#self.structures + 1] = names[structure]
        append(self.structures, dump_tree(roots[structure]))
    end
    append(self.stats, kd_stats(roots[1]))
    append(self.stats, quad_stats(roots[2], self.params.bucket))
    for _, structure in ipairs({3, 4, 6, 7}) do
        append(self.stats, rtree_stats(roots[structure], self.params.maximum, self.params.minimum))
    end
    append(self.stats, grid_stats(roots[5]))
end
local function rtree_position(tree, point)
    local current, position = tree:find_leaf(point.id, point.box)
    local path = {position}
    while current.parent do
        local parent = current.parent
        for i, entry in ipairs(parent.entries) do
            if entry.child == current then
                table.insert(path, 1, i)
                break
            end
        end
        current = parent
    end
    return table.concat(path, "/")
end
function Lab:locate(number, id)
    local point = self.points[id]
    if not point then
        return number .. " LOCATE " .. id .. " missing"
    end
    local current, kd_path = self.kd, ""
    while current.point.id ~= id do
        local side = kdtree.less(point, current.point, current.axis) and "left" or "right"
        kd_path = kd_path .. (side == "left" and "L" or "R")
        current = current[side]
    end
    local quad_path = {}
    current = self.quad
    while #current.children > 0 do
        local child = quadtree.destination(current, point)
        quad_path[#quad_path + 1] = quadtree.names[child]
        current = current.children[child]
    end
    local column, row = self.grid:position(point)
    return number .. " LOCATE " .. id .. " kdtree " .. (#kd_path > 0 and kd_path or "-") ..
        " quadtree " .. (#quad_path > 0 and table.concat(quad_path, "/") or "-") ..
        " rtree " .. rtree_position(self.trees[3], point) .. " str " .. rtree_position(self.trees[4], point) .. " grid " .. column .. " " .. row
end
function Lab:insert(values)
    local point = {id = values[1], x = values[2], y = values[3], box = {values[2], values[3], values[2], values[3]}}
    self.kd = kdtree.insert(self.kd, point)
    quadtree.insert(self.quad, point, self.params.bucket)
    self.trees[3]:insert({box = point.box, id = point.id})
    self.trees[4]:insert({box = point.box, id = point.id})
    self.grid:insert(point)
    self.points[point.id], self.point_count = point, self.point_count + 1
end
function Lab:delete(id)
    local point = self.points[id]
    if not point then
        return false
    end
    self.kd = kdtree.delete(self.kd, point)
    quadtree.delete(self.quad, point, self.params.bucket)
    self.trees[3]:delete(point)
    self.trees[4]:delete(point)
    self.grid:delete(point)
    self.points[id], self.point_count = nil, self.point_count - 1
    return true
end
function Lab:process(number, command)
    local name, values = command.name, command.values
    if name == "LOCATE" then
        self.answers[#self.answers + 1] = self:locate(number, values[1])
    elseif name == "INSERT" then
        self:insert(values)
        self.answers[#self.answers + 1] = number .. " INSERT " .. values[1] .. " inserted points " .. self.point_count
    elseif name == "DELETE" then
        local status = self:delete(values[1]) and "deleted" or "missing"
        self.answers[#self.answers + 1] = number .. " DELETE " .. values[1] .. " " .. status .. " points " .. self.point_count
    elseif name == "DUMP" then
        self.snapshot_count = self.snapshot_count + 1
        self:snapshot(number)
        self.answers[#self.answers + 1] = number .. " DUMP snapshot " .. self.snapshot_count
    else
        self:search(number, name, values)
    end
end
function Lab:finish()
    self.stats[#self.stats + 1], self.stats[#self.stats + 2] = "", "visits"
    for _, command in ipairs(command_order) do
        local totals = self.totals[command]
        if totals then
            local structures = {}
            for structure = 1, #names do
                local total = totals[structure]
                if total then
                    structures[#structures + 1] = structure
                    self.stats[#self.stats + 1] = command .. " " .. names[structure] .. " queries " .. total.queries ..
                        " nodes " .. total.nodes .. " tests " .. total.tests .. " max_nodes " .. total.maximum ..
                        " mean_nodes " .. report.fraction(total.nodes, total.queries)
                end
            end
            table.sort(structures, function(a, b)
                return less({totals[a].nodes, totals[a].tests, a}, {totals[b].nodes, totals[b].tests, b})
            end)
            local ranked = {}
            for _, structure in ipairs(structures) do
                ranked[#ranked + 1] = names[structure]
            end
            self.stats[#self.stats + 1] = "rank " .. command .. " " .. words(ranked)
        end
    end
    report.write("answers.txt", self.answers)
    report.write("visits.csv", self.visits)
    report.write("join.csv", self.joins)
    report.write("structures.txt", self.structures)
    report.write("stats.txt", self.stats)
end
local data = dataset.read()
local result = lab(data)
result:snapshot(0)
for number, command in ipairs(data.commands) do
    result:process(number, command)
end
result:finish()
