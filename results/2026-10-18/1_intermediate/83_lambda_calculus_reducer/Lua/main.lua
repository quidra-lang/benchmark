local function variable(name) return {kind="variable", name=name} end
local function abstraction(name, body) return {kind="abstraction", name=name, left=body} end
local function application(func, argument) return {kind="application", left=func, right=argument} end
local function free_variables(term)
    if term.free then return term.free end
    local result = {}
    if term.kind == "variable" then result[term.name] = true
    elseif term.kind == "abstraction" then for name in pairs(free_variables(term.left)) do if name ~= term.name then result[name] = true end end
    elseif term.kind == "application" then for name in pairs(free_variables(term.left)) do result[name] = true end; for name in pairs(free_variables(term.right)) do result[name] = true end end
    term.free = result
    return result
end
local function ordered_names(set) local names = {}; for name in pairs(set) do names[#names + 1] = name end; table.sort(names); return names end
local function print_term(term, at_end, debruijn)
    if term.kind == "variable" or term.kind == "macro" or term.kind == "constant" then return term.name
    elseif term.kind == "index" then return tostring(term.value)
    elseif term.kind == "numeral" then return "#" .. term.value
    elseif term.kind == "abstraction" then
        local names, body = {}, term
        while body.kind == "abstraction" do names[#names + 1] = body.name; body = body.left end
        local text
        if debruijn then text = string.rep("\\", #names) .. print_term(body, true, true)
        else text = "\\" .. table.concat(names, " ") .. ". " .. print_term(body, true, false) end
        return at_end and text or "(" .. text .. ")"
    end
    local left = print_term(term.left, false, debruijn)
    local right = term.right.kind == "application" and "(" .. print_term(term.right, true, debruijn) .. ")" or print_term(term.right, at_end, debruijn)
    return left .. " " .. right
end
local function substitute(term, name, replacement)
    if term.kind == "variable" then return term.name == name and replacement or term end
    if term.kind == "application" then return application(substitute(term.left, name, replacement), substitute(term.right, name, replacement)) end
    if term.kind ~= "abstraction" or term.name == name or not free_variables(term.left)[name] then return term end
    local binder, body = term.name, term.left
    if free_variables(replacement)[binder] then
        local base, index = binder:gsub("%d+$", ""), 1
        while free_variables(replacement)[base .. index] or free_variables(body)[base .. index] do index = index + 1 end
        binder = base .. index
        body = substitute(body, term.name, variable(binder))
    end
    return abstraction(binder, substitute(body, name, replacement))
end
local function name_sequence(index) return string.char(97 + index % 26) .. (index >= 26 and tostring(index // 26) or "") end
local function canonical(term)
    local free, counter, bound = free_variables(term), 0, {}
    local function visit(term)
        if term.kind == "variable" then
            local stack = bound[term.name]
            return stack and #stack > 0 and variable(stack[#stack]) or term
        elseif term.kind == "application" then return application(visit(term.left), visit(term.right)) end
        local name
        repeat name = name_sequence(counter); counter = counter + 1 until not free[name]
        bound[term.name] = bound[term.name] or {}
        local stack = bound[term.name]
        stack[#stack + 1] = name
        local body = visit(term.left)
        stack[#stack] = nil
        return abstraction(name, body)
    end
    return visit(term)
end
local function de_bruijn(term, bound)
    bound = bound or {}
    if term.kind == "variable" then
        for i = #bound, 1, -1 do if bound[i] == term.name then return {kind="index", value=#bound - i} end end
        return term
    elseif term.kind == "application" then return application(de_bruijn(term.left, bound), de_bruijn(term.right, bound)) end
    bound[#bound + 1] = term.name
    local body = de_bruijn(term.left, bound)
    bound[#bound] = nil
    return abstraction("", body)
end
local function from_de_bruijn(term)
    local counter, free, bound = 0, free_variables(term), {}
    local function visit(term)
        if term.kind == "variable" then return term end
        if term.kind == "index" then return variable(bound[#bound - term.value]) end
        if term.kind == "application" then return application(visit(term.left), visit(term.right)) end
        local name
        repeat name = name_sequence(counter); counter = counter + 1 until not free[name]
        bound[#bound + 1] = name
        local body = visit(term.left)
        bound[#bound] = nil
        return abstraction(name, body)
    end
    return visit(term)
end
local function equivalent(a, b) return print_term(de_bruijn(a), true, true) == print_term(de_bruijn(b), true, true) end
local function fail(format, ...) error({reason=string.format(format, ...)}, 0) end
local function has(items, value) for _, item in ipairs(items) do if item == value then return true end end; return false end
local function lower(c) return c ~= "" and c >= "a" and c <= "z" end
local function upper(c) return c ~= "" and c >= "A" and c <= "Z" end
local function digit(c) return c ~= "" and c >= "0" and c <= "9" end
local function lex(line, text, offset)
    local tokens, i = {}, 1
    while i <= #text do
        local c = text:sub(i, i)
        if c == " " then i = i + 1
        else
            local start, kind = i, nil
            if ("\\.()=;"):find(c, 1, true) then kind = c; i = i + 1
            elseif lower(c) then kind = "variable"; repeat i = i + 1; c = text:sub(i, i) until not lower(c) and not digit(c)
            elseif upper(c) then kind = "macro"; repeat i = i + 1; c = text:sub(i, i) until not upper(c) and not digit(c) and c ~= "_"
            elseif c == "#" and digit(text:sub(i + 1, i + 1)) then kind = "numeral"; i = i + 1; repeat i = i + 1 until not digit(text:sub(i, i))
            else fail("column %d: unexpected character '%s'", offset + i, c) end
            local token = {kind=kind, text=text:sub(start, i - 1), column=offset + start}
            if kind == "numeral" then token.value = tonumber(token.text:sub(2)) end
            tokens[#tokens + 1] = token
        end
    end
    tokens[#tokens + 1] = {kind="end", column=#line + 1}
    return tokens
end
local Parser = {}
Parser.__index = Parser
function Parser:peek() return self.tokens[self.at] end
function Parser:expect(kind)
    local token = self:peek()
    if token.kind ~= kind then
        local notation = kind == "variable" and "variable" or kind == "macro" and "macro name" or "'" .. kind .. "'"
        fail("column %d: expected %s", token.column, notation)
    end
    self.at = self.at + 1
    return token
end
function Parser:term()
    local elements = {}
    while true do
        local token = self:peek()
        if token.kind ~= "variable" and token.kind ~= "macro" and token.kind ~= "numeral" and token.kind ~= "(" then break end
        self.at = self.at + 1
        if token.kind == "(" then local value = self:term(); self:expect(")"); elements[#elements + 1] = value
        else elements[#elements + 1] = {kind=token.kind, name=token.text, value=token.value} end
    end
    if self:peek().kind == "\\" then
        self.at = self.at + 1
        local names = {self:expect("variable").text}
        while self:peek().kind == "variable" do names[#names + 1] = self:expect("variable").text end
        self:expect(".")
        local value = self:term()
        for i = #names, 1, -1 do value = abstraction(names[i], value) end
        elements[#elements + 1] = value
    end
    if #elements == 0 then fail("column %d: expected term", self:peek().column) end
    local result = elements[1]
    for i = 2, #elements do result = application(result, elements[i]) end
    return result
end
function Parser:finish() local token = self:peek(); if token.kind ~= "end" then fail("column %d: unexpected '%s'", token.column, token.text) end end
local function references(term, result)
    result = result or {}
    if term.kind == "macro" then result[#result + 1] = term.name
    elseif term.kind == "abstraction" then references(term.left, result)
    elseif term.kind == "application" then references(term.left, result); references(term.right, result) end
    return result
end
local reserved = {"S", "K", "I", "NORMAL", "APPLICATIVE", "CBN", "CBV"}
local Workbench = {}
Workbench.__index = Workbench
function Workbench.new()
    local body = application(application(variable("x"), variable("z")), application(variable("y"), variable("z")))
    return setmetatable({macros={I=abstraction("x", variable("x")), K=abstraction("x", abstraction("y", variable("x"))), S=abstraction("x", abstraction("y", abstraction("z", body)))}, steps=false, eta=false, limit=10000}, Workbench)
end
function Workbench:emit(format, ...) io.write(string.format(format, ...), "\n") end
function Workbench:expand(term)
    if term.kind == "variable" then return term end
    if term.kind == "macro" then local value = self.macros[term.name]; if not value then fail("unbound macro %s", term.name) end; return self:expand(value) end
    if term.kind == "numeral" then local body = variable("x"); for _ = 1, term.value do body = application(variable("f"), body) end; return abstraction("f", abstraction("x", body)) end
    if term.kind == "abstraction" then return abstraction(term.name, self:expand(term.left)) end
    return application(self:expand(term.left), self:expand(term.right))
end
function Workbench:depends(name, target, seen)
    if name == target then return true end
    if seen[name] or name == "S" or name == "K" or name == "I" or not self.macros[name] then return false end
    seen[name] = true
    for _, reference in ipairs(references(self.macros[name])) do if self:depends(reference, target, seen) then return true end end
    return false
end
local function eta_redex(term)
    return term.kind == "abstraction" and term.left.kind == "application" and term.left.right.kind == "variable" and term.left.right.name == term.name and not free_variables(term.left.left)[term.name]
end
local function one_step(term, strategy, eta)
    if term.kind == "application" then
        if (strategy == "NORMAL" or strategy == "CBN") and term.left.kind == "abstraction" then return substitute(term.left.left, term.left.name, term.right), "beta" end
        local value, kind = one_step(term.left, strategy, eta)
        if value then return application(value, term.right), kind end
        if strategy == "CBN" then return end
        value, kind = one_step(term.right, strategy, eta)
        if value then return application(term.left, value), kind end
        if term.left.kind == "abstraction" and (strategy ~= "CBV" or term.right.kind == "variable" or term.right.kind == "abstraction") then return substitute(term.left.left, term.left.name, term.right), "beta" end
    elseif term.kind == "abstraction" and strategy ~= "CBN" and strategy ~= "CBV" then
        if strategy == "NORMAL" and eta and eta_redex(term) then return term.left.left, "eta" end
        local value, kind = one_step(term.left, strategy, eta)
        if value then return abstraction(term.name, value), kind end
        if eta and eta_redex(term) then return term.left.left, "eta" end
    end
end
function Workbench:reduce(term, strategy, eta, display)
    local count = 0
    while true do
        local next_term, kind = one_step(term, strategy, eta)
        if not next_term then return term, count, true end
        if count == self.limit then return term, count, false end
        term, count = next_term, count + 1
        if display then self:emit("step %d (%s): %s", count, kind, print_term(term, true, false)) end
    end
end
local function size(term) if term.kind == "variable" then return 1 elseif term.kind == "abstraction" then return 1 + size(term.left) else return 1 + size(term.left) + size(term.right) end end
local function depth(term) if term.kind == "variable" then return 1 elseif term.kind == "abstraction" then return 1 + depth(term.left) else return 1 + math.max(depth(term.left), depth(term.right)) end end
local function resolve(value) if value.link then value.link = resolve(value.link); return value.link end; return value end
local function occurs(variable_type, value)
    value = resolve(value)
    return variable_type == value or value.left and (occurs(variable_type, value.left) or occurs(variable_type, value.right))
end
local function unify(a, b)
    a, b = resolve(a), resolve(b)
    if a == b then return end
    if not a.left then if occurs(a, b) then error("not typable", 0) end; a.link = b; return end
    if not b.left then unify(b, a); return end
    unify(a.left, b.left); unify(a.right, b.right)
end
local function infer_type(term)
    local ok, result = pcall(function()
        local free, bound = {}, {}
        local function infer(term)
            if term.kind == "variable" then
                local stack = bound[term.name]
                if stack and #stack > 0 then return stack[#stack] end
                free[term.name] = free[term.name] or {}
                return free[term.name]
            elseif term.kind == "abstraction" then
                local argument = {}
                bound[term.name] = bound[term.name] or {}
                local stack = bound[term.name]; stack[#stack + 1] = argument
                local body = infer(term.left); stack[#stack] = nil
                return {left=argument, right=body}
            end
            local func, argument, value = infer(term.left), infer(term.right), {}
            unify(func, {left=argument, right=value})
            return value
        end
        local principal, names, counter = infer(term), {}, 0
        local function print_type(value)
            value = resolve(value)
            if not value.left then if not names[value] then names[value] = name_sequence(counter); counter = counter + 1 end; return names[value] end
            local left = print_type(value.left)
            if resolve(value.left).left then left = "(" .. left .. ")" end
            return left .. " -> " .. print_type(value.right)
        end
        return print_type(principal)
    end)
    if not ok and result ~= "not typable" then error(result, 0) end
    return ok and result or "not typable"
end
local function church(term)
    if term.kind == "abstraction" and term.left.kind == "abstraction" then
        local outer, inner, body, count = term.name, term.left.name, term.left.left, 0
        while body.kind == "application" and body.left.kind == "variable" and body.left.name == outer do count = count + 1; body = body.right end
        if body.kind == "variable" and body.name == inner then return tostring(count) end
        if term.left.left.kind == "variable" and term.left.left.name == outer then return "true" end
    end
    if term.kind == "abstraction" and term.left.kind == "application" and term.left.left.kind == "application" then
        local body, func = term.left, term.left.left.left
        if func.kind == "variable" and func.name == term.name and not free_variables(body.left.right)[term.name] and not free_variables(body.right)[term.name] then return "(" .. church(body.left.right) .. ", " .. church(body.right) .. ")" end
    end
    return print_term(canonical(term), true, false)
end
local function constant(name) return {kind="constant", name=name} end
local function abstract_ski(name, term)
    if not free_variables(term)[name] then return application(constant("K"), term) end
    if term.kind == "variable" then return constant("I") end
    if term.right.kind == "variable" and term.right.name == name and not free_variables(term.left)[name] then return term.left end
    return application(application(constant("S"), abstract_ski(name, term.left)), abstract_ski(name, term.right))
end
local function ski(term)
    if term.kind == "variable" then return term elseif term.kind == "application" then return application(ski(term.left), ski(term.right)) end
    return abstract_ski(term.name, ski(term.left))
end
local function ski_step(term)
    local head, arguments = term, {}
    while head.kind == "application" do table.insert(arguments, 1, head.right); head = head.left end
    local result, used, kind
    if head.kind == "constant" then
        if head.name == "I" and #arguments >= 1 then result, used, kind = arguments[1], 1, "I"
        elseif head.name == "K" and #arguments >= 2 then result, used, kind = arguments[1], 2, "K"
        elseif head.name == "S" and #arguments >= 3 then result, used, kind = application(application(arguments[1], arguments[3]), application(arguments[2], arguments[3])), 3, "S" end
    end
    if result then for i = used + 1, #arguments do result = application(result, arguments[i]) end; return result, kind end
    for i, argument in ipairs(arguments) do
        local next_term, contraction = ski_step(argument)
        if next_term then
            result = head
            for j, item in ipairs(arguments) do result = application(result, j == i and next_term or item) end
            return result, contraction
        end
    end
end
local function reify(code, environment, inside)
    while code.kind == "index" and code.value >= inside do
        local closure = environment[code.value - inside + 1]
        code, environment, inside = closure.code, closure.environment, 0
    end
    if code.kind == "variable" or code.kind == "index" then return code end
    if code.kind == "abstraction" then return abstraction("", reify(code.left, environment, inside + 1)) end
    return application(reify(code.left, environment, inside), reify(code.right, environment, inside))
end
function Workbench:kam(term)
    local code, environment, stack, count = de_bruijn(term), {}, {}, 0
    while true do
        local kind = code.kind == "application" and "push" or code.kind == "index" and "access" or code.kind == "abstraction" and #stack > 0 and "grab" or nil
        if not kind then break end
        if count == self.limit then self:emit("no result within %d transitions", self.limit); return end
        count = count + 1
        if kind == "push" then stack[#stack + 1] = {code=code.right, environment=environment}; code = code.left
        elseif kind == "grab" then
            local next_environment = {table.remove(stack)}
            for _, closure in ipairs(environment) do next_environment[#next_environment + 1] = closure end
            environment, code = next_environment, code.left
        else local closure = environment[code.value + 1]; code, environment = closure.code, closure.environment end
        if self.steps then self:emit("step %d (%s): %s [env %d, stack %d]", count, kind, print_term(code, true, true), #environment, #stack) end
    end
    local result = reify(code, environment, 0)
    for i = #stack, 1, -1 do result = application(result, reify(stack[i].code, stack[i].environment, 0)) end
    self:emit("result: %s (transitions: %d)", print_term(from_de_bruijn(result), true, false), count)
end
function Workbench:command(line)
    if line == "" or line:sub(1, 2) == "--" then return end
    local space = line:find(" ", 1, true)
    local command, arguments, offset = line, "", #line
    if space then command, arguments, offset = line:sub(1, space - 1), line:sub(space + 1), space end
    if not has({"let","unlet","macros","steps","eta","limit","expand","subst","reduce","equal","alpha","debruijn","fv","size","depth","type","church","ski","skireduce","kam"}, command) then fail("unknown command %s", command) end
    if has({"unlet","macros","steps","eta","limit"}, command) then
        local words = {}; for word in arguments:gmatch("%S+") do words[#words + 1] = word end
        if command == "steps" or command == "eta" then
            if #words ~= 1 or words[1] ~= "on" and words[1] ~= "off" then fail("bad argument") end
            self[command] = words[1] == "on"
        elseif command == "limit" then
            if #words ~= 1 or #words[1] < 1 or #words[1] > 5 or not words[1]:match("^%d+$") then fail("bad argument") end
            local value = tonumber(words[1]); if value < 1 or value > 10000 then fail("bad argument") end; self.limit = value
        elseif command == "macros" then
            if #words ~= 0 then fail("bad argument") end
            local names = {}; for name in pairs(self.macros) do if name ~= "S" and name ~= "K" and name ~= "I" then names[#names + 1] = name end end; table.sort(names)
            if #names == 0 then self:emit("(none)") end
            for _, name in ipairs(names) do self:emit("%s = %s", name, print_term(self.macros[name], true, false)) end
        else
            if #words ~= 1 or not words[1]:match("^[A-Z][A-Z0-9_]*$") then fail("bad argument") end
            local name = words[1]
            if has(reserved, name) then fail("reserved name %s", name) end
            if not self.macros[name] then fail("unbound macro %s", name) end
            local users = {}
            for other, value in pairs(self.macros) do if has(references(value), name) then users[#users + 1] = other end end
            table.sort(users)
            if #users > 0 then fail("%s is used by %s", name, users[1]) end
            self.macros[name] = nil; self:emit("removed %s", name)
        end
        return
    end
    local parser = setmetatable({tokens=lex(line, arguments, offset), at=1}, Parser)
    local name, strategy = nil, "NORMAL"
    if command == "let" or command == "subst" then name = parser:expect(command == "let" and "macro" or "variable").text; parser:expect("=") end
    if command == "reduce" and parser:peek().kind == "macro" and has({"NORMAL","APPLICATIVE","CBN","CBV"}, parser:peek().text) then strategy = parser:peek().text; parser.at = parser.at + 1 end
    local first, second = parser:term(), nil
    if command == "subst" or command == "equal" or command == "alpha" then parser:expect(";"); second = parser:term() end
    parser:finish()
    if command == "let" then
        if has(reserved, name) then fail("reserved name %s", name) end
        local seen = {}
        for _, reference in ipairs(references(first)) do
            if self:depends(reference, name, seen) then fail("recursive definition of %s", name) end
            if not self.macros[reference] then fail("unbound macro %s", reference) end
        end
        local free = ordered_names(free_variables(first))
        if #free > 0 then fail("free variable %s in definition of %s", free[1], name) end
        local prefix = self.macros[name] and "redefined" or "defined"
        self.macros[name] = first; self:emit("%s %s", prefix, name); return
    end
    first = self:expand(first)
    if second then second = self:expand(second) end
    if command == "expand" then self:emit("%s", print_term(first, true, false))
    elseif command == "subst" then self:emit("%s", print_term(substitute(second, name, first), true, false))
    elseif command == "alpha" then self:emit(equivalent(first, second) and "yes" or "no")
    elseif command == "equal" then
        local a, _, ok_a = self:reduce(first, "NORMAL", self.eta, false)
        local b, _, ok_b = self:reduce(second, "NORMAL", self.eta, false)
        if not ok_a or not ok_b then self:emit("unknown")
        elseif equivalent(a, b) then self:emit("yes") else self:emit("no") end
    elseif command == "debruijn" then self:emit("%s", print_term(de_bruijn(first), true, true))
    elseif command == "fv" then local names = ordered_names(free_variables(first)); self:emit("%s", #names == 0 and "(none)" or table.concat(names, " "))
    elseif command == "size" then self:emit("%d", size(first)) elseif command == "depth" then self:emit("%d", depth(first))
    elseif command == "type" then self:emit("%s", infer_type(first))
    elseif command == "church" then local result, _, ok = self:reduce(first, "NORMAL", false, false); if ok then self:emit("%s", church(canonical(result))) else self:emit("no normal form within %d steps", self.limit) end
    elseif command == "ski" then self:emit("%s", print_term(ski(first), true, false))
    elseif command == "skireduce" then
        local value, count = ski(first), 0
        while true do
            local next_term, kind = ski_step(value)
            if not next_term then self:emit("result: %s (steps: %d)", print_term(value, true, false), count); break end
            if count == self.limit then self:emit("no normal form within %d steps", self.limit); break end
            value, count = next_term, count + 1
            if self.steps then self:emit("step %d (%s): %s", count, kind, print_term(value, true, false)) end
        end
    elseif command == "kam" then self:kam(first)
    elseif command == "reduce" then
        local result, count, ok = self:reduce(first, strategy, self.eta, self.steps)
        if ok then self:emit("result: %s (steps: %d)", print_term(canonical(result), true, false), count) else self:emit("no normal form within %d steps", self.limit) end
    end
end
local workbench = Workbench.new()
for line in io.lines() do
    if line == "quit" then break end
    local ok, caught = pcall(function() workbench:command(line) end)
    if not ok then if type(caught) ~= "table" or not caught.reason then error(caught, 0) end; workbench:emit("error: %s", caught.reason) end
end
