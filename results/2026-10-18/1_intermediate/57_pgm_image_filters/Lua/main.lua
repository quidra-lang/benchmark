local patterns = {
    NEW = "iiii", OUTPUT = "", INVERT = "", BRIGHTNESS = "i",
    CONTRAST = "ii", THRESHOLD = "i", LEVELS = "ii", POSTERIZE = "i",
    MAXVAL = "i", FLIPH = "", FLIPV = "", ROTATE = "i",
    CROP = "iiii", PAD = "ii", SCALE = "ii", SHIFT = "iii",
    TILE = "ii", BLUR = "", GAUSS = "", SHARPEN = "",
    CONVOLVE = "iiiiiiiiii", SOBEL = "", MEDIAN = "",
    ERODE = "", DILATE = "", OPEN = "", CLOSE = "", GRADIENT = "",
    LINE = "iiiii", RECT = "iiiii", CIRCLE = "iiii", FLOOD = "iii",
    HISTOGRAM = "", EQUALIZE = "", LABEL = "i", DISTANCE = "i",
    STATS = "", REGION = "iiii", DITHER = "", ASCIIART = "",
    STORE = "n", RECALL = "n", DROP = "n", BLEND = "nii",
    DIFF = "n", PASTE = "nii", SLOTS = "", INFO = "", UNDO = "", REDO = ""
}

local imageless = {
    NEW = true, RECALL = true, DROP = true, SLOTS = true,
    INFO = true, UNDO = true, REDO = true
}

local slot_commands = {
    RECALL = true, DROP = true, BLEND = true, DIFF = true, PASTE = true
}

local neighbors4 = {{0, -1}, {-1, 0}, {1, 0}, {0, 1}}
local neighbors8 = {
    {-1, -1}, {0, -1}, {1, -1}, {-1, 0},
    {1, 0}, {-1, 1}, {0, 1}, {1, 1}
}

local kernels = {
    BLUR = {{1, 1, 1, 1, 1, 1, 1, 1, 1}, 9},
    GAUSS = {{1, 2, 1, 2, 4, 2, 1, 2, 1}, 16},
    SHARPEN = {{0, -1, 0, -1, 5, -1, 0, -1, 0}, 1}
}

local shades = "@#*+=~-:,."

local function fail(reason)
    error({reason = reason}, 0)
end

local function check(condition, reason)
    if not condition then fail(reason or "bad value") end
end

local function clamp(value, low, high)
    return math.min(math.max(value, low), high)
end

local function within_limit(...)
    for i = 1, select("#", ...) do
        local value = select(i, ...)
        if value < -1000 or value > 1000 then return false end
    end
    return true
end

local function split(line)
    local words = {}
    for word in line:gmatch("%S+") do words[#words + 1] = word end
    return words
end

local function integer_word(text)
    if text == "0" then return true end
    if not text:match("^%-?[1-9]%d*$") then return false end
    return #text <= (text:sub(1, 1) == "-" and 8 or 7)
end

local function name_word(text)
    return #text >= 1 and #text <= 8 and text:match("^[a-z]+$") ~= nil
end

local function digits(text)
    return text ~= nil and text:match("^%d+$") ~= nil
end

local function sum(values, first, last)
    local total = 0
    for i = first or 1, last or #values do total = total + values[i] end
    return total
end

local function copy(values)
    local result = {}
    for i, value in ipairs(values) do result[i] = value end
    return result
end

local Image = {}
Image.__index = Image

function Image.new(width, height, maxval, pixels)
    return setmetatable({
        width = width, height = height, maxval = maxval, pixels = pixels
    }, Image)
end

function Image:get(x, y)
    return self.pixels[y * self.width + x + 1]
end

function Image:row(y)
    local result = {}
    for x = 0, self.width - 1 do result[#result + 1] = self:get(x, y) end
    return result
end

function Image:contains(x, y)
    return x >= 0 and y >= 0 and x < self.width and y < self.height
end

function Image:clamp(value)
    return clamp(value, 0, self.maxval)
end

function Image:with_pixels(pixels)
    return Image.new(self.width, self.height, self.maxval, pixels)
end

function Image:neighborhood(x, y)
    local values = {}
    for dy = -1, 1 do
        for dx = -1, 1 do
            local nx = clamp(x + dx, 0, self.width - 1)
            local ny = clamp(y + dy, 0, self.height - 1)
            values[#values + 1] = self:get(nx, ny)
        end
    end
    return values
end

function Image:summary()
    local checksum = 0
    for i, pixel in ipairs(self.pixels) do checksum = checksum + i * pixel end
    return string.format("%dx%d maxval %d checksum %d",
                         self.width, self.height, self.maxval, checksum)
end

local function read_pgm(lines)
    local words = {}
    for _, line in ipairs(lines) do
        local data = line:match("^[^#]*")
        for word in data:gmatch("%S+") do words[#words + 1] = word end
    end
    check(words[1] == "P2", "bad magic")
    local function header(position, limit, reason)
        check(words[position] ~= nil, "truncated header")
        check(digits(words[position]), "bad number")
        local value = tonumber(words[position])
        check(value >= 1 and value <= limit, reason)
        return value
    end
    local width = header(2, 64, "bad size")
    local height = header(3, 64, "bad size")
    local maxval = header(4, 255, "bad maxval")
    local count = #words - 4
    local needed = width * height
    local pixels = {}
    for index = 0, needed - 1 do
        local x, y = index % width, index // width
        local text = words[index + 5]
        check(text ~= nil, string.format("too few pixels (%d of %d)", count, needed))
        check(digits(text), string.format("bad pixel at %d,%d", x, y))
        local pixel = tonumber(text)
        check(pixel <= maxval, string.format("pixel out of range at %d,%d", x, y))
        pixels[#pixels + 1] = pixel
    end
    check(count <= needed, string.format("too many pixels (%d of %d)", count, needed))
    return Image.new(width, height, maxval, pixels)
end

local function transformed(image, width, height, pixel_at)
    local pixels = {}
    for y = 0, height - 1 do
        for x = 0, width - 1 do
            pixels[#pixels + 1] = pixel_at(x, y)
        end
    end
    return Image.new(width, height, image.maxval, pixels)
end

local function rotated(image, angle)
    local w, h = image.width, image.height
    if angle == 180 then
        return transformed(image, w, h, function(x, y)
            return image:get(w - 1 - x, h - 1 - y)
        end)
    elseif angle == 90 then
        return transformed(image, h, w, function(x, y)
            return image:get(y, h - 1 - x)
        end)
    end
    return transformed(image, h, w, function(x, y)
        return image:get(w - 1 - y, x)
    end)
end

local function cropped(image, left, top, width, height)
    return transformed(image, width, height, function(x, y)
        return image:get(left + x, top + y)
    end)
end

local function translated(image, width, height, dx, dy, fill)
    return transformed(image, width, height, function(x, y)
        if image:contains(x - dx, y - dy) then return image:get(x - dx, y - dy) end
        return fill
    end)
end

local function scaled(image, width, height, numerator, denominator)
    return transformed(image, width, height, function(x, y)
        local source_x = ((2 * x + 1) * denominator) // (2 * numerator)
        local source_y = ((2 * y + 1) * denominator) // (2 * numerator)
        return image:get(source_x, source_y)
    end)
end

local function convolution(image, kernel, divisor)
    return transformed(image, image.width, image.height, function(x, y)
        local neighborhood = image:neighborhood(x, y)
        local total = 0
        for i = 1, 9 do total = total + kernel[i] * neighborhood[i] end
        return image:clamp(total // divisor)
    end)
end

local function rank_filtered(image, rank)
    return transformed(image, image.width, image.height, function(x, y)
        local neighborhood = image:neighborhood(x, y)
        table.sort(neighborhood)
        return neighborhood[rank + 1]
    end)
end

local function sobel(image)
    return transformed(image, image.width, image.height, function(x, y)
        local q = image:neighborhood(x, y)
        local gx = q[3] + 2 * q[6] + q[9] - q[1] - 2 * q[4] - q[7]
        local gy = q[7] + 2 * q[8] + q[9] - q[1] - 2 * q[2] - q[3]
        return image:clamp(math.abs(gx) + math.abs(gy))
    end)
end

local function line_points(x0, y0, x1, y1)
    local dx, dy = math.abs(x1 - x0), -math.abs(y1 - y0)
    local sx, sy = x0 < x1 and 1 or -1, y0 < y1 and 1 or -1
    local err, x, y = dx + dy, x0, y0
    local points = {}
    while true do
        points[#points + 1] = {x, y}
        if x == x1 and y == y1 then return points end
        local twice = 2 * err
        if twice >= dy then err, x = err + dy, x + sx end
        if twice <= dx then err, y = err + dx, y + sy end
    end
end

local function rectangle_points(image, left, top, width, height, filled)
    local right, bottom = left + width - 1, top + height - 1
    local result = {}
    for y = math.max(0, top), math.min(bottom, image.height - 1) do
        for x = math.max(0, left), math.min(right, image.width - 1) do
            if filled or x == left or x == right or y == top or y == bottom then
                result[#result + 1] = {x, y}
            end
        end
    end
    return result
end

local function circle_points(cx, cy, radius)
    local a, b, err = radius, 0, 1 - radius
    local points = {}
    while a >= b do
        local coords = {
            {cx + a, cy + b}, {cx + b, cy + a}, {cx - b, cy + a}, {cx - a, cy + b},
            {cx - a, cy - b}, {cx - b, cy - a}, {cx + b, cy - a}, {cx + a, cy - b}
        }
        for _, point in ipairs(coords) do points[#points + 1] = point end
        b = b + 1
        if err < 0 then
            err = err + 2 * b + 1
        else
            a = a - 1
            err = err + 2 * (b - a) + 1
        end
    end
    return points
end

local function disc_points(image, outline)
    local rows = {}
    for _, point in ipairs(outline) do
        local x, y = point[1], point[2]
        local row = rows[y]
        if row then
            row[1], row[2] = math.min(row[1], x), math.max(row[2], x)
        else
            rows[y] = {x, x}
        end
    end
    local result = {}
    for y, span in pairs(rows) do
        if y >= 0 and y < image.height then
            for x = math.max(0, span[1]), math.min(image.width - 1, span[2]) do
                result[#result + 1] = {x, y}
            end
        end
    end
    return result
end

local function flood_points(image, x, y)
    local target = image:get(x, y)
    local stack, visited, points = {{x, y}}, {[y * image.width + x] = true}, {}
    while #stack > 0 do
        local point = table.remove(stack)
        local cx, cy = point[1], point[2]
        points[#points + 1] = point
        for _, direction in ipairs(neighbors4) do
            local nx, ny = cx + direction[1], cy + direction[2]
            if image:contains(nx, ny) and image:get(nx, ny) == target then
                local index = ny * image.width + nx
                if not visited[index] then
                    visited[index] = true
                    stack[#stack + 1] = {nx, ny}
                end
            end
        end
    end
    return points
end

local function equalized(image)
    local counts, cdf = {}, {}
    for v = 0, image.maxval do counts[v] = 0 end
    local minimum = image.maxval
    for _, pixel in ipairs(image.pixels) do
        counts[pixel] = counts[pixel] + 1
        minimum = math.min(minimum, pixel)
    end
    local accumulated = 0
    for v = 0, image.maxval do
        accumulated = accumulated + counts[v]
        cdf[v] = accumulated
    end
    local n, cmin = #image.pixels, cdf[minimum]
    if n == cmin then return image:with_pixels(copy(image.pixels)) end
    local span, pixels = n - cmin, {}
    for _, pixel in ipairs(image.pixels) do
        pixels[#pixels + 1] = (2 * (cdf[pixel] - cmin) * image.maxval + span) // (2 * span)
    end
    return image:with_pixels(pixels)
end

local function components(image, threshold)
    local visited, groups = {}, {}
    for start = 1, #image.pixels do
        if image.pixels[start] >= threshold and not visited[start] then
            visited[start] = true
            local stack = {{(start - 1) % image.width, (start - 1) // image.width}}
            local members = {}
            while #stack > 0 do
                local point = table.remove(stack)
                local x, y = point[1], point[2]
                members[#members + 1] = point
                for _, direction in ipairs(neighbors8) do
                    local nx, ny = x + direction[1], y + direction[2]
                    if image:contains(nx, ny) then
                        local index = ny * image.width + nx + 1
                        if image.pixels[index] >= threshold and not visited[index] then
                            visited[index] = true
                            stack[#stack + 1] = {nx, ny}
                        end
                    end
                end
            end
            groups[#groups + 1] = members
        end
    end
    return groups
end

local function component_text(image, threshold, members)
    local min_x, min_y = math.huge, math.huge
    local max_x, max_y = -math.huge, -math.huge
    local sum_x, sum_y, perimeter = 0, 0, 0
    for _, point in ipairs(members) do
        local x, y = point[1], point[2]
        min_x, min_y = math.min(min_x, x), math.min(min_y, y)
        max_x, max_y = math.max(max_x, x), math.max(max_y, y)
        sum_x, sum_y = sum_x + x, sum_y + y
        for _, direction in ipairs(neighbors4) do
            local nx, ny = x + direction[1], y + direction[2]
            if not image:contains(nx, ny) or image:get(nx, ny) < threshold then
                perimeter = perimeter + 1
                break
            end
        end
    end
    local area = #members
    return string.format("area %d perimeter %d box %d %d %d %d center %d %d",
                         area, perimeter, min_x, min_y, max_x, max_y,
                         sum_x // area, sum_y // area)
end

local function distance_map(image, threshold)
    local w, h = image.width, image.height
    local far, distances = w + h, {}
    for i, pixel in ipairs(image.pixels) do
        distances[i] = pixel < threshold and 0 or far
    end
    for y = 0, h - 1 do
        for x = 0, w - 1 do
            local index = y * w + x + 1
            if x > 0 then distances[index] = math.min(distances[index], distances[index - 1] + 1) end
            if y > 0 then distances[index] = math.min(distances[index], distances[index - w] + 1) end
        end
    end
    for y = h - 1, 0, -1 do
        for x = w - 1, 0, -1 do
            local index = y * w + x + 1
            if x < w - 1 then distances[index] = math.min(distances[index], distances[index + 1] + 1) end
            if y < h - 1 then distances[index] = math.min(distances[index], distances[index + w] + 1) end
        end
    end
    for i, distance in ipairs(distances) do distances[i] = math.min(distance, image.maxval) end
    return image:with_pixels(distances)
end

local function statistics(values, maxval)
    local ordered = copy(values)
    table.sort(ordered)
    local counts = {}
    for v = 0, maxval do counts[v] = 0 end
    for _, pixel in ipairs(values) do counts[pixel] = counts[pixel] + 1 end
    local mode = 0
    for v = 1, maxval do
        if counts[v] > counts[mode] then mode = v end
    end
    return string.format("min %d max %d mean %d median %d mode %d",
                         ordered[1], ordered[#ordered], sum(values) // #values,
                         ordered[(#ordered + 1) // 2], mode)
end

local function dithered(image)
    local errors, pixels = copy(image.pixels), {}
    local diffusion = {{1, 0, 7}, {-1, 1, 3}, {0, 1, 5}, {1, 1, 1}}
    for y = 0, image.height - 1 do
        for x = 0, image.width - 1 do
            local index = y * image.width + x + 1
            local old = errors[index]
            local new = 2 * old >= image.maxval and image.maxval or 0
            pixels[index] = new
            local err = old - new
            for _, entry in ipairs(diffusion) do
                local nx, ny = x + entry[1], y + entry[2]
                if image:contains(nx, ny) then
                    local destination = ny * image.width + nx + 1
                    errors[destination] = errors[destination] + err * entry[3] // 16
                end
            end
        end
    end
    return image:with_pixels(pixels)
end

local Editor = {}
Editor.__index = Editor

function Editor.new()
    return setmetatable({
        current = nil, undo_history = {}, redo_history = {},
        slots = {}, output = {}
    }, Editor)
end

function Editor:emit(line)
    self.output[#self.output + 1] = line
end

function Editor:parse(words)
    local name = words[1]
    local pattern = patterns[name]
    check(pattern ~= nil, "unknown command " .. name)
    local fill = (name == "RECT" or name == "CIRCLE") and
                 #words == #pattern + 2 and words[#words] == "FILL"
    local argc = #words - 1 - (fill and 1 or 0)
    check(argc == #pattern, "bad arguments")
    local numbers, slot = {}, nil
    for i = 1, argc do
        local word = words[i + 1]
        if pattern:sub(i, i) == "i" then
            check(integer_word(word), "bad arguments")
            numbers[#numbers + 1] = tonumber(word)
        else
            check(name_word(word), "bad arguments")
            slot = word
        end
    end
    return {name = name, numbers = numbers, slot = slot, fill = fill}
end

function Editor:execute(words)
    local ok, problem = pcall(function()
        local command = self:parse(words)
        if not imageless[command.name] then check(self.current ~= nil, "no image") end
        if slot_commands[command.name] then
            check(self.slots[command.slot] ~= nil, "no slot " .. command.slot)
        end
        self:run(command)
    end)
    if not ok then
        if type(problem) ~= "table" or not problem.reason then error(problem) end
        self:emit("error: " .. problem.reason)
    end
end

function Editor:load(lines)
    local ok, image = pcall(read_pgm, lines)
    if ok then
        self:replace(image, "loaded")
    else
        if type(image) ~= "table" or not image.reason then error(image) end
        self:emit("error: load: " .. image.reason)
    end
end

function Editor:replace(image, label)
    self.current, self.undo_history, self.redo_history = image, {}, {}
    self:emit(label .. " " .. image:summary())
end

function Editor:commit(image, painted)
    self.undo_history[#self.undo_history + 1] = self.current
    self.redo_history = {}
    self.current = image
    self:emit("ok " .. image:summary() .. (painted and " painted " .. painted or ""))
end

function Editor:paint(points, value)
    local image, marked = self.current, {}
    local count = 0
    for _, point in ipairs(points) do
        local x, y = point[1], point[2]
        if image:contains(x, y) then
            local index = y * image.width + x + 1
            if not marked[index] then
                marked[index] = true
                count = count + 1
            end
        end
    end
    local pixels = {}
    for i, pixel in ipairs(image.pixels) do
        pixels[i] = marked[i] and value or pixel
    end
    self:commit(image:with_pixels(pixels), count)
end

function Editor:crop_area(a)
    local x, y, w, h = table.unpack(a)
    local image = self.current
    check(x >= 0 and y >= 0 and w >= 1 and h >= 1)
    check(x + w <= image.width and y + h <= image.height)
    return x, y, w, h
end

function Editor:matching_slot(name)
    local other, image = self.slots[name], self.current
    check(other.width == image.width and other.height == image.height, "size mismatch")
    check(other.maxval == image.maxval, "maxval mismatch")
    return other
end

function Editor:run(command)
    local name, a, slot, fill = command.name, command.numbers, command.slot, command.fill
    local image = self.current
    local m = image and image.maxval or nil
    if name == "NEW" then
        local w, h, maxval, value = table.unpack(a)
        check(w >= 1 and w <= 64 and h >= 1 and h <= 64)
        check(maxval >= 1 and maxval <= 255 and value >= 0 and value <= maxval)
        local pixels = {}
        for i = 1, w * h do pixels[i] = value end
        self:replace(Image.new(w, h, maxval, pixels), "created")
    elseif name == "OUTPUT" then
        self:emit("P2")
        self:emit(image.width .. " " .. image.height)
        self:emit(tostring(m))
        for y = 0, image.height - 1 do
            self:emit(table.concat(image:row(y), " "))
        end
    elseif name == "INVERT" then
        local pixels = {}
        for i, p in ipairs(image.pixels) do pixels[i] = m - p end
        self:commit(image:with_pixels(pixels))
    elseif name == "BRIGHTNESS" then
        check(a[1] >= -255 and a[1] <= 255)
        local pixels = {}
        for i, p in ipairs(image.pixels) do pixels[i] = image:clamp(p + a[1]) end
        self:commit(image:with_pixels(pixels))
    elseif name == "CONTRAST" then
        check(a[1] >= 0 and a[1] <= 100 and a[2] >= 1 and a[2] <= 100)
        local center = (m + 1) // 2
        local pixels = {}
        for i, p in ipairs(image.pixels) do
            pixels[i] = image:clamp(center + ((p - center) * a[1]) // a[2])
        end
        self:commit(image:with_pixels(pixels))
    elseif name == "THRESHOLD" then
        check(a[1] >= 0 and a[1] <= m)
        local pixels = {}
        for i, p in ipairs(image.pixels) do pixels[i] = p >= a[1] and m or 0 end
        self:commit(image:with_pixels(pixels))
    elseif name == "LEVELS" then
        check(a[1] >= 0 and a[1] < a[2] and a[2] <= m)
        local pixels = {}
        for i, p in ipairs(image.pixels) do
            pixels[i] = image:clamp(((p - a[1]) * m) // (a[2] - a[1]))
        end
        self:commit(image:with_pixels(pixels))
    elseif name == "POSTERIZE" then
        check(a[1] >= 2 and a[1] <= m + 1)
        local pixels = {}
        for i, p in ipairs(image.pixels) do
            local group = (p * a[1]) // (m + 1)
            pixels[i] = (group * m) // (a[1] - 1)
        end
        self:commit(image:with_pixels(pixels))
    elseif name == "MAXVAL" then
        check(a[1] >= 1 and a[1] <= 255)
        local pixels = {}
        for i, p in ipairs(image.pixels) do pixels[i] = (2 * p * a[1] + m) // (2 * m) end
        self:commit(Image.new(image.width, image.height, a[1], pixels))
    elseif name == "FLIPH" or name == "FLIPV" then
        self:commit(transformed(image, image.width, image.height, function(x, y)
            if name == "FLIPH" then return image:get(image.width - 1 - x, y) end
            return image:get(x, image.height - 1 - y)
        end))
    elseif name == "ROTATE" then
        check(a[1] == 90 or a[1] == 180 or a[1] == 270)
        self:commit(rotated(image, a[1]))
    elseif name == "CROP" then
        self:commit(cropped(image, self:crop_area(a)))
    elseif name == "PAD" then
        check(a[1] >= 1 and a[2] >= 0 and a[2] <= m)
        local width, height = image.width + 2 * a[1], image.height + 2 * a[1]
        check(width <= 64 and height <= 64, "too large")
        self:commit(translated(image, width, height, a[1], a[1], a[2]))
    elseif name == "SCALE" then
        check(a[1] >= 1 and a[1] <= 16 and a[2] >= 1 and a[2] <= 16)
        local width = image.width * a[1] // a[2]
        local height = image.height * a[1] // a[2]
        check(width > 0 and height > 0, "too small")
        check(width <= 64 and height <= 64, "too large")
        self:commit(scaled(image, width, height, a[1], a[2]))
    elseif name == "SHIFT" then
        check(within_limit(a[1], a[2]) and a[3] >= 0 and a[3] <= m)
        self:commit(translated(image, image.width, image.height, a[1], a[2], a[3]))
    elseif name == "TILE" then
        check(a[1] >= 1 and a[2] >= 1)
        local width, height = image.width * a[1], image.height * a[2]
        check(width <= 64 and height <= 64, "too large")
        self:commit(transformed(image, width, height, function(x, y)
            return image:get(x % image.width, y % image.height)
        end))
    elseif kernels[name] then
        self:commit(convolution(image, kernels[name][1], kernels[name][2]))
    elseif name == "CONVOLVE" then
        local kernel = {}
        for i = 1, 9 do
            check(a[i] >= -16 and a[i] <= 16)
            kernel[i] = a[i]
        end
        check(a[10] >= 1 and a[10] <= 256)
        self:commit(convolution(image, kernel, a[10]))
    elseif name == "SOBEL" then
        self:commit(sobel(image))
    elseif name == "MEDIAN" or name == "ERODE" or name == "DILATE" then
        local rank = name == "MEDIAN" and 4 or name == "ERODE" and 0 or 8
        self:commit(rank_filtered(image, rank))
    elseif name == "OPEN" then
        self:commit(rank_filtered(rank_filtered(image, 0), 8))
    elseif name == "CLOSE" then
        self:commit(rank_filtered(rank_filtered(image, 8), 0))
    elseif name == "GRADIENT" then
        local high = rank_filtered(image, 8).pixels
        local low = rank_filtered(image, 0).pixels
        local pixels = {}
        for i = 1, #high do pixels[i] = high[i] - low[i] end
        self:commit(image:with_pixels(pixels))
    elseif name == "LINE" then
        check(within_limit(a[1], a[2], a[3], a[4]) and a[5] >= 0 and a[5] <= m)
        self:paint(line_points(a[1], a[2], a[3], a[4]), a[5])
    elseif name == "RECT" then
        check(within_limit(a[1], a[2]) and a[3] >= 1 and a[3] <= 1000 and
              a[4] >= 1 and a[4] <= 1000 and a[5] >= 0 and a[5] <= m)
        self:paint(rectangle_points(image, a[1], a[2], a[3], a[4], fill), a[5])
    elseif name == "CIRCLE" then
        check(within_limit(a[1], a[2]) and a[3] >= 0 and a[3] <= 1000 and
              a[4] >= 0 and a[4] <= m)
        local outline = circle_points(a[1], a[2], a[3])
        self:paint(fill and disc_points(image, outline) or outline, a[4])
    elseif name == "FLOOD" then
        check(image:contains(a[1], a[2]) and a[3] >= 0 and a[3] <= m)
        self:paint(flood_points(image, a[1], a[2]), a[3])
    elseif name == "HISTOGRAM" then
        local lows, highs, counts = {}, {}, {}
        for i = 0, 15 do counts[i] = 0 end
        for value = 0, m do
            local bin = value * 16 // (m + 1)
            if lows[bin] == nil then lows[bin] = value end
            highs[bin] = value
        end
        for _, pixel in ipairs(image.pixels) do
            local bin = pixel * 16 // (m + 1)
            counts[bin] = counts[bin] + 1
        end
        local top = 0
        for i = 0, 15 do top = math.max(top, counts[i]) end
        for i = 0, 15 do
            if lows[i] ~= nil then
                self:emit(string.format("%3d-%3d %4d |%s", lows[i], highs[i], counts[i],
                                        string.rep("#", counts[i] * 32 // top)))
            end
        end
    elseif name == "EQUALIZE" then
        self:commit(equalized(image))
    elseif name == "LABEL" then
        check(a[1] >= 0 and a[1] <= m)
        local groups = components(image, a[1])
        self:emit("labels " .. #groups)
        for i, group in ipairs(groups) do
            self:emit("label " .. i .. " " .. component_text(image, a[1], group))
        end
    elseif name == "DISTANCE" then
        check(a[1] >= 0 and a[1] <= m)
        self:commit(distance_map(image, a[1]))
    elseif name == "STATS" then
        self:emit(statistics(image.pixels, m))
    elseif name == "REGION" then
        local part = cropped(image, self:crop_area(a))
        self:emit(statistics(part.pixels, part.maxval))
    elseif name == "DITHER" then
        self:commit(dithered(image))
    elseif name == "ASCIIART" then
        for y = 0, image.height - 1 do
            local chars = {}
            for _, pixel in ipairs(image:row(y)) do
                local index = pixel * #shades // (m + 1) + 1
                chars[#chars + 1] = shades:sub(index, index)
            end
            self:emit(table.concat(chars))
        end
    elseif name == "STORE" then
        self.slots[slot] = image
        self:emit("stored " .. slot .. " " .. image:summary())
    elseif name == "RECALL" then
        self:replace(self.slots[slot], "recalled " .. slot)
    elseif name == "DROP" then
        self.slots[slot] = nil
        self:emit("dropped " .. slot)
    elseif name == "BLEND" then
        check(a[1] >= 0 and a[1] <= a[2] and a[2] >= 1 and a[2] <= 100)
        local other = self:matching_slot(slot)
        local pixels = {}
        for i, p in ipairs(image.pixels) do
            pixels[i] = (p * (a[2] - a[1]) + other.pixels[i] * a[1]) // a[2]
        end
        self:commit(image:with_pixels(pixels))
    elseif name == "DIFF" then
        local other = self:matching_slot(slot)
        local pixels = {}
        for i, p in ipairs(image.pixels) do pixels[i] = math.abs(p - other.pixels[i]) end
        self:commit(image:with_pixels(pixels))
    elseif name == "PASTE" then
        check(within_limit(a[1], a[2]))
        local other = self.slots[slot]
        check(other.maxval == m, "maxval mismatch")
        local pixels, count = copy(image.pixels), 0
        for y = 0, other.height - 1 do
            for x = 0, other.width - 1 do
                local nx, ny = a[1] + x, a[2] + y
                if image:contains(nx, ny) then
                    pixels[ny * image.width + nx + 1] = other:get(x, y)
                    count = count + 1
                end
            end
        end
        self:commit(image:with_pixels(pixels), count)
    elseif name == "SLOTS" then
        local names = {}
        for entry in pairs(self.slots) do names[#names + 1] = entry end
        table.sort(names)
        if #names == 0 then self:emit("no slots") end
        for _, entry in ipairs(names) do
            self:emit(entry .. " " .. self.slots[entry]:summary())
        end
    elseif name == "INFO" then
        self:emit("image " .. (image and image:summary() or "none") ..
                  " undo " .. #self.undo_history .. " redo " .. #self.redo_history ..
                  " slots " .. (function()
                      local n = 0
                      for _ in pairs(self.slots) do n = n + 1 end
                      return n
                  end)())
    elseif name == "UNDO" then
        check(#self.undo_history > 0, "nothing to undo")
        self.redo_history[#self.redo_history + 1] = image
        self.current = table.remove(self.undo_history)
        self:emit("undo " .. self.current:summary())
    elseif name == "REDO" then
        check(#self.redo_history > 0, "nothing to redo")
        self.undo_history[#self.undo_history + 1] = image
        self.current = table.remove(self.redo_history)
        self:emit("redo " .. self.current:summary())
    end
end

local count = tonumber(io.read("*l"))
local editor = Editor.new()
for _ = 1, count do
    local line = io.read("*l")
    local words = split(line)
    if words[1] == "LOAD" then
        local lines = {}
        for i = 1, tonumber(words[2]) do lines[i] = io.read("*l") or "" end
        editor:load(lines)
    else
        editor:execute(words)
    end
end
io.write(table.concat(editor.output, "\n"), "\n")
