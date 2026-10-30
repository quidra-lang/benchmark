local fixed = require("fixed_point")
local vector = require("vector3")
local scene_io = require("scene")
local intersect = require("intersect")
local shading = require("shading")
local kinds = {"primary", "reflection", "refraction", "shadow"}
local black = {0, 0, 0}
local function words(values)
    local result = {}
    for i, value in ipairs(values) do result[i] = tostring(value) end
    return table.concat(result, " ")
end
local function read_lines(path)
    local input = assert(io.open(path, "r"))
    local result = {}
    for line in input:lines() do result[#result + 1] = line end
    input:close()
    return result
end
local function write_lines(name, lines)
    local output = assert(io.open("output/" .. name, "w"))
    if #lines > 0 then output:write(table.concat(lines, "\n"), "\n") end
    output:close()
end
local function read_settings()
    local result = {}
    for _, line in ipairs(read_lines("input/render.txt")) do
        local key, rest = line:match("(%S+) (.+)")
        local values = {}
        for token in rest:gmatch("%S+") do values[#values + 1] = tonumber(token) end
        result[key] = values
    end
    return result
end
local function union_box(objects)
    local low, high = {table.unpack(objects[1].bounds[1])}, {table.unpack(objects[1].bounds[2])}
    for _, object in ipairs(objects) do
        for axis = 1, 3 do low[axis], high[axis] = math.min(low[axis], object.bounds[1][axis]), math.max(high[axis], object.bounds[2][axis]) end
    end
    return {low, high}
end
local function surface_cost(objects)
    local bounds = union_box(objects)
    local dx, dy, dz = table.unpack(vector.sub(bounds[2], bounds[1]))
    return (dx * dy + dy * dz + dz * dx) * #objects
end
local Renderer = {}
Renderer.__index = Renderer
function Renderer.new(scene, settings)
    local self = setmetatable({scene = scene, objects = scene.objects, lights = scene.lights,
        width = settings.size[1], height = settings.size[2], contrast = settings.contrast[1],
        max_depth = settings.depth[1], far = settings.far[1], epsilon = settings.epsilon[1],
        planes = {}, nodes = {}, rays = {0, 0, 0, 0}, misses = {0, 0, 0}, depths = {},
        tests = {{0, 0}, {0, 0}, {0, 0}, {0, 0}}, object_counts = {}, light_counts = {},
        total_internal = 0, clamped = 0, supersampled = 0, pixels = {}}, Renderer)
    local bounded = {}
    for _, object in ipairs(self.objects) do
        object.bounds = intersect.bounds(object, settings.pad[1])
        if object.bounds then bounded[#bounded + 1] = object else self.planes[#self.planes + 1] = object end
        self.object_counts[object.number] = {0, 0, 0}
    end
    for i = 1, #self.lights do self.light_counts[i] = {0, 0, 0, 0, 0, 0} end
    for depth = 0, self.max_depth do self.depths[depth + 1] = 0 end
    if #bounded > 0 then self.root = self:build(bounded, 0) end
    return self
end
function Renderer:build(objects, depth)
    local node = {bounds = union_box(objects), depth = depth, visits = 0}
    self.nodes[#self.nodes + 1] = node
    if #objects <= 2 then
        node.objects = {table.unpack(objects)}
        table.sort(node.objects, function(a, b) return a.number < b.number end)
        for _, object in ipairs(objects) do object.leaf_depth = depth end
        return node
    end
    local best_cost, best_left, best_right
    for axis = 1, 3 do
        local ordered = {table.unpack(objects)}
        table.sort(ordered, function(a, b)
            local first, second = (a.bounds[1][axis] + a.bounds[2][axis]) // 2, (b.bounds[1][axis] + b.bounds[2][axis]) // 2
            return first < second or first == second and a.number < b.number
        end)
        for split = 1, #ordered - 1 do
            local left, right = {}, {}
            for i, object in ipairs(ordered) do
                local target = i <= split and left or right
                target[#target + 1] = object
            end
            local cost = surface_cost(left) + surface_cost(right)
            if not best_cost or cost < best_cost then best_cost, best_left, best_right = cost, left, right end
        end
    end
    node.left = self:build(best_left, depth + 1)
    node.right = self:build(best_right, depth + 1)
    return node
end
function Renderer:test_node(node, origin, direction, kind, counted)
    if counted then self.tests[kind][1], node.visits = self.tests[kind][1] + 1, node.visits + 1 end
    local interval = intersect.slab(node.bounds[1], node.bounds[2], origin, direction)
    if interval and interval[3] > self.epsilon then return interval[1] end
end
function Renderer:test_object(object, origin, direction, kind, counted)
    if counted then self.tests[kind][2] = self.tests[kind][2] + 1 end
    return intersect.candidate(object, origin, direction, self.epsilon)
end
function Renderer:nearest(origin, direction, kind, counted)
    kind = kind or 1
    local best_object, best_hit
    local function consider(object)
        local hit = self:test_object(object, origin, direction, kind, counted)
        if hit and hit[1] <= self.far and (not best_hit or hit[1] < best_hit[1]
            or hit[1] == best_hit[1] and object.number < best_object.number) then best_object, best_hit = object, hit end
    end
    for _, object in ipairs(self.planes) do consider(object) end
    local pending = {}
    if self.root then pending[1] = self.root end
    while #pending > 0 do
        local node = table.remove(pending)
        local entry = self:test_node(node, origin, direction, kind, counted)
        if entry and entry <= self.far and (not best_hit or entry <= best_hit[1]) then
            if node.objects then for _, object in ipairs(node.objects) do consider(object) end
            else pending[#pending + 1], pending[#pending + 2] = node.right, node.left end
        end
    end
    return best_object, best_hit
end
function Renderer:occluders(origin, direction, distance, counted)
    local result = {}
    local function consider(object)
        local hit = self:test_object(object, origin, direction, 4, counted)
        if hit and hit[1] < distance then
            result[#result + 1] = object
            if counted then self.object_counts[object.number][3] = self.object_counts[object.number][3] + 1 end
        end
    end
    for _, object in ipairs(self.planes) do consider(object) end
    local pending = {}
    if self.root then pending[1] = self.root end
    while #pending > 0 do
        local node = table.remove(pending)
        local entry = self:test_node(node, origin, direction, 4, counted)
        if entry and entry < distance then
            if node.objects then for _, object in ipairs(node.objects) do consider(object) end
            else pending[#pending + 1], pending[#pending + 2] = node.right, node.left end
        end
    end
    table.sort(result, function(a, b) return a.number < b.number end)
    return result
end
function Renderer:camera(qx, qy)
    local u = ((qx - 2 * self.width) * self.scene.view[1]) // (2 * self.width)
    local v = ((2 * self.height - qy) * self.scene.view[2]) // (2 * self.height)
    local direction = vector.add(vector.add(self.scene.forward, vector.scale(self.scene.right, u)), vector.scale(self.scene.up, v))
    return self.scene.eye, vector.norm(direction)
end
function Renderer:samples(light, point)
    if light.kind == "sun" then return {{light.direction, self.far, light.intensity}} end
    local positions = {}
    if light.kind == "area" then
        local k = light.divisions
        for j = 0, k - 1 do
            for i = 0, k - 1 do
                local position = {}
                for axis = 1, 3 do position[axis] = light.position[axis] + ((2 * i + 1) * light.u[axis]) // (2 * k) + ((2 * j + 1) * light.v[axis]) // (2 * k) end
                positions[#positions + 1] = position
            end
        end
    else positions[1] = light.position end
    local result = {}
    for _, position in ipairs(positions) do
        local relative = vector.sub(position, point)
        result[#result + 1] = {vector.norm(relative), vector.length(relative), light.intensity // light.samples}
    end
    return result
end
function Renderer:cone(light, direction)
    if light.kind ~= "spot" then return 4096 end
    local cosine = -vector.dot(direction, light.direction)
    if cosine <= light.outer then return 0 end
    if cosine >= light.inner then return 4096 end
    return ((cosine - light.outer) * 4096) // (light.inner - light.outer)
end
function Renderer:local_color(info, direction, pixel)
    local diffuse_sum, specular_sum = 0, 0
    info.lighting, info.illumination = {}, 0
    for j, light in ipairs(self.lights) do
        local lit, diffuse, specular = 0, 0, 0
        local counters = self.light_counts[j]
        for _, sample in ipairs(self:samples(light, info.point)) do
            local toward, distance, intensity = table.unpack(sample)
            local ndl = vector.dot(info.normal, toward)
            if ndl <= 0 then
                if pixel then counters[5] = counters[5] + 1 end
            else
                local factor = self:cone(light, toward)
                if factor == 0 then
                    if pixel then counters[6] = counters[6] + 1 end
                else
                    if pixel then self.rays[4], pixel.rays, counters[2] = self.rays[4] + 1, pixel.rays + 1, counters[2] + 1 end
                    local occluders = self:occluders(info.point, toward, distance, pixel ~= nil)
                    for _, object in ipairs(occluders) do factor = fixed.mul(factor, object.material.kt) end
                    if factor == 0 then
                        if pixel then counters[3] = counters[3] + 1 end
                    else
                        if pixel and #occluders > 0 then counters[4] = counters[4] + 1 end
                        local dif, spe = shading.phong(info.object.material, info.normal, toward, vector.neg(direction), ndl, intensity, factor)
                        lit, diffuse, specular = lit + 1, diffuse + dif, specular + spe
                    end
                end
            end
        end
        info.lighting[j] = {lit, diffuse, specular}
        if lit > 0 then info.illumination = info.illumination + 1 end
        diffuse_sum, specular_sum = diffuse_sum + diffuse, specular_sum + specular
    end
    local color = {}
    for axis = 1, 3 do
        local raw = (info.base[axis] * (self.scene.ambient + diffuse_sum)) // 4096 + (255 * specular_sum) // 4096
        if pixel and raw > 255 then self.clamped = self.clamped + 1 end
        color[axis] = math.min(raw, 255)
    end
    return color
end
function Renderer:trace(origin, direction, kind, depth, pixel, record)
    kind, depth = kind or 1, depth or 0
    if pixel then
        self.rays[kind], self.depths[depth + 1], pixel.rays = self.rays[kind] + 1, self.depths[depth + 1] + 1, pixel.rays + 1
        pixel.depth = math.max(pixel.depth, depth)
    end
    if record then record[#record + 1] = "ray " .. kinds[kind] .. " " .. depth .. " origin " .. words(origin) .. " direction " .. words(direction) end
    local object, hit = self:nearest(origin, direction, kind, pixel ~= nil)
    if not object then
        if pixel then self.misses[kind] = self.misses[kind] + 1 end
        if record then record[#record + 1], record[#record + 2] = "miss", "color " .. words(self.scene.background) end
        return self.scene.background, nil
    end
    local point = vector.add(origin, vector.scale(direction, hit[1]))
    local outward = intersect.outward(object, point, direction, hit)
    local front = vector.dot(outward, direction) <= 0
    local normal = front and outward or vector.neg(outward)
    local info = {object = object, distance = hit[1], point = point, normal = normal, front = front, base = shading.base_color(object.material, point)}
    if pixel then
        local category = kind == 1 and 1 or 2
        self.object_counts[object.number][category] = self.object_counts[object.number][category] + 1
    end
    local local_color = self:local_color(info, direction, pixel)
    if record then
        record[#record + 1] = "hit " .. object.label .. " t " .. hit[1] .. " point " .. words(point) .. " normal " .. words(normal) .. " base " .. words(info.base)
        for j, lighting in ipairs(info.lighting) do
            record[#record + 1] = "light " .. j .. " lit " .. lighting[1] .. " of " .. self.lights[j].samples .. " diffuse " .. lighting[2] .. " specular " .. lighting[3]
        end
        record[#record + 1] = "local " .. words(local_color)
    end
    local material, color = object.material, local_color
    if depth < self.max_depth and (material.kr > 0 or material.kt > 0) then
        local wr, wt, transmitted, internal = shading.refraction(material, direction, normal, front)
        if internal then
            if pixel then self.total_internal = self.total_internal + 1 end
            if record then record[#record + 1] = "total_internal_reflection" end
        end
        local local_weight = 4096 - material.kr - material.kt
        if record then record[#record + 1] = "weights " .. local_weight .. " " .. wr .. " " .. wt end
        local reflected_color, refracted_color = black, black
        if wr > 0 then reflected_color = self:trace(point, shading.reflected(direction, normal), 2, depth + 1, pixel, record) end
        if wt > 0 then refracted_color = self:trace(point, transmitted, 3, depth + 1, pixel, record) end
        color = shading.mix({local_color, reflected_color, refracted_color}, {local_weight, wr, wt})
    end
    if self.scene.fog then
        local fog = self.scene.fog
        local factor = 0
        if hit[1] >= fog[5] then factor = 4096
        elseif hit[1] > fog[4] then factor = ((hit[1] - fog[4]) * 4096) // (fog[5] - fog[4]) end
        color = shading.mix({color, {fog[1], fog[2], fog[3]}}, {4096 - factor, factor})
    end
    if record then record[#record + 1] = "color " .. words(color) end
    return color, info
end
function Renderer:render()
    for y = 0, self.height - 1 do
        for x = 0, self.width - 1 do
            local pixel = {x = x, y = y, rays = 0, depth = 0, samples = 1, label = "."}
            local origin, direction = self:camera(4 * x + 2, 4 * y + 2)
            local color, info = self:trace(origin, direction, 1, 0, pixel)
            pixel.center, pixel.color, pixel.hit = color, color, info
            if info then
                pixel.label = info.object.label
                for j, lighting in ipairs(info.lighting) do if lighting[1] > 0 then self.light_counts[j][1] = self.light_counts[j][1] + 1 end end
            end
            self.pixels[#self.pixels + 1] = pixel
        end
    end
    for _, pixel in ipairs(self.pixels) do
        local boundary = false
        for _, offset in ipairs({{0, -1}, {0, 1}, {-1, 0}, {1, 0}}) do
            local x, y = pixel.x + offset[1], pixel.y + offset[2]
            if x >= 0 and x < self.width and y >= 0 and y < self.height then
                local other = self.pixels[y * self.width + x + 1]
                local difference = 0
                for axis = 1, 3 do difference = math.max(difference, math.abs(pixel.center[axis] - other.center[axis])) end
                if pixel.label ~= other.label or difference > self.contrast then boundary = true end
            end
        end
        if boundary then
            self.supersampled, pixel.samples = self.supersampled + 1, 4
            local total = {0, 0, 0}
            for _, offset in ipairs({{1, 1}, {3, 1}, {1, 3}, {3, 3}}) do
                local origin, direction = self:camera(4 * pixel.x + offset[1], 4 * pixel.y + offset[2])
                local color = self:trace(origin, direction, 1, 0, pixel)
                for axis = 1, 3 do total[axis] = total[axis] + color[axis] end
            end
            pixel.color = {total[1] // 4, total[2] // 4, total[3] // 4}
        end
    end
end
function Renderer:distance_range()
    local low, high
    for _, pixel in ipairs(self.pixels) do
        if pixel.hit then
            local distance = pixel.hit.distance
            low, high = low and math.min(low, distance) or distance, high and math.max(high, distance) or distance
        end
    end
    return low, high
end
function Renderer:mean_color(pixels)
    local total = {0, 0, 0}
    for _, pixel in ipairs(pixels) do for axis = 1, 3 do total[axis] = total[axis] + pixel.color[axis] end end
    return {total[1] // #pixels, total[2] // #pixels, total[3] // #pixels}
end
function Renderer:write_netpbm(name, magic, values)
    local lines = {magic, self.width .. " " .. self.height, "255"}
    for y = 0, self.height - 1 do
        local row = {}
        for x = 0, self.width - 1 do
            local value = values[y * self.width + x + 1]
            row[#row + 1] = magic == "P3" and words(value) or tostring(value)
        end
        lines[#lines + 1] = table.concat(row, " ")
    end
    write_lines(name, lines)
end
function Renderer:write_map(name, values)
    local lines = {}
    for y = 0, self.height - 1 do
        local row = {}
        for x = 0, self.width - 1 do row[#row + 1] = values[y * self.width + x + 1] end
        lines[#lines + 1] = table.concat(row)
    end
    write_lines(name, lines)
end
function Renderer:write_images()
    local low, high = self:distance_range()
    local max_cost = 0
    for _, pixel in ipairs(self.pixels) do max_cost = math.max(max_cost, pixel.rays) end
    local colors, depths, normals, albedos, costs, labels, lights, ray_depths = {}, {}, {}, {}, {}, {}, {}, {}
    for i, pixel in ipairs(self.pixels) do
        colors[i], costs[i], labels[i], ray_depths[i] = pixel.color, (255 * pixel.rays) // max_cost, pixel.label, tostring(pixel.depth)
        if not pixel.hit then depths[i], normals[i], albedos[i], lights[i] = 0, black, black, "."
        else
            local hit, normal = pixel.hit, {}
            depths[i] = low == high and 255 or 255 - (235 * (hit.distance - low)) // (high - low)
            for axis = 1, 3 do normal[axis] = math.max(0, math.min(255, ((hit.normal[axis] + 4096) * 255) // (2 * 4096))) end
            normals[i], albedos[i], lights[i] = normal, hit.base, tostring(hit.illumination)
        end
    end
    self:write_netpbm("image.ppm", "P3", colors)
    self:write_netpbm("depth.pgm", "P2", depths)
    self:write_netpbm("normal.ppm", "P3", normals)
    self:write_netpbm("albedo.ppm", "P3", albedos)
    self:write_netpbm("cost.pgm", "P2", costs)
    self:write_map("object_map.txt", labels)
    self:write_map("light_map.txt", lights)
    self:write_map("ray_depth.txt", ray_depths)
end
function Renderer:statistics()
    local lines = {"image " .. self.width .. " " .. self.height, "supersampled " .. self.supersampled}
    local ray_line, miss_line, total = "rays", "misses", 0
    for kind, name in ipairs(kinds) do
        ray_line, total = ray_line .. " " .. name .. " " .. self.rays[kind], total + self.rays[kind]
        if kind < 4 then miss_line = miss_line .. " " .. name .. " " .. self.misses[kind] end
    end
    lines[#lines + 1], lines[#lines + 2], lines[#lines + 3] = ray_line .. " total " .. total, miss_line, "depth " .. words(self.depths)
    for kind, name in ipairs(kinds) do lines[#lines + 1] = "tests " .. name .. " nodes " .. self.tests[kind][1] .. " objects " .. self.tests[kind][2] end
    lines[#lines + 1] = "total_internal_reflection " .. self.total_internal
    lines[#lines + 1] = "clamped " .. self.clamped
    local low, high = self:distance_range()
    lines[#lines + 1] = "distance " .. (low and low .. " " .. high or "none")
    local max_cost, histogram = 0, {0, 0, 0, 0, 0, 0, 0, 0}
    for _, pixel in ipairs(self.pixels) do
        max_cost = math.max(max_cost, pixel.rays)
        local r, g, b = table.unpack(pixel.color)
        local brightness = (299 * r + 587 * g + 114 * b) // 1000
        local bucket = brightness // 32 + 1
        histogram[bucket] = histogram[bucket] + 1
    end
    lines[#lines + 1], lines[#lines + 2], lines[#lines + 3] = "max_pixel_rays " .. max_cost, "mean " .. words(self:mean_color(self.pixels)), "histogram " .. words(histogram)
    for _, node in ipairs(self.nodes) do
        local role = "inner"
        if node.objects then
            local labels = {}
            for i, object in ipairs(node.objects) do labels[i] = object.label end
            role = "leaf " .. table.concat(labels)
        end
        lines[#lines + 1] = "node " .. node.depth .. " " .. role .. " box " .. words(node.bounds[1]) .. " " .. words(node.bounds[2]) .. " visits " .. node.visits
    end
    for i, object in ipairs(self.objects) do
        local pixels, xmin, ymin, xmax, ymax = {}, nil, nil, nil, nil
        for _, pixel in ipairs(self.pixels) do
            if pixel.label == object.label then
                pixels[#pixels + 1] = pixel
                xmin, ymin = xmin and math.min(xmin, pixel.x) or pixel.x, ymin and math.min(ymin, pixel.y) or pixel.y
                xmax, ymax = xmax and math.max(xmax, pixel.x) or pixel.x, ymax and math.max(ymax, pixel.y) or pixel.y
            end
        end
        local box, color = "none", "none"
        if #pixels > 0 then box, color = words({xmin, ymin, xmax, ymax}), words(self:mean_color(pixels)) end
        local counts = self.object_counts[i]
        lines[#lines + 1] = "object " .. object.label .. " " .. object.kind .. " primary " .. counts[1] .. " secondary " .. counts[2]
            .. " shadow " .. counts[3] .. " pixels " .. #pixels .. " box " .. box .. " color " .. color
    end
    for i, light in ipairs(self.lights) do
        local counts = self.light_counts[i]
        lines[#lines + 1] = "light " .. i .. " " .. light.kind .. " samples " .. light.samples .. " pixels " .. counts[1]
            .. " shadow_rays " .. counts[2] .. " blocked " .. counts[3] .. " attenuated " .. counts[4] .. " backfacing " .. counts[5] .. " outside " .. counts[6]
    end
    return lines
end
function Renderer:queries()
    local lines = {}
    for number, line in ipairs(read_lines("input/queries.txt")) do
        lines[#lines + 1] = "query " .. number .. " " .. line
        local fields = {}
        for token in line:gmatch("%S+") do fields[#fields + 1] = token end
        local kind, values = fields[1], {}
        if kind ~= "object" then for i = 2, #fields do values[#values + 1] = tonumber(fields[i]) end end
        if kind == "pixel" then
            local pixel = self.pixels[values[2] * self.width + values[1] + 1]
            local distance = pixel.hit and tostring(pixel.hit.distance) or "none"
            lines[#lines + 1] = "label " .. pixel.label .. " distance " .. distance .. " color " .. words(pixel.color) .. " samples " .. pixel.samples .. " rays " .. pixel.rays
        elseif kind == "trace" then
            local origin, direction = self:camera(4 * values[1] + 2, 4 * values[2] + 2)
            self:trace(origin, direction, 1, 0, nil, lines)
        elseif kind == "ray" then
            self:trace({values[1], values[2], values[3]}, vector.norm({values[4], values[5], values[6]}), 1, 0, nil, lines)
        elseif kind == "object" then
            for _, object in ipairs(self.objects) do
                if object.label == fields[2] then
                    local result = object.kind .. " material " .. object.material.name
                    if object.bounds then result = result .. " bounds " .. words(object.bounds[1]) .. " " .. words(object.bounds[2]) .. " leaf " .. object.leaf_depth
                    else result = result .. " bounds none leaf none" end
                    lines[#lines + 1] = result
                    break
                end
            end
        elseif kind == "visible" then
            local relative = vector.sub(values, self.scene.eye)
            local direction = vector.norm(relative)
            local occluders = self:occluders(self.scene.eye, direction, vector.length(relative) - self.epsilon, false)
            local visibility = #occluders == 0 and "yes" or "no"
            local object, hit = self:nearest(self.scene.eye, direction, 1, false)
            lines[#lines + 1] = visibility .. " first " .. (object and object.label .. " t " .. hit[1] or "none")
        elseif kind == "shadow" then
            for i, light in ipairs(self.lights) do
                local factor_sum, found = 0, {}
                for _, sample in ipairs(self:samples(light, values)) do
                    local direction, distance = sample[1], sample[2]
                    local factor = self:cone(light, direction)
                    for _, object in ipairs(self:occluders(values, direction, distance, false)) do
                        found[object.number], factor = true, fixed.mul(factor, object.material.kt)
                    end
                    factor_sum = factor_sum + factor
                end
                local labels = {}
                for _, object in ipairs(self.objects) do if found[object.number] then labels[#labels + 1] = object.label end end
                lines[#lines + 1] = "light " .. i .. " factor " .. factor_sum .. " occluders " .. (#labels > 0 and table.concat(labels) or "none")
            end
        elseif kind == "region" then
            local pixels, counts = {}, {}
            for y = values[2], values[4] do
                for x = values[1], values[3] do
                    local pixel = self.pixels[y * self.width + x + 1]
                    pixels[#pixels + 1], counts[pixel.label] = pixel, (counts[pixel.label] or 0) + 1
                end
            end
            lines[#lines + 1] = "pixels " .. #pixels .. " mean " .. words(self:mean_color(pixels))
            for _, object in ipairs(self.objects) do
                if counts[object.label] then lines[#lines + 1] = "label " .. object.label .. " " .. counts[object.label] end
            end
            if counts["."] then lines[#lines + 1] = "label . " .. counts["."] end
        end
    end
    return lines
end
local renderer = Renderer.new(scene_io.read(), read_settings())
renderer:render()
renderer:write_images()
write_lines("stats.txt", renderer:statistics())
write_lines("queries.txt", renderer:queries())
