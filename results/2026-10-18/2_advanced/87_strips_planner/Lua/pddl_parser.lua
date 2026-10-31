local Parser = {}

function Parser.read(path)
    local file = assert(io.open(path, "rb"))
    local text = file:read("a")
    file:close()
    return text
end

function Parser.words(text)
    local result = {}
    for word in text:gmatch("%S+") do result[#result + 1] = word end
    return result
end

local function slice(items, first)
    local result = {}
    for i = first, #items do result[#result + 1] = items[i] end
    return result
end

function Parser.expressions(text)
    local cleaned = {}
    for line in (text .. "\n"):gmatch("([^\n]*)\n") do cleaned[#cleaned + 1] = line:match("^[^;]*") end
    text = table.concat(cleaned, "\n"):gsub("([()])", " %1 ")
    local roots = {}
    local stack = {roots}
    for token in text:gmatch("%S+") do
        if token == "(" then
            local child, parent = {}, stack[#stack]
            parent[#parent + 1], stack[#stack + 1] = child, child
        elseif token == ")" then stack[#stack] = nil
        else local current = stack[#stack]; current[#current + 1] = token end
    end
    return roots
end

function Parser.typed_list(words)
    local result, pending, i = {}, {}, 1
    while i <= #words do
        if words[i] == "-" then
            for _, name in ipairs(pending) do result[#result + 1] = {name = name, type = words[i + 1]} end
            pending, i = {}, i + 2
        else pending[#pending + 1], i = words[i], i + 1 end
    end
    for _, name in ipairs(pending) do result[#result + 1] = {name = name, type = "object"} end
    return result
end

function Parser.atom(expression)
    return {predicate = expression[1], terms = slice(expression, 2), key = "(" .. table.concat(expression, " ") .. ")"}
end

function Parser.elements(expression, empty)
    local conjunction = expression[1] == "and"
    for i = 2, #expression do if type(expression[i]) ~= "table" then conjunction = false end end
    return conjunction and (empty ~= false or #expression > 1) and slice(expression, 2) or {expression}
end

local function literal(expression)
    if expression[1] == "not" and #expression == 2 and type(expression[2]) == "table" then
        return {sign = false, atom = Parser.atom(expression[2])}
    end
    return {sign = true, atom = Parser.atom(expression)}
end

function Parser.domain(text)
    local expression = Parser.expressions(text)[1]
    local domain = {name = expression[2][2], parents = {object = false}, type_order = {"object"},
        predicates = {}, predicate_order = {}, actions = {}}
    for index = 3, #expression do
        local section = expression[index]
        if section[1] == ":types" then
            for i = 2, #section do
                local name = section[i]
                if name ~= "-" and domain.parents[name] == nil then
                    domain.parents[name] = "object"
                    domain.type_order[#domain.type_order + 1] = name
                end
            end
            for _, item in ipairs(Parser.typed_list(slice(section, 2))) do domain.parents[item.name] = item.type end
        elseif section[1] == ":predicates" then
            for i = 2, #section do
                local declaration, types = section[i], {}
                for _, item in ipairs(Parser.typed_list(slice(declaration, 2))) do types[#types + 1] = item.type end
                domain.predicates[declaration[1]] = types
                domain.predicate_order[#domain.predicate_order + 1] = declaration[1]
            end
        elseif section[1] == ":action" then
            local fields = {}
            for i = 3, #section, 2 do fields[section[i]] = section[i + 1] end
            local action = {name = section[2], parameters = Parser.typed_list(fields[":parameters"]), condition = {}, effects = {}, cost = 1}
            if fields[":precondition"] then
                for _, item in ipairs(Parser.elements(fields[":precondition"])) do action.condition[#action.condition + 1] = literal(item) end
            end
            for _, item in ipairs(Parser.elements(fields[":effect"], false)) do
                if item[1] == "increase" and #item == 3 and type(item[2]) == "table" and #item[2] == 1 and item[2][1] == "total-cost" then action.cost = tonumber(item[3])
                else action.effects[#action.effects + 1] = literal(item) end
            end
            domain.actions[#domain.actions + 1] = action
        end
    end
    return domain
end

function Parser.problems(text)
    local problems = {}
    for _, expression in ipairs(Parser.expressions(text)) do
        local sections = {}
        for i = 3, #expression do sections[expression[i][1]] = slice(expression[i], 2) end
        local problem = {name = expression[2][2], objects = {}, object_order = {}, initial = {}, goals = {}}
        for _, item in ipairs(Parser.typed_list(sections[":objects"])) do
            problem.objects[item.name] = item.type
            problem.object_order[#problem.object_order + 1] = item.name
        end
        for _, item in ipairs(sections[":init"]) do problem.initial[#problem.initial + 1] = Parser.atom(item) end
        for _, item in ipairs(Parser.elements(sections[":goal"][1], false)) do problem.goals[#problem.goals + 1] = Parser.atom(item) end
        problems[#problems + 1] = problem
    end
    return problems
end

return Parser
