local function before(a,b) return a.priority < b.priority or (a.priority == b.priority and a.sequence < b.sequence) end
local heap = {}
local function push(task)
    heap[#heap+1] = task
    local child = #heap
    while child > 1 do
        local parent = child//2
        if not before(heap[child],heap[parent]) then break end
        heap[child],heap[parent] = heap[parent],heap[child]
        child = parent
    end
end
local function pop()
    local task = heap[1]
    local last = table.remove(heap)
    if #heap > 0 then
        heap[1] = last
        local parent = 1
        while 2*parent <= #heap do
            local child = 2*parent
            if child < #heap and before(heap[child+1],heap[child]) then child = child+1 end
            if not before(heap[child],heap[parent]) then break end
            heap[child],heap[parent] = heap[parent],heap[child]
            parent = child
        end
    end
    return task
end
local operations = {"add email 3","add backup 5","add deploy 1","run","add report 3","add test 2","add lint 3","run","run","add cleanup 5","add review 2","run","add build 1","add docs 4","run","run"}
for sequence,operation in ipairs(operations) do
    local parts = {}
    for part in operation:gmatch("%S+") do parts[#parts+1] = part end
    if parts[1] == "add" then push({name=parts[2],priority=tonumber(parts[3]),sequence=sequence})
    else
        local task = pop()
        io.write(string.format("run: %s (priority %d)\n",task.name,task.priority))
    end
end
local remaining = {}
while #heap > 0 do remaining[#remaining+1] = pop().name end
io.write("remaining: ",table.concat(remaining," "),"\n")
