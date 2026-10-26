local combat = require("combat")
local grid_map = require("grid_map")
local M = {TARGET_MODES = {FIRST = true, LAST = true, STRONGEST = true, WEAKEST = true, CLOSEST = true}}
function M.parse_tower_types(lines)
    local types, index = {}, 1
    local attributes = {"cost", "range", "power", "interval", "shot_speed", "splash", "slow_rate", "slow_time", "burn_amount", "burn_time"}
    while index <= #lines do
        local name, symbol, targets, count = lines[index]:match("^tower ([^ ]+) ([^ ]+) ([^ ]+) (%d+)$")
        local levels = {}
        for offset = 1, tonumber(count) do
            local level, position = {}, 0
            for value in lines[index + offset]:gmatch("[^ ]+") do
                if position > 0 then level[attributes[position]] = tonumber(value) end
                position = position + 1
            end
            levels[offset] = level
        end
        types[#types + 1] = {name = name, symbol = symbol, targets = targets, levels = levels}
        index = index + tonumber(count) + 1
    end
    return types
end
function M.can_aim(targets, enemy) return targets == "both" or targets == enemy.kind.movement end
local Tower = {}
Tower.__index = Tower
function Tower.new(number, kind, cell, tick)
    return setmetatable({number = number, kind = kind, cell = cell, level = 1, mode = "FIRST", ready = tick,
        investment = kind.levels[1].cost, built = tick, shots = 0, hits = 0, fizzles = 0, kills = 0, damage = 0}, Tower)
end
function Tower:stats() return self.kind.levels[self.level] end
function Tower:center() return grid_map.cell_center(self.cell) end
function Tower:standing() return self.sold == nil end
function Tower:in_range(point) local range = self:stats().range return combat.squared_distance(self:center(), point) <= range * range end
function Tower:target_key(enemy, field)
    if self.mode == "FIRST" then return enemy:remaining(field) end
    if self.mode == "LAST" then return -enemy:remaining(field) end
    if self.mode == "STRONGEST" then return -enemy.hp end
    if self.mode == "WEAKEST" then return enemy.hp end
    return combat.squared_distance(self:center(), enemy:position())
end
function Tower:select_target(enemies, field)
    local best, best_key
    for _, enemy in ipairs(enemies) do
        if M.can_aim(self.kind.targets, enemy) and self:in_range(enemy:position()) then
            local key = self:target_key(enemy, field)
            if best == nil or key < best_key then best, best_key = enemy, key end
        end
    end
    return best
end
M.Tower = Tower
return M
