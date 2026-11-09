local heap = require("heap")
local M = {}
function M.mark(state, roots, record)
    for _, object in ipairs(heap.active(state)) do
        object.marked = false
    end
    record.work = record.work + #roots
    local stack = {}
    local function push(number)
        state.objects[number].marked = true
        stack[#stack + 1] = number
        record.stack = math.max(record.stack, #stack)
    end
    for _, root in ipairs(roots) do
        if root ~= 0 and not state.objects[root].marked then
            push(root)
            while #stack > 0 do
                local object = state.objects[table.remove(stack)]
                heap.add(record.live, object)
                record.work = record.work + 1 + #object.fields
                for _, child in ipairs(object.fields) do
                    if child ~= 0 and not state.objects[child].marked then
                        push(child)
                    end
                end
            end
        end
    end
end
function M.sweep(state, record)
    local objects = heap.active(state)
    record.work = record.work + #objects
    for _, object in ipairs(objects) do
        if not object.marked then
            object.present = false
            heap.add(record.freed, object)
        end
    end
end
function M.collect(state, roots, line, request)
    local compact = state.algorithm == "MARK_COMPACT"
    local record = heap.record(state, line, request, compact and "compact" or "sweep")
    M.mark(state, roots, record)
    if not compact then
        M.sweep(state, record)
    else
        local objects, destination = heap.by_address(heap.active(state)), 0
        record.work = record.work + #objects + #roots
        for _, object in ipairs(objects) do
            if not object.marked then
                object.present = false
                heap.add(record.freed, object)
            else
                record.work = record.work + #object.fields
                if object.address ~= destination then
                    heap.add(record.moved, object)
                    record.work, object.address, object.moves = record.work + object.size, destination, object.moves + 1
                end
                destination = destination + object.size
            end
        end
        state.top = destination
    end
    heap.finish(state, record)
end
return M
