local is_section_name = require("ini_parser").is_section_name
local LITERAL_DOLLAR = require("lexer").LITERAL_DOLLAR

local Expander = {}
Expander.__index = Expander

function Expander.new(values, origins)
    return setmetatable({
        values = values,
        origins = origins,
        results = {},
        in_progress = {},
        cycle_keys = {},
        diagnostics = {},
    }, Expander)
end

function Expander:report(origin, code, message)
    table.insert(self.diagnostics, {
        document = origin.document,
        line = origin.line,
        code = code,
        message = message,
    })
end

-- A result is the expanded string, or false when the expansion failed.
function Expander:expand(key)
    if self.results[key] == nil then
        table.insert(self.in_progress, key)
        local result = self:evaluate(key)
        table.remove(self.in_progress)
        self.results[key] = result
    end
    return self.results[key]
end

function Expander:progress_index(key)
    for index, active in ipairs(self.in_progress) do
        if active == key then
            return index
        end
    end
    return nil
end

function Expander:evaluate(key)
    local value = self.values[key]
    local origin = self.origins[key]
    local section = key:match("^(.*)%.")
    local pieces = {}
    local position = 1
    while position <= #value do
        if value:sub(position, position + 1) ~= "${" then
            local char = value:sub(position, position)
            table.insert(pieces, char == LITERAL_DOLLAR and "$" or char)
            position = position + 1
        else
            local close = value:find("}", position + 2, true)
            local reference = close and value:sub(position + 2, close - 1)
            if not close or not is_section_name(reference) then
                self:report(origin, "E_BAD_REF", key .. ": invalid reference")
                return false
            end
            local target = reference:find(".", 1, true) and reference or section .. "." .. reference
            if self.values[target] == nil then
                self:report(origin, "E_UNDEFINED", key .. ": undefined reference " .. target)
                return false
            end
            local expanded = false
            if self:progress_index(target) then
                self:report_cycle(target)
            else
                expanded = self:expand(target)
            end
            if not expanded then
                if not self.cycle_keys[key] then
                    self:report(origin, "E_DEPENDENCY", key .. ": depends on failed key " .. target)
                end
                return false
            end
            table.insert(pieces, expanded)
            position = close + 1
        end
    end
    return table.concat(pieces)
end

function Expander:report_cycle(target)
    local path = { table.unpack(self.in_progress, self:progress_index(target)) }
    table.insert(path, target)
    local message = "interpolation cycle " .. table.concat(path, " -> ")
    self:report(self.origins[target], "E_CYCLE", message)
    for _, key in ipairs(path) do
        self.cycle_keys[key] = true
    end
end

return { Expander = Expander }
