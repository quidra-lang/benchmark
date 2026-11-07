local heap, marking = require("heap"), require("mark_sweep")
local M = {}
function M.old_blocks(state)
    return heap.free_blocks(heap.active(state), state.young, state.size)
end
function M.write_barrier(state, target, value)
    local object = state.objects[target]
    if object.address < state.young then
        return
    end
    state.barriers = state.barriers + 1
    if value ~= 0 and state.objects[value].address < state.young and not state.remembered[target] then
        state.remembered[target], state.remembers = true, state.remembers + 1
    end
end
function M.collect(state, roots, line, request, kind)
    local record = heap.record(state, line, request, kind)
    local major, tenure = kind == "major" or kind == "full", kind == "tenure" or kind == "full"
    if major then
        marking.mark(state, roots, record)
        for _, object in ipairs(heap.active(state)) do
            if object.address >= state.young then
                record.work = record.work + 1
                if not object.marked then
                    object.present, state.remembered[object.number] = false, nil
                    heap.add(record.freed, object)
                end
            end
        end
    end
    local pending, queue = {}, {}
    for _, object in ipairs(heap.active(state)) do
        if object.address < state.young then
            pending[object.number] = true
        end
    end
    local destination, target = state.half - state.base, state.half - state.base
    local function evacuate(number)
        if number == 0 or not pending[number] then
            return true
        end
        pending[number] = nil
        local object = state.objects[number]
        object.age, object.moves = object.age + 1, object.moves + 1
        if tenure or object.age >= state.promotion_age then
            local address = heap.first_fit(M.old_blocks(state), object.size)
            if not address then
                return false
            end
            object.address = address
            heap.add(record.promoted, object)
        else
            object.address, target = target, target + object.size
        end
        heap.add(record.moved, object)
        if not major then
            heap.add(record.live, object)
        end
        queue[#queue + 1] = number
        return true
    end
    local function evacuate_fields(object)
        for _, child in ipairs(object.fields) do
            if not evacuate(child) then
                return false
            end
        end
        return true
    end
    record.work = record.work + #roots
    for _, root in ipairs(roots) do
        if not evacuate(root) then
            return false
        end
    end
    local remembered = {}
    for number in pairs(state.remembered) do
        remembered[#remembered + 1] = state.objects[number]
    end
    for _, object in ipairs(heap.by_address(remembered)) do
        record.work = record.work + 1 + #object.fields
        if not evacuate_fields(object) then
            return false
        end
    end
    local index = 1
    while index <= #queue do
        local object = state.objects[queue[index]]
        index = index + 1
        record.work = record.work + object.size + #object.fields
        if not evacuate_fields(object) then
            return false
        end
    end
    for number in pairs(pending) do
        local object = state.objects[number]
        object.present = false
        heap.add(record.freed, object)
    end
    state.base, state.top, state.remembered = destination, target, {}
    for _, object in ipairs(heap.active(state)) do
        if object.address >= state.young then
            for _, child in ipairs(object.fields) do
                if child ~= 0 and state.objects[child].address < state.young then
                    state.remembered[object.number] = true
                    break
                end
            end
        end
    end
    heap.finish(state, record)
    return true
end
function M.allocate(state, roots, object, line)
    for attempt = 0, 2 do
        if state.top + object.size <= state.base + state.half then
            object.address, state.top = state.top, state.top + object.size
            state.objects[#state.objects + 1] = object
            return true
        end
        if attempt == 2 then
            return false
        end
        local scarce = heap.largest_free(M.old_blocks(state)) < state.top - state.base
        local kind = attempt == 0 and (scarce and "major" or "minor") or (scarce and "full" or "tenure")
        if not M.collect(state, roots, line, object.size, kind) then
            return false
        end
    end
end
return M
