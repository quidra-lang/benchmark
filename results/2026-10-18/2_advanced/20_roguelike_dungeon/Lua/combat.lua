local M = {}
local Dice = {}
Dice.__index = Dice

function Dice.new(count, sides) return setmetatable({count = count, sides = sides}, Dice) end
function Dice:roll(rng) return rng:roll(self.count, self.sides) end
function M.parse_dice(token)
    local count, sides = token:match("^(%d+)d(%d+)$")
    return Dice.new(tonumber(count), tonumber(sides))
end

function M.resolve_attack(rng, to_hit, defense, dice, bonus)
    local roll = 1 + rng:rnd(20)
    if roll == 1 then return "miss", 0 end
    local outcome, damage
    if roll == 20 then
        outcome = "critical"
        local first = dice:roll(rng)
        local second = dice:roll(rng)
        damage = first + second + bonus
    elseif roll + to_hit >= defense then outcome, damage = "hit", dice:roll(rng) + bonus
    else return "miss", 0 end
    return outcome, math.max(damage, 1)
end

M.Dice = Dice
return M
