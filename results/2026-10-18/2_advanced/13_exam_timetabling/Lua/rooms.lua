local enrolment = require("enrolment")
local M = {}

function M.load_rooms(path, errors)
    local accepted, rooms = {}, {}
    for _, record in ipairs(enrolment.read_records(path)) do
        local number, fields = record[1], record[2]
        local id, capacity = fields[1], tonumber(fields[2])
        if accepted[id] then
            errors[#errors + 1] = string.format("rooms.csv line %d: duplicate room %s", number, id)
        elseif capacity < 1 then
            errors[#errors + 1] = string.format("rooms.csv line %d: bad capacity %s", number, fields[2])
        else
            accepted[id] = true
            rooms[#rooms + 1] = {id = id, capacity = capacity}
        end
    end
    table.sort(rooms, function(a, b)
        if a.capacity ~= b.capacity then return a.capacity < b.capacity end
        return a.id < b.id
    end)
    return rooms
end

function M.packing_order(courses)
    local result = {}
    for _, course in ipairs(courses) do result[#result + 1] = course end
    table.sort(result, function(a, b)
        if a:size() ~= b:size() then return a:size() > b:size() end
        return a.id < b.id
    end)
    return result
end

function M.pack(rooms, courses)
    local remaining, durations, placements = {}, {}, {}
    for index, room in ipairs(rooms) do remaining[index] = room.capacity end
    for _, course in ipairs(M.packing_order(courses)) do
        local found = false
        for index, room in ipairs(rooms) do
            if remaining[index] >= course:size() and (not durations[index] or durations[index] == course.duration) then
                local first = room.capacity - remaining[index] + 1
                placements[#placements + 1] = {course = course, room = room,
                    first_seat = first, last_seat = first + course:size() - 1}
                remaining[index] = remaining[index] - course:size()
                durations[index] = course.duration
                found = true
                break
            end
        end
        if not found then return nil end
    end
    return placements
end

return M
