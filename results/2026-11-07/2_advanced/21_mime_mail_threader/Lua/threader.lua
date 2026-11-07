local M = {}

local function container(message_id) return {id = message_id, children = {}} end
local function adopt(parent, child) child.parent = parent parent.children[#parent.children + 1] = child end
local function ancestor(first, second)
    while second do if first == second then return true end second = second.parent end
    return false
end
local function key_compare(first, second)
    for index = 1, #first do
        if first[index] ~= second[index] then return first[index] < second[index] end
    end
    return false
end
local function container_key(node)
    if node.message then return node.message.sort_key end
    local best
    for _, child in ipairs(node.children) do
        local key = container_key(child)
        if best == nil or key_compare(key, best) then best = key end
    end
    return best
end
local function sort_containers(nodes)
    for _, node in ipairs(nodes) do sort_containers(node.children) end
    table.sort(nodes, function(a, b) return key_compare(container_key(a), container_key(b)) end)
end

local function prune(nodes, at_root)
    local result = {}
    for _, node in ipairs(nodes) do
        node.children = prune(node.children, false)
        if node.message or at_root and #node.children >= 2 then result[#result + 1] = node
        else
            for _, child in ipairs(node.children) do
                if at_root then child.parent = nil else child.parent = node.parent end
                result[#result + 1] = child
            end
        end
    end
    return result
end

function M.root_subject(root)
    if root.message then return root.message.base_subject end
    return root.children[1].message.base_subject
end

function M.build_threads(messages)
    local table_by_id, containers = {}, {}
    local function container_of(message_id)
        if not table_by_id[message_id] then
            local node = container(message_id)
            table_by_id[message_id] = node
            containers[#containers + 1] = node
        end
        return table_by_id[message_id]
    end
    for _, message in ipairs(messages) do
        local node
        if message.id ~= "" then node = container_of(message.id)
        else node = container("") containers[#containers + 1] = node end
        node.message = message
        local references = {}
        for _, id in ipairs(message.references) do references[#references + 1] = container_of(id) end
        for index = 1, #references - 1 do
            local current, following = references[index], references[index + 1]
            if following.parent == nil and not ancestor(following, current) then adopt(current, following) end
        end
        if node.parent then
            for index, child in ipairs(node.parent.children) do if child == node then table.remove(node.parent.children, index) break end end
            node.parent = nil
        end
        if #references > 0 and not ancestor(node, references[#references]) then adopt(references[#references], node) end
    end
    local roots = {}
    for _, node in ipairs(containers) do if node.parent == nil then roots[#roots + 1] = node end end
    roots = prune(roots, true)
    sort_containers(roots)
    local groups, subjects = {}, {}
    for _, root in ipairs(roots) do
        local subject = M.root_subject(root)
        if subject ~= "" then
            if groups[subject] == nil then groups[subject] = {} subjects[#subjects + 1] = subject end
            local group = groups[subject]
            group[#group + 1] = root
        end
    end
    local merged = {}
    for _, root in ipairs(roots) do
        local subject = M.root_subject(root)
        if subject == "" or #groups[subject] == 1 then merged[#merged + 1] = root end
    end
    for _, subject in ipairs(subjects) do
        local group = groups[subject]
        if #group >= 2 then
            local target, original, originals = nil, nil, 0
            for _, root in ipairs(group) do
                if root.message == nil and target == nil then target = root end
                if root.message and not root.message.reply then original, originals = root, originals + 1 end
            end
            if target == nil then
                if originals == 1 then target = original else target = container("") target.subject = subject end
            end
            for _, root in ipairs(group) do
                if root ~= target then
                    if root.message then adopt(target, root)
                    else for _, child in ipairs(root.children) do adopt(target, child) end end
                end
            end
            merged[#merged + 1] = target
        end
    end
    sort_containers(merged)
    return merged
end

return M
