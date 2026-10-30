local Topology = require("topology")
local Policy = {}
Policy.__index = Policy
Policy.NO_EXPORT = (65535 << 16) | 65281

function Policy.community(text)
    if text == "NO_EXPORT" then return Policy.NO_EXPORT end
    local first, second = text:match("^(%d+):(%d+)$")
    return (tonumber(first) << 16) | tonumber(second)
end

function Policy.communities(fields, first)
    local set, result = {}, {}
    for i = first or 1, #fields do set[Policy.community(fields[i])] = true end
    for value in pairs(set) do result[#result + 1] = value end
    table.sort(result)
    return result
end

function Policy.communities_text(values)
    local result = {}
    for _, value in ipairs(values) do
        result[#result + 1] = value == Policy.NO_EXPORT and "NO_EXPORT"
            or string.format("%d:%d", value >> 16, value & 65535)
    end
    return #result == 0 and "-" or table.concat(result, ",")
end

function Policy.contains(values, value)
    for _, item in ipairs(values) do if item == value then return true end end
    return false
end

function Policy.edit(values, rule)
    local set, result = {}, {}
    for _, value in ipairs(values) do set[value] = true end
    for _, action in ipairs(rule.actions) do
        if action[1] == "ADD" then set[action[2]] = true
        elseif action[1] == "REMOVE" then set[action[2]] = nil end
    end
    for value in pairs(set) do result[#result + 1] = value end
    table.sort(result)
    return result
end

function Policy.new()
    local self = setmetatable({lists = {}, rules = {}, by_name = {}}, Policy)
    for _, f in ipairs(Topology.read("input/policies.txt")) do
        if f[1] == "PLIST" then
            local base, ge, le = Topology.prefix(f[4])
            for i = 5, #f, 2 do
                if f[i] == "GE" then ge = tonumber(f[i + 1]) else le = tonumber(f[i + 1]) end
            end
            local entry = {permit = f[3] == "PERMIT", base = base, low = ge or base.length,
                high = le or (ge and 32 or base.length)}
            self.lists[f[2]] = self.lists[f[2]] or {}
            local list = self.lists[f[2]]
            list[#list + 1] = entry
        else
            local rule = {name = f[2], active = f[3] == "ON", owner = tonumber(f[4]),
                direction = f[5], target = f[6], conditions = {}, actions = {}, settings = {}, hits = 0}
            local i = 7
            while f[i] ~= "THEN" do
                local condition, value = f[i], f[i + 1]
                if condition == "CONTAINS" or condition == "ORIGINAS" then value = tonumber(value)
                elseif condition == "COMMUNITY" then value = Policy.community(value)
                elseif condition == "LENGTH" then
                    local low, high = value:match("^(%d+)%-(%d+)$")
                    value = {tonumber(low), tonumber(high)}
                end
                rule.conditions[#rule.conditions + 1] = {condition, value}
                i = i + 2
            end
            i = i + 1
            while i <= #f do
                local action, value = f[i], true
                i = i + 1
                if action ~= "ALLOW" and action ~= "DENY" then
                    value = (action == "ADD" or action == "REMOVE") and Policy.community(f[i]) or tonumber(f[i])
                    i = i + 1
                end
                rule.actions[#rule.actions + 1] = {action, value}
                rule.settings[action] = value
            end
            self.rules[#self.rules + 1], self.by_name[rule.name] = rule, rule
        end
    end
    return self
end

function Policy:permitted(name, prefix)
    local value = Topology.prefix(prefix)
    for _, entry in ipairs(self.lists[name]) do
        if value.length >= entry.low and value.length <= entry.high and Topology.contains(entry.base, value.address) then
            return entry.permit
        end
    end
    return false
end

function Policy:matches(rule, owner, link, prefix, path, communities)
    if not rule.active or rule.owner ~= owner then return false end
    if rule.target ~= "*" and rule.target ~= tostring(link:other(owner)) and rule.target ~= link.name then return false end
    for _, item in ipairs(rule.conditions) do
        local condition, value = item[1], item[2]
        if condition == "PREFIX" and not self:permitted(value, prefix) then return false end
        if condition == "CONTAINS" and not Policy.contains(path, value) then return false end
        if condition == "ORIGINAS" and (#path == 0 and owner or path[#path]) ~= value then return false end
        if condition == "LENGTH" and (#path < value[1] or #path > value[2]) then return false end
        if condition == "COMMUNITY" and not Policy.contains(communities, value) then return false end
    end
    return true
end

function Policy:applied(direction, owner, link, prefix, path, communities)
    for _, rule in ipairs(self.rules) do
        if rule.direction == direction and self:matches(rule, owner, link, prefix, path, communities) then return rule end
    end
end

return Policy
