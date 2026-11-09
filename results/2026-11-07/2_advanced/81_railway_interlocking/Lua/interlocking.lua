local Layout = require("layout")
local Interlocking = {}
Interlocking.__index = Interlocking

local function names(text)
    local result = {}
    if text ~= "-" then
        for name in text:gmatch("[^,]+") do result[#result + 1] = name end
    end
    return result
end

local function requirements(text)
    local result = {}
    for _, item in ipairs(names(text)) do
        local name, position = item:match("^([^:]+):(.+)$")
        result[#result + 1] = {name, position}
    end
    return result
end

function Interlocking.new(layout)
    local self = setmetatable({layout = layout, routes = {}, order = {}}, Interlocking)
    for _, f in ipairs(Layout.read("input/routes.txt")) do
        local route = {name = f[2], start = f[3], finish = f[4], points = requirements(f[5]),
            sections = names(f[6]), overlap = names(f[7]), flank = requirements(f[8]),
            conflicts = names(f[9]), approach_time = tonumber(f[10]), passed = {},
            overlap_locked = false, overlap_counter = 0, requests = 0, grants = 0, uses = 0,
            cancels = 0, wait = 0, maxwait = 0, locked_seconds = 0, requirements = {}}
        route.direction = layout.signals[route.start].direction
        for _, item in ipairs(route.points) do route.requirements[#route.requirements + 1] = item end
        for _, item in ipairs(route.flank) do route.requirements[#route.requirements + 1] = item end
        self.routes[route.name] = route
        self.order[#self.order + 1] = route
    end
    return self
end

function Interlocking:lock(route)
    route.state, route.release_time = "LOCKED", nil
    route.passed, route.overlap_locked, route.overlap_counter = {}, true, 0
    for _, name in ipairs(route.sections) do self.layout.sections[name].route_lock = route.name end
    for _, name in ipairs(route.overlap) do self.layout.sections[name].overlap_locks[route.name] = true end
    for _, item in ipairs(route.requirements) do
        self.layout.points[item[1]].locks[route.name] = item[2]
    end
end

function Interlocking:unlock_points(route, sections)
    for _, point in ipairs(self.layout.point_order) do
        if not sections or sections[point.common] then point.locks[route.name] = nil end
    end
end

function Interlocking:unlock_section(route, name)
    local section = self.layout.sections[name]
    if section.route_lock == route.name then section.route_lock = nil end
    self:unlock_points(route, {[name] = true})
end

function Interlocking:unlock_overlap(route)
    local sections = {}
    for _, name in ipairs(route.overlap) do
        self.layout.sections[name].overlap_locks[route.name] = nil
        sections[name] = true
    end
    self:unlock_points(route, sections)
    route.overlap_locked = false
end

function Interlocking:release(route)
    for _, name in ipairs(route.sections) do
        local section = self.layout.sections[name]
        if section.route_lock == route.name then section.route_lock = nil end
    end
    if route.overlap_locked then self:unlock_overlap(route) end
    self:unlock_points(route)
    route.state, route.release_time = nil, nil
end

return Interlocking
