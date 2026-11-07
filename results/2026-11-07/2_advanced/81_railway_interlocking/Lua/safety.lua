local Safety = {}
Safety.__index = Safety
local properties = {"OCCUPANCY", "POINT_MOTION", "CONFLICT", "SIGNAL_PASSING"}

function Safety.new()
    return setmetatable({checks = {}, violations = {}, records = {}}, Safety)
end

function Safety:check(time, kind, details)
    self.checks[kind] = (self.checks[kind] or 0) + 1
    if details then
        self.violations[kind] = (self.violations[kind] or 0) + 1
        self.records[#self.records + 1] = string.format("VIOLATION %d %s %s", time, kind, details)
    end
end

local function conflict(first, second)
    for _, name in ipairs(first.conflicts) do if name == second.name then return true end end
    for _, name in ipairs(second.conflicts) do if name == first.name then return true end end
    return false
end

function Safety:inspect(time, layout, interlocking)
    for _, section in ipairs(layout.section_order) do
        local details
        if #section.occupants >= 2 then details = section.name .. " " .. table.concat(section.occupants, ",") end
        self:check(time, "OCCUPANCY", details)
    end
    for _, point in ipairs(layout.point_order) do
        if point.moving then
            local details
            if #layout.sections[point.common].occupants > 0 then
                details = point.name .. " occupied"
            else
                for name in pairs(point.locks) do
                    local state = interlocking.routes[name].state
                    if state == "USED" or state == "APPROACH" then details = point.name .. " locked" end
                end
            end
            self:check(time, "POINT_MOTION", details)
        end
    end
    local locked = {}
    for _, route in ipairs(interlocking.order) do
        if route.state == "LOCKED" or route.state == "APPROACH" then locked[#locked + 1] = route end
    end
    for i, first in ipairs(locked) do
        for j = i + 1, #locked do
            local second = locked[j]
            self:check(time, "CONFLICT", conflict(first, second) and first.name .. " " .. second.name or nil)
        end
    end
end

function Safety:report()
    local lines = {}
    for _, kind in ipairs(properties) do
        local violations = self.violations[kind] or 0
        lines[#lines + 1] = string.format("%s %s checks %d violations %d", kind,
            violations == 0 and "OK" or "FAIL", self.checks[kind] or 0, violations)
    end
    for _, line in ipairs(self.records) do lines[#lines + 1] = line end
    lines[#lines + 1] = "RESULT " .. (#self.records == 0 and "SAFE" or "UNSAFE")
    return lines
end

return Safety
