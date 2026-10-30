local C = require("charset")
local F = require("formatter")
local Backtrack = require("backtrack_vm")
local Pike = require("pike_vm")
local P = {}
P.__index = P
local quantifiers = { ["*"] = true, ["+"] = true, ["?"] = true, ["{"] = true }
local function letter(ch) return ch and C.letter(ch:byte()) or false end
local function digit(ch) return ch and C.digit(ch:byte()) or false end
function P.new(text) return setmetatable({ text = text, index = 1, groups = 0, named = {}, backrefs = {} }, P) end
function P:peek(offset)
    local position = self.index + (offset or 0)
    return position <= #self.text and self.text:sub(position, position) or false
end
function P:take()
    local ch = self:peek()
    if ch then self.index = self.index + 1 end
    return ch
end
function P:error(message, column) error({ category = "pattern", message = message, column = column or self.index }, 0) end
function P:digits()
    local start = self.index
    while digit(self:peek()) do self:take() end
    return self.text:sub(start, self.index - 1)
end
function P:name()
    if not letter(self:peek()) and self:peek() ~= "_" then self:error("invalid group name") end
    local start = self.index
    while letter(self:peek()) or digit(self:peek()) or self:peek() == "_" do self:take() end
    local name = self.text:sub(start, self.index - 1)
    if self:peek() ~= ">" then self:error("invalid group name") end
    self:take()
    return name
end
function P:parse()
    local root = self:alternation()
    if self:peek() then self:error("unmatched )") end
    for _, reference in ipairs(self.backrefs) do
        if reference.name then
            if not self.named[reference.name] then self:error("unknown group name", reference.column) end
            reference.number = self.named[reference.name]
        elseif reference.number > self.groups then self:error("invalid group reference", reference.column) end
    end
    return root
end
function P:alternation()
    local children = { self:concatenation() }
    while self:peek() == "|" do self:take(); children[#children + 1] = self:concatenation() end
    return #children == 1 and children[1] or { kind = "alternation", elements = children }
end
function P:concatenation()
    local children = {}
    while self:peek() and self:peek() ~= "|" and self:peek() ~= ")" do children[#children + 1] = self:quantified() end
    return #children == 1 and children[1] or { kind = "concat", elements = children }
end
function P:quantified()
    if quantifiers[self:peek()] then self:error("nothing to repeat") end
    local element = self:element()
    if not quantifiers[self:peek()] then return element end
    if element.kind == "assert" or element.kind == "look" then self:error("nothing to repeat") end
    local beginning, ch, lower, upper = self.index, self:take(), 0, false
    if ch == "+" then lower = 1 elseif ch == "?" then upper = 1
    elseif ch == "{" then
        local low = self:digits()
        if low == "" then self:error("invalid quantifier", beginning) end
        lower = tonumber(low)
        if self:peek() == "}" then upper = lower
        elseif self:peek() == "," then
            self:take()
            if self:peek() ~= "}" then
                local high = self:digits()
                if high == "" then self:error("invalid quantifier", beginning) end
                upper = tonumber(high)
            end
        else self:error("invalid quantifier", beginning) end
        if self:peek() ~= "}" then self:error("invalid quantifier", beginning) end
        self:take()
        if lower > 100 or (upper and upper > 100) then self:error("quantifier too large", beginning) end
        if upper and lower > upper then self:error("quantifier range out of order", beginning) end
    end
    local mode = "greedy"
    if self:peek() == "?" then self:take(); mode = "lazy"
    elseif self:peek() == "+" then self:take(); mode = "possessive" end
    if quantifiers[self:peek()] then self:error("nested quantifier") end
    return { kind = "repeat", child = element, lower = lower, upper = upper, mode = mode }
end
function P:element()
    local ch = self:peek()
    if ch == "(" then return self:group()
    elseif ch == "[" then return self:character_class()
    elseif ch == "\\" then return self:escape() end
    self:take()
    if ch == "." then return { kind = "any" }
    elseif ch == "^" or ch == "$" then return { kind = "assert", value = ch == "^" and "BOL" or "EOL" } end
    return { kind = "literal", value = ch:byte() }
end
function P:group()
    local column, kind, named = self.index, "capture", false
    self:take()
    if self:peek() == "?" then
        self:take()
        local special = self:peek()
        if special ~= ":" and special ~= "=" and special ~= "!" and special ~= "<" then self:error("invalid group", column) end
        self:take()
        if special == ":" then kind = "noncapture" elseif special == "=" then kind = "ahead" elseif special == "!" then kind = "negative" end
        if special == "<" then
            local name_column = self.index
            named = self:name()
            if self.named[named] then self:error("duplicate group name", name_column) end
        end
    end
    local number
    if kind == "capture" then
        self.groups = self.groups + 1
        number = self.groups
        if named then self.named[named] = number end
    end
    local content = self:alternation()
    if self:peek() ~= ")" then self:error("missing )", column) end
    self:take()
    if kind == "noncapture" then return content
    elseif kind == "ahead" or kind == "negative" then return { kind = "look", positive = kind == "ahead", child = content } end
    return { kind = "group", number = number, child = content }
end
function P:class_item()
    if self:peek() ~= "\\" then return self:take():byte() end
    local column = self.index
    self:take()
    local special = self:take()
    if not special then self:error("trailing backslash", column) end
    local set = C.escaped(special)
    if set then return set end
    if special == "n" then return 10 elseif special == "t" then return 9 end
    if letter(special) or digit(special) then self:error("invalid escape", column) end
    return special:byte()
end
function P:character_class()
    local opening = self.index
    self:take()
    local negate = self:peek() == "^"
    if negate then self:take() end
    if self:peek() == "]" then self:error("empty class") end
    local values = {}
    while true do
        if not self:peek() then self:error("missing ]", opening) end
        if self:peek() == "]" then self:take(); break end
        local first = self:class_item()
        if self:peek() == "-" and self:peek(1) and self:peek(1) ~= "]" then
            local column = self.index
            self:take()
            if type(first) == "table" then self:error("invalid range", column) end
            local last = self:class_item()
            if type(last) == "table" or first > last then self:error("invalid range", column) end
            for code = first, last do values[code] = true end
        elseif type(first) == "table" then for code in pairs(first) do values[code] = true end
        else values[first] = true end
    end
    return { kind = "class", set = values, neg = negate }
end
function P:escape()
    local column = self.index
    self:take()
    local ch = self:take()
    if not ch then self:error("trailing backslash", column) end
    local set, negated = C.standard(ch)
    if set then return { kind = "class", set = set, neg = negated }
    elseif ch == "b" or ch == "B" then return { kind = "assert", value = ch == "b" and "WORD" or "NOTWORD" }
    elseif ch == "n" or ch == "t" then return { kind = "literal", value = ch == "n" and 10 or 9 }
    elseif digit(ch) and ch ~= "0" then
        local reference = { kind = "backref", number = tonumber(ch .. self:digits()), column = column }
        self.backrefs[#self.backrefs + 1] = reference
        return reference
    elseif ch == "k" then
        if self:peek() ~= "<" then self:error("invalid escape", column) end
        self:take()
        local reference = { kind = "backref", name = self:name(), column = column }
        self.backrefs[#self.backrefs + 1] = reference
        return reference
    elseif letter(ch) or digit(ch) then self:error("invalid escape", column) end
    return { kind = "literal", value = ch:byte() }
end
local function compile(root)
    local program = {}
    local function emit(op, parts)
        parts = parts or {}
        local address = #program
        parts.op, program[address + 1] = op, parts
        return address
    end
    local function split_target(pc, continuation, ending, mode)
        local instruction = program[pc + 1]
        instruction.x, instruction.y = mode == "lazy" and ending or continuation, mode == "lazy" and continuation or ending
    end
    local visit
    visit = function(node)
        local kind = node.kind
        if kind == "literal" then emit("CHAR", { char = node.value })
        elseif kind == "any" then emit("ANY")
        elseif kind == "class" then emit("CLASS", { set = node.set, neg = node.neg })
        elseif kind == "assert" then emit("ASSERT", { kind = node.value })
        elseif kind == "backref" then emit("BACKREF", { group = node.number })
        elseif kind == "group" then emit("SAVE", { slot = node.number * 2 }); visit(node.child); emit("SAVE", { slot = node.number * 2 + 1 })
        elseif kind == "look" then
            local pc = emit("LOOK", { kind = node.positive and "AHEAD" or "NOT" })
            visit(node.child)
            emit("MATCH")
            program[pc + 1].x = #program
        elseif kind == "concat" then for _, child in ipairs(node.elements) do visit(child) end
        elseif kind == "alternation" then
            local endings = {}
            for i = 1, #node.elements - 1 do
                local pc = emit("SPLIT", { x = #program + 1 })
                visit(node.elements[i])
                endings[#endings + 1] = emit("JMP")
                program[pc + 1].y = #program
            end
            visit(node.elements[#node.elements])
            for _, pc in ipairs(endings) do program[pc + 1].x = #program end
        elseif kind == "repeat" then
            local child, lower, upper, mode = node.child, node.lower, node.upper, node.mode
            if mode == "possessive" then
                local pc = emit("LOOK", { kind = "ATOMIC" })
                visit({ kind = "repeat", child = child, lower = lower, upper = upper, mode = "greedy" })
                emit("MATCH")
                program[pc + 1].x = #program
            elseif not upper and lower == 0 then
                local pc = emit("SPLIT")
                local continuation = #program
                visit(child)
                emit("JMP", { x = pc })
                split_target(pc, continuation, #program, mode)
            elseif not upper then
                for _ = 1, lower - 1 do visit(child) end
                local beginning = #program
                visit(child)
                local pc = emit("SPLIT")
                split_target(pc, beginning, #program, mode)
            else
                for _ = 1, lower do visit(child) end
                local optional = {}
                for _ = 1, upper - lower do
                    local pc = emit("SPLIT")
                    local continuation = #program
                    visit(child)
                    optional[#optional + 1] = { pc, continuation }
                end
                for _, entry in ipairs(optional) do split_target(entry[1], entry[2], #program, mode) end
            end
        end
    end
    emit("SAVE", { slot = 0 })
    visit(root)
    emit("SAVE", { slot = 1 })
    emit("MATCH")
    return program
end
local function length_range(node)
    local kind = node.kind
    if kind == "literal" or kind == "any" or kind == "class" then return 1, 1
    elseif kind == "assert" or kind == "look" then return 0, 0
    elseif kind == "backref" then return 0, false
    elseif kind == "group" then return length_range(node.child)
    elseif kind == "repeat" then
        local a, b = length_range(node.child)
        local maximum = false
        if b == 0 then maximum = 0 elseif b ~= false and node.upper ~= false then maximum = node.upper * b end
        return node.lower * a, maximum
    end
    local minimum, maximum = kind == "concat" and 0 or false, 0
    for _, child in ipairs(node.elements) do
        local a, b = length_range(child)
        if kind == "concat" then
            minimum = minimum + a
            maximum = maximum ~= false and b ~= false and maximum + b or false
        else
            if minimum == false or a < minimum then minimum = a end
            maximum = maximum ~= false and b ~= false and math.max(maximum, b) or false
        end
    end
    return minimum or 0, maximum
end
local function first_characters(node, flags)
    local kind, values = node.kind, {}
    if kind == "literal" then
        values[node.value] = true
        if flags.i and C.letter(node.value) then values[C.switched(node.value)] = true end
        return values, false
    elseif kind == "any" or kind == "backref" then
        for code = 0, 127 do if kind == "backref" or flags.s or code ~= 10 then values[code] = true end end
        return values, kind == "backref"
    elseif kind == "class" then
        for code = 0, 127 do if C.class(code, node.set, node.neg, flags) then values[code] = true end end
        return values, false
    elseif kind == "assert" or kind == "look" then return values, true
    elseif kind == "group" then return first_characters(node.child, flags)
    elseif kind == "repeat" then
        if node.upper == 0 then return values, true end
        local chars, nullable = first_characters(node.child, flags)
        return chars, nullable or node.lower == 0
    end
    local nullable = kind == "concat"
    for _, child in ipairs(node.elements) do
        local chars, child_nullable = first_characters(child, flags)
        for code in pairs(chars) do values[code] = true end
        if kind == "concat" and not child_nullable then nullable = false; break end
        if kind == "alternation" and child_nullable then nullable = true end
    end
    return values, nullable
end
local function decode_quoted(text)
    local parts, index = {}, 2
    local escapes = { n = "\n", t = "\t", ["\\"] = "\\", ['"'] = '"' }
    while index < #text do
        local ch = text:sub(index, index)
        if ch == "\\" then parts[#parts + 1], index = escapes[text:sub(index + 1, index + 1)], index + 2
        else parts[#parts + 1], index = ch, index + 1 end
    end
    return table.concat(parts)
end
local patterns, pattern_order = {}, {}
for line in io.lines("input/patterns.txt") do
    local first = assert(line:find(" ", 1, true))
    local second = assert(line:find(" ", first + 1, true))
    local name, flags_text, text = line:sub(1, first - 1), line:sub(first + 1, second - 1), line:sub(second + 1)
    local entry = { name = name, flags_text = flags_text, flags = {}, pattern = text }
    if flags_text ~= "-" then for i = 1, #flags_text do entry.flags[flags_text:sub(i, i)] = true end end
    local parser = P.new(text)
    local ok, root = pcall(parser.parse, parser)
    if not ok then
        if type(root) ~= "table" or root.category ~= "pattern" then error(root) end
        entry.error = root
    else
        entry.root, entry.program, entry.groups, entry.named, entry.pike = root, compile(root), parser.groups, parser.named, true
        for _, ins in ipairs(entry.program) do if ins.op == "BACKREF" or ins.op == "LOOK" then entry.pike = false; break end end
    end
    patterns[name], pattern_order[#pattern_order + 1] = entry, entry
end
local subjects, commands = {}, {}
for line in io.lines("input/subjects.txt") do
    local at = assert(line:find(" ", 1, true))
    subjects[line:sub(1, at - 1)] = decode_quoted(line:sub(at + 1))
end
for line in io.lines("input/commands.txt") do
    local position = 1
    local function word()
        local ending = line:find(" ", position, true) or #line + 1
        local value = line:sub(position, ending - 1)
        position = ending + 1
        return value
    end
    local command = { kind = word(), number = #commands + 1, line = line }
    if command.kind == "REPLACE" then
        command.mode, command.name, command.subject = word(), word(), word()
        command.template = decode_quoted(line:sub(position))
    else
        command.name = word()
        if command.kind ~= "LIST" then command.subject = word() end
    end
    commands[#commands + 1] = command
end
local function all_digits(text)
    if text == "" then return false end
    for i = 1, #text do if not C.digit(text:byte(i)) then return false end end
    return true
end
local function parse_template(text, pattern)
    local parts, position = {}, 1
    while position <= #text do
        local ch = text:sub(position, position)
        if ch ~= "$" then parts[#parts + 1], position = { "literal", ch }, position + 1
        else
            local next_ch = text:sub(position + 1, position + 1)
            local group
            if next_ch == "$" then parts[#parts + 1], position = { "literal", "$" }, position + 2
            else
                if digit(next_ch ~= "" and next_ch or false) then group, position = tonumber(next_ch), position + 2
                elseif next_ch == "{" then
                    local ending = text:find("}", position + 2, true)
                    if not ending then return false end
                    local name = text:sub(position + 2, ending - 1)
                    if all_digits(name) then group = tonumber(name) else group = pattern.named[name] end
                    if group == nil then return false end
                    position = ending + 1
                else return false end
                if group > pattern.groups then return false end
                parts[#parts + 1] = { "group", group }
            end
        end
    end
    return parts
end
local function captured(text, captures, group)
    local a, b = captures[group * 2 + 1], captures[group * 2 + 2]
    if a == false or b == false then return false end
    return text:sub(a + 1, b)
end
local function scans(vm, kind)
    if kind == "MATCH" or kind == "SEARCH" or kind == "REPLACE FIRST" then
        local found = vm:search(0)
        return found and { found } or {}
    end
    local found, start = {}, 0
    while start <= #vm.text do
        local result = vm:search(start)
        if not result then break end
        found[#found + 1] = result
        start = result[2] > result[1] and result[2] or result[2] + 1
    end
    return found
end
local function same_matches(a, b)
    if #a ~= #b then return false end
    for i, captures in ipairs(a) do
        if #captures ~= #b[i] then return false end
        for j, value in ipairs(captures) do if value ~= b[i][j] then return false end end
    end
    return true
end
local function execute_command(command, pattern)
    if pattern.error then return { status = "invalid pattern", steps = {} } end
    if command.kind == "LIST" then return { status = "list", steps = {} } end
    local template = false
    if command.kind == "REPLACE" then
        template = parse_template(command.template, pattern)
        if not template then return { status = "invalid template", steps = {} } end
    end
    local text, full = subjects[command.subject], command.kind == "MATCH"
    local kind = command.kind == "REPLACE" and "REPLACE " .. command.mode or command.kind
    local backtrack = Backtrack.new(pattern.program, pattern.flags, pattern.groups, text, full)
    local ok, backtrack_matches = pcall(scans, backtrack, kind)
    if not ok and (type(backtrack_matches) ~= "table" or backtrack_matches.category ~= "regex_limit") then error(backtrack_matches) end
    local steps = { { "backtrack", backtrack.steps } }
    local engine, matches
    if pattern.pike then
        local pike = Pike.new(pattern.program, pattern.flags, pattern.groups, text, full)
        matches = scans(pike, kind)
        steps[#steps + 1] = { "pike", pike.steps }
        if not ok then engine = "pike (backtrack: TOO_MANY_STEPS)"
        elseif not same_matches(backtrack_matches, matches) then return { status = "MISMATCH", steps = steps }
        else engine = "both" end
    else
        if not ok then return { status = "TOO_MANY_STEPS", steps = steps } end
        engine, matches = "backtrack", backtrack_matches
    end
    return { status = "ok", engine = engine, matches = matches, steps = steps, template = template, text = text }
end
local function append(target, source) for _, line in ipairs(source) do target[#target + 1] = line end end
local function match_lines(captures, pattern, text)
    local lines = { string.format("match %d-%d %s", captures[1], captures[2], F.quoted(captured(text, captures, 0))) }
    for group = 1, pattern.groups do
        local value = captured(text, captures, group)
        if value == false then lines[#lines + 1] = "group " .. group .. " -"
        else lines[#lines + 1] = string.format("group %d %d-%d %s", group, captures[2 * group + 1], captures[2 * group + 2], F.quoted(value)) end
    end
    return lines
end
local function render_result(command, pattern, evaluated)
    local lines = { "#" .. command.number .. " " .. command.line }
    if evaluated.status == "list" then lines[#lines + 1] = "instructions " .. #pattern.program; return lines end
    if evaluated.status ~= "ok" then lines[#lines + 1] = evaluated.status; return lines end
    local text, matches, kind = evaluated.text, evaluated.matches, command.kind
    lines[#lines + 1] = "engine " .. evaluated.engine
    if kind == "MATCH" or kind == "SEARCH" then
        if #matches == 0 then lines[#lines + 1] = "no match" else append(lines, match_lines(matches[1], pattern, text)) end
    elseif kind == "FINDALL" then
        lines[#lines + 1] = "matches " .. #matches
        for _, captures in ipairs(matches) do append(lines, match_lines(captures, pattern, text)) end
    elseif kind == "REPLACE" then
        local pieces, previous = {}, 0
        for _, captures in ipairs(matches) do
            pieces[#pieces + 1] = text:sub(previous + 1, captures[1])
            for _, part in ipairs(evaluated.template) do
                pieces[#pieces + 1] = part[1] == "literal" and part[2] or (captured(text, captures, part[2]) or "")
            end
            previous = captures[2]
        end
        pieces[#pieces + 1] = text:sub(previous + 1)
        lines[#lines + 1], lines[#lines + 2] = "replacements " .. #matches, "result " .. F.quoted(table.concat(pieces))
    elseif kind == "SPLIT" then
        local pieces, previous = {}, 0
        for _, captures in ipairs(matches) do pieces[#pieces + 1], previous = text:sub(previous + 1, captures[1]), captures[2] end
        pieces[#pieces + 1] = text:sub(previous + 1)
        lines[#lines + 1], lines[#lines + 2] = "pieces " .. #pieces, "piece " .. F.quoted(pieces[1])
        for i, captures in ipairs(matches) do
            for group = 1, pattern.groups do
                local value = captured(text, captures, group)
                lines[#lines + 1] = "group " .. group .. " " .. (value ~= false and F.quoted(value) or "-")
            end
            lines[#lines + 1] = "piece " .. F.quoted(pieces[i + 1])
        end
    end
    return lines
end
local function program_listing(pattern)
    local lower, upper = length_range(pattern.root)
    local first = first_characters(pattern.root, pattern.flags)
    local named, names = {}, {}
    for name, number in pairs(pattern.named) do named[#named + 1] = { name, number } end
    table.sort(named, function(a, b) return a[2] < b[2] end)
    for _, entry in ipairs(named) do names[#names + 1] = entry[1] .. ":" .. entry[2] end
    local has_first = next(first) ~= nil
    local lines = { "=== " .. pattern.name, string.format("flags=%s groups=%d names=%s length=%d..%s first=%s pike=%s size=%d",
        pattern.flags_text, pattern.groups, #names > 0 and table.concat(names, ",") or "-", lower,
        upper ~= false and tostring(upper) or "inf", has_first and F.set_notation(first, false) or "-", pattern.pike and "yes" or "no", #pattern.program) }
    for i, ins in ipairs(pattern.program) do lines[#lines + 1] = (i - 1) .. " " .. F.instruction(ins) end
    return lines
end
local results, programs, steps, errors = {}, {}, { "command,engine,steps" }, {}
for _, command in ipairs(commands) do
    local pattern = patterns[command.name]
    local evaluated = execute_command(command, pattern)
    append(results, render_result(command, pattern, evaluated))
    if command.kind == "LIST" and not pattern.error then append(programs, program_listing(pattern)) end
    for _, entry in ipairs(evaluated.steps) do steps[#steps + 1] = command.number .. "," .. entry[1] .. "," .. entry[2] end
end
for _, pattern in ipairs(pattern_order) do
    if pattern.error then
        errors[#errors + 1] = string.format("%s: %s at column %d", pattern.name, pattern.error.message, pattern.error.column)
        errors[#errors + 1], errors[#errors + 2] = "  " .. pattern.pattern, string.rep(" ", pattern.error.column + 1) .. "^"
    end
end
if #programs == 0 then programs[1] = "no programs" end
if #errors == 0 then errors[1] = "no errors" end
for _, entry in ipairs({ { "results.txt", results }, { "programs.txt", programs }, { "steps.csv", steps }, { "errors.txt", errors } }) do
    local output = assert(io.open("output/" .. entry[1], "w"))
    if #entry[2] > 0 then output:write(table.concat(entry[2], "\n"), "\n") end
    output:close()
end
