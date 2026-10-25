local format, concat = string.format, table.concat
local kinds = { "SEG", "LAZY", "FEN", "RFEN", "SPARSE", "SQRT", "PERSIST" }

local function copy(values)
    local result = {}
    for i, value in ipairs(values) do result[i] = value end
    return result
end
local function zeros(n)
    local result = {}
    for i = 1, n do result[i] = 0 end
    return result
end
local function total(values)
    local sum = 0
    for _, value in ipairs(values) do sum = sum + value end
    return sum
end
local function fail(message) error({ message = message }, 0) end
local function gcd(a, b)
    a, b = math.abs(a), math.abs(b)
    while b ~= 0 do a, b = b, a % b end
    return a
end
local operations = { SUM = function(a, b) return a + b end, MIN = math.min, MAX = math.max, GCD = gcd }
local function isqrt(n)
    local result = 1
    while (result + 1) * (result + 1) <= n do result = result + 1 end
    return result
end
local function log2(n)
    local result = 0
    while (1 << (result + 1)) <= n do result = result + 1 end
    return result
end
local function scalar(value, visited) return { value = value, visited = visited } end
local function scalarText(answer) return format("sum=%d visited=%d", answer.value, answer.visited) end
local function aggregate(sum, minimum, maximum) return { sum = sum, min = minimum, max = maximum } end
local function merge(a, b) return aggregate(a.sum + b.sum, math.min(a.min, b.min), math.max(a.max, b.max)) end
local function aggregateText(value) return format("sum=%d min=%d max=%d", value.sum, value.min, value.max) end
local function lazyText(answer) return format("%s visited=%d pushes=%d", aggregateText(answer.value), answer.visited, answer.pushes) end
local function workText(work) return format("visited=%d covered=%d pushes=%d", work.visited, work.covered, work.pushes) end
local function partitionText(parts) return format("whole=%d cells=%d", #parts.whole, #parts.cells) end
local function sqrtText(answer) return format("sum=%d %s", answer.value, partitionText(answer.parts)) end
local function sparseText(answer)
    return format("min=%d minpos=%d max=%d maxpos=%d level=%d", answer.min, answer.minpos, answer.max, answer.maxpos, answer.level)
end

local function layout(n)
    local shape = { ranges = {}, count = 2 * n - 1, maxNode = 0 }
    local function build(node, left, right)
        shape.ranges[node] = { left = left, right = right, middle = (left + right) // 2, length = right - left + 1 }
        shape.maxNode = math.max(shape.maxNode, node)
        if left < right then
            local middle = (left + right) // 2
            build(2 * node, left, middle)
            build(2 * node + 1, middle + 1, right)
        end
    end
    build(1, 0, n - 1)
    return shape
end
local function covered(range, left, right) return left <= range.left and range.right <= right end

local Segment = {}
Segment.__index = Segment
function Segment.new(contents, operation)
    local self = setmetatable({ shape = layout(#contents), values = {}, operation = operation }, Segment)
    local function build(node)
        local range = self.shape.ranges[node]
        if range.left == range.right then
            local value = contents[range.left + 1]
            self.values[node] = operation == "GCD" and math.abs(value) or value
        else
            build(2 * node)
            build(2 * node + 1)
            self:pull(node)
        end
    end
    build(1)
    return self
end
function Segment:pull(node) self.values[node] = operations[self.operation](self.values[2 * node], self.values[2 * node + 1]) end
function Segment:query(left, right, node)
    node = node or 1
    local range = self.shape.ranges[node]
    if covered(range, left, right) then return scalar(self.values[node], 1) end
    if right <= range.middle or left > range.middle then
        local child = self:query(left, right, right <= range.middle and 2 * node or 2 * node + 1)
        return scalar(child.value, child.visited + 1)
    end
    local a = self:query(left, right, 2 * node)
    local b = self:query(left, right, 2 * node + 1)
    return scalar(operations[self.operation](a.value, b.value), a.visited + b.visited + 1)
end
function Segment:update(index, value, node)
    node = node or 1
    local range = self.shape.ranges[node]
    if range.left == range.right then
        self.values[node] = self.operation == "GCD" and math.abs(value) or value
        return 1
    end
    local visited = self:update(index, value, index <= range.middle and 2 * node or 2 * node + 1)
    self:pull(node)
    return visited + 1
end
function Segment:describe(answer) return format("%s=%d visited=%d", self.operation:lower(), answer.value, answer.visited) end
function Segment:dump()
    local rows = { format("SEG DUMP %s nodes=%d", self.operation, self.shape.count) }
    for node = 1, self.shape.maxNode do
        local range = self.shape.ranges[node]
        if range then rows[#rows + 1] = format("NODE %d %d %d %d", node, range.left, range.right, self.values[node]) end
    end
    return rows
end

local Lazy = {}
Lazy.__index = Lazy
function Lazy.new(contents)
    local self = setmetatable({ shape = layout(#contents), values = {}, assign = {}, add = zeros(4 * #contents) }, Lazy)
    local function build(node)
        local range = self.shape.ranges[node]
        if range.left == range.right then
            local value = contents[range.left + 1]
            self.values[node] = aggregate(value, value, value)
        else
            build(2 * node)
            build(2 * node + 1)
            self:pull(node)
        end
    end
    build(1)
    return self
end
function Lazy:pull(node) self.values[node] = merge(self.values[2 * node], self.values[2 * node + 1]) end
function Lazy:apply(node, value, assignment)
    local range, old = self.shape.ranges[node], self.values[node]
    self.values[node] = assignment and aggregate(value * range.length, value, value)
        or aggregate(old.sum + value * range.length, old.min + value, old.max + value)
    if range.left == range.right then return end
    if assignment then self.assign[node], self.add[node] = value, 0
    else self.add[node] = self.add[node] + value end
end
function Lazy:push(node)
    local assignment, addition = self.assign[node], self.add[node]
    if assignment == nil and addition == 0 then return 0 end
    for child = 2 * node, 2 * node + 1 do
        if assignment ~= nil then self:apply(child, assignment, true) end
        if addition ~= 0 then self:apply(child, addition, false) end
    end
    self.assign[node], self.add[node] = nil, 0
    return 1
end
function Lazy:update(left, right, value, assignment)
    local work = { visited = 0, covered = 0, pushes = 0 }
    local function visit(node)
        work.visited = work.visited + 1
        local range = self.shape.ranges[node]
        if covered(range, left, right) then
            work.covered = work.covered + 1
            self:apply(node, value, assignment)
            return
        end
        work.pushes = work.pushes + self:push(node)
        if left <= range.middle then visit(2 * node) end
        if right > range.middle then visit(2 * node + 1) end
        self:pull(node)
    end
    visit(1)
    return work
end
function Lazy:query(left, right, node)
    node = node or 1
    local range = self.shape.ranges[node]
    if covered(range, left, right) then return { value = self.values[node], visited = 1, pushes = 0 } end
    local pushes = self:push(node)
    if right <= range.middle or left > range.middle then
        local child = self:query(left, right, right <= range.middle and 2 * node or 2 * node + 1)
        return { value = child.value, visited = child.visited + 1, pushes = child.pushes + pushes }
    end
    local a = self:query(left, right, 2 * node)
    local b = self:query(left, right, 2 * node + 1)
    return { value = merge(a.value, b.value), visited = a.visited + b.visited + 1, pushes = a.pushes + b.pushes + pushes }
end
function Lazy:dump()
    local rows = { format("LAZY DUMP nodes=%d", self.shape.count) }
    for node = 1, self.shape.maxNode do
        local range = self.shape.ranges[node]
        if range then
            local assignment = self.assign[node] == nil and "-" or tostring(self.assign[node])
            rows[#rows + 1] = format("NODE %d %d %d %s assign=%s add=%d", node, range.left, range.right, aggregateText(self.values[node]), assignment, self.add[node])
        end
    end
    return rows
end

local Fenwick = {}
Fenwick.__index = Fenwick
function Fenwick.new(n) return setmetatable({ n = n, tree = zeros(n) }, Fenwick) end
function Fenwick:add(position, value)
    local visited = 0
    while position <= self.n do
        self.tree[position] = self.tree[position] + value
        visited = visited + 1
        position = position + (position & -position)
    end
    return visited
end
function Fenwick:prefix(position)
    local sum, visited = 0, 0
    while position > 0 do
        sum, visited = sum + self.tree[position], visited + 1
        position = position - (position & -position)
    end
    return scalar(sum, visited)
end

local PointFenwick = {}
PointFenwick.__index = PointFenwick
function PointFenwick.new(contents)
    local self = setmetatable({ contents = copy(contents), bits = Fenwick.new(#contents) }, PointFenwick)
    for i, value in ipairs(contents) do self.bits:add(i, value) end
    return self
end
function PointFenwick:add(index, value)
    self.contents[index + 1] = self.contents[index + 1] + value
    return self.bits:add(index + 1, value)
end
function PointFenwick:query(left, right)
    local a = self.bits:prefix(right + 1)
    local b = self.bits:prefix(left)
    return scalar(a.value - b.value, a.visited + b.visited)
end
function PointFenwick:lower(rest)
    local position, visited, step = 0, 0, 1 << log2(#self.contents)
    while step >= 1 do
        if position + step <= #self.contents then
            visited = visited + 1
            local value = self.bits.tree[position + step]
            if value < rest then rest, position = rest - value, position + step end
        end
        step = step // 2
    end
    return position == #self.contents and "none" or tostring(position), visited
end
function PointFenwick:dump() return { format("FEN DUMP n=%d", #self.contents), "T " .. concat(self.bits.tree, " ") } end

local RangeFenwick = {}
RangeFenwick.__index = RangeFenwick
function RangeFenwick.new(contents)
    local self = setmetatable({ b1 = Fenwick.new(#contents), b2 = Fenwick.new(#contents) }, RangeFenwick)
    for i, value in ipairs(contents) do
        local difference = value - (i == 1 and 0 or contents[i - 1])
        self.b1:add(i, difference)
        self.b2:add(i, (i - 1) * difference)
    end
    return self
end
function RangeFenwick:add(left, right, value)
    local visited = self.b1:add(left + 1, value)
    visited = visited + self.b1:add(right + 2, -value)
    visited = visited + self.b2:add(left + 1, value * left)
    visited = visited + self.b2:add(right + 2, -value * (right + 1))
    return visited
end
function RangeFenwick:prefix(position)
    local a = self.b1:prefix(position)
    local b = self.b2:prefix(position)
    return scalar(position * a.value - b.value, a.visited + b.visited)
end
function RangeFenwick:query(left, right)
    local a = self:prefix(right + 1)
    local b = self:prefix(left)
    return scalar(a.value - b.value, a.visited + b.visited)
end
function RangeFenwick:dump() return { format("RFEN DUMP n=%d", self.b1.n), "B1 " .. concat(self.b1.tree, " "), "B2 " .. concat(self.b2.tree, " ") } end

local Sparse = {}
Sparse.__index = Sparse
function Sparse:choose(a, b, minimum)
    if minimum then return self.contents[b + 1] < self.contents[a + 1] and b or a end
    return self.contents[b + 1] > self.contents[a + 1] and b or a
end
function Sparse.new(contents)
    local initial = {}
    for i = 1, #contents do initial[i] = i - 1 end
    local self = setmetatable({ contents = copy(contents), minimum = { initial }, maximum = { copy(initial) }, entries = #contents }, Sparse)
    local width = 2
    while width <= #contents do
        local previous = #self.minimum
        local small, large = {}, {}
        for i = 1, #contents - width + 1 do
            small[i] = self:choose(self.minimum[previous][i], self.minimum[previous][i + width // 2], true)
            large[i] = self:choose(self.maximum[previous][i], self.maximum[previous][i + width // 2], false)
        end
        self.minimum[previous + 1], self.maximum[previous + 1] = small, large
        self.entries = self.entries + #small
        width = width * 2
    end
    return self
end
function Sparse:query(left, right)
    local level = log2(right - left + 1)
    local last = right + 1 - (1 << level)
    local small = self:choose(self.minimum[level + 1][left + 1], self.minimum[level + 1][last + 1], true)
    local large = self:choose(self.maximum[level + 1][left + 1], self.maximum[level + 1][last + 1], false)
    return { min = self.contents[small + 1], minpos = small, max = self.contents[large + 1], maxpos = large, level = level }
end
function Sparse:dump()
    local rows = { format("SPARSE DUMP levels=%d", #self.minimum) }
    for level = 1, #self.minimum do
        rows[#rows + 1] = format("MIN %d %s", level - 1, concat(self.minimum[level], " "))
        rows[#rows + 1] = format("MAX %d %s", level - 1, concat(self.maximum[level], " "))
    end
    return rows
end

local SqrtBlocks = {}
SqrtBlocks.__index = SqrtBlocks
function SqrtBlocks.new(contents, block)
    local count = (#contents + block - 1) // block
    local self = setmetatable({ raw = copy(contents), block = block, tags = zeros(count), sums = zeros(count) }, SqrtBlocks)
    for i, value in ipairs(contents) do
        local group = (i - 1) // block + 1
        self.sums[group] = self.sums[group] + value
    end
    return self
end
function SqrtBlocks:split(left, right)
    local first, last = left // self.block, right // self.block
    local parts = { cells = {}, whole = {} }
    if first == last then
        for i = left, right do parts.cells[#parts.cells + 1] = i end
    else
        for i = left, (first + 1) * self.block - 1 do parts.cells[#parts.cells + 1] = i end
        for i = last * self.block, right do parts.cells[#parts.cells + 1] = i end
        for group = first + 1, last - 1 do parts.whole[#parts.whole + 1] = group end
    end
    return parts
end
function SqrtBlocks:add(left, right, value)
    local parts = self:split(left, right)
    for _, i in ipairs(parts.cells) do
        local group = i // self.block + 1
        self.raw[i + 1] = self.raw[i + 1] + value
        self.sums[group] = self.sums[group] + value
    end
    for _, group in ipairs(parts.whole) do
        self.tags[group + 1] = self.tags[group + 1] + value
        self.sums[group + 1] = self.sums[group + 1] + value * self.block
    end
    return parts
end
function SqrtBlocks:query(left, right)
    local parts, sum = self:split(left, right), 0
    for _, i in ipairs(parts.cells) do sum = sum + (self.raw[i + 1] + self.tags[i // self.block + 1]) end
    for _, group in ipairs(parts.whole) do sum = sum + self.sums[group + 1] end
    return { value = sum, parts = parts }
end
function SqrtBlocks:dump()
    local rows = { format("SQRT DUMP block=%d blocks=%d", self.block, #self.tags) }
    for group = 1, #self.tags do
        local first, last = (group - 1) * self.block, math.min(#self.raw, group * self.block) - 1
        rows[#rows + 1] = format("BLOCK %d %d %d add=%d sum=%d %s", group - 1, first, last, self.tags[group], self.sums[group], concat(self.raw, " ", first + 1, last + 1))
    end
    return rows
end

local function node(value, left, right) return { value = value, left = left, right = right } end
local function buildNodes(contents, left, right)
    if left == right then return node(contents[left + 1]) end
    local middle = (left + right) // 2
    local a = buildNodes(contents, left, middle)
    local b = buildNodes(contents, middle + 1, right)
    return node(a.value + b.value, a, b)
end
local function changeNode(source, left, right, index, value, increment)
    if left == right then return node(increment and source.value + value or value), 1 end
    local middle = (left + right) // 2
    local a, b, created = source.left, source.right, 0
    if index <= middle then a, created = changeNode(a, left, middle, index, value, increment)
    else b, created = changeNode(b, middle + 1, right, index, value, increment) end
    return node(a.value + b.value, a, b), created + 1
end
local function queryNode(root, start, last, left, right)
    if left <= start and last <= right then return scalar(root.value, 1) end
    local middle = (start + last) // 2
    if right <= middle or left > middle then
        local answer
        if right <= middle then answer = queryNode(root.left, start, middle, left, right)
        else answer = queryNode(root.right, middle + 1, last, left, right) end
        return scalar(answer.value, answer.visited + 1)
    end
    local a = queryNode(root.left, start, middle, left, right)
    local b = queryNode(root.right, middle + 1, last, left, right)
    return scalar(a.value + b.value, a.visited + b.visited + 1)
end
local Persistent = {}
Persistent.__index = Persistent
function Persistent.new(contents)
    local sorted, values, ranks = copy(contents), {}, {}
    table.sort(sorted)
    for _, value in ipairs(sorted) do
        if #values == 0 or values[#values] ~= value then values[#values + 1] = value; ranks[value] = #values - 1 end
    end
    local self = setmetatable({ n = #contents, values = values, versions = { buildNodes(contents, 0, #contents - 1) },
        positionNodes = 2 * #contents - 1, valueRoots = { buildNodes(zeros(#values), 0, #values - 1) }, valueNodes = 2 * #values - 1 }, Persistent)
    for i, value in ipairs(contents) do
        local root, created = changeNode(self.valueRoots[i], 0, #values - 1, ranks[value], 1, true)
        self.valueRoots[i + 1] = root
        self.valueNodes = self.valueNodes + created
    end
    return self
end
function Persistent:setValue(version, index, value)
    local root, created = changeNode(self.versions[version + 1], 0, self.n - 1, index, value, false)
    self.versions[#self.versions + 1] = root
    self.positionNodes = self.positionNodes + created
    return created
end
function Persistent:query(version, left, right) return queryNode(self.versions[version + 1], 0, self.n - 1, left, right) end
function Persistent:kth(left, right, k)
    local u, w = self.valueRoots[right + 2], self.valueRoots[left + 1]
    local first, last, visited = 0, #self.values - 1, 1
    while first < last do
        local middle = (first + last) // 2
        local difference = u.left.value - w.left.value
        if k <= difference then u, w, last = u.left, w.left, middle
        else k, u, w, first = k - difference, u.right, w.right, middle + 1 end
        visited = visited + 1
    end
    return scalar(self.values[first + 1], visited)
end

local Grid = {}
Grid.__index = Grid
function Grid.new(height, width, contents)
    local self = setmetatable({ height = height, width = width, tree = {} }, Grid)
    for row = 1, height do self.tree[row] = zeros(width) end
    for index, value in ipairs(contents) do self:add((index - 1) // width, (index - 1) % width, value) end
    return self
end
function Grid:add(row, column, value)
    local visited, y = 0, row + 1
    while y <= self.height do
        local z = column + 1
        while z <= self.width do
            self.tree[y][z] = self.tree[y][z] + value
            visited = visited + 1
            z = z + (z & -z)
        end
        y = y + (y & -y)
    end
    return visited
end
function Grid:prefix(row, column)
    local sum, visited = 0, 0
    while row > 0 do
        local z = column
        while z > 0 do
            sum, visited = sum + self.tree[row][z], visited + 1
            z = z - (z & -z)
        end
        row = row - (row & -row)
    end
    return scalar(sum, visited)
end
function Grid:query(top, left, bottom, right)
    local a = self:prefix(bottom + 1, right + 1)
    local b = self:prefix(top, right + 1)
    local c = self:prefix(bottom + 1, left)
    local d = self:prefix(top, left)
    return scalar(a.value - b.value - c.value + d.value, a.visited + b.visited + c.visited + d.visited)
end
function Grid:dump()
    local rows = { format("GRID DUMP rows=%d cols=%d", self.height, self.width) }
    for row = 1, self.height do rows[#rows + 1] = format("ROW %d %s", row, concat(self.tree[row], " ")) end
    return rows
end

local Laboratory = {}
Laboratory.__index = Laboratory
function Laboratory.new(contents) return setmetatable({ a = copy(contents), original = copy(contents), structures = {} }, Laboratory) end
function Laboratory:index(index)
    if index < 0 or index >= #self.a then fail(format("BAD INDEX %d", index)) end
end
function Laboratory:range(left, right)
    self:index(left)
    self:index(right)
    if left > right then fail(format("BAD RANGE %d %d", left, right)) end
end
function Laboratory:cell(row, column)
    if row < 0 or row >= self.grid.height or column < 0 or column >= self.grid.width then fail(format("BAD CELL %d %d", row, column)) end
end
function Laboratory:version(version)
    if version < 0 or version >= #self.structures.PERSIST.versions then fail(format("BAD VERSION %d", version)) end
end
function Laboratory:arrayCount()
    local result = 0
    for _, kind in ipairs(kinds) do if self.structures[kind] then result = result + 1 end end
    return result
end
function Laboratory:buildArray(kind, parameter)
    local tree, text
    if kind == "SEG" then
        tree = Segment.new(self.a, parameter)
        text = format("SEG BUILD %s nodes=%d maxnode=%d root=%d", parameter, tree.shape.count, tree.shape.maxNode, tree.values[1])
    elseif kind == "LAZY" then
        tree = Lazy.new(self.a)
        text = format("LAZY BUILD nodes=%d %s", tree.shape.count, aggregateText(tree.values[1]))
    elseif kind == "FEN" then
        tree = PointFenwick.new(self.a)
        text = format("FEN BUILD n=%d total=%d", #self.a, total(self.a))
    elseif kind == "RFEN" then
        tree = RangeFenwick.new(self.a)
        text = format("RFEN BUILD n=%d total=%d", #self.a, total(self.a))
    elseif kind == "SPARSE" then
        tree = Sparse.new(self.a)
        text = format("SPARSE BUILD levels=%d entries=%d", #tree.minimum, tree.entries)
    elseif kind == "SQRT" then
        tree = SqrtBlocks.new(self.a, parameter)
        text = format("SQRT BUILD block=%d blocks=%d", parameter, #tree.tags)
    else
        tree = Persistent.new(self.a)
        text = format("PERSIST BUILD nodes=%d distinct=%d valuenodes=%d", tree.positionNodes, #tree.values, tree.valueNodes)
    end
    self.structures[kind] = tree
    return text
end
function Laboratory:reset()
    self.a = copy(self.original)
    local rebuilt = 0
    for _, kind in ipairs(kinds) do
        local tree = self.structures[kind]
        if tree then
            self:buildArray(kind, kind == "SEG" and tree.operation or kind == "SQRT" and tree.block or nil)
            rebuilt = rebuilt + 1
        end
    end
    return { format("RESET rebuilt=%d", rebuilt) }
end
function Laboratory:check(left, right)
    self:range(left, right)
    local sum, minimum, maximum, common = 0, self.a[left + 1], self.a[left + 1], 0
    for i = left + 1, right + 1 do
        sum, minimum, maximum, common = sum + self.a[i], math.min(minimum, self.a[i]), math.max(maximum, self.a[i]), gcd(common, self.a[i])
    end
    local rows = { format("CHECK %d %d sum=%d min=%d max=%d gcd=%d", left, right, sum, minimum, maximum, common) }
    local ok, different = 0, 0
    local function append(kind, same, items)
        if same then ok = ok + 1 else different = different + 1 end
        rows[#rows + 1] = kind .. (same and " OK " or " DIFF ") .. items
    end
    for _, kind in ipairs(kinds) do
        local tree = self.structures[kind]
        if tree then
            if kind == "PERSIST" then
                local version = #tree.versions - 1
                local answer = tree:query(version, left, right)
                append(kind, answer.value == sum, format("version=%d %s", version, scalarText(answer)))
            else
                local answer = tree:query(left, right)
                if kind == "SEG" then
                    local expected = ({ SUM = sum, MIN = minimum, MAX = maximum, GCD = common })[tree.operation]
                    append(kind, answer.value == expected, tree:describe(answer))
                elseif kind == "LAZY" then
                    append(kind, answer.value.sum == sum and answer.value.min == minimum and answer.value.max == maximum, lazyText(answer))
                elseif kind == "SPARSE" then
                    append(kind, answer.min == minimum and answer.max == maximum, sparseText(answer))
                elseif kind == "SQRT" then append(kind, answer.value == sum, sqrtText(answer))
                else append(kind, answer.value == sum, scalarText(answer)) end
            end
        end
    end
    rows[#rows + 1] = format("RESULT ok=%d diff=%d", ok, different)
    return rows
end
function Laboratory:mo(words)
    local queries = {}
    for i = 2, #words, 2 do
        local left, right = tonumber(words[i]), tonumber(words[i + 1])
        self:range(left, right)
        queries[#queries + 1] = { left = left, right = right, number = #queries + 1 }
    end
    local block, ordered = isqrt(#self.a), copy(queries)
    table.sort(ordered, function(a, b)
        local first, second = a.left // block, b.left // block
        if first ~= second then return first < second end
        if a.right ~= b.right then
            if first % 2 == 0 then return a.right < b.right end
            return a.right > b.right
        end
        return a.number < b.number
    end)
    local frequency, answers, order = {}, {}, {}
    local distinct, moves, left, right = 0, 0, 0, -1
    local function add(index)
        local value = self.a[index + 1]
        local old = frequency[value] or 0
        if old == 0 then distinct = distinct + 1 end
        frequency[value], moves = old + 1, moves + 1
    end
    local function remove(index)
        local value = self.a[index + 1]
        frequency[value], moves = frequency[value] - 1, moves + 1
        if frequency[value] == 0 then distinct = distinct - 1 end
    end
    for _, query in ipairs(ordered) do
        while left > query.left do left = left - 1; add(left) end
        while right < query.right do right = right + 1; add(right) end
        while left < query.left do remove(left); left = left + 1 end
        while right > query.right do remove(right); right = right - 1 end
        answers[query.number] = distinct
        order[#order + 1] = query.number
    end
    local rows = { format("MO queries=%d block=%d moves=%d", #queries, block, moves), "ORDER " .. concat(order, " ") }
    for _, query in ipairs(queries) do rows[#rows + 1] = format("ANSWER %d %d %d distinct=%d", query.number, query.left, query.right, answers[query.number]) end
    return rows
end
local function numericTail(words, start)
    local values = {}
    for i = start, #words do values[#values + 1] = tonumber(words[i]) end
    return values
end
function Laboratory:execute(words, line)
    local kind = words[1]
    if kind == "LOAD" then
        local removed = self:arrayCount()
        self.a = numericTail(words, 2)
        self.original, self.structures = copy(self.a), {}
        return { format("LOAD n=%d removed=%d", #self.a, removed) }
    end
    if kind == "RESET" then return self:reset() end
    if kind == "MO" then return self:mo(words) end
    if kind == "CHECK" then return self:check(tonumber(words[2]), tonumber(words[3])) end
    if kind == "ARRAY" then
        local left, right = tonumber(words[2]), tonumber(words[3])
        self:range(left, right)
        return { line .. " " .. concat(self.a, " ", left + 1, right + 1) }
    end
    local action = words[2]
    if action == "BUILD" then
        local parameter
        if kind == "SEG" then
            parameter = words[3]
            if not operations[parameter] then fail("BAD OP " .. parameter) end
        elseif kind == "SQRT" then
            parameter = words[3] and tonumber(words[3]) or isqrt(#self.a)
            if parameter > #self.a then fail(format("BAD BLOCK %d", parameter)) end
        elseif kind == "GRID" then
            local height, width = tonumber(words[3]), tonumber(words[4])
            local values = numericTail(words, 5)
            if #values ~= height * width then fail(format("BAD COUNT %d %d", #values, height * width)) end
            self.grid = Grid.new(height, width, values)
            return { format("GRID BUILD rows=%d cols=%d total=%d", height, width, total(values)) }
        end
        return { self:buildArray(kind, parameter) }
    end
    local tree = kind == "GRID" and self.grid or self.structures[kind]
    if not tree then fail("NOT BUILT " .. kind) end
    if action == "DUMP" then return tree:dump() end
    local args = numericTail(words, 3)
    if kind == "PERSIST" then
        if action == "NODES" then return { format("PERSIST NODES versions=%d position=%d value=%d", #tree.versions, tree.positionNodes, tree.valueNodes) } end
        if action == "KTH" then
            local left, right, k = args[1], args[2], args[3]
            self:range(left, right)
            if k < 1 or k > right - left + 1 then fail(format("BAD K %d", k)) end
            local answer = tree:kth(left, right, k)
            return { format("%s value=%d visited=%d", line, answer.value, answer.visited) }
        end
        local version = args[1]
        self:version(version)
        if action == "SET" then
            self:index(args[2])
            local newVersion = #tree.versions
            local created = tree:setValue(version, args[2], args[3])
            return { format("%s version=%d created=%d", line, newVersion, created) }
        end
        self:range(args[2], args[3])
        return { line .. " " .. scalarText(tree:query(version, args[2], args[3])) }
    end
    if kind == "GRID" then
        local row, column = args[1], args[2]
        self:cell(row, column)
        if action == "ADD" then return { format("%s visited=%d", line, tree:add(row, column, args[3])) } end
        self:cell(args[3], args[4])
        if row > args[3] or column > args[4] then fail("BAD RECT " .. concat(args, " ")) end
        return { line .. " " .. scalarText(tree:query(row, column, args[3], args[4])) }
    end
    if kind == "FEN" and action == "LOWER" then
        for i, value in ipairs(tree.contents) do if value < 0 then fail(format("NEGATIVE %d", i - 1)) end end
        local index, visited = tree:lower(args[1])
        return { format("%s index=%s visited=%d", line, index, visited) }
    end
    local left = args[1]
    if kind == "SEG" and action == "UPDATE" then
        self:index(left)
        local visited = tree:update(left, args[2])
        self.a[left + 1] = args[2]
        return { format("%s root=%d visited=%d", line, tree.values[1], visited) }
    end
    if kind == "FEN" and (action == "ADD" or action == "PREFIX") then
        self:index(left)
        if action == "PREFIX" then return { line .. " " .. scalarText(tree.bits:prefix(left + 1)) } end
        local visited = tree:add(left, args[2])
        self.a[left + 1] = self.a[left + 1] + args[2]
        return { format("%s visited=%d", line, visited) }
    end
    local right = args[2]
    self:range(left, right)
    if action == "ADD" or action == "ASSIGN" then
        local value, assignment, items = args[3], action == "ASSIGN"
        if kind == "LAZY" then items = workText(tree:update(left, right, value, assignment))
        elseif kind == "RFEN" then items = format("visited=%d", tree:add(left, right, value))
        else items = partitionText(tree:add(left, right, value)) end
        for i = left + 1, right + 1 do self.a[i] = assignment and value or self.a[i] + value end
        return { line .. " " .. items }
    end
    local answer, items = tree:query(left, right)
    if kind == "SEG" then items = tree:describe(answer)
    elseif kind == "LAZY" then items = lazyText(answer)
    elseif kind == "SPARSE" then items = sparseText(answer)
    elseif kind == "SQRT" then items = sqrtText(answer)
    else items = scalarText(answer) end
    return { line .. " " .. items }
end

local function wordsOf(line)
    local words = {}
    for word in line:gmatch("%S+") do words[#words + 1] = word end
    return words
end
local first = io.read("*l")
if not first then return end
local laboratory = Laboratory.new(numericTail(wordsOf(io.read("*l")), 1))
local commands = tonumber(io.read("*l"))
for _ = 1, commands do
    local words = wordsOf(io.read("*l"))
    local ok, rows = pcall(function() return laboratory:execute(words, concat(words, " ")) end)
    if ok then io.write(concat(rows, "\n"), "\n")
    elseif type(rows) == "table" and rows.message then io.write("ERROR ", rows.message, "\n")
    else error(rows, 0) end
    io.flush()
end
