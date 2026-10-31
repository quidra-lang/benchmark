local T = require("terms")
local D = {}
D.__index = D
function D.new() return setmetatable({ order = {}, predicates = {} }, D) end
function D:add(clause)
    local key = T.indicator(clause.head)
    if not self.predicates[key] then self.predicates[key] = {}; self.order[#self.order + 1] = key end
    local clauses = self.predicates[key]
    clauses[#clauses + 1] = clause
end
function D:candidates(goal)
    local result = {}
    local clauses = self.predicates[T.indicator(goal)]
    for _, clause in ipairs(clauses) do
        if not T.is_compound(goal) or T.same_kind(goal.args[1], clause.head.args[1]) then result[#result + 1] = clause end
    end
    return result
end
function D.copy_clause(clause) return T.copy_terms(clause.head, clause.body) end
return D
