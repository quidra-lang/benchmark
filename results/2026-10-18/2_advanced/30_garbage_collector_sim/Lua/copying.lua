local heap = require("heap")
local M = {}
function M.collect(state, roots, line, request)
    local record = heap.record(state, line, request, "copy")
    state.base = state.half - state.base
    state.top = state.base
    local copied, queue = {}, {}
    local function copy(number)
        if number == 0 or copied[number] then
            return
        end
        copied[number] = true
        local object = state.objects[number]
        object.address, object.moves = state.top, object.moves + 1
        state.top = state.top + object.size
        heap.add(record.live, object)
        heap.add(record.moved, object)
        queue[#queue + 1] = number
    end
    record.work = record.work + #roots
    for _, root in ipairs(roots) do
        copy(root)
    end
    local index = 1
    while index <= #queue do
        local object = state.objects[queue[index]]
        index = index + 1
        record.work = record.work + object.size + #object.fields
        for _, child in ipairs(object.fields) do
            copy(child)
        end
    end
    for _, object in ipairs(heap.active(state)) do
        if not copied[object.number] then
            object.present = false
            heap.add(record.freed, object)
        end
    end
    heap.finish(state, record)
end
return M
