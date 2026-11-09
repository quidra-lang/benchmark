local T = require("terms")
local U = require("unify")
local Reader = require("reader")
local Database = require("database")
local Predicates = require("predicates")
local controls, builtins = {}, {}
for _, pair in ipairs({ { ",", 2 }, { "!", 0 }, { ";", 2 }, { "->", 2 }, { "\\+", 1 }, { "catch", 3 } }) do controls[T.signature(pair[1], pair[2])] = true end
for arity = 1, 8 do controls[T.signature("call", arity)] = true end
for key in pairs(Predicates.deterministic) do builtins[key] = true end
for _, pair in ipairs({ { "findall", 3 }, { "throw", 1 }, { "between", 3 }, { "length", 2 } }) do builtins[T.signature(pair[1], pair[2])] = true end
local function is(term, name, arity) return T.is_compound(term) and term.name == name and #term.args == arity end
local function increment(values, key) values[key] = (values[key] or 0) + 1 end
local function append(values, other) for _, value in ipairs(other) do values[#values + 1] = value end end
local function goal_conversion(term)
    term = T.dereference(term)
    if T.is_variable(term) then return T.compound("call", term) end
    if type(term) == "number" then return nil end
    if T.is_compound(term) and #term.args == 2 and (term.name == "," or term.name == ";" or term.name == "->") then
        local left = goal_conversion(term.args[1])
        if not left then return nil end
        local right = goal_conversion(term.args[2])
        if not right then return nil end
        return T.compound(term.name, left, right)
    end
    return term
end
local function atom_name(name, quoted)
    local plain = name == "[]" or name == "!" or name == ";" or name:match("^[a-z][a-zA-Z0-9_]*$") ~= nil
    if #name > 0 and name ~= "." then
        local symbols = true
        for i = 1, #name do if not Reader.symbols[name:sub(i, i)] then symbols = false; break end end
        plain = plain or symbols
    end
    if not quoted or plain then return name end
    local escapes = { ["\\"] = "\\\\", ["'"] = "\\'", ["\n"] = "\\n", ["\t"] = "\\t" }
    return "'" .. name:gsub("[\\'\n\t]", escapes) .. "'"
end
local W = {}
W.__index = W
function W.new(names, quoted)
    local copy = {}
    for variable, name in pairs(names or {}) do copy[variable] = name end
    return setmetatable({ names = copy, next_name = 1, quoted = quoted ~= false }, W)
end
function W:write(term, limit, operand)
    limit = limit or 1200
    term = T.dereference(term)
    if T.is_variable(term) then
        if not self.names[term] then self.names[term] = "_G" .. self.next_name; self.next_name = self.next_name + 1 end
        return self.names[term]
    elseif type(term) == "number" then return tostring(term)
    elseif type(term) == "string" then
        local text = atom_name(term, self.quoted)
        return operand and (Reader.infix[term] or Reader.prefix[term]) and "(" .. text .. ")" or text
    end
    local name, arguments = term.name, term.args
    if name == "." and #arguments == 2 then
        local elements, tail = T.list_parts(term)
        local parts = {}
        for i, element in ipairs(elements) do parts[i] = self:write(element, 999) end
        local text = "[" .. table.concat(parts, ",")
        if tail ~= "[]" then text = text .. "|" .. self:write(tail, 999) end
        return text .. "]"
    elseif #arguments == 2 and Reader.infix[name] then
        local operator = Reader.infix[name]
        local left = self:write(arguments[1], operator[2], true)
        local right = self:write(arguments[2], operator[3], true)
        local text
        if name == "," then text = left .. "," .. right
        elseif name:match("^[a-zA-Z]") then text = left .. " " .. name .. " " .. right
        else
            text = left .. (Reader.symbols[left:sub(-1)] and " " or "") .. name .. (Reader.symbols[right:sub(1, 1)] and " " or "") .. right
        end
        return operator[1] > limit and "(" .. text .. ")" or text
    elseif #arguments == 1 and Reader.prefix[name] then
        local priority = Reader.prefix[name]
        local argument = self:write(arguments[1], priority, true)
        local first = argument:sub(1, 1)
        local space = Reader.symbols[first] or first ~= "" and first >= "0" and first <= "9" or first == "("
        local text = name .. (space and " " or "") .. argument
        return priority > limit and "(" .. text .. ")" or text
    end
    local parts = {}
    for i, argument in ipairs(arguments) do parts[i] = self:write(argument, 999) end
    return atom_name(name, self.quoted) .. "(" .. table.concat(parts, ",") .. ")"
end
local function predicate_name(key) return W.new():write(T.indicator_term(key)) end
local C = {}
C.__index = C
function C.new()
    return setmetatable({ database = Database.new(), lines = {}, counts = { ["prelude.pl"] = { 0, 0, 0 }, ["program.pl"] = { 0, 0, 0 } }, last = {}, discontiguous = {} }, C)
end
function C:warning(file, line, message)
    self.lines[#self.lines + 1] = file .. ":" .. line .. ": warning: " .. message
    self.counts[file][3] = self.counts[file][3] + 1
end
function C:add(term, file, line, reader)
    local head, body, issue = term, false, nil
    if is(term, ":-", 2) then head, body = term.args[1], term.args[2] end
    if T.is_variable(head) then issue = "instantiation_error"
    elseif type(head) == "number" then issue = T.type_error("callable", head)
    elseif controls[T.indicator(head)] or builtins[T.indicator(head)] then issue = T.compound("permission_error", "modify", "static_procedure", T.indicator_term(T.indicator(head)))
    elseif body then
        local converted = goal_conversion(body)
        if not converted then issue = T.type_error("callable", body) else body = converted end
    end
    if issue then
        self.lines[#self.lines + 1] = file .. ":" .. line .. ": error: " .. W.new():write(issue)
        self.counts[file][2] = self.counts[file][2] + 1
        return
    end
    local key = T.indicator(head)
    local previous = self.database.predicates[key] or {}
    local prelude, same_file = false, false
    for _, clause in ipairs(previous) do if clause.file == "prelude.pl" then prelude = true end end
    if file == "program.pl" and prelude then
        self:warning(file, line, "redefining prelude procedure " .. predicate_name(key))
        self.database.predicates[key], previous = {}, {}
    end
    for _, clause in ipairs(previous) do if clause.file == file then same_file = true end end
    local warning_key = file .. "\0" .. key
    if same_file and self.last[file] ~= key and not self.discontiguous[warning_key] then
        self:warning(file, line, "clauses of " .. predicate_name(key) .. " are not together")
        self.discontiguous[warning_key] = true
    end
    self.database:add({ head = head, body = body, file = file, line = line })
    self.last[file], self.counts[file][1] = key, self.counts[file][1] + 1
    local singletons, repeated = {}, {}
    for _, name in ipairs(reader.order) do
        if name:sub(1, 1) ~= "_" and reader.counts[name] == 1 then singletons[#singletons + 1] = name end
        if #name > 1 and name:sub(1, 1) == "_" and reader.counts[name] > 1 then repeated[#repeated + 1] = name end
    end
    if #singletons > 0 then self:warning(file, line, "singleton variables: " .. table.concat(singletons, ", ")) end
    if #repeated > 0 then self:warning(file, line, "variables starting with _ occur more than once: " .. table.concat(repeated, ", ")) end
end
function C:consult(file, text)
    local reader, source_lines = Reader.new(text), {}
    for line in (text .. "\n"):gmatch("([^\n]*)\n") do source_lines[#source_lines + 1] = line end
    while reader:peek().kind ~= "eof" do
        local line = reader:peek().line
        local ok, term = pcall(reader.clause, reader)
        if ok then self:add(term, file, line, reader)
        else
            if type(term) ~= "table" or term.category ~= "syntax" then error(term, 0) end
            local token = term.token
            self.counts[file][2] = self.counts[file][2] + 1
            self.lines[#self.lines + 1] = string.format("%s:%d:%d: syntax error: %s", file, token.line, token.column, term.message)
            if token.kind ~= "eof" then append(self.lines, { "    " .. source_lines[token.line], string.rep(" ", token.column + 3) .. "^" }) end
            reader.position = token.index
            while reader:peek().kind ~= "end" and reader:peek().kind ~= "eof" do reader:take() end
            if reader:peek().kind == "end" then reader:take() end
        end
    end
end
function C:finish()
    local reported = {}
    for _, source in ipairs(self.database.order) do
        for _, clause in ipairs(self.database.predicates[source]) do
            local pending = clause.body and { clause.body } or {}
            while #pending > 0 do
                local term = T.dereference(table.remove(pending))
                if not T.is_variable(term) and type(term) ~= "number" then
                    local key = T.indicator(term)
                    if is(term, ",", 2) or is(term, ";", 2) or is(term, "->", 2) then pending[#pending + 1], pending[#pending + 2] = term.args[2], term.args[1]
                    elseif is(term, "\\+", 1) or is(term, "call", 1) then pending[#pending + 1] = term.args[1]
                    elseif is(term, "findall", 3) then pending[#pending + 1] = term.args[2]
                    elseif is(term, "catch", 3) then pending[#pending + 1], pending[#pending + 2] = term.args[3], term.args[1]
                    elseif not controls[key] and not builtins[key] and not self.database.predicates[key] and not reported[key] then
                        reported[key] = true
                        self:warning(clause.file, clause.line, "undefined procedure " .. predicate_name(key) .. " called from " .. predicate_name(source))
                    end
                end
            end
        end
    end
    for _, file in ipairs({ "prelude.pl", "program.pl" }) do
        local count = self.counts[file]
        self.lines[#self.lines + 1] = string.format("%s: clauses=%d errors=%d warnings=%d", file, count[1], count[2], count[3])
    end
    local clauses = 0
    for _, key in ipairs(self.database.order) do clauses = clauses + #self.database.predicates[key] end
    self.lines[#self.lines + 1] = string.format("database: predicates=%d clauses=%d", #self.database.order, clauses)
end
local function listing(database)
    local lines = {}
    for _, key in ipairs(database.order) do
        if #lines > 0 then lines[#lines + 1] = "" end
        for _, clause in ipairs(database.predicates[key]) do
            local occurrences, counts, names, number = T.variables_in(clause.head, clause.body), {}, {}, 0
            for _, variable in ipairs(occurrences) do increment(counts, variable) end
            for _, variable in ipairs(occurrences) do
                if not names[variable] then
                    if counts[variable] == 1 then names[variable] = "_"
                    else
                        names[variable] = string.char(65 + number % 26) .. (number >= 26 and tostring(number // 26) or "")
                        number = number + 1
                    end
                end
            end
            local writer = W.new(names)
            local head = writer:write(clause.head)
            if not clause.body then lines[#lines + 1] = head .. "."
            else
                lines[#lines + 1] = head .. " :-"
                local goals, body = {}, clause.body
                while is(body, ",", 2) do goals[#goals + 1], body = body.args[1], body.args[2] end
                goals[#goals + 1] = body
                for i, goal in ipairs(goals) do lines[#lines + 1] = "    " .. writer:write(goal, 999) .. (i == #goals and "." or ",") end
            end
        end
    end
    return lines
end
local function answer(variables)
    local names, previous, items = {}, {}, {}
    for _, entry in ipairs(variables) do
        local value = T.dereference(entry[2])
        if T.is_variable(value) and not names[value] then names[value] = entry[1] end
    end
    local writer = W.new(names)
    for _, entry in ipairs(variables) do
        local name, value = entry[1], T.dereference(entry[2])
        if T.is_variable(value) then
            if previous[value] then items[#items + 1] = previous[value] .. " = " .. name end
            previous[value] = name
        else items[#items + 1] = name .. " = " .. writer:write(value, 699, true) end
    end
    return #items > 0 and table.concat(items, ", ") or "true"
end
local function entry(goal, barrier, context, next_entry) return { goal = goal, barrier = barrier, context = context, next = next_entry } end
local function marker(kind, payload) return { kind = "marker", marker_kind = kind, payload = payload } end
local E = {}
E.__index = E
function E.new(database, query, variables, limit, calls, tries)
    return setmetatable({ database = database, variables = variables, limit = limit, calls = calls, tries = tries, trail = U.new(),
        goals = entry(T.compound("call", query), 0, nil), choices = {}, solutions = 0, inferences = 0, choicepoints = 0, backtracks = 0, answers = {}, output = {} }, E)
end
function E:cut(height) for i = #self.choices, height + 1, -1 do self.choices[i] = nil end end
function E:create_choice(kind, resume, fields)
    fields = fields or {}
    fields.kind, fields.mark, fields.resume = kind, self.trail:mark(), resume
    self.choices[#self.choices + 1] = fields
    self.choicepoints = self.choicepoints + 1
    return fields
end
function E:infer(key)
    if self.inferences == 20000 then error({ category = "limit" }, 0) end
    self.inferences = self.inferences + 1
    increment(self.calls, key)
end
function E:try_clause(clause, goal, barrier, context, continuation)
    increment(self.tries, T.indicator(goal))
    local head, body = Database.copy_clause(clause)
    if not self.trail:unify(head, goal) then return false end
    self.goals = body and entry(body, barrier, context, continuation) or continuation
    return true
end
function E:user_call(goal, context)
    local key = T.indicator(goal)
    if not self.database.predicates[key] then T.fault(T.compound("existence_error", "procedure", T.indicator_term(key))) end
    local candidates, height = self.database:candidates(goal), #self.choices
    if #candidates == 0 then return false end
    if #candidates > 1 then self:create_choice("CLAUSES", self.goals, { goal = goal, candidates = candidates, next_candidate = 2, barrier = height, context = context }) end
    return self:try_clause(candidates[1], goal, height, context, self.goals)
end
function E:control(goal, barrier, context)
    local name = T.is_compound(goal) and goal.name or goal
    local args = T.is_compound(goal) and goal.args or {}
    local continuation, height = self.goals, #self.choices
    if name == "," then self.goals = entry(args[1], barrier, context, entry(args[2], barrier, context, continuation))
    elseif name == "!" then self:cut(barrier)
    elseif name == ";" then
        self:create_choice("ALT", entry(args[2], barrier, context, continuation))
        local left = T.dereference(args[1])
        if is(left, "->", 2) then
            self.goals = entry(left.args[1], height + 1, context, entry(marker("ITE", height), barrier, context, entry(left.args[2], barrier, context, continuation)))
        else self.goals = entry(left, barrier, context, continuation) end
    elseif name == "->" then self.goals = entry(args[1], height, context, entry(marker("ITE", height), barrier, context, entry(args[2], barrier, context, continuation)))
    elseif name == "\\+" then
        self:create_choice("ALT", continuation)
        self.goals = entry(T.compound("call", args[1]), barrier, context, entry(marker("NAF", height), barrier, context, continuation))
    elseif name == "call" then
        local target = T.dereference(args[1])
        if T.is_variable(target) then T.fault("instantiation_error") end
        if type(target) == "number" then T.fault(T.type_error("callable", target)) end
        if #args > 1 then
            local arguments = {}
            if T.is_compound(target) then append(arguments, target.args) end
            for i = 2, #args do arguments[#arguments + 1] = args[i] end
            target = T.application(T.is_compound(target) and target.name or target, arguments)
        end
        local converted = goal_conversion(target)
        if not converted then T.fault(T.type_error("callable", target)) end
        self.goals = entry(converted, height, context, continuation)
    elseif name == "catch" then
        local frame = self:create_choice("CATCH", continuation, { catcher = args[2], recovery = args[3], parent = context })
        self.goals = entry(T.compound("call", args[1]), barrier, frame, entry(marker("EXIT", frame), barrier, context, continuation))
    end
    return true
end
function E:marker(value)
    local kind, payload = value.marker_kind, value.payload
    if kind == "ITE" or kind == "NAF" then self:cut(payload); return kind == "ITE"
    elseif kind == "EXIT" then if self.choices[#self.choices] == payload then table.remove(self.choices) end; return true end
    payload.results[#payload.results + 1] = T.copy(payload.template)
    return false
end
local function fresh_list(count)
    local values = {}
    for i = 1, count do values[i] = T.variable() end
    return T.make_list(values)
end
function E:between(args)
    local lower = Predicates.require_integer(args[1])
    local upper = Predicates.require_integer(args[2])
    local value = T.dereference(args[3])
    if not T.is_variable(value) and type(value) ~= "number" then T.fault(T.type_error("integer", value)) end
    if type(value) == "number" then return lower <= value and value <= upper end
    if lower > upper then return false end
    if lower < upper then self:create_choice("BETWEEN", self.goals, { upper = upper, target = value, next_value = lower + 1 }) end
    return self.trail:unify(value, lower)
end
function E:length(args)
    local sequence, number = args[1], T.dereference(args[2])
    if not T.is_variable(number) and type(number) ~= "number" then T.fault(T.type_error("integer", number)) end
    if type(number) == "number" and number < 0 then T.fault(T.domain_error("not_less_than_zero", number)) end
    local elements, tail = T.list_parts(sequence)
    local count = #elements
    if tail == "[]" then return self.trail:unify(number, count) end
    if not T.is_variable(tail) then T.fault(T.type_error("list", sequence)) end
    if type(number) == "number" then
        if number < count then return false end
        return self.trail:unify(tail, fresh_list(number - count))
    end
    self:create_choice("LENGTH", self.goals, { tail = tail, number = number, count = count, next_length = count + 1 })
    return self.trail:unify(tail, "[]") and self.trail:unify(number, count)
end
function E:step()
    local current = self.goals
    local goal, barrier, context = current.goal, current.barrier, current.context
    self.goals, self.context = current.next, context
    if type(goal) == "table" and goal.kind == "marker" then return self:marker(goal) end
    goal = T.dereference(goal)
    local key = T.indicator(goal)
    self.current_key = key
    if controls[key] then return self:control(goal, barrier, context) end
    self:infer(key)
    if is(goal, "findall", 3) then
        local frame = self:create_choice("FINDALL", self.goals, { template = goal.args[1], result = goal.args[3], results = {} })
        self.goals = entry(T.compound("call", goal.args[2]), barrier, context, entry(marker("COLLECT", frame), barrier, context))
        return true
    elseif is(goal, "throw", 1) then
        local ball = T.dereference(goal.args[1])
        if T.is_variable(ball) then T.fault("instantiation_error") end
        error({ category = "ball", term = ball }, 0)
    elseif is(goal, "between", 3) then return self:between(goal.args)
    elseif is(goal, "length", 2) then return self:length(goal.args)
    elseif Predicates.deterministic[key] then
        return Predicates.execute(goal, self.trail, function(term, quoted)
            self.output[#self.output + 1] = term == nil and "\n" or W.new(nil, quoted):write(term)
        end)
    end
    return self:user_call(goal, context)
end
function E:backtrack()
    while true do
        self.backtracks = self.backtracks + 1
        local choice
        while #self.choices > 0 do
            choice = self.choices[#self.choices]
            self.trail:undo(choice.mark)
            if choice.kind == "CATCH" then table.remove(self.choices) else break end
        end
        if #self.choices == 0 then return false end
        if choice.kind == "ALT" then table.remove(self.choices); self.goals = choice.resume; return true
        elseif choice.kind == "CLAUSES" then
            local clause = choice.candidates[choice.next_candidate]
            if choice.next_candidate == #choice.candidates then table.remove(self.choices) else choice.next_candidate = choice.next_candidate + 1 end
            if self:try_clause(clause, choice.goal, choice.barrier, choice.context, choice.resume) then return true end
        elseif choice.kind == "BETWEEN" then
            self:infer(T.signature("between", 3))
            local value = choice.next_value
            if value == choice.upper then table.remove(self.choices) else choice.next_value = value + 1 end
            if self.trail:unify(choice.target, value) then self.goals = choice.resume; return true end
        elseif choice.kind == "LENGTH" then
            self:infer(T.signature("length", 2))
            local count = choice.next_length
            choice.next_length = count + 1
            if self.trail:unify(choice.tail, fresh_list(count - choice.count)) and self.trail:unify(choice.number, count) then self.goals = choice.resume; return true end
        elseif choice.kind == "FINDALL" then
            table.remove(self.choices)
            if self.trail:unify(T.make_list(choice.results), choice.result) then self.goals = choice.resume; return true end
        end
    end
end
function E:handle_exception(term)
    local ball, frame = T.copy(term), self.context
    while frame do
        local index
        for i, choice in ipairs(self.choices) do if choice == frame then index = i; break end end
        assert(index)
        self:cut(index - 1)
        self.trail:undo(frame.mark)
        local mark = self.trail:mark()
        if self.trail:unify(T.copy(ball), frame.catcher) then
            self.goals = entry(T.compound("call", frame.recovery), #self.choices, frame.parent, frame.resume)
            return true
        end
        self.trail:undo(mark)
        frame = frame.parent
    end
    self.answers[#self.answers + 1] = "uncaught exception: " .. W.new():write(ball)
    return false
end
function E:run()
    while true do
        local ok, result = pcall(function()
            if not self.goals then
                self.solutions = self.solutions + 1
                local text = answer(self.variables)
                if self.solutions == self.limit or #self.choices == 0 then self.answers[#self.answers + 1] = text .. "."; return "finished" end
                self.answers[#self.answers + 1] = text .. " ;"
                return self:backtrack()
            end
            local success = self:step()
            if not success then success = self:backtrack() end
            return success
        end)
        if ok then
            if result == "finished" then break end
            if not result then self.answers[#self.answers + 1] = "false."; break end
        else
            if type(result) ~= "table" then error(result, 0) end
            if result.category == "limit" then self.answers[#self.answers + 1] = "inference limit exceeded"; break
            elseif result.category == "fault" then
                if not self:handle_exception(T.compound("error", result.term, T.indicator_term(self.current_key))) then break end
            elseif result.category == "ball" then if not self:handle_exception(result.term) then break end
            else error(result, 0) end
        end
    end
    return { self.solutions, self.inferences, self.choicepoints, self.backtracks }
end
local function statistics(prefix, count)
    return string.format("%s solutions=%d inferences=%d choicepoints=%d backtracks=%d", prefix, count[1], count[2], count[3], count[4])
end
local function read(path)
    local input = assert(io.open(path, "r"))
    local result = input:read("*a")
    input:close()
    return result
end
local consultant = C.new()
for _, file in ipairs({ "prelude.pl", "program.pl" }) do consultant:consult(file, read("input/" .. file)) end
consultant:finish()
local answers, writes, stats, calls, tries, totals = {}, {}, {}, {}, {}, { 0, 0, 0, 0 }
local query_number = 0
for source in io.lines("input/queries.txt") do
    query_number = query_number + 1
    answers[#answers + 1] = source
    writes[#writes + 1] = "== query " .. query_number .. " ==\n"
    local start = assert(source:find("?- ", 1, true))
    local limit = start > 1 and tonumber(source:sub(1, start - 1)) or nil
    local body_start = start + 3
    local reader = Reader.new(source:sub(body_start), body_start)
    local ok, query = pcall(reader.clause, reader, true)
    if not ok then
        if type(query) ~= "table" or query.category ~= "syntax" then error(query, 0) end
        answers[#answers + 1] = "syntax error at column " .. query.token.column .. ": " .. query.message
        stats[#stats + 1] = "query " .. query_number .. ": syntax error"
    else
        local variables = {}
        for _, name in ipairs(reader.order) do if name:sub(1, 1) ~= "_" then variables[#variables + 1] = { name, reader.names[name] } end end
        local engine = E.new(consultant.database, query, variables, limit, calls, tries)
        local counts = engine:run()
        for i = 1, 4 do totals[i] = totals[i] + counts[i] end
        append(answers, engine.answers)
        local output = table.concat(engine.output)
        if #output > 0 and output:sub(-1) ~= "\n" then output = output .. "\n" end
        writes[#writes + 1] = output
        stats[#stats + 1] = statistics("query " .. query_number .. ":", counts)
    end
end
stats[#stats + 1] = statistics("total:", totals)
stats[#stats + 1] = "== profile =="
local keys, displayed = {}, {}
for key in pairs(calls) do keys[#keys + 1], displayed[key] = key, predicate_name(key) end
table.sort(keys, function(a, b) return calls[a] > calls[b] or calls[a] == calls[b] and displayed[a] < displayed[b] end)
for _, key in ipairs(keys) do
    local line = displayed[key] .. " calls=" .. calls[key]
    if consultant.database.predicates[key] then line = line .. " tries=" .. (tries[key] or 0) end
    stats[#stats + 1] = line
end
for filename, lines in pairs({ ["consult.txt"] = consultant.lines, ["listing.txt"] = listing(consultant.database), ["answers.txt"] = answers, ["stats.txt"] = stats }) do
    local output = assert(io.open("output/" .. filename, "w"))
    if #lines > 0 then output:write(table.concat(lines, "\n"), "\n") end
    output:close()
end
local output = assert(io.open("output/write_output.txt", "w"))
output:write(table.concat(writes))
output:close()
