local combat = require("combat")
local grid_map = require("grid_map")
local M = {}
function M.parse_waves(lines)
    local types, known, waves = {}, {}, {}
    for _, line in ipairs(lines) do
        local fields = {} for field in line:gmatch("[^ ]+") do fields[#fields + 1] = field end
        if fields[1] == "enemy" then
            local kind = {name = fields[2], symbol = fields[3], movement = fields[4], hp = tonumber(fields[5]), armor = tonumber(fields[6]),
                speed = tonumber(fields[7]), bounty = tonumber(fields[8]), lives = tonumber(fields[9]), regen = tonumber(fields[10]),
                split_into = known[fields[11]], split_count = tonumber(fields[12]), spawned = 0, kills = 0, leaks = 0, damage = 0}
            types[#types + 1], known[kind.name] = kind, kind
        elseif fields[1] == "wave" then waves[#waves + 1] = {reward = tonumber(fields[2]), groups = {}}
        else
            local groups = waves[#waves].groups
            groups[#groups + 1] = {kind = known[fields[2]], spawn = tonumber(fields[3]), count = tonumber(fields[4]), delay = tonumber(fields[5]), interval = tonumber(fields[6]), multiplier = tonumber(fields[7])}
        end
    end
    return types, waves
end
local Enemy = {}
Enemy.__index = Enemy
function Enemy.new(number, kind, multiplier)
    local hp = kind.hp * multiplier // 100
    return setmetatable({number = number, kind = kind, multiplier = multiplier, max_hp = hp, hp = hp, slow = combat.Effect.new(),
        burn = combat.Effect.new(), alive = true, progress = 0}, Enemy)
end
function Enemy:flying() return self.kind.movement == "air" end
function Enemy:position()
    if self:flying() then return self.point end
    return {100 * self.cell[1] + (self.next_cell[1] - self.cell[1]) * self.progress, 100 * self.cell[2] + (self.next_cell[2] - self.cell[2]) * self.progress}
end
function Enemy:occupied_cell()
    if self:flying() then return {(self.point[1] + 50) // 100, (self.point[2] + 50) // 100} end
    return self.progress < 50 and self.cell or self.next_cell
end
function Enemy:remaining(field)
    if self:flying() then return combat.isqrt(combat.squared_distance(self.point, grid_map.cell_center(field.exit))) end
    return 100 * field:at(self.next_cell) + 100 - self.progress
end
function Enemy:slowed_speed()
    return self.slow:active() and self.kind.speed * (100 - self.slow.strength) // 100 or self.kind.speed
end
function Enemy:split(number)
    local child = Enemy.new(number, self.kind.split_into, self.multiplier)
    child.cell, child.next_cell, child.progress, child.point = self.cell, self.next_cell, self.progress, self.point
    return child
end
M.Enemy = Enemy
return M
