local pgm_io = require("pgm_io")
local filters = require("filters")
local canny = require("canny")
local hough = require("hough")
local corners_module = require("corners")
local image, trig, params = pgm_io.read()
local height, width = #image, #image[1]
local function cross(a, b)
    return a[1] * b[2] - a[2] * b[1]
end
local function dot(a, b)
    return a[1] * b[1] + a[2] * b[2]
end
local function difference(a, b)
    return {a[1] - b[1], a[2] - b[2]}
end
local function chebyshev(a, b)
    return math.max(math.abs(a[1] - b[1]), math.abs(a[2] - b[2]))
end
local function angle_difference(a, b)
    local gap = math.abs(a - b)
    return math.min(gap, 180 - gap)
end
local function nearest(numerator, denominator)
    if denominator < 0 then
        numerator, denominator = -numerator, -denominator
    end
    return (2 * numerator + denominator) // (2 * denominator)
end
local function key(point)
    return point[2] * width + point[1] + 1
end
local function inside_image(point)
    return point[1] >= 0 and point[1] < width and point[2] >= 0 and point[2] < height
end
local function bresenham(first, last)
    local x, y, x1, y1 = first[1], first[2], last[1], last[2]
    local dx, dy = math.abs(x1 - x), -math.abs(y1 - y)
    local sx, sy = x < x1 and 1 or -1, y < y1 and 1 or -1
    local error, result = dx + dy, {}
    while true do
        result[#result + 1] = {x, y}
        if x == x1 and y == y1 then
            break
        end
        local doubled = 2 * error
        if doubled >= dy then
            error, x = error + dy, x + sx
        end
        if doubled <= dx then
            error, y = error + dx, y + sy
        end
    end
    return result
end
local function set_count(values)
    local count = 0
    for _ in pairs(values) do
        count = count + 1
    end
    return count
end
local function words(values)
    local fields = {}
    for _, value in ipairs(values) do
        fields[#fields + 1] = tostring(value)
    end
    return table.concat(fields, " ")
end
local smoothed = filters.smoothing(image, params.gauss_size, params.gauss_kernel, params.gauss_divisor)
local gx, gy, magnitude = filters.gradient(smoothed)
local directions = canny.directions(gx, gy)
local nonmax = canny.suppress(magnitude, directions)
local edges, strong, weak = canny.hysteresis(nonmax, params.canny_low, params.canny_high)
local edge_points = {}
for y = 0, height - 1 do
    for x = 0, width - 1 do
        if edges[y * width + x + 1] then
            edge_points[#edge_points + 1] = {x, y}
        end
    end
end
local components = canny.components(edges, width, height)
for _, component in ipairs(components) do
    local low_x, low_y, high_x, high_y = width, height, -1, -1
    local ends, strength, counts = 0, 0, {[0] = 0, [45] = 0, [90] = 0, [135] = 0}
    for _, point in ipairs(component.pixels) do
        local x, y, neighbors = point[1], point[2], 0
        low_x, low_y, high_x, high_y = math.min(low_x, x), math.min(low_y, y), math.max(high_x, x), math.max(high_y, y)
        for _, neighbor in ipairs(canny.neighbors(width, height, x, y)) do
            if edges[key(neighbor)] then
                neighbors = neighbors + 1
            end
        end
        ends = ends + (neighbors == 1 and 1 or 0)
        strength = strength + magnitude[y + 1][x + 1]
        local direction = directions[y + 1][x + 1]
        counts[direction] = counts[direction] + 1
    end
    local main_direction, greatest = 0, -1
    for _, direction in ipairs({0, 45, 90, 135}) do
        if counts[direction] > greatest then
            main_direction, greatest = direction, counts[direction]
        end
    end
    component.box, component.ends, component.strength, component.direction = {low_x, low_y, high_x, high_y}, ends, strength // #component.pixels, main_direction
end
local circle_cells, outlines = hough.circle_votes(edge_points, width, height, params.circle_min_radius, params.circle_max_radius)
local circle_candidate_count, circle_peaks = hough.circle_peaks(circle_cells, outlines, width, height,
    params.circle_min_radius, params.circle_max_radius, params.circle_min_percent)
table.sort(circle_peaks, function(a, b)
    local left, right = a.votes * b.points, b.votes * a.points
    if left ~= right then
        return left > right
    elseif a.radius ~= b.radius then
        return a.radius < b.radius
    elseif a.y ~= b.y then
        return a.y < b.y
    end
    return a.x < b.x
end)
local function ordered_outline(points)
    local result = {table.unpack(points)}
    local function half(point)
        return (point[2] > 0 or point[2] == 0 and point[1] > 0) and 0 or 1
    end
    table.sort(result, function(a, b)
        local ha, hb = half(a), half(b)
        if ha ~= hb then
            return ha < hb
        end
        local turn = cross(a, b)
        if turn ~= 0 then
            return turn > 0
        end
        return a[1] < b[1] or a[1] == b[1] and a[2] < b[2]
    end)
    return result
end
local circles = {}
for index = 1, math.min(params.circle_max_count, #circle_peaks) do
    local peak = circle_peaks[index]
    local circle = {number = index, shape_type = "circle", center = {peak.x, peak.y}, radius = peak.radius,
        votes = peak.votes, outline = outlines[peak.radius], points = peak.points}
    local hits, hit_count = {}, 0
    for _, offset in ipairs(ordered_outline(circle.outline)) do
        local point = {peak.x + offset[1], peak.y + offset[2]}
        local hit = inside_image(point) and edges[key(point)] or false
        hits[#hits + 1] = hit
        hit_count = hit_count + (hit and 1 or 0)
    end
    local gap, arcs = 0, 0
    if hit_count == #hits then
        arcs = 1
    elseif hit_count == 0 then
        gap = #hits
    else
        for i, hit in ipairs(hits) do
            if hit and not hits[(i - 2) % #hits + 1] then
                arcs = arcs + 1
            end
        end
        local run = 0
        for i = 1, 2 * #hits do
            if hits[(i - 1) % #hits + 1] then
                run = 0
            else
                run = run + 1
                gap = math.max(gap, run)
            end
        end
        gap = math.min(gap, #hits)
    end
    circle.gap, circle.arcs = gap, arcs
    circles[#circles + 1] = circle
end
local function circumference(circle, point)
    local delta = difference(point, circle.center)
    local squared = dot(delta, delta)
    return (circle.radius - 1) * (circle.radius - 1) <= squared and squared <= (circle.radius + 1) * (circle.radius + 1)
end
local circle_edge, line_edge = {}, {}
for _, point in ipairs(edge_points) do
    local claimed = false
    for _, circle in ipairs(circles) do
        if circumference(circle, point) then
            claimed = true
            break
        end
    end
    if claimed then
        circle_edge[key(point)] = true
    else
        line_edge[#line_edge + 1] = point
    end
end
local line_votes = hough.line_votes(line_edge, trig, params.hough_rho_step)
local line_peaks = hough.line_peaks(line_votes, params.hough_threshold)
table.sort(line_peaks, function(a, b)
    return a.votes > b.votes or a.votes == b.votes and (a.theta < b.theta or a.theta == b.theta and a.rho < b.rho)
end)
local lines, segments, used = {}, {}, {}
for _, peak in ipairs(line_peaks) do
    if #lines >= params.hough_max_lines then
        break
    end
    local available, row = {}, trig[peak.theta]
    for _, point in ipairs(line_edge) do
        if not used[key(point)] and math.abs(hough.rho(point, peak.theta, trig, params.hough_rho_step) - peak.rho) <= params.segment_tolerance then
            available[#available + 1] = {point = point, u = point[2] * row[1] - point[1] * row[2]}
        end
    end
    table.sort(available, function(a, b)
        return a.u < b.u or a.u == b.u and (a.point[1] < b.point[1] or a.point[1] == b.point[1] and a.point[2] < b.point[2])
    end)
    local groups, current = {}, {}
    for index, item in ipairs(available) do
        if index > 1 and item.u - available[index - 1].u > params.segment_max_gap * 16384 then
            groups[#groups + 1], current = current, {}
        end
        current[#current + 1] = item.point
    end
    if #current > 0 then
        groups[#groups + 1] = current
    end
    local pending = {}
    for _, group in ipairs(groups) do
        local first, last = group[1], group[#group]
        local length = chebyshev(first, last) + 1
        if length >= params.segment_min_length then
            pending[#pending + 1] = {first = first, last = last, length = length, pixels = #group, points = group, theta = peak.theta}
        end
    end
    if #pending > 0 then
        local line = {number = #lines + 1, theta = peak.theta, rho = peak.rho, votes = peak.votes, segments = {}}
        for _, segment in ipairs(pending) do
            segment.number, segment.line = #segments + 1, line.number
            segments[#segments + 1], line.segments[#line.segments + 1] = segment, segment.number
            for _, point in ipairs(segment.points) do
                used[key(point)] = true
            end
        end
        lines[#lines + 1] = line
    end
end
local junctions, graph, junction_count = {}, {}, 0
for index = 1, #segments do
    junctions[index], graph[index] = {}, {}
end
local function junction_end(segment, point)
    local start, ending = chebyshev(segment.first, point), chebyshev(segment.last, point)
    return start <= ending and 0 or 1, math.min(start, ending)
end
for a = 1, #segments - 1 do
    for b = a + 1, #segments do
        local first, second = segments[a], segments[b]
        if angle_difference(first.theta, second.theta) >= params.junction_min_angle then
            local da, db = difference(first.last, first.first), difference(second.last, second.first)
            local denominator = cross(da, db)
            if denominator ~= 0 then
                local lambda = cross(difference(second.first, first.first), db)
                local point = {nearest(first.first[1] * denominator + lambda * da[1], denominator),
                    nearest(first.first[2] * denominator + lambda * da[2], denominator)}
                local end_a, distance_a = junction_end(first, point)
                local end_b, distance_b = junction_end(second, point)
                if distance_a <= params.junction_distance and distance_b <= params.junction_distance then
                    local joined = {point = point, ends = {[a] = end_a, [b] = end_b}}
                    junctions[a][b], junctions[b][a] = joined, joined
                    graph[a][#graph[a] + 1], graph[b][#graph[b] + 1] = b, a
                    junction_count = junction_count + 1
                end
            end
        end
    end
end
for _, neighbors in ipairs(graph) do
    table.sort(neighbors)
end
local polygons = {}
for _, count in ipairs({3, 4}) do
    for first = 1, #segments do
        local function extend(sequence, present)
            if #sequence == count then
                if sequence[2] >= sequence[count] or not junctions[sequence[count]][first] then
                    return
                end
                local vertices = {}
                for i, segment in ipairs(sequence) do
                    local previous, following = sequence[(i - 2) % count + 1], sequence[i % count + 1]
                    local entry, exit = junctions[previous][segment], junctions[segment][following]
                    if entry.ends[segment] == exit.ends[segment] then
                        return
                    end
                    vertices[#vertices + 1] = entry.point
                end
                local positive, negative = true, true
                for i, point in ipairs(vertices) do
                    local next_point, after = vertices[i % count + 1], vertices[(i + 1) % count + 1]
                    local turn = cross(difference(next_point, point), difference(after, next_point))
                    positive, negative = positive and turn > 0, negative and turn < 0
                end
                if positive or negative then
                    polygons[#polygons + 1] = {number = #polygons + 1, shape_type = "polygon", segments = {table.unpack(sequence)}, vertices = vertices}
                end
                return
            end
            for _, candidate in ipairs(graph[sequence[#sequence]]) do
                if candidate > first and not present[candidate] then
                    sequence[#sequence + 1], present[candidate] = candidate, true
                    extend(sequence, present)
                    sequence[#sequence], present[candidate] = nil, nil
                end
            end
        end
        extend({first}, {[first] = true})
    end
end
local function near_edge(point)
    for dy = -1, 1 do
        for dx = -1, 1 do
            local neighbor = {point[1] + dx, point[2] + dy}
            if inside_image(neighbor) and edges[key(neighbor)] then
                return true
            end
        end
    end
    return false
end
local polygon_kinds = {"equilateral_triangle", "right_triangle", "triangle", "square", "rectangle", "parallelogram", "trapezoid", "quadrilateral"}
for _, polygon in ipairs(polygons) do
    local count, vertices = #polygon.segments, polygon.vertices
    local theta = {}
    for _, segment in ipairs(polygon.segments) do
        theta[#theta + 1] = segments[segment].theta
    end
    polygon.angles, polygon.lengths, polygon.supports, polygon.vertex_corners, polygon.sigma = {}, {}, {}, {}, 0
    local all_sixty, any_right, all_right = true, false, true
    for i, point in ipairs(vertices) do
        local previous, following = vertices[(i - 2) % count + 1], vertices[i % count + 1]
        local phi = angle_difference(theta[(i - 2) % count + 1], theta[i])
        if dot(difference(previous, point), difference(following, point)) < 0 then
            phi = 180 - phi
        end
        polygon.angles[i] = phi
        local side = difference(following, point)
        polygon.lengths[i] = dot(side, side)
        local raster, support = bresenham(point, following), 0
        for _, pixel in ipairs(raster) do
            support = support + (near_edge(pixel) and 1 or 0)
        end
        polygon.supports[i], polygon.vertex_corners[i] = 100 * support // #raster, 0
        polygon.sigma = polygon.sigma + cross(point, following)
        all_sixty = all_sixty and math.abs(phi - 60) <= params.angle_tolerance
        any_right = any_right or math.abs(phi - 90) <= params.angle_tolerance
        all_right = all_right and math.abs(phi - 90) <= params.angle_tolerance
    end
    if count == 3 then
        polygon.kind = all_sixty and "equilateral_triangle" or any_right and "right_triangle" or "triangle"
    else
        local first_parallel = angle_difference(theta[1], theta[3]) <= params.angle_tolerance
        local second_parallel = angle_difference(theta[2], theta[4]) <= params.angle_tolerance
        if not first_parallel and not second_parallel then
            polygon.kind = "quadrilateral"
        elseif first_parallel ~= second_parallel then
            polygon.kind = "trapezoid"
        elseif not all_right then
            polygon.kind = "parallelogram"
        else
            local low, high = polygon.lengths[1], polygon.lengths[1]
            for _, length in ipairs(polygon.lengths) do
                low, high = math.min(low, length), math.max(high, length)
            end
            polygon.kind = 100 * (high - low) <= params.square_tolerance * high and "square" or "rectangle"
        end
    end
end
local shapes = {}
for _, polygon in ipairs(polygons) do
    shapes[#shapes + 1] = polygon
end
for _, circle in ipairs(circles) do
    shapes[#shapes + 1] = circle
end
local function representatives(shape)
    if shape.shape_type == "polygon" then
        return shape.vertices
    end
    local x, y, radius = shape.center[1], shape.center[2], shape.radius
    return {{x + radius, y}, {x, y + radius}, {x - radius, y}, {x, y - radius}}
end
local function contains(shape, point)
    if shape.shape_type == "circle" then
        local delta = difference(point, shape.center)
        return dot(delta, delta) <= shape.radius * shape.radius
    end
    for i, vertex in ipairs(shape.vertices) do
        local side = difference(shape.vertices[i % #shape.vertices + 1], vertex)
        local turn = cross(side, difference(point, vertex))
        if turn ~= 0 and (turn > 0) ~= (shape.sigma > 0) then
            return false
        end
    end
    return true
end
local function shape_name(shape)
    return shape and shape.shape_type .. " " .. shape.number or "none"
end
for _, shape in ipairs(shapes) do
    local points = representatives(shape)
    local low_x, high_x, low_y, high_y = points[1][1], points[1][1], points[1][2], points[1][2]
    for _, point in ipairs(points) do
        low_x, high_x, low_y, high_y = math.min(low_x, point[1]), math.max(high_x, point[1]), math.min(low_y, point[2]), math.max(high_y, point[2])
    end
    low_x, high_x = math.max(0, low_x - params.contrast_margin), math.min(width - 1, high_x + params.contrast_margin)
    low_y, high_y = math.max(0, low_y - params.contrast_margin), math.min(height - 1, high_y + params.contrast_margin)
    local inside_count, outside_count, inside_sum, outside_sum = 0, 0, 0, 0
    for y = low_y, high_y do
        for x = low_x, high_x do
            local value = image[y + 1][x + 1]
            if contains(shape, {x, y}) then
                inside_count, inside_sum = inside_count + 1, inside_sum + value
            else
                outside_count, outside_sum = outside_count + 1, outside_sum + value
            end
        end
    end
    shape.pixels = inside_count
    shape.mean = inside_count > 0 and inside_sum // inside_count or 0
    shape.contrast = shape.mean - (outside_count > 0 and outside_sum // outside_count or 0)
end
for _, child in ipairs(shapes) do
    local enclosing = nil
    for _, parent in ipairs(shapes) do
        if parent ~= child and parent.pixels > child.pixels then
            local all_inside = true
            for _, point in ipairs(representatives(child)) do
                if not contains(parent, point) then
                    all_inside = false
                    break
                end
            end
            if all_inside and (not enclosing or parent.pixels < enclosing.pixels) then
                enclosing = parent
            end
        end
    end
    child.enclosing = enclosing
end
local corner_candidates = corners_module.detect(gx, gy, params.harris_window, params.harris_threshold)
local corners = {}
for index = 1, math.min(#corner_candidates, params.harris_max_count) do
    local corner = corner_candidates[index]
    corner.number, corner.match, corner.match_kind = index, "none", "none"
    local position, best = {corner.x, corner.y}, nil
    for _, polygon in ipairs(polygons) do
        for vertex, point in ipairs(polygon.vertices) do
            local distance = chebyshev(position, point)
            if distance <= params.corner_match_distance and (not best or distance < best) then
                best, corner.match, corner.match_kind = distance, "polygon " .. polygon.number .. " vertex " .. vertex, "vertex"
            end
        end
    end
    if not best then
        for _, segment in ipairs(segments) do
            for ending, point in ipairs({segment.first, segment.last}) do
                local distance = chebyshev(position, point)
                if distance <= params.corner_match_distance and (not best or distance < best) then
                    best, corner.match, corner.match_kind = distance, "segment " .. segment.number .. (ending == 1 and " start" or " end"), "segment"
                end
            end
        end
    end
    corners[#corners + 1] = corner
end
local vertices_with_corner = 0
for _, polygon in ipairs(polygons) do
    for i, point in ipairs(polygon.vertices) do
        local best = nil
        for _, corner in ipairs(corners) do
            local distance = chebyshev(point, {corner.x, corner.y})
            if distance <= params.corner_match_distance and (not best or distance < best) then
                best, polygon.vertex_corners[i] = distance, corner.number
            end
        end
        if best then
            vertices_with_corner = vertices_with_corner + 1
        end
    end
end
for _, shape in ipairs(shapes) do
    local explained = {}
    if shape.shape_type == "circle" then
        for _, point in ipairs(edge_points) do
            if circumference(shape, point) then
                explained[key(point)] = true
            end
        end
    else
        for i, first in ipairs(shape.vertices) do
            for _, point in ipairs(bresenham(first, shape.vertices[i % #shape.vertices + 1])) do
                for dy = -1, 1 do
                    for dx = -1, 1 do
                        local neighbor = {point[1] + dx, point[2] + dy}
                        if inside_image(neighbor) and edges[key(neighbor)] then
                            explained[key(neighbor)] = true
                        end
                    end
                end
            end
        end
    end
    shape.explained = explained
end
for _, component in ipairs(components) do
    component.explained, component.shape = 0, nil
    for _, shape in ipairs(shapes) do
        local count = 0
        for _, point in ipairs(component.pixels) do
            if shape.explained[key(point)] then
                count = count + 1
            end
        end
        if count > component.explained then
            component.explained, component.shape = count, shape
        end
    end
end
local overlay, edge_image = {}, {}
for y = 1, height do
    overlay[y], edge_image[y] = {}, {}
    for x = 1, width do
        overlay[y][x], edge_image[y][x] = image[y][x] // params.overlay_divisor, edges[(y - 1) * width + x] and 255 or 0
    end
end
local function mark(point)
    if inside_image(point) then
        overlay[point[2] + 1][point[1] + 1] = 255
    end
end
for _, segment in ipairs(segments) do
    for _, point in ipairs(bresenham(segment.first, segment.last)) do
        mark(point)
    end
end
for _, circle in ipairs(circles) do
    for _, point in ipairs(circle.outline) do
        mark({circle.center[1] + point[1], circle.center[2] + point[2]})
    end
end
for _, corner in ipairs(corners) do
    for offset = -2, 2 do
        mark({corner.x + offset, corner.y})
        mark({corner.x, corner.y + offset})
    end
end
local rho_low, rho_high, maximum_votes = 0, 0, 0
local image_corners = {{0, 0}, {width - 1, 0}, {0, height - 1}, {width - 1, height - 1}}
for angle = 0, 179 do
    for _, point in ipairs(image_corners) do
        local value = hough.rho(point, angle, trig, params.hough_rho_step)
        rho_low, rho_high = math.min(rho_low, value), math.max(rho_high, value)
    end
    for _, value in pairs(line_votes[angle]) do
        maximum_votes = math.max(maximum_votes, value)
    end
end
local vote_image = {}
for radial = rho_low, rho_high do
    local row = {}
    for angle = 0, 179 do
        row[#row + 1] = maximum_votes > 0 and 255 * (line_votes[angle][radial] or 0) // maximum_votes or 0
    end
    vote_image[#vote_image + 1] = row
end
local function lines_listing()
    local result = {"lines " .. #lines}
    for _, line in ipairs(lines) do
        result[#result + 1] = "line " .. line.number .. " theta " .. line.theta .. " rho " .. line.rho .. " votes " .. line.votes .. " segments " .. #line.segments
        for _, number in ipairs(line.segments) do
            local segment = segments[number]
            result[#result + 1] = "segment " .. number .. " start " .. words(segment.first) .. " end " .. words(segment.last) .. " length " .. segment.length .. " pixels " .. segment.pixels
        end
    end
    return result
end
local function circles_listing()
    local result = {"circles " .. #circles}
    for _, circle in ipairs(circles) do
        result[#result + 1] = "circle " .. circle.number .. " center " .. words(circle.center) .. " radius " .. circle.radius .. " votes " .. circle.votes ..
            " points " .. circle.points .. " gap " .. circle.gap .. " arcs " .. circle.arcs .. " pixels " .. circle.pixels .. " mean " .. circle.mean ..
            " contrast " .. circle.contrast .. " inside " .. shape_name(circle.enclosing)
    end
    return result
end
local function polygons_listing()
    local result = {"polygons " .. #polygons}
    for _, polygon in ipairs(polygons) do
        local area = math.abs(polygon.sigma)
        local area_text = area // 2 .. (area % 2 == 0 and ".0" or ".5")
        result[#result + 1] = "polygon " .. polygon.number .. " " .. polygon.kind .. " segments " .. words(polygon.segments) .. " area " .. area_text ..
            " pixels " .. polygon.pixels .. " mean " .. polygon.mean .. " contrast " .. polygon.contrast .. " inside " .. shape_name(polygon.enclosing)
        for i, point in ipairs(polygon.vertices) do
            local corner = polygon.vertex_corners[i]
            result[#result + 1] = "vertex " .. i .. " " .. words(point) .. " angle " .. polygon.angles[i] .. " corner " .. (corner == 0 and "none" or corner)
        end
        for i, number in ipairs(polygon.segments) do
            result[#result + 1] = "side " .. i .. " segment " .. number .. " length2 " .. polygon.lengths[i] .. " support " .. polygon.supports[i]
        end
    end
    return result
end
local function corners_listing()
    local result = {"corners " .. #corners}
    for _, corner in ipairs(corners) do
        result[#result + 1] = "corner " .. corner.number .. " " .. corner.x .. " " .. corner.y .. " response " .. corner.response .. " match " .. corner.match
    end
    return result
end
local function components_listing()
    local result = {"components " .. #components}
    for _, component in ipairs(components) do
        result[#result + 1] = "component " .. component.number .. " pixels " .. #component.pixels .. " box " .. words(component.box) .. " ends " .. component.ends ..
            " strength " .. component.strength .. " direction " .. component.direction .. " shape " .. shape_name(component.shape) .. " explained " .. component.explained
    end
    return result
end
local function report_lines()
    local gradient_nonzero, gradient_maximum, nms_kept, weak_kept = 0, 0, 0, 0
    local direction_counts, kind_counts, match_counts = {[0] = 0, [45] = 0, [90] = 0, [135] = 0}, {}, {vertex = 0, segment = 0, none = 0}
    for y = 1, height do
        for x = 1, width do
            gradient_nonzero = gradient_nonzero + (magnitude[y][x] > 0 and 1 or 0)
            gradient_maximum = math.max(gradient_maximum, magnitude[y][x])
            nms_kept = nms_kept + (nonmax[y][x] > 0 and 1 or 0)
            local pixel = (y - 1) * width + x
            if edges[pixel] then
                direction_counts[directions[y][x]] = direction_counts[directions[y][x]] + 1
                weak_kept = weak_kept + (weak[pixel] and 1 or 0)
            end
        end
    end
    for _, polygon in ipairs(polygons) do
        kind_counts[polygon.kind] = (kind_counts[polygon.kind] or 0) + 1
    end
    for _, corner in ipairs(corners) do
        match_counts[corner.match_kind] = match_counts[corner.match_kind] + 1
    end
    local result = {"image " .. width .. " " .. height, "gradient_nonzero " .. gradient_nonzero, "gradient_max " .. gradient_maximum,
        "nms_kept " .. nms_kept, "strong " .. set_count(strong), "weak " .. set_count(weak), "edges " .. #edge_points,
        "weak_kept " .. weak_kept, "weak_dropped " .. set_count(weak) - weak_kept, "edge_components " .. #components}
    for _, direction in ipairs({0, 45, 90, 135}) do
        result[#result + 1] = "direction_" .. direction .. " " .. direction_counts[direction]
    end
    local values = {{"circle_candidates", circle_candidate_count}, {"circle_peaks", #circle_peaks}, {"circles", #circles},
        {"circle_edge_pixels", set_count(circle_edge)}, {"line_edge_pixels", #line_edge}, {"hough_max_votes", maximum_votes},
        {"hough_peaks", #line_peaks}, {"lines", #lines}, {"segments", #segments}, {"claimed_pixels", set_count(used)},
        {"junctions", junction_count}, {"polygons", #polygons}}
    for _, value in ipairs(values) do
        result[#result + 1] = value[1] .. " " .. value[2]
    end
    for _, kind in ipairs(polygon_kinds) do
        result[#result + 1] = kind .. " " .. (kind_counts[kind] or 0)
    end
    for _, value in ipairs({{"corner_candidates", #corner_candidates}, {"corners", #corners}, {"corners_on_vertices", match_counts.vertex},
        {"corners_on_segments", match_counts.segment}, {"corners_unmatched", match_counts.none}, {"vertices_with_corner", vertices_with_corner}}) do
        result[#result + 1] = value[1] .. " " .. value[2]
    end
    return result
end
pgm_io.write_pgm("edges.pgm", edge_image)
pgm_io.write_pgm("hough.pgm", vote_image)
pgm_io.write_pgm("overlay.pgm", overlay)
pgm_io.write_lines("lines.txt", lines_listing())
pgm_io.write_lines("circles.txt", circles_listing())
pgm_io.write_lines("polygons.txt", polygons_listing())
pgm_io.write_lines("corners.txt", corners_listing())
pgm_io.write_lines("components.txt", components_listing())
pgm_io.write_lines("report.txt", report_lines())
