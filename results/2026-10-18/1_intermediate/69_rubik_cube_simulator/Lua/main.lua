local faces, colors = "URFDLB", "WRGYOB"
local turns = {
    R = {1, 1, {1}}, L = {1, 3, {-1}}, M = {1, 3, {0}},
    r = {1, 1, {0, 1}}, l = {1, 3, {-1, 0}}, x = {1, 1, {-1, 0, 1}},
    U = {2, 1, {1}}, D = {2, 3, {-1}}, E = {2, 3, {0}},
    u = {2, 1, {0, 1}}, d = {2, 3, {-1, 0}}, y = {2, 1, {-1, 0, 1}},
    F = {3, 1, {1}}, B = {3, 3, {-1}}, S = {3, 1, {0}},
    f = {3, 1, {0, 1}}, b = {3, 3, {-1, 0}}, z = {3, 1, {-1, 0, 1}},
}
local function bad(pattern, ...)
    error(string.format(pattern, ...), 0)
end
local function split(text, separator)
    local result, start = {}, 1
    while true do
        local at = text:find(separator, start, true)
        if not at then
            result[#result + 1] = text:sub(start)
            return result
        end
        result[#result + 1] = text:sub(start, at - 1)
        start = at + #separator
    end
end
local function words(text)
    local result = {}
    for word in text:gmatch("%S+") do
        result[#result + 1] = word
    end
    return result
end
local function copy(seq)
    local result = {}
    for i, move in ipairs(seq) do
        result[i] = {move[1], move[2]}
    end
    return result
end
local function append(destination, seq)
    for _, move in ipairs(seq) do
        destination[#destination + 1] = {move[1], move[2]}
    end
end
local function inverse(seq)
    local result = {}
    for i = #seq, 1, -1 do
        result[#result + 1] = {seq[i][1], 4 - seq[i][2]}
    end
    return result
end
local function literal_moves(text)
    local result = {}
    for _, word in ipairs(words(text)) do
        result[#result + 1] = {word:sub(1, 1), word:sub(2) == "2" and 2 or word:sub(2) == "'" and 3 or 1}
    end
    return result
end
local function move_text(move)
    return move[1] .. ({"", "2", "'"})[move[2]]
end
local function moves_text(seq)
    local result = {}
    for i, move in ipairs(seq) do
        result[i] = move_text(move)
    end
    return table.concat(result, " ")
end
local function sequence_text(seq)
    return tostring(#seq) .. (#seq > 0 and " " .. moves_text(seq) or "")
end
local function identity()
    local result = {}
    for i = 1, 54 do
        result[i] = i
    end
    return result
end
local function compose(a, b)
    local result = {}
    for i = 1, 54 do
        result[i] = a[b[i]]
    end
    return result
end
local function inverse_permutation(p)
    local result = {}
    for i, source in ipairs(p) do
        result[source] = i
    end
    return result
end
local function key(p)
    local result = {}
    for i, source in ipairs(p) do
        result[i] = string.char(source)
    end
    return table.concat(result)
end
local function permute(cube, p)
    local result = {}
    for i, source in ipairs(p) do
        result[i] = cube:sub(source, source)
    end
    return table.concat(result)
end
local function quarter(vector, axis)
    local result = {table.unpack(vector)}
    local a, b = axis % 3 + 1, (axis + 1) % 3 + 1
    result[a], result[b] = vector[b], -vector[a]
    return result
end
local function place_key(cubie, normal)
    return table.concat(cubie, ",") .. ";" .. table.concat(normal, ",")
end
local frames = {
    {{0, 1, 0}, {1, 0, 0}, {0, 0, 1}},
    {{1, 0, 0}, {0, 0, -1}, {0, -1, 0}},
    {{0, 0, 1}, {1, 0, 0}, {0, -1, 0}},
    {{0, -1, 0}, {1, 0, 0}, {0, 0, -1}},
    {{-1, 0, 0}, {0, 0, 1}, {0, -1, 0}},
    {{0, 0, -1}, {-1, 0, 0}, {0, -1, 0}},
}
local places, numbers = {}, {}
for _, frame in ipairs(frames) do
    for row = -1, 1 do
        for column = -1, 1 do
            local cubie = {}
            for axis = 1, 3 do
                cubie[axis] = frame[1][axis] + column * frame[2][axis] + row * frame[3][axis]
            end
            places[#places + 1] = {cubie, frame[1]}
            numbers[place_key(cubie, frame[1])] = #places
        end
    end
end
local tables, by_effect = {}, {}
for letter, turn in pairs(turns) do
    local p = identity()
    for source, place in ipairs(places) do
        local selected = false
        for _, layer in ipairs(turn[3]) do
            if place[1][turn[1]] == layer then
                selected = true
            end
        end
        if selected then
            local cubie, normal = place[1], place[2]
            for _ = 1, turn[2] do
                cubie, normal = quarter(cubie, turn[1]), quarter(normal, turn[1])
            end
            p[numbers[place_key(cubie, normal)]] = source
        end
    end
    local current = identity()
    for amount = 1, 3 do
        current = compose(current, p)
        tables[letter .. amount] = current
        by_effect[key(current)] = {letter, amount}
    end
end
local function effect(seq)
    local p = identity()
    for _, move in ipairs(seq) do
        p = compose(p, tables[move[1] .. move[2]])
    end
    return p
end
local function apply(cube, seq)
    for _, move in ipairs(seq) do
        cube = permute(cube, tables[move[1] .. move[2]])
    end
    return cube
end
local rotations, rotation_effects = {}, {}
for _, first in ipairs({"", "x", "x2", "x'", "z", "z'"}) do
    for _, second in ipairs({"", "y", "y2", "y'"}) do
        local seq = literal_moves(first .. " " .. second)
        rotations[#rotations + 1] = seq
        rotation_effects[#rotation_effects + 1] = effect(seq)
    end
end
local solved_parts = {}
for i = 1, 6 do
    solved_parts[i] = colors:sub(i, i):rep(9)
end
local solved = table.concat(solved_parts)
local function make_group(names, layout)
    local group = {names = words(names), stickers = {}}
    for _, row in ipairs(split(layout, ";")) do
        local stickers = {}
        for _, word in ipairs(words(row)) do
            stickers[#stickers + 1] = (faces:find(word:sub(1, 1), 1, true) - 1) * 9 + tonumber(word:sub(2))
        end
        group.stickers[#group.stickers + 1] = stickers
    end
    return group
end
local corners = make_group("URF UFL ULB UBR DFR DLF DBL DRB", "U9 R1 F3;U7 F1 L3;U1 L1 B3;U3 B1 R3;D3 F9 R7;D1 L9 F7;D7 B9 L7;D9 R9 B7")
local edges = make_group("UR UF UL UB DR DF DL DB FR FL BL BR", "U6 R2;U8 F2;U4 L2;U2 B2;D6 R8;D2 F8;D4 L8;D8 B8;F6 R4;F4 L6;B6 L4;B4 R6")
local centers = make_group("U R F D L B", "U5;R5;F5;D5;L5;B5")
local function normalize(cube)
    for i, p in ipairs(rotation_effects) do
        local candidate, good = permute(cube, p), true
        for face = 1, 6 do
            if candidate:sub((face - 1) * 9 + 5, (face - 1) * 9 + 5) ~= colors:sub(face, face) then
                good = false
                break
            end
        end
        if good then
            return candidate, i
        end
    end
    return nil
end
local function identify(cube, group)
    local result = {}
    for position, stickers in ipairs(group.stickers) do
        result[position] = {id = 0, orientation = 0}
        local found = false
        for id, name in ipairs(group.names) do
            for orientation = 0, #stickers - 1 do
                local same = true
                for i = 1, #stickers do
                    local face = faces:find(name:sub(i, i), 1, true)
                    local at = stickers[(orientation + i - 1) % #stickers + 1]
                    if cube:sub(at, at) ~= colors:sub(face, face) then
                        same = false
                        break
                    end
                end
                if same then
                    result[position] = {id = id, orientation = orientation}
                    found = true
                    break
                end
            end
            if found then
                break
            end
        end
    end
    return result
end
local function cycles(cube, group)
    local where, orientations, seen, written = {}, {}, {}, {}
    for position, piece in ipairs(identify(cube, group)) do
        where[piece.id], orientations[piece.id] = position, piece.orientation
    end
    for first = 1, #group.names do
        if not seen[first] then
            local names, sum, at = {}, 0, first
            while not seen[at] do
                seen[at] = true
                names[#names + 1] = group.names[at]
                sum, at = sum + orientations[at], where[at]
            end
            local mark = ""
            if #group.stickers[1] > 1 then
                mark = ({"", "+", "-"})[sum % #group.stickers[1] + 1]
            end
            if #names > 1 or mark ~= "" then
                written[#written + 1] = "(" .. table.concat(names, " ") .. ")" .. mark
            end
        end
    end
    return #written > 0 and table.concat(written, " ") or "none"
end
local function parity(pieces)
    local result = 0
    for i = 1, #pieces do
        for j = i + 1, #pieces do
            if pieces[i].id > pieces[j].id then
                result = 1 - result
            end
        end
    end
    return result
end
local function check(word)
    if #word ~= 54 then
        return "length " .. #word
    end
    local counts = {0, 0, 0, 0, 0, 0}
    for i = 1, #word do
        local at = colors:find(word:sub(i, i), 1, true)
        if not at then
            return "char " .. i
        end
        counts[at] = counts[at] + 1
    end
    for i, count in ipairs(counts) do
        if count ~= 9 then
            return "count " .. colors:sub(i, i) .. " " .. count
        end
    end
    local normalized = normalize(word)
    if not normalized then
        return "centers"
    end
    local c, e = identify(word, corners), identify(word, edges)
    for i, piece in ipairs(c) do
        if piece.id == 0 then
            return "corner " .. corners.names[i]
        end
    end
    for i, piece in ipairs(e) do
        if piece.id == 0 then
            return "edge " .. edges.names[i]
        end
    end
    for _, pair in ipairs({{corners, c}, {edges, e}}) do
        for id, name in ipairs(pair[1].names) do
            local found = false
            for _, piece in ipairs(pair[2]) do
                if piece.id == id then
                    found = true
                    break
                end
            end
            if not found then
                return "missing " .. name
            end
        end
    end
    c, e = identify(normalized, corners), identify(normalized, edges)
    local twist, flip = 0, 0
    for _, piece in ipairs(c) do
        twist = twist + piece.orientation
    end
    for _, piece in ipairs(e) do
        flip = flip + piece.orientation
    end
    if twist % 3 ~= 0 then
        return "twist"
    end
    if flip % 2 ~= 0 then
        return "flip"
    end
    if parity(c) ~= parity(e) then
        return "parity"
    end
    return nil
end
local function misplaced(cube)
    local count = 0
    for i = 1, 54 do
        local center = ((i - 1) // 9) * 9 + 5
        if cube:sub(i, i) ~= cube:sub(center, center) then
            count = count + 1
        end
    end
    return count
end
local function same_moves(a, b)
    if #a ~= #b then
        return false
    end
    for i = 1, #a do
        if a[i][1] ~= b[i][1] or a[i][2] ~= b[i][2] then
            return false
        end
    end
    return true
end
local function simplify(seq)
    while true do
        local result, start = {}, 1
        while start <= #seq do
            local finish = start + 1
            while finish <= #seq and turns[seq[finish][1]][1] == turns[seq[start][1]][1] do
                finish = finish + 1
            end
            local order, amounts = {}, {}
            for i = start, finish - 1 do
                local letter, amount = seq[i][1], seq[i][2]
                if amounts[letter] == nil then
                    order[#order + 1] = letter
                    amounts[letter] = 0
                end
                amounts[letter] = amounts[letter] + amount
            end
            for _, letter in ipairs(order) do
                if amounts[letter] % 4 ~= 0 then
                    result[#result + 1] = {letter, amounts[letter] % 4}
                end
            end
            start = finish
        end
        if same_moves(seq, result) then
            return result
        end
        seq = result
    end
end
local function gcd(a, b)
    while b ~= 0 do
        a, b = b, a % b
    end
    return a
end
local function order(p)
    local seen, result = {}, 1
    for first = 1, 54 do
        if not seen[first] then
            local length, at = 0, first
            while not seen[at] do
                seen[at] = true
                length = length + 1
                at = p[at]
            end
            result = (result // gcd(result, length)) * length
        end
    end
    return result
end
local function conjugate(rotation, move)
    return by_effect[key(compose(compose(rotation, tables[move[1] .. move[2]]), inverse_permutation(rotation)))]
end
local replacements = {}
for letter, text in pairs({M = "R L' x'", E = "U D' y'", S = "F' B z", r = "L x", l = "R x'", u = "D y", d = "U y'", f = "B z", b = "F z'"}) do
    replacements[letter] = literal_moves(text)
end
local function unrotate(seq)
    local result, rotation = {}, identity()
    for _, move in ipairs(seq) do
        local expanded
        if replacements[move[1]] then
            expanded = copy(replacements[move[1]])
            for _, part in ipairs(expanded) do
                part[2] = part[2] * move[2] % 4
            end
        else
            expanded = {move}
        end
        for _, part in ipairs(expanded) do
            if ("xyz"):find(part[1], 1, true) then
                rotation = compose(rotation, tables[part[1] .. part[2]])
            else
                result[#result + 1] = conjugate(rotation, part)
            end
        end
    end
    for i, p in ipairs(rotation_effects) do
        if key(p) == key(rotation) then
            append(result, rotations[i])
            return result
        end
    end
end
local function search(cube, depth, previous)
    if depth == 0 then
        return misplaced(cube) == 0 and {} or nil
    end
    for i = 1, #faces do
        local face = faces:sub(i, i)
        if face ~= previous and not (previous == "D" and face == "U" or previous == "L" and face == "R" or previous == "B" and face == "F") then
            for amount = 1, 3 do
                local move = {face, amount}
                local rest = search(permute(cube, tables[face .. amount]), depth - 1, face)
                if rest then
                    local result = {move}
                    append(result, rest)
                    return result
                end
            end
        end
    end
    return nil
end
local Parser = {}
Parser.__index = Parser
function Parser:peek()
    return self.line:sub(self.pos, self.pos)
end
function Parser:skip()
    while self:peek() == " " do
        self.pos = self.pos + 1
    end
end
function Parser:syntax()
    bad("syntax at %d", math.min(self.pos, #self.line + 1))
end
function Parser:power(seq)
    local count, current = 1, self:peek()
    if current ~= "" and current >= "1" and current <= "9" then
        count, self.pos = tonumber(current), self.pos + 1
        current = self:peek()
        if current ~= "" and current >= "0" and current <= "9" then
            count, self.pos = 10 * count + tonumber(current), self.pos + 1
        end
    end
    local invert = self:peek() == "'"
    if invert then
        self.pos = self.pos + 1
    end
    local result = {}
    for _ = 1, count do
        append(result, seq)
    end
    return invert and inverse(result) or result
end
function Parser:sequence()
    local result = {}
    while true do
        self:skip()
        local current, part = self:peek(), nil
        if turns[current] then
            self.pos = self.pos + 1
            local amount = 1
            if self:peek() == "2" then
                amount, self.pos = 2, self.pos + 1
            elseif self:peek() == "'" then
                amount, self.pos = 3, self.pos + 1
            end
            part = {{current, amount}}
        elseif current == "(" then
            self.pos = self.pos + 1
            local nested = self:sequence()
            self:skip()
            if self:peek() ~= ")" then
                self:syntax()
            end
            self.pos = self.pos + 1
            part = self:power(nested)
        elseif current == "[" then
            self.pos = self.pos + 1
            local a = self:sequence()
            self:skip()
            local separator = self:peek()
            if separator ~= "," and separator ~= ":" then
                self:syntax()
            end
            self.pos = self.pos + 1
            local b = self:sequence()
            self:skip()
            if self:peek() ~= "]" then
                self:syntax()
            end
            self.pos = self.pos + 1
            local nested = copy(a)
            append(nested, b)
            append(nested, inverse(a))
            if separator == "," then
                append(nested, inverse(b))
            end
            part = self:power(nested)
        elseif current == "{" then
            self.pos = self.pos + 1
            local start = self.pos
            while self:peek() ~= "" and self:peek() >= "a" and self:peek() <= "z" do
                self.pos = self.pos + 1
            end
            local name = self.line:sub(start, self.pos - 1)
            if name == "" or self:peek() ~= "}" then
                self:syntax()
            end
            if not self.macros[name] then
                bad("undefined %s", name)
            end
            self.pos = self.pos + 1
            part = self:power(self.macros[name])
        else
            return result
        end
        append(result, part)
    end
end
function Parser:whole()
    local result = self:sequence()
    self:skip()
    if self:peek() ~= "" then
        self:syntax()
    end
    if #result > 500 then
        bad("too long")
    end
    return result
end
local function name_word(word)
    return #word >= 1 and #word <= 8 and word:match("^[a-z]+$") ~= nil
end
local function number_word(word)
    return #word >= 1 and #word <= 10 and word:match("^[0-9]+$") ~= nil and (#word == 1 or word:sub(1, 1) ~= "0")
end
local function contains(list, value)
    for _, item in ipairs(list) do
        if item == value then
            return true
        end
    end
    return false
end
local no_arguments = {RESET = true, SHOW = true, STATE = true, ISSOLVED = true, HISTORY = true, SOLUTION = true, ANALYZE = true, STAGE = true, MACROS = true}
local word_counts = {CHECK = 1, LOAD = 1, UNDO = 1, REDO = 1, SEARCH = 1, WHERE = 1, SAVE = 1, RESTORE = 1, SCRAMBLE = 2}
local sequence_commands = {APPLY = true, INVERT = true, SIMPLIFY = true, METRICS = true, ORDER = true, CYCLES = true, UNROTATE = true, UNTIL = true}
local head_commands = {DEFINE = true, MIRROR = true, ROTATE = true}
local simulator = {cube = solved, history = {}, redo = {}, macros = {}, saves = {}}
local output = {}
local function emit(pattern, ...)
    output[#output + 1] = string.format(pattern, ...)
end
function simulator:record(seq)
    self.cube = apply(self.cube, seq)
    append(self.history, seq)
    self.redo = {}
end
function simulator:command(line)
    local at = line:find(" ", 1, true)
    local command, arguments = at and line:sub(1, at - 1) or line, at and line:sub(at + 1) or ""
    local no, count, sequence_command, head_command = no_arguments[command], word_counts[command], sequence_commands[command], head_commands[command]
    if not no and not count and not sequence_command and not head_command then
        bad("unknown command %s", command)
    end
    local arguments_words, head, seq_start = words(arguments), "", #command + 2
    local invalid = no and at ~= nil or count and #arguments_words ~= count or head_command and not at
    if not invalid and count then
        if command == "UNDO" or command == "REDO" or command == "SEARCH" or command == "SCRAMBLE" then
            for _, word in ipairs(arguments_words) do
                if not number_word(word) then
                    invalid = true
                end
            end
        end
        if (command == "SAVE" or command == "RESTORE") and not name_word(arguments_words[1]) then
            invalid = true
        end
    end
    if not invalid and head_command then
        head = arguments_words[1] or ""
        seq_start = #command + #head + 3
        if command == "DEFINE" then
            invalid = not name_word(head)
        elseif command == "MIRROR" then
            invalid = not contains({"LR", "UD", "FB"}, head)
        else
            invalid = not contains({"x", "x2", "x'", "y", "y2", "y'", "z", "z2", "z'"}, head)
        end
    end
    if invalid then
        bad("bad arguments")
    end
    local seq = {}
    if sequence_command or head_command then
        seq = setmetatable({line = line, pos = seq_start, macros = self.macros}, Parser):whole()
    end
    local w = arguments_words
    if (command == "UNDO" or command == "REDO") and tonumber(w[1]) < 1
    or command == "SEARCH" and tonumber(w[1]) > 4
    or command == "SCRAMBLE" and (tonumber(w[1]) < 1 or tonumber(w[1]) > 50 or tonumber(w[2]) < 1 or tonumber(w[2]) > 2147483646) then
        bad("bad value")
    end
    if command == "WHERE" and not contains(corners.names, w[1]) and not contains(edges.names, w[1]) then
        bad("unknown piece %s", w[1])
    end
    if command == "RESET" then
        self.cube, self.history, self.redo = solved, {}, {}
        emit("reset")
    elseif command == "SHOW" then
        for row = 1, 9 do
            local cells, prefix = {}, ""
            if row <= 3 or row >= 7 then
                local face, r = 0, row - 1
                if row >= 7 then
                    face, r = 3, row - 7
                end
                prefix = "      "
                for column = 1, 3 do
                    local index = face * 9 + r * 3 + column
                    cells[#cells + 1] = self.cube:sub(index, index)
                end
            else
                for _, face in ipairs({4, 2, 1, 5}) do
                    for column = 1, 3 do
                        local index = face * 9 + (row - 4) * 3 + column
                        cells[#cells + 1] = self.cube:sub(index, index)
                    end
                end
            end
            emit("%s%s", prefix, table.concat(cells, " "))
        end
    elseif command == "STATE" then
        emit("state %s", self.cube)
    elseif command == "ISSOLVED" then
        local n = misplaced(self.cube)
        if n == 0 then
            emit("solved")
        else
            emit("unsolved %d", n)
        end
    elseif command == "HISTORY" then
        emit("history %s", sequence_text(self.history))
    elseif command == "SOLUTION" then
        emit("solution %s", sequence_text(simplify(inverse(self.history))))
    elseif command == "ANALYZE" or command == "STAGE" or command == "WHERE" then
        local cube, rotation = normalize(self.cube)
        if command == "ANALYZE" then
            emit("rotation %s", #rotations[rotation] == 0 and "none" or moves_text(rotations[rotation]))
            emit("corners %s", cycles(cube, corners))
            emit("edges %s", cycles(cube, edges))
        elseif command == "WHERE" then
            local group, orientation = edges, "flip"
            if contains(corners.names, w[1]) then
                group, orientation = corners, "twist"
            end
            for position, piece in ipairs(identify(cube, group)) do
                if group.names[piece.id] == w[1] then
                    emit("%s at %s %s %d", w[1], group.names[position], orientation, piece.orientation)
                    break
                end
            end
        else
            local c, e = identify(cube, corners), identify(cube, edges)
            local cross, slots, top = 0, 0, 0
            for i = 5, 8 do
                if e[i].id == i and e[i].orientation == 0 then
                    cross = cross + 1
                end
                if c[i].id == i and c[i].orientation == 0 and e[i + 4].id == i + 4 and e[i + 4].orientation == 0 then
                    slots = slots + 1
                end
            end
            for i = 1, 9 do
                if cube:sub(i, i) == "W" then
                    top = top + 1
                end
            end
            local stage = "none"
            if misplaced(cube) == 0 then
                stage = "solved"
            elseif cross == 4 and slots == 4 and top == 9 then
                stage = "oll"
            elseif cross == 4 and slots == 4 then
                stage = "f2l"
            elseif cross == 4 then
                stage = "cross"
            end
            emit("stage %s cross %d slots %d top %d", stage, cross, slots, top)
        end
    elseif command == "MACROS" then
        local names = {}
        for name in pairs(self.macros) do
            names[#names + 1] = name
        end
        table.sort(names)
        emit("macros %d", #names)
        for _, name in ipairs(names) do
            emit("macro %s %s", name, sequence_text(self.macros[name]))
        end
    elseif command == "CHECK" or command == "LOAD" then
        local invalidity = check(w[1])
        if command == "CHECK" then
            if invalidity then
                emit("invalid %s", invalidity)
            else
                emit("valid")
            end
        else
            if invalidity then
                bad("invalid %s", invalidity)
            end
            self.cube, self.history, self.redo = w[1], {}, {}
            emit("loaded")
        end
    elseif command == "UNDO" or command == "REDO" then
        local source = command == "UNDO" and self.history or self.redo
        if #source == 0 then
            bad("nothing to %s", command == "UNDO" and "undo" or "redo")
        end
        local count_moves = math.min(tonumber(w[1]), #source)
        for _ = 1, count_moves do
            local move = table.remove(source)
            if command == "UNDO" then
                self.cube = permute(self.cube, tables[move[1] .. (4 - move[2])])
                self.redo[#self.redo + 1] = move
            else
                self.cube = permute(self.cube, tables[move[1] .. move[2]])
                self.history[#self.history + 1] = move
            end
        end
        emit("%s %d", command == "UNDO" and "undone" or "redone", count_moves)
    elseif command == "SEARCH" then
        for depth = 0, tonumber(w[1]) do
            local found = search(self.cube, depth, nil)
            if found then
                emit("found %s", sequence_text(found))
                return
            end
        end
        emit("not found")
    elseif command == "SAVE" then
        self.saves[w[1]] = {cube = self.cube, history = copy(self.history)}
        emit("saved %s", w[1])
    elseif command == "RESTORE" then
        local save = self.saves[w[1]]
        if not save then
            bad("no save %s", w[1])
        end
        self.cube, self.history, self.redo = save.cube, copy(save.history), {}
        emit("restored %s", w[1])
    elseif command == "SCRAMBLE" then
        local scramble, seed = {}, tonumber(w[2])
        for i = 1, tonumber(w[1]) do
            local usable = {}
            for j = 1, #faces do
                local face = faces:sub(j, j)
                if not (i >= 2 and face == scramble[i - 1][1]) and not (i >= 3 and turns[scramble[i - 1][1]][1] == turns[scramble[i - 2][1]][1] and turns[face][1] == turns[scramble[i - 1][1]][1]) then
                    usable[#usable + 1] = face
                end
            end
            seed = 48271 * seed % 2147483647
            local face = usable[seed % #usable + 1]
            seed = 48271 * seed % 2147483647
            scramble[#scramble + 1] = {face, ({1, 3, 2})[seed % 3 + 1]}
        end
        self:record(scramble)
        emit("scramble %s", moves_text(scramble))
    elseif command == "APPLY" then
        self:record(seq)
        emit("applied %d", #seq)
    elseif command == "INVERT" then
        emit("inverse %s", sequence_text(inverse(seq)))
    elseif command == "SIMPLIFY" then
        emit("simplified %s", sequence_text(simplify(seq)))
    elseif command == "METRICS" then
        local htm, qtm, stm = 0, 0, 0
        for _, move in ipairs(seq) do
            if not ("xyz"):find(move[1], 1, true) then
                local h, q = ("MES"):find(move[1], 1, true) and 2 or 1, move[2] == 2 and 2 or 1
                htm, qtm, stm = htm + h, qtm + h * q, stm + 1
            end
        end
        emit("metrics htm %d qtm %d stm %d etm %d", htm, qtm, stm, #seq)
    elseif command == "ORDER" then
        emit("order %d", order(effect(seq)))
    elseif command == "CYCLES" then
        local cube = apply(solved, seq)
        emit("corners %s", cycles(cube, corners))
        emit("edges %s", cycles(cube, edges))
        emit("centers %s", cycles(cube, centers))
    elseif command == "UNROTATE" then
        emit("unrotated %s", sequence_text(unrotate(seq)))
    elseif command == "UNTIL" then
        local p, cube = effect(seq), self.cube
        for k = 1, order(p) do
            cube = permute(cube, p)
            if misplaced(cube) == 0 then
                emit("until %d", k)
                return
            end
        end
        emit("until never")
    elseif command == "DEFINE" then
        self.macros[head] = copy(seq)
        emit("defined %s %d", head, #seq)
    elseif command == "MIRROR" then
        local axis = ({LR = 1, UD = 2, FB = 3})[head]
        local opposites = {R = "L", L = "R", U = "D", D = "U", F = "B", B = "F", r = "l", l = "r", u = "d", d = "u", f = "b", b = "f"}
        local mirrored = copy(seq)
        for _, move in ipairs(mirrored) do
            if turns[move[1]][1] ~= axis then
                move[2] = 4 - move[2]
            elseif opposites[move[1]] then
                move[1], move[2] = opposites[move[1]], 4 - move[2]
            end
        end
        emit("mirror %s", sequence_text(mirrored))
    elseif command == "ROTATE" then
        local rotation, rotated = effect(literal_moves(head)), {}
        for i, move in ipairs(seq) do
            rotated[i] = conjugate(rotation, move)
        end
        emit("rotated %s", sequence_text(rotated))
    end
end
local n = tonumber(io.read("*l"))
for _ = 1, n do
    local line = io.read("*l")
    local ok, message = pcall(function()
        simulator:command(line)
    end)
    if not ok then
        emit("error: %s", message)
    end
end
io.write(table.concat(output, "\n"), "\n")
