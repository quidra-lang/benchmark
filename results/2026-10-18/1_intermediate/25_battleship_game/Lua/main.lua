local ship_names = { "CARRIER", "BATTLESHIP", "CRUISER", "SUBMARINE", "DESTROYER" }
local lengths = { 5, 4, 3, 3, 2 }
local symbols = { "C", "B", "R", "S", "D" }
local strategies = { "HUNT", "PROB", "RANDOM" }
local ship_numbers = {}
for number, name in ipairs(ship_names) do ship_numbers[name] = number end

local function emit(...)
    local words = { ... }
    for i = 1, #words do words[i] = tostring(words[i]) end
    io.write(table.concat(words, " "), "\n")
end
local function fail(message) error({ command_error = true, message = message }, 0) end
local function fill(size, value)
    local result = {}
    for i = 1, size do result[i] = value end
    return result
end
local function copy_list(values)
    local result = {}
    for i, value in ipairs(values) do result[i] = value end
    return result
end
local function advance(random) return 48271 * random % 2147483647 end
local function coordinate(cell) return string.char(65 + (cell - 1) // 10) .. ((cell - 1) % 10 + 1) end
local function parse_cell(text) return (text:byte(1) - 65) * 10 + tonumber(text:sub(2)) end
local function switch_name(enabled) return enabled and "ON" or "OFF" end
local function step(cell, dr, dc)
    local row, column = (cell - 1) // 10 + dr, (cell - 1) % 10 + dc
    if row >= 0 and row < 10 and column >= 0 and column < 10 then return row * 10 + column + 1 end
end
local function adjacent(a, b)
    return math.abs((a - 1) // 10 - (b - 1) // 10) <= 1 and math.abs((a - 1) % 10 - (b - 1) % 10) <= 1
end
local surroundings = {}
for cell = 1, 100 do
    local nearby = {}
    for dr = -1, 1 do
        for dc = -1, 1 do
            if dr ~= 0 or dc ~= 0 then
                local other = step(cell, dr, dc)
                if other then nearby[#nearby + 1] = other end
            end
        end
    end
    surroundings[cell] = nearby
end
local function position(start, stride, length)
    local offset = stride == 1 and (start - 1) % 10 or (start - 1) // 10
    if offset + length > 10 then return nil end
    local cells = {}
    for i = 0, length - 1 do cells[#cells + 1] = start + i * stride end
    return cells
end
local function touching(first, second)
    for _, a in ipairs(first) do
        for _, b in ipairs(second) do if adjacent(a, b) then return true end end
    end
    return false
end
local function ship_range(cells) return coordinate(cells[1]) .. "-" .. coordinate(cells[#cells]) end

local placements = {}
for number, length in ipairs(lengths) do
    placements[number] = {}
    for cell = 1, 100 do
        for _, stride in ipairs({ 1, 10 }) do
            local cells = position(cell, stride, length)
            if cells then placements[number][#placements[number] + 1] = cells end
        end
    end
end

local Player = {}
Player.__index = Player
function Player.new(seed)
    return setmetatable({ fleet = fill(5, false), board = fill(100, 0), attacked = fill(100, false),
        candidates = {}, random = seed, controller = "HUMAN", torpedo_used = false, sonar_used = false,
        shots = 0, hits = 0, sinks = 0, turns = 0, streak = 0, longest = 0, wins = 0 }, Player)
end
function Player:clear_fleet() self.fleet, self.board = fill(5, false), fill(100, 0) end
function Player:put_ship(number, cells)
    self.fleet[number] = cells
    for _, cell in ipairs(cells) do self.board[cell] = number end
end
function Player:attacked_count(number)
    local count = 0
    if self.fleet[number] then
        for _, cell in ipairs(self.fleet[number]) do if self.attacked[cell] then count = count + 1 end end
    end
    return count
end
function Player:sunk(number) return self.fleet[number] and self:attacked_count(number) == lengths[number] end
function Player:placed()
    local count = 0
    for _, cells in ipairs(self.fleet) do if cells then count = count + 1 end end
    return count
end
function Player:afloat()
    local count = 0
    for number, cells in ipairs(self.fleet) do if cells and not self:sunk(number) then count = count + 1 end end
    return count
end
function Player:defeated()
    for number = 1, 5 do if not self:sunk(number) then return false end end
    return true
end
function Player:record(result)
    self.shots = self.shots + 1
    if result == "HIT" or result == "SUNK" then
        self.hits, self.streak = self.hits + 1, self.streak + 1
        self.longest = math.max(self.longest, self.streak)
    else
        self.streak = 0
    end
    if result == "SUNK" then self.sinks = self.sinks + 1 end
end

local Game = {}
Game.__index = Game
function Game.new()
    return setmetatable({ players = { Player.new(1), Player.new(2) }, reefs = fill(100, false),
        salvo = false, chain = false, touch = false, phase = "SETUP", current = 1 }, Game)
end
function Game:allowance(player) return self.salvo and self.players[player]:afloat() or 1 end
function Game:placement_problem(player, cells)
    if not cells then return "out of bounds" end
    for _, cell in ipairs(cells) do if self.reefs[cell] then return "on reef" end end
    for number = 1, 5 do
        for _, cell in ipairs(cells) do
            if player.board[cell] == number then return "overlaps " .. ship_names[number] end
        end
    end
    if not self.touch then
        for number, other in ipairs(player.fleet) do
            if other and touching(cells, other) then return "touches " .. ship_names[number] end
        end
    end
end
function Game:placement_output(player)
    for number, cells in ipairs(self.players[player].fleet) do
        emit("PLACED", player, ship_names[number], ship_range(cells))
    end
end
function Game:auto_place(player, seed)
    local owner, attempts = self.players[player], 0
    owner.random = seed
    owner:clear_fleet()
    for number, length in ipairs(lengths) do
        repeat
            attempts = attempts + 1
            owner.random = advance(owner.random)
            local stride = owner.random % 2 == 0 and 1 or 10
            owner.random = advance(owner.random)
            local k = owner.random % (10 * (11 - length))
            local start = stride == 1 and k // (11 - length) * 10 + k % (11 - length) + 1 or k + 1
            local cells = position(start, stride, length)
            if not self:placement_problem(owner, cells) then owner:put_ship(number, cells) end
        until owner.fleet[number]
    end
    return attempts
end
function Game:layout_fleet(layout)
    local flat, fleet = layout:gsub("/", ""), {}
    for number, symbol in ipairs(symbols) do
        local cells = {}
        for cell = 1, 100 do if flat:sub(cell, cell) == symbol then cells[#cells + 1] = cell end end
        if #cells ~= lengths[number] then fail(ship_names[number] .. " has " .. #cells .. " cells") end
        local stride = cells[2] - cells[1]
        local expected = (stride == 1 or stride == 10) and position(cells[1], stride, #cells)
        if not expected then fail(ship_names[number] .. " not straight") end
        for i, cell in ipairs(cells) do if cell ~= expected[i] then fail(ship_names[number] .. " not straight") end end
        for _, cell in ipairs(cells) do if self.reefs[cell] then fail(ship_names[number] .. " on reef") end end
        fleet[number] = cells
    end
    if not self.touch then
        for first = 1, 4 do
            for second = first + 1, 5 do
                if touching(fleet[first], fleet[second]) then fail(ship_names[first] .. " touches " .. ship_names[second]) end
            end
        end
    end
    return fleet
end
function Game:view(player)
    local opponent = self.players[3 - player]
    local view = { cells = {}, remaining = {}, excluded = fill(100, false) }
    for number = 1, 5 do view.remaining[number] = not opponent:sunk(number) end
    for cell = 1, 100 do
        local number = opponent.board[cell]
        if self.reefs[cell] then view.cells[cell] = "~"
        elseif not opponent.attacked[cell] then view.cells[cell] = "."
        elseif number == 0 then view.cells[cell] = "o"
        else view.cells[cell] = view.remaining[number] and "x" or "#" end
    end
    if not self.touch then
        for cell, value in ipairs(view.cells) do
            if value == "#" then
                for _, other in ipairs(surroundings[cell]) do view.excluded[other] = true end
            end
        end
    end
    return view
end
local function candidate(view, cell) return cell and view.cells[cell] == "." and not view.excluded[cell] end
local function density(view)
    local scores = fill(100, 0)
    for number = 1, 5 do
        if view.remaining[number] then
            for _, cells in ipairs(placements[number]) do
                local possible, hits = true, 0
                for _, cell in ipairs(cells) do
                    if view.excluded[cell] or view.cells[cell] ~= "." and view.cells[cell] ~= "x" then possible = false; break end
                    if view.cells[cell] == "x" then hits = hits + 1 end
                end
                if possible then
                    for _, cell in ipairs(cells) do scores[cell] = scores[cell] + 1 + 10 * hits end
                end
            end
        end
    end
    return scores
end
local function best_cell(view, scores)
    local best
    for cell = 1, 100 do
        if view.cells[cell] == "." and (not best or scores[cell] > scores[best]) then best = cell end
    end
    return best
end
function Game:choose(player, strategy)
    local owner, view = self.players[player], self:view(player)
    if strategy == "PROB" then
        local scores = density(view)
        local cell = best_cell(view, scores)
        return cell, scores[cell], owner.random
    elseif strategy == "RANDOM" then
        local cells = {}
        for cell = 1, 100 do if candidate(view, cell) then cells[#cells + 1] = cell end end
        local random = advance(owner.random)
        return cells[random % #cells + 1], #cells, random
    end
    for cell = 1, 100 do
        if view.cells[cell] == "x" then
            for _, direction in ipairs({ { 0, 1 }, { 1, 0 } }) do
                local dr, dc = direction[1], direction[2]
                local front = step(cell, dr, dc)
                if front and view.cells[front] == "x" then
                    repeat front = step(front, dr, dc) until not front or view.cells[front] ~= "x"
                    if candidate(view, front) then return front, "LINE", owner.random end
                    local back = step(cell, -dr, -dc)
                    if candidate(view, back) then return back, "LINE", owner.random end
                end
            end
        end
    end
    for i = #owner.candidates, 1, -1 do
        local cell = owner.candidates[i]
        if candidate(view, cell) then return cell, "STACK", owner.random end
    end
    local shortest = 5
    for number, remaining in ipairs(view.remaining) do if remaining then shortest = math.min(shortest, lengths[number]) end end
    for cell = 1, 100 do
        if candidate(view, cell) and ((cell - 1) // 10 + (cell - 1) % 10) % shortest == 0 then return cell, "PARITY", owner.random end
    end
end
local function is_hit(result) return result == "HIT" or result == "SUNK" end
local function shot_text(result, number) return result == "SUNK" and "SUNK " .. ship_names[number] or result end
function Game:shoot(player, cell)
    local owner, opponent = self.players[player], self.players[3 - player]
    local number, result = opponent.board[cell], "ALREADY"
    if not opponent.attacked[cell] then
        opponent.attacked[cell] = true
        result = number == 0 and "MISS" or opponent:sunk(number) and "SUNK" or "HIT"
    end
    if result == "HIT" then
        for _, direction in ipairs({ { 0, -1 }, { 1, 0 }, { 0, 1 }, { -1, 0 } }) do
            local other = step(cell, direction[1], direction[2])
            if other then owner.candidates[#owner.candidates + 1] = other end
        end
    end
    owner:record(result)
    return result, number
end
function Game:finish_turn(player, hit, mode)
    local owner = self.players[player]
    owner.turns = owner.turns + 1
    if self.players[3 - player]:defeated() then
        self.phase, self.winner = "OVER", player
        owner.wins = owner.wins + 1
        if mode == "normal" then emit("WINNER", player) end
    else
        self.current = self.chain and hit and player or 3 - player
    end
end
function Game:shooting_turn(player, strategy, cells, mode)
    local hit, allowance = false, self:allowance(player)
    for i = 1, allowance do
        local cell
        if strategy then
            local chosen, _, random = self:choose(player, strategy)
            cell = chosen
            self.players[player].random = random
        else
            cell = cells[i]
        end
        local result, number = self:shoot(player, cell)
        hit = hit or is_hit(result)
        if mode == "normal" then emit("SHOT", player, coordinate(cell), shot_text(result, number))
        elseif mode == "sinks" and result == "SUNK" then emit("SINK", player, ship_names[number], self.players[player].shots) end
        if self.players[3 - player]:defeated() then break end
    end
    self:finish_turn(player, hit, mode)
end
function Game:automatic()
    while self.phase == "BATTLE" do
        local player = self.current
        local controller = self.players[player].controller
        if controller == "HUMAN" then break end
        self:shooting_turn(player, controller, nil, "normal")
    end
end
function Game:torpedo_turn(player, row, side)
    local owner, opponent = self.players[player], self.players[3 - player]
    owner.torpedo_used = true
    local result, hit, stopped_ship = "MISS", false, false
    local start, last, stride = 1, 10, 1
    if side == "E" then start, last, stride = 10, 1, -1 end
    for column = start, last, stride do
        local cell = (row - 1) * 10 + column
        if self.reefs[cell] then
            result = "REEF " .. coordinate(cell)
            break
        elseif opponent.board[cell] ~= 0 then
            local shot, number = self:shoot(player, cell)
            result, hit, stopped_ship = shot_text(shot, number) .. " " .. coordinate(cell), is_hit(shot), true
            break
        end
        opponent.attacked[cell] = true
    end
    if not stopped_ship then owner:record("MISS") end
    emit("TORPEDO", player, string.char(64 + row), side, result)
    self:finish_turn(player, hit, "normal")
end
function Game:sonar_turn(player, center)
    self.players[player].sonar_used = true
    local opponent, count = self.players[3 - player], 0
    for cell = 1, 100 do
        if adjacent(cell, center) and opponent.board[cell] ~= 0 and not opponent.attacked[cell] then count = count + 1 end
    end
    emit("SONAR", player, coordinate(center), count)
    self:finish_turn(player, false, "normal")
end
function Game:board_output(player, radar)
    local owner = self.players[player]
    local view = radar and self:view(player)
    emit(radar and "RADAR" or "BOARD", player)
    emit("  1 2 3 4 5 6 7 8 9 10")
    for row = 1, 10 do
        local values = { string.char(64 + row) }
        for column = 1, 10 do
            local cell, value = (row - 1) * 10 + column
            local number = owner.board[cell]
            if radar then value = view.cells[cell]
            elseif self.reefs[cell] then value = "~"
            elseif number ~= 0 then value = owner.attacked[cell] and symbols[number]:lower() or symbols[number]
            else value = owner.attacked[cell] and "o" or "." end
            values[#values + 1] = value
        end
        emit(table.concat(values, " "))
    end
end
function Game:export_fleet(player)
    local rows = {}
    for row = 1, 10 do
        local cells = {}
        for column = 1, 10 do
            local number = self.players[player].board[(row - 1) * 10 + column]
            cells[column] = number == 0 and "." or symbols[number]
        end
        rows[row] = table.concat(cells)
    end
    emit("EXPORT", player, table.concat(rows, "/"))
end
function Game:fleet_output(player)
    local owner = self.players[player]
    emit("FLEET", player, "afloat", owner:afloat())
    for number, cells in ipairs(owner.fleet) do
        if not cells then emit(ship_names[number], "unplaced")
        else emit(ship_names[number], ship_range(cells), owner:attacked_count(number) .. "/" .. lengths[number], owner:sunk(number) and "SUNK" or "AFLOAT") end
    end
end
function Game:density_output(player)
    local view = self:view(player)
    local scores, columns = density(view), { " " }
    emit("DENSITY", player)
    for column = 1, 10 do columns[#columns + 1] = string.format("%5d", column) end
    emit(table.concat(columns))
    for row = 1, 10 do
        local values = { string.char(64 + row) }
        for column = 1, 10 do
            local cell = (row - 1) * 10 + column
            local value = view.cells[cell] == "." and scores[cell] or view.cells[cell] == "~" and "~" or "-"
            values[#values + 1] = string.format("%5s", tostring(value))
        end
        emit(table.concat(values))
    end
    local best = best_cell(view, scores)
    emit("BEST", coordinate(best), scores[best])
end
function Game:status_output()
    local reefs = 0
    for _, reef in ipairs(self.reefs) do if reef then reefs = reefs + 1 end end
    local prefix = "STATUS " .. self.phase .. " salvo " .. switch_name(self.salvo) .. " chain " .. switch_name(self.chain)
        .. " touch " .. switch_name(self.touch) .. " reefs " .. reefs
    local first, second = self.players[1], self.players[2]
    if self.phase == "SETUP" then emit(prefix, "placed", first:placed(), second:placed())
    elseif self.phase == "BATTLE" then emit(prefix, "turn", self.current, "shots", self:allowance(self.current), "afloat", first:afloat(), second:afloat())
    else emit(prefix, "winner", self.winner, "afloat", first:afloat(), second:afloat()) end
end
function Game:statistics_output()
    for player, owner in ipairs(self.players) do
        local accuracy = owner.shots == 0 and "-" or (owner.hits * 100 // owner.shots) .. "%"
        emit("STATS", player, "shots", owner.shots, "hits", owner.hits, "sunk", owner.sinks,
            "turns", owner.turns, "streak", owner.longest, "accuracy", accuracy, "wins", owner.wins)
    end
end

local function play_match(current, first_seed, second_seed, first_strategy, second_strategy, mode)
    local game = Game.new()
    game.salvo, game.chain, game.touch = current.salvo, current.chain, current.touch
    game.reefs = copy_list(current.reefs)
    game:auto_place(1, first_seed)
    game:auto_place(2, second_seed)
    game.phase = "BATTLE"
    while game.phase == "BATTLE" do
        local player = game.current
        game:shooting_turn(player, player == 1 and first_strategy or second_strategy, nil, mode)
    end
    return game
end
function Game:series_output(count, seed, first_strategy, second_strategy)
    local wins, shots, fastest = { 0, 0 }, { 0, 0 }, {}
    for _ = 1, count do
        local first_seed = advance(seed)
        seed = advance(first_seed)
        local game = play_match(self, first_seed, seed, first_strategy, second_strategy, "quiet")
        local winner = game.winner
        wins[winner] = wins[winner] + 1
        for player = 1, 2 do shots[player] = shots[player] + game.players[player].shots end
        local won_shots = game.players[winner].shots
        fastest[winner] = fastest[winner] and math.min(fastest[winner], won_shots) or won_shots
    end
    emit("SERIES", count, "wins", wins[1], wins[2], "shots", shots[1], shots[2], "fastest", fastest[1] or "-", fastest[2] or "-")
end
function Game:tourney_output(count, seed)
    local wins, shots = { 0, 0, 0 }, { 0, 0, 0 }
    for first = 1, 3 do
        for second = 1, 3 do
            if first ~= second then
                for _ = 1, count do
                    local first_seed = advance(seed)
                    seed = advance(first_seed)
                    local game = play_match(self, first_seed, seed, strategies[first], strategies[second], "quiet")
                    local winner = game.winner == 1 and first or second
                    wins[winner] = wins[winner] + 1
                    shots[first], shots[second] = shots[first] + game.players[1].shots, shots[second] + game.players[2].shots
                end
            end
        end
    end
    local ranking = { 1, 2, 3 }
    table.sort(ranking, function(a, b)
        if wins[a] ~= wins[b] then return wins[a] > wins[b] end
        if shots[a] ~= shots[b] then return shots[a] < shots[b] end
        return a < b
    end)
    emit("TOURNEY", count)
    for rank, number in ipairs(ranking) do emit(rank, strategies[number], "wins", wins[number], "shots", shots[number]) end
end

local setup_commands = { PLACE = true, REMOVE = true, AUTOPLACE = true, LAYOUT = true, REEF = true, SALVO = true, CHAIN = true, TOUCH = true }
local turn_commands = { FIRE = true, AI = true, TORPEDO = true, SONAR = true }
local player_commands = { PLACE = true, REMOVE = true, AUTOPLACE = true, LAYOUT = true, FIRE = true, AI = true, TORPEDO = true,
    SONAR = true, RESIGN = true, CONTROL = true, SEED = true, HINT = true, DENSITY = true, SHOW = true, RADAR = true, EXPORT = true, FLEET = true }

local function execute(game, words)
    local command = words[1]
    if command == "NEW" then
        local replacement = Game.new()
        for player = 1, 2 do replacement.players[player].wins = game.players[player].wins end
        emit("NEW")
        return replacement
    end
    local player = player_commands[command] and tonumber(words[2])
    if setup_commands[command] and game.phase ~= "SETUP" then fail("setup closed") end
    if turn_commands[command] then
        if game.phase == "OVER" then fail("game over") end
        if game.phase == "SETUP" and (game.players[1]:placed() < 5 or game.players[2]:placed() < 5) then fail("fleets not ready") end
        if player ~= game.current then fail("not your turn") end
        local cells = {}
        if command == "FIRE" then
            local expected = game:allowance(player)
            if #words - 2 ~= expected then fail("expected " .. expected .. " shots") end
            for i = 3, #words do
                local cell = parse_cell(words[i])
                if game.reefs[cell] then fail("reef at " .. coordinate(cell)) end
                cells[#cells + 1] = cell
            end
        elseif command == "TORPEDO" and game.players[player].torpedo_used then fail("torpedo used")
        elseif command == "SONAR" and game.players[player].sonar_used then fail("sonar used") end
        game.phase = "BATTLE"
        if command == "FIRE" then game:shooting_turn(player, nil, cells, "normal")
        elseif command == "AI" then game:shooting_turn(player, words[3], nil, "normal")
        elseif command == "TORPEDO" then game:torpedo_turn(player, words[3]:byte() - 64, words[4])
        else game:sonar_turn(player, parse_cell(words[3])) end
        game:automatic()
        return game
    end
    if command == "PLACE" or command == "REMOVE" then
        local owner, number = game.players[player], ship_numbers[words[3]]
        if command == "PLACE" then
            if owner.fleet[number] then fail(ship_names[number] .. " already placed") end
            local cells = position(parse_cell(words[4]), words[5] == "H" and 1 or 10, lengths[number])
            local problem = game:placement_problem(owner, cells)
            if problem then fail(problem) end
            owner:put_ship(number, cells)
            emit("PLACED", player, ship_names[number], ship_range(cells))
        else
            if not owner.fleet[number] then fail(ship_names[number] .. " not placed") end
            for _, cell in ipairs(owner.fleet[number]) do owner.board[cell] = 0 end
            owner.fleet[number] = false
            emit("REMOVED", player, ship_names[number])
        end
    elseif command == "AUTOPLACE" then
        local attempts = game:auto_place(player, tonumber(words[3]))
        emit("AUTOPLACE", player, "attempts", attempts)
        game:placement_output(player)
    elseif command == "LAYOUT" then
        local fleet = game:layout_fleet(words[3])
        game.players[player]:clear_fleet()
        for number, cells in ipairs(fleet) do game.players[player]:put_ship(number, cells) end
        emit("LAYOUT", player)
        game:placement_output(player)
    elseif command == "REEF" then
        local cell = parse_cell(words[2])
        if game.reefs[cell] then fail("reef exists at " .. coordinate(cell)) end
        for owner = 1, 2 do
            local number = game.players[owner].board[cell]
            if number ~= 0 then fail(coordinate(cell) .. " occupied by " .. owner .. " " .. ship_names[number]) end
        end
        game.reefs[cell] = true
        emit("REEF", coordinate(cell))
    elseif command == "SALVO" or command == "CHAIN" or command == "TOUCH" then
        game[command:lower()] = words[2] == "ON"
        emit(command, words[2])
    elseif command == "CONTROL" then
        game.players[player].controller = words[3]
        emit("CONTROL", player, words[3])
    elseif command == "SEED" then
        game.players[player].random = tonumber(words[3])
        emit("SEED", player, game.players[player].random)
    elseif command == "RESIGN" then
        if game.phase ~= "BATTLE" then fail("not in battle") end
        game.phase, game.winner = "OVER", 3 - player
        game.players[game.winner].wins = game.players[game.winner].wins + 1
        emit("RESIGN", player)
        emit("WINNER", game.winner)
    elseif command == "HINT" then
        if game.phase == "OVER" then fail("game over") end
        local cell, info = game:choose(player, words[3])
        emit("HINT", player, words[3], coordinate(cell), info)
    elseif command == "DENSITY" then
        if game.phase == "OVER" then fail("game over") end
        game:density_output(player)
    elseif command == "SHOW" or command == "RADAR" then game:board_output(player, command == "RADAR")
    elseif command == "EXPORT" then game:export_fleet(player)
    elseif command == "FLEET" then game:fleet_output(player)
    elseif command == "STATUS" then game:status_output()
    elseif command == "STATS" then game:statistics_output()
    elseif command == "MATCH" then
        emit("MATCH", 1, words[4], 2, words[5])
        local trial = play_match(game, tonumber(words[2]), tonumber(words[3]), words[4], words[5], "sinks")
        local first, second = trial.players[1], trial.players[2]
        emit("RESULT winner", trial.winner, "shots", first.shots, second.shots, "hits", first.hits, second.hits)
    elseif command == "SERIES" then game:series_output(tonumber(words[2]), tonumber(words[3]), words[4], words[5])
    elseif command == "TOURNEY" then game:tourney_output(tonumber(words[2]), tonumber(words[3])) end
    return game
end

local function input_line() return (io.read("l"):gsub("\r$", "")) end
local game = Game.new()
local count = tonumber(input_line())
for _ = 1, count do
    local words = {}
    for word in input_line():gmatch("%S+") do words[#words + 1] = word end
    local ok, result = pcall(execute, game, words)
    if ok then game = result
    elseif type(result) == "table" and result.command_error then emit("ERROR", result.message)
    else error(result, 0) end
end
