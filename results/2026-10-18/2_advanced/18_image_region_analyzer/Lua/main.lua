local source_directory = (arg[0]:match("^(.*[/\\])") or "./")
package.path = source_directory .. "?.lua;" .. package.path
local labeling = require("labeling")
local morphology = require("morphology")
local threshold = require("threshold")
local pgm_reader = require("pgm_reader")
local report = require("report")

local symbols = "0123456789ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz"
local orientations = {"none", "horizontal", "vertical", "falling", "rising"}
local directions = {
    [4] = {{1, 0}, {0, -1}, {-1, 0}, {0, 1}},
    [8] = {{1, 0}, {1, -1}, {0, -1}, {-1, -1}, {-1, 0}, {-1, 1}, {0, 1}, {1, 1}}
}
local csv_header = "image,label,class,flags,area,x0,y0,x1,y1,cx,cy,mean,variance,min,max,contrast,border,perimeter,chain,straight,diagonal,turns,compactness,runs,holes,hole_area,euler,parent,depth,var_x,var_y,cov_xy,hu1,orientation,anisotropy,extent,mirror_lr,mirror_tb,hull_area,solidity,feret2,width2,elongation,bays,bay_area,skeleton,endpoints,branches,neighbor,distance2,codes"

local function words(text)
    local result = {}
    for word in text:gmatch("%S+") do result[#result + 1] = word end
    return result
end

local function line(...)
    local values = {...}
    for index, value in ipairs(values) do values[index] = tostring(value) end
    return table.concat(values, " ")
end

local function extend(target, values)
    for _, value in ipairs(values) do target[#target + 1] = value end
end

local function fraction(numerator, denominator)
    denominator = denominator or 1
    local a, b = math.abs(numerator), denominator
    while b ~= 0 do a, b = b, a % b end
    return {n = numerator // a, d = denominator // a}
end

local function parse_rational(text)
    local numerator, denominator = text:match("^(-?%d+)/(%d+)$")
    if numerator then return fraction(tonumber(numerator), tonumber(denominator)) end
    return fraction(tonumber(text))
end

local function decimal(value, digits) return report.decimal(value.n, value.d, digits) end
local function mean_text(total, count) return count > 0 and report.decimal(total, count, 2) or "-" end

local function compare_rational(a, b)
    local left, right = a.n * b.d, b.n * a.d
    return left == right and 0 or left < right and -1 or 1
end

local function condition(feature, comparison, text)
    return {feature = feature, comparison = comparison, text = text,
        value = feature == "orientation" and text or parse_rational(text)}
end

local function holds(item, features)
    local value, order = features[item.feature], nil
    if item.feature == "orientation" then
        order = value == item.value and 0 or value < item.value and -1 or 1
    else
        if type(value) == "number" then value = fraction(value) end
        order = compare_rational(value, item.value)
    end
    local operator = item.comparison
    if operator == "<" then return order < 0 end
    if operator == "<=" then return order <= 0 end
    if operator == ">" then return order > 0 end
    if operator == ">=" then return order >= 0 end
    if operator == "=" then return order == 0 end
    return order ~= 0
end

local function matches(rule, features)
    for _, item in ipairs(rule.conditions) do if not holds(item, features) then return false end end
    return true
end

local function read_parameters(path)
    local parameters = {elements = {}, settings = {}}
    for text in io.lines(path) do
        local row = words(text)
        if row[1] == "otsu_top" then parameters.otsu_top = tonumber(row[2])
        elseif row[1] == "sweep" then parameters.sweep_step = tonumber(row[2])
        elseif row[1] == "isotropy" then parameters.isotropy = parse_rational(row[2])
        elseif row[1] == "bay_min" then parameters.bay_min = tonumber(row[2])
        elseif row[1] == "element" then
            local offsets, ox, oy = {}, tonumber(row[5]), tonumber(row[6])
            for index = 7, #row do
                for x = 1, #row[index] do
                    if row[index]:sub(x, x) == "#" then offsets[#offsets + 1] = {x - 1 - ox, index - 7 - oy} end
                end
            end
            parameters.elements[row[2]] = offsets
        elseif row[1] == "image" then
            local operations = {}
            for index = 6, #row do operations[#operations + 1] = row[index] end
            parameters.settings[row[2]] = {name = row[2], connectivity = tonumber(row[3]),
                threshold = row[4], polarity = row[5], operations = operations}
        end
    end
    return parameters
end

local function read_rules(path)
    local rules = {filters = {}, classes = {}, flags = {}, class_names = {}}
    local seen = {}
    for text in io.lines(path) do
        local row = words(text)
        if row[1] == "filter" then
            rules.filters[#rules.filters + 1] = condition(row[2], row[3], row[4])
        elseif row[1] == "class" or row[1] == "flag" then
            local conditions = {}
            for index = 3, #row, 3 do conditions[#conditions + 1] = condition(row[index], row[index + 1], row[index + 2]) end
            local target = row[1] == "class" and rules.classes or rules.flags
            target[#target + 1] = {name = row[2], conditions = conditions}
            if row[1] == "class" and not seen[row[2]] then
                seen[row[2]] = true
                rules.class_names[#rules.class_names + 1] = row[2]
            end
        end
    end
    rules.class_names[#rules.class_names + 1] = "other"
    return rules
end

local function count_foreground(mask)
    local count = 0
    for _, row in ipairs(mask) do for _, flag in ipairs(row) do if flag then count = count + 1 end end end
    return count
end

local function group_pixels(labels, count)
    local groups = {}
    for number = 0, count do groups[number] = {} end
    for y, row in ipairs(labels) do
        for x, number in ipairs(row) do
            local group = groups[number]
            group[#group + 1] = {x - 1, y - 1}
        end
    end
    return groups
end

local function enclosed_components(mask, connectivity)
    local height, width, background = #mask, #mask[1], {}
    for y, row in ipairs(mask) do
        background[y] = {}
        for x, value in ipairs(row) do background[y][x] = not value end
    end
    local components = labeling.label_components(background, connectivity)
    local groups, enclosed = group_pixels(components.labels, components.count), {}
    for number = 1, components.count do
        local on_edge = false
        for _, point in ipairs(groups[number]) do
            local x, y = point[1], point[2]
            if x == 0 or y == 0 or x == width - 1 or y == height - 1 then on_edge = true break end
        end
        if not on_edge then enclosed[#enclosed + 1] = groups[number] end
    end
    return enclosed
end

local function fill_holes(mask, connectivity)
    local result = {}
    for y, row in ipairs(mask) do
        result[y] = {}
        for x, flag in ipairs(row) do result[y][x] = flag end
    end
    for _, pixels in ipairs(enclosed_components(mask, connectivity)) do
        for _, point in ipairs(pixels) do result[point[2] + 1][point[1] + 1] = true end
    end
    return result
end

local function cross(a, b, point)
    return (b[1] - a[1]) * (point[2] - a[2]) - (b[2] - a[2]) * (point[1] - a[1])
end

local function squared_distance(a, b)
    local dx, dy = a[1] - b[1], a[2] - b[2]
    return dx * dx + dy * dy
end

local function convex_hull(pixels)
    local unique = {}
    for _, point in ipairs(pixels) do
        for dy = 0, 1 do for dx = 0, 1 do
            local x, y = point[1] + dx, point[2] + dy
            unique[morphology.key(x, y)] = {x, y}
        end end
    end
    local ordered = {}
    for _, point in pairs(unique) do ordered[#ordered + 1] = point end
    table.sort(ordered, function(a, b) return a[1] < b[1] or a[1] == b[1] and a[2] < b[2] end)
    local function half(first, last, step)
        local chain = {}
        for index = first, last, step do
            local point = ordered[index]
            while #chain >= 2 and cross(chain[#chain - 1], chain[#chain], point) <= 0 do table.remove(chain) end
            chain[#chain + 1] = point
        end
        table.remove(chain)
        return chain
    end
    local hull = half(1, #ordered, 1)
    extend(hull, half(#ordered, 1, -1))
    return hull
end

local function contains_center(hull, x, y)
    local center = {2 * x + 1, 2 * y + 1}
    for index, a in ipairs(hull) do
        local b = hull[index % #hull + 1]
        if cross({2 * a[1], 2 * a[2]}, {2 * b[1], 2 * b[2]}, center) < 0 then return false end
    end
    return true
end

local function orientation_line(regions)
    local parts = {"orientations"}
    for _, name in ipairs(orientations) do
        local count = 0
        for _, region in ipairs(regions) do if region.features.orientation == name then count = count + 1 end end
        extend(parts, {name, tostring(count)})
    end
    return table.concat(parts, " ")
end

local Analysis = {}
Analysis.__index = Analysis

function Analysis.new(image, setting, parameters)
    local self = setmetatable({image = image, setting = setting, parameters = parameters,
        width = image.width, height = image.height, connectivity = setting.connectivity,
        complement = 12 - setting.connectivity, morph_counts = {}, sweep = {}, regions = {}, holes = {}}, Analysis)
    self.histogram = threshold.histogram(image)
    self.otsu = threshold.otsu(self.histogram)
    self.isodata_cutoff, self.isodata_iterations = threshold.isodata(self.histogram)
    if setting.threshold == "otsu" then self.cutoff, self.method = self.otsu.cutoff, "otsu"
    elseif setting.threshold == "isodata" then self.cutoff, self.method = self.isodata_cutoff, "isodata"
    else self.cutoff, self.method = tonumber(setting.threshold), "fixed" end
    self.initial = self:binarize(self.cutoff)
    self.final = self.initial
    for _, operation in ipairs(setting.operations) do
        if operation == "fill" then self.final = fill_holes(self.final, self.complement)
        else
            local kind, name = operation:match("^([^:]+):(.+)$")
            local apply = ({erode = morphology.erode, dilate = morphology.dilate,
                open = morphology.opening, close = morphology.closing})[kind]
            self.final = apply(self.final, parameters.elements[name])
        end
        self.morph_counts[#self.morph_counts + 1] = count_foreground(self.final)
    end
    for cutoff = parameters.sweep_step, image.maxval - 1, parameters.sweep_step do
        local mask = self:binarize(cutoff)
        self.sweep[#self.sweep + 1] = {cutoff, count_foreground(mask), labeling.label_components(mask, self.connectivity).count}
    end
    local components = labeling.label_components(self.final, self.connectivity)
    self.labels, self.provisional = components.labels, components.provisional
    local groups = group_pixels(self.labels, components.count)
    for number = 1, components.count do
        self.regions[number] = {number = number, pixels = groups[number], features = {}, codes = {},
            parent = 0, depth = 0, children = {}, kept = false, class_name = "other", flags = {}, distance = 0}
    end
    self.four_components = labeling.label_components(self.final, 4).count
    self.eight_components = labeling.label_components(self.final, 8).count
    self.bit_quad = labeling.bit_quad_euler(self.final, self.connectivity)
    self.hole_of = {}
    for y = 1, self.height do
        self.hole_of[y] = {}
        for x = 1, self.width do self.hole_of[y][x] = 0 end
    end
    for _, pixels in ipairs(enclosed_components(self.final, self.complement)) do
        local first, number = pixels[1], #self.holes + 1
        local hole = {number = number, pixels = pixels, owner = self.labels[first[2]][first[1] + 1]}
        for _, point in ipairs(pixels) do self.hole_of[point[2] + 1][point[1] + 1] = number end
        self.holes[number] = hole
    end
    for _, region in ipairs(self.regions) do
        local first = region.pixels[1]
        local hole = first[2] >= 1 and self.hole_of[first[2]][first[1] + 1] or 0
        if hole > 0 then
            region.parent = self.holes[hole].owner
            local parent = self.regions[region.parent]
            region.depth = parent.depth + 1
            parent.children[#parent.children + 1] = region
        end
    end
    for _, region in ipairs(self.regions) do self:measure(region) end
    return self
end

function Analysis:binarize(cutoff)
    local mask = {}
    for y, row in ipairs(self.image.pixels) do
        mask[y] = {}
        for x, value in ipairs(row) do
            mask[y][x] = self.setting.polarity == "bright" and value > cutoff or self.setting.polarity == "dark" and value <= cutoff
        end
    end
    return mask
end

function Analysis:label_at(x, y)
    if x >= 0 and x < self.width and y >= 0 and y < self.height then return self.labels[y + 1][x + 1] end
    return -1
end

function Analysis:chain_code(region)
    local moves, visited, codes = directions[self.connectivity], {region.pixels[1]}, {}
    local heading = #moves - 1
    while true do
        local current, start = visited[#visited], nil
        if self.connectivity == 4 then start = (heading + 3) % 4
        else start = (heading + (heading % 2 == 0 and 7 or 6)) % 8 end
        local found
        for offset = 0, #moves - 1 do
            local direction = (start + offset) % #moves
            local move = moves[direction + 1]
            if self:label_at(current[1] + move[1], current[2] + move[2]) == region.number then found = direction break end
        end
        if found == nil then return {} end
        local move = moves[found + 1]
        visited[#visited + 1] = {current[1] + move[1], current[2] + move[2]}
        codes[#codes + 1], heading = found, found
        local count = #codes
        if count >= 2 and squared_distance(visited[count + 1], visited[2]) == 0 and squared_distance(visited[count], visited[1]) == 0 then
            table.remove(codes)
            return codes
        end
    end
end

function Analysis:measure(region)
    local f, area = region.features, #region.pixels
    local sx, sy, sxx, syy, sxy, intensity, squares = 0, 0, 0, 0, 0, 0, 0
    local x0, y0, x1, y1, minimum, maximum = self.width, self.height, -1, -1, self.image.maxval, 0
    local surrounding, perimeter, runs = {}, 0, 0
    for _, point in ipairs(region.pixels) do
        local x, y = point[1], point[2]
        local value = self.image.pixels[y + 1][x + 1]
        sx, sy, sxx, syy, sxy = sx + x, sy + y, sxx + x * x, syy + y * y, sxy + x * y
        intensity, squares = intensity + value, squares + value * value
        x0, y0, x1, y1 = math.min(x0, x), math.min(y0, y), math.max(x1, x), math.max(y1, y)
        minimum, maximum = math.min(minimum, value), math.max(maximum, value)
        for _, move in ipairs(directions[8]) do
            local nx, ny = x + move[1], y + move[2]
            if self:label_at(nx, ny) == 0 then surrounding[morphology.key(nx, ny)] = self.image.pixels[ny + 1][nx + 1] end
        end
        for _, move in ipairs(directions[self.complement]) do
            if self:label_at(x + move[1], y + move[2]) ~= region.number then perimeter = perimeter + 1 break end
        end
        if self:label_at(x - 1, y) ~= region.number then runs = runs + 1 end
    end
    f.area, f.x0, f.y0, f.x1, f.y1 = area, x0, y0, x1, y1
    f.width, f.height = x1 - x0 + 1, y1 - y0 + 1
    f.border = (x0 == 0 or y0 == 0 or x1 == self.width - 1 or y1 == self.height - 1) and 1 or 0
    f.mean, f.variance, f.min, f.max = fraction(intensity, area), fraction(area * squares - intensity * intensity, area * area), minimum, maximum
    local surrounding_count, surrounding_sum = 0, 0
    for _, value in pairs(surrounding) do surrounding_count, surrounding_sum = surrounding_count + 1, surrounding_sum + value end
    f.contrast = surrounding_count > 0 and fraction(intensity * surrounding_count - surrounding_sum * area, area * surrounding_count) or fraction(0)
    region.codes = self:chain_code(region)
    local straight, diagonal, turns = 0, 0, 0
    for index, code in ipairs(region.codes) do
        if self.connectivity == 4 or code % 2 == 0 then straight = straight + 1 else diagonal = diagonal + 1 end
        if code ~= region.codes[(index - 2) % #region.codes + 1] then turns = turns + 1 end
    end
    f.perimeter, f.runs, f.chain, f.straight, f.diagonal, f.turns = perimeter, runs, #region.codes, straight, diagonal, turns
    local contour = 5 * straight + 7 * diagonal
    f.compactness = fraction(contour * contour, 25 * area)
    f.holes, f.hole_area = 0, 0
    for _, hole in ipairs(self.holes) do
        if hole.owner == region.number then f.holes, f.hole_area = f.holes + 1, f.hole_area + #hole.pixels end
    end
    f.euler, f.depth = 1 - f.holes, region.depth
    local m20, m02, m11 = area * sxx - sx * sx, area * syy - sy * sy, area * sxy - sx * sy
    f.cx, f.cy = fraction(sx, area), fraction(sy, area)
    f.var_x, f.var_y, f.cov_xy = fraction(m20, area * area), fraction(m02, area * area), fraction(m11, area * area)
    f.hu1 = fraction(m20 + m02, area * area * area)
    f.anisotropy = m20 + m02 > 0 and fraction(math.abs(m20 - m02) + 2 * math.abs(m11), m20 + m02) or fraction(0)
    f.orientation = "none"
    if compare_rational(f.anisotropy, self.parameters.isotropy) > 0 then
        local u, v = m20 - m02, 2 * m11
        if math.abs(v) >= math.abs(u) then f.orientation = v > 0 and "falling" or "rising"
        else f.orientation = u > 0 and "horizontal" or "vertical" end
    end
    local mirror_lr, mirror_tb = 0, 0
    for _, point in ipairs(region.pixels) do
        if self:label_at(x0 + x1 - point[1], point[2]) == region.number then mirror_lr = mirror_lr + 1 end
        if self:label_at(point[1], y0 + y1 - point[2]) == region.number then mirror_tb = mirror_tb + 1 end
    end
    f.extent, f.mirror_lr, f.mirror_tb = fraction(area, f.width * f.height), fraction(mirror_lr, area), fraction(mirror_tb, area)
    local hull, doubled, feret2, width2 = convex_hull(region.pixels), 0, 0, nil
    for index, a in ipairs(hull) do
        local b, reach = hull[index % #hull + 1], 0
        doubled = doubled + a[1] * b[2] - b[1] * a[2]
        for _, point in ipairs(hull) do
            feret2 = math.max(feret2, squared_distance(a, point))
            reach = math.max(reach, math.abs(cross(a, b, point)))
        end
        local candidate = fraction(reach * reach, squared_distance(a, b))
        if width2 == nil or compare_rational(candidate, width2) < 0 then width2 = candidate end
    end
    region.hull_doubled = math.abs(doubled)
    f.solidity, f.feret2, f.width2, f.elongation = fraction(2 * area, region.hull_doubled), feret2, width2, fraction(feret2 * width2.d, width2.n)
    local bay_mask = {}
    for y = y0, y1 do
        local row = {}
        for x = x0, x1 do
            row[#row + 1] = self.labels[y + 1][x + 1] == 0 and self.hole_of[y + 1][x + 1] == 0 and contains_center(hull, x, y)
        end
        bay_mask[#bay_mask + 1] = row
    end
    local bays = labeling.label_components(bay_mask, self.complement)
    local bay_groups = group_pixels(bays.labels, bays.count)
    f.bays, f.bay_area = 0, 0
    for number = 1, bays.count do
        local size = #bay_groups[number]
        f.bay_area = f.bay_area + size
        if size >= self.parameters.bay_min then f.bays = f.bays + 1 end
    end
    region.skeleton = morphology.thin(region.pixels)
    f.skeleton, f.endpoints, f.branches = 0, 0, 0
    for _, point in pairs(region.skeleton) do
        local crossing = morphology.crossing_number(region.skeleton, point[1], point[2])
        f.skeleton = f.skeleton + 1
        if crossing == 1 then f.endpoints = f.endpoints + 1 end
        if crossing >= 3 then f.branches = f.branches + 1 end
    end
end

function Analysis:apply_rules(rules)
    for _, region in ipairs(self.regions) do
        for index, item in ipairs(rules.filters) do
            if not holds(item, region.features) then region.dropped_by = index break end
        end
        if region.dropped_by == nil then
            region.kept = true
            for _, rule in ipairs(rules.classes) do
                if matches(rule, region.features) then region.class_name = rule.name break end
            end
            for _, rule in ipairs(rules.flags) do
                if matches(rule, region.features) then region.flags[#region.flags + 1] = rule.name end
            end
        end
    end
end

function Analysis:kept_regions()
    local kept = {}
    for _, region in ipairs(self.regions) do if region.kept then kept[#kept + 1] = region end end
    return kept
end

function Analysis:find_neighbors()
    local kept = self:kept_regions()
    for _, region in ipairs(kept) do
        for _, other in ipairs(kept) do
            if other ~= region then
                local a, b = region.features, other.features
                local dx, dy = a.x0 + a.x1 - b.x0 - b.x1, a.y0 + a.y1 - b.y0 - b.y1
                local distance = dx * dx + dy * dy
                if region.neighbor == nil or distance < region.distance then region.distance, region.neighbor = distance, other.number end
            end
        end
    end
end

function Analysis:tree_text(region)
    if #region.children == 0 then return tostring(region.number) end
    local inner = {}
    for _, child in ipairs(region.children) do inner[#inner + 1] = self:tree_text(child) end
    return region.number .. "(" .. table.concat(inner, " ") .. ")"
end

function Analysis:threshold_lines()
    local image, histogram = self.image, self.histogram
    local bins = {tostring(histogram.bin_width)}
    for _, value in ipairs(histogram.bins) do bins[#bins + 1] = tostring(value) end
    local lines = {
        line("image", image.name, "size", self.width, self.height, "maxval", image.maxval),
        line("histogram pixels", histogram.pixels, "min", histogram.minimum, "max", histogram.maximum,
            "mean", mean_text(histogram.total, histogram.pixels), "median", histogram.median, "mode", histogram.mode, "levels", histogram.levels),
        "bins " .. table.concat(bins, " "),
        line("otsu threshold", self.otsu.cutoff, "upper", self.otsu.upper, "candidates", #self.otsu.candidates)
    }
    for rank = 1, math.min(self.parameters.otsu_top, #self.otsu.candidates) do
        local candidate = self.otsu.candidates[rank]
        local gap = fraction(candidate.sum_above * candidate.below - candidate.sum_below * candidate.above, candidate.below * candidate.above)
        lines[#lines + 1] = line("rank", rank, "t", candidate.cutoff, "below", candidate.below, "above", candidate.above,
            "mean_below", mean_text(candidate.sum_below, candidate.below), "mean_above", mean_text(candidate.sum_above, candidate.above), "gap", decimal(gap, 2))
    end
    lines[#lines + 1] = line("isodata threshold", self.isodata_cutoff, "iterations", self.isodata_iterations)
    lines[#lines + 1] = line("threshold", self.cutoff, self.method, self.setting.polarity, "foreground", count_foreground(self.initial))
    for index, operation in ipairs(self.setting.operations) do lines[#lines + 1] = line("morph", operation, "foreground", self.morph_counts[index]) end
    for _, sweep in ipairs(self.sweep) do lines[#lines + 1] = line("sweep", sweep[1], "foreground", sweep[2], "regions", sweep[3]) end
    return lines
end

function Analysis:region_symbol(x, y, skeleton_only)
    local number = self.labels[y + 1][x + 1]
    if number == 0 then return self.hole_of[y + 1][x + 1] > 0 and ":" or "." end
    local region = self.regions[number]
    if skeleton_only and region.skeleton[morphology.key(x, y)] == nil then return "+" end
    return region.kept and symbols:sub(number % #symbols + 1, number % #symbols + 1) or "#"
end

function Analysis:map_lines()
    local size = line(self.image.name, self.width, self.height)
    local lines = {"morphology " .. size}
    for y = 1, self.height do
        local row = {}
        for x = 1, self.width do
            local before, after = self.initial[y][x], self.final[y][x]
            row[x] = after and (before and "#" or "+") or (before and "-" or ".")
        end
        lines[#lines + 1] = table.concat(row)
    end
    for _, heading in ipairs({"labels", "skeleton"}) do
        lines[#lines + 1] = heading .. " " .. size
        for y = 0, self.height - 1 do
            local row = {}
            for x = 0, self.width - 1 do row[x + 1] = self:region_symbol(x, y, heading == "skeleton") end
            lines[#lines + 1] = table.concat(row)
        end
    end
    return lines
end

function Analysis:csv_rows()
    local rows = {}
    for _, region in ipairs(self:kept_regions()) do
        local f = region.features
        local codes = {}
        for _, code in ipairs(region.codes) do codes[#codes + 1] = tostring(code) end
        local columns = {self.image.name, region.number, region.class_name, #region.flags > 0 and table.concat(region.flags, "+") or "-",
            f.area, f.x0, f.y0, f.x1, f.y1, decimal(f.cx, 3), decimal(f.cy, 3), decimal(f.mean, 2), decimal(f.variance, 2),
            f.min, f.max, decimal(f.contrast, 2), f.border, f.perimeter, f.chain, f.straight, f.diagonal, f.turns,
            decimal(f.compactness, 3), f.runs, f.holes, f.hole_area, f.euler, region.parent > 0 and region.parent or "-", f.depth,
            decimal(f.var_x, 3), decimal(f.var_y, 3), decimal(f.cov_xy, 3), decimal(f.hu1, 4), f.orientation,
            decimal(f.anisotropy, 3), decimal(f.extent, 3), decimal(f.mirror_lr, 3), decimal(f.mirror_tb, 3),
            report.hull_area_text(region.hull_doubled), decimal(f.solidity, 3), f.feret2, decimal(f.width2, 3), decimal(f.elongation, 3),
            f.bays, f.bay_area, f.skeleton, f.endpoints, f.branches, region.neighbor or "-",
            region.neighbor and report.decimal(region.distance, 4, 2) or "-", #codes > 0 and table.concat(codes) or "-"}
        for index, value in ipairs(columns) do columns[index] = tostring(value) end
        rows[#rows + 1] = table.concat(columns, ",")
    end
    return rows
end

function Analysis:intensity_text(foreground)
    local total, count = 0, 0
    for y, row in ipairs(self.image.pixels) do
        for x, value in ipairs(row) do
            if self.final[y][x] == foreground then total, count = total + value, count + 1 end
        end
    end
    return mean_text(total, count)
end

function Analysis:summary_lines(rules)
    local kept, hole_pixels, depth_max, roots = self:kept_regions(), 0, 0, {"tree"}
    for _, hole in ipairs(self.holes) do hole_pixels = hole_pixels + #hole.pixels end
    for _, region in ipairs(self.regions) do
        depth_max = math.max(depth_max, region.depth)
        if region.parent == 0 then roots[#roots + 1] = self:tree_text(region) end
    end
    local lines = {line("image", self.image.name), line("threshold", self.cutoff, self.method, self.setting.polarity, "conn", self.connectivity),
        line("foreground", count_foreground(self.initial), count_foreground(self.final)),
        line("regions", #self.regions, "provisional", self.provisional, "kept", #kept, "dropped", #self.regions - #kept),
        line("connectivity four", self.four_components, "eight", self.eight_components),
        line("holes", #self.holes, "hole_pixels", hole_pixels, "euler", #self.regions - #self.holes, "bitquad", self.bit_quad)}
    for _, hole in ipairs(self.holes) do
        local x0, y0, x1, y1 = self.width, self.height, -1, -1
        for _, point in ipairs(hole.pixels) do x0, y0, x1, y1 = math.min(x0, point[1]), math.min(y0, point[2]), math.max(x1, point[1]), math.max(y1, point[2]) end
        lines[#lines + 1] = line("hole", hole.number, "owner", hole.owner, "area", #hole.pixels, "box", x0, y0, x1, y1)
    end
    extend(lines, {line("depth_max", depth_max), table.concat(roots, " "), line("intensity foreground", self:intensity_text(true), "background", self:intensity_text(false))})
    local area_line = "area total 0 mean - largest - smallest -"
    if #kept > 0 then
        local total, largest, smallest = 0, kept[1], kept[1]
        for _, region in ipairs(kept) do
            total = total + region.features.area
            if region.features.area > largest.features.area then largest = region end
            if region.features.area < smallest.features.area then smallest = region end
        end
        area_line = line("area total", total, "mean", mean_text(total, #kept), "largest", largest.number, largest.features.area, "smallest", smallest.number, smallest.features.area)
    end
    lines[#lines + 1] = area_line
    local classes, flags = {"classes"}, {"flags"}
    for _, name in ipairs(rules.class_names) do
        local count = 0
        for _, region in ipairs(kept) do if region.class_name == name then count = count + 1 end end
        extend(classes, {name, tostring(count)})
    end
    for _, rule in ipairs(rules.flags) do
        local count = 0
        for _, region in ipairs(kept) do
            for _, name in ipairs(region.flags) do if name == rule.name then count = count + 1 break end end
        end
        extend(flags, {rule.name, tostring(count)})
    end
    extend(lines, {table.concat(classes, " "), orientation_line(kept), table.concat(flags, " ")})
    return lines
end

local function overall_lines(analyses, rules)
    local regions, kept, hole_count, largest, largest_image = {}, {}, 0, nil, nil
    for _, analysis in ipairs(analyses) do
        extend(regions, analysis.regions)
        extend(kept, analysis:kept_regions())
        hole_count = hole_count + #analysis.holes
        for _, region in ipairs(analysis:kept_regions()) do
            if largest == nil or region.features.area > largest.features.area then largest, largest_image = region, analysis.image.name end
        end
    end
    local lines = {"overall", line("images", #analyses), line("regions", #regions, "kept", #kept, "dropped", #regions - #kept), line("holes", hole_count, "euler", #regions - hole_count)}
    for index, item in ipairs(rules.filters) do
        local dropped = 0
        for _, region in ipairs(regions) do if region.dropped_by == index then dropped = dropped + 1 end end
        lines[#lines + 1] = line("filter", index, item.feature, item.comparison, item.text, "dropped", dropped)
    end
    for _, name in ipairs(rules.class_names) do
        local count, area = 0, 0
        for _, region in ipairs(kept) do if region.class_name == name then count, area = count + 1, area + region.features.area end end
        lines[#lines + 1] = line("class", name, "count", count, "area", area, "mean", mean_text(area, count))
    end
    for _, rule in ipairs(rules.flags) do
        local count = 0
        for _, region in ipairs(kept) do for _, name in ipairs(region.flags) do if name == rule.name then count = count + 1 break end end end
        lines[#lines + 1] = line("flag", rule.name, "count", count)
    end
    lines[#lines + 1] = orientation_line(kept)
    lines[#lines + 1] = largest and line("largest", largest_image, largest.number, largest.features.area) or "largest -"
    return lines
end

local function main()
    local parameters, rules = read_parameters("input/params.txt"), read_rules("input/rules.txt")
    local analyses = {}
    for _, image in ipairs(pgm_reader.read_images("input/images.txt")) do
        local analysis = Analysis.new(image, parameters.settings[image.name], parameters)
        analysis:apply_rules(rules)
        analysis:find_neighbors()
        analyses[#analyses + 1] = analysis
    end
    local thresholds, maps, rows, summary = {}, {}, {csv_header}, {}
    for _, analysis in ipairs(analyses) do
        extend(thresholds, analysis:threshold_lines())
        extend(maps, analysis:map_lines())
        extend(rows, analysis:csv_rows())
        extend(summary, analysis:summary_lines(rules))
    end
    extend(summary, overall_lines(analyses, rules))
    report.write_files("output", {{"thresholds.txt", thresholds}, {"labels.txt", maps}, {"regions.csv", rows}, {"summary.txt", summary}})
end

main()
