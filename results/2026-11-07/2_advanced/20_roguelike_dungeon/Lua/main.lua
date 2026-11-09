local source_directory = (arg[0]:match("^(.*[/\\])") or "./")
package.path = source_directory .. "?.lua;" .. package.path
local Minstd = require("minstd")
local combat = require("combat")
local dungeon_gen = require("dungeon_gen")
local entities = require("entities")
local fov = require("fov")

local command_classes = {quaff = "potion", read = "scroll", wield = "weapon", wear = "armor", eat = "food"}
local hunger_messages = {hungry = "You are getting hungry.", weak = "You feel weak from hunger.", starving = "You are starving."}
local usage_fields = {"picked", "quaffed", "read", "eaten", "wielded", "worn"}
local unarmed_damage = combat.Dice.new(1, 2)

local function extend(target, values) for _, value in ipairs(values) do target[#target + 1] = value end end
local function read_rows(name)
    local rows = {}
    for line in io.lines("input/" .. name) do
        local tokens = {}
        for token in line:gmatch("[^ ]+") do tokens[#tokens + 1] = token end
        rows[#rows + 1] = tokens
    end
    return rows
end

local function config(rows)
    local values = {}
    for _, row in ipairs(rows) do
        local tokens = {}
        for index = 2, #row do tokens[#tokens + 1] = row[index] end
        values[row[1]] = tokens
    end
    local result = {
        generation_seed = tonumber(values.seed[1]), game_seed = tonumber(values.seed[2]),
        width = tonumber(values.map[1]), height = tonumber(values.map[2]),
        min_size = tonumber(values.bsp[1]), max_split = tonumber(values.bsp[2]),
        room_min = tonumber(values.room[1]), room_max = tonumber(values.room[2]), levels = tonumber(values.levels[1]),
        monster_base = tonumber(values.monsters[1]), monster_step = tonumber(values.monsters[2]),
        item_base = tonumber(values.items[1]), item_step = tonumber(values.items[2]),
        sleep_chance = tonumber(values.sleep[1]), wake_chance = tonumber(values.sleep[2]), fov_radius = tonumber(values.fov[1]),
        max_hp = tonumber(values.player[1]), regen_interval = tonumber(values.player[2]), hit_die = combat.parse_dice(values.hitdie[1]),
        food_start = tonumber(values.food[1]), food_max = tonumber(values.food[2]), food_hungry = tonumber(values.food[3]), food_weak = tonumber(values.food[4]),
        pack_limit = tonumber(values.pack[1]), start_items = values.start, xp_levels = {}, checkpoints = {}
    }
    for _, value in ipairs(values.xp) do result.xp_levels[#result.xp_levels + 1] = tonumber(value) end
    for _, value in ipairs(values.checkpoints) do result.checkpoints[tonumber(value)] = true end
    return result
end

local function expand_commands(rows)
    local commands = {}
    for _, row in ipairs(rows) do
        local name, argument, count = row[1], row[2], 1
        if name == "wait" then argument, count = nil, tonumber(row[2]) or 1
        elseif #row == 3 then count = tonumber(row[3]) end
        for _ = 1, count do commands[#commands + 1] = {name = name, argument = argument} end
    end
    return commands
end

local function dec_1(a, b)
    if b == 0 then return "-" end
    local z = (20 * a + b) // (2 * b)
    return (z // 10) .. "." .. (z % 10)
end

local function exploration(level)
    local explored, total = 0, 0
    for y = 1, level.height do
        for x = 1, level.width do
            if level.terrain[y][x] ~= " " then
                total = total + 1
                if level.memory[y][x] ~= " " then explored = explored + 1 end
            end
        end
    end
    return explored, total
end

local function remove_item(values, object)
    for index, value in ipairs(values) do if value == object then table.remove(values, index) return end end
end

local function defense(player) return 10 + (player.armor and player.armor.kind.armor + player.armor.bonus or 0) end
local function attack_stats() return {count = 0, hits = 0, criticals = 0, damage = 0} end
local function record_attack(stats, outcome, damage)
    stats.count = stats.count + 1
    if outcome ~= "miss" then stats.hits, stats.damage = stats.hits + 1, stats.damage + damage end
    if outcome == "critical" then stats.criticals = stats.criticals + 1 end
end
local function attack_line(stats, label)
    return string.format("%s %d hits %d criticals %d damage %d accuracy %s", label, stats.count, stats.hits, stats.criticals, stats.damage, dec_1(100 * stats.hits, stats.count))
end

local Game = {}
Game.__index = Game

function Game.new(settings, monster_types, item_types, commands)
    local self = setmetatable({config = settings, monster_types = monster_types, item_types = item_types, commands = commands,
        generation_rng = Minstd.new(settings.generation_seed), rng = Minstd.new(settings.game_seed), levels = {},
        turn = 1, messages = {}, map_lines = {}, succeeded = 0, failed = 0, unused = 0, moves = 0,
        player_attacks = attack_stats(), monster_attacks = attack_stats(), poison_damage = 0, starvation_damage = 0, usage = {}, kills = {}}, Game)
    for _, field in ipairs(usage_fields) do self.usage[field] = 0 end
    for _, kind in ipairs(monster_types) do self.kills[kind.name] = 0 end
    local generator = dungeon_gen.Generator.new(self.generation_rng, settings.min_size, settings.max_split, settings.room_min, settings.room_max)
    for depth = 1, settings.levels do
        local level = generator:generate(depth, settings.width, settings.height)
        local target = level.target
        if depth < settings.levels then level.terrain[target[2] + 1][target[1] + 1] = ">"
        else level.items[#level.items + 1] = entities.Item.new(entities.amulet_type(), target[1], target[2]) end
        self:place_monsters(level)
        self:place_items(level)
        self.levels[#self.levels + 1] = level
    end
    local start = self.levels[1].arrival
    self.player = {x = start[1], y = start[2], depth = 1, hp = settings.max_hp, max_hp = settings.max_hp,
        level = 1, xp = 0, gold = 0, satiation = settings.food_start, poison = 0, pack = {}}
    local types_by_name = {}
    for _, kind in ipairs(item_types) do types_by_name[kind.name] = kind end
    for _, name in ipairs(settings.start_items) do
        local item = entities.Item.new(types_by_name[name], start[1], start[2])
        self.player.pack[#self.player.pack + 1] = item
        if item.kind.category == "weapon" and self.player.weapon == nil then self.player.weapon = item end
        if item.kind.category == "armor" and self.player.armor == nil then self.player.armor = item end
    end
    return self
end

function Game:place_monsters(level)
    local count = self.config.monster_base + self.config.monster_step * (level.depth - 1)
    local candidates, weights = {}, {}
    for _, kind in ipairs(self.monster_types) do
        if kind.min_depth <= level.depth and level.depth <= kind.max_depth then candidates[#candidates + 1], weights[#weights + 1] = kind, kind.weight end
    end
    for number = 1, count do
        local kind = candidates[self.generation_rng:select(weights)]
        local room, x, y
        repeat room, x, y = level:draw_room_cell(self.generation_rng)
        until room ~= level.arrival_room and level.terrain[y + 1][x + 1] == "." and level:monster_at(x, y) == nil
        local hp = kind.hp:roll(self.generation_rng)
        local asleep = self.generation_rng:draw() % 100 < self.config.sleep_chance
        level.monsters[#level.monsters + 1] = entities.monster(number, kind, x, y, hp, asleep)
    end
    level.monsters_created = count
end

function Game:place_items(level)
    local count = self.config.item_base + self.config.item_step * (level.depth - 1)
    local candidates, weights = {}, {}
    for _, kind in ipairs(self.item_types) do
        if kind.min_depth <= level.depth and level.depth <= kind.max_depth then candidates[#candidates + 1], weights[#weights + 1] = kind, kind.weight end
    end
    for _ = 1, count do
        local kind = candidates[self.generation_rng:select(weights)]
        local room, x, y
        repeat room, x, y = level:draw_room_cell(self.generation_rng)
        until level.terrain[y + 1][x + 1] == "." and level:item_at(x, y) == nil
        local amount = kind.category == "gold" and kind.dice:roll(self.generation_rng) or 0
        level.items[#level.items + 1] = entities.Item.new(kind, x, y, amount)
    end
    level.items_placed = #level.items
end

function Game:current_level() return self.levels[self.player.depth] end
function Game:say(text) self.messages[#self.messages + 1] = string.format("%04d %s", self.turn, text) end
function Game:hunger_state()
    local food = self.player.satiation
    if food > self.config.food_hungry then return "normal" end
    if food > self.config.food_weak then return "hungry" end
    if food > 0 then return "weak" end
    return "starving"
end
function Game:finish(result, cause) self.result, self.cause = result, cause end
function Game:die(cause) self:say("You die.") self:finish("died", cause) end

function Game:update_view()
    local level, player = self:current_level(), self.player
    self.visible = fov.field_of_view(level, player.x, player.y, self.config.fov_radius)
    for y = 0, level.height - 1 do
        for x = 0, level.width - 1 do
            if self.visible[y + 1][x + 1] then
                local item = level:item_at(x, y)
                level.memory[y + 1][x + 1] = item and item:symbol() or level.terrain[y + 1][x + 1]
            end
        end
    end
    for _, monster in ipairs(level.monsters) do
        local seen = self.visible[monster.y + 1][monster.x + 1]
        if seen and not monster.was_visible then self:say("You see the " .. monster.kind.name .. ".") end
        monster.was_visible = seen
    end
end

function Game:run()
    self:update_view()
    for _, command in ipairs(self.commands) do
        if self.result then self.unused = self.unused + 1
        elseif not self:execute(command) then self.failed = self.failed + 1
        else
            self.succeeded = self.succeeded + 1
            if self.result == nil then self:advance_turn() end
        end
    end
    if self.result == nil then self:finish("alive", "commands_exhausted") end
end

function Game:advance_turn()
    self:update_view()
    self:monsters_act()
    if self.result then return end
    self:end_turn()
    if self.result then return end
    if self.config.checkpoints[self.turn] then self:write_checkpoint() end
    self.turn = self.turn + 1
end

function Game:execute(command)
    local name = command.name
    if name == "move" then
        for index, direction in ipairs(fov.direction_names) do
            if direction == command.argument then local move = fov.directions[index] return self:move(move[1], move[2]) end
        end
    elseif name == "wait" then return true
    elseif name == "pickup" then return self:pickup()
    elseif name == "descend" then return self:descend()
    else return self:use_item(name, tonumber(command.argument)) end
end

function Game:move(dx, dy)
    local level, player = self:current_level(), self.player
    local x, y = player.x + dx, player.y + dy
    if not fov.passable(level, x, y) then self:say("You bump into a wall.") return false end
    if not fov.can_move(level, player.x, player.y, dx, dy) then self:say("You cannot move diagonally through a door.") return false end
    local monster = level:monster_at(x, y)
    if monster then self:player_attack(level, monster) return true end
    player.x, player.y, self.moves = x, y, self.moves + 1
    local item = level:item_at(x, y)
    if item then self:say("You see " .. item:reference_name() .. " here.")
    elseif level.terrain[y + 1][x + 1] == ">" then self:say("There is a staircase down here.") end
    return true
end

function Game:pickup()
    local level, player = self:current_level(), self.player
    local item = level:item_at(player.x, player.y)
    if item == nil then self:say("There is nothing here.") return false end
    local category = item.kind.category
    if category == "gold" then player.gold = player.gold + item.amount self:say("You pick up " .. item:display_name() .. ".")
    elseif category == "amulet" then self:say("You pick up the amulet.") self:say("You win!") self:finish("won", "amulet")
    elseif #player.pack >= self.config.pack_limit then self:say("Your pack is full.") return false
    else player.pack[#player.pack + 1] = item self:say("You pick up the " .. item:display_name() .. " (" .. #player.pack .. ").") end
    remove_item(level.items, item)
    level.picked, self.usage.picked = level.picked + 1, self.usage.picked + 1
    return true
end

function Game:descend()
    local player = self.player
    if self:current_level().terrain[player.y + 1][player.x + 1] ~= ">" then self:say("There are no stairs here.") return false end
    player.depth = player.depth + 1
    local arrival = self:current_level().arrival
    player.x, player.y = arrival[1], arrival[2]
    self:say("You descend to depth " .. player.depth .. ".")
    return true
end

function Game:use_item(name, number)
    local player = self.player
    if number > #player.pack then self:say("You do not have that item.") return false end
    local item = player.pack[number]
    if item.kind.category ~= command_classes[name] then self:say("You cannot " .. name .. " that.") return false end
    if name == "quaff" then return self:quaff(item) end
    if name == "read" then return self:read(item) end
    if name == "wield" then
        if item == player.weapon then self:say("You are already wielding that.") return false end
        player.weapon, self.usage.wielded = item, self.usage.wielded + 1
        self:say("You are now wielding the " .. item:display_name() .. ".")
    elseif name == "wear" then
        if item == player.armor then self:say("You are already wearing that.") return false end
        player.armor, self.usage.worn = item, self.usage.worn + 1
        self:say("You are now wearing the " .. item:display_name() .. ".")
    else
        remove_item(player.pack, item)
        self.usage.eaten = self.usage.eaten + 1
        player.satiation = math.min(player.satiation + item.kind.nutrition, self.config.food_max)
        self:say("You eat the " .. item:display_name() .. ".")
    end
    return true
end

function Game:quaff(item)
    local player = self.player
    remove_item(player.pack, item)
    self.usage.quaffed = self.usage.quaffed + 1
    self:say("You quaff the " .. item:display_name() .. ".")
    if item.kind.effect == "heal" then
        player.hp = player.hp + item.kind.dice:roll(self.rng)
        if player.hp > player.max_hp then player.max_hp = player.max_hp + 1 player.hp = player.max_hp end
        player.poison = 0
        self:say("You feel better.")
    elseif item.kind.effect == "poison" then player.poison = player.poison + item.kind.poison_turns self:say("You feel very sick.")
    elseif item.kind.effect == "level" then
        self:say("You feel more experienced.")
        if player.level <= #self.config.xp_levels then self:gain_xp(self.config.xp_levels[player.level] - player.xp) end
    end
    return true
end

function Game:read(item)
    local level, player = self:current_level(), self.player
    remove_item(player.pack, item)
    self.usage.read = self.usage.read + 1
    self:say("You read the " .. item:display_name() .. ".")
    local effect = item.kind.effect
    if effect == "mapping" then
        for y = 1, level.height do for x = 1, level.width do
            if level.terrain[y][x] ~= " " and level.memory[y][x] == " " then level.memory[y][x] = level.terrain[y][x] end
        end end
        self:say("A map forms in your mind.")
    elseif effect == "teleport" then
        local room, x, y
        repeat room, x, y = level:draw_room_cell(self.rng)
        until (x ~= player.x or y ~= player.y) and level:monster_at(x, y) == nil
        player.x, player.y = x, y
        self:say("You are teleported.")
    elseif effect == "enchant_weapon" then
        if player.weapon then self:say("Your " .. player.weapon:display_name() .. " glows blue.") player.weapon.bonus = player.weapon.bonus + 1
        else self:say("Your hands twitch.") end
    elseif effect == "enchant_armor" then
        if player.armor then self:say("Your " .. player.armor:display_name() .. " glows silver.") player.armor.bonus = player.armor.bonus + 1
        else self:say("Your skin tingles.") end
    end
    return true
end

function Game:player_attack(level, monster)
    local player, weapon = self.player, self.player.weapon
    monster.asleep = false
    local to_hit, dice, bonus = player.level, unarmed_damage, 0
    if weapon then to_hit, dice, bonus = player.level + weapon.kind.to_hit + weapon.bonus, weapon.kind.dice, weapon.bonus end
    local hunger = self:hunger_state()
    if hunger == "weak" or hunger == "starving" then to_hit = to_hit - 2 end
    local name = monster.kind.name
    local outcome, damage = combat.resolve_attack(self.rng, to_hit, monster.kind.defense, dice, bonus)
    record_attack(self.player_attacks, outcome, damage)
    if outcome == "miss" then self:say("You miss the " .. name .. ".") return end
    self:say("You hit the " .. name .. (outcome == "critical" and " hard" or "") .. " for " .. damage .. ".")
    monster.hp = monster.hp - damage
    if monster.hp <= 0 then
        self:say("You kill the " .. name .. ".")
        remove_item(level.monsters, monster)
        level.kills, self.kills[name] = level.kills + 1, self.kills[name] + 1
        self:gain_xp(monster.kind.xp)
    end
end

function Game:gain_xp(amount)
    local player, thresholds = self.player, self.config.xp_levels
    player.xp = player.xp + amount
    while player.level <= #thresholds and player.xp >= thresholds[player.level] do
        player.level = player.level + 1
        local gained = self.config.hit_die:roll(self.rng)
        player.max_hp, player.hp = player.max_hp + gained, player.hp + gained
        self:say("Welcome to level " .. player.level .. ".")
    end
end

function Game:monster_attack(monster)
    local player, kind = self.player, monster.kind
    local outcome, damage = combat.resolve_attack(self.rng, kind.to_hit, defense(player), kind.damage, 0)
    record_attack(self.monster_attacks, outcome, damage)
    if outcome == "miss" then self:say("The " .. kind.name .. " misses you.") return end
    self:say("The " .. kind.name .. " hits you" .. (outcome == "critical" and " hard" or "") .. " for " .. damage .. ".")
    player.hp = player.hp - damage
    if player.hp <= 0 then self:die("killed_by " .. kind.name)
    elseif kind.poisonous then player.poison = player.poison + 5 self:say("You are poisoned.") end
end

function Game:monsters_act()
    local level, player = self:current_level(), self.player
    self.distance = fov.distances(level, player.x, player.y)
    for _, monster in ipairs(level.monsters) do
        monster.energy = monster.energy + monster.kind.speed
        while monster.energy >= 2 do
            monster.energy = monster.energy - 2
            self:monster_action(level, monster)
            if self.result then return end
        end
    end
end

function Game:monster_action(level, monster)
    local sees = self.visible[monster.y + 1][monster.x + 1]
    if monster.asleep then
        if sees and self.rng:draw() % 100 < self.config.wake_chance then monster.asleep = false self:say("The " .. monster.kind.name .. " wakes up.") end
    elseif monster.kind.stationary then
        if self:can_attack(level, monster) then self:monster_attack(monster) end
    elseif monster.kind.erratic and self.rng:draw() % 2 == 0 then self:wander(level, monster)
    elseif sees then self:chase(level, monster)
    else self:wander(level, monster) end
end

function Game:can_attack(level, monster)
    local dx, dy = self.player.x - monster.x, self.player.y - monster.y
    return math.max(math.abs(dx), math.abs(dy)) == 1 and fov.can_move(level, monster.x, monster.y, dx, dy)
end

function Game:wander(level, monster)
    local move = fov.directions[self.rng:draw() % 8 + 1]
    local dx, dy = move[1], move[2]
    if not fov.can_move(level, monster.x, monster.y, dx, dy) then return end
    local x, y = monster.x + dx, monster.y + dy
    if x == self.player.x and y == self.player.y then self:monster_attack(monster)
    elseif level:monster_at(x, y) == nil then monster.x, monster.y = x, y end
end

function Game:chase(level, monster)
    if self:can_attack(level, monster) then self:monster_attack(monster) return end
    local here, best, best_distance = self.distance[monster.y + 1][monster.x + 1], nil, nil
    for _, move in ipairs(fov.directions) do
        local dx, dy = move[1], move[2]
        if fov.can_move(level, monster.x, monster.y, dx, dy) then
            local x, y = monster.x + dx, monster.y + dy
            local distance = self.distance[y + 1][x + 1]
            if distance >= 0 and (here < 0 or distance < here) and level:monster_at(x, y) == nil and (x ~= self.player.x or y ~= self.player.y) then
                if best == nil or distance < best_distance then best, best_distance = {x, y}, distance end
            end
        end
    end
    if best then monster.x, monster.y = best[1], best[2] end
end

function Game:end_turn()
    local level, player = self:current_level(), self.player
    for _, monster in ipairs(level.monsters) do
        if monster.kind.regenerates and monster.hp < monster.max_hp then monster.hp = monster.hp + 1 end
    end
    if player.poison > 0 then
        player.hp, self.poison_damage = player.hp - 1, self.poison_damage + 1
        if player.hp <= 0 then self:die("poison") return end
        player.poison = player.poison - 1
        if player.poison == 0 then self:say("You feel less sick.") end
    end
    if player.satiation == 0 then
        player.hp, self.starvation_damage = player.hp - 1, self.starvation_damage + 1
        if player.hp <= 0 then self:die("starvation") return end
    else
        local before = self:hunger_state()
        player.satiation = player.satiation - 1
        local after = self:hunger_state()
        if after ~= before then self:say(hunger_messages[after]) end
    end
    if self.turn % self.config.regen_interval == 0 and player.poison == 0 and player.satiation > 0 and player.hp < player.max_hp then player.hp = player.hp + 1 end
end

function Game:view_symbol(level, x, y)
    if x == self.player.x and y == self.player.y then return "@" end
    local monster = level:monster_at(x, y)
    if monster then return monster.kind.symbol end
    local item = level:item_at(x, y)
    return item and item:symbol() or level.terrain[y + 1][x + 1]
end

function Game:map_rows(level, current)
    local border = "+" .. string.rep("-", level.width) .. "+"
    local rows = {border}
    for y = 0, level.height - 1 do
        local symbols = {}
        for x = 0, level.width - 1 do
            symbols[#symbols + 1] = current and self.visible[y + 1][x + 1] and self:view_symbol(level, x, y) or level.memory[y + 1][x + 1]
        end
        rows[#rows + 1] = "|" .. table.concat(symbols) .. "|"
    end
    rows[#rows + 1] = border
    return rows
end

function Game:status_line()
    local p = self.player
    return string.format("STATUS hp %d/%d level %d xp %d defense %d gold %d food %d %s poison %d", p.hp, p.max_hp, p.level, p.xp, defense(p), p.gold, p.satiation, self:hunger_state(), p.poison)
end

function Game:write_checkpoint()
    self.map_lines[#self.map_lines + 1] = "CHECKPOINT turn " .. self.turn .. " depth " .. self.player.depth
    extend(self.map_lines, self:map_rows(self:current_level(), true))
    self.map_lines[#self.map_lines + 1] = self:status_line()
end

function Game:final_block()
    local depth = self.player.depth
    local lines = {"FINAL turn " .. self.succeeded .. " depth " .. depth}
    for index = 1, depth do
        local level = self.levels[index]
        local explored, total = exploration(level)
        lines[#lines + 1] = "LEVEL " .. level.depth .. " explored " .. explored .. "/" .. total
        extend(lines, self:map_rows(level, index == depth))
    end
    lines[#lines + 1] = self:status_line()
    return lines
end

function Game:stats_lines()
    local p = self.player
    local lines = {"result " .. self.result, "cause " .. self.cause, "turns " .. self.succeeded, "depth " .. p.depth,
        "level " .. p.level, "xp " .. p.xp, "hp " .. p.hp .. "/" .. p.max_hp, "defense " .. defense(p), "gold " .. p.gold,
        "food " .. p.satiation .. " " .. self:hunger_state(), "poison " .. p.poison,
        "weapon " .. (p.weapon and p.weapon:display_name() or "-"), "armor " .. (p.armor and p.armor:display_name() or "-"),
        string.format("commands %d executed %d failed %d unused %d", #self.commands, self.succeeded, self.failed, self.unused), "moves " .. self.moves,
        attack_line(self.player_attacks, "player_attacks"), attack_line(self.monster_attacks, "monster_attacks"),
        "poison_damage " .. self.poison_damage .. " starvation_damage " .. self.starvation_damage}
    local usage = {}
    for _, field in ipairs(usage_fields) do usage[#usage + 1] = field .. " " .. self.usage[field] end
    lines[#lines + 1] = table.concat(usage, " ")
    local kills = 0
    for _, value in pairs(self.kills) do kills = kills + value end
    lines[#lines + 1] = "kills " .. kills
    for _, kind in ipairs(self.monster_types) do if self.kills[kind.name] > 0 then lines[#lines + 1] = "KILL " .. kind.name .. " " .. self.kills[kind.name] end end
    for _, level in ipairs(self.levels) do
        local explored, total = exploration(level)
        lines[#lines + 1] = string.format("LEVEL %d rooms %d explored %d/%d %s monsters %d/%d items %d/%d", level.depth, #level.rooms,
            explored, total, dec_1(100 * explored, total), level.kills, level.monsters_created, level.picked, level.items_placed)
    end
    for number, item in ipairs(p.pack) do
        local suffix = item == p.weapon and " (wielded)" or item == p.armor and " (worn)" or ""
        lines[#lines + 1] = "INVENTORY " .. number .. " " .. item:display_name() .. suffix
    end
    return lines
end

local function write_lines(name, lines)
    local file = assert(io.open("output/" .. name, "w"))
    for _, line in ipairs(lines) do file:write(line, "\n") end
    file:close()
end

local function main()
    local settings, monster_types, item_types = config(read_rows("config.txt")), {}, {}
    for _, row in ipairs(read_rows("monsters.txt")) do monster_types[#monster_types + 1] = entities.monster_type(row) end
    for _, row in ipairs(read_rows("items.txt")) do item_types[#item_types + 1] = entities.parse_item_type(row) end
    local game = Game.new(settings, monster_types, item_types, expand_commands(read_rows("commands.txt")))
    game:run()
    os.execute("mkdir -p output")
    write_lines("messages.txt", game.messages)
    extend(game.map_lines, game:final_block())
    write_lines("maps.txt", game.map_lines)
    write_lines("stats.txt", game:stats_lines())
end

main()
