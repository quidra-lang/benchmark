local M = {}
function M.new(capacity) return {capacity=capacity,texts={},log={}} end
function M.store(memory,prefix,keyword,text)
    for _,stored in ipairs(memory.texts) do
        if stored == text then table.insert(memory.log,prefix.." SKIP "..keyword.." "..text); return false end
    end
    if #memory.texts == memory.capacity then table.insert(memory.log,prefix.." DROP "..table.remove(memory.texts,1)) end
    table.insert(memory.texts,text); table.insert(memory.log,prefix.." STORE "..keyword.." "..text)
    return true
end
function M.recall(memory,prefix)
    local text = table.remove(memory.texts,1)
    table.insert(memory.log,prefix.." RECALL "..text)
    return text
end
function M.clear(memory,prefix)
    if #memory.texts > 0 then table.insert(memory.log,prefix.." CLEAR "..#memory.texts); memory.texts = {} end
end
return M
