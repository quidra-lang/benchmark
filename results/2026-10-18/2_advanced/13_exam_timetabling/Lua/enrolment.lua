local M = {}

local Course = {}
Course.__index = Course

function Course:size()
    return #self.students
end

function M.read_records(path)
    local records = {}
    local number = 0
    for line in io.lines(path) do
        number = number + 1
        if number > 1 then
            local fields = {}
            for field in (line .. ","):gmatch("(.-),") do
                fields[#fields + 1] = field
            end
            records[#records + 1] = {number, fields}
        end
    end
    return records
end

function M.load_courses(path, errors)
    local courses = {}
    for _, record in ipairs(M.read_records(path)) do
        local number, fields = record[1], record[2]
        local id = fields[1]
        if courses[id] then
            errors[#errors + 1] = string.format("courses.csv line %d: duplicate course %s", number, id)
        else
            courses[id] = setmetatable({id = id, duration = tonumber(fields[2]), name = fields[3], students = {}}, Course)
        end
    end
    return courses
end

function M.load_enrolments(path, courses, errors)
    local accepted, student_courses = {}, {}
    for _, record in ipairs(M.read_records(path)) do
        local number, fields = record[1], record[2]
        local student, id = fields[1], fields[2]
        local pair = student .. "," .. id
        if not courses[id] then
            errors[#errors + 1] = string.format("enrolments.csv line %d: unknown course %s", number, id)
        elseif accepted[pair] then
            errors[#errors + 1] = string.format("enrolments.csv line %d: duplicate enrolment %s %s", number, student, id)
        else
            accepted[pair] = true
            local roster = courses[id].students
            roster[#roster + 1] = student
            student_courses[student] = student_courses[student] or {}
            local list = student_courses[student]
            list[#list + 1] = id
        end
    end
    for _, course in pairs(courses) do
        table.sort(course.students)
    end
    for _, list in pairs(student_courses) do
        table.sort(list)
    end
    return student_courses
end

return M
