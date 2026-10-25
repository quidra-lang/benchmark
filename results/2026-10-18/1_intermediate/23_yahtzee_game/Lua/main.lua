local categories = {"ONES", "TWOS", "THREES", "FOURS", "FIVES", "SIXES", "THREEKIND", "FOURKIND", "FULLHOUSE", "SMALL", "LARGE", "YAHTZEE", "CHANCE"}
local category_index = {}
for i, category in ipairs(categories) do category_index[category] = i end
local strategies = {KIND = true, STRAIGHT = true, HIGH = true, UPPER = true}
local jokers = {FORCED = true, FREE = true, OFF = true}
local powers = {1, 6, 36, 216, 1296, 7776}
local lower_mask = 0x1fc0

local function fail(format, ...) error({message = string.format(format, ...)}, 0) end

local function positive(word, maximum)
    if not word:match("^[1-9][0-9]*$") then fail("bad value %s", word) end
    local value = tonumber(word, 10)
    if value > maximum then fail("bad value %s", word) end
    return value
end

local function check_name(word)
    if #word > 8 or not word:match("^[A-Z]+$") then fail("bad name %s", word) end
end

local function parse_pattern(word)
    if #word ~= 5 or word:find("[^01]") then fail("bad pattern %s", word) end
    return tonumber(word, 2)
end

local function parse_category(word)
    if not category_index[word] then fail("bad category %s", word) end
    return category_index[word]
end

local function parse_strategy(word)
    if not strategies[word] then fail("bad strategy %s", word) end
    return word
end

local function ascii_less(a, b)
    for i = 1, math.min(#a, #b) do
        local first, second = a:byte(i), b:byte(i)
        if first ~= second then return first < second end
    end
    return #a < #b
end

local function fraction(numerator, denominator)
    local a, b = numerator, denominator
    while b ~= 0 do a, b = b, a % b end
    numerator, denominator = numerator // a, denominator // a
    return denominator == 1 and tostring(numerator) or string.format("%d/%d", numerator, denominator)
end

local function average(sum, count)
    local value = count == 0 and 0 or 100 * sum // count
    return string.format("%d.%02d", value // 100, value % 100)
end

local function held(mask, die) return (mask & (1 << (5 - die))) ~= 0 end

local function pattern_text(mask)
    local text = {}
    for i = 1, 5 do text[i] = held(mask, i) and "1" or "0" end
    return table.concat(text)
end

local function faces_text(faces, mask)
    local selected = {}
    if faces then
        for i = 1, 5 do if held(mask or 31, i) then selected[#selected + 1] = tostring(faces[i]) end end
    end
    return #selected == 0 and "-" or table.concat(selected, " ")
end

local function face_counts(faces)
    local counts = {0, 0, 0, 0, 0, 0}
    for _, face in ipairs(faces) do counts[face] = counts[face] + 1 end
    return counts
end

local function decode(code)
    local counts = {}
    for i = 1, 6 do counts[i], code = code % 6, code // 6 end
    return counts
end

local function held_code(faces, mask)
    local code = 0
    for i = 1, 5 do if held(mask, i) then code = code + powers[faces[i]] end end
    return code
end

local function frequent(counts)
    local face = 1
    for i = 2, 6 do if counts[i] >= counts[face] then face = i end end
    return face
end

local function yahtzee(counts)
    for _, count in ipairs(counts) do if count == 5 then return true end end
    return false
end

local function normal_score(category, counts)
    if category <= 6 then return category * counts[category] end
    local total, largest, bits, pair, triple = 0, 0, 0, false, false
    for face, count in ipairs(counts) do
        total = total + face * count
        largest = math.max(largest, count)
        if count > 0 then bits = bits | (1 << (face - 1)) end
        pair, triple = pair or count == 2, triple or count == 3
    end
    if category == 7 then return largest >= 3 and total or 0
    elseif category == 8 then return largest >= 4 and total or 0
    elseif category == 9 then return pair and triple and 25 or 0
    elseif category == 10 then return ((bits & 15) == 15 or (bits & 30) == 30 or (bits & 60) == 60) and 30 or 0
    elseif category == 11 then return (bits == 31 or bits == 62) and 40 or 0
    elseif category == 12 then return largest == 5 and 50 or 0
    else return total end
end

local Player = {}
Player.__index = Player
function Player.new(name) return setmetatable({name = name, strategy = "KIND", scores = {}, yahtzee_bonus = 0}, Player) end
function Player:upper()
    local sum = 0
    for c = 1, 6 do sum = sum + (self.scores[c] or 0) end
    return sum
end
function Player:upper_bonus() return self:upper() >= 63 and 35 or 0 end
function Player:total()
    local sum = self:upper_bonus() + self.yahtzee_bonus
    for c = 1, 13 do sum = sum + (self.scores[c] or 0) end
    return sum
end
function Player:round()
    local round = 1
    for c = 1, 13 do if self.scores[c] ~= nil then round = round + 1 end end
    return round
end

local function evaluate(player, counts, rule)
    local allowed = 0
    for c = 1, 13 do if player.scores[c] == nil then allowed = allowed | (1 << (c - 1)) end end
    local joker = rule ~= "OFF" and yahtzee(counts) and player.scores[12] ~= nil
    if joker and rule == "FORCED" then
        local upper = frequent(counts)
        if (allowed & (1 << (upper - 1))) ~= 0 then allowed = 1 << (upper - 1)
        elseif (allowed & lower_mask) ~= 0 then allowed = allowed & lower_mask end
    end
    local points, best = {}, nil
    for c = 1, 13 do
        points[c] = -1
        if player.scores[c] == nil then
            if (allowed & (1 << (c - 1))) == 0 then points[c] = 0
            elseif joker and c >= 9 and c <= 11 then points[c] = ({25, 30, 40})[c - 8]
            else points[c] = normal_score(c, counts) end
            if not best or points[c] > points[best] then best = c end
        end
    end
    return {points = points, allowed = allowed, joker = joker, best = best}
end

local function make_outcomes()
    local result, factorial = {}, {1, 1, 2, 6, 24, 120}
    for size = 0, 5 do
        result[size] = {}
        local function add(face, remaining, code, divisor)
            if face == 7 then
                if remaining == 0 then
                    local list = result[size]
                    list[#list + 1] = {code = code, weight = factorial[size + 1] // divisor}
                end
                return
            end
            for count = 0, remaining do add(face + 1, remaining - count, code + count * powers[face], divisor * factorial[count + 1]) end
        end
        add(1, size, 0, 1)
    end
    return result
end
local outcomes = make_outcomes()

local function new_turn(seat) return {seat = seat or 1, rolls = 0, hold = 0} end
local Game = {}
Game.__index = Game
function Game.new(seed, names, rolls, joker, output)
    local players = {}
    for i, name in ipairs(names) do players[i] = Player.new(name) end
    return setmetatable({random_state = seed, players = players, max_rolls = rolls, joker = joker, output = output,
        loaded = {}, loaded_head = 1, face_totals = {0, 0, 0, 0, 0, 0}, entries = {}, redo_list = {}, turn = new_turn()}, Game)
end
function Game:emit(format, ...) if self.output then self.output(string.format(format, ...)) end end
function Game:current() return self.players[self.turn.seat] end
function Game:check_turn() if not self.turn then fail("game over") end end
function Game:check_rolled()
    self:check_turn()
    if self.turn.rolls == 0 then fail("not rolled") end
end
function Game:check_rolls_left()
    self:check_rolled()
    if self.turn.rolls == self.max_rolls then fail("no rolls left") end
end
function Game:roll()
    self:check_turn()
    local turn = self.turn
    if turn.rolls == self.max_rolls then fail("no rolls left") end
    if turn.hold == 31 then fail("all dice held") end
    self.redo_list = {}
    local faces = {}
    for i = 1, 5 do
        if turn.rolls > 0 and held(turn.hold, i) then faces[i] = turn.faces[i]
        else
            if self.loaded_head <= #self.loaded then
                faces[i] = self.loaded[self.loaded_head]
                self.loaded_head = self.loaded_head + 1
            else
                self.random_state = 48271 * self.random_state % 2147483647
                faces[i] = self.random_state % 6 + 1
            end
            self.face_totals[faces[i]] = self.face_totals[faces[i]] + 1
        end
    end
    self.turn = {seat = turn.seat, rolls = turn.rolls + 1, faces = faces, hold = turn.hold}
    self:emit("%s roll %d: %s", self:current().name, self.turn.rolls, faces_text(faces))
end
function Game:hold(mask)
    self:check_rolls_left()
    self.redo_list = {}
    local turn = self.turn
    self.turn = {seat = turn.seat, rolls = turn.rolls, faces = turn.faces, hold = mask}
    self:emit("%s holds %s: %s", self:current().name, pattern_text(mask), faces_text(turn.faces, mask))
end
function Game:keep(values)
    self:check_rolls_left()
    local mask = 0
    for _, value in ipairs(values) do
        local die
        for i = 1, 5 do if not held(mask, i) and self.turn.faces[i] == value then die = i; break end end
        if not die then fail("not showing %d", value) end
        mask = mask | (1 << (5 - die))
    end
    self:hold(mask)
end
function Game:score(category, preview)
    self:check_rolled()
    local player = self:current()
    if player.scores[category] ~= nil then fail("%s already used", categories[category]) end
    local counts = face_counts(self.turn.faces)
    local candidates = evaluate(player, counts, self.joker)
    if (candidates.allowed & (1 << (category - 1))) == 0 then
        local upper = frequent(counts)
        fail("joker requires %s", player.scores[upper] == nil and categories[upper] or "lower box")
    end
    local points = candidates.points[category]
    local bonus = yahtzee(counts) and player.scores[12] == 50 and 100 or 0
    local upper_bonus = category <= 6 and player:upper() < 63 and player:upper() + points >= 63 and 35 or 0
    local line = string.format("%s %s %d in %s", player.name, preview and "would score" or "scores", points, categories[category])
    if candidates.joker then line = line .. " joker" end
    if bonus ~= 0 then line = line .. " ybonus 100" end
    if upper_bonus ~= 0 then line = line .. " ubonus 35" end
    line = line .. string.format(" total %d", player:total() + points + bonus + upper_bonus)
    if preview then self:emit("%s", line); return end
    self.redo_list = {}
    local entry = {before = self.turn, category = category, points = points, bonus = bonus, joker = candidates.joker}
    self.entries[#self.entries + 1] = entry
    player.scores[category] = points
    player.yahtzee_bonus = player.yahtzee_bonus + bonus
    if #self.entries == 13 * #self.players then self.turn = nil
    else self.turn = new_turn(entry.before.seat % #self.players + 1) end
    self:emit("%s", line)
    if self.turn then self:emit("turn %d %s", self:current():round(), self:current().name)
    else self:emit("game over") end
end
function Game:undo()
    if #self.entries == 0 then fail("nothing to undo") end
    local entry = table.remove(self.entries)
    self.redo_list[#self.redo_list + 1] = {after = self.turn, entry = entry}
    local player = self.players[entry.before.seat]
    player.scores[entry.category] = nil
    player.yahtzee_bonus = player.yahtzee_bonus - entry.bonus
    self.turn = entry.before
    self:emit("undo %s %s %d", player.name, categories[entry.category], entry.points)
end
function Game:redo()
    if #self.redo_list == 0 then fail("nothing to redo") end
    local saved = table.remove(self.redo_list)
    local entry = saved.entry
    local player = self.players[entry.before.seat]
    player.scores[entry.category] = entry.points
    player.yahtzee_bonus = player.yahtzee_bonus + entry.bonus
    self.entries[#self.entries + 1] = entry
    self.turn = saved.after
    self:emit("redo %s %s %d", player.name, categories[entry.category], entry.points)
end
function Game:bot_hold(strategy)
    local faces, counts = self.turn.faces, face_counts(self.turn.faces)
    local target, mask = frequent(counts), 0
    if strategy == "STRAIGHT" then
        local best_start, best_length = 1, 0
        for start = 1, 6 do
            local last = start
            while last <= 6 and counts[last] > 0 do last = last + 1 end
            if last - start >= best_length then best_start, best_length = start, last - start end
        end
        if best_length >= 3 then
            for face = best_start, best_start + best_length - 1 do
                for i = 1, 5 do if faces[i] == face then mask = mask | (1 << (5 - i)); break end end
            end
            return mask
        end
    end
    for i = 1, 5 do
        local keep = strategy == "HIGH" and faces[i] >= 5 or strategy ~= "HIGH" and faces[i] == target
        if keep then mask = mask | (1 << (5 - i)) end
    end
    return mask
end
function Game:bot_turn()
    local strategy = self:current().strategy
    if self.turn.rolls == 0 then self:roll() end
    while self.turn.rolls < self.max_rolls do
        local mask = self:bot_hold(strategy)
        if mask == 31 then break end
        self:hold(mask)
        self:roll()
    end
    local counts = face_counts(self.turn.faces)
    local candidates = evaluate(self:current(), counts, self.joker)
    local target = frequent(counts)
    local category = strategy == "UPPER" and counts[target] >= 3 and (candidates.allowed & (1 << (target - 1))) ~= 0 and target or candidates.best
    self:score(category, false)
end
function Game:ranking()
    local seats = {}
    for i = 1, #self.players do seats[i] = i end
    table.sort(seats, function(a, b)
        local first, second = self.players[a]:total(), self.players[b]:total()
        if first ~= second then return first > second end
        return a < b
    end)
    return seats
end

local Adviser = {}
Adviser.__index = Adviser
function Adviser.new(player, joker) return setmetatable({player = player, joker = joker, values = {}, expectations = {}}, Adviser) end
function Adviser:value(code, depth)
    local key = depth * 46656 + code
    if self.values[key] ~= nil then return self.values[key] end
    local counts, best = decode(code), -1
    if depth == 0 then
        local candidates = evaluate(self.player, counts, self.joker)
        best = candidates.points[candidates.best]
    else best = self:choose(counts, depth, 1, 0) end
    self.values[key] = best
    return best
end
function Adviser:choose(counts, depth, face, kept)
    if face == 7 then return self:expected(kept, depth) end
    local best = -1
    for count = 0, counts[face] do best = math.max(best, self:choose(counts, depth, face + 1, kept + count * powers[face])) end
    return best
end
function Adviser:expected(kept, depth)
    local key = depth * 46656 + kept
    if self.expectations[key] ~= nil then return self.expectations[key] end
    local rerolled, sum = 5, 0
    for _, count in ipairs(decode(kept)) do rerolled = rerolled - count end
    for _, outcome in ipairs(outcomes[rerolled]) do sum = sum + outcome.weight * self:value(kept + outcome.code, depth - 1) end
    local result = sum * powers[6 - rerolled]
    self.expectations[key] = result
    return result
end

local Program = {}
Program.__index = Program
function Program.new() return setmetatable({rolls = 3, joker = "FORCED", records = {}, output = {}}, Program) end
function Program:emit(format, ...) self.output[#self.output + 1] = string.format(format, ...) end
function Program:table() if not self.game then fail("no game") end; return self.game end
function Program:odds(game, mask)
    game:check_rolls_left()
    local kept = held_code(game.turn.faces, mask)
    local rerolled = 5
    for _, count in ipairs(decode(kept)) do rerolled = rerolled - count end
    local count, sums, chances, best = powers[rerolled + 1], {}, {}, 0
    for c = 1, 13 do sums[c], chances[c] = 0, 0 end
    for _, outcome in ipairs(outcomes[rerolled]) do
        local candidates = evaluate(game:current(), decode(kept + outcome.code), game.joker)
        for c = 1, 13 do
            if candidates.points[c] >= 0 then
                sums[c] = sums[c] + outcome.weight * candidates.points[c]
                if candidates.points[c] > 0 then chances[c] = chances[c] + outcome.weight end
            end
        end
        best = best + outcome.weight * candidates.points[candidates.best]
    end
    self:emit("odds %s outcomes %d", pattern_text(mask), count)
    for c = 1, 13 do
        if game:current().scores[c] == nil then self:emit("%s expect %s chance %s", categories[c], fraction(sums[c], count), fraction(chances[c], count)) end
    end
    self:emit("best expect %s", fraction(best, count))
end
function Program:advise(game)
    game:check_rolls_left()
    local depth = game.max_rolls - game.turn.rolls
    local chosen, best, denominator = 0, -1, 1
    for _ = 1, depth do denominator = denominator * 7776 end
    local adviser = Adviser.new(game:current(), game.joker)
    for mask = 0, 31 do
        local value = adviser:expected(held_code(game.turn.faces, mask), depth)
        if value > best then best, chosen = value, mask end
    end
    self:emit("advise %s: %s expect %s", pattern_text(chosen), faces_text(game.turn.faces, chosen), fraction(best, denominator))
end
function Program:card(game)
    local function row(heading, cell)
        local line = string.format("%-9s", heading)
        for _, player in ipairs(game.players) do line = line .. string.format(" %" .. math.max(4, #player.name) .. "s", cell(player)) end
        self:emit("%s", line)
    end
    row("CATEGORY", function(player) return player.name end)
    for c = 1, 13 do row(categories[c], function(player) return player.scores[c] ~= nil and tostring(player.scores[c]) or "-" end) end
    row("UPPER", function(player) return tostring(player:upper()) end)
    row("BONUS", function(player) return tostring(player:upper_bonus()) end)
    row("YBONUS", function(player) return tostring(player.yahtzee_bonus) end)
    row("TOTAL", function(player) return tostring(player:total()) end)
end
function Program:simulate(seed, count, bots)
    local names, totals = {}, {}
    for i = 1, #bots do names[i], totals[i] = string.char(64 + i), {wins = 0, sum = 0, best = 0, bonus = 0, yahtzee = 0} end
    local state = seed
    for _ = 1, count do
        local game = Game.new(state, names, self.rolls, self.joker)
        for i, strategy in ipairs(bots) do game.players[i].strategy = strategy end
        while game.turn do game:bot_turn() end
        state = game.random_state
        local winner = game:ranking()[1]
        totals[winner].wins = totals[winner].wins + 1
        for i, player in ipairs(game.players) do
            local total = totals[i]
            total.sum, total.best = total.sum + player:total(), math.max(total.best, player:total())
            if player:upper_bonus() == 35 then total.bonus = total.bonus + 1 end
            if player.scores[12] == 50 then total.yahtzee = total.yahtzee + 1 end
        end
    end
    self:emit("sim seed %d games %d players %d", seed, count, #bots)
    for i, strategy in ipairs(bots) do
        local total = totals[i]
        self:emit("seat %d %s wins %d average %s best %d bonus %d yahtzee %d", i, strategy, total.wins, average(total.sum, count), total.best, total.bonus, total.yahtzee)
    end
end
function Program:execute(words)
    local command = words[1]
    if command == "RULE" then
        if words[2] ~= "ROLLS" and words[2] ~= "JOKER" then fail("unknown rule %s", words[2]) end
        local rolls, joker = self.rolls, self.joker
        if words[2] == "ROLLS" then rolls = positive(words[3], 4)
        elseif not jokers[words[3]] then fail("bad value %s", words[3])
        else joker = words[3] end
        if self.game then fail("game in progress") end
        self.rolls, self.joker = rolls, joker
        self:emit("rule %s %s", words[2], words[3])
    elseif command == "GAME" then
        local seed = positive(words[2], 2147483646)
        local names = {}
        for i = 3, #words do check_name(words[i]); names[#names + 1] = words[i] end
        if #names > 6 then fail("too many players") end
        if self.game then fail("game in progress") end
        local seen = {}
        for _, name in ipairs(names) do if seen[name] then fail("duplicate name %s", name) end; seen[name] = true end
        self.game = Game.new(seed, names, self.rolls, self.joker, function(line) self.output[#self.output + 1] = line end)
        self:emit("game seed %d players %s", seed, table.concat(names, " "))
        self:emit("turn 1 %s", names[1])
    elseif command == "BOT" then
        check_name(words[2])
        local strategy = parse_strategy(words[3])
        local game, selected = self:table(), nil
        for _, player in ipairs(game.players) do if player.name == words[2] then selected = player; break end end
        if not selected then fail("no player %s", words[2]) end
        selected.strategy = strategy
        self:emit("bot %s %s", words[2], words[3])
    elseif command == "LOAD" or command == "KEEP" then
        local values = {}
        for i = 2, #words do values[#values + 1] = positive(words[i], 6) end
        local game = self:table()
        if command == "KEEP" then game:keep(values)
        else
            for _, value in ipairs(values) do game.loaded[#game.loaded + 1] = value end
            self:emit("loaded %d", #game.loaded - game.loaded_head + 1)
        end
    elseif command == "ROLL" then self:table():roll()
    elseif command == "HOLD" or command == "ODDS" then
        local mask = parse_pattern(words[2])
        local game = self:table()
        if command == "HOLD" then game:hold(mask) else self:odds(game, mask) end
    elseif command == "SCORE" or command == "WHATIF" then
        local category = parse_category(words[2])
        self:table():score(category, command == "WHATIF")
    elseif command == "UNDO" then self:table():undo()
    elseif command == "REDO" then self:table():redo()
    elseif command == "SUGGEST" then
        local game = self:table()
        game:check_rolled()
        local candidates = evaluate(game:current(), face_counts(game.turn.faces), game.joker)
        local line = "suggest"
        for c = 1, 13 do if candidates.points[c] >= 0 then line = line .. string.format(" %s %d", categories[c], candidates.points[c]) end end
        self:emit("%s best %s %d", line, categories[candidates.best], candidates.points[candidates.best])
    elseif command == "ADVISE" then self:advise(self:table())
    elseif command == "AUTO" then
        local count = positive(words[2], 100)
        local game = self:table()
        game:check_turn()
        game.redo_list = {}
        for _ = 1, count do if not game.turn then break end; game:bot_turn() end
    elseif command == "STATUS" then
        local game = self:table()
        local turn = game.turn
        if not turn then self:emit("status game over")
        else self:emit("status round %d player %s rolls %d dice %s holds %s", game:current():round(), game:current().name, turn.rolls, faces_text(turn.faces), pattern_text(turn.hold)) end
    elseif command == "CARD" then self:card(self:table())
    elseif command == "BONUS" then
        for _, player in ipairs(self:table().players) do
            local upper, maximum = player:upper(), player:upper()
            for c = 1, 6 do if player.scores[c] == nil then maximum = maximum + 5 * c end end
            local status = upper >= 63 and "made" or maximum < 63 and "lost" or "open"
            self:emit("bonus %s upper %d need %d max %d %s", player.name, upper, math.max(63 - upper, 0), maximum, status)
        end
    elseif command == "STATS" then
        local game = self:table()
        for seat, player in ipairs(game.players) do
            local turns, rolls, zeros, yahtzees, sum = 0, 0, 0, 0, 0
            for _, entry in ipairs(game.entries) do
                if entry.before.seat == seat then
                    turns, rolls, sum = turns + 1, rolls + entry.before.rolls, sum + entry.points
                    if entry.points == 0 then zeros = zeros + 1 end
                    if yahtzee(face_counts(entry.before.faces)) then yahtzees = yahtzees + 1 end
                end
            end
            self:emit("stats %s turns %d rolls %d zeros %d yahtzees %d average %s", player.name, turns, rolls, zeros, yahtzees, average(sum, turns))
        end
    elseif command == "LOG" then
        local game = self:table()
        for i, entry in ipairs(game.entries) do
            self:emit("log %d %s %s %s %d%s%s", i, game.players[entry.before.seat].name, faces_text(entry.before.faces), categories[entry.category], entry.points,
                entry.joker and " joker" or "", entry.bonus ~= 0 and " ybonus 100" or "")
        end
        if #game.entries == 0 then self:emit("no scores") end
    elseif command == "FACES" then
        local game = self:table()
        local total, squares = 0, 0
        for _, count in ipairs(game.face_totals) do total, squares = total + count, squares + count * count end
        self:emit("faces %s total %d chi2 %s", table.concat(game.face_totals, " "), total, fraction(6 * squares - total * total, total == 0 and 1 or total))
    elseif command == "STANDINGS" or command == "END" then
        local game = self:table()
        local ranking, ending = game:ranking(), command == "END"
        if ending then self:emit("end %s", game.turn and "abandoned" or "final") end
        for rank, seat in ipairs(ranking) do
            local player = game.players[seat]
            if not ending then self:emit("standing %d %s %d behind %d", rank, player.name, player:total(), game.players[ranking[1]]:total() - player:total())
            else
                self:emit("rank %d %s %d", rank, player.name, player:total())
                if not game.turn then
                    local record = self.records[player.name] or {games = 0, wins = 0, best = 0, sum = 0}
                    record.games, record.sum, record.best = record.games + 1, record.sum + player:total(), math.max(record.best, player:total())
                    if rank == 1 then record.wins = record.wins + 1 end
                    self.records[player.name] = record
                end
            end
        end
        if ending then self.game = nil end
    elseif command == "RECORDS" then
        local names = {}
        for name in pairs(self.records) do names[#names + 1] = name end
        table.sort(names, function(a, b)
            local first, second = self.records[a], self.records[b]
            if first.wins ~= second.wins then return first.wins > second.wins end
            if first.best ~= second.best then return first.best > second.best end
            return ascii_less(a, b)
        end)
        for _, name in ipairs(names) do
            local record = self.records[name]
            self:emit("record %s games %d wins %d best %d average %s", name, record.games, record.wins, record.best, average(record.sum, record.games))
        end
        if #names == 0 then self:emit("no records") end
    elseif command == "SIM" then
        local seed = positive(words[2], 2147483646)
        local count = positive(words[3], 50)
        local bots = {}
        for i = 4, #words do bots[#bots + 1] = parse_strategy(words[i]) end
        if #bots > 6 then fail("too many players") end
        self:simulate(seed, count, bots)
    else fail("unknown command %s", command) end
end

local count = tonumber(io.read("l"), 10)
local program = Program.new()
for _ = 1, count do
    local words = {}
    for word in io.read("l"):gmatch("%S+") do words[#words + 1] = word end
    local ok, problem = pcall(program.execute, program, words)
    if not ok then
        if type(problem) ~= "table" or not problem.message then error(problem, 0) end
        program:emit("error: %s", problem.message)
    end
end
if #program.output > 0 then io.write(table.concat(program.output, "\n"), "\n") end
