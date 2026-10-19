local DAYS = {"MO", "TU", "WE", "TH", "FR", "SA", "SU"}
local DAY_INDEX = {}
for i, name in ipairs(DAYS) do DAY_INDEX[name] = i end
local GRADE_POINTS = {A = 4, B = 3, C = 2, D = 1, F = 0}
local courses = {}
local students = {}
local output = {}
local command_number = 0

local function sorted_keys(map)
    local result = {}
    for key in pairs(map) do result[#result + 1] = key end
    table.sort(result)
    return result
end

local function count_keys(map)
    local total = 0
    for _ in pairs(map) do total = total + 1 end
    return total
end

local function words(...)
    local args = {...}
    for i, value in ipairs(args) do args[i] = tostring(value) end
    return table.concat(args, " ")
end

local function emit(...)
    output[#output + 1] = words(...)
end

local function emit_indented(...)
    output[#output + 1] = "  " .. words(...)
end

local function fail(message)
    error({reason = message}, 0)
end

local function separated(text, separator)
    local result = {}
    local start = 1
    while true do
        local first, last = text:find(separator, start, true)
        if not first then
            result[#result + 1] = text:sub(start)
            break
        end
        result[#result + 1] = text:sub(start, first - 1)
        start = last + 1
    end
    return result
end

local function time_text(minutes)
    return string.format("%02d:%02d", math.floor(minutes / 60), minutes % 60)
end

local function rate_text(count, capacity)
    return capacity == 0 and "n/a" or math.floor(count * 100 / capacity) .. "%"
end

local function course_word(word)
    local department, digits = word:match("^([A-Z]+)(%d%d%d)$")
    return department ~= nil and #department >= 2 and #department <= 4 and #digits == 3
end

local function year_word(word)
    return word:match("^Y[1-9]$") ~= nil
end

local function expression(kind, children, word)
    local references = {}
    if kind == "WORD" and not year_word(word) then
        references[word] = true
    end
    for _, child in ipairs(children or {}) do
        for code in pairs(child.references) do
            references[code] = true
        end
    end
    return {kind = kind, children = children or {}, word = word, references = references}
end

local function combine(kind, children)
    local flattened = {}
    for _, child in ipairs(children) do
        if child.kind == kind then
            for _, nested in ipairs(child.children) do
                flattened[#flattened + 1] = nested
            end
        else
            flattened[#flattened + 1] = child
        end
    end
    if #flattened == 1 then return flattened[1] end
    return expression(kind, flattened)
end

local function prerequisite(code, text)
    if text == "-" then return expression("TRUE") end
    local tokens = {}
    local position = 1
    while position <= #text do
        local symbol = text:sub(position, position)
        if symbol == "&" or symbol == "|" or symbol == "(" or symbol == ")" then
            tokens[#tokens + 1] = symbol
            position = position + 1
        else
            local word = text:match("^([A-Z0-9]+)", position)
            if not word or not (course_word(word) or year_word(word)) then
                fail("invalid prereq " .. code)
            end
            tokens[#tokens + 1] = word
            position = position + #word
        end
    end

    local next_token = 1
    local function peek() return tokens[next_token] end
    local parse_expression

    local function factor()
        local token = peek()
        if not token or token == "&" or token == "|" or token == ")" then
            fail("invalid prereq " .. code)
        end
        next_token = next_token + 1
        if token == "(" then
            local child = parse_expression()
            if peek() ~= ")" then fail("invalid prereq " .. code) end
            next_token = next_token + 1
            return child
        end
        return expression("WORD", nil, token)
    end

    local function term()
        local children = {factor()}
        while peek() == "&" do
            next_token = next_token + 1
            children[#children + 1] = factor()
        end
        return combine("AND", children)
    end

    parse_expression = function()
        local children = {term()}
        while peek() == "|" do
            next_token = next_token + 1
            children[#children + 1] = term()
        end
        return combine("OR", children)
    end

    local result = parse_expression()
    if peek() then fail("invalid prereq " .. code) end
    if result.references[code] then fail("self prereq " .. code) end
    return result
end

local function canonical(node)
    if node.kind == "TRUE" then return "-" end
    if node.kind == "WORD" then return node.word end
    local parts = {}
    for _, child in ipairs(node.children) do
        local text = canonical(child)
        if node.kind == "AND" and child.kind == "OR" then
            text = "(" .. text .. ")"
        end
        parts[#parts + 1] = text
    end
    return table.concat(parts, node.kind == "AND" and "&" or "|")
end

local function satisfied(node, student)
    if node.kind == "TRUE" then return true end
    if node.kind == "WORD" then
        if year_word(node.word) then
            return student.year >= tonumber(node.word:sub(2))
        end
        return student.passed[node.word] ~= nil
    end
    if node.kind == "AND" then
        for _, child in ipairs(node.children) do
            if not satisfied(child, student) then return false end
        end
        return true
    end
    for _, child in ipairs(node.children) do
        if satisfied(child, student) then return true end
    end
    return false
end

local function parse_slot(text)
    local day = text:sub(1, 2)
    local sh = tonumber(text:sub(3, 4))
    local sm = tonumber(text:sub(5, 6))
    local eh = tonumber(text:sub(8, 9))
    local em = tonumber(text:sub(10, 11))
    local first = sh * 60 + sm
    local last = eh * 60 + em
    if not DAY_INDEX[day] or sh > 23 or sm > 59 or eh > 23 or em > 59 or
       first >= last then
        fail("invalid slot " .. text)
    end
    return {day = DAY_INDEX[day], start = first, finish = last, original = text}
end

local function overlap(a, b)
    return a.day == b.day and a.start < b.finish and b.start < a.finish
end

local function slot_text(slot)
    return time_text(slot.start) .. "-" .. time_text(slot.finish)
end

local function weekly(course)
    local total = 0
    for _, slot in ipairs(course.slots) do
        total = total + slot.finish - slot.start
    end
    return total
end

local function department(code)
    return code:sub(1, #code - 3)
end

local function status(course)
    return course.open and "open" or "closed"
end

local function earned(student)
    local total = 0
    for _, record in pairs(student.records) do
        if record.grade ~= "F" then total = total + record.credits end
    end
    return total
end

local function gpa(student)
    if count_keys(student.records) == 0 then return "n/a" end
    local points, credits = 0, 0
    for _, record in pairs(student.records) do
        points = points + GRADE_POINTS[record.grade] * record.credits
        credits = credits + record.credits
    end
    local value = math.floor((200 * points + credits) / (2 * credits))
    return string.format("%d.%02d", math.floor(value / 100), value % 100)
end

local function require_student(identifier)
    if not students[identifier] then fail("unknown student " .. identifier) end
    return students[identifier]
end

local function require_course(code)
    if not courses[code] then fail("unknown course " .. code) end
    return courses[code]
end

local function record(student, event)
    student.history[#student.history + 1] = {command_number, event}
end

local function conflict(student, course, excluded)
    local best
    for code in pairs(student.courses) do
        if code ~= excluded and course.conflicts[code] and
           (not best or code < best) then
            best = code
        end
    end
    return best
end

local function decision(kind, ...)
    return {kind = kind, extra = {...}}
end

local function decision_text(result)
    local parts = {result.kind}
    for _, item in ipairs(result.extra) do
        parts[#parts + 1] = tostring(item)
    end
    return table.concat(parts, " ")
end

local function eligibility(student, course, excluded)
    if not course.open then return decision("course closed") end
    if student.courses[course.code] then return decision("already enrolled") end
    if student.waiting[course.code] then return decision("already waitlisted") end
    if student.passed[course.code] then
        return decision("already completed", student.passed[course.code])
    end
    if not satisfied(course.prerequisite, student) then
        return decision("prereq not met")
    end
    local occupied = conflict(student, course, excluded)
    if occupied then return decision("time conflict", occupied) end
    local credits = student.credits + course.credits
    if excluded then credits = credits - courses[excluded].credits end
    if credits > student.limit then
        return decision("credit limit", credits, student.limit)
    end
    return decision("OK")
end

local function wait_position(student, course)
    local position = 1
    for _, id in ipairs(course.waitlist) do
        if students[id].year >= student.year then position = position + 1 end
    end
    return position
end

local function request(student, course)
    local outcome = eligibility(student, course)
    if outcome.kind ~= "OK" then return outcome end
    if count_keys(course.enrolled) < course.capacity then
        return decision("enroll")
    end
    if count_keys(student.waiting) >= 3 then return decision("waitlist limit") end
    return decision("waitlist", wait_position(student, course))
end

local function fail_request(result, student, course)
    local extra = {}
    for _, item in ipairs(result.extra) do extra[#extra + 1] = tostring(item) end
    fail(result.kind .. " " .. student.id .. " " .. course.code ..
         (#extra > 0 and " " .. table.concat(extra, " ") or ""))
end

local function enroll(student, course)
    course.enrolled[student.id] = true
    student.courses[course.code] = true
    student.credits = student.credits + course.credits
end

local function withdraw(student, course)
    course.enrolled[student.id] = nil
    student.courses[course.code] = nil
    student.credits = student.credits - course.credits
end

local function unlist_student(student, course)
    for position, id in ipairs(course.waitlist) do
        if id == student.id then
            table.remove(course.waitlist, position)
            break
        end
    end
    student.waiting[course.code] = nil
end

local function promotion()
    for _, code in ipairs(sorted_keys(courses)) do
        local course = courses[code]
        if course.open then
            local waiting = {table.unpack(course.waitlist)}
            for _, id in ipairs(waiting) do
                if count_keys(course.enrolled) >= course.capacity then break end
                local student = students[id]
                if not conflict(student, course) and
                   student.credits + course.credits <= student.limit then
                    unlist_student(student, course)
                    enroll(student, course)
                    record(student, "promote " .. code)
                    emit_indented("PROMOTE", id, code, "enrolled",
                        count_keys(course.enrolled) .. "/" .. course.capacity,
                        "credits", student.credits .. "/" .. student.limit)
                end
            end
        end
    end
end

local function cmd_course(args)
    local code, credits, capacity, timetable, text = table.unpack(args)
    if courses[code] then fail("duplicate course " .. code) end
    local slots = {}
    if timetable ~= "-" then
        for _, value in ipairs(separated(timetable, ",")) do
            slots[#slots + 1] = parse_slot(value)
        end
    end
    for i = 1, #slots do
        for j = i + 1, #slots do
            if overlap(slots[i], slots[j]) then
                fail("overlapping slots " .. slots[i].original .. " " .. slots[j].original)
            end
        end
    end
    local required = prerequisite(code, text)
    local course = {
        code = code, credits = tonumber(credits), capacity = tonumber(capacity),
        slots = slots, prerequisite = required, open = true,
        enrolled = {}, waitlist = {}, conflicts = {}
    }
    for other_code, other in pairs(courses) do
        local overlapping = false
        for _, first in ipairs(slots) do
            for _, second in ipairs(other.slots) do
                if overlap(first, second) then overlapping = true end
            end
        end
        if overlapping then
            course.conflicts[other_code] = true
            other.conflicts[code] = true
        end
    end
    courses[code] = course
    emit("COURSE", code, "credits", credits, "capacity", capacity,
         "meetings", #slots, "weekly", time_text(weekly(course)),
         "prereq", canonical(required))
end

local function cmd_student(args)
    local id, year, limit, text = table.unpack(args)
    if students[id] then fail("duplicate student " .. id) end
    local records = {}
    if text ~= "-" then
        for _, entry in ipairs(separated(text, ",")) do
            local parts = separated(entry, ":")
            local code, grade, credits = table.unpack(parts)
            if not GRADE_POINTS[grade] then
                fail("invalid grade " .. id .. " " .. code .. " " .. grade)
            end
            if records[code] then fail("duplicate record " .. id .. " " .. code) end
            records[code] = {grade = grade, credits = tonumber(credits)}
        end
    end
    local student = {
        id = id, year = tonumber(year), limit = tonumber(limit),
        records = records, passed = {}, courses = {}, waiting = {},
        credits = 0, history = {}
    }
    for code, entry in pairs(records) do
        if entry.grade == "A" or entry.grade == "B" or entry.grade == "C" then
            student.passed[code] = entry.grade
        end
    end
    students[id] = student
    emit("STUDENT", id, "year", year, "limit", limit,
         "records", count_keys(records), "earned", earned(student), "gpa", gpa(student))
end

local function cmd_enroll(args)
    local student = require_student(args[1])
    local course = require_course(args[2])
    local outcome = request(student, course)
    if outcome.kind ~= "enroll" and outcome.kind ~= "waitlist" then
        fail_request(outcome, student, course)
    end
    if outcome.kind == "enroll" then
        enroll(student, course)
        record(student, "enroll " .. course.code)
        emit("ENROLL", student.id, course.code, "enrolled",
             count_keys(course.enrolled) .. "/" .. course.capacity,
             "credits", student.credits .. "/" .. student.limit)
    else
        local position = outcome.extra[1]
        table.insert(course.waitlist, position, student.id)
        student.waiting[course.code] = true
        record(student, "waitlist " .. course.code .. " " .. position)
        emit("ENROLL", student.id, course.code, "waitlist", position)
    end
end

local function cmd_check(args)
    local student = require_student(args[1])
    local course = require_course(args[2])
    emit("CHECK", student.id, course.code, decision_text(request(student, course)))
end

local function cmd_options(args)
    local student = require_student(args[1])
    emit("OPTIONS", student.id, "courses", count_keys(courses))
    for _, code in ipairs(sorted_keys(courses)) do
        emit_indented(code, decision_text(request(student, courses[code])))
    end
end

local function cmd_drop(args)
    local student = require_student(args[1])
    local course = require_course(args[2])
    if student.courses[course.code] then
        withdraw(student, course)
        record(student, "drop " .. course.code)
        emit("DROP", student.id, course.code, "enrolled",
             count_keys(course.enrolled) .. "/" .. course.capacity,
             "credits", student.credits .. "/" .. student.limit)
    elseif student.waiting[course.code] then
        unlist_student(student, course)
        record(student, "drop " .. course.code .. " waitlist")
        emit("DROP", student.id, course.code, "waitlist removed")
    else
        fail("not registered " .. student.id .. " " .. course.code)
    end
    promotion()
end

local function cmd_swap(args)
    local student = require_student(args[1])
    local source = require_course(args[2])
    local destination = require_course(args[3])
    if not student.courses[source.code] then
        fail("not enrolled " .. student.id .. " " .. source.code)
    end
    if source.code == destination.code then fail("same course " .. source.code) end
    local outcome = eligibility(student, destination, source.code)
    if outcome.kind ~= "OK" then fail_request(outcome, student, destination) end
    if count_keys(destination.enrolled) >= destination.capacity then
        fail("course full " .. destination.code)
    end
    withdraw(student, source)
    enroll(student, destination)
    record(student, "swap " .. source.code .. " " .. destination.code)
    emit("SWAP", student.id, source.code, "->", destination.code,
         "credits", student.credits .. "/" .. student.limit)
    promotion()
end

local function cmd_close(args)
    local course = require_course(args[1])
    if not course.open then fail("already closed " .. course.code) end
    course.open = false
    emit("CLOSE", course.code, "enrolled",
         count_keys(course.enrolled) .. "/" .. course.capacity,
         "waitlist", #course.waitlist)
end

local function cmd_open(args)
    local course = require_course(args[1])
    if course.open then fail("already open " .. course.code) end
    course.open = true
    emit("OPEN", course.code, "enrolled",
         count_keys(course.enrolled) .. "/" .. course.capacity,
         "waitlist", #course.waitlist)
    promotion()
end

local function cmd_capacity(args)
    local course = require_course(args[1])
    local capacity = tonumber(args[2])
    if capacity < count_keys(course.enrolled) then
        fail("capacity below enrollment " .. course.code .. " " ..
             count_keys(course.enrolled))
    end
    local previous = course.capacity
    course.capacity = capacity
    emit("CAPACITY", course.code, previous, "->", capacity)
    promotion()
end

local function cmd_limit(args)
    local student = require_student(args[1])
    local limit = tonumber(args[2])
    if limit < student.credits then
        fail("limit below enrolled " .. student.id .. " " .. student.credits)
    end
    local previous = student.limit
    student.limit = limit
    emit("LIMIT", student.id, previous, "->", limit)
    promotion()
end

local function cmd_prereq(args)
    local course = require_course(args[1])
    local required = prerequisite(course.code, args[2])
    course.prerequisite = required
    emit("PREREQ", course.code, canonical(required))
    local waiting = {table.unpack(course.waitlist)}
    for _, id in ipairs(waiting) do
        local student = students[id]
        if not satisfied(required, student) then
            unlist_student(student, course)
            record(student, "unlist " .. course.code)
            emit_indented("UNLIST", student.id, course.code)
        end
    end
end

local function cmd_cancel(args)
    local course = require_course(args[1])
    local code = course.code
    emit("CANCEL", code, "enrolled", count_keys(course.enrolled),
         "waitlist", #course.waitlist)
    for id in pairs(course.enrolled) do
        local student = students[id]
        student.courses[code] = nil
        student.credits = student.credits - course.credits
        record(student, "cancel " .. code)
    end
    for _, id in ipairs(course.waitlist) do
        local student = students[id]
        student.waiting[code] = nil
        record(student, "cancel " .. code .. " waitlist")
    end
    for other_code in pairs(course.conflicts) do
        courses[other_code].conflicts[code] = nil
    end
    courses[code] = nil
    promotion()
end

local function cmd_roster(args)
    local course = require_course(args[1])
    emit("ROSTER", course.code, status(course), "enrolled",
         count_keys(course.enrolled) .. "/" .. course.capacity,
         "waitlist", #course.waitlist)
    for _, id in ipairs(sorted_keys(course.enrolled)) do
        emit_indented("enrolled", id, "year", students[id].year)
    end
    for position, id in ipairs(course.waitlist) do
        emit_indented("waitlist", position, id, "year", students[id].year)
    end
end

local function student_slots(student, day)
    local slots = {}
    for code in pairs(student.courses) do
        for _, slot in ipairs(courses[code].slots) do
            if slot.day == day then
                slots[#slots + 1] = {
                    start = slot.start, finish = slot.finish, code = code
                }
            end
        end
    end
    table.sort(slots, function(a, b)
        if a.start ~= b.start then return a.start < b.start end
        if a.finish ~= b.finish then return a.finish < b.finish end
        return a.code < b.code
    end)
    return slots
end

local function cmd_schedule(args)
    local student = require_student(args[1])
    local duration = 0
    for code in pairs(student.courses) do duration = duration + weekly(courses[code]) end
    emit("SCHEDULE", student.id, "courses", count_keys(student.courses),
         "credits", student.credits, "weekly", time_text(duration))
    for day, name in ipairs(DAYS) do
        local slots = student_slots(student, day)
        if #slots > 0 then
            local parts = {name}
            for _, slot in ipairs(slots) do
                parts[#parts + 1] = time_text(slot.start) .. "-" .. time_text(slot.finish)
                parts[#parts + 1] = slot.code
            end
            emit_indented(table.unpack(parts))
        end
    end
    local tba = {}
    for code in pairs(student.courses) do
        if #courses[code].slots == 0 then tba[#tba + 1] = code end
    end
    table.sort(tba)
    if #tba > 0 then
        emit_indented("TBA", table.unpack(tba))
    end
end

local function cmd_free(args)
    local student = require_student(args[1])
    local day = DAY_INDEX[args[2]]
    if not day then fail("invalid day " .. args[2]) end
    local occupied = {}
    for _, slot in ipairs(student_slots(student, day)) do
        local first, last = math.max(480, slot.start), math.min(1320, slot.finish)
        if first < last then occupied[#occupied + 1] = {first, last} end
    end
    local free, cursor = {}, 480
    for _, interval in ipairs(occupied) do
        if cursor < interval[1] then
            free[#free + 1] = {cursor, interval[1]}
        end
        cursor = math.max(cursor, interval[2])
    end
    if cursor < 1320 then free[#free + 1] = {cursor, 1320} end
    local minutes = 0
    for _, interval in ipairs(free) do
        minutes = minutes + interval[2] - interval[1]
    end
    local parts = {"FREE", student.id, args[2], "total", time_text(minutes)}
    for _, interval in ipairs(free) do
        parts[#parts + 1] = time_text(interval[1]) .. "-" .. time_text(interval[2])
    end
    emit(table.unpack(parts))
end

local function cmd_info(args)
    local course = require_course(args[1])
    emit("INFO", course.code, status(course), "credits", course.credits,
         "capacity", course.capacity, "prereq", canonical(course.prerequisite))
    local slots = {table.unpack(course.slots)}
    table.sort(slots, function(a, b)
        if a.day ~= b.day then return a.day < b.day end
        return a.start < b.start
    end)
    if #slots == 0 then
        emit_indented("meet TBA")
    else
        for _, slot in ipairs(slots) do
            emit_indented("meet", DAYS[slot.day], slot_text(slot))
        end
    end
    local required_by = {}
    for code, other in pairs(courses) do
        if other.prerequisite.references[course.code] then
            required_by[#required_by + 1] = code
        end
    end
    table.sort(required_by)
    if #required_by == 0 then required_by = {"none"} end
    emit_indented("required by", table.unpack(required_by))
end

local function cmd_audit(args)
    local student = require_student(args[1])
    emit("AUDIT", student.id, "year", student.year, "limit", student.limit)
    for _, code in ipairs(sorted_keys(student.records)) do
        local entry = student.records[code]
        emit_indented("record", code, entry.grade, entry.credits)
    end
    emit_indented("earned", earned(student), "gpa", gpa(student))
    for _, code in ipairs(sorted_keys(student.courses)) do
        emit_indented("enrolled", code, courses[code].credits)
    end
    emit_indented("credits", student.credits, "remaining", student.limit - student.credits)
    for _, code in ipairs(sorted_keys(student.waiting)) do
        for position, id in ipairs(courses[code].waitlist) do
            if id == student.id then
                emit_indented("waitlist", code, position)
                break
            end
        end
    end
end

local function cmd_history(args)
    local student = require_student(args[1])
    emit("HISTORY", student.id, "events", #student.history)
    for _, entry in ipairs(student.history) do
        emit_indented(entry[1], entry[2])
    end
end

local function cmd_students()
    emit("STUDENTS", count_keys(students))
    for _, id in ipairs(sorted_keys(students)) do
        local student = students[id]
        emit_indented(id, "year", student.year,
            "credits", student.credits .. "/" .. student.limit,
            "courses", count_keys(student.courses),
            "waitlists", count_keys(student.waiting))
    end
end

local function group_counts(group)
    local enrolled, capacity, waitlisted = 0, 0, 0
    for _, course in ipairs(group) do
        enrolled = enrolled + count_keys(course.enrolled)
        capacity = capacity + course.capacity
        waitlisted = waitlisted + #course.waitlist
    end
    return words("enrolled", enrolled .. "/" .. capacity,
                 "rate", rate_text(enrolled, capacity), "waitlisted", waitlisted)
end

local function cmd_report()
    local all, departments = {}, {}
    for _, code in ipairs(sorted_keys(courses)) do
        local course = courses[code]
        all[#all + 1] = course
        local dept = department(code)
        departments[dept] = departments[dept] or {}
        departments[dept][#departments[dept] + 1] = course
    end
    emit("REPORT", "courses", count_keys(courses), group_counts(all))
    for _, code in ipairs(sorted_keys(courses)) do
        local course = courses[code]
        emit_indented(code, status(course),
            count_keys(course.enrolled) .. "/" .. course.capacity,
            rate_text(count_keys(course.enrolled), course.capacity),
            "waitlist", #course.waitlist)
    end
    for _, dept in ipairs(sorted_keys(departments)) do
        emit_indented("dept", dept, "courses", #departments[dept],
                      group_counts(departments[dept]))
    end
end

local handlers = {
    COURSE = cmd_course, STUDENT = cmd_student, ENROLL = cmd_enroll,
    CHECK = cmd_check, OPTIONS = cmd_options, DROP = cmd_drop,
    SWAP = cmd_swap, CLOSE = cmd_close, OPEN = cmd_open,
    CAPACITY = cmd_capacity, LIMIT = cmd_limit, PREREQ = cmd_prereq,
    CANCEL = cmd_cancel, ROSTER = cmd_roster, SCHEDULE = cmd_schedule,
    FREE = cmd_free, INFO = cmd_info, AUDIT = cmd_audit,
    HISTORY = cmd_history, STUDENTS = cmd_students, REPORT = cmd_report
}

local count = tonumber(io.read("*l"))
for number = 1, count do
    command_number = number
    local line = io.read("*l")
    local fields = separated(line, " ")
    local cmd = fields[1]
    local arguments = {}
    for i = 2, #fields do arguments[#arguments + 1] = fields[i] end
    local ok, reason = pcall(handlers[cmd], arguments)
    if not ok then
        if type(reason) == "table" and reason.reason then
            emit("ERROR", reason.reason)
        else
            error(reason)
        end
    end
end
for _, line in ipairs(output) do io.write(line, "\n") end
