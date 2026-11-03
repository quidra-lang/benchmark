local RBAC = require('rbac')
local policies = require('policy_parser')
local combine = require('combining').combine
local analysis = require('analysis')
local NA, IP, ID = 'NOT_APPLICABLE', 'INDETERMINATE{P}', 'INDETERMINATE{D}'
local function definite(decision) return decision == 'PERMIT' or decision == 'DENY' end
local function indeterminate(decision) return decision:sub(1, 13) == 'INDETERMINATE' end
local function add(values, key, amount) values[key] = (values[key] or 0) + (amount or 1) end
local function keys(values)
    local result = {}; for key in pairs(values) do result[#result + 1] = key end
    table.sort(result); return result
end
local function append(target, source) for _, value in ipairs(source) do target[#target + 1] = value end end
local function joined_blocks(blocks)
    local lines = {}
    for _, block in ipairs(blocks) do if #lines > 0 then lines[#lines + 1] = '' end; append(lines, block) end
    return lines
end
local function error_value(reason) return {reason = reason} end
local function is_error(value) return type(value) == 'table' and value.reason ~= nil end
local function first_error(values)
    for _, value in ipairs(values) do if is_error(value) then return value end end
end
local function input_value(text)
    if text == 'true' or text == 'false' then return text == 'true' end
    if text:sub(1, 1) == '[' then
        local bag = {}; for value in text:sub(2, -2):gmatch('[^,]+') do bag[#bag + 1] = value end
        return bag
    end
    if text:match('^%-?%d+$') then return tonumber(text) end
    return text
end
local function attributes(fields, first)
    local values = {}
    for index = first, #fields do
        local name, text = fields[index]:match('^([^=]+)=(.*)$'); values[name] = input_value(text)
    end
    return values
end
local function value_notation(value)
    local kind = type(value)
    if kind == 'boolean' or kind == 'number' then return tostring(value) end
    if kind == 'string' then return '"' .. value .. '"' end
    local items = {}; for _, item in ipairs(value) do items[#items + 1] = value_notation(item) end
    return '[' .. table.concat(items, ',') .. ']'
end
local function boolean_result(values, veto, name)
    local checked = {}
    for _, value in ipairs(values) do
        if type(value) == 'boolean' or is_error(value) then checked[#checked + 1] = value
        else checked[#checked + 1] = error_value('type ' .. name) end
    end
    for _, value in ipairs(checked) do if value == veto then return veto end end
    local failure = first_error(checked)
    if failure then return failure end
    return not veto
end
local function operation(name, values)
    local failure = first_error(values)
    if failure then return failure end
    local left, right = values[1], values[2]
    local a, b = type(left), type(right)
    if name == '+' or name == '-' or name == '*' or name == '<' or name == '<=' or name == '>' or name == '>=' then
        if a == 'number' and (#values == 1 or b == 'number') then
            if #values == 1 then return -left end
            if name == '+' then return left + right elseif name == '-' then return left - right elseif name == '*' then return left * right
            elseif name == '<' then return left < right elseif name == '<=' then return left <= right elseif name == '>' then return left > right else return left >= right end
        end
    elseif name == '==' or name == '!=' then
        if a == b and (a == 'number' or a == 'string' or a == 'boolean') then
            if name == '==' then return left == right else return left ~= right end
        end
    elseif name == 'in' then
        if a == 'string' and b == 'table' then for _, item in ipairs(right) do if left == item then return true end end; return false end
    elseif name == 'not' then if a == 'boolean' then return not left end
    elseif name == 'starts_with' or name == '^=' then if a == 'string' and b == 'string' then return left:sub(1, #right) == right end
    elseif name == 'size' then if a == 'table' then return #left end end
    return error_value('type ' .. name)
end
local expression
expression = function(tree, values, current)
    local name, arguments = tree.operation, tree.arguments
    if name == 'literal' then return tree.value end
    if name == 'attribute' then
        if values[tree.reference] ~= nil then return values[tree.reference] end
        return error_value('missing ' .. tree.reference)
    end
    if name == 'it' then return current end
    if name == 'present' then return values[arguments[1].reference] ~= nil end
    if name == 'any_of' or name == 'all_of' then
        local bag = expression(arguments[1], values, current)
        if is_error(bag) then return bag end
        if type(bag) ~= 'table' then return error_value('type ' .. name) end
        local predicates = {}
        for _, item in ipairs(bag) do predicates[#predicates + 1] = expression(arguments[2], values, item) end
        return boolean_result(predicates, name == 'any_of', name)
    end
    local operands = {}
    for _, argument in ipairs(arguments) do operands[#operands + 1] = expression(argument, values, current) end
    if name == 'and' or name == 'or' then return boolean_result(operands, name == 'or', name) end
    return operation(name, operands)
end
local function target_group(results, conjunction)
    if conjunction then
        local all_match = true
        for _, result in ipairs(results) do
            if result.kind == 'NO_MATCH' then return {kind = 'NO_MATCH'} end
            if result.kind ~= 'MATCH' then all_match = false end
        end
        if all_match then return {kind = 'MATCH'} end
    else
        for _, result in ipairs(results) do if result.kind == 'MATCH' then return {kind = 'MATCH'} end end
    end
    for _, result in ipairs(results) do if result.kind == 'INDETERMINATE' then return result end end
    return {kind = 'NO_MATCH'}
end
local function match_clause(clause, values)
    local source = values[clause.reference]
    if source == nil then
        if clause.mandatory then return {kind = 'INDETERMINATE', reason = 'missing ' .. clause.reference} end
        return {kind = 'NO_MATCH'}
    end
    local items = type(source) == 'table' and source or {source}
    local literal, results = expression(clause.literal, values), {}
    for _, item in ipairs(items) do results[#results + 1] = operation(clause.operation, {item, literal}) end
    for _, result in ipairs(results) do if result == true then return {kind = 'MATCH'} end end
    local failure = first_error(results)
    if failure then return {kind = 'INDETERMINATE', reason = failure.reason} end
    return {kind = 'NO_MATCH'}
end
local function notation(result)
    return result.decision .. (indeterminate(result.decision) and ' (' .. result.reason .. ')' or '')
end
local function final_notation(result) return notation(result) .. (definite(result.decision) and ' by ' .. result.decisive.identifier or '') end
local Evaluator = {}
Evaluator.__index = Evaluator
function Evaluator.new(values, record) return setmetatable({values = values, record = record, coverage = {}}, Evaluator) end
function Evaluator:target(element)
    local lines = {}
    for _, line in ipairs(element.targets) do
        local alternatives = {}
        for _, alternative in ipairs(line) do
            local clauses = {}; for _, clause in ipairs(alternative) do clauses[#clauses + 1] = match_clause(clause, self.values) end
            alternatives[#alternatives + 1] = target_group(clauses, true)
        end
        lines[#lines + 1] = target_group(alternatives, false)
    end
    return target_group(lines, true)
end
function Evaluator:attachments(result, supporters)
    for _, supporter in ipairs(supporters) do append(result.obligations, supporter.obligations); append(result.advice, supporter.advice) end
    local effect = result.decision
    for _, kind in ipairs({'obligations', 'advice'}) do
        for _, definition in ipairs(result.element[kind]) do
            if definition.effect == effect then
                local evaluated = {}
                for _, argument in ipairs(definition.arguments) do evaluated[#evaluated + 1] = expression(argument.expression, self.values) end
                local failure = first_error(evaluated)
                if failure then
                    if kind == 'obligations' then
                        result.decision, result.reason, result.decisive = effect == 'DENY' and ID or IP, 'obligation ' .. definition.identifier .. ': ' .. failure.reason, nil
                        result.obligations, result.advice = {}, {}; return
                    end
                else
                    local item = definition.identifier
                    for index, argument in ipairs(definition.arguments) do item = item .. ' ' .. argument.name .. '=' .. value_notation(evaluated[index]) end
                    result[kind][#result[kind] + 1] = {identifier = definition.identifier, text = item}
                end
            end
        end
    end
end
local function evaluation(element, target)
    return {element = element, target = target, decision = NA, children = {}, obligations = {}, advice = {}}
end
function Evaluator:rule(element, obligations)
    local result = evaluation(element, self:target(element))
    local uncertain = element.behavior == 'DENY' and ID or IP
    if result.target.kind == 'INDETERMINATE' then result.decision, result.reason = uncertain, result.target.reason
    elseif result.target.kind == 'MATCH' then
        local condition = true
        if element.condition then condition = expression(element.condition, self.values) end
        if type(condition) ~= 'boolean' and not is_error(condition) then condition = error_value('type condition') end
        result.condition = condition
        if is_error(condition) then result.decision, result.reason = uncertain, condition.reason
        elseif condition then
            result.decision, result.decisive = element.behavior, element
            if obligations ~= false then self:attachments(result, {}) end
        end
    end
    if self.record then self.coverage[element.identifier] = result.decision == 'PERMIT' and 'P' or result.decision == 'DENY' and 'D' or result.decision == NA and '-' or 'I' end
    return result
end
function Evaluator:evaluate(element)
    if element.kind == 'rule' then return self:rule(element) end
    local result = evaluation(element, self:target(element))
    if result.target.kind == 'NO_MATCH' then return result end
    result.decision, result.reason, result.children = combine(element.behavior, element.children,
        function(child) return self:evaluate(child) end, function(child) return self:target(child) end)
    if result.target.kind == 'INDETERMINATE' then
        if definite(result.decision) then result.decision = result.decision == 'DENY' and ID or IP end
        if indeterminate(result.decision) then result.reason = result.target.reason end
    end
    if definite(result.decision) then
        local supporters = {}
        for _, state in ipairs(result.children) do
            if state.kind == 'evaluated' and state.value.decision == result.decision then supporters[#supporters + 1] = state.value end
        end
        result.decisive = #supporters > 0 and supporters[1].decisive or element
        self:attachments(result, supporters)
    end
    return result
end
local tree_lines
tree_lines = function(result, depth)
    depth = depth or 0
    local element, target, prefix = result.element, result.target.kind, string.rep(' ', 2 + 2 * depth)
    local line = prefix .. element.kind .. ' ' .. element.identifier .. ' ' .. element.behavior .. ' target ' .. target
    if element.kind == 'rule' and target == 'MATCH' then line = line .. ' condition ' .. (is_error(result.condition) and 'INDETERMINATE' or result.condition and 'TRUE' or 'FALSE') end
    local lines = {line .. ' -> ' .. notation(result)}
    if element.kind ~= 'rule' and target ~= 'NO_MATCH' then
        for index, child in ipairs(element.children) do
            local state = result.children[index]
            if state.kind == 'evaluated' then append(lines, tree_lines(state.value, depth + 1))
            elseif state.kind == 'skipped' then lines[#lines + 1] = prefix .. '  ' .. child.kind .. ' ' .. child.identifier .. ' skipped'
            else
                local checked = state.value
                lines[#lines + 1] = prefix .. '  ' .. child.kind .. ' ' .. child.identifier .. ' ' .. child.behavior .. ' target ' .. checked.kind
                    .. (checked.kind == 'INDETERMINATE' and ' (' .. checked.reason .. ')' or '')
            end
        end
    end
    return lines
end

local Engine = {}
Engine.__index = Engine
function Engine.new()
    local root, elements = policies.read()
    local self = setmetatable({rbac = RBAC.new(), root = root, elements = elements, rules = {}, subjects = {}, resources = {},
        domains = {}, reference = {}, requests = {}, coverage = {}, grant_counts = {}, decisions = {}, decisive = {},
        obligations = {}, advice = {}, refused = 0}, Engine)
    for _, element in ipairs(elements) do
        if element.kind == 'rule' then self.rules[#self.rules + 1] = element; self.coverage[element.identifier] = '' end
    end
    for line in io.lines('input/attributes.txt') do
        local fields = {}; for field in line:gmatch('%S+') do fields[#fields + 1] = field end
        if fields[1] == 'SUBJECT' then self.subjects[fields[2]] = attributes(fields, 3)
        elseif fields[1] == 'RESOURCE' then self.resources[fields[2]] = {kind = fields[3], attributes = attributes(fields, 4)}
        elseif fields[1] == 'DOMAIN' then
            local values = {}; for index = 3, #fields do values[#values + 1] = input_value(fields[index]) end
            self.domains[#self.domains + 1] = {name = fields[2], values = values}
        else self.reference = attributes(fields, 2) end
    end
    for line in io.lines('input/requests.txt') do
        local fields = {}; for field in line:gmatch('%S+') do fields[#fields + 1] = field end
        local explain = fields[#fields] == 'EXPLAIN'
        if explain then table.remove(fields) end
        self.requests[#self.requests + 1] = {identifier = fields[1], user = fields[2], roles = fields[3], action = fields[4],
            resource = fields[5], environment = attributes(fields, 6), explain = explain}
    end
    return self
end
function Engine:check(request)
    if not self.subjects[request.user] then return 'unknown user ' .. request.user end
    if not self.resources[request.resource] then return 'unknown resource ' .. request.resource end
    local day = request.environment.day
    if type(day) ~= 'number' or day < 1 or day > 365 then return 'bad day' end
end
function Engine:activate(user, specification, day)
    local authorized, candidates = self.rbac:authorized(user, day), {}
    if specification == '*' then candidates = keys(authorized)
    elseif specification ~= '-' then for role in specification:gmatch('[^,]+') do candidates[#candidates + 1] = role end end
    local active, seen, activations = {}, {}, {}
    for _, candidate in ipairs(candidates) do
        local reason
        if not self.rbac.roles[candidate] then reason = 'unknown'
        elseif seen[candidate] then reason = 'duplicate'
        elseif not authorized[candidate] then reason = 'unauthorized'
        else
            local proposed = {}; for role in pairs(active) do proposed[role] = true end; proposed[candidate] = true
            local closure = self.rbac:closure(proposed)
            for _, constraint in ipairs(self.rbac.dsd) do
                local overlap = 0
                for role in pairs(constraint.roles) do if closure[role] then overlap = overlap + 1 end end
                if overlap >= constraint.cardinality then reason = 'dsd ' .. constraint.name; break end
            end
        end
        seen[candidate] = true
        if not reason then active[candidate] = true end
        activations[#activations + 1] = {role = candidate, reason = reason}
    end
    return activations, keys(self.rbac:closure(active))
end
function Engine:prepare(request)
    local activations, roles = self:activate(request.user, request.roles, request.environment.day)
    local resource, grant, values = self.resources[request.resource], nil, {}
    for _, role in ipairs(roles) do if self.rbac.permissions[role][request.action .. ' ' .. resource.kind] then grant = role; break end end
    for name, value in pairs(self.subjects[request.user]) do values['subject.' .. name] = value end
    values['subject.id'], values['subject.role'], values['subject.rbac'] = request.user, roles, grant ~= nil
    for name, value in pairs(resource.attributes) do values['resource.' .. name] = value end
    values['resource.id'], values['resource.type'], values['action.id'] = request.resource, resource.kind, request.action
    for name, value in pairs(request.environment) do values['environment.' .. name] = value end
    return activations, roles, grant, values
end
function Engine:process_requests()
    local lines, explanations = {}, {}
    for _, request in ipairs(self.requests) do
        local coverage, failure = {}, self:check(request)
        if failure then
            lines[#lines + 1] = request.identifier .. ' ERROR ' .. failure; add(self.decisions, 'ERROR')
            if request.explain then explanations[#explanations + 1] = {'request ' .. request.identifier, '  error ' .. failure} end
        else
            local activations, roles, grant, values = self:prepare(request)
            local evaluator = Evaluator.new(values, true)
            local result = evaluator:evaluate(self.root)
            coverage = evaluator.coverage
            lines[#lines + 1] = request.identifier .. ' ' .. final_notation(result)
            for _, activation in ipairs(activations) do
                if activation.reason then lines[#lines + 1] = '  refused ' .. activation.role .. ' ' .. activation.reason; self.refused = self.refused + 1 end
            end
            for _, item in ipairs(result.obligations) do lines[#lines + 1] = '  obligation ' .. item.text; add(self.obligations, item.identifier) end
            for _, item in ipairs(result.advice) do lines[#lines + 1] = '  advice ' .. item.text; add(self.advice, item.identifier) end
            if grant then add(self.grant_counts, grant .. ' ' .. request.action .. ' ' .. self.resources[request.resource].kind) end
            add(self.decisions, indeterminate(result.decision) and 'INDETERMINATE' or result.decision)
            if definite(result.decision) then add(self.decisive, result.decisive.identifier) end
            if request.explain then
                local trace = {'request ' .. request.identifier, '  user ' .. request.user .. ' resource ' .. request.resource
                    .. ' type ' .. self.resources[request.resource].kind .. ' action ' .. request.action .. ' day ' .. request.environment.day}
                for _, activation in ipairs(activations) do trace[#trace + 1] = '  activate ' .. activation.role .. (activation.reason and ' refused ' .. activation.reason or ' ok') end
                trace[#trace + 1] = '  roles ' .. (#roles > 0 and table.concat(roles, ',') or '-')
                trace[#trace + 1] = '  rbac ' .. (grant and 'yes ' .. grant or 'no')
                append(trace, tree_lines(result)); trace[#trace + 1] = '  decision ' .. final_notation(result)
                explanations[#explanations + 1] = trace
            end
        end
        for _, rule in ipairs(self.rules) do self.coverage[rule.identifier] = self.coverage[rule.identifier] .. (coverage[rule.identifier] or '.') end
    end
    return lines, joined_blocks(explanations)
end
function Engine:permission_report()
    local users, blocks = {}, {}
    for _, assignment in ipairs(self.rbac.assignments) do users[assignment.user] = true end
    for _, user in ipairs(keys(users)) do
        local assigned, authorized = {}, {}
        for _, a in ipairs(self.rbac.assignments) do
            if a.user == user then
                assigned[a.role] = assigned[a.role] or {}
                for day = a.first, a.last do assigned[a.role][day] = true end
            end
        end
        for role, days in pairs(assigned) do
            for inherited in pairs(self.rbac:closure({[role] = true})) do
                authorized[inherited] = authorized[inherited] or {}
                for day in pairs(days) do authorized[inherited][day] = true end
            end
        end
        local lines, via = {'user ' .. user}, {}
        for _, role in ipairs(keys(assigned)) do lines[#lines + 1] = '  assigned ' .. role .. ' ' .. analysis.day_notation(assigned[role]) end
        for _, role in ipairs(keys(authorized)) do
            lines[#lines + 1] = '  authorized ' .. role .. ' ' .. analysis.day_notation(authorized[role])
            for permission in pairs(self.rbac.permissions[role]) do via[permission] = via[permission] or {}; via[permission][#via[permission] + 1] = role end
        end
        for _, permission in ipairs(keys(via)) do
            local roles, days, effective = via[permission], {}, '-'
            for _, role in ipairs(roles) do for day in pairs(authorized[role]) do days[day] = true end end
            if self.subjects[user] then
                local action, kind = permission:match('^(%S+) (%S+)$')
                local permitted, total = 0, 0
                for resource, definition in pairs(self.resources) do
                    if definition.kind == kind then
                        total = total + 1
                        local request = {user = user, roles = '*', action = action, resource = resource, environment = self.reference}
                        local _, _, _, values = self:prepare(request)
                        if Evaluator.new(values):evaluate(self.root).decision == 'PERMIT' then permitted = permitted + 1 end
                    end
                end
                effective = permitted .. '/' .. total
            end
            lines[#lines + 1] = '  permission ' .. permission .. ' ' .. analysis.day_notation(days) .. ' via ' .. table.concat(roles, ',') .. ' effective ' .. effective
        end
        blocks[#blocks + 1] = lines
    end
    return joined_blocks(blocks)
end
function Engine:domain_analysis()
    local counts, examples, shadowed, blockers, ancestors, pairs_to_check, conflict_counts = {}, {}, {}, {}, {}, {}, {}
    for _, rule in ipairs(self.rules) do
        if rule.parent.behavior == 'first-applicable' then shadowed[rule.identifier] = true end
        local chain, parent = {}, rule.parent
        while parent do chain[#chain + 1] = parent.identifier; parent = parent.parent end
        ancestors[rule.identifier] = chain
    end
    for _, policy in ipairs(self.elements) do
        if policy.kind == 'policy' then
            for index, earlier in ipairs(policy.children) do
                for later_index = index + 1, #policy.children do
                    local later = policy.children[later_index]
                    if earlier.behavior ~= later.behavior then pairs_to_check[#pairs_to_check + 1] = {policy, earlier, later}; conflict_counts[#conflict_counts + 1] = 0 end
                end
            end
        end
    end
    local point_count = 0
    analysis.points(self.domains, function(values)
        point_count = point_count + 1
        local evaluator, targets, standalone, applying = Evaluator.new(values), {}, {}, {}
        for _, element in ipairs(self.elements) do if element.kind ~= 'rule' then targets[element.identifier] = evaluator:target(element).kind end end
        for _, rule in ipairs(self.rules) do standalone[rule.identifier] = evaluator:rule(rule, false).decision end
        for _, rule in ipairs(self.rules) do
            local identifier, applies = rule.identifier, definite(standalone[rule.identifier])
            for _, parent in ipairs(ancestors[identifier]) do if targets[parent] ~= 'MATCH' then applies = false end end
            if applies then
                applying[identifier] = true; add(counts, identifier)
                if not examples[identifier] then
                    local example = {}
                    for _, domain in ipairs(self.domains) do if #domain.values >= 2 then example[#example + 1] = domain.name .. '=' .. value_notation(values[domain.name]) end end
                    examples[identifier] = table.concat(example, ' ')
                end
                if shadowed[identifier] then
                    local earlier = analysis.blocker(rule, standalone)
                    if earlier then blockers[identifier] = blockers[identifier] or {}; blockers[identifier][earlier] = true
                    else shadowed[identifier] = nil end
                end
            end
        end
        for index, pair in ipairs(pairs_to_check) do if applying[pair[2].identifier] and applying[pair[3].identifier] then conflict_counts[index] = conflict_counts[index] + 1 end end
    end)
    local lines, dead = {'applicability ' .. point_count}, {}
    for _, rule in ipairs(self.rules) do
        local identifier = rule.identifier
        lines[#lines + 1] = '  ' .. identifier .. ' ' .. (counts[identifier] or 0) .. ' ' .. (examples[identifier] or '-')
        if not counts[identifier] then dead[#dead + 1] = identifier; shadowed[identifier] = nil end
    end
    lines[#lines + 1] = 'dead ' .. #dead
    for _, identifier in ipairs(dead) do lines[#lines + 1] = '  ' .. identifier end
    lines[#lines + 1] = 'shadowed ' .. #keys(shadowed)
    for _, rule in ipairs(self.rules) do
        if shadowed[rule.identifier] then
            local names = {}
            for _, earlier in ipairs(self.rules) do if blockers[rule.identifier][earlier.identifier] then names[#names + 1] = earlier.identifier end end
            lines[#lines + 1] = '  ' .. rule.identifier .. ' by ' .. table.concat(names, ',')
        end
    end
    local conflicts = 0
    for _, amount in ipairs(conflict_counts) do if amount > 0 then conflicts = conflicts + 1 end end
    lines[#lines + 1] = 'conflicts ' .. conflicts
    for index, pair in ipairs(pairs_to_check) do
        if conflict_counts[index] > 0 then lines[#lines + 1] = '  ' .. pair[1].identifier .. ' ' .. pair[2].identifier .. ' ' .. pair[3].identifier
            .. ' ' .. conflict_counts[index] .. ' ' .. analysis.conflict_winner(pair[1], pair[2], pair[3]) end
    end
    return lines
end
function Engine:analysis_report()
    local lines = {'rbac ' .. #self.rbac.diagnostics}
    for _, diagnostic in ipairs(self.rbac.diagnostics) do lines[#lines + 1] = '  line ' .. diagnostic.number .. ' ' .. diagnostic.keyword .. ' ' .. diagnostic.reason end
    local grants = keys(self.rbac.grants)
    lines[#lines + 1] = 'grants ' .. #grants
    for _, grant in ipairs(grants) do lines[#lines + 1] = '  ' .. grant .. ' ' .. (self.grant_counts[grant] or 0) end
    append(lines, self:domain_analysis()); lines[#lines + 1] = 'coverage ' .. #self.requests
    local uncovered = {}
    for _, rule in ipairs(self.rules) do
        local symbols = self.coverage[rule.identifier]
        local _, amount = symbols:gsub('[PD]', '')
        lines[#lines + 1] = '  ' .. rule.identifier .. ' ' .. symbols .. ' ' .. amount
        if amount == 0 then uncovered[#uncovered + 1] = rule.identifier end
    end
    lines[#lines + 1] = 'uncovered ' .. #uncovered
    for _, identifier in ipairs(uncovered) do lines[#lines + 1] = '  ' .. identifier end
    lines[#lines + 1] = 'summary'
    for _, name in ipairs({'PERMIT', 'DENY', NA, 'INDETERMINATE', 'ERROR'}) do lines[#lines + 1] = '  decision ' .. name .. ' ' .. (self.decisions[name] or 0) end
    lines[#lines + 1] = '  refused ' .. self.refused
    for _, element in ipairs(self.elements) do if self.decisive[element.identifier] then lines[#lines + 1] = '  decisive ' .. element.identifier .. ' ' .. self.decisive[element.identifier] end end
    for _, kind in ipairs({'obligations', 'advice'}) do
        for _, identifier in ipairs(keys(self[kind])) do lines[#lines + 1] = '  ' .. (kind == 'obligations' and 'obligation' or 'advice') .. ' ' .. identifier .. ' ' .. self[kind][identifier] end
    end
    return lines
end
function Engine:run()
    local decisions, traces = self:process_requests()
    local outputs = {['decisions.txt'] = decisions, ['traces.txt'] = traces,
        ['permissions.txt'] = self:permission_report(), ['analysis.txt'] = self:analysis_report()}
    os.execute('mkdir -p output')
    for name, lines in pairs(outputs) do
        local file = assert(io.open('output/' .. name, 'w'))
        file:write(table.concat(lines, '\n'), #lines > 0 and '\n' or ''); file:close()
    end
end
Engine.new():run()
