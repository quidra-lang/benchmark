local M = {}
function M.isqrt(value)
    if value < 2 then return value end
    local root, following = value, (value + 1) // 2
    while following < root do root, following = following, (following + value // following) // 2 end
    return root
end
function M.squared_distance(first, second)
    local dx, dy = first[1] - second[1], first[2] - second[2]
    return dx * dx + dy * dy
end
local function scaled(delta, step, length) return delta >= 0 and delta * step // length or -((-delta) * step // length) end
function M.advance(point, goal, step)
    local dx, dy = goal[1] - point[1], goal[2] - point[2]
    local squared = dx * dx + dy * dy
    if squared <= step * step then return goal, true end
    local length = M.isqrt(squared)
    return {point[1] + scaled(dx, step, length), point[2] + scaled(dy, step, length)}, false
end
function M.damage_dealt(hp, power, armor) return math.min(hp, math.max(1, power - armor)) end
local Effect = {}
Effect.__index = Effect
function Effect.new() return setmetatable({strength = 0, remaining = 0}, Effect) end
function Effect:active() return self.remaining > 0 end
function Effect:receive(strength, duration, source)
    if strength > self.strength then self.strength, self.remaining, self.source = strength, duration, source
    elseif strength == self.strength then self.remaining = math.max(self.remaining, duration) end
end
function Effect:advance_time()
    self.remaining = self.remaining - 1
    if self.remaining == 0 then self.strength, self.source = 0, nil end
end
local Projectile = {}
Projectile.__index = Projectile
function Projectile.new(number, tower, target, position, aim, targets, stats)
    return setmetatable({number = number, tower = tower, target = target, position = position, aim = aim, targets = targets,
        power = stats.power, speed = stats.shot_speed, splash = stats.splash, slow_rate = stats.slow_rate, slow_time = stats.slow_time,
        burn_amount = stats.burn_amount, burn_time = stats.burn_time}, Projectile)
end
function Projectile:fly()
    if self.speed == 0 then return true end
    local arrived
    self.position, arrived = M.advance(self.position, self.aim, self.speed)
    return arrived
end
M.Effect, M.Projectile = Effect, Projectile
return M
