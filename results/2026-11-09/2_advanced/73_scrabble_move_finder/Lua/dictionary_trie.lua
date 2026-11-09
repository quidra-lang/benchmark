local M = {}
M.__index = M
local LETTERS = 'ABCDEFGHIJKLMNOPQRSTUVWXYZ'
function M.new() return setmetatable({root = {children = {}, terminal = false}, nodes = 1, words = 0}, M) end
function M:add(word)
    local node = self.root
    for i = 1, #word do
        local letter = word:sub(i, i)
        if not node.children[letter] then node.children[letter] = {children = {}, terminal = false}; self.nodes = self.nodes + 1 end
        node = node.children[letter]
    end
    if node.terminal then return false end
    node.terminal, self.words = true, self.words + 1
    return true
end
function M:prefix(word)
    local node = self.root
    for i = 1, #word do node = node.children[word:sub(i, i)]; if not node then return nil end end
    return node
end
function M:contains(word)
    local node = self:prefix(word)
    return node ~= nil and node.terminal
end
function M:anagrams(rack)
    local counts, result = {}, {}
    for i = 1, #rack do local letter = rack:sub(i, i); counts[letter] = (counts[letter] or 0) + 1 end
    local function visit(node, word)
        if node.terminal then result[#result + 1] = word end
        for i = 1, 26 do
            local letter = LETTERS:sub(i, i)
            local child = node.children[letter]
            if child then
                local tile = (counts[letter] or 0) > 0 and letter or '?'
                if (counts[tile] or 0) > 0 then counts[tile] = counts[tile] - 1; visit(child, word .. letter); counts[tile] = counts[tile] + 1 end
            end
        end
    end
    visit(self.root, '')
    return result
end
return M
