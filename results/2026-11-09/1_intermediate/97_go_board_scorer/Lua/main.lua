local columns = "ABCDEFGHJKLMNOPQRST"
local handicap_points = {
    [9] = {"C3", "G7", "C7", "G3", "C5", "G5", "E3", "E7", "E5"},
    [13] = {"D4", "K10", "D10", "K4", "D7", "K7", "G4", "G10", "G7"},
    [19] = {"D4", "Q16", "D16", "Q4", "D10", "Q10", "K4", "K16", "K10"}
}
local arity = {
    BOARD = 2,
    KOMI = 1,
    SUPERKO = 1,
    HANDICAP = 1,
    PLAY = 2,
    PASS = 1,
    REPLAY = 1,
    UNDO = 0,
    SHOW = 0,
    MAP = 0,
    STATUS = 0,
    CAPTURES = 0,
    HISTORY = 0,
    MOVES = 0,
    GROUP = 1,
    GROUPS = 0,
    ATARI = 0,
    LEGAL = 1,
    EYES = 1,
    SAFE = 1,
    LADDER = 1,
    DEAD = 1,
    REGIONS = 0,
    SCORE = 1
}
local function other(c)
    return c == "B" and "W" or "B"
end
local function half(x)
    return (x < 0 and "-" or "") .. (math.abs(x) // 2) .. (math.abs(x) % 2 == 1 and ".5" or ".0")
end
local function copy(a)
    local b = {}
    for k, v in pairs(a) do
        b[k] = v
    end
    return b
end
local function size(a)
    local n = 0
    for _ in pairs(a) do
        n = n + 1
    end
    return n
end
local function ordered(a)
    local r = {}
    for p in pairs(a) do
        r[#r + 1] = p
    end
    table.sort(r)
    return r
end
local function subset(a, b)
    for p in pairs(a) do
        if not b[p] then
            return false
        end
    end
    return true
end
local function merge(a, b)
    for p in pairs(b) do
        a[p] = true
    end
end
local function emit(...)
    local a = {...}
    for i, v in ipairs(a) do
        a[i] = tostring(v)
    end
    io.write(table.concat(a, " "), "\n")
end
local function komi(s)
    local unsigned = s:sub(1, 1) == "-" and s:sub(2) or s
    local whole, fraction = unsigned:match("^(%d+)%.([05])$")
    if not whole then
        whole = unsigned:match("^%d+$")
        fraction = "0"
    end
    if not whole or (#whole > 1 and whole:sub(1, 1) == "0") or tonumber(whole) > 100 then
        return nil
    end
    local x = 2 * tonumber(whole) + (fraction == "5" and 1 or 0)
    if s:sub(1, 1) == "-" then
        if x == 0 then
            return nil
        end
        return -x
    end
    return x
end
local function adjacent(p, n, diagonal)
    local r, c = (p - 1) // n, (p - 1) % n
    local a = {}
    local steps =
        diagonal and {{-1, -1}, {-1, 1}, {1, -1}, {1, 1}} or {{-1, 0}, {1, 0}, {0, -1}, {0, 1}}
    for _, step in ipairs(steps) do
        local dr, dc = step[1], step[2]
        if r + dr >= 0 and r + dr < n and c + dc >= 0 and c + dc < n then
            a[#a + 1] = (r + dr) * n + c + dc + 1
        end
    end
    return a
end
local function flood(b, n, p, allowed)
    local seen, todo = {[p] = true}, {p}
    while #todo > 0 do
        local s = table.remove(todo)
        for _, q in ipairs(adjacent(s, n)) do
            if not seen[q] and allowed:find(b[q], 1, true) then
                seen[q] = true
                todo[#todo + 1] = q
            end
        end
    end
    return seen
end
local function group(b, n, p)
    local stones, liberties = flood(b, n, p, b[p]), {}
    for q in pairs(stones) do
        for _, t in ipairs(adjacent(q, n)) do
            if b[t] == "." then
                liberties[t] = true
            end
        end
    end
    return {color = b[p], first = ordered(stones)[1], stones = stones, liberties = liberties}
end
local function groups(b, n, color)
    local out, seen = {}, {}
    for p = 1, #b do
        if b[p] ~= "." and not seen[p] and (not color or b[p] == color) then
            local g = group(b, n, p)
            merge(seen, g.stones)
            out[#out + 1] = g
        end
    end
    return out
end
local function placement(b, n, c, p)
    if b[p] ~= "." then
        return b, 0, "occupied"
    end
    local updated = copy(b)
    updated[p] = c
    local captured, seen = 0, {}
    for _, q in ipairs(adjacent(p, n)) do
        if updated[q] == other(c) and not seen[q] then
            local g = group(updated, n, q)
            merge(seen, g.stones)
            if size(g.liberties) == 0 then
                for t in pairs(g.stones) do
                    updated[t] = "."
                    captured = captured + 1
                end
            end
        end
    end
    return updated, captured, size(group(updated, n, p).liberties) == 0 and "suicide" or ""
end
local function regions(b, n)
    local out, seen = {}, {}
    for p = 1, #b do
        if b[p] == "." and not seen[p] then
            local points = flood(b, n, p, ".")
            merge(seen, points)
            local border = {}
            for q in pairs(points) do
                for _, t in ipairs(adjacent(q, n)) do
                    if b[t] ~= "." then
                        border[b[t]] = true
                    end
                end
            end
            local owner = "neutral"
            if size(border) == 1 then
                for c in pairs(border) do
                    owner = c
                end
            end
            out[#out + 1] = {first = p, points = points, owner = owner}
        end
    end
    return out
end
local function safe_groups(b, n, c)
    local own, areas, seen = groups(b, n, c), {}, {}
    for p = 1, #b do
        if b[p] ~= c and not seen[p] then
            local area = flood(b, n, p, "." .. other(c))
            merge(seen, area)
            local empty = {}
            for q in pairs(area) do
                if b[q] == "." then
                    empty[q] = true
                end
            end
            local touch, vital = {}, {}
            for i, g in ipairs(own) do
                local touching = false
                for q in pairs(area) do
                    for _, t in ipairs(adjacent(q, n)) do
                        if g.stones[t] then
                            touching = true
                        end
                    end
                end
                if touching then
                    touch[i] = true
                end
                if subset(empty, g.liberties) then
                    vital[i] = true
                end
            end
            areas[#areas + 1] = {touch = touch, vital = vital}
        end
    end
    local s, t = {}, {}
    for i in ipairs(own) do
        s[i] = true
    end
    for j in ipairs(areas) do
        t[j] = true
    end
    while true do
        local before = size(s) + size(t)
        local ns, nt = {}, {}
        for i in pairs(s) do
            local count = 0
            for j in pairs(t) do
                if areas[j].vital[i] then
                    count = count + 1
                end
            end
            if count >= 2 then
                ns[i] = true
            end
        end
        s = ns
        for j in pairs(t) do
            if subset(areas[j].touch, s) then
                nt[j] = true
            end
        end
        t = nt
        if before == size(s) + size(t) then
            break
        end
    end
    local out = {}
    for _, i in ipairs(ordered(s)) do
        out[#out + 1] = own[i]
    end
    return out
end
local function ladder(b, n, p)
    local defender, attacker = b[p], other(b[p])
    local memo = {}
    local read
    read = function(current, depth, defending)
        if depth >= 40 then
            return defending, -1
        end
        local key = table.concat(current) .. ":" .. depth .. ":" .. tostring(defending)
        if memo[key] then
            return table.unpack(memo[key])
        end
        local g = group(current, n, p)
        local candidates, seen = copy(g.liberties), {}
        if defending then
            for q in pairs(g.stones) do
                for _, t in ipairs(adjacent(q, n)) do
                    if current[t] == attacker and not seen[t] then
                        local e = group(current, n, t)
                        merge(seen, e.stones)
                        if size(e.liberties) == 1 then
                            merge(candidates, e.liberties)
                        end
                    end
                end
            end
        end
        for _, q in ipairs(ordered(candidates)) do
            local updated, _, reason = placement(current, n, defending and defender or attacker, q)
            if reason == "" then
                local success
                if defending then
                    local count = size(group(updated, n, p).liberties)
                    success = count >= 3 or count == 2 and not read(updated, depth + 1, false)
                else
                    success = not read(updated, depth + 1, true)
                end
                if success then
                    memo[key] = {true, q}
                    return true, q
                end
            end
        end
        memo[key] = {false, -1}
        return false, -1
    end
    local count = size(group(b, n, p).liberties)
    if count >= 3 then
        return "safe", -1
    end
    local success, move = read(b, 0, count == 1)
    local escapes = count == 1 and success or count ~= 1 and not success
    return escapes and "escapes" or "captured", move
end
local Game = {}
Game.__index = Game
function Game:reset(n, k)
    self.n, self.komi, self.board, self.turn = n, k, {}, "B"
    for p = 1, n * n do
        self.board[p] = "."
    end
    self.captures, self.passes, self.over = {B = 0, W = 0}, 0, false
    self.handicap, self.history, self.positions, self.dead = {}, {}, {self.board}, {}
end
function Game:point(s)
    local letter, row = s:match("^([A-HJ-T])([1-9]%d?)$")
    if not letter then
        return -1
    end
    local c = columns:find(letter, 1, true)
    local r = tonumber(row)
    if c > self.n or r > self.n then
        return -1
    end
    return (r - 1) * self.n + c
end
function Game:name(p)
    local c = (p - 1) % self.n + 1
    return columns:sub(c, c) .. ((p - 1) // self.n + 1)
end
function Game:sgf(p)
    return string.char(97 + (p - 1) % self.n, 97 + self.n - 1 - (p - 1) // self.n)
end
function Game:check(c, p)
    local b, captured, reason = placement(self.board, self.n, c, p)
    local text = table.concat(b)
    if
        reason == "" and #self.positions >= 2 and
            text == table.concat(self.positions[#self.positions - 1])
     then
        reason = "ko"
    end
    if reason == "" and self.superko then
        for _, old in ipairs(self.positions) do
            if text == table.concat(old) then
                reason = "superko"
                break
            end
        end
    end
    return b, captured, reason
end
function Game:move(c, p, checked)
    local before = {
        board = self.board,
        turn = self.turn,
        captures = copy(self.captures),
        passes = self.passes,
        over = self.over
    }
    local captured = 0
    if p < 0 then
        self.passes = self.passes + 1
        if self.passes == 2 then
            self.over = true
        end
    else
        local b, count
        if checked then
            b, count = checked[1], checked[2]
        else
            b, count = self:check(c, p)
        end
        self.board = b
        captured = count
        self.captures[c] = self.captures[c] + captured
        self.passes = 0
    end
    self.turn = other(c)
    self.history[#self.history + 1] = {color = c, point = p, captured = captured, before = before}
    self.positions[#self.positions + 1] = self.board
    self.dead = {}
    return captured
end
function Game:clean()
    local b = copy(self.board)
    for p in pairs(self.dead) do
        b[p] = "."
    end
    return b
end
function Game:show(map)
    local b = map and self:clean() or self.board
    local chars, stars = copy(b), {}
    for i, s in ipairs(handicap_points[self.n]) do
        if self.n == 19 or i <= 4 or i == 9 then
            stars[self:point(s)] = true
        end
    end
    if map then
        for _, r in ipairs(regions(b, self.n)) do
            for p in pairs(r.points) do
                chars[p] = r.owner == "B" and "x" or r.owner == "W" and "o" or "."
            end
        end
    end
    for p, c in ipairs(b) do
        if c ~= "." then
            local letter = c == "B" and "X" or "O"
            chars[p] = not map and self.dead[p] and letter:lower() or letter
        elseif not map then
            chars[p] = stars[p] and "+" or "."
        end
    end
    local letters = {}
    for c = 1, self.n do
        letters[c] = columns:sub(c, c)
    end
    local header = "   " .. table.concat(letters, " ")
    emit(header)
    for r = self.n, 1, -1 do
        local a = {}
        for c = 1, self.n do
            a[#a + 1] = chars[(r - 1) * self.n + c]
        end
        emit(string.format("%2d", r), table.concat(a, " "), r)
    end
    emit(header)
end
function Game:score(method)
    local b, territory, total = self:clean(), {B = 0, W = 0}, {}
    for _, r in ipairs(regions(b, self.n)) do
        if territory[r.owner] then
            territory[r.owner] = territory[r.owner] + size(r.points)
        end
    end
    for _, c in ipairs({"B", "W"}) do
        local fields = {c}
        if method == "AREA" then
            local stones = 0
            for _, v in ipairs(b) do
                if v == c then
                    stones = stones + 1
                end
            end
            total[c] = 2 * (stones + territory[c]) + (c == "W" and self.komi or 0)
            fields = {c, "stones", stones, "territory", territory[c]}
        else
            local prisoners = self.captures[c]
            for p in pairs(self.dead) do
                if self.board[p] == other(c) then
                    prisoners = prisoners + 1
                end
            end
            total[c] = 2 * (territory[c] + prisoners) + (c == "W" and self.komi or 0)
            fields = {c, "territory", territory[c], "prisoners", prisoners}
        end
        if c == "W" then
            fields[#fields + 1] = "komi"
            fields[#fields + 1] = half(self.komi)
        end
        fields[#fields + 1] = "total"
        fields[#fields + 1] = half(total[c])
        emit(table.unpack(fields))
    end
    local d = total.B - total.W
    emit("result", d > 0 and "B+" .. half(d) or d < 0 and "W+" .. half(-d) or "Draw")
end
function Game:execute(line)
    local words = {}
    for word in line:gmatch("[^ ]+") do
        words[#words + 1] = word
    end
    local c = table.remove(words, 1)
    local a = words
    if arity[c] == nil then
        emit("ERROR unknown command")
        return
    end
    if #a ~= arity[c] then
        emit("ERROR bad arguments")
        return
    end
    local valid = true
    if c == "BOARD" then
        valid = (a[1] == "9" or a[1] == "13" or a[1] == "19") and komi(a[2]) ~= nil
    elseif c == "KOMI" then
        valid = komi(a[1]) ~= nil
    elseif c == "SUPERKO" then
        valid = a[1] == "ON" or a[1] == "OFF"
    elseif c == "HANDICAP" then
        valid = a[1]:match("^[2-9]$") ~= nil
    elseif c == "PLAY" or c == "PASS" or c == "LEGAL" or c == "EYES" or c == "SAFE" then
        valid = a[1] == "B" or a[1] == "W"
    elseif c == "SCORE" then
        valid = a[1] == "AREA" or a[1] == "TERRITORY"
    end
    if not valid then
        emit("ERROR bad arguments")
        return
    end
    local p = -1
    if c == "PLAY" or c == "GROUP" or c == "LADDER" or c == "DEAD" then
        p = self:point(a[c == "PLAY" and 2 or 1])
        if p < 0 then
            emit("ERROR bad point")
            return
        end
    end
    local records = {}
    if c == "REPLAY" then
        local at = 1
        while at <= #a[1] do
            local s, e, color, text = a[1]:find(";([BW])%[([a-z]*)%]", at)
            if
                s ~= at or
                    (#text ~= 0 and
                        (#text ~= 2 or text:byte(1) - 97 >= self.n or text:byte(2) - 97 >= self.n))
             then
                emit("ERROR bad sequence")
                return
            end
            records[#records + 1] = {
                color = color,
                point = #text == 0 and -1 or
                    (self.n - 1 - (text:byte(2) - 97)) * self.n + text:byte(1) - 96
            }
            at = e + 1
        end
        if #records == 0 then
            emit("ERROR bad sequence")
            return
        end
    end
    if (c == "PLAY" or c == "PASS" or c == "REPLAY") and self.over then
        emit("ERROR game over")
        return
    end
    if c == "BOARD" then
        self:reset(tonumber(a[1]), komi(a[2]))
        emit("board", self.n, "komi", half(self.komi))
    elseif c == "KOMI" then
        self.komi = komi(a[1])
        emit("komi", half(self.komi))
    elseif c == "SUPERKO" then
        self.superko = a[1] == "ON"
        emit("superko", self.superko and "on" or "off")
    elseif c == "HANDICAP" then
        if #self.history > 0 then
            emit("ERROR handicap not allowed")
            return
        end
        for _, v in ipairs(self.board) do
            if v ~= "." then
                emit("ERROR handicap not allowed")
                return
            end
        end
        local k = tonumber(a[1])
        local ix = k == 5 and {1, 2, 3, 4, 9} or k == 7 and {1, 2, 3, 4, 5, 6, 9} or {}
        if #ix == 0 then
            for i = 1, k do
                ix[i] = i
            end
        end
        self.board = copy(self.board)
        self.handicap = {}
        local fields = {"handicap", k}
        for _, i in ipairs(ix) do
            local q = self:point(handicap_points[self.n][i])
            self.handicap[#self.handicap + 1] = q
            self.board[q] = "B"
            fields[#fields + 1] = self:name(q)
        end
        self.turn = "W"
        self.positions = {self.board}
        self.dead = {}
        emit(table.unpack(fields))
    elseif c == "PLAY" then
        local checked = {self:check(a[1], p)}
        local reason = a[1] ~= self.turn and "turn" or checked[3]
        if reason ~= "" then
            emit("ILLEGAL", a[1], a[2], reason)
        else
            local captured = self:move(a[1], p, checked)
            if captured == 0 then
                emit(a[1], a[2])
            else
                emit(a[1], a[2], "captures", captured)
            end
        end
    elseif c == "PASS" then
        if a[1] ~= self.turn then
            emit("ILLEGAL", a[1], "pass turn")
        else
            self:move(a[1], -1)
            emit(a[1], "pass")
            if self.over then
                emit("game over")
            end
        end
    elseif c == "REPLAY" then
        local count, stop = 0, {}
        for _, r in ipairs(records) do
            local checked
            if r.point >= 0 then
                checked = {self:check(r.color, r.point)}
            end
            local reason =
                self.over and "game over" or r.color ~= self.turn and "turn" or
                checked and checked[3] or
                ""
            if reason ~= "" then
                stop = {"stopped", r.color, r.point < 0 and "pass" or self:name(r.point), reason}
                break
            end
            self:move(r.color, r.point, checked)
            count = count + 1
        end
        emit("replay", count, "moves", table.unpack(stop))
        if self.over then
            emit("game over")
        end
    elseif c == "UNDO" then
        if #self.history == 0 then
            emit("ERROR nothing to undo")
            return
        end
        local m = table.remove(self.history)
        for k, v in pairs(m.before) do
            self[k] = v
        end
        table.remove(self.positions)
        self.dead = {}
        emit("undo", m.color, m.point < 0 and "pass" or self:name(m.point))
    elseif c == "SHOW" or c == "MAP" then
        self:show(c == "MAP")
    elseif c == "STATUS" then
        emit(
            "size",
            self.n,
            "komi",
            half(self.komi),
            "handicap",
            #self.handicap,
            "superko",
            self.superko and "on" or "off"
        )
        if self.over then
            emit("moves", #self.history, "game over")
        else
            emit("moves", #self.history, "next", self.turn, "passes", self.passes)
        end
    elseif c == "CAPTURES" then
        emit("captures B", self.captures.B, "W", self.captures.W)
    elseif c == "HISTORY" then
        emit("history", #self.history)
        for i, m in ipairs(self.history) do
            local fields = {i, m.color, m.point < 0 and "pass" or self:name(m.point)}
            if m.captured > 0 then
                fields[#fields + 1] = "captures"
                fields[#fields + 1] = m.captured
            end
            emit(table.unpack(fields))
        end
    elseif c == "MOVES" then
        local s = "(;GM[1]FF[4]SZ[" .. self.n .. "]KM[" .. half(self.komi) .. "]"
        if #self.handicap > 0 then
            s = s .. "HA[" .. #self.handicap .. "]AB"
            for _, q in ipairs(self.handicap) do
                s = s .. "[" .. self:sgf(q) .. "]"
            end
        end
        for _, m in ipairs(self.history) do
            s = s .. ";" .. m.color .. "[" .. (m.point < 0 and "" or self:sgf(m.point)) .. "]"
        end
        emit(s .. ")")
    elseif c == "GROUP" or c == "DEAD" or c == "LADDER" then
        if self.board[p] == "." then
            emit("ERROR no stone")
            return
        end
        local g = group(self.board, self.n, p)
        if c == "GROUP" then
            emit(
                "group",
                g.color,
                self:name(g.first),
                "size",
                size(g.stones),
                "liberties",
                size(g.liberties)
            )
            local stones, liberties = {"stones"}, {"liberties"}
            for _, q in ipairs(ordered(g.stones)) do
                stones[#stones + 1] = self:name(q)
            end
            for _, q in ipairs(ordered(g.liberties)) do
                liberties[#liberties + 1] = self:name(q)
            end
            emit(table.unpack(stones))
            emit(table.unpack(liberties))
        elseif c == "DEAD" then
            local alive = self.dead[p]
            for q in pairs(g.stones) do
                self.dead[q] = not alive and true or nil
            end
            emit(alive and "alive" or "dead", g.color, self:name(g.first), "size", size(g.stones))
        else
            local status, q = ladder(self.board, self.n, p)
            if q < 0 then
                emit("ladder", a[1], status)
            else
                emit("ladder", a[1], status, self:name(q))
            end
        end
    elseif c == "GROUPS" then
        local gs = groups(self.board, self.n)
        emit("groups", #gs)
        for _, g in ipairs(gs) do
            local fields = {
                g.color,
                self:name(g.first),
                "size",
                size(g.stones),
                "liberties",
                size(g.liberties)
            }
            if self.dead[g.first] then
                fields[#fields + 1] = "dead"
            end
            emit(table.unpack(fields))
        end
    elseif c == "ATARI" then
        local found = false
        for _, g in ipairs(groups(self.board, self.n)) do
            if size(g.liberties) == 1 then
                found = true
                emit(
                    "atari",
                    g.color,
                    self:name(g.first),
                    "size",
                    size(g.stones),
                    "at",
                    self:name(ordered(g.liberties)[1])
                )
            end
        end
        if not found then
            emit("atari none")
        end
    elseif c == "LEGAL" then
        local rejected, count = {}, 0
        for q, v in ipairs(self.board) do
            if v == "." then
                local _, _, reason = self:check(a[1], q)
                if reason == "" then
                    count = count + 1
                else
                    rejected[#rejected + 1] = {self:name(q), reason}
                end
            end
        end
        emit("legal", a[1], count)
        for _, r in ipairs(rejected) do
            emit(table.unpack(r))
        end
    elseif c == "EYES" then
        local found = {}
        for q, v in ipairs(self.board) do
            if v == "." then
                local ns = adjacent(q, self.n)
                local all = true
                for _, t in ipairs(ns) do
                    if self.board[t] ~= a[1] then
                        all = false
                    end
                end
                if all then
                    local enemies = 0
                    for _, t in ipairs(adjacent(q, self.n, true)) do
                        if self.board[t] == other(a[1]) then
                            enemies = enemies + 1
                        end
                    end
                    found[#found + 1] = {
                        self:name(q),
                        enemies <= (#ns == 4 and 1 or 0) and "real" or "false"
                    }
                end
            end
        end
        emit("eyes", a[1], #found)
        for _, r in ipairs(found) do
            emit(table.unpack(r))
        end
    elseif c == "SAFE" then
        local gs = safe_groups(self.board, self.n, a[1])
        emit("safe", a[1], #gs)
        for _, g in ipairs(gs) do
            emit(self:name(g.first), "size", size(g.stones))
        end
    elseif c == "REGIONS" then
        local rs = regions(self:clean(), self.n)
        emit("regions", #rs)
        for _, r in ipairs(rs) do
            emit(self:name(r.first), "size", size(r.points), r.owner)
        end
    elseif c == "SCORE" then
        self:score(a[1])
    end
end
local game = setmetatable({superko = false}, Game)
game:reset(19, 13)
local count = tonumber(io.read("*l"))
for _ = 1, count do
    game:execute(io.read("*l"))
end
