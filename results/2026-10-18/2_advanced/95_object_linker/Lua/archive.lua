local O = require("object_parser")
local A = {}
function A.read(name)
    local lines, members, index = O.lines("input/" .. name), {}, 1
    while index <= #lines do
        local words = O.words(lines[index])
        local object
        object, index = O.parse(lines, index + 1, name .. "(" .. words[2] .. ")")
        local exports = {}
        for i = 3, #words do exports[#exports + 1] = words[i] end
        members[#members + 1] = { object = object, exports = exports, loaded = false }
    end
    return members
end
function A.scan(members, is_undefined, extract)
    local count = 0
    while true do
        local changed = false
        for _, member in ipairs(members) do
            if not member.loaded then
                local reason
                for _, name in ipairs(member.exports) do if is_undefined(name) then reason = name; break end end
                if reason then
                    member.loaded = true
                    extract(member.object, reason)
                    count, changed = count + 1, true
                end
            end
        end
        if not changed then return count end
    end
end
return A
