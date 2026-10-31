local C = {}
C.__index = C
function C.copy(values)
    local result = {}
    for value in pairs(values) do result[value] = true end
    return result
end
function C.keys(values)
    local result = {}
    for value in pairs(values) do result[#result + 1] = value end
    table.sort(result)
    return result
end
function C.count(values) local n = 0; for _ in pairs(values) do n = n + 1 end; return n end
function C.equal(a, b)
    for value in pairs(a) do if not b[value] then return false end end
    for value in pairs(b) do if not a[value] then return false end end
    return true
end
function C.union(a, b) for value in pairs(b) do a[value] = true end; return a end
function C.intersect(a, b) for value in pairs(a) do if not b[value] then a[value] = nil end end; return a end
function C.new(fn)
    local result = setmetatable({ fn = fn, blocks = {}, instructions = {}, positions = {}, block_of = {}, reachable = {}, postorder = {},
        reverse_postorder = {}, reachable_predecessors = {}, dominators = {}, immediate = {}, loops = {}, depth = {} }, C)
    result:split(); result:connect(); result:dfs(); result:dominance(); result:natural_loops()
    return result
end
function C:split()
    local pending, first_label, current, previous = {}, nil, nil, nil
    for position, line in ipairs(self.fn.code) do
        if type(line) == "string" then
            if #pending == 0 then first_label = position end
            pending[#pending + 1] = line
        else
            local number = #self.instructions + 1
            if not current or #pending > 0 or previous == "goto" or previous == "if" or previous == "return" then
                local start = #pending > 0 and first_label or position
                if current then current.finish = start - 1 end
                current = { number = #self.blocks + 1, labels = pending, start = start, instructions = {}, predecessors = {}, successors = {} }
                self.blocks[#self.blocks + 1], pending = current, {}
            end
            self.instructions[number], self.positions[number], self.block_of[number] = line, position, current.number
            current.instructions[#current.instructions + 1], previous = number, line.kind
        end
    end
    current.finish = #self.fn.code
end
function C:connect()
    local labels = {}
    for number, block in ipairs(self.blocks) do for _, label in ipairs(block.labels) do labels[label] = number end end
    for number, block in ipairs(self.blocks) do
        local last = self.instructions[block.instructions[#block.instructions]]
        if last.kind == "goto" then block.successors = { labels[last.name] }
        elseif last.kind == "if" then
            block.successors = { number + 1 }
            if labels[last.name] ~= number + 1 then block.successors[2] = labels[last.name] end
        elseif last.kind ~= "return" then block.successors = { number + 1 } end
        for _, successor in ipairs(block.successors) do
            local predecessors = self.blocks[successor].predecessors
            predecessors[#predecessors + 1] = number
        end
    end
end
function C:dfs()
    local stack = { { 1, 1 } }
    self.reachable[1] = true
    while #stack > 0 do
        local top = stack[#stack]
        local successor = self.blocks[top[1]].successors[top[2]]
        if successor then
            top[2] = top[2] + 1
            if not self.reachable[successor] then self.reachable[successor] = true; stack[#stack + 1] = { successor, 1 } end
        else self.postorder[#self.postorder + 1] = top[1]; table.remove(stack) end
    end
    for i = #self.postorder, 1, -1 do self.reverse_postorder[#self.reverse_postorder + 1] = self.postorder[i] end
    for number in pairs(self.reachable) do
        local values = {}
        for _, predecessor in ipairs(self.blocks[number].predecessors) do if self.reachable[predecessor] then values[#values + 1] = predecessor end end
        self.reachable_predecessors[number] = values
    end
end
function C:dominance()
    for number in pairs(self.reachable) do self.dominators[number] = C.copy(self.reachable) end
    self.dominators[1] = { [1] = true }
    local changed = true
    while changed do
        changed = false
        for i = 2, #self.reverse_postorder do
            local number = self.reverse_postorder[i]
            local predecessors = self.reachable_predecessors[number]
            local values = C.copy(self.dominators[predecessors[1]])
            for j = 2, #predecessors do C.intersect(values, self.dominators[predecessors[j]]) end
            values[number] = true
            if not C.equal(values, self.dominators[number]) then self.dominators[number], changed = values, true end
        end
    end
    for number in pairs(self.reachable) do
        if number ~= 1 then
            local parent, largest = nil, -1
            for candidate in pairs(self.dominators[number]) do
                local size = C.count(self.dominators[candidate])
                if candidate ~= number and size > largest then parent, largest = candidate, size end
            end
            self.immediate[number] = parent
        end
    end
end
function C:natural_loops()
    for _, header in ipairs(C.keys(self.reachable)) do
        local latches, members, pending = {}, { [header] = true }, {}
        for _, number in ipairs(self.reachable_predecessors[header]) do
            if self.dominators[number][header] then
                latches[#latches + 1], members[number] = number, true
                if number ~= header then pending[#pending + 1] = number end
            end
        end
        if #latches > 0 then
            while #pending > 0 do
                local number = table.remove(pending)
                for _, predecessor in ipairs(self.reachable_predecessors[number]) do
                    if not members[predecessor] then members[predecessor] = true; pending[#pending + 1] = predecessor end
                end
            end
            self.loops[#self.loops + 1] = { header = header, latches = latches, blocks = members, exits = {}, outside = {}, depth = 0 }
        end
    end
    for number in ipairs(self.blocks) do
        self.depth[number] = 0
        for _, loop in ipairs(self.loops) do if loop.blocks[number] then self.depth[number] = self.depth[number] + 1 end end
    end
    for _, loop in ipairs(self.loops) do
        for _, other in ipairs(self.loops) do if other.blocks[loop.header] then loop.depth = loop.depth + 1 end end
        for number in pairs(loop.blocks) do
            local block = self.blocks[number]
            if self.instructions[block.instructions[#block.instructions]].kind == "return" then loop.exits[number] = true end
            for _, successor in ipairs(block.successors) do
                if not loop.blocks[successor] then loop.exits[number], loop.outside[successor] = true, true end
            end
        end
    end
end
return C
