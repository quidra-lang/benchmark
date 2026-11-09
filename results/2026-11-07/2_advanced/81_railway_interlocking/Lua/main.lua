local Layout = require("layout")
local Interlocking = require("interlocking")
local Signals = require("signals")
local Trains = require("trains")
local Safety = require("safety")

local Simulation = {}
Simulation.__index = Simulation

local function append(items, item)
    items[#items + 1] = item
end

local function count(items)
    local result = 0
    for _ in pairs(items) do result = result + 1 end
    return result
end

function Simulation.new()
    local layout = Layout.new()
    local self = setmetatable({layout = layout, interlocking = Interlocking.new(layout),
        planned_requests = {}, events = {}, snapshot_times = {}, time = 0, request_count = 0,
        dropped = 0, queue = {}, log_lines = {}, snapshots = {}, safety = Safety.new()}, Simulation)
    self.routes = self.interlocking.routes
    self.trains, self.train_order, self.requests = Trains.read()
    for _, request in ipairs(self.requests) do
        local time = request.time
        self.planned_requests[time] = self.planned_requests[time] or {}
        append(self.planned_requests[time], request)
    end
    for _, f in ipairs(Layout.read("input/events.txt")) do
        local time = tonumber(f[1])
        self.events[time] = self.events[time] or {}
        append(self.events[time], f)
    end
    for _, f in ipairs(Layout.read("input/params.txt")) do
        if f[1] == "END" then self.end_time = tonumber(f[2])
        elseif f[1] == "THROW" then self.throw_time = tonumber(f[2])
        elseif f[1] == "OVERLAP" then self.overlap_time = tonumber(f[2])
        else
            for i = 2, #f do self.snapshot_times[tonumber(f[i])] = true end
        end
    end
    return self
end

function Simulation:log(format, ...)
    append(self.log_lines, self.time .. " " .. string.format(format, ...))
end

function Simulation:occupied(name)
    local section = self.layout.sections[name]
    return #section.occupants > 0 or section.failed
end

function Simulation:start_throw(point, target)
    point.moving, point.target, point.completion = true, target, self.time + self.throw_time
    self:log("MOVE %s %s until %d", point.name, target, point.completion)
end

function Simulation:complete_throws()
    for _, point in ipairs(self.layout.point_order) do
        if point.moving and point.completion == self.time then
            point.position, point.moving, point.completion = point.target, false, nil
            point.throws = point.throws + 1
            self:log("POINT %s %s", point.name, point.position)
        end
    end
end

function Simulation:release_approaches()
    for _, route in ipairs(self.interlocking.order) do
        if route.state == "APPROACH" and route.release_time == self.time then
            self.interlocking:release(route)
            self:log("TIMEOUT %s", route.name)
        end
    end
end

function Simulation:add_request(name, requester)
    self.request_count = self.request_count + 1
    append(self.queue, {number = self.request_count, route = name, time = self.time})
    self.routes[name].requests = self.routes[name].requests + 1
    self:log("REQUEST q%d %s %s", self.request_count, name, requester)
end

function Simulation:cancel(name)
    local waiting, removed = {}, false
    for _, request in ipairs(self.queue) do
        if request.route == name then
            self:log("DROP q%d %s", request.number, name)
            self.dropped, removed = self.dropped + 1, true
        else
            append(waiting, request)
        end
    end
    if removed then self.queue = waiting; return end
    local route = self.routes[name]
    if route.state == "LOCKED" then
        route.cancels = route.cancels + 1
        local signal = self.layout.signals[route.start]
        if signal.aspect ~= "RED" and self:occupied(signal.section) then
            route.state, route.release_time = "APPROACH", self.time + route.approach_time
            self:log("CANCEL %s approach until %d", name, route.release_time)
        else
            self.interlocking:release(route)
            self:log("CANCEL %s released", name)
        end
    else
        self:log("CANCEL %s %s", name, route.state and "refused" or "none")
    end
end

function Simulation:individual_throw(name, target)
    local point, result = self.layout.points[name]
    if next(point.locks) then result = "locked"
    elseif point.failed then result = "failed"
    elseif point.moving then result = "moving"
    elseif self:occupied(point.common) then result = "occupied"
    elseif point.position == target then result = "none"
    else result = "start" end
    self:log("THROW %s %s %s", name, target, result)
    if result == "start" then self:start_throw(point, target) end
end

function Simulation:execute_events()
    for _, f in ipairs(self.events[self.time] or {}) do
        local command, name = f[2], f[3]
        if command == "REQUEST" then self:add_request(name, "OPERATOR")
        elseif command == "CANCEL" then self:cancel(name)
        elseif command == "THROW" then self:individual_throw(name, f[4])
        elseif command == "TCFAIL" or command == "TCFIX" then
            self.layout.sections[name].failed = command == "TCFAIL"
            self:log("%s %s", command, name)
        else
            local point = self.layout.points[name]
            point.failed = command == "POINTFAIL"
            if point.failed and point.moving then point.completion = nil end
            self:log("%s %s", command, name)
            if not point.failed and point.moving then self:start_throw(point, point.target) end
        end
    end
end

function Simulation:opposite_lock(locks, route)
    for name in pairs(locks) do
        if self.routes[name].direction ~= route.direction then return true end
    end
    return false
end

function Simulation:request_reason(route)
    if route.state then return "busy" end
    for _, name in ipairs(route.conflicts) do
        local state = self.routes[name].state
        if state == "LOCKED" or state == "APPROACH" then return "conflict " .. name end
    end
    for _, name in ipairs(route.sections) do
        local section = self.layout.sections[name]
        if self:occupied(name) then return "occupied " .. name end
        if section.route_lock or self:opposite_lock(section.overlap_locks, route) then return "locked " .. name end
    end
    for _, name in ipairs(route.overlap) do
        local section = self.layout.sections[name]
        if self:occupied(name) then return "occupied " .. name end
        if (section.route_lock and self.routes[section.route_lock].direction ~= route.direction)
            or self:opposite_lock(section.overlap_locks, route) then return "locked " .. name end
    end
    for _, item in ipairs(route.requirements) do
        local name, target = item[1], item[2]
        local point = self.layout.points[name]
        for _, position in pairs(point.locks) do
            if position ~= target then return "point " .. name .. " locked" end
        end
        if not ((not point.moving and point.position == target) or (point.moving and point.target == target)) then
            if point.failed then return "point " .. name .. " failed" end
            if point.moving then return "point " .. name .. " moving" end
            if self:occupied(point.common) then return "point " .. name .. " occupied" end
        end
    end
end

function Simulation:judge_requests()
    local waiting = {}
    for _, request in ipairs(self.queue) do
        local route = self.routes[request.route]
        local reason = self:request_reason(route)
        if reason then
            if reason ~= request.reason then
                self:log("WAIT q%d %s %s", request.number, route.name, reason)
                request.reason = reason
            end
            append(waiting, request)
        else
            self.interlocking:lock(route)
            local wait = self.time - request.time
            self:log("GRANT q%d %s wait %d", request.number, route.name, wait)
            route.grants, route.wait, route.maxwait = route.grants + 1, route.wait + wait, math.max(route.maxwait, wait)
            for _, item in ipairs(route.requirements) do
                local point = self.layout.points[item[1]]
                if not point.moving and point.position ~= item[2] then self:start_throw(point, item[2]) end
            end
        end
    end
    self.queue = waiting
end

function Simulation:decide_signals()
    local decided = Signals.aspects(self.interlocking, function(name) return self:occupied(name) end)
    for _, item in ipairs(decided) do
        local signal, aspect = item[1], item[2]
        if signal.aspect ~= aspect then
            signal.aspect = aspect
            self:log("SIGNAL %s %s", signal.name, aspect)
        end
    end
end

function Simulation:occupied_parts(train)
    local parts = {}
    if train.state == "RUNNING" then
        local tail = train.head - train.length
        for _, item in ipairs(train.path) do
            local name, start = item[1], item[2]
            local finish = start + self.layout.sections[name].length
            if start < train.head and finish > tail then
                append(parts, {name, start, math.max(tail, start), math.min(train.head, finish)})
            end
        end
    end
    return parts
end

function Simulation:head_section(train)
    for i = #train.path, 1, -1 do
        if train.path[i][2] < train.head then return train.path[i][1], train.path[i][2] end
    end
    return train.path[1][1], train.path[1][2]
end

function Simulation:enter(train, entered)
    if train.state == "EXITED" then return false end
    if train.state == "RUNNING" then return true end
    local boundary = self.layout.boundaries[train.entry]
    if self.time < train.entry_time or self:occupied(boundary.section) or entered[train.entry] then return false end
    train.state, train.direction = "RUNNING", boundary.side == "L" and "UP" or "DOWN"
    train.path, train.head, train.speed, train.entered = {{boundary.section, 0}}, 0, train.entry_speed, self.time
    entered[train.entry] = true
    self:log("ENTER %s %s", train.name, train.entry)
    return true
end

function Simulation:reverse(train, stop)
    local name, start = self:head_section(train)
    local finish, parts, path = start + self.layout.sections[name].length, self:occupied_parts(train), {}
    for i = #parts, 1, -1 do
        local section, origin = parts[i][1], parts[i][2]
        append(path, {section, finish - (origin + self.layout.sections[section].length)})
    end
    train.path, train.head = path, finish - (train.head - train.length)
    train.direction = train.direction == "UP" and "DOWN" or "UP"
    self:log("REVERSE %s %s", train.name, stop.section)
end

function Simulation:finish_dwell(train)
    if not train.dwelling then return true end
    local stop = Trains.next_stop(train)
    if self.time < stop.arrival + stop.dwell or self.time < stop.scheduled_departure then return false end
    train.dwelling, train.awaiting_departure, train.stop_index = false, stop, train.stop_index + 1
    if stop.kind == "TURN" then self:reverse(train, stop) end
    return true
end

function Simulation:limit_distance(train)
    if train.boundary then return nil end
    local name, start = self:head_section(train)
    local distance = start + self.layout.sections[name].length - train.head
    while true do
        local signal, stop = self.layout:signal_at(name, train.direction), Trains.next_stop(train)
        if signal and signal.aspect == "RED" then return distance end
        if stop and stop.section == name then return distance end
        local kind, following = self.layout:beyond(name, train.direction)
        if kind == "boundary" then return nil end
        if kind == "buffer" or kind == "impassable" then return distance end
        distance, name = distance + self.layout.sections[following].length, following
    end
end

function Simulation:pass_signal(train, signal)
    local route
    for _, candidate in ipairs(self.interlocking.order) do
        if candidate.start == signal.name and (candidate.state == "LOCKED" or candidate.state == "APPROACH") then
            route = candidate
            break
        end
    end
    self:log("PASS %s %s %s %s", train.name, signal.name, signal.aspect, route and route.name or "-")
    signal.passes, train.passes = signal.passes + 1, train.passes + 1
    if route then route.state, route.uses = "USED", route.uses + 1 end
    if signal.aspect == "RED" then
        self:log("SPAD %s %s", train.name, signal.name)
        self.safety:check(self.time, "SIGNAL_PASSING", train.name .. " " .. signal.name)
        train.emergency = true
    else
        self.safety:check(self.time, "SIGNAL_PASSING")
    end
end

function Simulation:move(train, distance)
    local name, start = self:head_section(train)
    local remaining = distance
    while remaining > 0 do
        if train.boundary then train.head = train.head + remaining; break end
        local finish = start + self.layout.sections[name].length
        if train.head + remaining <= finish then train.head = train.head + remaining; break end
        remaining, train.head = remaining - (finish - train.head), finish
        local signal = self.layout:signal_at(name, train.direction)
        if signal then self:pass_signal(train, signal) end
        local stop = train.awaiting_departure
        if stop and stop.section == name then
            self:log("DEPART %s %s", train.name, name)
            stop.departure, train.awaiting_departure = self.time, nil
        end
        local kind, following = self.layout:beyond(name, train.direction)
        if kind == "boundary" then
            train.boundary, train.boundary_coordinate = following, finish
        else
            name, start = following, finish
            append(train.path, {name, start})
        end
    end
end

function Simulation:after_movement(train, speed, previous_speed)
    train.speed, train.distance = speed, train.distance + speed
    train.maximum_speed = math.max(train.maximum_speed, speed)
    if speed == 0 then train.emergency = false end
    local name, start = self:head_section(train)
    local stop = Trains.next_stop(train)
    local arrived = stop and speed == 0 and name == stop.section
        and train.head == start + self.layout.sections[name].length
    if arrived then
        train.dwelling, stop.arrival = true, self.time
        self:log("ARRIVE %s %s", train.name, name)
    end
    if speed == 0 and not arrived then
        train.standing = train.standing + 1
        if previous_speed > 0 then self:log("HOLD %s %s", train.name, name) end
    end
    if train.boundary and train.head - train.length >= train.boundary_coordinate then
        train.state, train.exited = "EXITED", self.time
        self:log("EXIT %s %s", train.name, train.boundary)
    end
end

function Simulation:run_trains()
    local entered = {}
    for _, train in ipairs(self.train_order) do
        if self:enter(train, entered) and self:finish_dwell(train) then
            local speed, previous_speed = Trains.select_speed(train, self:limit_distance(train)), train.speed
            self:move(train, speed)
            self:after_movement(train, speed, previous_speed)
        end
    end
end

function Simulation:recompute_occupancy()
    for _, section in ipairs(self.layout.section_order) do section.occupants = {} end
    for _, train in ipairs(self.train_order) do
        local seen = {}
        for _, part in ipairs(self:occupied_parts(train)) do
            if not seen[part[1]] then
                append(self.layout.sections[part[1]].occupants, train.name)
                seen[part[1]] = true
            end
        end
    end
end

function Simulation:sectional_release()
    for _, route in ipairs(self.interlocking.order) do
        if route.state == "USED" then
            local remaining = {}
            for _, name in ipairs(route.sections) do
                if self.layout.sections[name].route_lock == route.name then
                    append(remaining, name)
                    if self:occupied(name) then route.passed[name] = true end
                end
            end
            for _, name in ipairs(remaining) do
                if not route.passed[name] or self:occupied(name) then break end
                self.interlocking:unlock_section(route, name)
                self:log("RELEASE %s %s", route.name, name)
            end
            local locked = false
            for _, name in ipairs(route.sections) do
                if self.layout.sections[name].route_lock == route.name then locked = true end
            end
            if not locked then
                self.interlocking:release(route)
                self:log("DONE %s", route.name)
            elseif #route.overlap > 0 and route.overlap_locked then
                route.overlap_counter = self:occupied(route.sections[#route.sections]) and route.overlap_counter + 1 or 0
                if route.overlap_counter >= self.overlap_time then
                    self.interlocking:unlock_overlap(route)
                    self:log("OVERLAP %s", route.name)
                end
            end
        end
    end
end

function Simulation:record_statistics()
    for _, route in ipairs(self.interlocking.order) do
        if route.state then route.locked_seconds = route.locked_seconds + 1 end
    end
    for _, point in ipairs(self.layout.point_order) do
        if next(point.locks) then point.locked_seconds = point.locked_seconds + 1 end
        if point.moving then point.moving_seconds = point.moving_seconds + 1 end
    end
    for _, section in ipairs(self.layout.section_order) do
        if self:occupied(section.name) then section.occupied_seconds = section.occupied_seconds + 1 end
        if section.route_lock or next(section.overlap_locks) then section.locked_seconds = section.locked_seconds + 1 end
        for _, name in ipairs(section.occupants) do section.trains[name] = true end
    end
    for _, signal in ipairs(self.layout.signal_order) do signal.seconds[signal.aspect] = signal.seconds[signal.aspect] + 1 end
end

function Simulation:diagram()
    local rows, columns = 0, 0
    for _, section in ipairs(self.layout.section_order) do
        rows, columns = math.max(rows, section.row), math.max(columns, section.last)
    end
    for _, items in ipairs({self.layout.point_order, self.layout.signal_order, self.layout.buffer_order}) do
        for _, item in ipairs(items) do rows, columns = math.max(rows, item.row), math.max(columns, item.column) end
    end
    for _, item in ipairs(self.layout.labels) do
        rows, columns = math.max(rows, item[1]), math.max(columns, item[2] + #item[3] - 1)
    end
    local grid = {}
    for row = 0, rows do
        grid[row] = {}
        for column = 0, columns do grid[row][column] = " " end
    end
    for _, item in ipairs(self.layout.labels) do
        for i = 1, #item[3] do grid[item[1]][item[2] + i - 1] = item[3]:sub(i, i) end
    end
    for _, section in ipairs(self.layout.section_order) do
        local character = section.failed and "#" or section.route_lock and "=" or next(section.overlap_locks) and "~" or "-"
        for column = section.first, section.last do grid[section.row][column] = character end
    end
    for _, train in ipairs(self.train_order) do
        for _, part in ipairs(self:occupied_parts(train)) do
            local section = self.layout.sections[part[1]]
            local length, cells, left, right = section.length, section.last - section.first + 1
            if train.direction == "UP" then left, right = part[3] - part[2], part[4] - part[2]
            else left, right = length - (part[4] - part[2]), length - (part[3] - part[2]) end
            for cell = 0, cells - 1 do
                if left * cells < (cell + 1) * length and right * cells > cell * length then
                    local column = section.first + cell
                    local previous = grid[section.row][column]
                    grid[section.row][column] = ((previous >= "a" and previous <= "z") or previous == "*") and "*" or train.symbol
                end
            end
        end
    end
    for _, item in ipairs(self.layout.buffer_order) do grid[item.row][item.column] = "|" end
    for _, point in ipairs(self.layout.point_order) do grid[point.row][point.column] = Layout.detected(point) and point.position or "?" end
    local aspects = {RED = "X", YELLOW = "Y", GREEN = "G"}
    for _, signal in ipairs(self.layout.signal_order) do grid[signal.row][signal.column] = aspects[signal.aspect] end
    local lines = {}
    for row = 0, rows do
        local cells = {}
        for column = 0, columns do append(cells, grid[row][column]) end
        append(lines, (table.concat(cells):gsub(" +$", "")))
    end
    return lines
end

function Simulation:snapshot()
    append(self.snapshots, "SNAPSHOT " .. self.time)
    for _, line in ipairs(self:diagram()) do append(self.snapshots, line) end
    for _, train in ipairs(self.train_order) do
        if train.state == "RUNNING" then
            local sections = {}
            for _, part in ipairs(self:occupied_parts(train)) do append(sections, part[1]) end
            local line = string.format("TRAIN %s %s %s %d", train.symbol, train.name,
                train.direction, train.speed)
            if #sections > 0 then line = line .. " " .. table.concat(sections, ",") end
            append(self.snapshots, line)
        end
    end
    local routes = {}
    for _, route in ipairs(self.interlocking.order) do
        if route.state then append(routes, route.name .. "/" .. route.state) end
    end
    append(self.snapshots, "ROUTES " .. (#routes == 0 and "-" or table.concat(routes, " ")))
end

function Simulation:train_rows()
    local rows = {}
    for _, train in ipairs(self.train_order) do
        append(rows, {train.name, "enter:" .. train.entry, train.entry_time, train.entered})
        for _, stop in ipairs(train.stops) do
            append(rows, {train.name, "arr:" .. stop.section, stop.scheduled_arrival, stop.arrival})
            append(rows, {train.name, "dep:" .. stop.section, stop.scheduled_departure, stop.departure})
        end
        append(rows, {train.name, "exit:" .. train.exit, train.scheduled_exit, train.exited})
    end
    return rows
end

function Simulation:train_report(rows)
    local lines = {"train,location,scheduled,actual,delay"}
    for _, row in ipairs(rows) do
        local timing = row[4] and string.format("%d,%d", row[4], row[4] - row[3]) or "-,-"
        append(lines, string.format("%s,%s,%d,%s", row[1], row[2], row[3], timing))
    end
    return lines
end

function Simulation:summary(rows)
    local lines = {}
    for _, r in ipairs(self.interlocking.order) do
        append(lines, string.format("ROUTE %s %s-%s requests %d grants %d uses %d cancels %d wait %d maxwait %d locked %d",
            r.name, r.start, r.finish, r.requests, r.grants, r.uses, r.cancels, r.wait, r.maxwait, r.locked_seconds))
    end
    for _, p in ipairs(self.layout.point_order) do
        append(lines, string.format("POINT %s throws %d locked %d moving %d final %s", p.name,
            p.throws, p.locked_seconds, p.moving_seconds, Layout.detected(p) and p.position or "?"))
    end
    for _, s in ipairs(self.layout.section_order) do
        append(lines, string.format("SECTION %s occupied %d locked %d trains %d", s.name,
            s.occupied_seconds, s.locked_seconds, count(s.trains)))
    end
    for _, s in ipairs(self.layout.signal_order) do
        append(lines, string.format("SIGNAL %s red %d yellow %d green %d passes %d", s.name,
            s.seconds.RED, s.seconds.YELLOW, s.seconds.GREEN, s.passes))
    end
    local states, grants = {EXITED = 0, RUNNING = 0, WAITING = 0}, 0
    for _, t in ipairs(self.train_order) do
        append(lines, string.format("TRAIN %s %s %s distance %d maxspeed %d standing %d passes %d",
            t.name, t.symbol, t.state, t.distance, t.maximum_speed, t.standing, t.passes))
        states[t.state] = states[t.state] + 1
    end
    append(lines, string.format("TRAINS total %d exited %d running %d waiting %d", #self.train_order,
        states.EXITED, states.RUNNING, states.WAITING))
    local on_time, late, missing, delay_total, maximum = 0, 0, 0, 0, 0
    for _, row in ipairs(rows) do
        if not row[4] then missing = missing + 1
        else
            local delay = row[4] - row[3]
            if delay <= 0 then on_time = on_time + 1
            else late, delay_total, maximum = late + 1, delay_total + delay, math.max(maximum, delay) end
        end
    end
    append(lines, string.format("PUNCTUALITY on_time %d late %d missing %d total_delay %d max_delay %d",
        on_time, late, missing, delay_total, maximum))
    for _, route in ipairs(self.interlocking.order) do grants = grants + route.grants end
    append(lines, string.format("REQUESTS total %d granted %d dropped %d pending %d",
        self.request_count, grants, self.dropped, #self.queue))
    return lines
end

function Simulation:write_reports()
    local rows = self:train_rows()
    local reports = {{"events.txt", self.log_lines}, {"snapshots.txt", self.snapshots},
        {"train_log.csv", self:train_report(rows)}, {"safety.txt", self.safety:report()},
        {"summary.txt", self:summary(rows)}}
    assert(os.execute("mkdir -p output"))
    for _, report in ipairs(reports) do
        local file = assert(io.open("output/" .. report[1], "wb"))
        for _, line in ipairs(report[2]) do file:write(line, "\n") end
        file:close()
    end
end

function Simulation:run()
    for time = 0, self.end_time do
        self.time = time
        self:complete_throws()
        self:release_approaches()
        for _, request in ipairs(self.planned_requests[time] or {}) do self:add_request(request.route, request.train) end
        self:execute_events()
        self:judge_requests()
        self:decide_signals()
        self:run_trains()
        self:recompute_occupancy()
        self:sectional_release()
        self.safety:inspect(time, self.layout, self.interlocking)
        self:record_statistics()
        if self.snapshot_times[time] then self:snapshot() end
    end
    self:write_reports()
end

Simulation.new():run()
