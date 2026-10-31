local T = require("terms")
local U = {}
U.__index = U
function U.new() return setmetatable({ bindings = {} }, U) end
function U:mark() return #self.bindings end
function U:undo(mark)
    while #self.bindings > mark do table.remove(self.bindings).binding = nil end
end
function U:unify(a, b)
    local pending = { { a, b } }
    while #pending > 0 do
        local pair = table.remove(pending)
        local left, right = T.dereference(pair[1]), T.dereference(pair[2])
        if left ~= right then
            if T.is_variable(left) then left.binding = right; self.bindings[#self.bindings + 1] = left
            elseif T.is_variable(right) then right.binding = left; self.bindings[#self.bindings + 1] = right
            elseif T.is_compound(left) and T.is_compound(right) then
                if left.name ~= right.name or #left.args ~= #right.args then return false end
                for i = #left.args, 1, -1 do pending[#pending + 1] = { left.args[i], right.args[i] } end
            else return false end
        end
    end
    return true
end
function U.identical(a, b)
    local pending = { { a, b } }
    while #pending > 0 do
        local pair = table.remove(pending)
        local left, right = T.dereference(pair[1]), T.dereference(pair[2])
        if left ~= right then
            if T.is_variable(left) or T.is_variable(right) then return false end
            if T.is_compound(left) and T.is_compound(right) then
                if left.name ~= right.name or #left.args ~= #right.args then return false end
                for i = #left.args, 1, -1 do pending[#pending + 1] = { left.args[i], right.args[i] } end
            else return false end
        end
    end
    return true
end
return U
