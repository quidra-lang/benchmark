local Layout = require("layout")
local Signals = {}

function Signals.aspects(interlocking, occupied)
    local layout, cleared = interlocking.layout, {}
    for _, signal in ipairs(layout.signal_order) do
        for _, route in ipairs(interlocking.order) do
            if route.start == signal.name and route.state == "LOCKED" then
                local valid = true
                for _, item in ipairs(route.requirements) do
                    local point = layout.points[item[1]]
                    if not Layout.detected(point) or point.position ~= item[2] then valid = false end
                end
                for _, name in ipairs(route.sections) do if occupied(name) then valid = false end end
                for _, name in ipairs(route.overlap) do if occupied(name) then valid = false end end
                if valid then cleared[signal.name] = route; break end
            end
        end
    end
    local result = {}
    for _, signal in ipairs(layout.signal_order) do
        local route, aspect = cleared[signal.name], "RED"
        if route then
            if layout.signals[route.finish] then
                aspect = cleared[route.finish] and "GREEN" or "YELLOW"
            elseif layout.buffers[route.finish] then
                aspect = "YELLOW"
            else
                aspect = "GREEN"
            end
        end
        result[#result + 1] = {signal, aspect}
    end
    return result
end

return Signals
