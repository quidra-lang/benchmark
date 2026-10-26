local function leaf(kind)
    return {kind = kind}
end
local function unary(child)
    return {kind = "~", left = child}
end
local function binary(kind, left, right)
    return {kind = kind, left = left, right = right}
end
local priorities = {["<->"] = 1, ["->"] = 2, ["|"] = 3, ["^"] = 4, ["&"] = 5}
local function precedence(kind)
    return priorities[kind] or 0
end
local function notation(node)
    if not node.left then
        return node.kind
    end
    if node.kind == "~" then
        local text = notation(node.left)
        return "~" .. (precedence(node.left.kind) > 0 and "(" .. text .. ")" or text)
    end
    local left, right = notation(node.left), notation(node.right)
    local p = precedence(node.kind)
    if
        precedence(node.left.kind) > 0 and
            (precedence(node.left.kind) < p or node.kind == "->" and node.left.kind == "->")
     then
        left = "(" .. left .. ")"
    end
    if
        precedence(node.right.kind) > 0 and
            (precedence(node.right.kind) < p or node.kind == node.right.kind and node.kind ~= "->")
     then
        right = "(" .. right .. ")"
    end
    return left .. " " .. node.kind .. " " .. right
end
local function equal(a, b)
    return a == b or
        a.kind == b.kind and
            (not a.left or equal(a.left, b.left) and (not a.right or equal(a.right, b.right)))
end
local function variable(text)
    return #text == 1 and text >= "A" and text <= "Z"
end
local function valid_name(text)
    return #text >= 1 and #text <= 8 and text:match("^[a-z][a-z0-9]*$") ~= nil
end
local function fail(format, ...)
    error({reason = string.format(format, ...)}, 0)
end
local function contains(items, value)
    for _, item in ipairs(items) do
        if item == value then
            return true
        end
    end
    return false
end
local function words(text)
    local result = {}
    for word in text:gmatch("%S+") do
        result[#result + 1] = word
    end
    return result
end
local function lexical(text, start)
    local result, i = {}, 1
    while i <= #text do
        local c, begin = text:sub(i, i), i
        if c == " " then
            i = i + 1
        else
            if text:sub(i, i + 2) == "<->" then
                i = i + 3
            elseif text:sub(i, i + 1) == "->" then
                i = i + 2
            elseif c >= "a" and c <= "z" then
                repeat
                    i = i + 1
                    c = text:sub(i, i)
                until c == "" or not (c >= "a" and c <= "z" or c >= "0" and c <= "9")
            elseif ("ABCDEFGHIJKLMNOPQRSTUVWXYZ01~&^|()"):find(c, 1, true) then
                i = i + 1
            else
                fail("invalid character '%s' at %d", c, start + i - 1)
            end
            result[#result + 1] = {text = text:sub(begin, i - 1), position = start + begin - 1}
        end
    end
    return result
end
local Parser = {}
Parser.__index = Parser
function Parser:unexpected()
    local token = self.tokens[self.at]
    if not token then
        fail("unexpected end of formula at %d", self.ending)
    end
    fail("unexpected '%s' at %d", token.text, token.position)
end
function Parser:unary()
    local token = self.tokens[self.at]
    if not token then
        self:unexpected()
    end
    if token.text == "~" then
        self.at = self.at + 1
        return unary(self:unary())
    end
    if token.text == "(" then
        self.at = self.at + 1
        local value = self:expression(1)
        if not self.tokens[self.at] or self.tokens[self.at].text ~= ")" then
            self:unexpected()
        end
        self.at = self.at + 1
        return value
    end
    if variable(token.text) or token.text == "0" or token.text == "1" then
        self.at = self.at + 1
        return leaf(token.text)
    end
    if token.text:sub(1, 1) >= "a" and token.text:sub(1, 1) <= "z" then
        local value = self.names[token.text]
        if not value then
            fail("undefined name '%s' at %d", token.text, token.position)
        end
        self.at = self.at + 1
        return value
    end
    self:unexpected()
end
function Parser:expression(minimum)
    local value = self:unary()
    while self.tokens[self.at] do
        local operator = self.tokens[self.at].text
        local priority = precedence(operator)
        if priority < minimum then
            break
        end
        self.at = self.at + 1
        value =
            binary(operator, value, self:expression(operator == "->" and priority or priority + 1))
    end
    return value
end
local function parse(text, start, names)
    local parser =
        setmetatable(
        {tokens = lexical(text, start), at = 1, ending = start + #text, names = names},
        Parser
    )
    local value = parser:expression(1)
    if parser.tokens[parser.at] then
        parser:unexpected()
    end
    return value
end
local function variable_list(...)
    local set = {}
    local function walk(node)
        if variable(node.kind) then
            set[node.kind] = true
        end
        if node.left then
            walk(node.left)
        end
        if node.right then
            walk(node.right)
        end
    end
    for _, formula in ipairs({...}) do
        walk(formula)
    end
    local result = {}
    for name in pairs(set) do
        result[#result + 1] = name
    end
    table.sort(result)
    return result
end
local function size(node)
    return not node.left and 1 or not node.right and 1 + size(node.left) or
        1 + size(node.left) + size(node.right)
end
local function depth(node)
    return not node.left and 1 or not node.right and 1 + depth(node.left) or
        1 + math.max(depth(node.left), depth(node.right))
end
local function truth(node, assignment)
    if variable(node.kind) then
        return assignment[node.kind]
    end
    if node.kind == "0" then
        return 0
    elseif node.kind == "1" then
        return 1
    end
    local a = truth(node.left, assignment)
    if node.kind == "~" then
        return 1 - a
    end
    local b = truth(node.right, assignment)
    if node.kind == "&" then
        return a & b
    elseif node.kind == "|" then
        return a | b
    elseif node.kind == "^" then
        return a ~ b
    elseif node.kind == "->" then
        return (1 - a) | b
    else
        return 1 - (a ~ b)
    end
end
local function truth_table(node, names)
    local result = {}
    for row = 0, (1 << #names) - 1 do
        local assignment = {}
        for i, name in ipairs(names) do
            assignment[name] = (row >> (#names - i)) & 1
        end
        result[row + 1] = truth(node, assignment)
    end
    return result
end
local function assignment_text(names, row)
    local parts = {}
    for i, name in ipairs(names) do
        parts[#parts + 1] = name .. "=" .. ((row >> (#names - i)) & 1)
    end
    return "{" .. table.concat(parts, " ") .. "}"
end
local function bit_pattern(row, n)
    local parts = {}
    for i = 1, n do
        parts[i] = tostring((row >> (n - i)) & 1)
    end
    return table.concat(parts)
end
local function literal_count(pattern)
    local _, count = pattern:gsub("%-", "")
    return #pattern - count
end
local pattern_rank = {["1"] = 0, ["0"] = 1, ["-"] = 2}
local function pattern_less(a, b)
    for i = 1, #a do
        local x, y = pattern_rank[a:sub(i, i)], pattern_rank[b:sub(i, i)]
        if x ~= y then
            return x < y
        end
    end
    return false
end
local function sort_patterns(patterns)
    table.sort(patterns, pattern_less)
end
local function flipped(pattern)
    return (pattern:gsub("[01]", {["0"] = "1", ["1"] = "0"}))
end
local function term_text(pattern, names, clause)
    local literals = {}
    for i = 1, #pattern do
        local c = pattern:sub(i, i)
        if c ~= "-" then
            literals[#literals + 1] = (c == "0" and "~" or "") .. names[i]
        end
    end
    if #literals == 0 then
        return clause and "0" or "1"
    end
    return table.concat(literals, clause and " | " or " & ")
end
local function form_text(patterns, names, clauses)
    if #patterns == 0 then
        return clauses and "1" or "0"
    end
    local parts = {}
    for _, pattern in ipairs(patterns) do
        local text = term_text(pattern, names, clauses)
        if clauses and #patterns >= 2 and literal_count(pattern) >= 2 then
            text = "(" .. text .. ")"
        end
        parts[#parts + 1] = text
    end
    return table.concat(parts, clauses and " & " or " | ")
end
local function reduce_negation(node)
    if node.kind == "0" then
        return leaf("1")
    elseif node.kind == "1" then
        return leaf("0")
    elseif node.kind == "~" then
        return node.left
    else
        return unary(node)
    end
end
local function simplify_binary(operator, a, b)
    local same = equal(a, b)
    local complement = a.kind == "~" and equal(a.left, b) or b.kind == "~" and equal(b.left, a)
    if operator == "&" then
        if a.kind == "0" or b.kind == "0" then
            return leaf("0")
        elseif a.kind == "1" then
            return b
        elseif b.kind == "1" or same then
            return a
        elseif complement then
            return leaf("0")
        end
    elseif operator == "|" then
        if a.kind == "1" or b.kind == "1" then
            return leaf("1")
        elseif a.kind == "0" then
            return b
        elseif b.kind == "0" or same then
            return a
        elseif complement then
            return leaf("1")
        end
    elseif operator == "^" then
        if a.kind == "0" then
            return b
        elseif b.kind == "0" then
            return a
        elseif a.kind == "1" then
            return reduce_negation(b)
        elseif b.kind == "1" then
            return reduce_negation(a)
        elseif same then
            return leaf("0")
        elseif complement then
            return leaf("1")
        end
    elseif operator == "->" then
        if a.kind == "0" or b.kind == "1" then
            return leaf("1")
        elseif a.kind == "1" then
            return b
        elseif b.kind == "0" then
            return reduce_negation(a)
        elseif same then
            return leaf("1")
        elseif complement then
            return b
        end
    elseif operator == "<->" then
        if a.kind == "1" then
            return b
        elseif b.kind == "1" then
            return a
        elseif a.kind == "0" then
            return reduce_negation(b)
        elseif b.kind == "0" then
            return reduce_negation(a)
        elseif same then
            return leaf("1")
        elseif complement then
            return leaf("0")
        end
    end
    return binary(operator, a, b)
end
local function simplify(node, assignments)
    if not node.left then
        return assignments and assignments[node.kind] and leaf(assignments[node.kind]) or node
    end
    local a = simplify(node.left, assignments)
    if node.kind == "~" then
        return reduce_negation(a)
    end
    return simplify_binary(node.kind, a, simplify(node.right, assignments))
end
local function nnf(node, positive, memo)
    memo[node] = memo[node] or {}
    local sign = positive and 1 or 2
    if memo[node][sign] then
        return memo[node][sign]
    end
    local kind, result = node.kind
    if kind == "0" or kind == "1" then
        result = positive and node or reduce_negation(node)
    elseif kind == "~" then
        result = nnf(node.left, not positive, memo)
    elseif kind == "&" or kind == "|" then
        local operator = kind
        if not positive then
            operator = kind == "&" and "|" or "&"
        end
        result = binary(operator, nnf(node.left, positive, memo), nnf(node.right, positive, memo))
    elseif kind == "->" then
        result =
            binary(
            positive and "|" or "&",
            nnf(node.left, not positive, memo),
            nnf(node.right, positive, memo)
        )
    elseif kind == "^" or kind == "<->" then
        local same_sign = positive
        if kind == "^" then
            same_sign = not same_sign
        end
        result =
            binary(
            "|",
            binary("&", nnf(node.left, true, memo), nnf(node.right, same_sign, memo)),
            binary("&", nnf(node.left, false, memo), nnf(node.right, not same_sign, memo))
        )
    else
        result = positive and node or unary(node)
    end
    memo[node][sign] = result
    return result
end
local function dual(node)
    if variable(node.kind) then
        return node
    elseif node.kind == "0" or node.kind == "1" then
        return reduce_negation(node)
    elseif node.kind == "~" then
        return unary(dual(node.left))
    end
    local a, b = dual(node.left), dual(node.right)
    local swap = {["&"] = "|", ["|"] = "&", ["^"] = "<->", ["<->"] = "^"}
    if node.kind == "->" then
        return binary("&", unary(a), b)
    end
    return binary(swap[node.kind], a, b)
end
local function covers(pattern, row)
    local bits = bit_pattern(row, #pattern)
    for i = 1, #pattern do
        local c = pattern:sub(i, i)
        if c ~= "-" and c ~= bits:sub(i, i) then
            return false
        end
    end
    return true
end
local function pattern_subset(a, b)
    for i = 1, #a do
        local c = a:sub(i, i)
        if c ~= "-" and c ~= b:sub(i, i) then
            return false
        end
    end
    return true
end
local function tidy(patterns)
    local unique, result = {}, {}
    for _, pattern in ipairs(patterns) do
        if not contains(unique, pattern) then
            unique[#unique + 1] = pattern
        end
    end
    for i, pattern in ipairs(unique) do
        local redundant = false
        for j, other in ipairs(unique) do
            if i ~= j and pattern_subset(other, pattern) then
                redundant = true
                break
            end
        end
        if not redundant then
            result[#result + 1] = pattern
        end
    end
    return result
end
local function merge_clauses(a, b)
    local result = {}
    for i = 1, #a do
        local x, y = a:sub(i, i), b:sub(i, i)
        if x ~= "-" and y ~= "-" and x ~= y then
            return nil
        end
        result[i] = y ~= "-" and y or x
    end
    return table.concat(result)
end
local function clauses(node, names, memo)
    if memo[node] then
        return memo[node]
    end
    local empty = string.rep("-", #names)
    local result = {}
    if node.kind == "1" then
    elseif node.kind == "0" then
        result = {empty}
    elseif node.kind == "&" then
        for _, pattern in ipairs(clauses(node.left, names, memo)) do
            result[#result + 1] = pattern
        end
        for _, pattern in ipairs(clauses(node.right, names, memo)) do
            result[#result + 1] = pattern
        end
        result = tidy(result)
    elseif node.kind == "|" then
        for _, a in ipairs(clauses(node.left, names, memo)) do
            for _, b in ipairs(clauses(node.right, names, memo)) do
                local merged = merge_clauses(a, b)
                if merged then
                    result[#result + 1] = merged
                end
            end
        end
        result = tidy(result)
    else
        local name, sign = node.kind, "1"
        if node.kind == "~" then
            name, sign = node.left.kind, "0"
        end
        local pattern = {}
        for i, variable_name in ipairs(names) do
            pattern[i] = variable_name == name and sign or "-"
        end
        result = {table.concat(pattern)}
    end
    memo[node] = result
    return result
end
local function list_copy(list)
    local result = {}
    for i, value in ipairs(list) do
        result[i] = value
    end
    return result
end
local function minimize(values, dc, names, pos)
    local on, stage = {}, {}
    for index, value in ipairs(values) do
        if value == 1 and (not dc or dc[index] == 0) then
            on[#on + 1] = index - 1
        end
        if value == 1 or dc and dc[index] == 1 then
            stage[#stage + 1] = bit_pattern(index - 1, #names)
        end
    end
    local out, primes, level = {}, {}, 0
    while true do
        local used, next_stage = {}, {}
        for i, a in ipairs(stage) do
            for j = i + 1, #stage do
                local b, differing = stage[j], nil
                for k = 1, #a do
                    local x, y = a:sub(k, k), b:sub(k, k)
                    if x ~= y then
                        if x == "-" or y == "-" or differing then
                            differing = false
                            break
                        end
                        differing = k
                    end
                end
                if differing then
                    local pattern = a:sub(1, differing - 1) .. "-" .. a:sub(differing + 1)
                    used[a], used[b] = true, true
                    if not contains(next_stage, pattern) then
                        next_stage[#next_stage + 1] = pattern
                    end
                end
            end
        end
        local count = 0
        for _, pattern in ipairs(stage) do
            if not used[pattern] then
                primes[#primes + 1] = pattern
                count = count + 1
            end
        end
        if not pos then
            out[#out + 1] = string.format("stage %d: implicants %d primes %d", level, #stage, count)
        end
        if #next_stage == 0 then
            break
        end
        stage, level = next_stage, level + 1
    end
    local target = {}
    for _, pattern in ipairs(primes) do
        for _, row in ipairs(on) do
            if covers(pattern, row) then
                target[#target + 1] = pattern
                break
            end
        end
    end
    sort_patterns(target)
    local essential = {}
    for _, row in ipairs(on) do
        local options = {}
        for _, pattern in ipairs(target) do
            if covers(pattern, row) then
                options[#options + 1] = pattern
            end
        end
        if #options == 1 and not contains(essential, options[1]) then
            essential[#essential + 1] = options[1]
        end
    end
    sort_patterns(essential)
    local optional = {}
    for _, pattern in ipairs(target) do
        if not contains(essential, pattern) then
            optional[#optional + 1] = pattern
        end
    end
    local best, best_count, best_literals = nil, math.huge, math.huge
    for mask = 0, (1 << #optional) - 1 do
        local chosen = list_copy(essential)
        for i, pattern in ipairs(optional) do
            if (mask >> (i - 1)) & 1 ~= 0 then
                chosen[#chosen + 1] = pattern
            end
        end
        local valid = true
        for _, row in ipairs(on) do
            local found = false
            for _, pattern in ipairs(chosen) do
                if covers(pattern, row) then
                    found = true
                    break
                end
            end
            if not found then
                valid = false
                break
            end
        end
        if valid then
            local literals = 0
            for _, pattern in ipairs(chosen) do
                literals = literals + literal_count(pattern)
            end
            local candidate = list_copy(chosen)
            if pos then
                for i, pattern in ipairs(candidate) do
                    candidate[i] = flipped(pattern)
                end
            end
            sort_patterns(candidate)
            local better =
                #chosen < best_count or #chosen == best_count and literals < best_literals
            if #chosen == best_count and literals == best_literals then
                for i, pattern in ipairs(candidate) do
                    if pattern ~= best[i] then
                        better = pattern_less(pattern, best[i])
                        break
                    end
                end
            end
            if better then
                best, best_count, best_literals = candidate, #chosen, literals
            end
        end
    end
    if pos then
        return {
            "minimal: " .. form_text(best, names, true),
            string.format("clauses %d literals %d", best_count, best_literals)
        }
    end
    local function terms(patterns)
        if #patterns == 0 then
            return "none"
        end
        local result = {}
        for _, pattern in ipairs(patterns) do
            result[#result + 1] = term_text(pattern, names, false)
        end
        return table.concat(result, ", ")
    end
    out[#out + 1] = "primes: " .. terms(target)
    out[#out + 1] = "essential: " .. terms(essential)
    out[#out + 1] = "minimal: " .. form_text(best, names, false)
    out[#out + 1] = string.format("terms %d literals %d", best_count, best_literals)
    return out
end
local function coefficients(values, n)
    local result = list_copy(values)
    for bit = 0, n - 1 do
        for row = 0, #values - 1 do
            if (row >> bit) & 1 ~= 0 then
                result[row + 1] = result[row + 1] ~ result[(row ~ (1 << bit)) + 1]
            end
        end
    end
    return result
end
local function bit_count(value)
    local count = 0
    while value > 0 do
        count = count + (value & 1)
        value = value >> 1
    end
    return count
end
local commands =
    words(
    "DEF DEFSUM DEL LIST PRINT TABLE MINTERMS MAXTERMS DNF CNF NNF DUAL ANF SIMPLIFY RESTRICT COFACTOR MINIMIZE MINDC MINPOS KMAP SAT TAUT COUNT EQUIV IMPLIES PROPS BDD CLAUSES DP"
)
local truth_commands =
    words(
    "TABLE MINTERMS MAXTERMS DNF CNF ANF SAT TAUT COUNT EQUIV IMPLIES PROPS KMAP BDD MINIMIZE MINDC MINPOS"
)
local Workbench = {}
Workbench.__index = Workbench
function Workbench:command(line)
    local separator = line:find(" ", 1, true)
    local command, argument = line, ""
    if separator then
        command, argument = line:sub(1, separator - 1), line:sub(separator + 1)
    end
    if not contains(commands, command) then
        fail("unknown command %s", command)
    end
    if command == "LIST" then
        if separator then
            fail("unexpected argument")
        end
        local names = {}
        for name in pairs(self.names) do
            names[#names + 1] = name
        end
        table.sort(names)
        local out = {"names: " .. #names}
        for _, name in ipairs(names) do
            out[#out + 1] = name .. " = " .. notation(self.names[name])
        end
        return out
    end
    if not separator then
        fail("missing argument")
    end
    if command == "DEF" then
        local space = argument:find(" ", 1, true)
        if not space then
            fail("missing argument")
        end
        local name = argument:sub(1, space - 1)
        if not valid_name(name) then
            fail("invalid name '%s'", name)
        end
        local formula = parse(argument:sub(space + 1), #name + 6, self.names)
        local prefix = self.names[name] and "redefined" or "defined"
        self.names[name] = formula
        return {prefix .. " " .. name .. " = " .. notation(formula)}
    elseif command == "DEL" then
        if not valid_name(argument) then
            fail("invalid name '%s'", argument)
        end
        if not self.names[argument] then
            fail("undefined name '%s'", argument)
        end
        self.names[argument] = nil
        return {"deleted " .. argument}
    elseif command == "DEFSUM" then
        local semicolon = argument:find(";", 1, true)
        if not semicolon then
            fail("missing ';'")
        end
        local front = words(argument:sub(1, semicolon - 1))
        if #front == 0 then
            fail("missing argument")
        end
        local name = table.remove(front, 1)
        if not valid_name(name) then
            fail("invalid name '%s'", name)
        end
        if #front == 0 then
            fail("bad variable list")
        end
        for i, text in ipairs(front) do
            if not variable(text) or i > 1 and text <= front[i - 1] then
                fail("bad variable list")
            end
        end
        if #front >= 9 then
            fail("too many variables: %d", #front)
        end
        local previous, formula = -1, nil
        for _, word in ipairs(words(argument:sub(semicolon + 1))) do
            local row = tonumber(word)
            if
                not word:match("^%d+$") or word ~= "0" and word:sub(1, 1) == "0" or not row or
                    row >= (1 << #front) or
                    row <= previous
             then
                fail("bad minterm '%s'", word)
            end
            previous = row
            local product
            for i, variable_name in ipairs(front) do
                local literal = leaf(variable_name)
                if (row >> (#front - i)) & 1 == 0 then
                    literal = unary(literal)
                end
                product = product and binary("&", product, literal) or literal
            end
            formula = formula and binary("|", formula, product) or product
        end
        formula = formula or leaf("0")
        local prefix = self.names[name] and "redefined" or "defined"
        self.names[name] = formula
        return {prefix .. " " .. name .. " = " .. notation(formula)}
    end
    local front, back, start, back_start = argument, "", #command + 2, 0
    if contains({"RESTRICT", "COFACTOR", "MINDC", "EQUIV", "IMPLIES"}, command) then
        local semicolon = argument:find(";", 1, true)
        if not semicolon then
            fail("missing ';'")
        end
        front, back, back_start =
            argument:sub(1, semicolon - 1),
            argument:sub(semicolon + 1),
            start + semicolon
    end
    local formula = parse(front, start, self.names)
    local second
    if command == "MINDC" or command == "EQUIV" or command == "IMPLIES" then
        second = parse(back, back_start, self.names)
    end
    if command == "RESTRICT" then
        local assignments, parts = {}, words(back)
        if #parts == 0 then
            fail("missing assignment")
        end
        for _, word in ipairs(parts) do
            if
                #word ~= 3 or not variable(word:sub(1, 1)) or word:sub(2, 2) ~= "=" or
                    word:sub(3, 3) ~= "0" and word:sub(3, 3) ~= "1"
             then
                fail("bad assignment '%s'", word)
            end
            local name = word:sub(1, 1)
            if assignments[name] then
                fail("duplicate variable %s", name)
            end
            assignments[name] = word:sub(3)
        end
        return {"restricted: " .. notation(simplify(formula, assignments))}
    elseif command == "COFACTOR" then
        local parts = words(back)
        if #parts ~= 1 or not variable(parts[1]) then
            fail("bad variable")
        end
        local name = parts[1]
        local one, zero = simplify(formula, {[name] = "1"}), simplify(formula, {[name] = "0"})
        return {
            "cofactor " .. name .. "=1: " .. notation(one),
            "cofactor " .. name .. "=0: " .. notation(zero),
            "difference: " .. notation(simplify_binary("^", one, zero))
        }
    end
    local names = second and variable_list(formula, second) or variable_list(formula)
    if contains(truth_commands, command) and #names >= 9 then
        fail("too many variables: %d", #names)
    end
    if command == "PRINT" then
        return {
            "formula: " .. notation(formula),
            "variables: " .. (#names == 0 and "none" or table.concat(names, " ")),
            string.format("size %d depth %d", size(formula), depth(formula))
        }
    elseif command == "SIMPLIFY" then
        return {"simplified: " .. notation(simplify(formula))}
    elseif command == "NNF" then
        return {"nnf: " .. notation(nnf(formula, true, {}))}
    elseif command == "DUAL" then
        return {"dual: " .. notation(dual(formula))}
    elseif command == "CLAUSES" or command == "DP" then
        local set = clauses(nnf(formula, true, {}), names, {})
        sort_patterns(set)
        if command == "CLAUSES" then
            return {"clauses: " .. form_text(set, names, true)}
        end
        local out = {"start: clauses " .. #set}
        local empty = string.rep("-", #names)
        for i, name in ipairs(names) do
            if #set == 0 or contains(set, empty) then
                break
            end
            local p, q, rest = {}, {}, {}
            for _, pattern in ipairs(set) do
                local c = pattern:sub(i, i)
                local target = c == "1" and p or c == "0" and q or rest
                target[#target + 1] = pattern
            end
            local resolvents = {}
            for _, a in ipairs(p) do
                for _, b in ipairs(q) do
                    local merged =
                        merge_clauses(
                        a:sub(1, i - 1) .. "-" .. a:sub(i + 1),
                        b:sub(1, i - 1) .. "-" .. b:sub(i + 1)
                    )
                    if merged and not contains(resolvents, merged) then
                        resolvents[#resolvents + 1] = merged
                    end
                end
            end
            for _, pattern in ipairs(resolvents) do
                rest[#rest + 1] = pattern
            end
            set = tidy(rest)
            out[#out + 1] =
                string.format("eliminate %s: resolvents %d clauses %d", name, #resolvents, #set)
        end
        out[#out + 1] = "result: " .. (contains(set, empty) and "unsatisfiable" or "satisfiable")
        return out
    end
    local values = truth_table(formula, names)
    local models, false_rows = {}, {}
    for index, value in ipairs(values) do
        local target = value == 1 and models or false_rows
        target[#target + 1] = index - 1
    end
    local function row_patterns(rows, flip)
        local result = {}
        for _, row in ipairs(rows) do
            local pattern = bit_pattern(row, #names)
            result[#result + 1] = flip and flipped(pattern) or pattern
        end
        return result
    end
    if command == "TABLE" then
        local out = {(#names == 0 and "" or table.concat(names, " ") .. " ") .. "| F"}
        for index, value in ipairs(values) do
            local parts = {}
            for c in bit_pattern(index - 1, #names):gmatch(".") do
                parts[#parts + 1] = c
            end
            parts[#parts + 1] = "|"
            parts[#parts + 1] = value
            out[#out + 1] = table.concat(parts, " ")
        end
        return out
    elseif command == "MINTERMS" or command == "MAXTERMS" then
        local rows = command == "MINTERMS" and models or false_rows
        return {command:lower() .. ": " .. (#rows == 0 and "none" or table.concat(rows, " "))}
    elseif command == "DNF" then
        return {"dnf: " .. form_text(row_patterns(models), names, false)}
    elseif command == "CNF" then
        return {"cnf: " .. form_text(row_patterns(false_rows, true), names, true)}
    elseif command == "ANF" then
        local patterns = {}
        for index, coefficient in ipairs(coefficients(values, #names)) do
            if coefficient == 1 then
                patterns[#patterns + 1] = (bit_pattern(index - 1, #names):gsub("0", "-"))
            end
        end
        table.sort(
            patterns,
            function(a, b)
                local x, y = literal_count(a), literal_count(b)
                return x < y or x == y and pattern_less(a, b)
            end
        )
        local parts = {}
        for _, pattern in ipairs(patterns) do
            parts[#parts + 1] = term_text(pattern, names, false)
        end
        return {"anf: " .. (#parts == 0 and "0" or table.concat(parts, " ^ "))}
    elseif command == "SAT" then
        return {
            #models == 0 and "unsatisfiable" or "satisfiable: " .. assignment_text(names, models[1])
        }
    elseif command == "TAUT" then
        return {
            #false_rows == 0 and "tautology" or
                "not a tautology: " .. assignment_text(names, false_rows[1])
        }
    elseif command == "COUNT" then
        return {string.format("models: %d of %d", #models, #values)}
    elseif command == "EQUIV" or command == "IMPLIES" then
        local other = truth_table(second, names)
        for index, value in ipairs(values) do
            if command == "EQUIV" and value ~= other[index] then
                return {
                    string.format(
                        "not equivalent: %s f=%d g=%d",
                        assignment_text(names, index - 1),
                        value,
                        other[index]
                    )
                }
            end
            if command == "IMPLIES" and value == 1 and other[index] == 0 then
                return {"does not imply: " .. assignment_text(names, index - 1)}
            end
        end
        return {command == "EQUIV" and "equivalent" or "implies"}
    elseif command == "MINIMIZE" then
        return minimize(values, nil, names, false)
    elseif command == "MINDC" then
        return minimize(values, truth_table(second, names), names, false)
    elseif command == "MINPOS" then
        local inverted = {}
        for i, value in ipairs(values) do
            inverted[i] = 1 - value
        end
        return minimize(inverted, nil, names, true)
    elseif command == "KMAP" then
        local n = #names
        if n < 2 or n > 4 then
            fail("kmap needs 2 to 4 variables")
        end
        local p, q = n // 2, n - n // 2
        local label = table.concat(names, "", 1, p) .. "\\" .. table.concat(names, "", p + 1, n)
        local header = label
        for i = 0, (1 << q) - 1 do
            header = header .. " " .. bit_pattern(i ~ (i // 2), q)
        end
        local out = {header}
        for i = 0, (1 << p) - 1 do
            local row = i ~ (i // 2)
            local text = bit_pattern(row, p) .. string.rep(" ", n + 1 - p)
            for j = 0, (1 << q) - 1 do
                text = text .. string.rep(" ", q) .. values[((row << q) | (j ~ (j // 2))) + 1]
            end
            out[#out + 1] = text
        end
        return out
    elseif command == "PROPS" then
        local depends = {}
        for i, name in ipairs(names) do
            local bit = 1 << (#names - i)
            for row = 0, #values - 1 do
                if values[row + 1] ~= values[(row ~ bit) + 1] then
                    depends[#depends + 1] = name
                    break
                end
            end
        end
        local self_dual, monotone, linear, symmetric = true, true, true, true
        local weights = {}
        for row = 0, #values - 1 do
            local value = values[row + 1]
            if value == values[#values - row] then
                self_dual = false
            end
            for bit = 0, #names - 1 do
                local mask = 1 << bit
                if row & mask == 0 and value > values[(row | mask) + 1] then
                    monotone = false
                end
            end
            local weight = bit_count(row)
            if weights[weight] ~= nil and weights[weight] ~= value then
                symmetric = false
            end
            weights[weight] = value
        end
        for index, coefficient in ipairs(coefficients(values, #names)) do
            if coefficient == 1 and bit_count(index - 1) > 1 then
                linear = false
            end
        end
        local function yes(value)
            return value and "yes" or "no"
        end
        return {
            "depends: " .. (#depends == 0 and "none" or table.concat(depends, " ")),
            "zero-preserving: " .. yes(values[1] == 0),
            "one-preserving: " .. yes(values[#values] == 1),
            "self-dual: " .. yes(self_dual),
            "monotone: " .. yes(monotone),
            "linear: " .. yes(linear),
            "symmetric: " .. yes(symmetric)
        }
    elseif command == "BDD" then
        local nodes, unique = {}, {}
        local function build(level, first, count)
            if level > #names then
                return values[first]
            end
            local half = count // 2
            local low = build(level + 1, first, half)
            local high = build(level + 1, first + half, half)
            if low == high then
                return low
            end
            local key = level .. ":" .. low .. ":" .. high
            if unique[key] then
                return unique[key]
            end
            local index = #nodes + 2
            nodes[#nodes + 1] = {variable = level, low = low, high = high}
            unique[key] = index
            return index
        end
        local root = build(1, 1, #values)
        local out = {"nodes: " .. #nodes}
        local paths = {[0] = 0, [1] = 1}
        for i, node in ipairs(nodes) do
            out[#out + 1] =
                string.format(
                "%d = ite(%s, %d, %d)",
                i + 1,
                names[node.variable],
                node.high,
                node.low
            )
            paths[i + 1] = paths[node.low] + paths[node.high]
        end
        out[#out + 1] = "root: " .. root
        out[#out + 1] = "paths: " .. paths[root]
        return out
    end
end
local workbench = setmetatable({names = {}}, Workbench)
local count = tonumber(io.read("*l"))
for _ = 1, count do
    local line = io.read("*l")
    local ok, result =
        pcall(
        function()
            return workbench:command(line)
        end
    )
    if not ok then
        if type(result) ~= "table" or not result.reason then
            error(result, 0)
        end
        io.write("error: ", result.reason, "\n")
    else
        for _, text in ipairs(result) do
            io.write(text, "\n")
        end
    end
end
