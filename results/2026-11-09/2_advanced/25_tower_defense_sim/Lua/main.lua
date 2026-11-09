local source_directory = arg[0]:match("^(.*[/\\])") or "./"
package.path = source_directory .. "?.lua;" .. package.path
local grid_map = require("grid_map")
local pathing = require("pathing")
local towers = require("towers")
local enemies = require("enemies")
local combat = require("combat")
local income_fields = {"bounty", "reward", "interest", "early", "refund"}
local wave_columns = "wave,start,end,status,spawned,peak,kills,leaks,lives_lost,bounty,reward,interest,gold,lives"
local function fields(line) local result = {} for word in line:gmatch("[^ ]+") do result[#result + 1] = word end return result end
local function read_lines(name) local lines = {} for line in io.lines("input/" .. name) do lines[#lines + 1] = line end return lines end
local function write_lines(name, lines)
    local file = assert(io.open("output/" .. name, "w"))
    for _, line in ipairs(lines) do file:write(line, "\n") end
    file:close()
end
local function extend(target, values) for _, value in ipairs(values) do target[#target + 1] = value end end
local function map(values, fn) local result = {} for index, value in ipairs(values) do result[index] = fn(value, index) end return result end
local function zeros(count) local result = {} for index = 1, count do result[index] = 0 end return result end
local function one_decimal(numerator, denominator)
    if denominator == 0 then return "-" end
    local rounded = (20 * numerator + denominator) // (2 * denominator)
    return rounded // 10 .. "." .. rounded % 10
end
local function digit(count) return count == 0 and "." or count <= 9 and tostring(count) or "*" end
local function ruled(rows)
    local ruler = "  " for x = 0, #rows[1] - 1 do ruler = ruler .. x % 10 end
    local lines = {ruler}
    for y, row in ipairs(rows) do lines[#lines + 1] = (y - 1) % 10 .. " " .. table.concat(row) end
    return lines
end
local function read_params(lines)
    local values = map(lines, fields)
    local snapshots = {} for index = 2, #values[7] do snapshots[tonumber(values[7][index])] = true end
    return {gold = tonumber(values[1][2]), lives = tonumber(values[2][2]), interest_rate = tonumber(values[3][2]), interest_cap = tonumber(values[3][3]),
        sell_rate = tonumber(values[4][2]), start = tonumber(values[5][2]), interval = tonumber(values[5][3]), early = tonumber(values[6][2]), snapshots = snapshots}
end
local function read_actions(lines)
    return map(lines, function(line)
        local words = fields(line)
        local arguments = {} for index = 3, #words do arguments[#arguments + 1] = words[index] end
        return {tick = tonumber(words[1]), command = words[2], arguments = arguments}
    end)
end
local function wave_record(number, plan, tick)
    return {number = number, plan = plan, start = tick, ending = 0, status = "", released = zeros(#plan.groups), spawned = 0, peak = 0, kills = 0,
        leaks = 0, lives_lost = 0, bounty = 0, reward = 0, interest = 0, gold = 0, lives = 0, tower_damage = {}}
end
local function close_wave(wave, status, tick, gold, lives) wave.status, wave.ending, wave.gold, wave.lives = status, tick, gold, lives end
local function all_released(wave)
    for index, group in ipairs(wave.plan.groups) do if wave.released[index] ~= group.count then return false end end
    return true
end

local Game = {}
Game.__index = Game
function Game.new(grid, tower_types, enemy_types, waves, params)
    local self = setmetatable({grid = grid, tower_types = {}, enemy_types = enemy_types, waves = waves, params = params, exit_center = grid_map.cell_center(grid.exit),
        tick = 0, gold = params.gold, lives = params.lives, towers = {}, enemies = {}, all_enemies = {}, projectiles = {}, projectile_count = 0,
        records = {}, next_start = params.start, field = pathing.DistanceField.new(grid, {}), kill_counts = {}, income = {}, spent = 0, done = 0, refused = 0, events = {}, snapshots = {}}, Game)
    for _, kind in ipairs(tower_types) do self.tower_types[kind.name] = kind end
    for y = 1, grid.height do self.kill_counts[y] = zeros(grid.width) end
    for _, name in ipairs(income_fields) do self.income[name] = 0 end
    return self
end
function Game:record(...)
    local parts = {tostring(self.tick)}
    for _, value in ipairs({...}) do parts[#parts + 1] = tostring(value) end
    self.events[#self.events + 1] = table.concat(parts, " ")
end
function Game:run(actions)
    local index = 1
    while true do
        self.tick = self.tick + 1
        while index <= #actions and actions[index].tick == self.tick do self:perform(actions[index]) index = index + 1 end
        self:spawn_enemies()
        self:move_enemies()
        if self.outcome then break end
        self:fire_towers()
        self:move_projectiles()
        self:check_wave_end()
        if self.params.snapshots[self.tick] then extend(self.snapshots, self:block("SNAPSHOT")) end
        if self.outcome then break end
    end
    extend(self.snapshots, self:final_block())
end
function Game:standing_towers()
    local result = {} for _, tower in ipairs(self.towers) do if tower:standing() then result[#result + 1] = tower end end return result
end
function Game:tower_cells()
    local result = {} for _, tower in ipairs(self:standing_towers()) do result[grid_map.key(tower.cell)] = true end return result
end
function Game:tower_at(cell)
    for _, tower in ipairs(self:standing_towers()) do if grid_map.same(tower.cell, cell) then return tower end end
end
function Game:standing_tower(text)
    local tower = self.towers[tonumber(text)]
    return tower and tower:standing() and tower or nil
end
function Game:ground_enemies()
    local result = {} for _, enemy in ipairs(self.enemies) do if not enemy:flying() then result[#result + 1] = enemy end end return result
end
function Game:perform(action)
    local handlers = {BUILD = self.build, UPGRADE = self.upgrade, SELL = self.sell, TARGET = self.set_target, CALL = self.call_wave}
    if handlers[action.command](self, action.arguments) then self.done = self.done + 1 else self.refused = self.refused + 1 end
end
function Game:build_refusal(name, cell)
    if not self.tower_types[name] then return "type" end
    if not self.grid:inside(cell) then return "bounds" end
    if not self.grid:buildable(cell) then return "terrain" end
    if self:tower_at(cell) then return "tower" end
    if self.gold < self.tower_types[name].levels[1].cost then return "gold" end
    local walkers = self:ground_enemies()
    for _, enemy in ipairs(walkers) do if grid_map.same(enemy.cell, cell) or grid_map.same(enemy.next_cell, cell) then return "enemy" end end
    local occupied = self:tower_cells()
    occupied[grid_map.key(cell)] = true
    local trial = pathing.DistanceField.new(self.grid, occupied)
    for _, spawn in ipairs(self.grid.spawns) do if trial:at(spawn) < 0 then return "blocked" end end
    for _, enemy in ipairs(walkers) do if trial:at(enemy.next_cell) < 0 then return "blocked" end end
end
function Game:build(arguments)
    local name, cell = arguments[1], {tonumber(arguments[2]), tonumber(arguments[3])}
    local reason = self:build_refusal(name, cell)
    if reason then self:record("BUILD_REFUSED", name, arguments[2], arguments[3], reason) return false end
    local kind = self.tower_types[name]
    local cost = kind.levels[1].cost
    local tower = towers.Tower.new(#self.towers + 1, kind, cell, self.tick)
    self.towers[#self.towers + 1] = tower
    self.gold, self.spent = self.gold - cost, self.spent + cost
    self:record("BUILD", "T" .. tower.number, name, cell[1], cell[2], "cost", cost, "gold", self.gold)
    self:update_field()
    return true
end
function Game:upgrade(arguments)
    local tower, reason = self:standing_tower(arguments[1]), nil
    if not tower then reason = "notower"
    elseif tower.level == #tower.kind.levels then reason = "maxlevel"
    elseif self.gold < tower.kind.levels[tower.level + 1].cost then reason = "gold"
    else
        local cost = tower.kind.levels[tower.level + 1].cost
        self.gold, self.spent = self.gold - cost, self.spent + cost
        tower.level, tower.investment = tower.level + 1, tower.investment + cost
        self:record("UPGRADE", "T" .. tower.number, "level", tower.level, "cost", cost, "gold", self.gold)
        return true
    end
    self:record("UPGRADE_REFUSED", "T" .. arguments[1], reason)
    return false
end
function Game:sell(arguments)
    local tower = self:standing_tower(arguments[1])
    if not tower then self:record("SELL_REFUSED", "T" .. arguments[1], "notower") return false end
    local rate = self.tick == tower.built and 100 or self.params.sell_rate
    local refund = tower.investment * rate // 100
    tower.sold, self.gold = self.tick, self.gold + refund
    self.income.refund = self.income.refund + refund
    self:record("SELL", "T" .. tower.number, "refund", refund, "gold", self.gold)
    self:update_field()
    return true
end
function Game:set_target(arguments)
    local tower, reason = self:standing_tower(arguments[1]), nil
    if not tower then reason = "notower"
    elseif not towers.TARGET_MODES[arguments[2]] then reason = "mode"
    else tower.mode = arguments[2] self:record("TARGET", "T" .. tower.number, tower.mode) return true end
    self:record("TARGET_REFUSED", "T" .. arguments[1], reason)
    return false
end
function Game:call_wave()
    if self.active then self:record("CALL_REFUSED", "active") return false end
    local bonus = (self.next_start - self.tick) * self.params.early
    self.gold, self.income.early, self.next_start = self.gold + bonus, self.income.early + bonus, self.tick
    self:record("CALL", #self.records + 1, "bonus", bonus, "gold", self.gold)
    return true
end
function Game:update_field()
    local before = self.field
    self.field = pathing.DistanceField.new(self.grid, self:tower_cells())
    for number, spawn in ipairs(self.grid.spawns) do
        local old, new = before:at(spawn), self.field:at(spawn)
        if old ~= new then self:record("REPATH", number, old, new) end
    end
end
function Game:start_wave()
    local plan = self.waves[#self.records + 1]
    local wave = wave_record(#self.records + 1, plan, self.tick)
    self.records[#self.records + 1], self.active, self.next_start = wave, wave, nil
    local count = 0 for _, group in ipairs(plan.groups) do count = count + group.count end
    self:record("WAVE_START", wave.number, "enemies", count)
end
function Game:add_enemy(enemy)
    self.enemies[#self.enemies + 1], self.all_enemies[#self.all_enemies + 1] = enemy, enemy
    self.active.spawned, enemy.kind.spawned = self.active.spawned + 1, enemy.kind.spawned + 1
end
function Game:remove_enemy(enemy)
    enemy.alive = false
    for index, current in ipairs(self.enemies) do if current == enemy then table.remove(self.enemies, index) return end end
end
function Game:spawn_enemies()
    if self.tick == self.next_start then self:start_wave() end
    local wave = self.active
    if not wave then return end
    for index, group in ipairs(wave.plan.groups) do
        local released = wave.released[index]
        if released < group.count and group.delay + wave.start + released * group.interval == self.tick then
            wave.released[index] = released + 1
            local spawn = self.grid.spawns[group.spawn]
            local enemy = enemies.Enemy.new(#self.all_enemies + 1, group.kind, group.multiplier)
            if enemy:flying() then enemy.point = grid_map.cell_center(spawn) else enemy.cell, enemy.next_cell = spawn, self.field:next_cell(spawn) end
            self:add_enemy(enemy)
            self:record("SPAWN", "E" .. enemy.number, enemy.kind.name, group.spawn, "hp", enemy.hp)
        end
    end
    wave.peak = math.max(wave.peak, #self.enemies)
end
function Game:move_enemies()
    local moving = map(self.enemies, function(enemy) return enemy end)
    for _, enemy in ipairs(moving) do self:move_enemy(enemy) if self.outcome then return end end
end
function Game:move_enemy(enemy)
    if enemy.burn:active() then
        local source = self.towers[enemy.burn.source]
        local damage = math.min(enemy.hp, enemy.burn.strength)
        enemy.hp = enemy.hp - damage
        self:credit(source, enemy, damage)
        enemy.burn:advance_time()
        if enemy.hp == 0 then self:kill(enemy, source) return end
    end
    enemy.hp = math.min(enemy.hp + enemy.kind.regen, enemy.max_hp)
    local speed = enemy:slowed_speed()
    if enemy.slow:active() then enemy.slow:advance_time() end
    local arrived
    if enemy:flying() then enemy.point, arrived = combat.advance(enemy.point, self.exit_center, speed) else arrived = self:walk(enemy, speed) end
    if arrived then self:leak(enemy) end
end
function Game:walk(enemy, speed)
    if self.grid:is_water(enemy:occupied_cell()) then speed = speed // 2 end
    while speed > 0 do
        local rest = 100 - enemy.progress
        if speed < rest then enemy.progress, speed = enemy.progress + speed, 0
        else
            speed, enemy.cell, enemy.progress = speed - rest, enemy.next_cell, 0
            if grid_map.same(enemy.cell, self.grid.exit) then return true end
            enemy.next_cell = self.field:next_cell(enemy.cell)
        end
    end
    return false
end
function Game:leak(enemy)
    self:remove_enemy(enemy)
    local lost, wave = math.min(self.lives, enemy.kind.lives), self.active
    self.lives = self.lives - lost
    wave.leaks, wave.lives_lost, enemy.kind.leaks = wave.leaks + 1, wave.lives_lost + lost, enemy.kind.leaks + 1
    self:record("LEAK", "E" .. enemy.number, enemy.kind.name, "lives", self.lives)
    if self.lives == 0 then
        self:record("DEFEAT")
        self.outcome = "defeat"
        close_wave(wave, "lost", self.tick, self.gold, self.lives)
        self.active = nil
    end
end
function Game:fire_towers()
    for _, tower in ipairs(self:standing_towers()) do
        if self.tick >= tower.ready then local target = tower:select_target(self.enemies, self.field) if target then self:fire(tower, target) end end
    end
end
function Game:fire(tower, target)
    local stats = tower:stats()
    self.projectile_count = self.projectile_count + 1
    self.projectiles[#self.projectiles + 1] = combat.Projectile.new(self.projectile_count, tower.number, target.number, tower:center(), target:position(), tower.kind.targets, stats)
    tower.shots, tower.ready = tower.shots + 1, self.tick + stats.interval
    self:record("SHOT", "T" .. tower.number, "E" .. target.number)
end
function Game:move_projectiles()
    local flying = {}
    for _, projectile in ipairs(self.projectiles) do
        local target = self.all_enemies[projectile.target]
        if target.alive then projectile.aim = target:position() end
        if projectile:fly() then self:impact(projectile) else flying[#flying + 1] = projectile end
    end
    self.projectiles = flying
end
function Game:impact(projectile)
    local tower, target, victims = self.towers[projectile.tower], self.all_enemies[projectile.target], {}
    if projectile.splash == 0 then if target.alive then victims[1] = target end
    else
        local reach = projectile.splash * projectile.splash
        for _, enemy in ipairs(self.enemies) do
            if towers.can_aim(projectile.targets, enemy) and combat.squared_distance(enemy:position(), projectile.aim) <= reach then victims[#victims + 1] = enemy end
        end
    end
    if #victims == 0 then tower.fizzles = tower.fizzles + 1 end
    for _, enemy in ipairs(victims) do
        tower.hits = tower.hits + 1
        local damage = combat.damage_dealt(enemy.hp, projectile.power, enemy.kind.armor)
        enemy.hp = enemy.hp - damage
        self:credit(tower, enemy, damage)
        if enemy.hp == 0 then self:kill(enemy, tower)
        else
            if projectile.slow_rate > 0 then enemy.slow:receive(projectile.slow_rate, projectile.slow_time) end
            if projectile.burn_amount > 0 then enemy.burn:receive(projectile.burn_amount, projectile.burn_time, tower.number) end
        end
    end
end
function Game:credit(tower, enemy, damage)
    tower.damage, enemy.kind.damage = tower.damage + damage, enemy.kind.damage + damage
    local wave_damage = self.active.tower_damage
    wave_damage[tower.number] = (wave_damage[tower.number] or 0) + damage
end
function Game:kill(enemy, tower)
    self:remove_enemy(enemy)
    local cell = enemy:occupied_cell()
    self.kill_counts[cell[2] + 1][cell[1] + 1] = self.kill_counts[cell[2] + 1][cell[1] + 1] + 1
    local wave, bounty = self.active, enemy.kind.bounty
    tower.kills, wave.kills, enemy.kind.kills = tower.kills + 1, wave.kills + 1, enemy.kind.kills + 1
    self.gold, wave.bounty, self.income.bounty = self.gold + bounty, wave.bounty + bounty, self.income.bounty + bounty
    self:record("KILL", "E" .. enemy.number, enemy.kind.name, "T" .. tower.number, "bounty", bounty, "gold", self.gold)
    for _ = 1, enemy.kind.split_count do
        local child = enemy:split(#self.all_enemies + 1)
        self:add_enemy(child)
        self:record("SPAWN", "E" .. child.number, child.kind.name, "E" .. enemy.number, "hp", child.hp)
    end
end
function Game:check_wave_end()
    local wave = self.active
    if not wave or #self.enemies > 0 or not all_released(wave) then return end
    self.gold = self.gold + wave.plan.reward
    local interest = math.min(self.params.interest_cap, self.gold * self.params.interest_rate // 100)
    self.gold = self.gold + interest
    wave.reward, wave.interest = wave.plan.reward, interest
    self.income.reward, self.income.interest, self.active = self.income.reward + wave.reward, self.income.interest + interest, nil
    self:record("WAVE_END", wave.number, "reward", wave.reward, "interest", interest, "gold", self.gold)
    if wave.number == #self.waves then self:record("VICTORY") self.outcome = "victory" else self.next_start = self.tick + self.params.interval end
    close_wave(wave, "cleared", self.tick, self.gold, self.lives)
end

function Game:map_picture()
    local rows = {}
    for y, text in ipairs(self.grid.rows) do
        rows[y] = {}
        for x = 1, #text do rows[y][x] = text:sub(x, x) end
    end
    for _, spawn in ipairs(self.grid.spawns) do
        for _, cell in ipairs(self.field:path(spawn)) do
            local terrain = self.grid:terrain(cell)
            if terrain == "." or terrain == "~" then rows[cell[2] + 1][cell[1] + 1] = "+" end
        end
    end
    for _, tower in ipairs(self:standing_towers()) do rows[tower.cell[2] + 1][tower.cell[1] + 1] = tower.kind.symbol end
    local occupants = {}
    for _, enemy in ipairs(self.enemies) do
        local cell = enemy:occupied_cell()
        local key = grid_map.key(cell)
        occupants[key] = (occupants[key] or 0) + 1
        rows[cell[2] + 1][cell[1] + 1] = occupants[key] == 1 and enemy.kind.symbol or "*"
    end
    return rows
end
function Game:flow_picture()
    local rows, arrows = {}, {"^", ">", "v", "<"}
    for y = 0, self.grid.height - 1 do
        local row = {}
        for x = 0, self.grid.width - 1 do
            local cell = {x, y}
            local terrain, tower = self.grid:terrain(cell), self:tower_at(cell)
            if terrain == "#" or terrain == "E" then row[#row + 1] = terrain
            elseif tower then row[#row + 1] = tower.kind.symbol
            elseif self.field:at(cell) < 0 then row[#row + 1] = "?"
            else row[#row + 1] = arrows[self.field:direction(cell)] end
        end
        rows[#rows + 1] = row
    end
    return rows
end
function Game:coverage_picture()
    local rows, standing = {}, self:standing_towers()
    for y = 0, self.grid.height - 1 do
        local row = {}
        for x = 0, self.grid.width - 1 do
            local cell, count = {x, y}, 0
            local tower = self:tower_at(cell)
            if self.grid:is_rock(cell) then row[#row + 1] = "#"
            elseif tower then row[#row + 1] = tower.kind.symbol
            else
                for _, other in ipairs(standing) do if other:in_range(grid_map.cell_center(cell)) then count = count + 1 end end
                row[#row + 1] = digit(count)
            end
        end
        rows[#rows + 1] = row
    end
    return rows
end
function Game:kills_picture()
    local rows = {}
    for y = 0, self.grid.height - 1 do
        local row = {}
        for x = 0, self.grid.width - 1 do
            local count = self.kill_counts[y + 1][x + 1]
            row[#row + 1] = count > 0 and digit(count) or self.grid:is_rock({x, y}) and "#" or "."
        end
        rows[#rows + 1] = row
    end
    return rows
end
function Game:block(label)
    local next_text = self.active == nil and self.outcome == nil and tostring(self.next_start) or "-"
    local lines = {label .. " " .. self.tick .. " wave " .. #self.records .. " next " .. next_text .. " gold " .. self.gold .. " lives " .. self.lives}
    extend(lines, ruled(self:map_picture()))
    for number, spawn in ipairs(self.grid.spawns) do lines[#lines + 1] = "PATH " .. number .. " length " .. self.field:at(spawn) end
    for _, tower in ipairs(self:standing_towers()) do
        lines[#lines + 1] = "T" .. tower.number .. " " .. tower.kind.name .. " " .. tower.cell[1] .. " " .. tower.cell[2] .. " level " .. tower.level .. " mode " .. tower.mode .. " ready " .. tower.ready
    end
    for _, enemy in ipairs(self.enemies) do
        local point = enemy:position()
        lines[#lines + 1] = "E" .. enemy.number .. " " .. enemy.kind.name .. " " .. point[1] .. " " .. point[2] .. " hp " .. enemy.hp .. "/" .. enemy.max_hp
            .. " slow " .. enemy.slow.strength .. " " .. enemy.slow.remaining .. " burn " .. enemy.burn.strength .. " " .. enemy.burn.remaining
    end
    for _, projectile in ipairs(self.projectiles) do
        lines[#lines + 1] = "P" .. projectile.number .. " T" .. projectile.tower .. " E" .. projectile.target .. " " .. projectile.position[1] .. " " .. projectile.position[2]
    end
    return lines
end
function Game:final_block()
    local lines = self:block("FINAL")
    lines[#lines + 1] = "FLOW"
    extend(lines, ruled(self:flow_picture()))
    lines[#lines + 1] = "COVERAGE"
    extend(lines, ruled(self:coverage_picture()))
    lines[#lines + 1] = "KILLS"
    extend(lines, ruled(self:kills_picture()))
    return lines
end
function Game:wave_lines()
    local header = wave_columns
    for _, tower in ipairs(self.towers) do header = header .. ",T" .. tower.number end
    local lines = {header}
    for _, wave in ipairs(self.records) do
        local values = {wave.number, wave.start, wave.ending, wave.status, wave.spawned, wave.peak, wave.kills, wave.leaks, wave.lives_lost,
            wave.bounty, wave.reward, wave.interest, wave.gold, wave.lives}
        for number = 1, #self.towers do values[#values + 1] = wave.tower_damage[number] or 0 end
        lines[#lines + 1] = table.concat(map(values, function(value) return tostring(value) end), ",")
    end
    return lines
end
function Game:mvp_line()
    local best
    for _, tower in ipairs(self.towers) do if not best or tower.damage > best.damage then best = tower end end
    return best and "mvp T" .. best.number .. " damage " .. best.damage or "mvp -"
end
function Game:tower_line(tower, total_damage)
    local state = tower:standing() and "active" or "sold " .. tower.sold
    return "TOWER T" .. tower.number .. " " .. tower.kind.name .. " " .. tower.cell[1] .. " " .. tower.cell[2] .. " level " .. tower.level .. " mode " .. tower.mode .. " " .. state
        .. " shots " .. tower.shots .. " hits " .. tower.hits .. " fizzles " .. tower.fizzles .. " kills " .. tower.kills .. " damage " .. tower.damage
        .. " per_shot " .. one_decimal(tower.damage, tower.shots) .. " share " .. one_decimal(100 * tower.damage, total_damage) .. " invested " .. tower.investment
end
function Game:summary_lines(action_count)
    local cleared, perfect, spawned, killed, leaked, total_damage = 0, 0, 0, 0, 0, 0
    for _, wave in ipairs(self.records) do
        if wave.status == "cleared" then cleared = cleared + 1 if wave.leaks == 0 then perfect = perfect + 1 end end
    end
    for _, kind in ipairs(self.enemy_types) do spawned, killed, leaked = spawned + kind.spawned, killed + kind.kills, leaked + kind.leaks end
    for _, tower in ipairs(self.towers) do total_damage = total_damage + tower.damage end
    local income = {} for _, name in ipairs(income_fields) do income[#income + 1] = name .. " " .. self.income[name] end
    local score = 10 * killed + 100 * self.lives + 50 * perfect + self.gold
    local lines = {"outcome " .. self.outcome, "ticks " .. self.tick, "waves " .. cleared .. "/" .. #self.waves .. " perfect " .. perfect,
        "lives " .. self.lives .. "/" .. self.params.lives, "gold " .. self.gold, "enemies spawned " .. spawned .. " killed " .. killed .. " leaked " .. leaked,
        "income " .. table.concat(income, " "), "spent " .. self.spent, "damage " .. total_damage,
        "actions total " .. action_count .. " done " .. self.done .. " refused " .. self.refused .. " unused " .. (action_count - self.done - self.refused), "score " .. score, self:mvp_line()}
    for _, kind in ipairs(self.enemy_types) do lines[#lines + 1] = "ENEMY " .. kind.name .. " spawned " .. kind.spawned .. " killed " .. kind.kills .. " leaked " .. kind.leaks .. " damage " .. kind.damage end
    for _, tower in ipairs(self.towers) do lines[#lines + 1] = self:tower_line(tower, total_damage) end
    return lines
end

local function main()
    local grid = grid_map.read_map("input/map.txt")
    local tower_types = towers.parse_tower_types(read_lines("towers.txt"))
    local enemy_types, waves = enemies.parse_waves(read_lines("waves.txt"))
    local actions = read_actions(read_lines("actions.txt"))
    local game = Game.new(grid, tower_types, enemy_types, waves, read_params(read_lines("params.txt")))
    game:run(actions)
    os.execute("mkdir -p output")
    write_lines("events.txt", game.events)
    write_lines("waves.csv", game:wave_lines())
    write_lines("snapshots.txt", game.snapshots)
    write_lines("summary.txt", game:summary_lines(#actions))
end

main()
