local Layout = {}
Layout.__index = Layout

function Layout.words(line)
    local fields = {}
    for value in line:gmatch("%S+") do fields[#fields + 1] = value end
    return fields
end

function Layout.read(path)
    local lines = {}
    for line in io.lines(path) do lines[#lines + 1] = Layout.words(line) end
    return lines
end

local function key(section, side)
    return section .. ":" .. side
end

function Layout.new()
    local self = setmetatable({sections = {}, points = {}, signals = {}, buffers = {},
        boundaries = {}, labels = {}, ends = {}, signals_at = {}, section_order = {},
        point_order = {}, signal_order = {}, buffer_order = {}}, Layout)
    for _, f in ipairs(Layout.read("input/layout.txt")) do
        local kind, name = f[1], f[2]
        if kind == "SECTION" then
            local item = {name = name, length = tonumber(f[3]), row = tonumber(f[4]),
                first = tonumber(f[5]), last = tonumber(f[6]), failed = false, occupants = {},
                occupied_seconds = 0, locked_seconds = 0, trains = {}, overlap_locks = {}}
            self.sections[name] = item
            self.section_order[#self.section_order + 1] = item
        elseif kind == "JOINT" then
            self.ends[key(name, "R")] = {"section", f[3]}
            self.ends[key(f[3], "L")] = {"section", name}
        elseif kind == "POINT" then
            local item = {name = name, side = f[3], common = f[4], normal = f[5],
                reverse = f[6], row = tonumber(f[7]), column = tonumber(f[8]),
                position = "N", moving = false, failed = false, throws = 0,
                locked_seconds = 0, moving_seconds = 0, locks = {}}
            self.points[name] = item
            self.point_order[#self.point_order + 1] = item
            self.ends[key(item.common, item.side)] = {"point", name}
            local other = item.side == "R" and "L" or "R"
            self.ends[key(item.normal, other)] = {"point", name}
            self.ends[key(item.reverse, other)] = {"point", name}
        elseif kind == "SIGNAL" then
            local item = {name = name, section = f[3], direction = f[4], row = tonumber(f[5]),
                column = tonumber(f[6]), aspect = "RED", seconds = {RED = 0, YELLOW = 0, GREEN = 0},
                passes = 0}
            self.signals[name] = item
            self.signal_order[#self.signal_order + 1] = item
            self.signals_at[key(item.section, item.direction)] = item
        elseif kind == "BUFFER" or kind == "BOUNDARY" then
            local item = {name = name, section = f[3], side = f[4]}
            if kind == "BUFFER" then
                item.row, item.column = tonumber(f[5]), tonumber(f[6])
                self.buffers[name] = item
                self.buffer_order[#self.buffer_order + 1] = item
            else
                self.boundaries[name] = item
            end
            self.ends[key(item.section, item.side)] = {kind:lower(), name}
        else
            self.labels[#self.labels + 1] = {tonumber(f[2]), tonumber(f[3]), f[4]}
        end
    end
    return self
end

function Layout:signal_at(section, direction)
    return self.signals_at[key(section, direction)]
end

function Layout.detected(point)
    return not point.moving and not point.failed
end

function Layout:beyond(section, direction)
    local edge = self.ends[key(section, direction == "UP" and "R" or "L")]
    local kind, name = edge[1], edge[2]
    if kind ~= "point" then return kind, name end
    local point = self.points[name]
    local branch = point.position == "N" and point.normal or point.reverse
    if point.moving or (section ~= point.common and section ~= branch) then
        return "impassable"
    end
    return "section", section == point.common and branch or point.common
end

return Layout
