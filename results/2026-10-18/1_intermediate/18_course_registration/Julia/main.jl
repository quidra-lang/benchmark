using Printf

const DAYS = ["MO", "TU", "WE", "TH", "FR", "SA", "SU"]
const DAY_INDEX = Dict(day => i for (i, day) in enumerate(DAYS))
const GRADE_POINTS = Dict('A' => 4, 'B' => 3, 'C' => 2, 'D' => 1, 'F' => 0)

struct CommandError <: Exception
    reason::String
end
Base.showerror(io::IO, error::CommandError) = print(io, error.reason)
fail(reason::String) = throw(CommandError(reason))

struct ParseError <: Exception end

time_text(minutes::Int) = @sprintf("%02d:%02d", div(minutes, 60), mod(minutes, 60))
rate_text(count::Int, capacity::Int) = capacity == 0 ? "n/a" :
    string(div(100 * count, capacity), "%")
course_word(text::String) = occursin(r"^[A-Z]{2,4}[0-9]{3}$", text)
year_word(text::String) = occursin(r"^Y[1-9]$", text)

struct Expression
    kind::Symbol
    word::String
    children::Vector{Expression}
    references::Set{String}
end

true_expression() = Expression(:TRUE, "", Expression[], Set{String}())

function leaf(word::String)
    refs = year_word(word) ? Set{String}() : Set([word])
    Expression(:WORD, word, Expression[], refs)
end

function combine(kind::Symbol, children::Vector{Expression})
    flat = Expression[]
    for child in children
        if child.kind == kind
            append!(flat, child.children)
        else
            push!(flat, child)
        end
    end
    length(flat) == 1 && return flat[1]
    refs = Set{String}()
    for child in flat
        union!(refs, child.references)
    end
    Expression(kind, "", flat, refs)
end

mutable struct Parser
    tokens::Vector{String}
    position::Int
end

peek(parser::Parser) =
    parser.position > length(parser.tokens) ? "" : parser.tokens[parser.position]

function parse_factor!(parser::Parser)
    token = peek(parser)
    token == "" || token in ("&", "|", ")") && throw(ParseError())
    if token == "" || token in ("&", "|", ")")
        throw(ParseError())
    end
    parser.position += 1
    if token == "("
        node = parse_expression!(parser)
        peek(parser) == ")" || throw(ParseError())
        parser.position += 1
        return node
    end
    leaf(token)
end

function parse_term!(parser::Parser)
    children = Expression[parse_factor!(parser)]
    while peek(parser) == "&"
        parser.position += 1
        push!(children, parse_factor!(parser))
    end
    combine(:AND, children)
end

function parse_expression!(parser::Parser)
    children = Expression[parse_term!(parser)]
    while peek(parser) == "|"
        parser.position += 1
        push!(children, parse_term!(parser))
    end
    combine(:OR, children)
end

function prerequisite(code::String, text::String)
    text == "-" && return true_expression()
    tokens = String[String(match.match) for match in eachmatch(r"[A-Z0-9]+|[&|()]", text)]
    try
        for token in tokens
            if !(token in ("&", "|", "(", ")") || course_word(token) || year_word(token))
                throw(ParseError())
            end
        end
        parser = Parser(tokens, 1)
        result = parse_expression!(parser)
        parser.position == length(tokens) + 1 || throw(ParseError())
        code in result.references && fail("self prereq " * code)
        return result
    catch error
        error isa ParseError || rethrow()
        fail("invalid prereq " * code)
    end
end

function canonical(expr::Expression)
    expr.kind == :TRUE && return "-"
    expr.kind == :WORD && return expr.word
    separator = expr.kind == :AND ? "&" : "|"
    parts = String[]
    for child in expr.children
        text = canonical(child)
        if expr.kind == :AND && child.kind == :OR
            text = "(" * text * ")"
        end
        push!(parts, text)
    end
    join(parts, separator)
end

struct Slot
    day::Int
    start::Int
    finish::Int
    original::String
end

function make_slot(text::String)
    day = get(DAY_INDEX, text[1:2], 0)
    sh = parse(Int, text[3:4])
    sm = parse(Int, text[5:6])
    eh = parse(Int, text[8:9])
    em = parse(Int, text[10:11])
    first, last = sh * 60 + sm, eh * 60 + em
    if day == 0 || sh > 23 || sm > 59 || eh > 23 || em > 59 || first >= last
        fail("invalid slot " * text)
    end
    Slot(day, first, last, text)
end

overlaps(a::Slot, b::Slot) =
    a.day == b.day && a.start < b.finish && b.start < a.finish
slot_text(slot::Slot) = time_text(slot.start) * "-" * time_text(slot.finish)

mutable struct Course
    code::String
    credits::Int
    capacity::Int
    slots::Vector{Slot}
    required::Expression
    open::Bool
    enrolled::Set{String}
    waitlist::Vector{String}
    conflicts::Set{String}
end

weekly(course::Course) = sum(slot.finish - slot.start for slot in course.slots; init=0)
department(course::Course) = course.code[1:end-3]
status(course::Course) = course.open ? "open" : "closed"

mutable struct Student
    id::String
    year::Int
    limit::Int
    records::Dict{String, Tuple{Char, Int}}
    passed::Dict{String, Char}
    courses::Set{String}
    waiting::Set{String}
    credits::Int
    history::Vector{Tuple{Int, String}}
end

function Student(id::String, year::Int, limit::Int,
                 records::Dict{String, Tuple{Char, Int}})
    passed = Dict(code => grade for (code, (grade, _)) in records
                  if grade in ('A', 'B', 'C'))
    Student(id, year, limit, records, passed, Set{String}(),
            Set{String}(), 0, Tuple{Int, String}[])
end

earned(student::Student) =
    sum(grade == 'F' ? 0 : credits for (grade, credits) in values(student.records); init=0)

function gpa(student::Student)
    isempty(student.records) && return "n/a"
    points = sum(GRADE_POINTS[grade] * credits
                 for (grade, credits) in values(student.records))
    credits = sum(value for (_, value) in values(student.records))
    rounded = div(200 * points + credits, 2 * credits)
    @sprintf("%d.%02d", div(rounded, 100), mod(rounded, 100))
end

function satisfied(expr::Expression, student::Student)
    expr.kind == :TRUE && return true
    if expr.kind == :WORD
        return year_word(expr.word) ?
            student.year >= parse(Int, expr.word[2:end]) :
            haskey(student.passed, expr.word)
    elseif expr.kind == :AND
        return all(satisfied(child, student) for child in expr.children)
    end
    any(satisfied(child, student) for child in expr.children)
end

struct Decision
    kind::String
    extra::Vector{String}
end
decision(kind::String, extras...) = Decision(kind, string.(collect(extras)))
decision_text(value::Decision) = join(vcat([value.kind], value.extra), " ")

mutable struct Registrar
    courses::Dict{String, Course}
    students::Dict{String, Student}
    number::Int
    output::Vector{String}
end
Registrar() = Registrar(Dict{String, Course}(), Dict{String, Student}(), 0, String[])

function emit!(registrar::Registrar, parts...; indent::Int=0)
    push!(registrar.output, repeat(" ", indent) * join(string.(parts), " "))
end

function require_student(registrar::Registrar, id::String)
    haskey(registrar.students, id) || fail("unknown student " * id)
    registrar.students[id]
end

function require_course(registrar::Registrar, code::String)
    haskey(registrar.courses, code) || fail("unknown course " * code)
    registrar.courses[code]
end

function record!(registrar::Registrar, student::Student, event::String)
    push!(student.history, (registrar.number, event))
end

function conflict(student::Student, course::Course, excluded::String="")
    options = [code for code in student.courses
               if code != excluded && code in course.conflicts]
    isempty(options) ? nothing : minimum(options)
end

function eligibility(registrar::Registrar, student::Student, course::Course,
                     excluded::String="")
    !course.open && return decision("course closed")
    course.code in student.courses && return decision("already enrolled")
    course.code in student.waiting && return decision("already waitlisted")
    haskey(student.passed, course.code) &&
        return decision("already completed", student.passed[course.code])
    !satisfied(course.required, student) && return decision("prereq not met")
    occupied = conflict(student, course, excluded)
    occupied !== nothing && return decision("time conflict", occupied)
    credits = student.credits + course.credits
    if excluded != ""
        credits -= registrar.courses[excluded].credits
    end
    credits > student.limit && return decision("credit limit", credits, student.limit)
    decision("OK")
end

wait_position(registrar::Registrar, student::Student, course::Course) =
    1 + count(id -> registrar.students[id].year >= student.year, course.waitlist)

function request(registrar::Registrar, student::Student, course::Course)
    result = eligibility(registrar, student, course)
    result.kind != "OK" && return result
    length(course.enrolled) < course.capacity && return decision("enroll")
    length(student.waiting) >= 3 && return decision("waitlist limit")
    decision("waitlist", wait_position(registrar, student, course))
end

function fail_request(result::Decision, student::Student, course::Course)
    fail(join(vcat([result.kind, student.id, course.code], result.extra), " "))
end

function enroll!(student::Student, course::Course)
    push!(course.enrolled, student.id)
    push!(student.courses, course.code)
    student.credits += course.credits
end

function withdraw!(student::Student, course::Course)
    delete!(course.enrolled, student.id)
    delete!(student.courses, course.code)
    student.credits -= course.credits
end

function unlist!(student::Student, course::Course)
    position = findfirst(==(student.id), course.waitlist)
    position !== nothing && deleteat!(course.waitlist, position)
    delete!(student.waiting, course.code)
end

function promotion!(registrar::Registrar)
    for code in sort(collect(keys(registrar.courses)))
        course = registrar.courses[code]
        course.open || continue
        for id in copy(course.waitlist)
            length(course.enrolled) < course.capacity || break
            student = registrar.students[id]
            if conflict(student, course) !== nothing ||
               student.credits + course.credits > student.limit
                continue
            end
            unlist!(student, course)
            enroll!(student, course)
            record!(registrar, student, "promote " * code)
            emit!(registrar, "PROMOTE", id, code, "enrolled",
                  "$(length(course.enrolled))/$(course.capacity)",
                  "credits", "$(student.credits)/$(student.limit)"; indent=2)
        end
    end
end

function cmd_course!(r::Registrar, args::Vector{String})
    code, credits, capacity, timetable, text = args
    haskey(r.courses, code) && fail("duplicate course " * code)
    slots = timetable == "-" ? Slot[] :
        [make_slot(String(value)) for value in split(timetable, ',')]
    for i in 1:length(slots), j in (i+1):length(slots)
        if overlaps(slots[i], slots[j])
            fail("overlapping slots $(slots[i].original) $(slots[j].original)")
        end
    end
    required = prerequisite(code, text)
    course = Course(code, parse(Int, credits), parse(Int, capacity), slots, required,
                    true, Set{String}(), String[], Set{String}())
    for (other_code, other) in r.courses
        if any(overlaps(a, b) for a in slots for b in other.slots)
            push!(course.conflicts, other_code)
            push!(other.conflicts, code)
        end
    end
    r.courses[code] = course
    emit!(r, "COURSE", code, "credits", credits, "capacity", capacity,
          "meetings", length(slots), "weekly", time_text(weekly(course)),
          "prereq", canonical(required))
end

function cmd_student!(r::Registrar, args::Vector{String})
    id, year, limit, text = args
    haskey(r.students, id) && fail("duplicate student " * id)
    records = Dict{String, Tuple{Char, Int}}()
    if text != "-"
        for entry in split(text, ',')
            fields = split(entry, ':')
            code = String(fields[1])
            grade = only(fields[2])
            haskey(GRADE_POINTS, grade) || fail("invalid grade $id $code $grade")
            haskey(records, code) && fail("duplicate record $id $code")
            records[code] = (grade, parse(Int, fields[3]))
        end
    end
    student = Student(id, parse(Int, year), parse(Int, limit), records)
    r.students[id] = student
    emit!(r, "STUDENT", id, "year", year, "limit", limit,
          "records", length(records), "earned", earned(student), "gpa", gpa(student))
end

function cmd_enroll!(r::Registrar, args::Vector{String})
    s = require_student(r, args[1])
    c = require_course(r, args[2])
    result = request(r, s, c)
    result.kind in ("enroll", "waitlist") || fail_request(result, s, c)
    if result.kind == "enroll"
        enroll!(s, c)
        record!(r, s, "enroll " * c.code)
        emit!(r, "ENROLL", s.id, c.code, "enrolled",
              "$(length(c.enrolled))/$(c.capacity)",
              "credits", "$(s.credits)/$(s.limit)")
    else
        position = parse(Int, result.extra[1])
        insert!(c.waitlist, position, s.id)
        push!(s.waiting, c.code)
        record!(r, s, "waitlist $(c.code) $position")
        emit!(r, "ENROLL", s.id, c.code, "waitlist", position)
    end
end

function cmd_check!(r::Registrar, args::Vector{String})
    s = require_student(r, args[1])
    c = require_course(r, args[2])
    emit!(r, "CHECK", s.id, c.code, decision_text(request(r, s, c)))
end

function cmd_options!(r::Registrar, args::Vector{String})
    s = require_student(r, args[1])
    emit!(r, "OPTIONS", s.id, "courses", length(r.courses))
    for code in sort(collect(keys(r.courses)))
        emit!(r, code, decision_text(request(r, s, r.courses[code])); indent=2)
    end
end

function cmd_drop!(r::Registrar, args::Vector{String})
    s = require_student(r, args[1])
    c = require_course(r, args[2])
    if c.code in s.courses
        withdraw!(s, c)
        record!(r, s, "drop " * c.code)
        emit!(r, "DROP", s.id, c.code, "enrolled",
              "$(length(c.enrolled))/$(c.capacity)",
              "credits", "$(s.credits)/$(s.limit)")
    elseif c.code in s.waiting
        unlist!(s, c)
        record!(r, s, "drop $(c.code) waitlist")
        emit!(r, "DROP", s.id, c.code, "waitlist removed")
    else
        fail("not registered $(s.id) $(c.code)")
    end
    promotion!(r)
end

function cmd_swap!(r::Registrar, args::Vector{String})
    s = require_student(r, args[1])
    source = require_course(r, args[2])
    destination = require_course(r, args[3])
    source.code in s.courses || fail("not enrolled $(s.id) $(source.code)")
    source.code != destination.code || fail("same course " * source.code)
    result = eligibility(r, s, destination, source.code)
    result.kind == "OK" || fail_request(result, s, destination)
    length(destination.enrolled) < destination.capacity ||
        fail("course full " * destination.code)
    withdraw!(s, source)
    enroll!(s, destination)
    record!(r, s, "swap $(source.code) $(destination.code)")
    emit!(r, "SWAP", s.id, source.code, "->", destination.code, "credits",
          "$(s.credits)/$(s.limit)")
    promotion!(r)
end

function cmd_close!(r::Registrar, args::Vector{String})
    c = require_course(r, args[1])
    c.open || fail("already closed " * c.code)
    c.open = false
    emit!(r, "CLOSE", c.code, "enrolled", "$(length(c.enrolled))/$(c.capacity)",
          "waitlist", length(c.waitlist))
end

function cmd_open!(r::Registrar, args::Vector{String})
    c = require_course(r, args[1])
    !c.open || fail("already open " * c.code)
    c.open = true
    emit!(r, "OPEN", c.code, "enrolled", "$(length(c.enrolled))/$(c.capacity)",
          "waitlist", length(c.waitlist))
    promotion!(r)
end

function cmd_capacity!(r::Registrar, args::Vector{String})
    c = require_course(r, args[1])
    capacity = parse(Int, args[2])
    capacity >= length(c.enrolled) ||
        fail("capacity below enrollment $(c.code) $(length(c.enrolled))")
    previous = c.capacity
    c.capacity = capacity
    emit!(r, "CAPACITY", c.code, previous, "->", capacity)
    promotion!(r)
end

function cmd_limit!(r::Registrar, args::Vector{String})
    s = require_student(r, args[1])
    limit = parse(Int, args[2])
    limit >= s.credits || fail("limit below enrolled $(s.id) $(s.credits)")
    previous = s.limit
    s.limit = limit
    emit!(r, "LIMIT", s.id, previous, "->", limit)
    promotion!(r)
end

function cmd_prereq!(r::Registrar, args::Vector{String})
    c = require_course(r, args[1])
    expression = prerequisite(c.code, args[2])
    c.required = expression
    emit!(r, "PREREQ", c.code, canonical(expression))
    for id in copy(c.waitlist)
        s = r.students[id]
        if !satisfied(expression, s)
            unlist!(s, c)
            record!(r, s, "unlist " * c.code)
            emit!(r, "UNLIST", s.id, c.code; indent=2)
        end
    end
end

function cmd_cancel!(r::Registrar, args::Vector{String})
    c = require_course(r, args[1])
    code = c.code
    emit!(r, "CANCEL", code, "enrolled", length(c.enrolled),
          "waitlist", length(c.waitlist))
    for id in c.enrolled
        s = r.students[id]
        delete!(s.courses, code)
        s.credits -= c.credits
        record!(r, s, "cancel " * code)
    end
    for id in c.waitlist
        s = r.students[id]
        delete!(s.waiting, code)
        record!(r, s, "cancel $code waitlist")
    end
    for other in c.conflicts
        delete!(r.courses[other].conflicts, code)
    end
    delete!(r.courses, code)
    promotion!(r)
end

function cmd_roster!(r::Registrar, args::Vector{String})
    c = require_course(r, args[1])
    emit!(r, "ROSTER", c.code, status(c), "enrolled",
          "$(length(c.enrolled))/$(c.capacity)", "waitlist", length(c.waitlist))
    for id in sort(collect(c.enrolled))
        emit!(r, "enrolled", id, "year", r.students[id].year; indent=2)
    end
    for (position, id) in enumerate(c.waitlist)
        emit!(r, "waitlist", position, id, "year", r.students[id].year; indent=2)
    end
end

function student_slots(r::Registrar, s::Student, day::Int)
    slots = Tuple{Int, Int, String}[]
    for code in s.courses
        for slot in r.courses[code].slots
            if slot.day == day
                push!(slots, (slot.start, slot.finish, code))
            end
        end
    end
    sort!(slots)
end

function cmd_schedule!(r::Registrar, args::Vector{String})
    s = require_student(r, args[1])
    minutes = sum(weekly(r.courses[code]) for code in s.courses; init=0)
    emit!(r, "SCHEDULE", s.id, "courses", length(s.courses),
          "credits", s.credits, "weekly", time_text(minutes))
    for (day, name) in enumerate(DAYS)
        slots = student_slots(r, s, day)
        isempty(slots) && continue
        parts = String[name]
        for (first, last, code) in slots
            append!(parts, [time_text(first) * "-" * time_text(last), code])
        end
        emit!(r, join(parts, " "); indent=2)
    end
    undated = sort([code for code in s.courses if isempty(r.courses[code].slots)])
    if !isempty(undated)
        emit!(r, "TBA", join(undated, " "); indent=2)
    end
end

function cmd_free!(r::Registrar, args::Vector{String})
    s = require_student(r, args[1])
    day = get(DAY_INDEX, args[2], 0)
    day != 0 || fail("invalid day " * args[2])
    occupied = Tuple{Int, Int}[]
    for (first, last, _) in student_slots(r, s, day)
        start, finish = max(480, first), min(1320, last)
        if start < finish
            push!(occupied, (start, finish))
        end
    end
    free = Tuple{Int, Int}[]
    cursor = 480
    for (first, last) in occupied
        if cursor < first
            push!(free, (cursor, first))
        end
        cursor = max(cursor, last)
    end
    if cursor < 1320
        push!(free, (cursor, 1320))
    end
    total = sum(last - first for (first, last) in free; init=0)
    parts = ["FREE", s.id, args[2], "total", time_text(total)]
    append!(parts, [time_text(a) * "-" * time_text(b) for (a, b) in free])
    emit!(r, join(parts, " "))
end

function cmd_info!(r::Registrar, args::Vector{String})
    c = require_course(r, args[1])
    emit!(r, "INFO", c.code, status(c), "credits", c.credits, "capacity",
          c.capacity, "prereq", canonical(c.required))
    slots = sort(c.slots; by=slot -> (slot.day, slot.start))
    if isempty(slots)
        emit!(r, "meet TBA"; indent=2)
    else
        for slot in slots
            emit!(r, "meet", DAYS[slot.day], slot_text(slot); indent=2)
        end
    end
    required_by = sort([code for (code, other) in r.courses
                        if c.code in other.required.references])
    emit!(r, "required by", isempty(required_by) ? "none" : join(required_by, " "); indent=2)
end

function cmd_audit!(r::Registrar, args::Vector{String})
    s = require_student(r, args[1])
    emit!(r, "AUDIT", s.id, "year", s.year, "limit", s.limit)
    for code in sort(collect(keys(s.records)))
        grade, credits = s.records[code]
        emit!(r, "record", code, grade, credits; indent=2)
    end
    emit!(r, "earned", earned(s), "gpa", gpa(s); indent=2)
    for code in sort(collect(s.courses))
        emit!(r, "enrolled", code, r.courses[code].credits; indent=2)
    end
    emit!(r, "credits", s.credits, "remaining", s.limit - s.credits; indent=2)
    for code in sort(collect(s.waiting))
        position = findfirst(==(s.id), r.courses[code].waitlist)
        emit!(r, "waitlist", code, position; indent=2)
    end
end

function cmd_history!(r::Registrar, args::Vector{String})
    s = require_student(r, args[1])
    emit!(r, "HISTORY", s.id, "events", length(s.history))
    for (number, event) in s.history
        emit!(r, number, event; indent=2)
    end
end

function cmd_students!(r::Registrar, args::Vector{String})
    emit!(r, "STUDENTS", length(r.students))
    for id in sort(collect(keys(r.students)))
        s = r.students[id]
        emit!(r, id, "year", s.year, "credits", "$(s.credits)/$(s.limit)",
              "courses", length(s.courses), "waitlists", length(s.waiting); indent=2)
    end
end

function group_counts(selected::Vector{Course})
    enrolled = sum(length(c.enrolled) for c in selected; init=0)
    capacity = sum(c.capacity for c in selected; init=0)
    waitlisted = sum(length(c.waitlist) for c in selected; init=0)
    "enrolled $enrolled/$capacity rate $(rate_text(enrolled, capacity)) waitlisted $waitlisted"
end

function cmd_report!(r::Registrar, args::Vector{String})
    all_courses = collect(values(r.courses))
    emit!(r, "REPORT", "courses", length(r.courses), group_counts(all_courses))
    departments = Dict{String, Vector{Course}}()
    for code in sort(collect(keys(r.courses)))
        c = r.courses[code]
        emit!(r, code, status(c), "$(length(c.enrolled))/$(c.capacity)",
              rate_text(length(c.enrolled), c.capacity),
              "waitlist", length(c.waitlist); indent=2)
        push!(get!(departments, department(c), Course[]), c)
    end
    for dept in sort(collect(keys(departments)))
        selected = departments[dept]
        emit!(r, "dept", dept, "courses", length(selected), group_counts(selected); indent=2)
    end
end

const HANDLERS = Dict{String, Function}(
    "COURSE" => cmd_course!, "STUDENT" => cmd_student!,
    "ENROLL" => cmd_enroll!, "CHECK" => cmd_check!,
    "OPTIONS" => cmd_options!, "DROP" => cmd_drop!,
    "SWAP" => cmd_swap!, "CLOSE" => cmd_close!,
    "OPEN" => cmd_open!, "CAPACITY" => cmd_capacity!,
    "LIMIT" => cmd_limit!, "PREREQ" => cmd_prereq!,
    "CANCEL" => cmd_cancel!, "ROSTER" => cmd_roster!,
    "SCHEDULE" => cmd_schedule!, "FREE" => cmd_free!,
    "INFO" => cmd_info!, "AUDIT" => cmd_audit!,
    "HISTORY" => cmd_history!, "STUDENTS" => cmd_students!,
    "REPORT" => cmd_report!
)

function execute!(registrar::Registrar, text::String)
    registrar.number += 1
    fields = String.(split(text))
    command = first(fields)
    try
        HANDLERS[command](registrar, fields[2:end])
    catch error
        if error isa CommandError
            emit!(registrar, "ERROR", error.reason)
        else
            rethrow()
        end
    end
end

function main()
    count = parse(Int, readline(stdin))
    registrar = Registrar()
    for _ in 1:count
        execute!(registrar, readline(stdin))
    end
    for line in registrar.output
        println(line)
    end
end

main()
