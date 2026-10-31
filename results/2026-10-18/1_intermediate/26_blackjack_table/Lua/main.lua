local function set(words)
    local result = {}
    for word in words:gmatch("%S+") do result[word] = true end
    return result
end
local commands = set("SHOE RULE RULES PLAYER LEAVE REBUY BET SIDE DEAL INSURANCE HIT STAND DOUBLE SPLIT SURRENDER HINT AUTO STATUS COUNT STATS")
local actions = set("HIT STAND DOUBLE SPLIT SURRENDER")
local idle_commands = set("SHOE RULE PLAYER LEAVE REBUY BET SIDE DEAL")
local player_commands = set("LEAVE REBUY BET SIDE INSURANCE HIT STAND DOUBLE SPLIT SURRENDER AUTO")
local amount_commands = set("REBUY BET SIDE INSURANCE")
local rule_names = { "DEALER", "PEN", "MIN", "MAX", "BJ", "DAS", "DOUBLE", "HANDS", "RSA", "SURRENDER", "CHARLIE", "SIDEMAX" }
local stat_names = { "rounds", "hands", "wins", "losses", "pushes", "blackjacks", "busts", "surrenders", "doubles", "splits" }
local defaults = { DEALER = "S17", PEN = 75, MIN = 10, MAX = 500, BJ = "3:2", DAS = "ON", DOUBLE = "ANY",
    HANDS = 4, RSA = "OFF", SURRENDER = "ON", CHARLIE = 0, SIDEMAX = 25 }
local rule_choices = { DEALER = set("S17 H17"), BJ = set("3:2 6:5"), DOUBLE = set("ANY 9-11 10-11"),
    DAS = set("ON OFF"), RSA = set("ON OFF"), SURRENDER = set("ON OFF") }
local rule_bounds = { PEN = { 50, 90 }, MIN = { 1, 10000 }, MAX = { 1, 10000 }, HANDS = { 1, 4 },
    CHARLIE = { 0, 7 }, SIDEMAX = { 0, 1000 } }

local function fail(message) error({ command_error = true, message = message }, 0) end
local function copy(values)
    local result = {}
    for key, value in pairs(values) do result[key] = value end
    return result
end
local function integer_word(word, low, high)
    if #word > 10 or not word:match("^[0-9]+$") or (#word > 1 and word:sub(1, 1) == "0") then fail("bad value " .. word) end
    local value = tonumber(word)
    if value < low or value > high then fail("bad value " .. word) end
    return value
end
local function rule_value(name, word)
    if defaults[name] == nil then fail("unknown rule " .. name) end
    if rule_choices[name] then
        if not rule_choices[name][word] then fail("bad value " .. word) end
        return word
    end
    local bounds = rule_bounds[name]
    local value = integer_word(word, bounds[1], bounds[2])
    if name == "CHARLIE" and value ~= 0 and value < 5 then fail("bad value " .. word) end
    return value
end
local function signed(value) return (value >= 0 and "+" or "") .. value end
local function point(card) return math.min(10, card % 13 + 1) end
local function card_text(card) return ("A23456789TJQK"):sub(card % 13 + 1, card % 13 + 1) .. ("CDHS"):sub(card // 13 + 1, card // 13 + 1) end
local function black(card) return card // 13 == 0 or card // 13 == 3 end
local function hilo(card)
    local value = point(card)
    return value >= 2 and value <= 6 and 1 or (value >= 7 and value <= 9 and 0 or -1)
end

local Hand = {}
Hand.__index = Hand
function Hand.new(cards, bet, split, split_aces)
    return setmetatable({ cards = cards or {}, bet = bet or 0, split = split or false, split_aces = split_aces or false }, Hand)
end
function Hand:total()
    local value, ace = 0, false
    for _, card in ipairs(self.cards) do
        value = value + point(card)
        ace = ace or card % 13 == 0
    end
    local soft = ace and value + 10 <= 21
    return value + (soft and 10 or 0), soft
end
function Hand:blackjack() return not self.split and #self.cards == 2 and self:total() == 21 end
function Hand:text()
    local value, soft = self:total()
    local status = self:blackjack() and "blackjack" or (value > 21 and "bust " .. value or (soft and "soft " .. value or tostring(value)))
    local cards = {}
    for _, card in ipairs(self.cards) do cards[#cards + 1] = card_text(card) end
    return table.concat(cards, " ") .. " (" .. status .. ")"
end
function Hand:check(rules, hand_count)
    local value = self:total()
    if value > 21 then self.finish = "bust"
    elseif rules.CHARLIE ~= 0 and #self.cards == rules.CHARLIE then self.finish = "charlie"
    elseif value == 21 then self.finish = "ordinary"
    elseif self.split_aces and #self.cards == 2 then
        local again = self.cards[1] % 13 == 0 and self.cards[2] % 13 == 0 and rules.RSA == "ON" and hand_count < rules.HANDS
        if not again then self.finish = "ordinary" end
    end
end

local Player = {}
Player.__index = Player
function Player.new(name, bankroll)
    local stats = {}
    for _, field in ipairs(stat_names) do stats[field] = 0 end
    return setmetatable({ name = name, bankroll = bankroll, bet = 0, side = 0, insurance = 0, net = 0, hands = {}, stats = stats }, Player)
end
function Player:hand_name(index) return self.name .. "[" .. index .. "]" end

local Game = {}
Game.__index = Game
function Game.new()
    return setmetatable({ rules = copy(defaults), players = { false, false, false, false, false, false, false },
        phase = "idle", round = 0, decks = 0, random = 1, shoe = {}, drawn = 0, running = 0, participants = {},
        insurance_turn = 1, dealer = Hand.new(), hole_visible = false, dealer_natural = false,
        dealer_blackjacks = 0, dealer_busts = 0, output = {} }, Game)
end
function Game:emit(...)
    local words = { ... }
    for index = 1, #words do words[index] = tostring(words[index]) end
    self.output[#self.output + 1] = table.concat(words, " ")
end
function Game:find_player(name)
    for seat, player in ipairs(self.players) do if player and player.name == name then return seat end end
end
function Game:lookup(name)
    local seat = self:find_player(name)
    if not seat then fail("unknown player " .. name) end
    return seat
end
function Game:current() return self.players[self.current_seat].hands[self.current_hand] end
function Game:current_name() return self.players[self.current_seat]:hand_name(self.current_hand) end
function Game:hand_line(player, index, verb)
    self:emit(player:hand_name(index) .. (verb and " " .. verb or "") .. ": " .. player.hands[index]:text())
end
function Game:cut() return (#self.shoe * self.rules.PEN) // 100 end
function Game:shuffle()
    self.shoe = {}
    for card = 0, self.decks * 52 - 1 do self.shoe[#self.shoe + 1] = card % 52 end
    for index = #self.shoe, 2, -1 do
        self.random = 48271 * self.random % 2147483647
        local other = self.random % index + 1
        self.shoe[index], self.shoe[other] = self.shoe[other], self.shoe[index]
    end
    self.drawn, self.running = 0, 0
end
function Game:draw(visible)
    self.drawn = self.drawn + 1
    local card = self.shoe[self.drawn]
    if visible then self.running = self.running + hilo(card) end
    return card
end
function Game:reveal_dealer()
    if not self.hole_visible then
        self.running = self.running + hilo(self.dealer.cards[2])
        self.hole_visible = true
    end
    self:emit("dealer: " .. self.dealer:text())
end
function Game:result(hand)
    if self.dealer_natural then return hand:blackjack() and "push" or "lose" end
    if hand:blackjack() then return "blackjack" end
    if hand.finish == "bust" or hand.finish == "surrender" or hand.finish == "charlie" then return hand.finish end
    local own = hand:total()
    local dealer = self.dealer:total()
    if dealer > 21 or own > dealer then return "win" end
    return own == dealer and "push" or "lose"
end
function Game:profit(bet, result)
    if result == "blackjack" then return self.rules.BJ == "3:2" and (bet * 3) // 2 or (bet * 6) // 5 end
    if result == "win" or result == "charlie" then return bet end
    if result == "push" then return 0 end
    if result == "surrender" then return bet // 2 - bet end
    return -bet
end
function Game:settle()
    for _, seat in ipairs(self.participants) do
        local player = self.players[seat]
        for index, hand in ipairs(player.hands) do
            local result = self:result(hand)
            local profit = self:profit(hand.bet, result)
            player.bankroll = player.bankroll + hand.bet + profit
            player.net = player.net + profit
            local stats = player.stats
            stats.hands = stats.hands + 1
            local field = (result == "blackjack" or result == "win" or result == "charlie") and "wins" or (result == "push" and "pushes" or "losses")
            stats[field] = stats[field] + 1
            local special = result == "blackjack" and "blackjacks" or (result == "bust" and "busts" or (result == "surrender" and "surrenders" or nil))
            if special then stats[special] = stats[special] + 1 end
            self:emit(player:hand_name(index), result, signed(profit))
        end
        self:emit(player.name, "bankroll", player.bankroll)
    end
    for _, player in ipairs(self.players) do if player then player.bet, player.side = 0, 0 end end
    self.phase, self.current_seat, self.current_hand = "idle", nil, nil
end
function Game:dealer_turn()
    self:reveal_dealer()
    local required = false
    for _, seat in ipairs(self.participants) do
        for _, hand in ipairs(self.players[seat].hands) do
            if hand.finish == "ordinary" and not hand:blackjack() then required = true end
        end
    end
    local drew = false
    if required then
        while true do
            local value, soft = self.dealer:total()
            if value > 16 and not (value == 17 and soft and self.rules.DEALER == "H17") then break end
            self.dealer.cards[#self.dealer.cards + 1] = self:draw(true)
            self:emit("dealer hits: " .. self.dealer:text())
            drew = true
        end
    end
    if drew and self.dealer:total() > 21 then self.dealer_busts = self.dealer_busts + 1 end
    self:settle()
end
function Game:next_hand()
    for _, seat in ipairs(self.participants) do
        for index, hand in ipairs(self.players[seat].hands) do if not hand.finish then return seat, index end end
    end
end
function Game:advance_hands()
    while true do
        local seat, index = self:next_hand()
        if not seat then self:dealer_turn(); return end
        self.current_seat, self.current_hand = seat, index
        local player = self.players[seat]
        local hand = player.hands[index]
        if #hand.cards ~= 1 then return end
        hand.cards[2] = self:draw(true)
        self:hand_line(player, index)
        hand:check(self.rules, #player.hands)
        if not hand.finish then return end
    end
end
function Game:peek()
    self.dealer_natural = self.dealer:blackjack()
    self:emit("dealer peeks:", self.dealer_natural and "blackjack" or "no blackjack")
    for _, seat in ipairs(self.participants) do
        local player = self.players[seat]
        if player.insurance ~= 0 then
            local profit = self.dealer_natural and player.insurance * 2 or -player.insurance
            player.bankroll = player.bankroll + player.insurance + profit
            player.net = player.net + profit
            self:emit(player.name, "insurance", signed(profit))
        end
    end
    if self.dealer_natural then
        self.dealer_blackjacks = self.dealer_blackjacks + 1
        self:reveal_dealer()
        self:settle()
    else
        self.phase = "play"
        self:advance_hands()
    end
end
function Game:deal()
    if self.drawn >= self:cut() then self:shuffle(); self:emit("shuffle") end
    self.round = self.round + 1
    self:emit("round", self.round)
    self.participants = {}
    for seat, player in ipairs(self.players) do
        if player and player.bet ~= 0 then
            self.participants[#self.participants + 1] = seat
            player.bankroll = player.bankroll - player.bet - player.side
            player.insurance = 0
            player.stats.rounds = player.stats.rounds + 1
            player.hands = { Hand.new({}, player.bet) }
        end
    end
    for _, seat in ipairs(self.participants) do self.players[seat].hands[1].cards[1] = self:draw(true) end
    self.dealer = Hand.new({ self:draw(true) })
    for _, seat in ipairs(self.participants) do
        local hand = self.players[seat].hands[1]
        hand.cards[2] = self:draw(true)
        if hand:blackjack() then hand.finish = "ordinary" end
    end
    self.dealer.cards[2] = self:draw(false)
    self.hole_visible, self.dealer_natural = false, false
    self.current_seat, self.current_hand = nil, nil
    for _, seat in ipairs(self.participants) do self:hand_line(self.players[seat], 1) end
    self:emit("dealer:", card_text(self.dealer.cards[1]), "??")
    for _, seat in ipairs(self.participants) do
        local player = self.players[seat]
        if player.side ~= 0 then
            local first, second = player.hands[1].cards[1], player.hands[1].cards[2]
            local result, multiplier
            if first % 13 ~= second % 13 then result, multiplier = "lose", -1
            elseif first == second then result, multiplier = "perfect", 25
            elseif black(first) == black(second) then result, multiplier = "colored", 12
            else result, multiplier = "mixed", 6 end
            local profit = player.side * multiplier
            player.bankroll = player.bankroll + player.side + profit
            player.net = player.net + profit
            self:emit(player.name, "side", result, signed(profit))
        end
    end
    local up = point(self.dealer.cards[1])
    if up == 1 then
        self.phase, self.insurance_turn = "insurance", 1
        self:emit("insurance offered")
    elseif up == 10 then self:peek()
    else self.phase = "play"; self:advance_hands() end
end
function Game:action_problem(action)
    local player, hand = self.players[self.current_seat], self:current()
    if action == "HIT" then return hand.split_aces and "split aces" or nil end
    if action == "DOUBLE" then
        if hand.split_aces then return "split aces" end
        if #hand.cards ~= 2 then return "two cards only" end
        local value, soft = hand:total()
        local low = self.rules.DOUBLE == "9-11" and 9 or 10
        local limited = self.rules.DOUBLE ~= "ANY" and (soft or value < low or value > 11)
        if limited or (self.rules.DAS == "OFF" and hand.split) then return "double not allowed" end
        if player.bankroll < hand.bet then return "insufficient funds" end
    elseif action == "SPLIT" then
        if #hand.cards ~= 2 then return "two cards only" end
        if point(hand.cards[1]) ~= point(hand.cards[2]) then return "not a pair" end
        if #player.hands >= self.rules.HANDS then return "hand limit" end
        if player.bankroll < hand.bet then return "insufficient funds" end
    elseif action == "SURRENDER" then
        if self.rules.SURRENDER == "OFF" or hand.split then return "surrender not allowed" end
        if #hand.cards ~= 2 then return "two cards only" end
    end
end
function Game:recommendation()
    local hand = self:current()
    local can_split = not self:action_problem("SPLIT")
    if hand.split_aces then return can_split and "SPLIT" or "STAND" end
    local up = point(self.dealer.cards[1])
    if up == 1 then up = 11 end
    if can_split then
        local value = point(hand.cards[1])
        local wanted = value == 1 or value == 8 or (value == 9 and up ~= 7 and up ~= 10 and up ~= 11)
            or ((value == 2 or value == 3 or value == 7) and up <= 7) or (value == 6 and up <= 6)
            or (value == 4 and (up == 5 or up == 6))
        if wanted then return "SPLIT" end
    end
    local value, soft = hand:total()
    local can_double = not self:action_problem("DOUBLE")
    if soft then
        if value >= 19 then return "STAND" end
        if value == 18 then
            if up >= 3 and up <= 6 then return can_double and "DOUBLE" or "STAND" end
            return (up == 2 or up == 7 or up == 8) and "STAND" or "HIT"
        end
        local wanted = (value == 17 and up >= 3 and up <= 6) or ((value == 15 or value == 16) and up >= 4 and up <= 6)
            or ((value == 13 or value == 14) and (up == 5 or up == 6))
        return wanted and can_double and "DOUBLE" or "HIT"
    end
    if value >= 17 then return "STAND" end
    if value >= 13 then
        if up <= 6 then return "STAND" end
        if ((value == 16 and up >= 9) or (value == 15 and up == 10)) and not self:action_problem("SURRENDER") then return "SURRENDER" end
        return "HIT"
    end
    if value == 12 then return up >= 4 and up <= 6 and "STAND" or "HIT" end
    local wanted = (value == 11 and up <= 10) or (value == 10 and up <= 9) or (value == 9 and up >= 3 and up <= 6)
    return wanted and can_double and "DOUBLE" or "HIT"
end
function Game:act(action)
    local player, index = self.players[self.current_seat], self.current_hand
    local hand = player.hands[index]
    if action == "SPLIT" then
        player.bankroll = player.bankroll - hand.bet
        player.stats.splits = player.stats.splits + 1
        self:emit(player:hand_name(index), "splits", card_text(hand.cards[1]), card_text(hand.cards[2]))
        local aces = hand.split_aces or point(hand.cards[1]) == 1
        local first = Hand.new({ hand.cards[1] }, hand.bet, true, aces)
        local second = Hand.new({ hand.cards[2] }, hand.bet, true, aces)
        player.hands[index] = first
        table.insert(player.hands, index + 1, second)
        first.cards[2] = self:draw(true)
        self:hand_line(player, index)
        first:check(self.rules, #player.hands)
    elseif action == "STAND" or action == "SURRENDER" then
        hand.finish = action == "STAND" and "ordinary" or "surrender"
        self:hand_line(player, index, action == "STAND" and "stands" or "surrenders")
    else
        if action == "DOUBLE" then
            player.bankroll = player.bankroll - hand.bet
            hand.bet = hand.bet * 2
            player.stats.doubles = player.stats.doubles + 1
        end
        hand.cards[#hand.cards + 1] = self:draw(true)
        self:hand_line(player, index, action == "DOUBLE" and "doubles" or "hits")
        hand:check(self.rules, #player.hands)
        if action == "DOUBLE" and not hand.finish then hand.finish = "ordinary" end
    end
    self:advance_hands()
end
function Game:status()
    local headline = "table " .. self.phase .. " round " .. self.round
    if self.phase == "insurance" then headline = headline .. " next " .. self.players[self.participants[self.insurance_turn]].name
    elseif self.phase == "play" then headline = headline .. " turn " .. self:current_name() end
    self:emit(headline)
    if self.phase ~= "idle" then self:emit("dealer:", card_text(self.dealer.cards[1]), "??") end
    local participating = {}
    for _, seat in ipairs(self.participants) do participating[seat] = true end
    for seat, player in ipairs(self.players) do
        if player then
            self:emit("seat", seat, player.name, "bankroll", player.bankroll, "bet", player.bet, "side", player.side)
            if self.phase ~= "idle" and participating[seat] then
                for index, hand in ipairs(player.hands) do self:emit(player:hand_name(index) .. ": " .. hand:text(), "bet", hand.bet) end
            end
        end
    end
end
function Game:statistics()
    for _, player in ipairs(self.players) do
        if player then
            local fields = { "stats", player.name }
            for _, name in ipairs(stat_names) do fields[#fields + 1], fields[#fields + 2] = name, tostring(player.stats[name]) end
            fields[#fields + 1], fields[#fields + 2] = "net", signed(player.net)
            self:emit(table.concat(fields, " "))
        end
    end
    self:emit("stats dealer rounds", self.round, "blackjacks", self.dealer_blackjacks, "busts", self.dealer_busts)
end
function Game:command(words)
    self.output = {}
    local op = words[1]
    if not commands[op] then fail("unknown command " .. op) end
    local seat, amount, seed, proposed
    if op == "SHOE" then
        amount = integer_word(words[2], 1, 8)
        seed = integer_word(words[3], 1, 2147483646)
    elseif op == "RULE" then proposed = rule_value(words[2], words[3])
    elseif op == "PLAYER" then
        if #words[2] > 8 or not words[2]:match("^[A-Z]+$") then fail("bad name " .. words[2]) end
        amount = integer_word(words[3], 1, 1000000)
    elseif player_commands[op] then
        seat = self:lookup(words[2])
        if amount_commands[op] then amount = integer_word(words[3], op == "REBUY" and 1 or 0, 1000000) end
    end
    if idle_commands[op] and self.phase ~= "idle" then fail("round in progress") end
    if op == "INSURANCE" and self.phase ~= "insurance" then fail("no insurance") end
    local action_command = actions[op] or op == "AUTO"
    if action_command or op == "HINT" then
        if self.phase == "idle" then fail("no round") end
        if self.phase == "insurance" then fail("insurance pending") end
        if action_command and seat ~= self.current_seat then fail("waiting for " .. self:current_name()) end
    end
    if action_command then
        if op == "AUTO" then
            while self.phase == "play" and self.current_seat == seat do self:act(self:recommendation()) end
        else
            local problem = self:action_problem(op)
            if problem then fail(problem) end
            self:act(op)
        end
        return self.output
    end
    if op == "SHOE" then
        self.decks, self.random = amount, seed
        self:shuffle()
        self:emit("shoe", amount, "decks", #self.shoe, "cards cut", self:cut())
    elseif op == "RULE" then
        local changed = copy(self.rules)
        changed[words[2]] = proposed
        if changed.MIN > changed.MAX then fail("min above max") end
        self.rules = changed
        self:emit("rule", words[2], proposed)
    elseif op == "RULES" then
        local fields = { "rules" }
        for _, name in ipairs(rule_names) do fields[#fields + 1], fields[#fields + 2] = name, tostring(self.rules[name]) end
        self:emit(table.concat(fields, " "))
    elseif op == "PLAYER" then
        if self:find_player(words[2]) then fail("player exists") end
        local empty
        for index, player in ipairs(self.players) do if not player then empty = index; break end end
        if not empty then fail("table full") end
        self.players[empty] = Player.new(words[2], amount)
        self:emit(words[2], "sits at seat", empty, "with", amount)
    elseif op == "LEAVE" then
        local player = self.players[seat]
        self:emit(player.name, "leaves with", player.bankroll, "net", signed(player.net))
        self.players[seat] = false
    elseif op == "REBUY" then
        local player = self.players[seat]
        player.bankroll = player.bankroll + amount
        self:emit(player.name, "rebuys", amount, "bankroll", player.bankroll)
    elseif op == "BET" then
        local player = self.players[seat]
        if amount ~= 0 then
            if amount < self.rules.MIN or amount > self.rules.MAX then fail("bet out of limits") end
            if amount + player.side > player.bankroll then fail("insufficient funds") end
        end
        player.bet = amount
        if amount == 0 then player.side = 0; self:emit(player.name, "bet cleared")
        else self:emit(player.name, "bets", amount) end
    elseif op == "SIDE" then
        local player = self.players[seat]
        if amount ~= 0 then
            if player.bet == 0 then fail("no bet") end
            if amount > self.rules.SIDEMAX then fail("side out of limits") end
            if player.bet + amount > player.bankroll then fail("insufficient funds") end
        end
        player.side = amount
        if amount == 0 then self:emit(player.name, "side cleared") else self:emit(player.name, "side", amount) end
    elseif op == "DEAL" then
        if self.decks == 0 then fail("no shoe") end
        local has_bet = false
        for _, player in ipairs(self.players) do if player and player.bet ~= 0 then has_bet = true end end
        if not has_bet then fail("no bets") end
        self:deal()
    elseif op == "INSURANCE" then
        local waiting = self.participants[self.insurance_turn]
        if seat ~= waiting then fail("waiting for " .. self.players[waiting].name) end
        local player = self.players[seat]
        if amount > player.bet // 2 then fail("insurance out of limits") end
        if amount > player.bankroll then fail("insufficient funds") end
        player.bankroll = player.bankroll - amount
        player.insurance = amount
        if amount == 0 then self:emit(player.name, "declines insurance") else self:emit(player.name, "insures", amount) end
        self.insurance_turn = self.insurance_turn + 1
        if self.insurance_turn > #self.participants then self:peek() end
    elseif op == "HINT" then self:emit("hint " .. self:current_name() .. ": " .. self:recommendation():lower())
    elseif op == "STATUS" then self:status()
    elseif op == "COUNT" then
        if self.decks == 0 then fail("no shoe") end
        local remaining = #self.shoe - self.drawn
        local value = (math.abs(self.running) * 5200) // remaining
        local text = ("%s%d.%02d"):format(self.running < 0 and "-" or "", value // 100, value % 100)
        self:emit("count running", self.running, "true", text, "remaining", remaining)
    elseif op == "STATS" then
        local any = false
        for _, player in ipairs(self.players) do if player then any = true end end
        if not any then fail("no players") end
        self:statistics()
    end
    return self.output
end

local count = tonumber(io.read("*l"))
local game = Game.new()
for _ = 1, count do
    local words = {}
    for word in io.read("*l"):gmatch("%S+") do words[#words + 1] = word end
    local ok, result = pcall(Game.command, game, words)
    if ok then
        for _, line in ipairs(result) do io.write(line, "\n") end
    elseif type(result) == "table" and result.command_error then
        io.write("error: ", result.message, "\n")
    else
        error(result, 0)
    end
end
