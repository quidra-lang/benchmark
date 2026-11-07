local source_dir = arg[0]:match("^(.*[/\\])") or "./"
package.path = source_dir .. "?.lua;" .. package.path

local enrolment = require("enrolment")
local graphs = require("conflict_graph")
local coloring = require("coloring")
local rooms = require("rooms")
local report = require("report")
local format = string.format
local RELATIONS = {"back_to_back", "same_day", "overnight"}
local EXCHANGE_VERDICTS = {"fixed", "invalid", "worse", "applied"}
local SWAP_VERDICTS = {"fixed", "invalid", "rooms", "worse", "applied"}

local function read_lines(name)
    local lines = {}
    for line in io.lines("input/" .. name) do lines[#lines + 1] = line end
    return lines
end

local function copy(map)
    local result = {}
    for key, value in pairs(map) do result[key] = value end
    return result
end

local function sorted_keys(map)
    local result = {}
    for key in pairs(map) do result[#result + 1] = key end
    table.sort(result)
    return result
end

local function count(map)
    local total = 0
    for _ in pairs(map) do total = total + 1 end
    return total
end

local function contains(list, value)
    for _, item in ipairs(list) do
        if item == value then return true end
    end
    return false
end

local function extend(target, items)
    for _, item in ipairs(items) do target[#target + 1] = item end
end

local function ceil_div(a, b)
    return (a + b - 1) // b
end

local function verdict_counts(tally, verdicts)
    local parts = {}
    for _, verdict in ipairs(verdicts) do
        parts[#parts + 1] = verdict .. " " .. tally[verdict]
    end
    return table.concat(parts, " ")
end

local Calendar = {}
Calendar.__index = Calendar

function Calendar.new(lines)
    local settings = {}
    for index = 1, 6 do
        local values = {}
        local first = true
        for token in lines[index]:gmatch("%S+") do
            if first then first = false else values[#values + 1] = tonumber(token) end
        end
        settings[index] = values
    end
    return setmetatable({days = settings[1][1], lengths = settings[2], periods = #settings[2],
        limit = settings[3][1], weights = settings[4], front_count = settings[5][1],
        deadline = settings[5][2], ratio = settings[6][1],
        slot_count = settings[1][1] * #settings[2], closed = {}, unavailable = {},
        fixed = {}, orders = {}, arrows = {}}, Calendar)
end

function Calendar:slots()
    local slots = {}
    for slot = 1, self.slot_count do slots[#slots + 1] = slot end
    return slots
end

function Calendar:slot_at(day_text, period_text)
    local day, period = tonumber(day_text), tonumber(period_text)
    if day >= 1 and day <= self.days and period >= 1 and period <= self.periods then
        return (day - 1) * self.periods + period
    end
    return nil
end

function Calendar:day_of(slot)
    return (slot - 1) // self.periods + 1
end

function Calendar:name(slot)
    return format("D%dP%d", self:day_of(slot), (slot - 1) % self.periods + 1)
end

function Calendar:length(slot)
    return self.lengths[(slot - 1) % self.periods + 1]
end

function Calendar:relation(first, second)
    local low, high = math.min(first, second), math.max(first, second)
    if self:day_of(low) == self:day_of(high) then
        if high - low == 1 then return 1 end
        if high - low >= 2 then return 2 end
    elseif high - low == 1 then
        return 3
    end
    return nil
end

local Breakdown = {}
Breakdown.__index = Breakdown

function Breakdown.new(counts, late, weights)
    local total = weights[4] * late
    for relation, value in ipairs(counts) do total = total + weights[relation] * value end
    return setmetatable({counts = counts, late = late, total = total}, Breakdown)
end

function Breakdown:text()
    return format("back_to_back %d same_day %d overnight %d front_load %d penalty %d",
        self.counts[1], self.counts[2], self.counts[3], self.late, self.total)
end

local Scheduler = {}
Scheduler.__index = Scheduler

function Scheduler.new(courses, student_courses, room_list, calendar, errors)
    local self = setmetatable({courses = courses, student_courses = student_courses,
        rooms = room_list, calendar = calendar, errors = errors, largest_room = 0,
        empty = {}, oversized = {}, schedulable = {}, open_slots = {}, fixed_slots = {},
        assignment = {}, penalty = 0, attempts = {}, assignment_order = {}, excluded = {},
        insertions = {}, reasons = {}, exchange_log = {}, swap_log = {},
        placements = {}, slot_placements = {}}, Scheduler)
    for _, room in ipairs(room_list) do self.largest_room = math.max(self.largest_room, room.capacity) end
    local vertices = {}
    for _, id in ipairs(sorted_keys(courses)) do
        local size = courses[id]:size()
        if size == 0 then
            self.empty[#self.empty + 1] = id
        elseif size > self.largest_room then
            self.oversized[#self.oversized + 1] = id
        else
            self.schedulable[#self.schedulable + 1] = id
        end
        if size > 0 then vertices[#vertices + 1] = id end
    end
    self.graph = graphs.ConflictGraph.new(vertices, student_courses)
    self.edges = self.graph:edges()
    self.front_load = {}
    local ranked = self:by_size(self.schedulable)
    for index = 1, math.min(calendar.front_count, #ranked) do
        self.front_load[#self.front_load + 1] = ranked[index]
    end
    return self
end

function Scheduler:by_size(ids)
    local result = copy(ids)
    table.sort(result, function(a, b)
        local sa, sb = self.courses[a]:size(), self.courses[b]:size()
        if sa ~= sb then return sa > sb end
        return a < b
    end)
    return result
end

function Scheduler:by_degree(ids)
    local result = copy(ids)
    table.sort(result, function(a, b)
        local da, db = self.graph:degree(a), self.graph:degree(b)
        if da ~= db then return da > db end
        return a < b
    end)
    return result
end

function Scheduler:blocked_students(course, slot)
    local blocked = {}
    for _, student in ipairs(course.students) do
        if (self.calendar.unavailable[student] or {})[slot] then
            blocked[#blocked + 1] = student
        end
    end
    return blocked
end

function Scheduler:suitable(course, slot)
    return self.calendar:length(slot) >= course.duration and #self:blocked_students(course, slot) == 0
end

function Scheduler:packs(ids)
    local courses = {}
    for _, id in ipairs(ids) do courses[#courses + 1] = self.courses[id] end
    return rooms.pack(self.rooms, courses) ~= nil
end

function Scheduler:outside(day, period)
    return "slot " .. day .. " " .. period .. " outside calendar"
end

function Scheduler:validate_calendar(lines)
    local handlers = {closed = self.accept_closed, unavailable = self.accept_unavailable,
        fixed = self.accept_fixed, after = self.accept_after}
    for number = 7, #lines do
        local fields = {}
        for token in lines[number]:gmatch("%S+") do fields[#fields + 1] = token end
        local kind = table.remove(fields, 1)
        local message = handlers[kind](self, fields)
        if message then
            self.errors[#self.errors + 1] = format("calendar.txt line %d: %s", number, message)
        end
    end
    for slot = 1, self.calendar.slot_count do
        if not self.calendar.closed[slot] then self.open_slots[#self.open_slots + 1] = slot end
    end
    for _, slot in pairs(self.calendar.fixed) do self.fixed_slots[slot] = true end
end

function Scheduler:accept_closed(fields)
    local slot = self.calendar:slot_at(fields[1], fields[2])
    if not slot then return self:outside(fields[1], fields[2]) end
    if self.calendar.closed[slot] then return "duplicate closed " .. self.calendar:name(slot) end
    self.calendar.closed[slot] = true
end

function Scheduler:accept_unavailable(fields)
    local student, day, period = fields[1], fields[2], fields[3]
    if not self.student_courses[student] then return "unknown student " .. student end
    local slot = self.calendar:slot_at(day, period)
    if not slot then return self:outside(day, period) end
    local blocked = self.calendar.unavailable[student] or {}
    if blocked[slot] then return "duplicate unavailable " .. student .. " " .. self.calendar:name(slot) end
    blocked[slot] = true
    self.calendar.unavailable[student] = blocked
end

function Scheduler:accept_fixed(fields)
    local id, day, period = fields[1], fields[2], fields[3]
    if not self.courses[id] then return "unknown course " .. id end
    if not contains(self.schedulable, id) then return "course " .. id .. " not schedulable" end
    local slot = self.calendar:slot_at(day, period)
    if not slot then return self:outside(day, period) end
    local name = self.calendar:name(slot)
    if self.calendar.closed[slot] then return "slot " .. name .. " closed" end
    if not self:suitable(self.courses[id], slot) then return "slot " .. name .. " unsuitable for " .. id end
    if self.calendar.fixed[id] then return "duplicate fixed " .. id end
    local group = self:courses_at(self.calendar.fixed, slot)
    for _, other in ipairs(group) do
        if self.graph:neighbours(id)[other] then return "conflict " .. id .. " " .. other end
    end
    group[#group + 1] = id
    if not self:packs(group) then return "rooms full " .. name end
    self.calendar.fixed[id] = slot
end

function Scheduler:accept_after(fields)
    local later, earlier = fields[1], fields[2]
    for _, id in ipairs(fields) do
        if not self.courses[id] then return "unknown course " .. id end
    end
    for _, id in ipairs(fields) do
        if not contains(self.schedulable, id) then return "course " .. id .. " not schedulable" end
    end
    if later == earlier then return "bad order " .. later .. " " .. earlier end
    for _, order in ipairs(self.calendar.orders) do
        if order[1] == later and order[2] == earlier then return "duplicate order " .. later .. " " .. earlier end
    end
    if graphs.reachable(self.calendar.arrows, earlier, later) then return "cycle " .. later .. " " .. earlier end
    local fixed = self.calendar.fixed
    if fixed[later] and fixed[earlier] and fixed[later] <= fixed[earlier] then
        return "fixed order " .. later .. " " .. earlier
    end
    self.calendar.orders[#self.calendar.orders + 1] = {later, earlier}
    self.calendar.arrows[later] = self.calendar.arrows[later] or {}
    local arrows = self.calendar.arrows[later]
    arrows[#arrows + 1] = earlier
end

function Scheduler:courses_at(assignment, slot)
    local result = {}
    for id, other in pairs(assignment) do
        if other == slot then result[#result + 1] = id end
    end
    table.sort(result)
    return result
end

function Scheduler:order_conflicts(id, slot, assignment)
    local conflicts = {}
    for _, order in ipairs(self.calendar.orders) do
        local later, earlier = order[1], order[2]
        if later == id and assignment[earlier] and slot <= assignment[earlier] then
            conflicts[#conflicts + 1] = earlier
        elseif earlier == id and assignment[later] and slot >= assignment[later] then
            conflicts[#conflicts + 1] = later
        end
    end
    return conflicts
end

function Scheduler:orders_satisfied(assignment)
    for _, order in ipairs(self.calendar.orders) do
        local later, earlier = assignment[order[1]], assignment[order[2]]
        if later and earlier and later <= earlier then return false end
    end
    return true
end

function Scheduler:candidate_slots(id, assignment)
    local candidates = {}
    for _, slot in ipairs(self.open_slots) do
        local valid = self:suitable(self.courses[id], slot)
        if valid then
            for other in pairs(self.graph:neighbours(id)) do
                if assignment[other] == slot then valid = false; break end
            end
        end
        if valid and #self:order_conflicts(id, slot, assignment) == 0 then
            local group = self:courses_at(assignment, slot)
            group[#group + 1] = id
            if self:packs(group) then candidates[#candidates + 1] = slot end
        end
    end
    return candidates
end

function Scheduler:build_timetable()
    local assignment, attempt
    while true do
        local pending = {}
        for _, id in ipairs(self.schedulable) do
            if not self.calendar.fixed[id] and not contains(self.excluded, id) then pending[#pending + 1] = id end
        end
        assignment = copy(self.calendar.fixed)
        attempt = coloring.Attempt.new(pending, self.graph, self.calendar.limit,
            function(id, trial) return self:candidate_slots(id, trial) end)
        local succeeded = attempt:search(assignment)
        local failed_course
        if not succeeded then failed_course = attempt.dead_end_course end
        self.attempts[#self.attempts + 1] = {#pending, attempt.dead_ends, failed_course}
        if succeeded then break end
        self.excluded[#self.excluded + 1] = attempt.dead_end_course
    end
    self.assignment = assignment
    for _, chosen in ipairs(attempt.chosen) do
        self.assignment_order[#self.assignment_order + 1] = {chosen[1], assignment[chosen[1]], chosen[2]}
    end
end

function Scheduler:penalty_pairs(assignment)
    local result = {}
    for _, edge in ipairs(self.edges) do
        local first, second, shared = edge[1], edge[2], edge[3]
        if assignment[first] and assignment[second] then
            local relation = self.calendar:relation(assignment[first], assignment[second])
            if relation then result[#result + 1] = {first, second, relation, shared} end
        end
    end
    return result
end

function Scheduler:late_courses(assignment)
    local result = {}
    for _, id in ipairs(self.front_load) do
        if assignment[id] and assignment[id] > self.calendar.deadline then result[#result + 1] = id end
    end
    return result
end

function Scheduler:breakdown(assignment)
    local counts = {0, 0, 0}
    for _, pair in ipairs(self:penalty_pairs(assignment)) do counts[pair[3]] = counts[pair[3]] + pair[4] end
    return Breakdown.new(counts, #self:late_courses(assignment), self.calendar.weights)
end

function Scheduler:contributions()
    local result = {}
    for id in pairs(self.assignment) do result[id] = 0 end
    for _, pair in ipairs(self:penalty_pairs(self.assignment)) do
        local amount = self.calendar.weights[pair[3]] * pair[4]
        result[pair[1]] = result[pair[1]] + amount
        result[pair[2]] = result[pair[2]] + amount
    end
    for _, id in ipairs(self:late_courses(self.assignment)) do result[id] = result[id] + self.calendar.weights[4] end
    return result
end

function Scheduler:blocking_reason(id, slot)
    local course = self.courses[id]
    if self.calendar.closed[slot] then return "closed" end
    if self.calendar:length(slot) < course.duration then return "too_short" end
    local blocked = self:blocked_students(course, slot)
    if #blocked > 0 then return "unavailable " .. blocked[1] end
    local clash, strength
    for other, shared in pairs(self.graph:neighbours(id)) do
        if self.assignment[other] == slot and (not clash or shared > strength or (shared == strength and other < clash)) then
            clash, strength = other, shared
        end
    end
    if clash then return format("conflict %s shared %d", clash, strength) end
    local conflicts = self:order_conflicts(id, slot, self.assignment)
    table.sort(conflicts)
    if #conflicts > 0 then return "order " .. conflicts[1] end
    return "rooms"
end

function Scheduler:insert_excluded()
    local excluded = copy(self.excluded)
    table.sort(excluded)
    for _, id in ipairs(excluded) do
        local slots = self:candidate_slots(id, self.assignment)
        if #slots == 0 then
            local reasons = {}
            for slot = 1, self.calendar.slot_count do reasons[#reasons + 1] = self:blocking_reason(id, slot) end
            self.reasons[id] = reasons
        else
            local before, best, total = self:breakdown(self.assignment).total
            for _, slot in ipairs(slots) do
                local trial = copy(self.assignment)
                trial[id] = slot
                local value = self:breakdown(trial).total
                if not best or value < total then best, total = slot, value end
            end
            self.assignment[id] = best
            self.insertions[#self.insertions + 1] = {id, best, total - before}
        end
    end
    self.initial = self:breakdown(self.assignment)
    self.penalty = self.initial.total
end

function Scheduler:unscheduled()
    local result = copy(self.oversized)
    for _, id in ipairs(self.excluded) do
        if not self.assignment[id] then result[#result + 1] = id end
    end
    table.sort(result)
    return result
end

function Scheduler:valid_trial(trial, moved)
    for _, id in ipairs(moved) do
        if not self:suitable(self.courses[id], trial[id]) then return false end
    end
    return self:orders_satisfied(trial)
end

function Scheduler:moved_courses(trial)
    local result = {}
    for id, slot in pairs(trial) do
        if slot ~= self.assignment[id] then result[#result + 1] = id end
    end
    table.sort(result)
    return result
end

function Scheduler:exchange_trial(first, second)
    if self.fixed_slots[first] or self.fixed_slots[second] then return "fixed" end
    local trial = copy(self.assignment)
    for id, slot in pairs(self.assignment) do
        if slot == first then trial[id] = second elseif slot == second then trial[id] = first end
    end
    if not self:valid_trial(trial, self:moved_courses(trial)) then return "invalid" end
    local total = self:breakdown(trial).total
    if total >= self.penalty then return "worse" end
    return "applied", trial, total
end

function Scheduler:exchange_slots()
    local round_number, serial = 0, 0
    while true do
        round_number = round_number + 1
        local tally = {fixed = 0, invalid = 0, worse = 0, applied = 0}
        local records, pair_count = {}, 0
        for index, first in ipairs(self.open_slots) do
            for j = index + 1, #self.open_slots do
                local second = self.open_slots[j]
                pair_count = pair_count + 1
                local verdict, trial, total = self:exchange_trial(first, second)
                tally[verdict] = tally[verdict] + 1
                if verdict == "applied" then
                    serial = serial + 1
                    records[#records + 1] = format("EXCHANGE %d %s %s penalty %d -> %d", serial,
                        self.calendar:name(first), self.calendar:name(second), self.penalty, total)
                    self.assignment, self.penalty = trial, total
                end
            end
        end
        self.exchange_log[#self.exchange_log + 1] = format("ROUND %d pairs %d %s", round_number,
            pair_count, verdict_counts(tally, EXCHANGE_VERDICTS))
        extend(self.exchange_log, records)
        if tally.applied == 0 then break end
    end
    self.exchanged = self:breakdown(self.assignment)
end

function Scheduler:swap_trial(id, home, target)
    local chain = self.graph:kempe_chain(self.assignment, id, home, target)
    for _, member in ipairs(chain) do
        if self.calendar.fixed[member] then return "fixed" end
    end
    local trial = copy(self.assignment)
    for _, member in ipairs(chain) do trial[member] = self.assignment[member] == home and target or home end
    if not self:valid_trial(trial, chain) then return "invalid" end
    if not self:packs(self:courses_at(trial, home)) or not self:packs(self:courses_at(trial, target)) then return "rooms" end
    local total = self:breakdown(trial).total
    if total >= self.penalty then return "worse" end
    return "applied", trial, total
end

function Scheduler:swap_chains()
    local pass_number, serial = 0, 0
    while true do
        pass_number = pass_number + 1
        local tally = {fixed = 0, invalid = 0, rooms = 0, worse = 0, applied = 0}
        local records, candidates, movable = {}, 0, {}
        for _, id in ipairs(sorted_keys(self.assignment)) do
            if not self.calendar.fixed[id] then movable[#movable + 1] = id end
        end
        for _, id in ipairs(movable) do
            local home = self.assignment[id]
            for _, target in ipairs(self.open_slots) do
                if target ~= home then
                    candidates = candidates + 1
                    local verdict, trial, total = self:swap_trial(id, home, target)
                    tally[verdict] = tally[verdict] + 1
                    if verdict == "applied" then
                        serial = serial + 1
                        local chain = self:moved_courses(trial)
                        records[#records + 1] = format("SWAP %d %s %s %s chain %d penalty %d -> %d", serial,
                            id, self.calendar:name(home), self.calendar:name(target), #chain, self.penalty, total)
                        for _, member in ipairs(chain) do
                            records[#records + 1] = format("  MOVE %s %s -> %s", member,
                                self.calendar:name(self.assignment[member]), self.calendar:name(trial[member]))
                        end
                        self.assignment, self.penalty = trial, total
                        break
                    end
                end
            end
        end
        self.swap_log[#self.swap_log + 1] = format("PASS %d candidates %d %s", pass_number,
            candidates, verdict_counts(tally, SWAP_VERDICTS))
        extend(self.swap_log, records)
        if tally.applied == 0 then break end
    end
end

function Scheduler:assign_rooms()
    for _, slot in ipairs(self.open_slots) do
        local group = {}
        for _, id in ipairs(self:courses_at(self.assignment, slot)) do group[#group + 1] = self.courses[id] end
        local placements = rooms.pack(self.rooms, group)
        self.slot_placements[slot] = placements
        for _, placement in ipairs(placements) do self.placements[placement.course.id] = placement end
    end
end

function Scheduler:room_groups(slot)
    local groups = {}
    for _, room in ipairs(self.rooms) do
        local placed = {}
        for _, placement in ipairs(self.slot_placements[slot]) do
            if placement.room == room then placed[#placed + 1] = placement end
        end
        if #placed > 0 then groups[#groups + 1] = {room, placed} end
    end
    return groups
end

function Scheduler:invigilators(slot)
    local total = 0
    for _, group in ipairs(self:room_groups(slot)) do
        local students = 0
        for _, placement in ipairs(group[2]) do students = students + placement.course:size() end
        total = total + ceil_div(students, self.calendar.ratio)
    end
    return total
end

function Scheduler:slot_load(slot)
    local ids = self:courses_at(self.assignment, slot)
    local students = 0
    for _, id in ipairs(ids) do students = students + self.courses[id]:size() end
    return #ids, students
end

function Scheduler:student_assignments(student)
    local assigned = {}
    for _, id in ipairs(self.student_courses[student]) do
        if self.assignment[id] then assigned[#assigned + 1] = {self.assignment[id], id} end
    end
    table.sort(assigned, function(a, b)
        if a[1] ~= b[1] then return a[1] < b[1] end
        return a[2] < b[2]
    end)
    return assigned
end

function Scheduler:student_pairs(student)
    local assigned, pairs_list = self:student_assignments(student), {}
    for index, low in ipairs(assigned) do
        for j = index + 1, #assigned do
            local high = assigned[j]
            local relation = self.calendar:relation(low[1], high[1])
            if relation then pairs_list[#pairs_list + 1] = {relation, low[1], low[2], high[1], high[2]} end
        end
    end
    return pairs_list
end

function Scheduler:student_penalty(student)
    local counts, penalty = {0, 0, 0}, 0
    for _, pair in ipairs(self:student_pairs(student)) do counts[pair[1]] = counts[pair[1]] + 1 end
    for relation, value in ipairs(counts) do penalty = penalty + self.calendar.weights[relation] * value end
    return counts, penalty
end

function Scheduler:timetable_lines()
    local calendar = self.calendar
    local lines = {format("TIMETABLE days %d periods %d open %d courses %d scheduled %d unscheduled %d empty %d",
        calendar.days, calendar.periods, #self.open_slots, count(self.courses), count(self.assignment),
        #self:unscheduled(), #self.empty)}
    local header = {}
    for period = 1, calendar.periods do header[#header + 1] = "P" .. period end
    header[#header + 1] = "TOTAL"
    lines[#lines + 1] = report.fixed_width_line("DAY", header, 4, 10)
    for day = 1, calendar.days do
        local cells, day_exams, day_students = {}, 0, 0
        for period = 1, calendar.periods do
            local slot = (day - 1) * calendar.periods + period
            if calendar.closed[slot] then
                cells[#cells + 1] = "closed"
            else
                local exams, students = self:slot_load(slot)
                cells[#cells + 1] = format("%d/%d", exams, students)
                day_exams, day_students = day_exams + exams, day_students + students
            end
        end
        cells[#cells + 1] = format("%d/%d", day_exams, day_students)
        lines[#lines + 1] = report.fixed_width_line("D" .. day, cells, 4, 10)
    end
    for slot = 1, calendar.slot_count do
        local prefix = format("SLOT %d %s minutes %d", slot, calendar:name(slot), calendar:length(slot))
        if calendar.closed[slot] then
            lines[#lines + 1] = prefix .. " closed"
        else
            local exams, students = self:slot_load(slot)
            local groups, seats = self:room_groups(slot), 0
            for _, group in ipairs(groups) do seats = seats + group[1].capacity end
            lines[#lines + 1] = format("%s exams %d students %d rooms %d seats %d invigilators %d",
                prefix, exams, students, #groups, seats, self:invigilators(slot))
            for _, placement in ipairs(self.slot_placements[slot]) do
                local course = placement.course
                local marker = calendar.fixed[course.id] and " fixed" or ""
                lines[#lines + 1] = format("  %s %dmin students %d room %s seats %d-%d%s %s",
                    course.id, course.duration, course:size(), placement.room.id,
                    placement.first_seat, placement.last_seat, marker, course.name)
            end
        end
    end
    for _, room in ipairs(self.rooms) do
        local used, exams, seated = 0, 0, 0
        for _, slot in ipairs(self.open_slots) do
            for _, group in ipairs(self:room_groups(slot)) do
                if group[1] == room then
                    used, exams = used + 1, exams + #group[2]
                    for _, placement in ipairs(group[2]) do seated = seated + placement.course:size() end
                end
            end
        end
        lines[#lines + 1] = format("ROOM %s capacity %d slots %d exams %d seated %d utilization %d",
            room.id, room.capacity, used, exams, seated, report.rounded_percent(seated, room.capacity * #self.open_slots))
    end
    local total = 0
    for _, slot in ipairs(self.open_slots) do total = total + self:invigilators(slot) end
    lines[#lines + 1] = format("INVIGILATORS total %d ratio %d", total, calendar.ratio)
    return lines
end

function Scheduler:room_lines()
    local lines = {"slot,room,course,students,first_seat,last_seat"}
    for _, slot in ipairs(self.open_slots) do
        for _, group in ipairs(self:room_groups(slot)) do
            for _, placement in ipairs(group[2]) do
                lines[#lines + 1] = format("%s,%s,%s,%d,%d,%d", self.calendar:name(slot),
                    group[1].id, placement.course.id, placement.course:size(), placement.first_seat, placement.last_seat)
            end
        end
    end
    return lines
end

function Scheduler:student_statistics()
    local histogram, gaps, day_loads, ranking = {}, {}, {}, {}
    for student in pairs(self.student_courses) do
        local counts, penalty = self:student_penalty(student)
        histogram[penalty] = (histogram[penalty] or 0) + 1
        ranking[#ranking + 1] = {student = student, counts = counts, penalty = penalty}
        local assigned = self:student_assignments(student)
        for index = 2, #assigned do
            local gap = assigned[index][1] - assigned[index - 1][1]
            gaps[gap] = (gaps[gap] or 0) + 1
        end
        if #assigned > 0 then
            local per_day, maximum = {}, 0
            for _, item in ipairs(assigned) do
                local day = self.calendar:day_of(item[1])
                per_day[day] = (per_day[day] or 0) + 1
                maximum = math.max(maximum, per_day[day])
            end
            day_loads[maximum] = (day_loads[maximum] or 0) + 1
        end
    end
    local lines = {}
    for _, value in ipairs(sorted_keys(histogram)) do lines[#lines + 1] = format("HISTOGRAM %d %d", value, histogram[value]) end
    for _, value in ipairs(sorted_keys(gaps)) do lines[#lines + 1] = format("GAP %d %d", value, gaps[value]) end
    for _, value in ipairs(sorted_keys(day_loads)) do lines[#lines + 1] = format("DAYLOAD %d %d", value, day_loads[value]) end
    table.sort(ranking, function(a, b)
        if a.penalty ~= b.penalty then return a.penalty > b.penalty end
        return a.student < b.student
    end)
    for index = 1, math.min(5, #ranking) do
        local item = ranking[index]
        if item.penalty > 0 then
            lines[#lines + 1] = format("WORST %s penalty %d back_to_back %d same_day %d overnight %d",
                item.student, item.penalty, item.counts[1], item.counts[2], item.counts[3])
        end
    end
    return lines
end

function Scheduler:penalty_lines()
    local calendar, weights = self.calendar, self.calendar.weights
    local final = self:breakdown(self.assignment)
    local lines = {
        format("WEIGHTS back_to_back %d same_day %d overnight %d front_load %d", weights[1], weights[2], weights[3], weights[4]),
        format("FRONT_LOAD courses %d last_slot %s", #self.front_load, calendar:name(calendar.deadline)),
        "INITIAL " .. self.initial:text()
    }
    extend(lines, self.exchange_log)
    lines[#lines + 1] = "EXCHANGED " .. self.exchanged:text()
    extend(lines, self.swap_log)
    lines[#lines + 1] = "FINAL " .. final:text()
    lines[#lines + 1] = "SAVED " .. (self.initial.total - final.total)
    local daily = {}
    for day = 1, calendar.days do daily[day] = {0, 0, 0} end
    for _, pair in ipairs(self:penalty_pairs(self.assignment)) do
        local day = calendar:day_of(math.min(self.assignment[pair[1]], self.assignment[pair[2]]))
        daily[day][pair[3]] = daily[day][pair[3]] + pair[4]
    end
    for day = 1, calendar.days do
        local values = daily[day]
        lines[#lines + 1] = format("DAY D%d back_to_back %d same_day %d overnight %d", day, values[1], values[2], values[3])
    end
    for _, id in ipairs(self:late_courses(self.assignment)) do
        lines[#lines + 1] = format("LATE %s %s students %d", id, calendar:name(self.assignment[id]), self.courses[id]:size())
    end
    local contributions = self:contributions()
    local ranked = sorted_keys(contributions)
    table.sort(ranked, function(a, b)
        if contributions[a] ~= contributions[b] then return contributions[a] > contributions[b] end
        return a < b
    end)
    for index = 1, math.min(10, #ranked) do
        local id = ranked[index]
        if contributions[id] > 0 then
            lines[#lines + 1] = format("COURSE %s %s penalty %d", id, calendar:name(self.assignment[id]), contributions[id])
        end
    end
    extend(lines, self:student_statistics())
    return lines
end

function Scheduler:schedule_lines(queries)
    local lines = {}
    for _, student in ipairs(queries) do
        if not self.student_courses[student] then
            lines[#lines + 1] = "STUDENT " .. student .. " not found"
        else
            local ids = self.student_courses[student]
            local assigned = self:student_assignments(student)
            local _, penalty = self:student_penalty(student)
            lines[#lines + 1] = format("STUDENT %s exams %d scheduled %d penalty %d", student, #ids, #assigned, penalty)
            for _, item in ipairs(assigned) do
                local placement = self.placements[item[2]]
                local course, offset = placement.course, 0
                for index, enrolled in ipairs(course.students) do
                    if enrolled == student then offset = index - 1; break end
                end
                lines[#lines + 1] = format("  %s %s room %s seat %d %s", self.calendar:name(item[1]),
                    course.id, placement.room.id, placement.first_seat + offset, course.name)
            end
            for _, id in ipairs(ids) do
                if not self.assignment[id] then lines[#lines + 1] = "  UNSCHEDULED " .. id .. " " .. self.courses[id].name end
            end
            for _, pair in ipairs(self:student_pairs(student)) do
                lines[#lines + 1] = format("  %s %s %s %s %s", RELATIONS[pair[1]]:upper(),
                    self.calendar:name(pair[2]), pair[3], self.calendar:name(pair[4]), pair[5])
            end
            for _, slot in ipairs(sorted_keys(self.calendar.unavailable[student] or {})) do
                lines[#lines + 1] = "  UNAVAILABLE " .. self.calendar:name(slot)
            end
        end
    end
    return lines
end

function Scheduler:status_lines()
    local contributions = self:contributions()
    local lines = {"course,status,slot,students,minutes,degree,penalty"}
    for _, id in ipairs(sorted_keys(self.courses)) do
        local course, status = self.courses[id]
        if self.calendar.fixed[id] then status = "fixed"
        elseif self.assignment[id] then status = "scheduled"
        elseif contains(self.oversized, id) then status = "too_large"
        elseif contains(self.empty, id) then status = "empty"
        else status = "no_slot" end
        local slot = self.assignment[id] and self.calendar:name(self.assignment[id]) or "-"
        lines[#lines + 1] = format("%s,%s,%s,%d,%d,%d,%d", id, status, slot, course:size(),
            course.duration, self.graph:degree(id), contributions[id] or 0)
    end
    return lines
end

function Scheduler:graph_lines()
    local graph, shared = self.graph, 0
    local vertices, edge_count = #graph.vertices, #self.edges
    for _, edge in ipairs(self.edges) do shared = shared + edge[3] end
    local density = vertices >= 2 and (2000 * edge_count // (vertices * (vertices - 1))) or 0
    local lines = {format("GRAPH courses %d edges %d shared %d density %d", vertices, edge_count, shared, density)}
    local ranked = self:by_degree(graph.vertices)
    for index = 1, math.min(5, #ranked) do
        local id = ranked[index]
        lines[#lines + 1] = format("DEGREE %s neighbours %d shared %d students %d", id,
            graph:degree(id), graph:shared_total(id), self.courses[id]:size())
    end
    local components = graph:components()
    lines[#lines + 1] = "COMPONENTS " .. #components
    for number, component in ipairs(components) do
        lines[#lines + 1] = format("COMPONENT %d size %d first %s", number, #component, component[1])
    end
    local clique = graph:greedy_clique(self.schedulable)
    local parts = {"CLIQUE", "size", tostring(#clique)}
    extend(parts, clique)
    lines[#lines + 1] = table.concat(parts, " ")
    return lines
end

function Scheduler:capacity_lines()
    local most, attaining, demand, capacity = 0, 0, 0, 0
    for _, ids in pairs(self.student_courses) do
        if #ids > most then most, attaining = #ids, 1
        elseif #ids == most then attaining = attaining + 1 end
    end
    for _, id in ipairs(self.schedulable) do demand = demand + self.courses[id]:size() end
    for _, room in ipairs(self.rooms) do capacity = capacity + room.capacity end
    local lines = {
        format("LOAD max_exams %d students %d", most, attaining),
        format("SEATS demand %d capacity %d min_slots %d", demand, capacity, ceil_div(demand, capacity)),
        "HEURISTIC largest_degree slots " .. coloring.greedy_numbering(self:by_degree(self.schedulable), self.graph),
        "HEURISTIC largest_enrolment slots " .. coloring.greedy_numbering(self:by_size(self.schedulable), self.graph)
    }
    local ranked, table_ids = self:by_size(self.graph.vertices), {}
    for index = 1, math.min(8, #ranked) do table_ids[#table_ids + 1] = ranked[index] end
    lines[#lines + 1] = report.fixed_width_line("MATRIX", table_ids, 9, 9)
    for _, row in ipairs(table_ids) do
        local cells, neighbours = {}, self.graph:neighbours(row)
        for _, column in ipairs(table_ids) do
            cells[#cells + 1] = row == column and "-" or tostring(neighbours[column] or 0)
        end
        lines[#lines + 1] = report.fixed_width_line(row, cells, 9, 9)
    end
    return lines
end

function Scheduler:report_lines()
    local calendar, enrolments = self.calendar, 0
    for _, ids in pairs(self.student_courses) do enrolments = enrolments + #ids end
    local lines = {format("INPUT courses %d enrolments %d rooms %d students %d errors %d", count(self.courses),
        enrolments, #self.rooms, count(self.student_courses), #self.errors)}
    for _, error in ipairs(self.errors) do lines[#lines + 1] = "ERROR " .. error end
    extend(lines, self:graph_lines())
    extend(lines, self:capacity_lines())
    for _, id in ipairs(self.empty) do lines[#lines + 1] = "EMPTY " .. id end
    for _, id in ipairs(self.oversized) do
        lines[#lines + 1] = format("TOO_LARGE %s students %d largest_room %d", id, self.courses[id]:size(), self.largest_room)
    end
    for _, slot in ipairs(sorted_keys(calendar.closed)) do lines[#lines + 1] = "CLOSED " .. calendar:name(slot) end
    for _, id in ipairs(sorted_keys(calendar.fixed)) do lines[#lines + 1] = "FIXED " .. id .. " " .. calendar:name(calendar.fixed[id]) end
    for _, order in ipairs(calendar.orders) do lines[#lines + 1] = "AFTER " .. order[1] .. " " .. order[2] end
    for number, attempt in ipairs(self.attempts) do
        local result = attempt[3] and ("failed " .. attempt[3]) or "success"
        lines[#lines + 1] = format("ATTEMPT %d courses %d backtracks %d %s", number, attempt[1], attempt[2], result)
    end
    for number, chosen in ipairs(self.assignment_order) do
        lines[#lines + 1] = format("ORDER %d %s %s saturation %d degree %d", number, chosen[1],
            calendar:name(chosen[2]), chosen[3], self.graph:degree(chosen[1]))
    end
    for _, insertion in ipairs(self.insertions) do
        lines[#lines + 1] = format("INSERTED %s %s penalty %d", insertion[1], calendar:name(insertion[2]), insertion[3])
    end
    local unscheduled = self:unscheduled()
    for _, id in ipairs(unscheduled) do
        local reason = contains(self.oversized, id) and "too_large" or "no_slot"
        lines[#lines + 1] = format("UNSCHEDULED %s reason %s students %d", id, reason, self.courses[id]:size())
        for slot, slot_reason in ipairs(self.reasons[id] or {}) do
            lines[#lines + 1] = "  " .. calendar:name(slot) .. " " .. slot_reason
        end
    end
    local slots_used = {}
    for _, slot in pairs(self.assignment) do slots_used[slot] = true end
    lines[#lines + 1] = format("SUMMARY scheduled %d unscheduled %d slots_used %d penalty %d", count(self.assignment),
        #unscheduled, count(slots_used), self.penalty)
    return lines
end

local function main()
    local errors = {}
    local courses = enrolment.load_courses("input/courses.csv", errors)
    local student_courses = enrolment.load_enrolments("input/enrolments.csv", courses, errors)
    local room_list = rooms.load_rooms("input/rooms.csv", errors)
    local calendar_lines = read_lines("calendar.txt")
    local scheduler = Scheduler.new(courses, student_courses, room_list, Calendar.new(calendar_lines), errors)
    scheduler:validate_calendar(calendar_lines)
    scheduler:build_timetable()
    scheduler:insert_excluded()
    scheduler:exchange_slots()
    scheduler:swap_chains()
    scheduler:assign_rooms()
    local queries = read_lines("queries.txt")
    report.write_files("output", {
        {"timetable.txt", scheduler:timetable_lines()},
        {"rooms.csv", scheduler:room_lines()},
        {"penalties.txt", scheduler:penalty_lines()},
        {"student_schedules.txt", scheduler:schedule_lines(queries)},
        {"course_status.csv", scheduler:status_lines()},
        {"report.txt", scheduler:report_lines()}
    })
end

main()
