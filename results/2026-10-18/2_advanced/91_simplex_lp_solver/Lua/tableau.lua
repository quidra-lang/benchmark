local Q = require("rational")
local T = {}
T.__index = T
function T.new(form)
    local result = setmetatable({ values = {}, rhs = {}, basic = {}, row_names = form.row_names,
        column_names = form.column_names }, T)
    for i, row in ipairs(form.matrix) do
        result.values[i] = { table.unpack(row) }
        result.rhs[i], result.basic[i] = form.rhs[i], form.initial[i]
    end
    return result
end
function T:pivot(p, q)
    local divisor = self.values[p][q]
    for k, value in ipairs(self.values[p]) do self.values[p][k] = value / divisor end
    self.rhs[p] = self.rhs[p] / divisor
    for i, row in ipairs(self.values) do
        if i ~= p then
            local factor = row[q]
            for k, value in ipairs(row) do row[k] = value - factor * self.values[p][k] end
            self.rhs[i] = self.rhs[i] - factor * self.rhs[p]
        end
    end
    self.basic[p] = q
end
function T:reduced(costs)
    local result = {}
    for k, cost in ipairs(costs) do
        local value = cost
        for i, row in ipairs(self.values) do value = value - costs[self.basic[i]] * row[k] end
        result[k] = value
    end
    return result
end
function T:phase_value(costs)
    local result = Q.zero
    for i, basic in ipairs(self.basic) do result = result + costs[basic] * self.rhs[i] end
    return result
end
local function joined(values)
    local parts = {}
    for _, value in ipairs(values) do parts[#parts + 1] = tostring(value) end
    return table.concat(parts, " ")
end
function T:display(heading, costs, objective)
    local lines = { "TABLEAU " .. heading, "COLUMNS " .. table.concat(self.column_names, " ") }
    for i, row in ipairs(self.values) do
        lines[#lines + 1] = "ROW " .. self.row_names[i] .. " " .. self.column_names[self.basic[i]] .. " "
            .. joined(row) .. " | " .. self.rhs[i]
    end
    lines[#lines + 1] = "COST " .. joined(self:reduced(costs)) .. " | " .. objective(self:phase_value(costs))
    return lines
end
return T
