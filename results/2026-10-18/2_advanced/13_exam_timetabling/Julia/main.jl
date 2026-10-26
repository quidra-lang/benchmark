include("enrolment.jl")
include("conflict_graph.jl")
include("coloring.jl")
include("rooms.jl")
include("report.jl")

const RELATIONS = ("back_to_back", "same_day", "overnight")
const EXCHANGE_VERDICTS = ("fixed", "invalid", "worse", "applied")
const SWAP_VERDICTS = ("fixed", "invalid", "rooms", "worse", "applied")
ceil_div(a, b) = div(a + b - 1, b)
read_lines(name) = readlines(joinpath("input", name))
verdict_counts(tally, verdicts) = join(("$verdict $(tally[verdict])" for verdict in verdicts), " ")

mutable struct Calendar
    days::Int
    lengths::Vector{Int}
    periods::Int
    limit::Int
    weights::Vector{Int}
    front_count::Int
    deadline::Int
    ratio::Int
    slot_count::Int
    closed::Set{Int}
    unavailable::Dict{String,Set{Int}}
    fixed::Dict{String,Int}
    orders::Vector{Tuple{String,String}}
    arrows::Dict{String,Vector{String}}
end

function Calendar(lines)
    settings = [parse.(Int, split(line)[2:end]) for line in lines[1:6]]
    days, lengths = settings[1][1], settings[2]
    Calendar(days, lengths, length(lengths), settings[3][1], settings[4], settings[5]...,
        settings[6][1], days * length(lengths), Set{Int}(), Dict{String,Set{Int}}(),
        Dict{String,Int}(), Tuple{String,String}[], Dict{String,Vector{String}}())
end

slots(calendar) = 1:calendar.slot_count
day_of(calendar, slot) = div(slot - 1, calendar.periods) + 1
slot_name(calendar, slot) = "D$(day_of(calendar, slot))P$(mod(slot - 1, calendar.periods) + 1)"
slot_length(calendar, slot) = calendar.lengths[mod(slot - 1, calendar.periods) + 1]

function slot_at(calendar, day_text, period_text)
    day, period = parse(Int, day_text), parse(Int, period_text)
    1 <= day <= calendar.days && 1 <= period <= calendar.periods ? (day - 1) * calendar.periods + period : 0
end

function relation(calendar, first, second)
    low, high = minmax(first, second)
    if day_of(calendar, low) == day_of(calendar, high)
        high - low == 1 && return 1
        high - low >= 2 && return 2
    elseif high - low == 1
        return 3
    end
    0
end

struct Breakdown
    counts::Vector{Int}
    late::Int
    total::Int
end

breakdown_text(value) = "back_to_back $(value.counts[1]) same_day $(value.counts[2]) overnight $(value.counts[3]) front_load $(value.late) penalty $(value.total)"

Base.@kwdef mutable struct Scheduler
    courses::Dict{String,Course}
    students::Dict{String,Vector{String}}
    rooms::Vector{Room}
    calendar::Calendar
    errors::Vector{String}
    largest_room::Int
    empty::Vector{String}
    oversized::Vector{String}
    schedulable::Vector{String}
    graph::ConflictGraph
    edges::Vector{Tuple{String,String,Int}}
    front_load::Vector{String}
    open_slots::Vector{Int} = Int[]
    fixed_slots::Set{Int} = Set{Int}()
    assignment::Dict{String,Int} = Dict{String,Int}()
    penalty::Int = 0
    attempts::Vector{Tuple{Int,Int,Union{Nothing,String}}} = Tuple{Int,Int,Union{Nothing,String}}[]
    assignment_order::Vector{Tuple{String,Int,Int}} = Tuple{String,Int,Int}[]
    excluded::Vector{String} = String[]
    insertions::Vector{Tuple{String,Int,Int}} = Tuple{String,Int,Int}[]
    reasons::Dict{String,Vector{String}} = Dict{String,Vector{String}}()
    initial::Union{Nothing,Breakdown} = nothing
    exchanged::Union{Nothing,Breakdown} = nothing
    exchange_log::Vector{String} = String[]
    swap_log::Vector{String} = String[]
    placements::Dict{String,Placement} = Dict{String,Placement}()
    slot_placements::Dict{Int,Vector{Placement}} = Dict{Int,Vector{Placement}}()
end

function Scheduler(courses, students, rooms, calendar, errors)
    largest = maximum(room.capacity for room in rooms)
    ids = sort(collect(keys(courses)))
    empty = [id for id in ids if enrolment_count(courses[id]) == 0]
    oversized = [id for id in ids if enrolment_count(courses[id]) > largest]
    schedulable = [id for id in ids if !(id in empty) && !(id in oversized)]
    graph = ConflictGraph([id for id in ids if enrolment_count(courses[id]) > 0], values(students))
    front = sort(schedulable; by=id -> (-enrolment_count(courses[id]), id))
    Scheduler(; courses, students, rooms, calendar, errors, largest_room=largest, empty,
        oversized, schedulable, graph, edges=graph_edges(graph), front_load=front[1:min(end, calendar.front_count)])
end

by_size(s, ids) = sort(collect(ids); by=id -> (-enrolment_count(s.courses[id]), id))
by_degree(s, ids) = sort(collect(ids); by=id -> (-degree(s.graph, id), id))
blocked_students(s, course, slot) = [student for student in course.students if slot in get(s.calendar.unavailable, student, Set{Int}())]
suitable(s, course, slot) = slot_length(s.calendar, slot) >= course.duration && isempty(blocked_students(s, course, slot))
packs(s, ids) = !isnothing(pack(s.rooms, [s.courses[id] for id in ids]))
outside(day, period) = "slot $day $period outside calendar"
courses_at(assignment, slot) = sort([id for (id, other) in assignment if other == slot])

function accept_closed!(s, fields)
    day, period = fields
    slot = slot_at(s.calendar, day, period)
    slot == 0 && return outside(day, period)
    slot in s.calendar.closed && return "duplicate closed $(slot_name(s.calendar, slot))"
    push!(s.calendar.closed, slot)
    nothing
end

function accept_unavailable!(s, fields)
    student, day, period = fields
    !haskey(s.students, student) && return "unknown student $student"
    slot = slot_at(s.calendar, day, period)
    slot == 0 && return outside(day, period)
    blocked = get!(s.calendar.unavailable, student, Set{Int}())
    slot in blocked && return "duplicate unavailable $student $(slot_name(s.calendar, slot))"
    push!(blocked, slot)
    nothing
end

function accept_fixed!(s, fields)
    id, day, period = fields
    !haskey(s.courses, id) && return "unknown course $id"
    !(id in s.schedulable) && return "course $id not schedulable"
    slot = slot_at(s.calendar, day, period)
    slot == 0 && return outside(day, period)
    name = slot_name(s.calendar, slot)
    slot in s.calendar.closed && return "slot $name closed"
    !suitable(s, s.courses[id], slot) && return "slot $name unsuitable for $id"
    haskey(s.calendar.fixed, id) && return "duplicate fixed $id"
    group = courses_at(s.calendar.fixed, slot)
    clashes = [other for other in group if haskey(neighbours(s.graph, id), other)]
    !isempty(clashes) && return "conflict $id $(minimum(clashes))"
    !packs(s, [group; id]) && return "rooms full $name"
    s.calendar.fixed[id] = slot
    nothing
end

function accept_after!(s, fields)
    later, earlier = fields
    for id in fields
        !haskey(s.courses, id) && return "unknown course $id"
    end
    for id in fields
        !(id in s.schedulable) && return "course $id not schedulable"
    end
    later == earlier && return "bad order $later $earlier"
    (later, earlier) in s.calendar.orders && return "duplicate order $later $earlier"
    reachable(s.calendar.arrows, earlier, later) && return "cycle $later $earlier"
    fixed = s.calendar.fixed
    if haskey(fixed, later) && haskey(fixed, earlier) && fixed[later] <= fixed[earlier]
        return "fixed order $later $earlier"
    end
    push!(s.calendar.orders, (later, earlier))
    push!(get!(s.calendar.arrows, later, String[]), earlier)
    nothing
end

function validate_calendar!(s, lines)
    handlers = Dict("closed" => accept_closed!, "unavailable" => accept_unavailable!, "fixed" => accept_fixed!, "after" => accept_after!)
    for number in 7:length(lines)
        fields = split(lines[number])
        message = handlers[fields[1]](s, fields[2:end])
        !isnothing(message) && push!(s.errors, "calendar.txt line $number: $message")
    end
    s.open_slots = [slot for slot in slots(s.calendar) if !(slot in s.calendar.closed)]
    s.fixed_slots = Set(values(s.calendar.fixed))
end

function order_conflicts(s, id, slot, assignment)
    conflicts = String[]
    for (later, earlier) in s.calendar.orders
        if later == id && haskey(assignment, earlier) && slot <= assignment[earlier]
            push!(conflicts, earlier)
        elseif earlier == id && haskey(assignment, later) && slot >= assignment[later]
            push!(conflicts, later)
        end
    end
    conflicts
end

orders_satisfied(s, assignment) = all(assignment[later] > assignment[earlier] for (later, earlier) in s.calendar.orders if haskey(assignment, later) && haskey(assignment, earlier))

function candidate_slots(s, id, assignment)
    candidates = Int[]
    for slot in s.open_slots
        suitable(s, s.courses[id], slot) || continue
        any(get(assignment, other, 0) == slot for other in keys(neighbours(s.graph, id))) && continue
        isempty(order_conflicts(s, id, slot, assignment)) || continue
        packs(s, [courses_at(assignment, slot); id]) && push!(candidates, slot)
    end
    candidates
end

function build_timetable!(s)
    while true
        pending = [id for id in s.schedulable if !haskey(s.calendar.fixed, id) && !(id in s.excluded)]
        assignment = copy(s.calendar.fixed)
        attempt = Attempt(; courses=pending, graph=s.graph, limit=s.calendar.limit, candidates=(id, a) -> candidate_slots(s, id, a))
        succeeded = search!(attempt, assignment)
        failed = succeeded ? nothing : attempt.dead_end_course
        push!(s.attempts, (length(pending), attempt.dead_ends, failed))
        if succeeded
            s.assignment = assignment
            s.assignment_order = [(id, assignment[id], saturation) for (id, saturation) in attempt.chosen]
            return
        end
        push!(s.excluded, failed)
    end
end

function penalty_pairs(s, assignment)
    result = Tuple{String,String,Int,Int}[]
    for (first, second, shared) in s.edges
        if haskey(assignment, first) && haskey(assignment, second)
            kind = relation(s.calendar, assignment[first], assignment[second])
            kind != 0 && push!(result, (first, second, kind, shared))
        end
    end
    result
end

late_courses(s, assignment) = [id for id in s.front_load if haskey(assignment, id) && assignment[id] > s.calendar.deadline]

function breakdown(s, assignment)
    counts = zeros(Int, 3)
    for (_, _, kind, shared) in penalty_pairs(s, assignment)
        counts[kind] += shared
    end
    late = length(late_courses(s, assignment))
    Breakdown(counts, late, sum(s.calendar.weights[1:3] .* counts) + s.calendar.weights[4] * late)
end

function contributions(s)
    result = Dict(id => 0 for id in keys(s.assignment))
    for (first, second, kind, shared) in penalty_pairs(s, s.assignment)
        amount = s.calendar.weights[kind] * shared
        result[first] += amount
        result[second] += amount
    end
    for id in late_courses(s, s.assignment)
        result[id] += s.calendar.weights[4]
    end
    result
end

function blocking_reason(s, id, slot)
    course = s.courses[id]
    slot in s.calendar.closed && return "closed"
    slot_length(s.calendar, slot) < course.duration && return "too_short"
    blocked = blocked_students(s, course, slot)
    !isempty(blocked) && return "unavailable $(minimum(blocked))"
    clashes = [(-shared, other) for (other, shared) in neighbours(s.graph, id) if get(s.assignment, other, 0) == slot]
    if !isempty(clashes)
        negative, other = minimum(clashes)
        return "conflict $other shared $(-negative)"
    end
    conflicts = order_conflicts(s, id, slot, s.assignment)
    !isempty(conflicts) && return "order $(minimum(conflicts))"
    "rooms"
end

function insert_excluded!(s)
    for id in sort(s.excluded)
        candidates = candidate_slots(s, id, s.assignment)
        if isempty(candidates)
            s.reasons[id] = [blocking_reason(s, id, slot) for slot in slots(s.calendar)]
            continue
        end
        before = breakdown(s, s.assignment).total
        scores = Tuple{Int,Int}[]
        for slot in candidates
            trial = copy(s.assignment)
            trial[id] = slot
            push!(scores, (breakdown(s, trial).total, slot))
        end
        total, best = minimum(scores)
        s.assignment[id] = best
        push!(s.insertions, (id, best, total - before))
    end
    s.initial = breakdown(s, s.assignment)
    s.penalty = s.initial.total
end

unscheduled(s) = sort([id for id in s.excluded if !haskey(s.assignment, id)] ∪ s.oversized)
valid_trial(s, trial, moved) = all(suitable(s, s.courses[id], trial[id]) for id in moved) && orders_satisfied(s, trial)
moved_courses(s, trial) = sort([id for id in keys(trial) if trial[id] != s.assignment[id]])

function exchange_trial(s, home, target)
    (home in s.fixed_slots || target in s.fixed_slots) && return ("fixed", nothing, 0)
    trial = copy(s.assignment)
    for (id, slot) in s.assignment
        slot == home && (trial[id] = target)
        slot == target && (trial[id] = home)
    end
    !valid_trial(s, trial, moved_courses(s, trial)) && return ("invalid", nothing, 0)
    total = breakdown(s, trial).total
    total >= s.penalty && return ("worse", nothing, 0)
    ("applied", trial, total)
end

function exchange_slots!(s)
    round_number = serial = 0
    while true
        round_number += 1
        tally = Dict(verdict => 0 for verdict in EXCHANGE_VERDICTS)
        records = String[]
        pairs = 0
        for index in eachindex(s.open_slots), target in s.open_slots[index + 1:end]
            home = s.open_slots[index]
            pairs += 1
            verdict, trial, total = exchange_trial(s, home, target)
            tally[verdict] += 1
            if verdict == "applied"
                serial += 1
                push!(records, "EXCHANGE $serial $(slot_name(s.calendar, home)) $(slot_name(s.calendar, target)) penalty $(s.penalty) -> $total")
                s.assignment, s.penalty = trial, total
            end
        end
        push!(s.exchange_log, "ROUND $round_number pairs $pairs $(verdict_counts(tally, EXCHANGE_VERDICTS))")
        append!(s.exchange_log, records)
        tally["applied"] == 0 && break
    end
    s.exchanged = breakdown(s, s.assignment)
end

function swap_trial(s, id, home, target)
    chain = kempe_chain(s.graph, s.assignment, id, home, target)
    any(haskey(s.calendar.fixed, member) for member in chain) && return ("fixed", nothing, 0)
    trial = copy(s.assignment)
    for member in chain
        trial[member] = s.assignment[member] == home ? target : home
    end
    !valid_trial(s, trial, chain) && return ("invalid", nothing, 0)
    (!packs(s, courses_at(trial, home)) || !packs(s, courses_at(trial, target))) && return ("rooms", nothing, 0)
    total = breakdown(s, trial).total
    total >= s.penalty && return ("worse", nothing, 0)
    ("applied", trial, total)
end

function swap_chains!(s)
    pass_number = serial = 0
    while true
        pass_number += 1
        tally = Dict(verdict => 0 for verdict in SWAP_VERDICTS)
        records = String[]
        candidates = 0
        movable = sort([id for id in keys(s.assignment) if !haskey(s.calendar.fixed, id)])
        for id in movable
            home = s.assignment[id]
            for target in s.open_slots
                target == home && continue
                candidates += 1
                verdict, trial, total = swap_trial(s, id, home, target)
                tally[verdict] += 1
                verdict == "applied" || continue
                serial += 1
                chain = moved_courses(s, trial)
                push!(records, "SWAP $serial $id $(slot_name(s.calendar, home)) $(slot_name(s.calendar, target)) chain $(length(chain)) penalty $(s.penalty) -> $total")
                for member in chain
                    push!(records, "  MOVE $member $(slot_name(s.calendar, s.assignment[member])) -> $(slot_name(s.calendar, trial[member]))")
                end
                s.assignment, s.penalty = trial, total
                break
            end
        end
        push!(s.swap_log, "PASS $pass_number candidates $candidates $(verdict_counts(tally, SWAP_VERDICTS))")
        append!(s.swap_log, records)
        tally["applied"] == 0 && break
    end
end

function assign_rooms!(s)
    for slot in s.open_slots
        placed = pack(s.rooms, [s.courses[id] for id in courses_at(s.assignment, slot)])
        s.slot_placements[slot] = placed
        for placement in placed
            s.placements[placement.course.id] = placement
        end
    end
end

function room_groups(s, slot)
    result = Tuple{Room,Vector{Placement}}[]
    for room in s.rooms
        placed = [p for p in s.slot_placements[slot] if p.room.id == room.id]
        !isempty(placed) && push!(result, (room, placed))
    end
    result
end

invigilators(s, slot) = sum((ceil_div(sum(enrolment_count(p.course) for p in placed), s.calendar.ratio) for (_, placed) in room_groups(s, slot)); init=0)
slot_load(s, slot) = (length(courses_at(s.assignment, slot)), sum((enrolment_count(s.courses[id]) for id in courses_at(s.assignment, slot)); init=0))
assigned_courses(s, student) = sort([(s.assignment[id], id) for id in s.students[student] if haskey(s.assignment, id)])
assigned_slots(s, student) = [slot for (slot, _) in assigned_courses(s, student)]

function student_pairs(s, student)
    assigned = assigned_courses(s, student)
    result = Tuple{Int,Int,String,Int,String}[]
    for i in eachindex(assigned), j in i + 1:length(assigned)
        low_slot, low_course = assigned[i]
        high_slot, high_course = assigned[j]
        kind = relation(s.calendar, low_slot, high_slot)
        kind != 0 && push!(result, (kind, low_slot, low_course, high_slot, high_course))
    end
    result
end

function student_penalty(s, student)
    counts = zeros(Int, 3)
    for (kind, _, _, _, _) in student_pairs(s, student)
        counts[kind] += 1
    end
    counts, sum(s.calendar.weights[1:3] .* counts)
end

function timetable_lines(s)
    calendar = s.calendar
    lines = ["TIMETABLE days $(calendar.days) periods $(calendar.periods) open $(length(s.open_slots)) courses $(length(s.courses)) scheduled $(length(s.assignment)) unscheduled $(length(unscheduled(s))) empty $(length(s.empty))"]
    push!(lines, fixed_width_line("DAY", [["P$p" for p in 1:calendar.periods]; "TOTAL"], 4, 10))
    for day in 1:calendar.days
        cells = String[]
        exams = students = 0
        for period in 1:calendar.periods
            slot = (day - 1) * calendar.periods + period
            if slot in calendar.closed
                push!(cells, "closed")
            else
                n, count = slot_load(s, slot)
                push!(cells, "$n/$count")
                exams += n
                students += count
            end
        end
        push!(cells, "$exams/$students")
        push!(lines, fixed_width_line("D$day", cells, 4, 10))
    end
    for slot in slots(calendar)
        prefix = "SLOT $slot $(slot_name(calendar, slot)) minutes $(slot_length(calendar, slot))"
        if slot in calendar.closed
            push!(lines, prefix * " closed")
            continue
        end
        exams, students = slot_load(s, slot)
        groups = room_groups(s, slot)
        seats = sum((room.capacity for (room, _) in groups); init=0)
        push!(lines, "$prefix exams $exams students $students rooms $(length(groups)) seats $seats invigilators $(invigilators(s, slot))")
        for p in s.slot_placements[slot]
            c = p.course
            marker = haskey(calendar.fixed, c.id) ? " fixed" : ""
            push!(lines, "  $(c.id) $(c.duration)min students $(enrolment_count(c)) room $(p.room.id) seats $(p.first_seat)-$(p.last_seat)$marker $(c.name)")
        end
    end
    for room in s.rooms
        used = exams = seated = 0
        for slot in s.open_slots, (other, placed) in room_groups(s, slot)
            if room.id == other.id
                used += 1
                exams += length(placed)
                seated += sum(enrolment_count(p.course) for p in placed)
            end
        end
        utilization = rounded_percent(seated, room.capacity * length(s.open_slots))
        push!(lines, "ROOM $(room.id) capacity $(room.capacity) slots $used exams $exams seated $seated utilization $utilization")
    end
    push!(lines, "INVIGILATORS total $(sum(invigilators(s, slot) for slot in s.open_slots)) ratio $(calendar.ratio)")
    lines
end

function room_lines(s)
    lines = ["slot,room,course,students,first_seat,last_seat"]
    for slot in s.open_slots, (room, placed) in room_groups(s, slot), p in placed
        push!(lines, "$(slot_name(s.calendar, slot)),$(room.id),$(p.course.id),$(enrolment_count(p.course)),$(p.first_seat),$(p.last_seat)")
    end
    lines
end

function student_statistics(s)
    histogram, gaps, dayloads = (Dict{Int,Int}() for _ in 1:3)
    ranking = Tuple{Int,String,Vector{Int}}[]
    for student in keys(s.students)
        counts, penalty = student_penalty(s, student)
        histogram[penalty] = get(histogram, penalty, 0) + 1
        push!(ranking, (-penalty, student, counts))
        assigned = assigned_slots(s, student)
        for i in 2:length(assigned)
            gap = assigned[i] - assigned[i - 1]
            gaps[gap] = get(gaps, gap, 0) + 1
        end
        if !isempty(assigned)
            daily = [count(slot -> day_of(s.calendar, slot) == day, assigned) for day in 1:s.calendar.days]
            most = maximum(daily)
            dayloads[most] = get(dayloads, most, 0) + 1
        end
    end
    lines = ["HISTOGRAM $value $(histogram[value])" for value in sort(collect(keys(histogram)))]
    append!(lines, ["GAP $value $(gaps[value])" for value in sort(collect(keys(gaps)))])
    append!(lines, ["DAYLOAD $value $(dayloads[value])" for value in sort(collect(keys(dayloads)))])
    sort!(ranking; by=item -> (item[1], item[2]))
    for (negative, student, counts) in ranking[1:min(end, 5)]
        negative < 0 && push!(lines, "WORST $student penalty $(-negative) back_to_back $(counts[1]) same_day $(counts[2]) overnight $(counts[3])")
    end
    lines
end

function penalty_lines(s)
    calendar, weights = s.calendar, s.calendar.weights
    final = breakdown(s, s.assignment)
    lines = ["WEIGHTS back_to_back $(weights[1]) same_day $(weights[2]) overnight $(weights[3]) front_load $(weights[4])",
        "FRONT_LOAD courses $(length(s.front_load)) last_slot $(slot_name(calendar, calendar.deadline))", "INITIAL $(breakdown_text(s.initial))"]
    append!(lines, s.exchange_log)
    push!(lines, "EXCHANGED $(breakdown_text(s.exchanged))")
    append!(lines, s.swap_log)
    push!(lines, "FINAL $(breakdown_text(final))", "SAVED $(s.initial.total - final.total)")
    daily = zeros(Int, calendar.days, 3)
    for (first, second, kind, shared) in penalty_pairs(s, s.assignment)
        daily[day_of(calendar, min(s.assignment[first], s.assignment[second])), kind] += shared
    end
    for day in 1:calendar.days
        push!(lines, "DAY D$day back_to_back $(daily[day, 1]) same_day $(daily[day, 2]) overnight $(daily[day, 3])")
    end
    for id in late_courses(s, s.assignment)
        push!(lines, "LATE $id $(slot_name(calendar, s.assignment[id])) students $(enrolment_count(s.courses[id]))")
    end
    values = contributions(s)
    ranked = sort(collect(keys(values)); by=id -> (-values[id], id))
    for id in ranked[1:min(end, 10)]
        values[id] > 0 && push!(lines, "COURSE $id $(slot_name(calendar, s.assignment[id])) penalty $(values[id])")
    end
    append!(lines, student_statistics(s))
    lines
end

function schedule_lines(s, queries)
    lines = String[]
    for student in queries
        if !haskey(s.students, student)
            push!(lines, "STUDENT $student not found")
            continue
        end
        ids, assigned = s.students[student], assigned_courses(s, student)
        _, penalty = student_penalty(s, student)
        push!(lines, "STUDENT $student exams $(length(ids)) scheduled $(length(assigned)) penalty $penalty")
        for (slot, id) in assigned
            p = s.placements[id]
            seat = p.first_seat + findfirst(==(student), p.course.students) - 1
            push!(lines, "  $(slot_name(s.calendar, slot)) $id room $(p.room.id) seat $seat $(p.course.name)")
        end
        for id in ids
            !haskey(s.assignment, id) && push!(lines, "  UNSCHEDULED $id $(s.courses[id].name)")
        end
        for (kind, low, first, high, second) in student_pairs(s, student)
            push!(lines, "  $(uppercase(RELATIONS[kind])) $(slot_name(s.calendar, low)) $first $(slot_name(s.calendar, high)) $second")
        end
        for slot in sort(collect(get(s.calendar.unavailable, student, Set{Int}())))
            push!(lines, "  UNAVAILABLE $(slot_name(s.calendar, slot))")
        end
    end
    lines
end

function status_lines(s)
    values = contributions(s)
    lines = ["course,status,slot,students,minutes,degree,penalty"]
    for id in sort(collect(keys(s.courses)))
        c = s.courses[id]
        status = haskey(s.calendar.fixed, id) ? "fixed" : haskey(s.assignment, id) ? "scheduled" : id in s.oversized ? "too_large" : id in s.empty ? "empty" : "no_slot"
        slot = haskey(s.assignment, id) ? slot_name(s.calendar, s.assignment[id]) : "-"
        push!(lines, "$id,$status,$slot,$(enrolment_count(c)),$(c.duration),$(degree(s.graph, id)),$(get(values, id, 0))")
    end
    lines
end

function graph_lines(s)
    vertices, edges = length(s.graph.vertices), length(s.edges)
    shared = sum((count for (_, _, count) in s.edges); init=0)
    density = vertices >= 2 ? div(2000 * edges, vertices * (vertices - 1)) : 0
    lines = ["GRAPH courses $vertices edges $edges shared $shared density $density"]
    ranked = by_degree(s, s.graph.vertices)
    for id in ranked[1:min(end, 5)]
        push!(lines, "DEGREE $id neighbours $(degree(s.graph, id)) shared $(shared_total(s.graph, id)) students $(enrolment_count(s.courses[id]))")
    end
    groups = components(s.graph)
    push!(lines, "COMPONENTS $(length(groups))")
    for (number, group) in enumerate(groups)
        push!(lines, "COMPONENT $number size $(length(group)) first $(first(group))")
    end
    clique = greedy_clique(s.graph, s.schedulable)
    push!(lines, join(["CLIQUE", "size", string(length(clique)), clique...], " "))
    lines
end

function capacity_lines(s)
    loads = length.(collect(values(s.students)))
    most = maximum(loads)
    demand = sum(enrolment_count(s.courses[id]) for id in s.schedulable)
    capacity = sum(room.capacity for room in s.rooms)
    lines = ["LOAD max_exams $most students $(count(==(most), loads))", "SEATS demand $demand capacity $capacity min_slots $(ceil_div(demand, capacity))",
        "HEURISTIC largest_degree slots $(greedy_numbering(by_degree(s, s.schedulable), s.graph))", "HEURISTIC largest_enrolment slots $(greedy_numbering(by_size(s, s.schedulable), s.graph))"]
    ranked = by_size(s, s.graph.vertices)
    table = ranked[1:min(end, 8)]
    push!(lines, fixed_width_line("MATRIX", table, 9, 9))
    for row in table
        cells = [column == row ? "-" : string(get(neighbours(s.graph, row), column, 0)) for column in table]
        push!(lines, fixed_width_line(row, cells, 9, 9))
    end
    lines
end

function report_lines(s)
    calendar = s.calendar
    enrolments = sum(length, values(s.students))
    lines = ["INPUT courses $(length(s.courses)) enrolments $enrolments rooms $(length(s.rooms)) students $(length(s.students)) errors $(length(s.errors))"]
    append!(lines, ["ERROR $error" for error in s.errors])
    append!(lines, graph_lines(s), capacity_lines(s))
    append!(lines, ["EMPTY $id" for id in s.empty])
    for id in s.oversized
        push!(lines, "TOO_LARGE $id students $(enrolment_count(s.courses[id])) largest_room $(s.largest_room)")
    end
    append!(lines, ["CLOSED $(slot_name(calendar, slot))" for slot in sort(collect(calendar.closed))])
    for id in sort(collect(keys(calendar.fixed)))
        push!(lines, "FIXED $id $(slot_name(calendar, calendar.fixed[id]))")
    end
    append!(lines, ["AFTER $later $earlier" for (later, earlier) in calendar.orders])
    for (number, (size, dead, failed)) in enumerate(s.attempts)
        result = isnothing(failed) ? "success" : "failed $failed"
        push!(lines, "ATTEMPT $number courses $size backtracks $dead $result")
    end
    for (number, (id, slot, saturation)) in enumerate(s.assignment_order)
        push!(lines, "ORDER $number $id $(slot_name(calendar, slot)) saturation $saturation degree $(degree(s.graph, id))")
    end
    for (id, slot, increase) in s.insertions
        push!(lines, "INSERTED $id $(slot_name(calendar, slot)) penalty $increase")
    end
    for id in unscheduled(s)
        reason = id in s.oversized ? "too_large" : "no_slot"
        push!(lines, "UNSCHEDULED $id reason $reason students $(enrolment_count(s.courses[id]))")
        for (slot, reason) in enumerate(get(s.reasons, id, String[]))
            push!(lines, "  $(slot_name(calendar, slot)) $reason")
        end
    end
    used = length(Set(values(s.assignment)))
    push!(lines, "SUMMARY scheduled $(length(s.assignment)) unscheduled $(length(unscheduled(s))) slots_used $used penalty $(s.penalty)")
    lines
end

function main()
    errors = String[]
    courses = load_courses(joinpath("input", "courses.csv"), errors)
    students = load_enrolments(joinpath("input", "enrolments.csv"), courses, errors)
    rooms = load_rooms(joinpath("input", "rooms.csv"), errors)
    lines = read_lines("calendar.txt")
    s = Scheduler(courses, students, rooms, Calendar(lines), errors)
    validate_calendar!(s, lines)
    build_timetable!(s)
    insert_excluded!(s)
    exchange_slots!(s)
    swap_chains!(s)
    assign_rooms!(s)
    queries = read_lines("queries.txt")
    write_files("output", [("timetable.txt", timetable_lines(s)), ("rooms.csv", room_lines(s)),
        ("penalties.txt", penalty_lines(s)), ("student_schedules.txt", schedule_lines(s, queries)),
        ("course_status.csv", status_lines(s)), ("report.txt", report_lines(s))])
end

main()
