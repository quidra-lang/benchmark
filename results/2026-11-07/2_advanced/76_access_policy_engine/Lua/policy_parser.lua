local parse = require('expressions').parse
local policies = {}
local function split(text, separator)
    local result, start = {}, 1
    while true do
        local position = text:find(separator, start, true)
        if not position then result[#result + 1] = text:sub(start); return result end
        result[#result + 1] = text:sub(start, position - 1); start = position + #separator
    end
end
local function target(text)
    local alternatives = {}
    for _, alternative in ipairs(split(text, ' | ')) do
        local clauses = {}
        for _, clause in ipairs(split(alternative, ' & ')) do
            local reference, operation, literal = clause:match('^(%S+) (%S+) (.*)$')
            local mandatory = reference:sub(-1) == '!'
            clauses[#clauses + 1] = {reference = mandatory and reference:sub(1, -2) or reference,
                mandatory = mandatory, operation = operation, literal = parse(literal)}
        end
        alternatives[#alternatives + 1] = clauses
    end
    return alternatives
end
function policies.read()
    local elements, stack = {}, {}
    for raw in io.lines('input/policies.txt') do
        local line = raw:gsub('^ +', '')
        if line ~= '' and line:sub(1, 1) ~= '#' then
            local keyword, rest = line:match('^(%S+)%s?(.*)$')
            if keyword == 'POLICYSET' or keyword == 'POLICY' or keyword == 'RULE' then
                local identifier, behavior = rest:match('^(%S+) (%S+)$')
                local element = {kind = keyword:lower(), identifier = identifier, behavior = behavior, parent = stack[#stack],
                    targets = {}, children = {}, obligations = {}, advice = {}}
                if element.parent then element.parent.children[#element.parent.children + 1] = element end
                elements[#elements + 1], stack[#stack + 1] = element, element
            elseif keyword == 'END' then table.remove(stack)
            elseif keyword == 'TARGET' then local element = stack[#stack]; element.targets[#element.targets + 1] = target(rest)
            elseif keyword == 'CONDITION' then stack[#stack].condition = parse(rest)
            else
                local effect, identifier, arguments = rest:match('^(%S+) (%S+)%s?(.*)$')
                local definition = {effect = effect, identifier = identifier, arguments = {}}
                if arguments ~= '' then
                    for _, part in ipairs(split(arguments, ';')) do
                        part = part:match('^%s*(.-)%s*$')
                        local name, expression = part:match('^([^=]+)=(.*)$')
                        definition.arguments[#definition.arguments + 1] = {name = name, expression = parse(expression)}
                    end
                end
                local collection = keyword == 'OBLIGATION' and stack[#stack].obligations or stack[#stack].advice
                collection[#collection + 1] = definition
            end
        end
    end
    return elements[1], elements
end
return policies
