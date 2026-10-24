local function emit(...)
    local words = { ... }
    for i = 1, #words do words[i] = tostring(words[i]) end
    io.write(table.concat(words, " "), "\n")
end

local function fail(message) error({ command_error = true, message = message }, 0) end
local function input_line() return (io.read("l"):gsub("\r$", "")) end
local function split(line)
    local words = {}
    for word in line:gmatch("%S+") do words[#words + 1] = word end
    return words
end
local function fill(size, value)
    local values = {}
    for i = 1, size do values[i] = value end
    return values
end
local function copy_list(values)
    local result = {}
    for i = 1, #values do result[i] = values[i] end
    return result
end
local function count_true(values)
    local count = 0
    for _, value in pairs(values) do if value then count = count + 1 end end
    return count
end
local function fraction(numerator, denominator)
    local a, b = numerator, denominator
    while b ~= 0 do a, b = b, a % b end
    return (numerator // a) .. "/" .. (denominator // a)
end
local function totals() return { rounds = 0, flagged = 0, opened = 0, guesses = 0 } end
local function add_totals(total, other)
    total.rounds = total.rounds + other.rounds
    total.flagged = total.flagged + other.flagged
    total.opened = total.opened + other.opened
end
local function any_deduction(result) return next(result.safe) ~= nil or next(result.mines) ~= nil end

local Component = {}
Component.__index = Component
function Component.new(cells, constraints)
    return setmetatable({ cells = cells, constraints = constraints, configurations = 0,
        minimum = #cells, maximum = 0, mine_counts = fill(#cells, 0), counted = false }, Component)
end
function Component:search(depth, mines)
    if depth > #self.cells then
        self.configurations = self.configurations + 1
        self.minimum, self.maximum = math.min(self.minimum, mines), math.max(self.maximum, mines)
        for i, value in ipairs(self.assignment) do self.mine_counts[i] = self.mine_counts[i] + value end
        return
    end
    local variable = self.order[depth]
    for value = 0, 1 do
        self.assignment[variable] = value
        local possible = true
        for _, c in ipairs(self.links[variable]) do
            self.remaining[c] = self.remaining[c] - 1
            self.sums[c] = self.sums[c] + value
            local required = self.constraints[c].remaining
            if self.sums[c] > required or self.sums[c] + self.remaining[c] < required then possible = false end
        end
        if possible then self:search(depth + 1, mines + value) end
        for _, c in ipairs(self.links[variable]) do
            self.sums[c], self.remaining[c] = self.sums[c] - value, self.remaining[c] + 1
        end
    end
end
function Component:count()
    if self.counted then return end
    self.counted = true
    for _, c in ipairs(self.constraints) do if c.remaining < 0 or c.remaining > #c.unknown then return end end
    self.index, self.links, self.order, self.remaining = {}, {}, {}, {}
    for i, cell in ipairs(self.cells) do self.index[cell], self.links[i], self.order[i] = i, {}, i end
    for c, constraint in ipairs(self.constraints) do
        self.remaining[c] = #constraint.unknown
        for _, cell in ipairs(constraint.unknown) do
            local links = self.links[self.index[cell]]
            links[#links + 1] = c
        end
    end
    table.sort(self.order, function(a, b)
        if #self.links[a] ~= #self.links[b] then return #self.links[a] > #self.links[b] end
        return a < b
    end)
    self.sums, self.assignment = fill(#self.constraints, 0), fill(#self.cells, 0)
    self:search(1, 0)
end
function Component:mine_count(cell) return self.mine_counts[self.index[cell]] end

local Game = {}
Game.__index = Game
function Game.new(width, height, mine_count, seed, placement)
    local size = width * height
    local self = setmetatable({ width = width, height = height, size = size, mine_count = mine_count, seed = seed,
        numbers = fill(size, 0), neighbors = {}, revealed = fill(size, false), marks = fill(size, "none"),
        state = "ready", moves = {}, undo = {} }, Game)
    for cell = 1, size do
        local x, y = (cell - 1) % width, (cell - 1) // width
        local nearby = {}
        for dy = -1, 1 do
            for dx = -1, 1 do
                if (dx ~= 0 or dy ~= 0) and x + dx >= 0 and x + dx < width and y + dy >= 0 and y + dy < height then
                    nearby[#nearby + 1] = (y + dy) * width + x + dx + 1
                end
            end
        end
        self.neighbors[cell] = nearby
    end
    if placement then self:set_placement(placement) end
    return self
end
function Game:finished() return self.state == "won" or self.state == "lost" end
function Game:cell(cell) return ((cell - 1) % self.width) .. "," .. ((cell - 1) // self.width) end
function Game:unknown(cell) return not self.revealed[cell] and self.marks[cell] ~= "flag" end
function Game:remaining()
    local flags = 0
    for _, mark in ipairs(self.marks) do if mark == "flag" then flags = flags + 1 end end
    return self.mine_count - flags
end
function Game:open_count() return count_true(self.revealed) end
function Game:flags(cell)
    local flags = 0
    for _, other in ipairs(self.neighbors[cell]) do if self.marks[other] == "flag" then flags = flags + 1 end end
    return flags
end
function Game:unknown_neighbors(cell)
    local result = {}
    for _, other in ipairs(self.neighbors[cell]) do if self:unknown(other) then result[#result + 1] = other end end
    return result
end
function Game:copy(reset)
    local result = setmetatable({}, Game)
    -- Placements, numbers, neighbors and recorded moves remain immutable after creation.
    for key, value in pairs(self) do result[key] = value end
    result.revealed, result.marks, result.moves = copy_list(self.revealed), copy_list(self.marks), copy_list(self.moves)
    result.undo = {}
    if reset then result:restart() end
    return result
end
function Game:set_placement(mines)
    local numbers = {}
    for cell, nearby in ipairs(self.neighbors) do
        local number = 0
        for _, other in ipairs(nearby) do if mines[other] then number = number + 1 end end
        numbers[cell] = number
    end
    self.mines, self.numbers, self.state = mines, numbers, "playing"
end
function Game:place(first, safety)
    local sx, sy = (first - 1) % self.width, (first - 1) // self.width
    local candidates = {}
    for cell = 1, self.size do
        if safety == "none" or safety == "cell" and cell ~= first or safety == "block" and
            (math.abs((cell - 1) % self.width - sx) >= 2 or math.abs((cell - 1) // self.width - sy) >= 2) then
            candidates[#candidates + 1] = cell
        end
    end
    local mines, random = fill(self.size, false), self.seed
    for _ = 1, self.mine_count do
        random = 48271 * random % 2147483647
        local index = random % #candidates + 1
        mines[candidates[index]] = true
        table.remove(candidates, index)
    end
    self:set_placement(mines)
end
function Game:restart()
    self.revealed, self.marks = fill(self.size, false), fill(self.size, "none")
    self.moves, self.undo, self.exploded = {}, {}, nil
    self.state = self.mines and "playing" or "ready"
end
function Game:snapshot(name)
    return { name = name, revealed = copy_list(self.revealed), marks = copy_list(self.marks), move_count = #self.moves }
end
function Game:restore(saved)
    self.revealed, self.marks = saved.revealed, saved.marks
    while #self.moves > saved.move_count do self.moves[#self.moves] = nil end
end
function Game:record(kind, cell) self.moves[#self.moves + 1] = { kind = kind, cell = cell } end
function Game:reveal(first, safety)
    if not self.mines then self:place(first, safety) end
    if self.mines[first] then self.state, self.exploded = "lost", first; return 0 end
    self.revealed[first], self.marks[first] = true, "none"
    local queue, head = { first }, 1
    while head <= #queue do
        local cell = queue[head]
        head = head + 1
        if self.numbers[cell] == 0 then
            for _, other in ipairs(self.neighbors[cell]) do
                if self:unknown(other) then
                    self.revealed[other], self.marks[other] = true, "none"
                    queue[#queue + 1] = other
                end
            end
        end
    end
    return #queue
end
function Game:chord(cell, safety)
    local opened = 0
    for _, other in ipairs(self.neighbors[cell]) do
        if self:unknown(other) then
            opened = opened + self:reveal(other, safety)
            if self.state == "lost" then break end
        end
    end
    return opened
end
function Game:check_win()
    if self.state ~= "playing" or self:open_count() ~= self.size - self.mine_count then return false end
    self.state = "won"
    for cell, mine in ipairs(self.mines) do if mine then self.marks[cell] = "flag" end end
    return true
end
function Game:display()
    for y = 0, self.height - 1 do
        local row = {}
        for x = 0, self.width - 1 do
            local cell = y * self.width + x + 1
            local character
            if self.state == "lost" and self.mines[cell] then
                character = cell == self.exploded and "!" or (self.marks[cell] == "flag" and "F" or "*")
            elseif self.state == "lost" and self.marks[cell] == "flag" then character = "X"
            elseif self.revealed[cell] then character = self.numbers[cell] == 0 and "." or tostring(self.numbers[cell])
            else character = self.marks[cell] == "flag" and "F" or (self.marks[cell] == "question" and "?" or "#") end
            row[#row + 1] = character
        end
        emit(table.concat(row))
    end
end
function Game:ending()
    if self.state == "lost" then emit("boom", self:cell(self.exploded)); self:display()
    elseif self.state == "won" then emit("win moves", #self.moves) end
end
function Game:constraints()
    local constraints = {}
    for cell = 1, self.size do
        if self.revealed[cell] and self.numbers[cell] > 0 then
            local unknown = self:unknown_neighbors(cell)
            if #unknown > 0 then
                local members = {}
                for _, other in ipairs(unknown) do members[other] = true end
                constraints[#constraints + 1] = { cell = cell, unknown = unknown, members = members,
                    remaining = self.numbers[cell] - self:flags(cell) }
            end
        end
    end
    return constraints
end
function Game:deduce()
    local result, constraints = { safe = {}, mines = {} }, self:constraints()
    for _, c in ipairs(constraints) do
        if c.remaining == 0 then
            for _, cell in ipairs(c.unknown) do result.safe[cell] = result.safe[cell] or "single " .. self:cell(c.cell) end
        end
    end
    if any_deduction(result) then return result end
    for _, c in ipairs(constraints) do
        if c.remaining == #c.unknown then
            for _, cell in ipairs(c.unknown) do result.mines[cell] = result.mines[cell] or "single " .. self:cell(c.cell) end
        end
    end
    if any_deduction(result) then return result end
    for _, a in ipairs(constraints) do
        for _, b in ipairs(constraints) do
            if #a.unknown < #b.unknown then
                local subset = true
                for _, cell in ipairs(a.unknown) do if not b.members[cell] then subset = false; break end end
                if subset then
                    local difference = {}
                    for _, cell in ipairs(b.unknown) do if not a.members[cell] then difference[#difference + 1] = cell end end
                    local remaining = b.remaining - a.remaining
                    local reason = "subset " .. self:cell(a.cell) .. " " .. self:cell(b.cell)
                    if remaining == 0 then
                        for _, cell in ipairs(difference) do result.safe[cell] = result.safe[cell] or reason end
                    end
                    if remaining == #difference then
                        for _, cell in ipairs(difference) do result.mines[cell] = result.mines[cell] or reason end
                    end
                end
            end
        end
    end
    if any_deduction(result) then return result end
    if self.state == "playing" and self:remaining() == 0 then
        for cell = 1, self.size do if self:unknown(cell) then result.safe[cell] = "count" end end
    end
    return result
end
function Game:frontier()
    local constraints, links = self:constraints(), {}
    for cell = 1, self.size do links[cell] = {} end
    for c, constraint in ipairs(constraints) do
        for _, cell in ipairs(constraint.unknown) do links[cell][#links[cell] + 1] = c end
    end
    local seen, components, at = {}, {}, {}
    for start = 1, self.size do
        if not seen[start] and #links[start] > 0 then
            local cells, selected, picked, head = { start }, {}, {}, 1
            seen[start] = true
            while head <= #cells do
                for _, c in ipairs(links[cells[head]]) do
                    if not picked[c] then
                        picked[c] = true
                        selected[#selected + 1] = constraints[c]
                        for _, cell in ipairs(constraints[c].unknown) do
                            if not seen[cell] then seen[cell] = true; cells[#cells + 1] = cell end
                        end
                    end
                end
                head = head + 1
            end
            table.sort(cells)
            local component = Component.new(cells, selected)
            components[#components + 1] = component
            for _, cell in ipairs(cells) do at[cell] = component end
        end
    end
    return { components = components, at = at }
end
function Game:auto(safety)
    local total = totals()
    while self.state == "playing" do
        local deduction = self:deduce()
        if not any_deduction(deduction) then break end
        total.rounds = total.rounds + 1
        for cell = 1, self.size do
            if deduction.safe[cell] and not self.revealed[cell] then
                self:record("auto-reveal", cell)
                total.opened = total.opened + self:reveal(cell, safety)
                self:check_win()
                if self:finished() then return total end
            end
        end
        for cell = 1, self.size do
            if deduction.mines[cell] and self:unknown(cell) then
                self.marks[cell] = "flag"
                total.flagged = total.flagged + 1
                self:record("auto-flag", cell)
            end
        end
    end
    return total
end
function Game:solve(safety)
    local total = totals()
    while not self:finished() do
        add_totals(total, self:auto(safety))
        if self:finished() then break end
        local frontier = self:frontier()
        for _, component in ipairs(frontier.components) do component:count() end
        local unknown_count = 0
        for cell = 1, self.size do if self:unknown(cell) then unknown_count = unknown_count + 1 end end
        local background = math.max(self:remaining(), 0)
        local best, best_numerator, best_denominator = nil, 0, 1
        for cell = 1, self.size do
            if self:unknown(cell) then
                local component = frontier.at[cell]
                local numerator, denominator
                if not component then numerator, denominator = background, unknown_count
                elseif component.configurations > 0 then numerator, denominator = component:mine_count(cell), component.configurations end
                if numerator and (not best or numerator * best_denominator < best_numerator * denominator) then
                    best, best_numerator, best_denominator = cell, numerator, denominator
                end
            end
        end
        if not best then break end
        total.guesses = total.guesses + 1
        self:record("guess", best)
        total.opened = total.opened + self:reveal(best, safety)
        self:check_win()
    end
    return total
end
function Game:replay(count, safety)
    local copy = self:copy(true)
    for i = 1, count do
        local move = self.moves[i]
        local kind, cell = move.kind, move.cell
        if kind == "reveal" or kind == "auto-reveal" or kind == "guess" then copy:reveal(cell, safety)
        elseif kind == "chord" then copy:chord(cell, safety)
        elseif kind == "flag" or kind == "auto-flag" then copy.marks[cell] = "flag"
        elseif kind == "unflag" then copy.marks[cell] = "none"
        else copy.marks[cell] = copy.marks[cell] == "question" and "none" or "question" end
        copy:check_win()
    end
    return copy
end
function Game:board_info()
    local blank, seen = {}, {}
    for cell = 1, self.size do blank[cell] = not self.mines[cell] and self.numbers[cell] == 0 end
    local openings, largest, isolated = 0, 0, 0
    for start = 1, self.size do
        if blank[start] and not seen[start] then
            openings = openings + 1
            local queue, head, area = { start }, 1, { [start] = true }
            seen[start] = true
            while head <= #queue do
                for _, cell in ipairs(self.neighbors[queue[head]]) do
                    area[cell] = true
                    if blank[cell] and not seen[cell] then seen[cell] = true; queue[#queue + 1] = cell end
                end
                head = head + 1
            end
            largest = math.max(largest, count_true(area))
        end
        if not self.mines[start] and not blank[start] then
            local adjacent_blank = false
            for _, cell in ipairs(self.neighbors[start]) do if blank[cell] then adjacent_blank = true; break end end
            if not adjacent_blank then isolated = isolated + 1 end
        end
    end
    emit("3bv", openings + isolated, "openings", openings, "largest", largest, "mines", self.mine_count, "safe", self.size - self.mine_count)
end

local ARITY = { NEW = 4, PRESET = 2, SAFETY = 1, RESTART = 0, REVEAL = 2, FLAG = 2, UNFLAG = 2,
    QUESTION = 2, CHORD = 2, UNDO = 0, SHOW = 0, STATUS = 0, CELL = 2, HISTORY = 1, REPLAY = 1,
    HINT = 0, AUTO = 0, ANALYZE = 0, PROB = 2, FRONTIER = 0, SOLVE = 0, BOARDINFO = 0, STATS = 0 }
local CELL_COMMANDS = { REVEAL = true, FLAG = true, UNFLAG = true, QUESTION = true, CHORD = true, CELL = true, PROB = true }
local ACTIVE_COMMANDS = { REVEAL = true, FLAG = true, UNFLAG = true, QUESTION = true, CHORD = true, UNDO = true,
    HINT = true, AUTO = true, ANALYZE = true, PROB = true, FRONTIER = true, SOLVE = true }
local UNDOABLE = { REVEAL = true, FLAG = true, UNFLAG = true, QUESTION = true, CHORD = true, AUTO = true, SOLVE = true }
local PRESETS = { beginner = { 9, 9, 10 }, intermediate = { 16, 16, 40 }, expert = { 30, 16, 99 } }
local SAFETY = { block = true, cell = true, none = true }
local function number_word(word)
    if #word > 10 or not word:match("^%d+$") or #word > 1 and word:sub(1, 1) == "0" then fail("bad arguments") end
    return tonumber(word)
end

local Program = {}
Program.__index = Program
function Program.new()
    return setmetatable({ safety = "block", played = 0, won = 0, lost = 0, streak = 0, best_streak = 0 }, Program)
end
function Program:layout(words)
    local width, height, rows = tonumber(words[2]), tonumber(words[3]), {}
    for i = 1, height do rows[i] = input_line() end
    local mines, count = {}, 0
    for i, row in ipairs(rows) do
        if #row ~= width or row:find("[^*.]") then fail("bad row " .. i) end
        for x = 1, width do
            local mine = row:sub(x, x) == "*"
            mines[#mines + 1] = mine
            if mine then count = count + 1 end
        end
    end
    if count == 0 or count == width * height then fail("bad mine count " .. count) end
    self.game = Game.new(width, height, count, 1, mines)
    emit("layout", width .. "x" .. height, "mines", count)
end
function Program:stats()
    local rate = self.played == 0 and "-" or (self.won * 100 // self.played) .. "%"
    emit("stats played", self.played, "won", self.won, "lost", self.lost, "rate", rate,
        "streak", self.streak, "best", self.best_streak, "fastest", self.fastest or "-")
end
function Program:record_finish(game)
    self.played = self.played + 1
    if game.state == "won" then
        self.won, self.streak = self.won + 1, self.streak + 1
        self.best_streak = math.max(self.best_streak, self.streak)
        self.fastest = math.min(self.fastest or #game.moves, #game.moves)
    else self.lost, self.streak = self.lost + 1, 0 end
end
function Program:execute(words)
    local op = words[1]
    if op == "LAYOUT" then self:layout(words); return end
    if ARITY[op] == nil then fail("unknown command " .. op) end
    if #words ~= ARITY[op] + 1 then fail("bad arguments") end
    local values = {}
    if op == "NEW" or CELL_COMMANDS[op] or op == "HISTORY" or op == "REPLAY" then
        for i = 2, #words do values[#values + 1] = number_word(words[i]) end
    elseif op == "PRESET" then
        if not PRESETS[words[2]] then fail("bad arguments") end
        values[1] = number_word(words[3])
    elseif op == "SAFETY" and not SAFETY[words[2]] then fail("bad arguments") end

    if op == "NEW" or op == "PRESET" then
        local width, height, mines, seed
        if op == "NEW" then width, height, mines, seed = table.unpack(values)
        else width, height, mines = table.unpack(PRESETS[words[2]]); seed = values[1] end
        if width < 1 or width > 30 or height < 1 or height > 30 or mines < 1 or mines > width * height - 9 or seed < 1 or seed > 2147483646 then fail("bad value") end
        self.game = Game.new(width, height, mines, seed)
        emit("new", width .. "x" .. height, "mines", mines); return
    end
    if op == "HISTORY" and values[1] == 0 then fail("bad value") end
    if op == "SAFETY" then self.safety = words[2]; emit("safety", self.safety); return end
    if op == "STATS" then self:stats(); return end
    local game = self.game
    if not game then fail("no game") end
    if CELL_COMMANDS[op] and (values[1] >= game.width or values[2] >= game.height) then fail("out of range") end
    local cell = CELL_COMMANDS[op] and (values[2] * game.width + values[1] + 1) or 1
    if game:finished() and ACTIVE_COMMANDS[op] then fail("game over") end
    if (op == "ANALYZE" or op == "BOARDINFO") and not game.mines then fail("not started") end
    local was_finished = game:finished()
    local saved = UNDOABLE[op] and game:snapshot(op:lower()) or nil

    if op == "RESTART" then game:restart(); emit("restart", game.width .. "x" .. game.height, "mines", game.mine_count)
    elseif op == "REVEAL" then
        if game.revealed[cell] then fail("already revealed") end
        if game.marks[cell] == "flag" then fail("flagged") end
        game:record("reveal", cell)
        local opened = game:reveal(cell, self.safety)
        if game.state ~= "lost" then emit("revealed", opened); game:check_win() end
        game:ending()
    elseif op == "FLAG" or op == "UNFLAG" or op == "QUESTION" then
        if game.revealed[cell] then fail("already revealed") end
        if op == "FLAG" and game.marks[cell] == "flag" then fail("already flagged") end
        if op == "UNFLAG" and game.marks[cell] ~= "flag" then fail("not flagged") end
        local mark, verb
        if op == "FLAG" then mark, verb = "flag", "flagged"
        elseif op == "UNFLAG" then mark, verb = "none", "unflagged"
        else
            mark = game.marks[cell] == "question" and "none" or "question"
            verb = mark == "none" and "unmarked" or "questioned"
        end
        game.marks[cell] = mark; game:record(op:lower(), cell)
        emit(verb, game:cell(cell), "left", game:remaining())
    elseif op == "CHORD" then
        if not game.revealed[cell] then fail("not revealed") end
        if game.numbers[cell] == 0 then fail("no number") end
        local flags = game:flags(cell)
        if flags ~= game.numbers[cell] then fail("flags " .. flags .. " of " .. game.numbers[cell]) end
        if #game:unknown_neighbors(cell) == 0 then fail("nothing to reveal") end
        game:record("chord", cell)
        local opened = game:chord(cell, self.safety)
        if game.state ~= "lost" then emit("chorded", opened); game:check_win() end
        game:ending()
    elseif op == "UNDO" then
        if #game.undo == 0 then fail("nothing to undo") end
        local record = table.remove(game.undo)
        game:restore(record); emit("undo", record.name, "moves", #game.moves)
    elseif op == "SHOW" then game:display()
    elseif op == "STATUS" then
        emit("status", game.state, "left", game:remaining(), "moves", #game.moves, "revealed", game:open_count() .. "/" .. (game.size - game.mine_count))
    elseif op == "CELL" then
        if game.revealed[cell] then
            emit("cell", game:cell(cell), "number", game.numbers[cell], "flags", game:flags(cell), "unknown", #game:unknown_neighbors(cell))
        else
            local opened = 0
            for _, other in ipairs(game.neighbors[cell]) do if game.revealed[other] then opened = opened + 1 end end
            emit("cell", game:cell(cell), "hidden mark", game.marks[cell], "open", opened)
        end
    elseif op == "HISTORY" then
        emit("history", #game.moves)
        for i = math.max(1, #game.moves - values[1] + 1), #game.moves do
            local move = game.moves[i]; emit(i, move.kind, game:cell(move.cell))
        end
    elseif op == "REPLAY" then
        if values[1] > #game.moves then fail("no move " .. values[1]) end
        emit("replay", values[1] .. "/" .. #game.moves); game:replay(values[1], self.safety):display()
    elseif op == "HINT" then
        local deduction, found = game:deduce(), false
        for _, kind in ipairs({ "safe", "mine" }) do
            local reasons = kind == "safe" and deduction.safe or deduction.mines
            for at = 1, game.size do
                if reasons[at] then emit("hint", kind, game:cell(at), "by", reasons[at]); found = true; break end
            end
            if found then break end
        end
        if not found then emit("hint none") end
    elseif op == "AUTO" or op == "SOLVE" then
        local total = op == "AUTO" and game:auto(self.safety) or game:solve(self.safety)
        if op == "AUTO" then emit("auto rounds", total.rounds, "flagged", total.flagged, "revealed", total.opened)
        else emit("solve guesses", total.guesses, "rounds", total.rounds, "flagged", total.flagged, "revealed", total.opened) end
        game:ending()
    elseif op == "ANALYZE" then
        local copy = game:copy()
        local total = copy:auto(self.safety)
        if copy.state == "lost" then emit("analyze boom", copy:cell(copy.exploded), "rounds", total.rounds)
        elseif copy.state == "won" then emit("analyze clear rounds", total.rounds)
        else emit("analyze stuck rounds", total.rounds, "revealed", copy:open_count() .. "/" .. (copy.size - copy.mine_count)) end
    elseif op == "PROB" then
        if game.revealed[cell] then fail("already revealed") end
        if game.marks[cell] == "flag" then fail("flagged") end
        local component = game:frontier().at[cell]
        if not component then emit("prob", game:cell(cell), "unconstrained")
        else
            component:count()
            if component.configurations == 0 then emit("prob", game:cell(cell), "inconsistent")
            else emit("prob", game:cell(cell), fraction(component:mine_count(cell), component.configurations), "size", #component.cells, "configs", component.configurations) end
        end
    elseif op == "FRONTIER" then
        local frontier = game:frontier()
        emit("frontier", count_true(frontier.at), "components", #frontier.components)
        for _, component in ipairs(frontier.components) do
            component:count()
            if component.configurations == 0 then emit("component", game:cell(component.cells[1]), "size", #component.cells, "inconsistent")
            else emit("component", game:cell(component.cells[1]), "size", #component.cells, "configs", component.configurations, "min", component.minimum, "max", component.maximum) end
        end
    elseif op == "BOARDINFO" then game:board_info() end
    if saved and #game.moves > saved.move_count then game.undo[#game.undo + 1] = saved end
    if not was_finished and game:finished() then self:record_finish(game) end
end

local program = Program.new()
local command_count = tonumber(input_line())
for _ = 1, command_count do
    local ok, problem = pcall(program.execute, program, split(input_line()))
    if not ok then
        if type(problem) == "table" and problem.command_error then emit("error:", problem.message)
        else error(problem, 0) end
    end
end
