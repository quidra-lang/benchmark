local Canvas = {}
Canvas.__index = Canvas

function Canvas.new(direction, main_length, secondary_length)
    local vertical = direction == "TB" or direction == "BT"
    return setmetatable({direction = direction, main_length = main_length, vertical = vertical,
        rows = vertical and main_length or secondary_length, columns = vertical and secondary_length or main_length,
        line_bits = {}, arrows = {}, boxes = {}, highlighted = {}, main_character = vertical and "|" or "-",
        secondary_character = vertical and "-" or "|"}, Canvas)
end

function Canvas:key(row, column)
    return row * self.columns + column + 1
end

function Canvas:cell(main, secondary)
    if self.direction == "BT" or self.direction == "RL" then main = self.main_length - 1 - main end
    return self.vertical and {main, secondary} or {secondary, main}
end

function Canvas:add_line(main, secondary, character)
    local cell = self:cell(main, secondary)
    local key = self:key(cell[1], cell[2])
    self.line_bits[key] = (self.line_bits[key] or 0) | ({["|"] = 1, ["-"] = 2, ["+"] = 4})[character]
end

function Canvas:main_line(start, finish, secondary)
    for main = start, finish do self:add_line(main, secondary, self.main_character) end
end

function Canvas:segment(start, gap, first, second, offset)
    if first == second then self:main_line(start, start + gap - 1, first); return end
    self:main_line(start, start + offset - 1, first)
    self:add_line(start + offset, first, "+")
    self:add_line(start + offset, second, "+")
    for secondary = math.min(first, second) + 1, math.max(first, second) - 1 do self:add_line(start + offset, secondary, self.secondary_character) end
    self:main_line(start + offset + 1, start + gap - 1, second)
end

function Canvas:arrow(point, reversed)
    local forward = {TB = "v", BT = "^", LR = ">", RL = "<"}
    local backward = {TB = "^", BT = "v", LR = "<", RL = ">"}
    local cell = self:cell(point[1], point[2])
    self.arrows[self:key(cell[1], cell[2])] = (reversed and backward or forward)[self.direction]
end

function Canvas:highlight_route(points)
    for i = 1, #points - 1 do
        local a, b = points[i], points[i + 1]
        local row_step = b[1] > a[1] and 1 or b[1] < a[1] and -1 or 0
        local column_step = b[2] > a[2] and 1 or b[2] < a[2] and -1 or 0
        for step = 0, math.abs(b[1] - a[1]) + math.abs(b[2] - a[2]) do
            self.highlighted[self:key(a[1] + step * row_step, a[2] + step * column_step)] = true
        end
    end
end

function Canvas:box(label, band_start, coordinate, left, on_path)
    local text = on_path and "{" .. label .. "}" or "[" .. label .. "]"
    local row, column
    if self.vertical then local cell = self:cell(band_start, coordinate - left); row, column = cell[1], cell[2]
    elseif self.direction == "LR" then row, column = coordinate, band_start
    else row, column = coordinate, self.main_length - band_start - #text end
    for i = 1, #text do self.boxes[self:key(row, column + i - 1)] = text:sub(i, i) end
end

function Canvas:character(row, column)
    local key = self:key(row, column)
    if self.boxes[key] then return self.boxes[key] end
    if self.arrows[key] then return self.arrows[key] end
    if self.highlighted[key] then return "#" end
    return ({[0] = " ", [1] = "|", [2] = "-", [4] = "+"})[self.line_bits[key] or 0] or "+"
end

function Canvas:crossing_cells()
    local count = 0
    for _, bits in pairs(self.line_bits) do if bits & 3 == 3 then count = count + 1 end end
    return count
end

function Canvas:drawing_lines()
    local ruler = {}
    for column = 0, self.columns - 1 do ruler[#ruler + 1] = tostring(column % 10) end
    local lines = {"    " .. table.concat(ruler)}
    for row = 0, self.rows - 1 do
        local characters = {}
        for column = 0, self.columns - 1 do characters[#characters + 1] = self:character(row, column) end
        lines[#lines + 1] = (string.format("%3d ", row) .. table.concat(characters)):gsub(" +$", "")
    end
    return lines
end

return Canvas
