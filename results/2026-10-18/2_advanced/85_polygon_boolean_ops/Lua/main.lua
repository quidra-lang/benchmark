local Rational = require("rational")
local Intersections = require("intersections")
local Rings = require("rings")
local Graph = require("greiner_hormann")
local Render = require("render")
local kinds = {"UNION", "INTERSECTION", "DIFFERENCE", "XOR", "CLIP", "AREA", "MOVE", "ROTATE", "MIRROR", "SNAP", "LOCATE", "RENDER"}
local binary = {UNION = true, INTERSECTION = true, DIFFERENCE = true, XOR = true, CLIP = true}
local definitions = {MOVE = true, ROTATE = true, MIRROR = true, SNAP = true}
local word_counts = {UNION = 3, INTERSECTION = 3, DIFFERENCE = 3, XOR = 3, CLIP = 3,
    AREA = 2, MOVE = 5, ROTATE = 6, MIRROR = 5, SNAP = 3, LOCATE = 4, RENDER = 8}

local function append(items, value)
    items[#items + 1] = value
end

local function extend(items, values)
    for _, value in ipairs(values) do append(items, value) end
end

local function words(line)
    local result = {}
    for word in line:gmatch("%S+") do append(result, word) end
    return result
end

local function digits(word)
    return word ~= nil and #word >= 1 and #word <= 9 and word:match("^%d+$") ~= nil
end

local function integer_word(word)
    return word ~= nil and digits(word:sub(1, 1) == "-" and word:sub(2) or word)
end

local function valid_name(word)
    return word ~= nil and #word >= 1 and #word <= 16 and word:match("^[a-z0-9_]+$") ~= nil
end

local function records(filename)
    local result, number = {}, 0
    for line in io.lines("input/" .. filename) do
        number = number + 1
        if line ~= "" and line:sub(1, 1) ~= "#" then append(result, {number = number, line = line}) end
    end
    return result
end

local function polygon(name, input_rings)
    local holes, sequence = {}, {Rings.normalize(input_rings[1], true)}
    for i = 2, #input_rings do append(holes, Rings.normalize(input_rings[i], false)) end
    table.sort(holes, function(a, b) return Rational.less(a[1], b[1]) end)
    extend(sequence, holes)
    return {name = name, input_rings = input_rings, rings = sequence}
end

local function parse_rings(content, end_line)
    local result, position = {}, 1
    while position <= #content do
        local record = content[position]
        local f = words(record.line)
        if #f ~= 2 or (f[1] ~= "OUTER" and f[1] ~= "HOLE") or not digits(f[2]) or tonumber(f[2]) < 1
            or (f[1] == "OUTER" and #result > 0) or (f[1] == "HOLE" and #result == 0) then return nil, record.number end
        local count, vertices = tonumber(f[2]), {}
        position = position + 1
        for _ = 1, count do
            if position > #content then return nil, end_line end
            local vertex = content[position]
            local coordinates = words(vertex.line)
            if #coordinates ~= 2 or not integer_word(coordinates[1]) or not integer_word(coordinates[2]) then return nil, vertex.number end
            append(vertices, Rational.point(tonumber(coordinates[1]), tonumber(coordinates[2])))
            position = position + 1
        end
        append(result, Rational.ring(vertices))
    end
    if #result == 0 then return nil, end_line end
    return result, nil
end

local function in_range(point)
    return point.x >= 0 and point.y >= 0 and point.x <= 1000 * point.d and point.y <= 1000 * point.d
end

local function check_ring(ring, number)
    local count = #ring
    if count < 3 then return "too_few_vertices ring " .. number end
    for _, point in ipairs(ring) do
        if not in_range(point) then return "out_of_range ring " .. number .. " " .. Rational.text(point) end
    end
    local seen = {}
    for _, point in ipairs(ring) do
        local key = Rational.key(point)
        if seen[key] then return "duplicate_vertex ring " .. number .. " " .. Rational.text(point) end
        seen[key] = true
    end
    for i, point in ipairs(ring) do
        if Rational.cross(ring[(i - 2) % count + 1], point, ring[i % count + 1]) == 0 then
            return "collinear ring " .. number .. " " .. Rational.text(point)
        end
    end
    for first = 1, count do
        for second = first + 2, count do
            if not (first == 1 and second == count) then
                local a, b, c, d = ring[first], ring[first % count + 1], ring[second], ring[second % count + 1]
                if Intersections.touch(a, b, c, d) then return "self_intersection ring " .. number .. " "
                    .. Rational.segment(a, b) .. " " .. Rational.segment(c, d) end
            end
        end
    end
end

local function check_polygon(sequence)
    for number, ring in ipairs(sequence) do local error = check_ring(ring, number); if error then return error end end
    for first = 1, #sequence do
        for second = first + 1, #sequence do
            local one, two = sequence[first], sequence[second]
            for e, a in ipairs(one) do
                local b = one[e % #one + 1]
                for f, c in ipairs(two) do
                    local d = two[f % #two + 1]
                    if Intersections.touch(a, b, c, d) then return string.format("rings_touch rings %d %d %s %s",
                        first, second, Rational.segment(a, b), Rational.segment(c, d)) end
                end
            end
        end
    end
    for index = 2, #sequence do
        if not Rings.inside(sequence[1], sequence[index][1]) then return "hole_outside ring " .. index .. " " .. Rational.text(sequence[index][1]) end
    end
    for first = 2, #sequence do
        for second = first + 1, #sequence do
            local point
            if Rings.inside(sequence[first], sequence[second][1]) then point = sequence[second][1]
            elseif Rings.inside(sequence[second], sequence[first][1]) then point = sequence[first][1] end
            if point then return string.format("hole_in_hole rings %d %d %s", first, second, Rational.text(point)) end
        end
    end
end

local Registry = {}
Registry.__index = Registry

function Registry.new()
    local self = setmetatable({used = {}, polygons = {}, invalid = {}, block_count = 0, valid_blocks = 0}, Registry)
    local lines, position = records("polygons.txt"), 1
    while position <= #lines do
        local start = lines[position]
        local name = words(start.line)[2]
        local content = {}
        position = position + 1
        while lines[position].line ~= "END" do append(content, lines[position]); position = position + 1 end
        local end_line = lines[position].number
        position, self.block_count = position + 1, self.block_count + 1
        if self.used[name] then append(self.invalid, {name, "duplicate_name line " .. start.number})
        else
            self.used[name] = true
            local sequence, error_line = parse_rings(content, end_line)
            local error = error_line and "format line " .. error_line or check_polygon(sequence)
            if error then append(self.invalid, {name, error})
            else self.polygons[name], self.valid_blocks = polygon(name, sequence), self.valid_blocks + 1 end
        end
    end
    return self
end

function Registry:resolve(name)
    if not self.used[name] then return nil, "unknown_polygon " .. name end
    if not self.polygons[name] then return nil, "invalid_polygon " .. name end
    return self.polygons[name], nil
end

local function arguments_valid(f)
    local kind = f[1]
    if #f ~= word_counts[kind] then return false end
    if binary[kind] or kind == "AREA" then return true end
    if kind == "SNAP" then return valid_name(f[3]) end
    if kind == "MIRROR" then return valid_name(f[5]) and (f[3] == "x" or f[3] == "y")
        and integer_word(f[4]) and tonumber(f[4]) >= 0 and tonumber(f[4]) <= 1000 end
    local last = (kind == "MOVE" or kind == "ROTATE") and #f - 1 or #f
    for i = 3, last do if not integer_word(f[i]) then return false end end
    if kind == "LOCATE" then return tonumber(f[3]) >= 0 and tonumber(f[3]) <= 1000 and tonumber(f[4]) >= 0 and tonumber(f[4]) <= 1000 end
    if kind == "MOVE" then return valid_name(f[5]) and math.abs(tonumber(f[3])) <= 1000 and math.abs(tonumber(f[4])) <= 1000 end
    if kind == "ROTATE" then return valid_name(f[6]) and tonumber(f[3]) >= 0 and tonumber(f[3]) <= 1000
        and tonumber(f[4]) >= 0 and tonumber(f[4]) <= 1000 and tonumber(f[5]) >= 1 and tonumber(f[5]) <= 3 end
    local x0, y0, width, height, columns, rows = tonumber(f[3]), tonumber(f[4]), tonumber(f[5]), tonumber(f[6]), tonumber(f[7]), tonumber(f[8])
    return x0 >= 0 and y0 >= 0 and width >= 1 and width <= 100 and height >= 1 and height <= 100
        and columns >= 1 and columns <= 100 and rows >= 1 and rows <= 60
        and x0 + width * columns <= 1000 and y0 + height * rows <= 1000
end

local function general_position(first, second)
    local second_vertices = {}
    for _, ring in ipairs(second.rings) do for _, point in ipairs(ring) do second_vertices[Rational.key(point)] = true end end
    for _, ring in ipairs(first.rings) do
        for _, point in ipairs(ring) do if second_vertices[Rational.key(point)] then return "shared_vertex " .. Rational.text(point) end end
    end
    for _, one in ipairs(first.rings) do
        for e, a in ipairs(one) do
            local b = one[e % #one + 1]
            for _, two in ipairs(second.rings) do
                for f, c in ipairs(two) do
                    local d = two[f % #two + 1]
                    if Intersections.overlap(a, b, c, d) then return "overlapping_edges " .. Rational.segment(a, b) .. " " .. Rational.segment(c, d) end
                end
            end
        end
    end
    for _, pair in ipairs({{first, second}, {second, first}}) do
        for _, ring in ipairs(pair[1].rings) do
            for _, point in ipairs(ring) do
                for _, other in ipairs(pair[2].rings) do
                    for e, a in ipairs(other) do
                        local b = other[e % #other + 1]
                        if Intersections.on_segment(point, a, b) then return "vertex_on_edge " .. pair[1].name .. " "
                            .. Rational.text(point) .. " " .. pair[2].name .. " " .. Rational.segment(a, b) end
                    end
                end
            end
        end
    end
end

local function transformed_rings(source, f)
    local result = {}
    for _, ring in ipairs(source.input_rings) do
        local transformed = {}
        for _, point in ipairs(ring) do
            local x, y = point.x, point.y
            if f[1] == "MOVE" then x, y = x + tonumber(f[3]), y + tonumber(f[4])
            elseif f[1] == "ROTATE" then
                local cx, cy = tonumber(f[3]), tonumber(f[4])
                for _ = 1, tonumber(f[5]) do x, y = cx - (y - cy), cy + (x - cx) end
            elseif f[3] == "x" then x = 2 * tonumber(f[4]) - x
            else y = 2 * tonumber(f[4]) - y end
            append(transformed, Rational.point(x, y))
        end
        append(result, Rational.ring(transformed))
    end
    return result
end

local function rounded_rings(source)
    local result = {}
    for _, ring in ipairs(source) do
        local rounded = {}
        for _, point in ipairs(ring) do append(rounded, Rational.snapped(point)) end
        append(result, Rational.ring(rounded))
    end
    return result
end

local function total_area(polygons)
    local total = 0.0
    for _, polygon in ipairs(polygons) do for _, ring in ipairs(polygon) do total = total + Rings.area(ring) end end
    return total
end

local function binary_result(kind, first, second)
    local graph = Graph.new(first.rings, second.rings)
    local intersection, union = Rings.assemble(graph:traverse(false, false)), Rings.assemble(graph:traverse(true, true))
    local polygons
    if kind == "UNION" then polygons = union
    elseif kind == "INTERSECTION" or kind == "CLIP" then polygons = intersection
    else
        polygons = Rings.assemble(graph:traverse(true, false))
        if kind == "XOR" then
            local reverse = Graph.new(second.rings, first.rings)
            extend(polygons, Rings.assemble(reverse:traverse(true, false)))
            table.sort(polygons, function(a, b) return Rational.less(a[1][1], b[1][1]) end)
        end
    end
    local relation
    if #graph.crossings > 0 then relation = "overlap"
    elseif graph.n_a == #first.rings and graph.n_b == 0 then relation = "within"
    elseif graph.n_b == #second.rings and graph.n_a == 0 then relation = "contains"
    elseif graph.n_a == 0 and graph.n_b == 0 then relation = "disjoint"
    else relation = "overlap" end
    return {polygons = polygons, operands = {first, second}}, graph, relation, total_area(intersection) / total_area(union)
end

local function cyclic_equal(first, second)
    if #first ~= #second then return false end
    for start, point in ipairs(second) do
        if Rational.equal(point, first[1]) then
            local equal = true
            for i = 1, #first do
                if not Rational.equal(first[i], second[(start + i - 2) % #second + 1]) then equal = false; break end
            end
            if equal then return true end
        end
    end
    return false
end

local function crosscheck_clip(first, window, polygons)
    local clipped = {}
    for _, ring in ipairs(first.rings) do
        local points = {}
        for i, point in ipairs(ring) do append(points, {point = point, incoming = ring.lines[(i - 2) % #ring + 1]}) end
        for _, line in ipairs(window.rings[1].lines) do
            local replacement = {}
            for i, current in ipairs(points) do
                local previous = points[(i - 2) % #points + 1]
                local a, b = Rational.line_cross(line.a, line.b, previous.point), Rational.line_cross(line.a, line.b, current.point)
                if (a > 0) ~= (b > 0) then
                    append(replacement, {point = Intersections.line_intersection(current.incoming, line), incoming = a > 0 and current.incoming or line})
                end
                if b > 0 then append(replacement, current) end
            end
            points = replacement
        end
        local deduplicated = {}
        for i, current in ipairs(points) do
            if not Rational.equal(current.point, points[(i - 2) % #points + 1].point) then append(deduplicated, current.point) end
        end
        if #deduplicated >= 3 then append(clipped, deduplicated) end
    end
    local count, vertices, matches = 0, 0, true
    for _, ring in ipairs(clipped) do vertices = vertices + #ring end
    for _, polygon in ipairs(polygons) do
        for _, ring in ipairs(polygon) do
            count = count + 1
            local found = false
            for _, other in ipairs(clipped) do if cyclic_equal(ring, other) then found = true; break end end
            if not found then matches = false end
        end
    end
    return matches and count == #clipped and "match" or "mismatch", #clipped, vertices
end

local function result_values(polygons, first, second)
    local values = {polygon_count = #polygons, ring_items = {}, area = 0.0, perimeter = 0.0, origins = {0, 0, 0}, vertex_count = 0}
    local first_vertices, second_vertices, sx, sy = {}, {}, 0.0, 0.0
    for _, ring in ipairs(first.rings) do for _, point in ipairs(ring) do first_vertices[Rational.key(point)] = true end end
    if second then for _, ring in ipairs(second.rings) do for _, point in ipairs(ring) do second_vertices[Rational.key(point)] = true end end end
    local min_x, min_y, max_x, max_y
    for p, polygon in ipairs(polygons) do
        for r, ring in ipairs(polygon) do
            local area = Rings.area(ring)
            values.area, values.perimeter = values.area + area, values.perimeter + Rings.perimeter(ring)
            append(values.ring_items, {polygon = p, hole = r - 1, ring = ring, area = area})
            values.vertex_count = values.vertex_count + #ring
            for i, point in ipairs(ring) do
                local key = Rational.key(point)
                local origin = first_vertices[key] and 1 or second_vertices[key] and 2 or 3
                values.origins[origin] = values.origins[origin] + 1
                if not min_x or Rational.x_less(point, min_x) then min_x = point end
                if not min_y or Rational.y_less(point, min_y) then min_y = point end
                if not max_x or Rational.x_less(max_x, point) then max_x = point end
                if not max_y or Rational.y_less(max_y, point) then max_y = point end
                local x1, y1 = Rational.real(point)
                local x2, y2 = Rational.real(ring[i % #ring + 1])
                local cross = x1 * y2 - x2 * y1
                sx, sy = sx + (x1 + x2) * cross, sy + (y1 + y2) * cross
            end
        end
    end
    values.ring_count = #values.ring_items
    values.hole_count = values.ring_count - values.polygon_count
    if min_x then
        values.low = "(" .. Rational.fraction(min_x.x, min_x.d) .. "," .. Rational.fraction(min_y.y, min_y.d) .. ")"
        values.high = "(" .. Rational.fraction(max_x.x, max_x.d) .. "," .. Rational.fraction(max_y.y, max_y.d) .. ")"
        values.centroid = string.format("(%.3f,%.3f)", sx / (6.0 * values.area), sy / (6.0 * values.area))
    end
    local lines = {string.format("polygons %d rings %d holes %d vertices %d area %.3f", values.polygon_count,
        values.ring_count, values.hole_count, values.vertex_count, values.area)}
    for _, item in ipairs(values.ring_items) do
        local prefix = item.hole == 0 and "outer " .. item.polygon or "hole " .. item.polygon .. " " .. item.hole
        local points = {}
        for _, point in ipairs(item.ring) do append(points, Rational.text(point)) end
        append(lines, prefix .. string.format(" %d %.3f %s", #item.ring, item.area, table.concat(points, " ")))
    end
    append(lines, values.low and "bbox " .. values.low .. " " .. values.high or "bbox none")
    append(lines, values.centroid and "centroid " .. values.centroid or "centroid none")
    append(lines, string.format("perimeter %.3f", values.perimeter))
    append(lines, string.format("origins a %d b %d crossing %d", values.origins[1], values.origins[2], values.origins[3]))
    values.lines = lines
    return values
end

local function convex_hull(outer)
    local ordered = {}
    for i, point in ipairs(outer) do ordered[i] = point end
    table.sort(ordered, function(a, b)
        if a.x ~= b.x then return a.x < b.x end
        return a.y < b.y
    end)
    local chains = {{}, {}}
    for side = 1, 2 do
        local chain = chains[side]
        for index = 1, #ordered do
            local point = ordered[side == 1 and index or #ordered - index + 1]
            while #chain >= 2 and Rational.cross(chain[#chain - 1], chain[#chain], point) <= 0 do table.remove(chain) end
            append(chain, point)
        end
        table.remove(chain)
    end
    extend(chains[1], chains[2])
    return Rational.ring(chains[1])
end

local function property_lines(polygon, area)
    local orientations, reflex = {}, 0
    for _, ring in ipairs(polygon.input_rings) do
        local double_area = 0
        for i, point in ipairs(ring) do
            local next_point = ring[i % #ring + 1]
            double_area = double_area + point.x * next_point.y - next_point.x * point.y
        end
        append(orientations, double_area > 0 and "ccw" or "cw")
    end
    for _, ring in ipairs(polygon.rings) do
        for i, point in ipairs(ring) do
            if Rational.cross(ring[(i - 2) % #ring + 1], point, ring[i % #ring + 1]) < 0 then reflex = reflex + 1 end
        end
    end
    local hull, double_area = convex_hull(polygon.rings[1]), 0
    for i, point in ipairs(hull) do
        local next_point = hull[i % #hull + 1]
        double_area = double_area + point.x * next_point.y - next_point.x * point.y
    end
    local hull_area = (double_area + 0.0) / 2.0
    return {"input " .. table.concat(orientations, " "), "reflex " .. reflex,
        string.format("hull %d %.3f solidity %.6f", #hull, hull_area, area / hull_area)}
end

local function locate(polygons, point)
    for number, polygon in ipairs(polygons) do
        if Rings.boundary(polygon[1], point) then return "boundary outer " .. number end
        for hole = 2, #polygon do if Rings.boundary(polygon[hole], point) then return "boundary hole " .. number .. " " .. (hole - 1) end end
    end
    for number, polygon in ipairs(polygons) do
        if Rings.inside(polygon[1], point) then
            local in_hole = false
            for hole = 2, #polygon do if Rings.inside(polygon[hole], point) then in_hole = true; break end end
            if not in_hole then return "inside polygon " .. number end
        end
    end
    return "outside"
end

local function operand_location(polygon, point)
    for _, ring in ipairs(polygon.rings) do if Rings.boundary(ring, point) then return "boundary" end end
    return Rings.interior(polygon.rings, point) and "inside" or "outside"
end

local Processor = {}
Processor.__index = Processor

function Processor.new()
    local self = setmetatable({registry = Registry.new(), operations = records("operations.txt"), regions = {}, results = {},
        areas = {"operation,rings,holes,vertices,area"}, drawings = {}, rejected_operations = {}, kind_totals = {},
        kind_succeeded = {}, succeeded = 0, defined = 0, crossings = 0}, Processor)
    for _, kind in ipairs(kinds) do self.kind_totals[kind], self.kind_succeeded[kind] = 0, 0 end
    return self
end

function Processor:resolve_target(word)
    if word:sub(1, 1) == "@" then
        local number = word:sub(2)
        if not digits(number) or not self.regions[tonumber(number)] then return nil, "bad_target " .. word end
        return self.regions[tonumber(number)], nil
    end
    local polygon, error = self.registry:resolve(word)
    if error then return nil, error end
    return {polygons = {polygon.rings}}, nil
end

function Processor:check_operation(f)
    local kind, checked, error = f[1], {}, nil
    if not word_counts[kind] then return nil, "unknown_operation " .. kind end
    if not arguments_valid(f) then return nil, "bad_arguments" end
    if binary[kind] then
        checked.a, error = self.registry:resolve(f[2])
        if error then return nil, error end
        checked.b, error = self.registry:resolve(f[3])
    elseif kind == "AREA" or kind == "MOVE" or kind == "ROTATE" or kind == "MIRROR" then
        checked.a, error = self.registry:resolve(f[2])
    else checked.target, error = self:resolve_target(f[2]) end
    if error then return nil, error end
    if definitions[kind] and self.registry.used[f[#f]] then return nil, "duplicate_name " .. f[#f] end
    if kind == "SNAP" and #checked.target.polygons ~= 1 then return nil, "not_single " .. f[2] end
    if kind == "CLIP" then
        local sequence = checked.b.rings
        if #sequence > 1 then return nil, "not_convex " .. f[3] end
        local ring = sequence[1]
        for i, point in ipairs(ring) do
            if Rational.cross(ring[(i - 2) % #ring + 1], point, ring[i % #ring + 1]) <= 0 then return nil, "not_convex " .. f[3] end
        end
    end
    if binary[kind] then error = general_position(checked.a, checked.b); if error then return nil, error end end
    if kind == "MOVE" or kind == "ROTATE" or kind == "MIRROR" then
        local sequence = transformed_rings(checked.a, f)
        for _, ring in ipairs(sequence) do
            for _, point in ipairs(ring) do if not in_range(point) then return nil, "out_of_range " .. f[#f] end end
        end
        checked.defined = polygon(f[#f], sequence)
    elseif kind == "SNAP" then
        local sequence = rounded_rings(checked.target.polygons[1])
        error = check_polygon(sequence)
        if error then return nil, "invalid_result " .. error end
        checked.defined = polygon(f[#f], sequence)
    end
    return checked, nil
end

function Processor:record_region(number, line, f, checked)
    local kind, region, first, second = f[1]
    append(self.results, "op " .. number .. " " .. line)
    if binary[kind] then
        first, second = checked.a, checked.b
        local graph, relation, iou
        region, graph, relation, iou = binary_result(kind, first, second)
        append(self.results, string.format("relation %s iou %.6f", relation, iou))
        append(self.results, "crossings " .. #graph.crossings)
        self.crossings = self.crossings + #graph.crossings
        for _, crossing in ipairs(graph.crossings) do append(self.results, "crossing " .. Rational.text(crossing.point)
            .. " " .. (crossing.first.entering and "in" or "out")) end
    else
        first = definitions[kind] and checked.defined or checked.a
        region = {polygons = {first.rings}}
    end
    self.regions[number] = region
    local values = result_values(region.polygons, first, second)
    extend(self.results, values.lines)
    if not binary[kind] then extend(self.results, property_lines(first, values.area)) end
    if kind == "CLIP" then
        local decision, count, vertices = crosscheck_clip(first, second, region.polygons)
        append(self.results, string.format("crosscheck %s rings %d vertices %d", decision, count, vertices))
    end
    append(self.areas, string.format("%d:%s,%d,%d,%d,%.3f", number, table.concat(f, ":"),
        values.ring_count, values.hole_count, values.vertex_count, values.area))
end

function Processor:record_location(number, line, f, target)
    local point = Rational.point(tonumber(f[3]), tonumber(f[4]))
    append(self.results, "op " .. number .. " " .. line)
    append(self.results, "location " .. locate(target.polygons, point))
    if target.operands then append(self.results, "operands a " .. operand_location(target.operands[1], point)
        .. " b " .. operand_location(target.operands[2], point)) end
end

function Processor:record_render(number, f, target)
    local x0, y0, width, height, columns, rows = tonumber(f[3]), tonumber(f[4]), tonumber(f[5]), tonumber(f[6]), tonumber(f[7]), tonumber(f[8])
    local lines, counts = Render.grid(target.polygons, target.operands, x0, y0, width, height, columns, rows)
    append(self.drawings, string.format("render %d %s cols %d rows %d result %d a %d b %d both %d", number,
        f[2], columns, rows, counts["#"], counts.a, counts.b, counts["+"]))
    extend(self.drawings, lines)
end

function Processor:process()
    for number, operation in ipairs(self.operations) do
        local f = words(operation.line)
        local kind = f[1]
        if self.kind_totals[kind] then self.kind_totals[kind] = self.kind_totals[kind] + 1 end
        local checked, error = self:check_operation(f)
        if error then append(self.rejected_operations, {number, error})
        else
            self.succeeded, self.kind_succeeded[kind] = self.succeeded + 1, self.kind_succeeded[kind] + 1
            if definitions[kind] then
                local defined = checked.defined
                self.registry.used[defined.name], self.registry.polygons[defined.name], self.defined = true, defined, self.defined + 1
            end
            if kind == "RENDER" then self:record_render(number, f, checked.target)
            elseif kind == "LOCATE" then self:record_location(number, operation.line, f, checked.target)
            else self:record_region(number, operation.line, f, checked) end
        end
    end
    local registry = self.registry
    append(self.results, string.format("summary polygons %d valid %d invalid %d defined %d", registry.block_count,
        registry.valid_blocks, #registry.invalid, self.defined))
    append(self.results, string.format("summary operations %d succeeded %d rejected %d", #self.operations, self.succeeded, #self.rejected_operations))
    append(self.results, "summary crossings " .. self.crossings)
    for _, kind in ipairs(kinds) do append(self.results, string.format("kind %s %d %d", kind, self.kind_totals[kind], self.kind_succeeded[kind])) end
end

function Processor:write()
    local rejections = {"rejections " .. (#self.registry.invalid + #self.rejected_operations)}
    for _, item in ipairs(self.registry.invalid) do append(rejections, "polygon " .. item[1] .. " " .. item[2]) end
    for _, item in ipairs(self.rejected_operations) do append(rejections, "op " .. item[1] .. " " .. item[2]) end
    assert(os.execute("mkdir -p output"))
    for _, report in ipairs({{"results.txt", self.results}, {"areas.csv", self.areas}, {"render.txt", self.drawings}, {"rejections.txt", rejections}}) do
        local file = assert(io.open("output/" .. report[1], "wb"))
        for _, line in ipairs(report[2]) do file:write(line, "\n") end
        file:close()
    end
end

local processor = Processor.new()
processor:process()
processor:write()
