local M = {}
local Model = {}
Model.__index = Model
local Design = {}
Design.__index = Design
local function split(text, separator)
    local result, position = {}, 1
    while true do
        local first, last = text:find(separator, position, true)
        if not first then
            result[#result + 1] = text:sub(position)
            return result
        end
        result[#result + 1] = text:sub(position, first - 1)
        position = last + 1
    end
end
local function factor(name)
    local result = {name = name, power = 1, categorical = name:sub(1, 2) == "C("}
    if result.categorical then
        result.column = name:sub(3, -2)
    elseif name:sub(1, 2) == "I(" then
        local column, power = name:match("^I%((.-)%^(%d)%)$")
        result.column, result.power = column, tonumber(power)
    else
        result.column = name
    end
    return result
end
local function term(factors)
    local names, keys = {}, {}
    for _, value in ipairs(factors) do
        names[#names + 1] = value.name
        keys[value.name] = true
    end
    local sorted = {table.unpack(names)}
    table.sort(sorted)
    return {factors = factors, name = table.concat(names, ":"), key = table.concat(sorted, ":"), keys = keys}
end
local function contained(first, second)
    if #first.factors >= #second.factors then
        return false
    end
    for _, value in ipairs(first.factors) do
        if not second.keys[value.name] then
            return false
        end
    end
    return true
end
function M.parse(line)
    local parts = split(line, " weights=")
    local halves = split(parts[1], " ~ ")
    local model = setmetatable({original = parts[1], response = halves[1], weight = parts[2], terms = {}, factor_columns = {}, categorical_columns = {}, variables = {}}, Model)
    local seen, columns, categorical = {}, {}, {}
    for _, expression in ipairs(split(halves[2], " + ")) do
        local expanded = {}
        if expression:find("*", 1, true) then
            local factors = {}
            for _, name in ipairs(split(expression, "*")) do
                factors[#factors + 1] = factor(name)
            end
            for size = 1, #factors do
                for mask = 1, (1 << #factors) - 1 do
                    local chosen = {}
                    for index, value in ipairs(factors) do
                        if (mask & (1 << (index - 1))) ~= 0 then
                            chosen[#chosen + 1] = value
                        end
                    end
                    if #chosen == size then
                        expanded[#expanded + 1] = chosen
                    end
                end
            end
        else
            local factors = {}
            for _, name in ipairs(split(expression, ":")) do
                factors[#factors + 1] = factor(name)
            end
            expanded[1] = factors
        end
        for _, factors in ipairs(expanded) do
            local item = term(factors)
            if not seen[item.key] then
                seen[item.key] = true
                model.terms[#model.terms + 1] = item
                for _, value in ipairs(factors) do
                    if not columns[value.column] then
                        columns[value.column] = true
                        model.factor_columns[#model.factor_columns + 1] = value.column
                        model.variables[#model.variables + 1] = value.column
                    end
                    if value.categorical and not categorical[value.column] then
                        categorical[value.column] = true
                        model.categorical_columns[#model.categorical_columns + 1] = value.column
                    end
                end
            end
        end
    end
    model.variables[#model.variables + 1] = model.response
    if model.weight then
        model.variables[#model.variables + 1] = model.weight
    end
    return model
end
function Model:format(indices)
    local names = {}
    for _, index in ipairs(indices) do
        names[#names + 1] = self.terms[index].name
    end
    return self.response .. " ~ " .. (#names == 0 and "1" or table.concat(names, " + "))
end
function Model:removable(indices)
    local result = {}
    for _, index in ipairs(indices) do
        local allowed = true
        for _, other in ipairs(indices) do
            if contained(self.terms[index], self.terms[other]) then
                allowed = false
                break
            end
        end
        if allowed then
            result[#result + 1] = index
        end
    end
    return result
end
function Model:candidates(indices)
    local selected, result = {}, {}
    for _, index in ipairs(indices) do
        selected[index] = true
    end
    for index, item in ipairs(self.terms) do
        local allowed = not selected[index]
        for other, smaller in ipairs(self.terms) do
            if contained(smaller, item) and not selected[other] then
                allowed = false
            end
        end
        if allowed then
            result[#result + 1] = index
        end
    end
    return result
end
function Model:hierarchical(indices)
    local selected = {}
    for _, index in ipairs(indices) do
        selected[index] = true
    end
    for _, index in ipairs(indices) do
        for other, item in ipairs(self.terms) do
            if contained(item, self.terms[index]) and not selected[other] then
                return false
            end
        end
    end
    return true
end
local function component_value(component, row)
    local item, value = component.factor, row[component.factor.column]
    if item.categorical then
        return value == component.level and 1.0 or 0.0
    elseif item.power == 2 then
        return value * value
    elseif item.power == 3 then
        return value * value * value
    end
    return value
end
function Design:values(row)
    local values = {}
    for _, column in ipairs(self.columns) do
        local value = 1.0
        for index, component in ipairs(column.components) do
            local next_value = component_value(component, row)
            value = index == 1 and next_value or value * next_value
        end
        values[#values + 1] = value
    end
    return values
end
function Design:subset_matrix(indices)
    local selected, result = {}, {}
    for _, index in ipairs(indices) do
        selected[index] = true
    end
    for _, row in ipairs(self.matrix) do
        local values = {}
        for index, column in ipairs(self.columns) do
            if column.term_index == 0 or selected[column.term_index] then
                values[#values + 1] = row[index]
            end
        end
        result[#result + 1] = values
    end
    return result
end
function Design:predictable(row)
    for _, column in ipairs(self.model.factor_columns) do
        local value = row[column]
        if value == nil then
            return false
        end
        if self.levels[column] then
            local found = false
            for _, level in ipairs(self.levels[column]) do
                found = found or level == value
            end
            if not found then
                return false
            end
        end
    end
    return true
end
function M.design(model, data)
    local design = setmetatable({model = model, rows = {}, row_numbers = {}, levels = {}, columns = {}, matrix = {}, response = {}, weights = {}}, Design)
    for index, row in ipairs(data.rows) do
        local complete = true
        for _, column in ipairs(model.variables) do
            complete = complete and row[column] ~= nil
        end
        if complete then
            design.rows[#design.rows + 1] = row
            design.row_numbers[#design.row_numbers + 1] = index
        end
    end
    for _, column in ipairs(model.categorical_columns) do
        local seen, values = {}, {}
        for _, row in ipairs(design.rows) do
            if not seen[row[column]] then
                seen[row[column]] = true
                values[#values + 1] = row[column]
            end
        end
        table.sort(values)
        design.levels[column] = values
    end
    design.columns[1] = {term_index = 0, name = "(Intercept)", components = {}}
    for term_index, item in ipairs(model.terms) do
        local choices, total = {}, 1
        for _, value in ipairs(item.factors) do
            local components = {}
            if value.categorical then
                for index = 2, #design.levels[value.column] do
                    local level = design.levels[value.column][index]
                    components[#components + 1] = {factor = value, name = value.name .. level, level = level}
                end
            else
                components[1] = {factor = value, name = value.name}
            end
            choices[#choices + 1], total = components, total * #components
        end
        for code = 0, total - 1 do
            local remaining, names, components = code, {}, {}
            for _, options in ipairs(choices) do
                local component = options[remaining % #options + 1]
                remaining = remaining // #options
                names[#names + 1], components[#components + 1] = component.name, component
            end
            design.columns[#design.columns + 1] = {term_index = term_index, name = table.concat(names, ":"), components = components}
        end
    end
    for _, row in ipairs(design.rows) do
        design.matrix[#design.matrix + 1] = design:values(row)
        design.response[#design.response + 1] = row[model.response]
        design.weights[#design.weights + 1] = model.weight and row[model.weight] or 1.0
    end
    return design
end
return M
