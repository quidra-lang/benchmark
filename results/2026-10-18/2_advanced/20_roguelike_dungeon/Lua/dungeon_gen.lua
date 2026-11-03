local M = {}
local Level = {}
Level.__index = Level

function Level.new(depth, width, height)
    local terrain, memory = {}, {}
    for y = 1, height do
        terrain[y], memory[y] = {}, {}
        for x = 1, width do terrain[y][x], memory[y][x] = " ", " " end
    end
    return setmetatable({depth = depth, width = width, height = height, terrain = terrain, memory = memory,
        rooms = {}, monsters = {}, items = {}, monsters_created = 0, items_placed = 0, kills = 0, picked = 0}, Level)
end

function Level:monster_at(x, y)
    for _, monster in ipairs(self.monsters) do if monster.x == x and monster.y == y then return monster end end
    return nil
end
function Level:item_at(x, y)
    for _, item in ipairs(self.items) do if item.x == x and item.y == y then return item end end
    return nil
end
function Level:draw_interior_cell(rng, index)
    local room = self.rooms[index]
    local x = room.x + 1 + rng:rnd(room.width - 2)
    local y = room.y + 1 + rng:rnd(room.height - 2)
    return x, y
end
function Level:draw_room_cell(rng)
    local index = rng:rnd(#self.rooms) + 1
    local x, y = self:draw_interior_cell(rng, index)
    return index, x, y
end

local Generator = {}
Generator.__index = Generator
function Generator.new(rng, min_size, max_split, room_min, room_max)
    return setmetatable({rng = rng, min_size = min_size, max_split = max_split, room_min = room_min, room_max = room_max}, Generator)
end

function Generator:split(region, depth, leaves)
    local cv, ch = region.width >= 2 * self.min_size, region.height >= 2 * self.min_size
    if depth == self.max_split or not (cv or ch) then
        region.leaf = #leaves + 1
        leaves[#leaves + 1] = region
        return
    end
    local vertical
    if cv and ch then
        if 4 * region.width >= 5 * region.height then vertical = true
        elseif 4 * region.height >= 5 * region.width then vertical = false
        else vertical = self.rng:draw() % 2 == 0 end
    else vertical = cv end
    local x, y, w, h = region.x, region.y, region.width, region.height
    if vertical then
        local cut = self.min_size + self.rng:rnd(w - 2 * self.min_size + 1)
        region.first, region.second = {x = x, y = y, width = cut, height = h}, {x = x + cut, y = y, width = w - cut, height = h}
    else
        local cut = self.min_size + self.rng:rnd(h - 2 * self.min_size + 1)
        region.first, region.second = {x = x, y = y, width = w, height = cut}, {x = x, y = y + cut, width = w, height = h - cut}
    end
    self:split(region.first, depth + 1, leaves)
    self:split(region.second, depth + 1, leaves)
end

function Generator:make_room(level, region)
    local width = self.room_min + self.rng:rnd(math.min(self.room_max, region.width - 1) - self.room_min + 1)
    local height = self.room_min + self.rng:rnd(math.min(self.room_max, region.height - 1) - self.room_min + 1)
    local x = region.x + self.rng:rnd(region.width - width)
    local y = region.y + self.rng:rnd(region.height - height)
    for row = y, y + height - 1 do
        for column = x, x + width - 1 do
            local symbol = "."
            if row == y or row == y + height - 1 then symbol = "-"
            elseif column == x or column == x + width - 1 then symbol = "|" end
            level.terrain[row + 1][column + 1] = symbol
        end
    end
    return {x = x, y = y, width = width, height = height, cx = x + width // 2, cy = y + height // 2}
end

function Generator:dig(level, a, b, horizontal_first)
    local function cell(x, y)
        local mark = level.terrain[y + 1][x + 1]
        if mark == " " then level.terrain[y + 1][x + 1] = "#"
        elseif mark == "-" or mark == "|" then level.terrain[y + 1][x + 1] = "+" end
    end
    local sx, sy = b.cx >= a.cx and 1 or -1, b.cy >= a.cy and 1 or -1
    if horizontal_first then
        for x = a.cx, b.cx, sx do cell(x, a.cy) end
        for y = a.cy, b.cy, sy do cell(b.cx, y) end
    else
        for y = a.cy, b.cy, sy do cell(a.cx, y) end
        for x = a.cx, b.cx, sx do cell(x, b.cy) end
    end
end

function Generator:connect(level, region)
    if region.leaf then return {region.leaf} end
    local first = self:connect(level, region.first)
    local second = self:connect(level, region.second)
    local best_a, best_b, best_distance
    for _, a in ipairs(first) do
        for _, b in ipairs(second) do
            local one, two = level.rooms[a], level.rooms[b]
            local distance = math.abs(one.cx - two.cx) + math.abs(one.cy - two.cy)
            if best_a == nil or distance < best_distance then best_a, best_b, best_distance = a, b, distance end
        end
    end
    local horizontal = self.rng:draw() % 2 == 0
    self:dig(level, level.rooms[best_a], level.rooms[best_b], horizontal)
    for _, room in ipairs(second) do first[#first + 1] = room end
    return first
end

function Generator:generate(depth, width, height)
    local level = Level.new(depth, width, height)
    local root, leaves = {x = 0, y = 0, width = width, height = height}, {}
    self:split(root, 0, leaves)
    for _, leaf in ipairs(leaves) do level.rooms[#level.rooms + 1] = self:make_room(level, leaf) end
    self:connect(level, root)
    local room, x, y = level:draw_room_cell(self.rng)
    level.terrain[y + 1][x + 1], level.arrival, level.arrival_room = "<", {x, y}, room
    local other = self.rng:rnd(#level.rooms - 1) + 1
    if other >= room then other = other + 1 end
    local tx, ty = level:draw_interior_cell(self.rng, other)
    level.target = {tx, ty}
    return level
end

M.Level, M.Generator = Level, Generator
return M
