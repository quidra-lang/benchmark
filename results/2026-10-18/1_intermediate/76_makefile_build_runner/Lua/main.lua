local function trim(s)
    return (s:gsub("^ +", ""):gsub(" +$", ""))
end
local function words(s)
    local result = {}
    for word in s:gmatch("[^ ]+") do
        result[#result + 1] = word
    end
    return result
end
local function keys(t)
    local result = {}
    for key in pairs(t) do
        result[#result + 1] = key
    end
    table.sort(result)
    return result
end
local function unique(list)
    local result, seen = {}, {}
    for _, item in ipairs(list) do
        if not seen[item] then
            seen[item] = true
            result[#result + 1] = item
        end
    end
    return result
end
local function copy(list)
    local result = {}
    for i, item in ipairs(list) do
        result[i] = item
    end
    return result
end
local function match(pattern, word)
    local at = pattern:find("%", 1, true)
    if not at then
        return pattern == word and "" or nil
    end
    local a, b = pattern:sub(1, at - 1), pattern:sub(at + 1)
    if #word < #a + #b or word:sub(1, #a) ~= a or (#b > 0 and word:sub(-(#b)) ~= b) then
        return nil
    end
    return word:sub(#a + 1, #word - #b)
end
local function substitute(pattern, stem)
    local at = pattern:find("%", 1, true)
    return at and pattern:sub(1, at - 1) .. stem .. pattern:sub(at + 1) or pattern
end
local function replacement(word, pattern, value)
    local stem = match(pattern, word)
    if not stem then
        return word
    end
    return pattern:find("%", 1, true) and substitute(value, stem) or value
end
local function wildcard(pattern, name)
    local memo = {}
    local function visit(p, n)
        local key = p .. ":" .. n
        if memo[key] ~= nil then
            return memo[key]
        end
        local result = false
        local c = pattern:sub(p, p)
        if p > #pattern then
            result = n > #name
        elseif c == "*" then
            result = visit(p + 1, n) or (n <= #name and name:sub(n, n) ~= "/" and visit(p, n + 1))
        elseif n <= #name and (c == name:sub(n, n) or c == "?" and name:sub(n, n) ~= "/") then
            result = visit(p + 1, n + 1)
        end
        memo[key] = result
        return result
    end
    return visit(1, 1)
end
local limits = {
    subst = {3, 3},
    patsubst = {3, 3},
    strip = {1, 1},
    findstring = {2, 2},
    filter = {2, 2},
    ["filter-out"] = {2, 2},
    sort = {1, 1},
    word = {2, 2},
    wordlist = {3, 3},
    words = {1, 1},
    firstword = {1, 1},
    lastword = {1, 1},
    dir = {1, 1},
    notdir = {1, 1},
    suffix = {1, 1},
    basename = {1, 1},
    addsuffix = {2, 2},
    addprefix = {2, 2},
    wildcard = {1, 1},
    foreach = {3, 3},
    ["if"] = {2, 3},
    call = {1, 0},
    value = {1, 1},
    info = {1, 1},
    warning = {1, 1},
    error = {1, 1}
}
local M = {files = {}, clock = 0, output = {}}
function M:emit(s)
    self.output[#self.output + 1] = s
end
function M:fail(reason)
    error({location = self.location, reason = reason}, 0)
end
function M:clear()
    self.loaded, self.variables, self.rules, self.patterns, self.phony, self.goal =
        false,
        {},
        {},
        {},
        {},
        nil
end
function M:resetExpansion()
    self.location, self.scopes, self.expanding, self.automatic = "make", {}, {}, {}
end
function M:glob(pattern)
    local result = {}
    for _, name in ipairs(keys(self.files)) do
        if wildcard(pattern, name) then
            result[#result + 1] = name
        end
    end
    return result
end
function M:reference(name)
    for i = #self.scopes, 1, -1 do
        local scope = self.scopes[i]
        if scope.call then
            if name:match("^[0-9]+$") then
                return scope.call[tonumber(name) + 1] or ""
            end
        elseif scope.name == name then
            return scope.word
        end
    end
    if self.automatic[name] ~= nil then
        return self.automatic[name]
    end
    local variable = self.variables[name]
    if not variable then
        return ""
    end
    if variable.simple then
        return variable.value
    end
    if self.expanding[name] then
        self:fail("Recursive variable '" .. name .. "' references itself (eventually)")
    end
    self.expanding[name] = true
    local result = self:expand(variable.value)
    self.expanding[name] = nil
    return result
end
function M:closing(s, open)
    local opening = s:sub(open, open)
    local closing = opening == "(" and ")" or "}"
    local depth = 0
    for i = open, #s do
        local c = s:sub(i, i)
        if c == opening then
            depth = depth + 1
        elseif c == closing then
            depth = depth - 1
            if depth == 0 then
                return i
            end
        end
    end
    self:fail("unterminated variable reference")
end
function M:outside(s, wanted)
    local found, i = nil, 1
    while i <= #s do
        local c, next = s:sub(i, i), s:sub(i + 1, i + 1)
        if c == "$" then
            if next == "(" or next == "{" then
                i = self:closing(s, i + 1)
            else
                i = i + 1
            end
        elseif c == wanted and not found then
            found = i
        end
        i = i + 1
    end
    return found
end
function M:expand(s)
    local result, i = {}, 1
    while i <= #s do
        local c = s:sub(i, i)
        if c ~= "$" then
            result[#result + 1] = c
            i = i + 1
        else
            i = i + 1
            c = s:sub(i, i)
            if c == "" then
                break
            end
            if c == "$" then
                result[#result + 1] = "$"
                i = i + 1
            elseif c == "(" or c == "{" then
                local finish = self:closing(s, i)
                local content = s:sub(i + 1, finish - 1)
                local space = content:find(" ", 1, true)
                if space and limits[content:sub(1, space - 1)] then
                    result[#result + 1] =
                        self:func(
                        content:sub(1, space - 1),
                        content:sub(space + 1):gsub("^ +", ""),
                        c
                    )
                else
                    local name = self:expand(content)
                    local colon = name:find(":", 1, true)
                    local equal = colon and name:find("=", colon + 1, true)
                    if equal then
                        local from, to = name:sub(colon + 1, equal - 1), name:sub(equal + 1)
                        if not from:find("%", 1, true) then
                            from, to = "%" .. from, "%" .. to
                        end
                        local list = words(self:reference(name:sub(1, colon - 1)))
                        for n, word in ipairs(list) do
                            list[n] = replacement(word, from, to)
                        end
                        result[#result + 1] = table.concat(list, " ")
                    else
                        result[#result + 1] = self:reference(name)
                    end
                end
                i = finish + 1
            else
                result[#result + 1] = self:reference(c)
                i = i + 1
            end
        end
    end
    return table.concat(result)
end
function M:func(name, text, opening)
    local bounds, args, depth, start = limits[name], {}, 0, 1
    local closing = opening == "(" and ")" or "}"
    for i = 1, #text do
        local c = text:sub(i, i)
        if c == opening then
            depth = depth + 1
        elseif c == closing then
            depth = depth - 1
        end
        if c == "," and depth == 0 and (bounds[2] == 0 or #args < bounds[2] - 1) then
            args[#args + 1] = text:sub(start, i - 1)
            start = i + 1
        end
    end
    args[#args + 1] = text:sub(start)
    if #args < bounds[1] then
        self:fail("insufficient number of arguments (" .. #args .. ") to function '" .. name .. "'")
    end
    if name == "if" then
        if trim(self:expand(args[1])) ~= "" then
            return self:expand(args[2])
        end
        return args[3] and self:expand(args[3]) or ""
    end
    if name == "foreach" then
        local variable = trim(self:expand(args[1]))
        local list, result = words(self:expand(args[2])), {}
        for _, word in ipairs(list) do
            self.scopes[#self.scopes + 1] = {name = variable, word = word}
            result[#result + 1] = self:expand(args[3])
            self.scopes[#self.scopes] = nil
        end
        return table.concat(result, " ")
    end
    for i, value in ipairs(args) do
        args[i] = self:expand(value)
        if name ~= "subst" and name ~= "call" then
            args[i] = trim(args[i])
        end
    end
    if name == "call" then
        args[1] = trim(args[1])
        local variable = self.variables[args[1]]
        if not variable then
            return ""
        end
        if variable.simple then
            return variable.value
        end
        self.scopes[#self.scopes + 1] = {call = args}
        local result = self:expand(variable.value)
        self.scopes[#self.scopes] = nil
        return result
    elseif name == "subst" then
        if args[1] == "" then
            return args[3]
        end
        local result, start = {}, 1
        while true do
            local at = args[3]:find(args[1], start, true)
            if not at then
                result[#result + 1] = args[3]:sub(start)
                break
            end
            result[#result + 1] = args[3]:sub(start, at - 1) .. args[2]
            start = at + #args[1]
        end
        return table.concat(result)
    elseif name == "patsubst" then
        local list = words(args[3])
        for i, word in ipairs(list) do
            list[i] = replacement(word, args[1], args[2])
        end
        return table.concat(list, " ")
    elseif name == "strip" then
        return table.concat(words(args[1]), " ")
    elseif name == "findstring" then
        return args[2]:find(args[1], 1, true) and args[1] or ""
    elseif name == "filter" or name == "filter-out" then
        local result = {}
        for _, word in ipairs(words(args[2])) do
            local matched = false
            for _, pattern in ipairs(words(args[1])) do
                if match(pattern, word) then
                    matched = true
                    break
                end
            end
            if matched == (name == "filter") then
                result[#result + 1] = word
            end
        end
        return table.concat(result, " ")
    elseif name == "sort" then
        local list = unique(words(args[1]))
        table.sort(list)
        return table.concat(list, " ")
    elseif name == "word" then
        if not args[1]:match("^[0-9]+$") then
            self:fail("non-numeric first argument to 'word' function: '" .. args[1] .. "'")
        end
        local n = tonumber(args[1])
        if n == 0 then
            self:fail("first argument to 'word' function must be greater than 0")
        end
        return words(args[2])[n] or ""
    elseif name == "wordlist" then
        if not args[1]:match("^[0-9]+$") then
            self:fail("non-numeric first argument to 'wordlist' function: '" .. args[1] .. "'")
        end
        if not args[2]:match("^[0-9]+$") then
            self:fail("non-numeric second argument to 'wordlist' function: '" .. args[2] .. "'")
        end
        local a, b = tonumber(args[1]), tonumber(args[2])
        if a == 0 then
            self:fail("invalid first argument to 'wordlist' function: '" .. args[1] .. "'")
        end
        local list, result = words(args[3]), {}
        for i = a, math.min(b, #list) do
            result[#result + 1] = list[i]
        end
        return table.concat(result, " ")
    elseif name == "words" then
        return tostring(#words(args[1]))
    elseif name == "firstword" or name == "lastword" then
        local list = words(args[1])
        return list[name == "firstword" and 1 or #list] or ""
    elseif name == "dir" or name == "notdir" or name == "suffix" or name == "basename" then
        local result = {}
        for _, word in ipairs(words(args[1])) do
            local slash, dot = 0, 0
            for i = 1, #word do
                local c = word:sub(i, i)
                if c == "/" then
                    slash = i
                elseif c == "." then
                    dot = i
                end
            end
            if name == "dir" then
                result[#result + 1] = slash == 0 and "./" or word:sub(1, slash)
            elseif name == "notdir" then
                result[#result + 1] = word:sub(slash + 1)
            elseif name == "suffix" then
                if dot > slash then
                    result[#result + 1] = word:sub(dot)
                end
            else
                result[#result + 1] = dot > slash and word:sub(1, dot - 1) or word
            end
        end
        return table.concat(result, " ")
    elseif name == "addprefix" or name == "addsuffix" then
        local list = words(args[2])
        for i, word in ipairs(list) do
            list[i] = name == "addprefix" and args[1] .. word or word .. args[1]
        end
        return table.concat(list, " ")
    elseif name == "wildcard" then
        local result = {}
        for _, pattern in ipairs(words(args[1])) do
            for _, word in ipairs(self:glob(pattern)) do
                result[#result + 1] = word
            end
        end
        return table.concat(result, " ")
    elseif name == "value" then
        return self.variables[args[1]] and self.variables[args[1]].value or ""
    elseif name == "info" then
        self:emit(args[1])
    elseif name == "warning" then
        self:emit(self.location .. ": " .. args[1])
    elseif name == "error" then
        self:fail(args[1])
    end
    return ""
end
function M:register(target, prerequisites)
    local rule = self.rules[target]
    if not rule then
        rule = {target = target, prerequisites = {}, stem = ""}
        self.rules[target] = rule
    end
    for _, p in ipairs(prerequisites) do
        rule.prerequisites[#rule.prerequisites + 1] = p
    end
    rule.prerequisites = unique(rule.prerequisites)
    if not self.goal and target:sub(1, 1) ~= "." then
        self.goal = target
    end
    return rule
end
function M:addRecipe(group, line)
    if #group.targets == 0 then
        return
    end
    if not group.recipe then
        group.recipe = {}
        for _, rule in ipairs(group.targets) do
            if group.explicit and rule.recipe then
                self:emit(
                    "Makefile:" ..
                        line.number ..
                            ": warning: overriding recipe for target '" .. rule.target .. "'"
                )
                self:emit(
                    "Makefile:" ..
                        rule.recipe[1].number ..
                            ": warning: ignoring old recipe for target '" .. rule.target .. "'"
                )
            end
            rule.recipe = group.recipe
        end
    end
    group.recipe[#group.recipe + 1] = line
end
function M:load(body)
    self:clear()
    local current, stack, index = nil, {}, 1
    local function active()
        return #stack == 0 or stack[#stack].outer and stack[#stack].value
    end
    local ok, caught =
        pcall(
        function()
            while index <= #body do
                local number, text = index, body[index]
                self.location = "Makefile:" .. number
                index = index + 1
                if text:sub(1, 1) == ">" then
                    if active() then
                        if not current then
                            self:fail("recipe commences before first target")
                        end
                        self:addRecipe(
                            current,
                            {number = number, text = text:sub(2):gsub("^ +", "")}
                        )
                    end
                    goto continue
                end
                while text:sub(-1) == "\\" and index <= #body do
                    text = text:sub(1, -2):gsub(" +$", "") .. " " .. body[index]:gsub("^ +", "")
                    index = index + 1
                end
                text = trim((text:gsub("#.*$", "")))
                local first, rest = text:match("^([^ ]*) ?(.*)$")
                rest = trim(rest)
                if first == "else" then
                    if #stack == 0 then
                        self:fail("extraneous 'else'")
                    end
                    local top = stack[#stack]
                    if top.otherwise then
                        self:fail("only one 'else' per conditional")
                    end
                    top.value, top.otherwise = not top.value, true
                    goto continue
                elseif first == "endif" then
                    if #stack == 0 then
                        self:fail("extraneous 'endif'")
                    end
                    stack[#stack] = nil
                    goto continue
                elseif first == "ifdef" or first == "ifndef" or first == "ifeq" or first == "ifneq" then
                    local outer, value = active(), false
                    if outer then
                        if first == "ifdef" or first == "ifndef" then
                            local v = self.variables[trim(self:expand(rest))]
                            value = v ~= nil and v.value ~= ""
                            if first == "ifndef" then
                                value = not value
                            end
                        else
                            if #rest < 2 or rest:sub(1, 1) ~= "(" or rest:sub(-1) ~= ")" then
                                self:fail("invalid syntax in conditional")
                            end
                            local inside, depth, comma = rest:sub(2, -2), 0, nil
                            for i = 1, #inside do
                                local c = inside:sub(i, i)
                                if c == "(" then
                                    depth = depth + 1
                                elseif c == ")" then
                                    depth = depth - 1
                                elseif c == "," and depth == 0 then
                                    comma = i
                                    break
                                end
                            end
                            if not comma then
                                self:fail("invalid syntax in conditional")
                            end
                            local left = trim(self:expand(inside:sub(1, comma - 1)))
                            local right = trim(self:expand(inside:sub(comma + 1)))
                            value = left == right
                            if first == "ifneq" then
                                value = not value
                            end
                        end
                    end
                    stack[#stack + 1] = {
                        outer = outer,
                        value = value,
                        otherwise = false,
                        number = number
                    }
                    goto continue
                end
                if text == "" or not active() then
                    goto continue
                end
                do
                    local eq, colon = self:outside(text, "="), self:outside(text, ":")
                    if eq and (not colon or colon >= eq - 1) then
                        local start, op = eq, "="
                        local c = text:sub(eq - 1, eq - 1)
                        if eq > 1 and (c == ":" or c == "+" or c == "?") then
                            start, op = eq - 1, c
                        end
                        local name, value = trim(text:sub(1, start - 1)), trim(text:sub(eq + 1))
                        if name == "" then
                            self:fail("empty variable name")
                        end
                        local old = self.variables[name]
                        if op == "=" then
                            self.variables[name] = {value = value}
                        elseif op == ":" then
                            self.variables[name] = {simple = true, value = self:expand(value)}
                        elseif op == "?" then
                            if not old then
                                self.variables[name] = {value = value}
                            end
                        elseif old then
                            if old.simple then
                                value = self:expand(value)
                            end
                            old.value = old.value ~= "" and old.value .. " " .. value or value
                        else
                            self.variables[name] = {value = value}
                        end
                        current = nil
                    elseif colon then
                        local targets = unique(words(self:expand(text:sub(1, colon - 1))))
                        local remainder = text:sub(colon + 1)
                        local inline, static, pattern
                        local semi = self:outside(remainder, ";")
                        if semi then
                            inline, remainder =
                                remainder:sub(semi + 1):gsub("^ +", ""),
                                remainder:sub(1, semi - 1)
                        end
                        local at = self:outside(remainder, ":")
                        if at then
                            static, pattern, remainder =
                                true,
                                trim(self:expand(remainder:sub(1, at - 1))),
                                remainder:sub(at + 1)
                        end
                        local prerequisites = words(self:expand(remainder))
                        current = {targets = {}, explicit = true}
                        if #targets == 1 and targets[1] == ".PHONY" then
                            for _, p in ipairs(prerequisites) do
                                self.phony[p] = true
                            end
                        elseif static then
                            if not pattern:find("%", 1, true) then
                                self:fail("target pattern contains no '%'")
                            end
                            for _, target in ipairs(targets) do
                                local stem = match(pattern, target)
                                if not stem or stem == "" then
                                    self:emit(
                                        "Makefile:" ..
                                            number ..
                                                ": target '" ..
                                                    target .. "' doesn't match the target pattern"
                                    )
                                else
                                    local list = {}
                                    for i, p in ipairs(prerequisites) do
                                        list[i] = substitute(p, stem)
                                    end
                                    local rule = self:register(target, list)
                                    rule.stem = stem
                                    current.targets[#current.targets + 1] = rule
                                end
                            end
                        else
                            local count = 0
                            for _, target in ipairs(targets) do
                                if target:find("%", 1, true) then
                                    count = count + 1
                                end
                            end
                            if count > 0 and count ~= #targets then
                                self:fail("mixed implicit and normal rules")
                            end
                            current.explicit = count == 0
                            for _, target in ipairs(targets) do
                                local rule
                                if count > 0 then
                                    rule = {
                                        target = target,
                                        prerequisites = copy(prerequisites),
                                        stem = ""
                                    }
                                    self.patterns[#self.patterns + 1] = rule
                                else
                                    rule = self:register(target, prerequisites)
                                end
                                current.targets[#current.targets + 1] = rule
                            end
                        end
                        if inline ~= nil then
                            self:addRecipe(current, {number = number, text = inline})
                        end
                    elseif trim(self:expand(text)) ~= "" then
                        self:fail("missing separator")
                    end
                end
                ::continue::
            end
            if #stack > 0 then
                self.location = "Makefile:" .. stack[#stack].number
                self:fail("missing 'endif'")
            end
        end
    )
    if not ok then
        self:emit(caught.location .. ": *** " .. caught.reason .. ".  Stop.")
        self:clear()
        return
    end
    self.loaded = true
    local count = 0
    for _, rule in ipairs(self.patterns) do
        if rule.recipe then
            count = count + 1
        end
    end
    self:emit(
        "Makefile loaded: lines=" ..
            #body ..
                " variables=" ..
                    #keys(self.variables) ..
                        " targets=" ..
                            #keys(self.rules) ..
                                " patterns=" .. count .. " goal=" .. (self.goal or "(none)")
    )
end
function M:determine(target)
    local explicit = self.rules[target]
    if explicit and explicit.recipe then
        return {
            prerequisites = copy(explicit.prerequisites),
            recipe = explicit.recipe,
            stem = explicit.stem
        }
    end
    if not self.phony[target] then
        local candidates = {}
        for index, rule in ipairs(self.patterns) do
            local stem = match(rule.target, target)
            if rule.recipe and stem and stem ~= "" then
                candidates[#candidates + 1] = {rule = rule, stem = stem, index = index}
            end
        end
        table.sort(
            candidates,
            function(a, b)
                return #a.stem < #b.stem or #a.stem == #b.stem and a.index < b.index
            end
        )
        for _, candidate in ipairs(candidates) do
            local list, usable = {}, true
            for _, p in ipairs(candidate.rule.prerequisites) do
                p = substitute(p, candidate.stem)
                list[#list + 1] = p
                if self.files[p] == nil and not self.rules[p] then
                    usable = false
                end
            end
            if usable then
                if explicit then
                    for _, p in ipairs(explicit.prerequisites) do
                        list[#list + 1] = p
                    end
                end
                return {
                    prerequisites = unique(list),
                    recipe = candidate.rule.recipe,
                    stem = candidate.stem
                }
            end
        end
    end
    if explicit then
        return {prerequisites = copy(explicit.prerequisites), stem = explicit.stem}
    end
    if self.phony[target] then
        return {prerequisites = {}, stem = ""}
    end
    return self.files[target] ~= nil and {source = true} or {missing = true}
end
function M:touch(name)
    self.clock = self.clock + 1
    self.files[name] = self.clock
end
function M:execute(text)
    local list = words(text)
    if list[1] == "echo" then
        self:emit(table.concat(list, " ", 2))
    elseif list[1] == "touch" then
        for i = 2, #list do
            self:touch(list[i])
        end
    elseif list[1] == "rm" then
        local forced, start, code = list[2] == "-f", list[2] == "-f" and 3 or 2, 0
        for i = start, #list do
            local names = self:glob(list[i])
            if #names == 0 then
                names = {list[i]}
            end
            for _, name in ipairs(names) do
                if self.files[name] ~= nil then
                    self.files[name] = nil
                elseif not forced then
                    self:emit("rm: cannot remove '" .. name .. "': No such file or directory")
                    code = 1
                end
            end
        end
        return code
    elseif list[1] == "false" then
        return 1
    elseif list[1] == "exit" then
        return tonumber(list[2]) or 0
    end
    return 0
end
function M:make(args)
    local options, goals = {}, {}
    for _, arg in ipairs(args) do
        if arg:sub(1, 1) == "-" then
            for i = 2, #arg do
                local c = arg:sub(i, i)
                if not ("nBkis"):find(c, 1, true) then
                    self:emit("make: invalid option -- '" .. c .. "'")
                    return
                end
                options[c] = true
            end
        else
            goals[#goals + 1] = arg
        end
    end
    if #goals == 0 then
        if not self.loaded then
            self:emit("make: *** No targets specified and no makefile found.  Stop.")
            return
        end
        if not self.goal then
            self:emit("make: *** No targets.  Stop.")
            return
        end
        goals = {self.goal}
    end
    local saved, clock
    if options.n then
        saved, clock = {}, self.clock
        for name, time in pairs(self.files) do
            saved[name] = time
        end
    end
    local results, selected, building, runs = {}, {}, {}, 0
    local function abort()
        error({abort = true}, 0)
    end
    local build
    build = function(target, parent)
        if results[target] ~= nil then
            return results[target]
        end
        local rule = self:determine(target)
        selected[target] = rule
        if rule.missing then
            local message = "make: *** No rule to make target '" .. target .. "'"
            if parent then
                message = message .. ", needed by '" .. parent .. "'"
            end
            self:emit(message .. "." .. (options.k and "" or "  Stop."))
            results[target] = 1
            if not options.k then
                abort()
            end
            return 1
        end
        if rule.source then
            results[target] = 0
            return 0
        end
        building[target] = true
        local prerequisites, failed = {}, false
        for _, p in ipairs(rule.prerequisites) do
            if building[p] then
                self:emit("make: Circular " .. target .. " <- " .. p .. " dependency dropped.")
            else
                prerequisites[#prerequisites + 1] = p
                if build(p, target) ~= 0 then
                    failed = true
                end
            end
        end
        building[target] = nil
        if failed then
            results[target] = 2
            return 2
        end
        local time, newer = not self.phony[target] and self.files[target] or nil, {}
        for _, p in ipairs(prerequisites) do
            if
                options.B or time == nil or self.phony[p] or self.files[p] == nil or
                    self.files[p] > time
             then
                newer[#newer + 1] = p
            end
        end
        if not rule.recipe or not options.B and time ~= nil and #newer == 0 then
            results[target] = 0
            return 0
        end
        runs = runs + 1
        self.automatic = {
            ["@"] = target,
            ["<"] = prerequisites[1] or "",
            ["^"] = table.concat(prerequisites, " "),
            ["?"] = table.concat(newer, " "),
            ["*"] = rule.stem
        }
        local expanded = {}
        for i, line in ipairs(rule.recipe) do
            self.location = "Makefile:" .. line.number
            expanded[i] = self:expand(line.text)
        end
        self.automatic = {}
        for i, text in ipairs(expanded) do
            local prefix, command = text:match("^([ @%-]*)(.*)$")
            command = command:gsub(" +$", "")
            if command ~= "" then
                if options.n or not prefix:find("@", 1, true) and not options.s then
                    self:emit(command)
                end
                if not options.n then
                    local code = self:execute(command)
                    if code ~= 0 then
                        local number = rule.recipe[i].number
                        if prefix:find("-", 1, true) or options.i then
                            self:emit(
                                "make: [Makefile:" ..
                                    number .. ": " .. target .. "] Error " .. code .. " (ignored)"
                            )
                        else
                            self:emit(
                                "make: *** [Makefile:" ..
                                    number .. ": " .. target .. "] Error " .. code
                            )
                            results[target] = 1
                            if not options.k then
                                abort()
                            end
                            return 1
                        end
                    end
                end
            end
        end
        if not self.phony[target] then
            self:touch(target)
        end
        results[target] = 0
        return 0
    end
    local ok, caught =
        pcall(
        function()
            for _, goal in ipairs(goals) do
                local before = runs
                local result = build(goal, nil)
                if result == 0 and runs == before then
                    if self.phony[goal] or not selected[goal].recipe then
                        self:emit("make: Nothing to be done for '" .. goal .. "'.")
                    else
                        self:emit("make: '" .. goal .. "' is up to date.")
                    end
                elseif result == 2 then
                    self:emit("make: Target '" .. goal .. "' not remade because of errors.")
                end
            end
        end
    )
    if saved then
        self.files, self.clock = saved, clock
    end
    if not ok and not caught.abort then
        error(caught, 0)
    end
end
function M:command(line, body)
    self:resetExpansion()
    self:emit("$ " .. line)
    local command, text = line:match("^([^ ]+) ?(.*)$")
    local ok, caught =
        pcall(
        function()
            if command == "MAKEFILE" then
                self:load(body)
            elseif command == "MAKE" then
                self:make(words(text))
            elseif command == "TOUCH" then
                for _, name in ipairs(words(text)) do
                    self:touch(name)
                end
            elseif command == "RM" then
                for _, name in ipairs(words(text)) do
                    if self.files[name] ~= nil then
                        self.files[name] = nil
                    else
                        self:emit("rm: cannot remove '" .. name .. "': No such file or directory")
                    end
                end
            elseif command == "FILES" then
                self:emit("clock " .. self.clock)
                for _, name in ipairs(keys(self.files)) do
                    self:emit(name .. " " .. self.files[name])
                end
            elseif command == "VARS" then
                for _, name in ipairs(keys(self.variables)) do
                    local value = trim(self:reference(name))
                    self:emit(
                        name ..
                            (self.variables[name].simple and " :=" or " =") ..
                                (value ~= "" and " " .. value or "")
                    )
                end
            elseif command == "RULES" then
                local function display(rule)
                    self:emit(
                        rule.target ..
                            ":" ..
                                (#rule.prerequisites > 0 and
                                    " " .. table.concat(rule.prerequisites, " ") or
                                    "")
                    )
                    for _, recipe in ipairs(rule.recipe or {}) do
                        self:emit(">" .. recipe.text)
                    end
                end
                for _, name in ipairs(keys(self.rules)) do
                    display(self.rules[name])
                end
                for _, rule in ipairs(self.patterns) do
                    if rule.recipe then
                        display(rule)
                    end
                end
                if next(self.phony) then
                    self:emit(".PHONY: " .. table.concat(keys(self.phony), " "))
                end
            elseif command == "EXPAND" then
                self:emit("[" .. self:expand(text) .. "]")
            end
        end
    )
    if not ok then
        self:emit(caught.location .. ": *** " .. caught.reason .. ".  Stop.")
    end
end
M:clear()
io.read("*l")
while true do
    local line = io.read("*l")
    if line == "END FILES" then
        break
    end
    local name, time = line:match("^([^ ]+) ([0-9]+)$")
    time = tonumber(time)
    M.files[name] = time
    M.clock = math.max(M.clock, time)
end
while true do
    local line = io.read("*l")
    if line == "QUIT" then
        break
    end
    local body = {}
    if line == "MAKEFILE" then
        while true do
            local text = io.read("*l")
            if text == "END MAKEFILE" then
                break
            end
            body[#body + 1] = text
        end
    end
    M:command(line, body)
end
if #M.output > 0 then
    io.write(table.concat(M.output, "\n"), "\n")
end
