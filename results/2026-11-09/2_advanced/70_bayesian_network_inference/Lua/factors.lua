local learning = require('learning')
local M = {}
local Factor = {}
Factor.__index = Factor
function M.entry_count(variables, sizes)
    local result = 1
    for _, v in ipairs(variables) do result = result * sizes[v] end
    return result
end
function M.assignments(variables, sizes)
    local cursor, count = 0, M.entry_count(variables, sizes)
    return function()
        if cursor >= count then return nil end
        local index, assignment = cursor, {}
        cursor = cursor + 1
        for i = #variables, 1, -1 do local v = variables[i]; assignment[v] = index % sizes[v] + 1; index = index // sizes[v] end
        return assignment
    end
end
function M.new(variables, values, sizes) return setmetatable({variables = variables, values = values, sizes = sizes}, Factor) end
function Factor:value(assignment) return self.values[learning.parent_row(self.variables, assignment, self.sizes)] end
function Factor:reduced(evidence)
    local variables, values = {}, {}
    for _, v in ipairs(self.variables) do if evidence[v] == nil then variables[#variables + 1] = v end end
    for assignment in M.assignments(variables, self.sizes) do
        for v, state in pairs(evidence) do assignment[v] = state end
        values[#values + 1] = self:value(assignment)
    end
    return M.new(variables, values, self.sizes)
end
function Factor:multiplied(other)
    local present, variables, values = {}, {}, {}
    for _, v in ipairs(self.variables) do present[v] = true end
    for _, v in ipairs(other.variables) do present[v] = true end
    for v in pairs(present) do variables[#variables + 1] = v end
    table.sort(variables)
    for assignment in M.assignments(variables, self.sizes) do values[#values + 1] = self:value(assignment) * other:value(assignment) end
    return M.new(variables, values, self.sizes)
end
function Factor:eliminate(variable, maximize)
    local variables, values = {}, {}
    for _, v in ipairs(self.variables) do if v ~= variable then variables[#variables + 1] = v end end
    for assignment in M.assignments(variables, self.sizes) do
        local result = maximize and -math.huge or 0.0
        for state = 1, self.sizes[variable] do
            assignment[variable] = state
            local value = self:value(assignment)
            if maximize then result = math.max(result, value) else result = result + value end
        end
        values[#values + 1] = result
    end
    return M.new(variables, values, self.sizes)
end
function M.cpt_factor(variable, parents, cpt, sizes)
    local variables, values = {variable}, {}
    for _, parent in ipairs(parents) do variables[#variables + 1] = parent end
    table.sort(variables)
    for assignment in M.assignments(variables, sizes) do values[#values + 1] = cpt[learning.parent_row(parents, assignment, sizes)][assignment[variable]] end
    return M.new(variables, values, sizes)
end
function M.multiply(factors, sizes)
    if #factors == 0 then return M.new({}, {1.0}, sizes) end
    local result = factors[1]
    for i = 2, #factors do result = result:multiplied(factors[i]) end
    return result
end
return M
