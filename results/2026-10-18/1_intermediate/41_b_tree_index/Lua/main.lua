local function fail(format, ...)
    error({ message = string.format(format, ...) }, 0)
end
local function slice(values, first, last)
    local result = {}
    for i = first or 1, last or #values do result[#result + 1] = values[i] end
    return result
end
local function append(target, source)
    for _, value in ipairs(source) do target[#target + 1] = value end
end
local function display(entry) return entry.key .. "=" .. entry.value end
local function same_values(left, right)
    if #left ~= #right then return false end
    for i, value in ipairs(left) do if value ~= right[i] then return false end end
    return true
end

local Node = {}
Node.__index = Node
function Node.new(entries, children)
    return setmetatable({ entries = entries or {}, children = children or {} }, Node)
end
function Node:leaf() return #self.children == 0 end
function Node:position(key)
    for i, entry in ipairs(self.entries) do if key <= entry.key then return i end end
    return #self.entries + 1
end
function Node:copy() return Node.new(slice(self.entries), slice(self.children)) end
function Node:same_content(other)
    if #self.entries ~= #other.entries or not same_values(self.children, other.children) then return false end
    for i, entry in ipairs(self.entries) do
        if entry.key ~= other.entries[i].key or entry.value ~= other.entries[i].value then return false end
    end
    return true
end
function Node:__tostring()
    local keys = {}
    for _, entry in ipairs(self.entries) do keys[#keys + 1] = entry.key end
    return "[" .. table.concat(keys, " ") .. "]"
end

local Trace = {}
Trace.__index = Trace
function Trace.new(enabled) return setmetatable({ enabled = enabled, lines = {}, cases = {} }, Trace) end
function Trace:emit(format, ...)
    if self.enabled then self.lines[#self.lines + 1] = string.format(format, ...) end
end
function Trace:record(name) self.cases[#self.cases + 1] = name end

local Tree = {}
Tree.__index = Tree
function Tree.new(degree, empty)
    local tree = setmetatable({ degree = degree, root = 0, pages = {}, splits = 0, merges = 0, borrows = 0 }, Tree)
    if empty ~= false then tree.pages[0] = Node.new() end
    return tree
end
function Tree:copy()
    local result = Tree.new(self.degree, false)
    result.root, result.splits, result.merges, result.borrows = self.root, self.splits, self.merges, self.borrows
    for page, node in pairs(self.pages) do result.pages[page] = node:copy() end
    return result
end
function Tree:new_page(node)
    local page = 0
    while self.pages[page] ~= nil do page = page + 1 end
    self.pages[page] = node
    return page
end
function Tree:node_count()
    local count = 0
    for _ in pairs(self.pages) do count = count + 1 end
    return count
end
function Tree.load(degree, tokens)
    local tree, position = Tree.new(degree, false), 1
    local function read_entry()
        local token = tokens[position]
        if token == nil or token == "(" or token == ")" then fail("SYNTAX %d", position) end
        local key, value = token:match("^(%-?%d+)=(.+)$")
        position = position + 1
        return { key = tonumber(key), value = value }
    end
    local function read_node()
        if tokens[position] ~= "(" then fail("SYNTAX %d", position) end
        position = position + 1
        local node = Node.new()
        local page = tree:new_page(node)
        if tokens[position] == "(" then
            node.children[#node.children + 1] = read_node()
            while tokens[position] ~= ")" do
                node.entries[#node.entries + 1] = read_entry()
                node.children[#node.children + 1] = read_node()
            end
        else
            while tokens[position] ~= ")" do node.entries[#node.entries + 1] = read_entry() end
        end
        position = position + 1
        return page
    end
    tree.root = read_node()
    if position ~= #tokens + 1 then fail("SYNTAX %d", position) end
    return tree
end
function Tree:entries()
    local result = {}
    local function visit(page)
        local node = self.pages[page]
        if not node:leaf() then visit(node.children[1]) end
        for i, entry in ipairs(node.entries) do
            result[#result + 1] = entry
            if not node:leaf() then visit(node.children[i + 1]) end
        end
    end
    visit(self.root)
    return result
end
function Tree:height()
    local page, depth = self.root, 0
    while not self.pages[page]:leaf() do
        page, depth = self.pages[page].children[1], depth + 1
    end
    return depth
end
function Tree:search(key)
    local page, path = self.root, {}
    while true do
        local node = self.pages[page]
        path[#path + 1] = tostring(node)
        local position = node:position(key)
        if position <= #node.entries and node.entries[position].key == key then
            return { page = page, position = position, path = path }
        end
        if node:leaf() then return { path = path } end
        page = node.children[position]
    end
end
function Tree:violation()
    local reference
    local function visit(page, location, depth, low, high)
        local node = self.pages[page]
        local count = #node.entries
        local minimum = page == self.root and (node:leaf() and 0 or 1) or self.degree - 1
        local maximum = 2 * self.degree - 1
        if count < minimum or count > maximum then
            return string.format("COUNT at=%s node=%s keys=%d allowed=%d..%d", location, node, count, minimum, maximum)
        end
        for i = 1, count - 1 do
            local left, right = node.entries[i].key, node.entries[i + 1].key
            if left >= right then return string.format("ORDER at=%s node=%s %d>=%d", location, node, left, right) end
        end
        for _, entry in ipairs(node.entries) do
            if (low ~= nil and entry.key <= low) or (high ~= nil and entry.key >= high) then
                return string.format("RANGE at=%s node=%s key=%d low=%s high=%s", location, node, entry.key,
                    low == nil and "-inf" or low, high == nil and "+inf" or high)
            end
        end
        if node:leaf() then
            if reference == nil then reference = depth
            elseif depth ~= reference then
                return string.format("DEPTH at=%s node=%s depth=%d expected=%d", location, node, depth, reference)
            end
        end
        for i, child in ipairs(node.children) do
            local child_low, child_high = low, high
            if i > 1 then child_low = node.entries[i - 1].key end
            if i <= count then child_high = node.entries[i].key end
            local problem = visit(child, location .. "." .. (i - 1), depth + 1, child_low, child_high)
            if problem ~= nil then return problem end
        end
        return nil
    end
    return visit(self.root, "root", 0, nil, nil)
end
function Tree:changes(before)
    local writes, frees = 0, 0
    for page, node in pairs(self.pages) do
        if before.pages[page] == nil or not node:same_content(before.pages[page]) then writes = writes + 1 end
    end
    for page in pairs(before.pages) do if self.pages[page] == nil then frees = frees + 1 end end
    return writes, frees
end
function Tree:split_child(parent_page, position, trace)
    local parent = self.pages[parent_page]
    local child_page = parent.children[position]
    local child = self.pages[child_page]
    local middle = child.entries[self.degree]
    local right = Node.new(slice(child.entries, self.degree + 1),
        child:leaf() and {} or slice(child.children, self.degree + 1))
    local right_page = self:new_page(right)
    trace:emit("STEP split page=%d keys=%s up=%d new=%d", child_page, child, middle.key, right_page)
    child.entries = slice(child.entries, 1, self.degree - 1)
    if not child:leaf() then child.children = slice(child.children, 1, self.degree) end
    table.insert(parent.entries, position, middle)
    table.insert(parent.children, position + 1, right_page)
    self.splits = self.splits + 1
end
function Tree:upsert(key, value, trace)
    local found = self:search(key)
    if found.page ~= nil then
        local node = self.pages[found.page]
        local old = node.entries[found.position].value
        node.entries[found.position] = { key = key, value = value }
        return old
    end
    if #self.pages[self.root].entries == 2 * self.degree - 1 then
        local previous = self.root
        self.root = self:new_page(Node.new({}, { previous }))
        trace:emit("STEP grow page=%d", self.root)
        self:split_child(self.root, 1, trace)
    end
    local page = self.root
    while not self.pages[page]:leaf() do
        local node = self.pages[page]
        local position = node:position(key)
        if #self.pages[node.children[position]].entries == 2 * self.degree - 1 then
            self:split_child(page, position, trace)
            if key > node.entries[position].key then position = position + 1 end
        end
        page = node.children[position]
    end
    local node = self.pages[page]
    table.insert(node.entries, node:position(key), { key = key, value = value })
    trace:emit("STEP place page=%d keys=%s", page, node)
    return nil
end
function Tree:merge(parent_page, position, case, trace)
    local parent = self.pages[parent_page]
    local left_page, right_page = parent.children[position], parent.children[position + 1]
    local left, right = self.pages[left_page], self.pages[right_page]
    left.entries[#left.entries + 1] = parent.entries[position]
    append(left.entries, right.entries)
    append(left.children, right.children)
    table.remove(parent.entries, position)
    table.remove(parent.children, position + 1)
    self.pages[right_page] = nil
    self.merges = self.merges + 1
    trace:emit("STEP %s page=%d merge=%d+%d keys=%s", case, parent_page, left_page, right_page, left)
    if parent_page == self.root and #parent.entries == 0 then
        self.root = left_page
        self.pages[parent_page] = nil
        trace:emit("STEP shrink page=%d", left_page)
    end
    return left_page
end
function Tree:remove_at(page, key, trace)
    local node = self.pages[page]
    local position = node:position(key)
    if position <= #node.entries and node.entries[position].key == key then
        if node:leaf() then
            trace:record("1")
            table.remove(node.entries, position)
            trace:emit("STEP 1 page=%d keys=%s", page, node)
            return
        end
        local left, right = node.children[position], node.children[position + 1]
        if #self.pages[left].entries >= self.degree then
            local last = left
            while not self.pages[last]:leaf() do
                local children = self.pages[last].children
                last = children[#children]
            end
            local rows = self.pages[last].entries
            local predecessor = rows[#rows]
            trace:record("2a")
            trace:emit("STEP 2a page=%d pred=%d", page, predecessor.key)
            self:remove_at(left, predecessor.key, trace)
            node.entries[position] = predecessor
        elseif #self.pages[right].entries >= self.degree then
            local first = right
            while not self.pages[first]:leaf() do first = self.pages[first].children[1] end
            local successor = self.pages[first].entries[1]
            trace:record("2b")
            trace:emit("STEP 2b page=%d succ=%d", page, successor.key)
            self:remove_at(right, successor.key, trace)
            node.entries[position] = successor
        else
            trace:record("2c")
            local child = self:merge(page, position, "2c", trace)
            self:remove_at(child, key, trace)
        end
        return
    end
    local child_page = node.children[position]
    local child = self.pages[child_page]
    if #child.entries == self.degree - 1 then
        local left = position > 1 and node.children[position - 1] or nil
        local right = position <= #node.entries and node.children[position + 1] or nil
        if left ~= nil and #self.pages[left].entries >= self.degree then
            local sibling = self.pages[left]
            trace:record("3a-left")
            table.insert(child.entries, 1, node.entries[position - 1])
            node.entries[position - 1] = table.remove(sibling.entries)
            if not sibling:leaf() then table.insert(child.children, 1, table.remove(sibling.children)) end
            self.borrows = self.borrows + 1
            trace:emit("STEP 3a-left page=%d child=%d from=%d keys=%s", page, child_page, left, child)
        elseif right ~= nil and #self.pages[right].entries >= self.degree then
            local sibling = self.pages[right]
            trace:record("3a-right")
            child.entries[#child.entries + 1] = node.entries[position]
            node.entries[position] = table.remove(sibling.entries, 1)
            if not sibling:leaf() then child.children[#child.children + 1] = table.remove(sibling.children, 1) end
            self.borrows = self.borrows + 1
            trace:emit("STEP 3a-right page=%d child=%d from=%d keys=%s", page, child_page, right, child)
        elseif left ~= nil then
            trace:record("3b-left")
            child_page = self:merge(page, position - 1, "3b-left", trace)
        else
            trace:record("3b-right")
            child_page = self:merge(page, position, "3b-right", trace)
        end
    end
    self:remove_at(child_page, key, trace)
end
function Tree:remove(key, trace)
    trace.cases = {}
    self:remove_at(self.root, key, trace)
    return trace.cases
end
function Tree:scan(low, high)
    local result, visited = {}, 0
    local function visit(page)
        visited = visited + 1
        local node = self.pages[page]
        for i = 1, #node.entries + 1 do
            if not node:leaf() and (i == 1 or node.entries[i - 1].key < high)
                and (i == #node.entries + 1 or node.entries[i].key > low) then visit(node.children[i]) end
            if i <= #node.entries and low <= node.entries[i].key and node.entries[i].key <= high then
                result[#result + 1] = node.entries[i]
            end
        end
    end
    visit(self.root)
    return result, visited
end
function Tree:dump()
    local tokens = {}
    local function visit(page)
        local node = self.pages[page]
        tokens[#tokens + 1] = "("
        if not node:leaf() then visit(node.children[1]) end
        for i, entry in ipairs(node.entries) do
            tokens[#tokens + 1] = display(entry)
            if not node:leaf() then visit(node.children[i + 1]) end
        end
        tokens[#tokens + 1] = ")"
    end
    visit(self.root)
    return table.concat(tokens, " ")
end
function Tree:compact()
    local source, children, built = self:entries(), {}, {}
    local old_root
    while true do
        local groups = (#source + 2 * self.degree) // (2 * self.degree)
        local keys = #source - (groups - 1)
        local size, extra = keys // groups, keys % groups
        local entry_index, child_index = 1, 1
        local nodes, separators = {}, {}
        for group = 1, groups do
            local count = size + (group <= extra and 1 or 0)
            nodes[#nodes + 1] = #built + 1
            built[#built + 1] = Node.new(slice(source, entry_index, entry_index + count - 1),
                #children == 0 and {} or slice(children, child_index, child_index + count))
            entry_index, child_index = entry_index + count, child_index + count + 1
            if group < groups then
                separators[#separators + 1] = source[entry_index]
                entry_index = entry_index + 1
            end
        end
        if groups == 1 then old_root = nodes[1]; break end
        source, children = separators, nodes
    end
    local replacement, next_page = {}, 0
    local function renumber(old_page)
        local page = next_page
        next_page = next_page + 1
        local old, kids = built[old_page], {}
        for _, child in ipairs(old.children) do kids[#kids + 1] = renumber(child) end
        replacement[page] = Node.new(slice(old.entries), kids)
        return page
    end
    self.root = renumber(old_root)
    self.pages = replacement
    self.splits, self.merges, self.borrows = 0, 0, 0
end

local needs_valid = {
    INSERT = true, BULKLOAD = true, DELETE = true, DELRANGE = true, RANGE = true, COUNT = true,
    MIN = true, MAX = true, FLOOR = true, CEIL = true, RANK = true, SELECT = true,
    SEEK = true, NEXT = true, PREV = true, HEIGHT = true, COMPACT = true,
}
local function find(entries, predicate, last)
    local result
    for _, entry in ipairs(entries) do
        if predicate(entry) then
            result = entry
            if not last then break end
        end
    end
    return result
end
local function summary(prefix, tree)
    return string.format("%s nodes=%d keys=%d %s", prefix, tree:node_count(), #tree:entries(),
        tree:violation() == nil and "OK" or "DAMAGED")
end

local Workbench = {}
Workbench.__index = Workbench
function Workbench.new() return setmetatable({ cursor = "UNSET", trace = false }, Workbench) end
function Workbench:process(source)
    local words = {}
    for word in source:gmatch("%S+") do words[#words + 1] = word end
    local command = words[1]
    if command == "TRACE" then
        self.trace = words[2] == "ON"
        return { "TRACE " .. words[2] }
    end
    local first = words[2] and tonumber(words[2]) or 0
    local ranged = command == "DELRANGE" or command == "RANGE" or command == "COUNT"
    local second = ranged and tonumber(words[3]) or 0
    if command == "CREATE" or command == "LOAD" then
        if first < 2 or first > 5 then fail("BAD DEGREE %d", first) end
        local tree = command == "CREATE" and Tree.new(first) or Tree.load(first, slice(words, 3))
        self.index, self.cursor = tree, "UNSET"
        return { command == "CREATE" and ("CREATE t=" .. first) or summary("LOAD t=" .. first, tree) }
    end
    local tree = self.index
    if tree == nil then fail("NO INDEX") end
    if needs_valid[command] and tree:violation() ~= nil then fail("DAMAGED") end
    local entries = tree:entries()
    if ranged and first > second then fail("BAD RANGE %d %d", first, second) end
    if command == "SELECT" and (first < 1 or first > #entries) then fail("BAD POSITION %d", first) end
    if (command == "NEXT" or command == "PREV") and self.cursor == "UNSET" then fail("NO CURSOR") end
    if command == "RESTORE" and self.saved == nil then fail("NO SAVE") end
    local output = {}
    local steps = Trace.new(self.trace and (command == "INSERT" or command == "DELETE"))
    if command == "INSERT" then
        local before, splits = tree:copy(), tree.splits
        local old = tree:upsert(first, words[3], steps)
        local writes = tree:changes(before)
        output = steps.lines
        output[#output + 1] = old ~= nil
            and string.format("INSERT %d UPDATED old=%s writes=%d", first, old, writes)
            or string.format("INSERT %d NEW splits=%d height=%d writes=%d", first, tree.splits - splits, tree:height(), writes)
    elseif command == "BULKLOAD" then
        local before, splits = tree:copy(), tree.splits
        local inserted, updated = 0, 0
        for i = 2, #words, 2 do
            if tree:upsert(tonumber(words[i]), words[i + 1], steps) == nil then inserted = inserted + 1
            else updated = updated + 1 end
        end
        local writes = tree:changes(before)
        output[1] = string.format("BULKLOAD pairs=%d new=%d updated=%d splits=%d height=%d writes=%d",
            (#words - 1) // 2, inserted, updated, tree.splits - splits, tree:height(), writes)
    elseif command == "DELETE" then
        local found = tree:search(first)
        if found.page == nil then output[1] = string.format("DELETE %d NOT FOUND", first)
        else
            local value, before = tree.pages[found.page].entries[found.position].value, tree:copy()
            local cases = tree:remove(first, steps)
            local writes, frees = tree:changes(before)
            output = steps.lines
            output[#output + 1] = string.format("DELETE %d REMOVED value=%s cases=%s height=%d writes=%d frees=%d",
                first, value, table.concat(cases, ","), tree:height(), writes, frees)
        end
    elseif command == "DELRANGE" then
        local before, merges, borrows = tree:copy(), tree.merges, tree.borrows
        local removed = 0
        for _, entry in ipairs(entries) do
            if first <= entry.key and entry.key <= second then
                tree:remove(entry.key, steps)
                removed = removed + 1
            end
        end
        local writes, frees = tree:changes(before)
        output[1] = string.format("DELRANGE %d %d removed=%d merges=%d borrows=%d height=%d writes=%d frees=%d",
            first, second, removed, tree.merges - merges, tree.borrows - borrows, tree:height(), writes, frees)
    elseif command == "GET" then
        local found = tree:search(first)
        local result = found.page ~= nil and ("FOUND value=" .. tree.pages[found.page].entries[found.position].value) or "NOT FOUND"
        output[1] = string.format("GET %d %s path=%s", first, result, table.concat(found.path, " -> "))
    elseif command == "RANGE" or command == "COUNT" then
        local rows, visited = tree:scan(first, second)
        local text = string.format("%s %d %d count=%d visited=%d", command, first, second, #rows, visited)
        if command == "RANGE" then for _, entry in ipairs(rows) do text = text .. " " .. display(entry) end end
        output[1] = text
    elseif command == "MIN" or command == "MAX" then
        output[1] = command .. " " .. (#entries == 0 and "EMPTY" or display(entries[command == "MIN" and 1 or #entries]))
    elseif command == "FLOOR" or command == "CEIL" then
        local entry
        if command == "FLOOR" then entry = find(entries, function(value) return value.key <= first end, true)
        else entry = find(entries, function(value) return value.key >= first end) end
        output[1] = string.format("%s %d %s", command, first, entry and display(entry) or "NONE")
    elseif command == "RANK" then
        local rank = 0
        for _, entry in ipairs(entries) do if entry.key < first then rank = rank + 1 end end
        output[1] = string.format("RANK %d %d", first, rank)
    elseif command == "SELECT" then
        output[1] = string.format("SELECT %d %s", first, display(entries[first]))
    elseif command == "SEEK" then
        local entry = find(entries, function(value) return value.key >= first end)
        self.cursor = entry and entry.key or "END"
        output[1] = string.format("SEEK %d %s", first, entry and display(entry) or "END")
    elseif command == "NEXT" or command == "PREV" then
        local entry
        if command == "NEXT" then
            if self.cursor == "BEGIN" then entry = entries[1]
            elseif type(self.cursor) == "number" then entry = find(entries, function(value) return value.key > self.cursor end) end
        else
            if self.cursor == "END" then entry = entries[#entries]
            elseif type(self.cursor) == "number" then entry = find(entries, function(value) return value.key < self.cursor end, true) end
        end
        local marker = command == "NEXT" and "END" or "BEGIN"
        self.cursor = entry and entry.key or marker
        output[1] = command .. " " .. (entry and display(entry) or marker)
    elseif command == "PRINT" then
        local level, depth = { tree.root }, 0
        while #level > 0 do
            local notations, next_level = {}, {}
            for _, page in ipairs(level) do
                notations[#notations + 1] = tostring(tree.pages[page])
                append(next_level, tree.pages[page].children)
            end
            output[#output + 1] = string.format("LEVEL %d %s", depth, table.concat(notations, " "))
            level, depth = next_level, depth + 1
        end
    elseif command == "PAGES" then
        local pages = {}
        for page in pairs(tree.pages) do pages[#pages + 1] = page end
        table.sort(pages)
        for _, page in ipairs(pages) do
            local node = tree.pages[page]
            output[#output + 1] = string.format("PAGE %d %s kids=%s", page, node,
                node:leaf() and "-" or table.concat(node.children, ","))
        end
    elseif command == "DUMP" then output[1] = string.format("DUMP %d %s", tree.degree, tree:dump())
    elseif command == "HEIGHT" then output[1] = "HEIGHT " .. tree:height()
    elseif command == "STATS" then
        local leaves, nodes = 0, tree:node_count()
        for _, node in pairs(tree.pages) do if node:leaf() then leaves = leaves + 1 end end
        local fill = 100 * #entries // ((2 * tree.degree - 1) * nodes)
        output[1] = string.format("STATS t=%d nodes=%d leaves=%d keys=%d fill=%d%% splits=%d merges=%d borrows=%d",
            tree.degree, nodes, leaves, #entries, fill, tree.splits, tree.merges, tree.borrows)
    elseif command == "VERIFY" then
        local problem = tree:violation()
        output[1] = problem and ("VERIFY FAIL " .. problem) or "VERIFY OK"
    elseif command == "REBUILD" then
        tree = Tree.new(tree.degree)
        for _, entry in ipairs(entries) do tree:upsert(entry.key, entry.value, steps) end
        output[1] = string.format("REBUILD entries=%d keys=%d nodes=%d splits=%d height=%d",
            #entries, #tree:entries(), tree:node_count(), tree.splits, tree:height())
    elseif command == "COMPACT" then
        local nodes = tree:node_count()
        tree:compact()
        output[1] = string.format("COMPACT nodes=%d->%d height=%d", nodes, tree:node_count(), tree:height())
    elseif command == "SAVE" then
        self.saved = tree:copy()
        output[1] = summary("SAVE", tree)
    elseif command == "RESTORE" then
        tree = self.saved:copy()
        output[1] = summary("RESTORE", tree)
    end
    self.index = tree
    return output
end

local command_count = tonumber(io.read("l"))
local workbench = Workbench.new()
for _ = 1, command_count do
    local source = io.read("l")
    local success, output = pcall(function() return workbench:process(source) end)
    if success then io.write(table.concat(output, "\n"), "\n")
    else io.write("ERROR ", output.message, "\n") end
end
