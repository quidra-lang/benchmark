local M = {}
local function wildcard(element) return element == "*" or element == "#" or element:sub(1,1) == "@" end
function M.match(pattern, words, groups)
    local ends = {}
    local function visit(i,j)
        if i > #pattern then return j > #words end
        local element = pattern[i]
        if element == "*" then
            for last=j-1,#words do ends[i] = last; if visit(i+1,last+1) then return true end end
        elseif j <= #words and (element == "#" or element == words[j] or (element:sub(1,1) == "@" and (groups[element:sub(2)] or {})[words[j]])) then
            ends[i] = j; if visit(i+1,j+1) then return true end
        end
        return false
    end
    if not visit(1,1) then return nil end
    local bindings,start = {},1
    for i,element in ipairs(pattern) do
        if wildcard(element) then
            local binding = {}; for j=start,ends[i] do binding[#binding+1] = words[j] end
            bindings[#bindings+1] = binding
        end
        start = ends[i]+1
    end
    return bindings
end
function M.covers(earlier,later,groups)
    local function fits(element,other)
        if element == "#" then return other ~= "*" end
        if element:sub(1,1) == "@" then
            local members = groups[element:sub(2)]
            if other:sub(1,1) == "@" then
                for word in pairs(groups[other:sub(2)]) do if not members[word] then return false end end
                return true
            end
            return members[other] == true
        end
        return element == other
    end
    local function visit(i,j)
        if i > #earlier then return j > #later end
        if earlier[i] == "*" then
            for last=j-1,#later do if visit(i+1,last+1) then return true end end
            return false
        end
        return j <= #later and fits(earlier[i],later[j]) and visit(i+1,j+1)
    end
    return visit(1,1)
end
return M
