local M = {}
function M.area(box)
    return (box[3] - box[1]) * (box[4] - box[2])
end
function M.mbr(first, second)
    return {math.min(first[1], second[1]), math.min(first[2], second[2]), math.max(first[3], second[3]), math.max(first[4], second[4])}
end
function M.enlargement(first, second)
    return M.area(M.mbr(first, second)) - M.area(first)
end
function M.contains(outer, inner)
    return outer[1] <= inner[1] and inner[3] <= outer[3] and outer[2] <= inner[2] and inner[4] <= outer[4]
end
function M.intersects(first, second)
    return first[1] <= second[3] and second[1] <= first[3] and first[2] <= second[4] and second[2] <= first[4]
end
function M.overlap(first, second)
    local width = math.min(first[3], second[3]) - math.max(first[1], second[1])
    local height = math.min(first[4], second[4]) - math.max(first[2], second[2])
    return width > 0 and height > 0 and width * height or 0
end
local function less(first, second)
    for i = 1, #first do
        if first[i] ~= second[i] then
            return first[i] < second[i]
        end
    end
    return false
end
local Node = {}
Node.__index = Node
local function node(level, entries, parent)
    local result = setmetatable({level = level, entries = entries or {}, parent = parent}, Node)
    result:adopt()
    return result
end
function Node:adopt()
    if self.level > 0 then
        for _, entry in ipairs(self.entries) do
            entry.child.parent = self
        end
    end
end
function Node:box()
    local result = self.entries[1].box
    for i = 2, #self.entries do
        result = M.mbr(result, self.entries[i].box)
    end
    return result
end
local Tree = {}
Tree.__index = Tree
function Tree:choose(box, level)
    local current = self.root
    while current.level > level do
        local selected = 1
        for i = 2, #current.entries do
            local first, second = current.entries[i].box, current.entries[selected].box
            if less({M.enlargement(first, box), M.area(first)}, {M.enlargement(second, box), M.area(second)}) then
                selected = i
            end
        end
        current = current.entries[selected].child
    end
    return current
end
function Tree:split(current)
    local entries, first_seed, second_seed, best = current.entries, nil, nil, nil
    for i = 1, #entries - 1 do
        for j = i + 1, #entries do
            local waste = M.area(M.mbr(entries[i].box, entries[j].box)) - M.area(entries[i].box) - M.area(entries[j].box)
            if not best or waste > best then
                first_seed, second_seed, best = i, j, waste
            end
        end
    end
    local first, second, rest = {entries[first_seed]}, {entries[second_seed]}, {}
    local box1, box2 = entries[first_seed].box, entries[second_seed].box
    for i, entry in ipairs(entries) do
        if i ~= first_seed and i ~= second_seed then
            rest[#rest + 1] = entry
        end
    end
    while #rest > 0 do
        if #first + #rest == self.minimum then
            for _, entry in ipairs(rest) do
                first[#first + 1] = entry
            end
            break
        elseif #second + #rest == self.minimum then
            for _, entry in ipairs(rest) do
                second[#second + 1] = entry
            end
            break
        end
        local selected, difference, selected_d1, selected_d2 = 1, -1, 0, 0
        for i, entry in ipairs(rest) do
            local d1, d2 = M.enlargement(box1, entry.box), M.enlargement(box2, entry.box)
            local value = math.abs(d1 - d2)
            if value > difference then
                selected, difference, selected_d1, selected_d2 = i, value, d1, d2
            end
        end
        local entry = table.remove(rest, selected)
        if less({selected_d1, M.area(box1), #first, 0}, {selected_d2, M.area(box2), #second, 1}) then
            first[#first + 1], box1 = entry, M.mbr(box1, entry.box)
        else
            second[#second + 1], box2 = entry, M.mbr(box2, entry.box)
        end
    end
    current.entries = first
    current:adopt()
    return node(current.level, second, current.parent)
end
function Tree:insert(entry, level)
    level = level or 0
    local current = self:choose(entry.box, level)
    current.entries[#current.entries + 1] = entry
    if level > 0 then
        entry.child.parent = current
    end
    while true do
        local sibling
        if #current.entries > self.maximum then
            sibling = self:split(current)
        end
        local parent = current.parent
        if not parent then
            if sibling then
                self.root = node(current.level + 1, {{box = current:box(), child = current}, {box = sibling:box(), child = sibling}})
            end
            return
        end
        for _, parent_entry in ipairs(parent.entries) do
            if parent_entry.child == current then
                parent_entry.box = current:box()
                break
            end
        end
        if sibling then
            parent.entries[#parent.entries + 1] = {box = sibling:box(), child = sibling}
            sibling.parent = parent
        end
        current = parent
    end
end
function Tree:find_leaf(id, box)
    local pending = {self.root}
    while #pending > 0 do
        local current = table.remove(pending)
        if current.level == 0 then
            for i, entry in ipairs(current.entries) do
                if entry.id == id then
                    return current, i
                end
            end
        else
            for i = #current.entries, 1, -1 do
                local entry = current.entries[i]
                if M.contains(entry.box, box) then
                    pending[#pending + 1] = entry.child
                end
            end
        end
    end
end
function Tree:delete(point)
    local current, index = self:find_leaf(point.id, point.box)
    table.remove(current.entries, index)
    local removed = {}
    while current ~= self.root do
        local parent = current.parent
        for i, entry in ipairs(parent.entries) do
            if entry.child == current then
                if #current.entries < self.minimum then
                    table.remove(parent.entries, i)
                    removed[#removed + 1] = current
                    current.parent = nil
                else
                    entry.box = current:box()
                end
                break
            end
        end
        current = parent
    end
    for _, discarded in ipairs(removed) do
        for _, entry in ipairs(discarded.entries) do
            self:insert(entry, discarded.level)
        end
    end
    while self.root.level > 0 and #self.root.entries == 1 do
        self.root = self.root.entries[1].child
        self.root.parent = nil
    end
end
local function str_root(entries, maximum)
    local numbered = {}
    for _, entry in ipairs(entries) do
        numbered[#numbered + 1] = {number = entry.id, entry = entry}
    end
    local level = 0
    while true do
        local pages = (#numbered + maximum - 1) // maximum
        local slabs = 1
        while slabs * slabs < pages do
            slabs = slabs + 1
        end
        local function order(axis)
            return function(first, second)
                local a, b = first.entry.box, second.entry.box
                if axis == 1 then
                    return less({a[1] + a[3], a[2] + a[4], first.number}, {b[1] + b[3], b[2] + b[4], second.number})
                end
                return less({a[2] + a[4], a[1] + a[3], first.number}, {b[2] + b[4], b[1] + b[3], second.number})
            end
        end
        table.sort(numbered, order(1))
        local nodes, slab_size = {}, slabs * maximum
        for first = 1, #numbered, slab_size do
            local slab = {}
            for i = first, math.min(first + slab_size - 1, #numbered) do
                slab[#slab + 1] = numbered[i]
            end
            table.sort(slab, order(2))
            for offset = 1, #slab, maximum do
                local group = {}
                for i = offset, math.min(offset + maximum - 1, #slab) do
                    group[#group + 1] = slab[i].entry
                end
                nodes[#nodes + 1] = node(level, group)
            end
        end
        if #nodes == 1 then
            return nodes[1]
        end
        numbered = {}
        for i, current in ipairs(nodes) do
            numbered[i] = {number = i - 1, entry = {box = current:box(), child = current}}
        end
        level = level + 1
    end
end
function M.build(objects, maximum, minimum, bulk)
    local tree = setmetatable({maximum = maximum, minimum = minimum, root = node(0)}, Tree)
    local entries = {}
    for i, object in ipairs(objects) do
        entries[i] = {box = object.box, id = object.id}
    end
    if bulk then
        tree.root = str_root(entries, maximum)
    else
        for _, entry in ipairs(entries) do
            tree:insert(entry)
        end
    end
    return tree
end
return M
