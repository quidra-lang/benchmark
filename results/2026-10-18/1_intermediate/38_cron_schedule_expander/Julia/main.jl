using Printf

@enum FieldKind MINUTE=1 HOUR DAY_OF_MONTH MONTH DAY_OF_WEEK
@enum SpecialKind LAST LAST_WORKDAY BEFORE_LAST NEAREST NTH_WEEKDAY LAST_WEEKDAY
@enum Policy ALLOW FORBID REPLACE
const FIELD_NAMES = ("minute", "hour", "day-of-month", "month", "day-of-week")
const MINIMUM = (0, 0, 1, 1, 0)
const MAXIMUM = (59, 23, 31, 12, 7)
const MONTH_NAMES = ("January", "February", "March", "April", "May", "June", "July", "August",
                     "September", "October", "November", "December")
const WEEKDAY_NAMES = ("Sunday", "Monday", "Tuesday", "Wednesday", "Thursday", "Friday", "Saturday")
const MONTH_CODES = ("JAN", "FEB", "MAR", "APR", "MAY", "JUN", "JUL", "AUG", "SEP", "OCT", "NOV", "DEC")
const WEEKDAY_CODES = ("SUN", "MON", "TUE", "WED", "THU", "FRI", "SAT")
const MACROS = Dict("@yearly" => "0 0 1 1 *", "@annually" => "0 0 1 1 *", "@monthly" => "0 0 1 * *",
                    "@weekly" => "0 0 * * 0", "@daily" => "0 0 * * *", "@midnight" => "0 0 * * *", "@hourly" => "0 * * * *")
const ARITIES = Dict("JOB" => -3, "VALIDATE" => -2, "LIST" => 1, "HOLIDAYS" => 1,
    "REMOVE" => 2, "RENAME" => 3, "ENABLE" => 2, "DISABLE" => 2, "RUNTIME" => 4,
    "EXPAND" => 3, "DESCRIBE" => 2, "MATCH" => 4, "NEXT" => 5, "PREV" => 5,
    "COUNT" => 6, "GAP" => 4, "OVERLAP" => 7, "TIMELINE" => 5, "CONFLICTS" => 5,
    "WEEK" => 2, "CALENDAR" => 3, "SIMULATE" => 5, "EXCLUDE" => 2, "INCLUDE" => 2)

struct CommandError <: Exception
    message::String
end
fail(message::String) = throw(CommandError(message))
field_error(kind::FieldKind, reason::String) = fail("$(FIELD_NAMES[Int(kind)]) $reason")
ascii_digits(text::AbstractString, low::Int, high::Int) = low <= length(text) <= high && all(c -> '0' <= c <= '9', text)
leap(year::Int) = year % 4 == 0 && (year % 100 != 0 || year % 400 == 0)
month_length(year::Int, month::Int) = (31, 28, 31, 30, 31, 30, 31, 31, 30, 31, 30, 31)[month] + (month == 2 && leap(year))
leaps(year::Int) = year ÷ 4 - year ÷ 100 + year ÷ 400

struct CivilDate
    year::Int
    month::Int
    day::Int
end
function day_number(date::CivilDate)
    result = 365 * (date.year - 2000) + leaps(date.year - 1) - leaps(1999) + date.day - 1
    for month in 1:date.month-1
        result += month_length(date.year, month)
    end
    result
end
const CALENDAR = vcat([CivilDate(year, month, day) for year in 2000:2099 for month in 1:12
                       for day in 1:month_length(year, month)], [CivilDate(2100, 1, 1)])
weekday(day::Int) = (day + 6) % 7
function plain_date(day::Int)
    date = CALENDAR[day + 1]
    @sprintf("%04d-%02d-%02d", date.year, date.month, date.day)
end
date_text(day::Int) = "$(plain_date(day)) $(WEEKDAY_NAMES[weekday(day) + 1][1:3])"
clock_text(minute::Int) = @sprintf("%02d:%02d", minute ÷ 60, minute % 60)
datetime_text(minute::Int) = "$(plain_date(minute ÷ 1440)) $(clock_text(minute % 1440)) $(WEEKDAY_NAMES[weekday(minute ÷ 1440) + 1][1:3])"
span_text(minutes::Int) = @sprintf("%dd%02dh%02dm", minutes ÷ 1440, minutes % 1440 ÷ 60, minutes % 60)

function read_date(text::AbstractString, reason::String = "invalid date")
    occursin(r"^[0-9]{4}-[0-9]{2}-[0-9]{2}$", text) || fail(reason)
    year, month, day = parse(Int, text[1:4]), parse(Int, text[6:7]), parse(Int, text[9:10])
    2001 <= year <= 2098 && 1 <= month <= 12 && 1 <= day <= month_length(year, month) || fail(reason)
    day_number(CivilDate(year, month, day))
end
function read_datetime(words, position::Int)
    day = read_date(words[position], "invalid datetime")
    text = words[position + 1]
    occursin(r"^[0-9]{2}:[0-9]{2}$", text) || fail("invalid datetime")
    hour, minute = parse(Int, text[1:2]), parse(Int, text[4:5])
    hour <= 23 && minute <= 59 || fail("invalid datetime")
    day * 1440 + hour * 60 + minute
end
function read_month(text::AbstractString)
    occursin(r"^[0-9]{4}-[0-9]{2}$", text) || fail("invalid month")
    year, month = parse(Int, text[1:4]), parse(Int, text[6:7])
    2001 <= year <= 2098 && 1 <= month <= 12 || fail("invalid month")
    day_number(CivilDate(year, month, 1))
end
function positive(text::AbstractString, width::Int, maximum::Int, reason::String)
    ascii_digits(text, 1, width) && first(text) != '0' || fail(reason)
    value = parse(Int, text)
    value <= maximum || fail(reason)
    value
end
struct Window
    low::Int
    high::Int
end
function read_window(words, position::Int)
    low = read_datetime(words, position)
    high = read_datetime(words, position + 2)
    low <= high || fail("invalid window")
    high - low <= 44640 || fail("window too long")
    Window(low, high)
end

struct Special
    kind::SpecialKind
    value::Int
    occurrence::Int
end
Special(kind::SpecialKind, value::Int = 0) = Special(kind, value, 0)
function special_text(special::Special)
    special.kind == LAST && return "L"
    special.kind == LAST_WORKDAY && return "LW"
    special.kind == BEFORE_LAST && return "L-$(special.value)"
    special.kind == NEAREST && return "$(special.value)W"
    special.kind == NTH_WEEKDAY && return "$(special.value)#$(special.occurrence)"
    "$(special.value)L"
end
function special_phrase(special::Special)
    special.kind == LAST && return "the last day"
    special.kind == LAST_WORKDAY && return "the last weekday"
    special.kind == BEFORE_LAST && return "$(special.value) $(special.value == 1 ? "day" : "days") before the last day"
    special.kind == NEAREST && return "the weekday nearest day $(special.value)"
    name = WEEKDAY_NAMES[special.value + 1]
    special.kind == LAST_WEEKDAY && return "the last $name"
    ordinal = ("1st", "2nd", "3rd", "4th", "5th")[special.occurrence]
    "the $ordinal $name"
end
function field_value(text::AbstractString, kind::FieldKind)
    names = kind == MONTH ? MONTH_CODES : kind == DAY_OF_WEEK ? WEEKDAY_CODES : ()
    index = findfirst(==(text), names)
    isnothing(index) || return index - (kind == DAY_OF_WEEK)
    ascii_digits(text, 1, 2) || field_error(kind, "invalid value")
    value = parse(Int, text)
    MINIMUM[Int(kind)] <= value <= MAXIMUM[Int(kind)] || field_error(kind, "out of range")
    value
end
function special_number(text::AbstractString, kind::FieldKind, width::Int, maximum::Int)
    ascii_digits(text, 1, width) || field_error(kind, "invalid value")
    value = parse(Int, text)
    1 <= value <= maximum || field_error(kind, "out of range")
    value
end
struct CronField
    kind::FieldKind
    values::Vector{Int}
    specials::Vector{Special}
    restricted::Bool
end
function parse_field(text::AbstractString, kind::FieldKind)
    values, specials = Set{Int}(), Special[]
    for item in split(text, ','; keepempty = true)
        isempty(item) && field_error(kind, "empty item")
        special = nothing
        if kind == DAY_OF_MONTH && (startswith(item, 'L') || endswith(item, 'W'))
            if item == "L"
                special = Special(LAST)
            elseif item == "LW"
                special = Special(LAST_WORKDAY)
            elseif startswith(item, "L-")
                special = Special(BEFORE_LAST, special_number(item[3:end], kind, 2, 30))
            elseif endswith(item, 'W')
                special = Special(NEAREST, special_number(item[1:end-1], kind, 2, 31))
            else
                field_error(kind, "invalid value")
            end
        elseif kind == DAY_OF_WEEK && occursin('#', item)
            at = findfirst(==('#'), item)
            value = field_value(item[1:at-1], kind)
            occurrence = special_number(item[at+1:end], kind, 1, 5)
            special = Special(NTH_WEEKDAY, value % 7, occurrence)
        elseif kind == DAY_OF_WEEK && length(item) >= 2 && endswith(item, 'L')
            special = Special(LAST_WEEKDAY, field_value(item[1:end-1], kind) % 7)
        end
        if !isnothing(special)
            special in specials || push!(specials, special)
            continue
        end
        slash = findfirst(==('/'), item)
        base = isnothing(slash) ? item : item[1:slash-1]
        dash = findfirst(==('-'), base)
        if base == "*"
            low, high = MINIMUM[Int(kind)], MAXIMUM[Int(kind)]
        elseif !isnothing(dash)
            low = field_value(base[1:dash-1], kind)
            high = field_value(base[dash+1:end], kind)
            low <= high || field_error(kind, "invalid range")
        else
            low = field_value(base, kind)
            high = isnothing(slash) ? low : MAXIMUM[Int(kind)]
        end
        step = 1
        if !isnothing(slash)
            part = item[slash+1:end]
            ascii_digits(part, 1, 2) || field_error(kind, "invalid step")
            step = parse(Int, part)
            step >= 1 || field_error(kind, "invalid step")
        end
        for value in low:step:high
            push!(values, kind == DAY_OF_WEEK ? value % 7 : value)
        end
    end
    CronField(kind, sort!(collect(values)), specials, !startswith(text, '*'))
end
struct Cron
    fields::NTuple{5,CronField}
    times::Vector{Int}
    text::String
    expanded::String
end
function parse_cron(input)
    text = join(input, " ")
    words = input
    if length(words) == 1 && startswith(words[1], '@')
        haskey(MACROS, words[1]) || fail("unknown macro")
        words = split(MACROS[words[1]], ' ')
    end
    length(words) == 5 || fail("field count")
    fields = CronField[]
    for (index, token) in enumerate(words)
        push!(fields, parse_field(token, FieldKind(index)))
    end
    times = [60hour + minute for hour in fields[2].values for minute in fields[1].values]
    Cron(Tuple(fields), times, text, join(words, " "))
end
or_rule(cron::Cron) = cron.fields[3].restricted && cron.fields[5].restricted
function nearest_workday(first::Int, day::Int, last::Int)
    w = weekday(first + day - 1)
    w == 6 && return day == 1 ? 3 : day - 1
    w == 0 && return day == last ? day - 2 : day + 1
    day
end
struct DayStatus
    month::Bool
    dom::Bool
    dow::Bool
    condition::Bool
end
function day_status(cron::Cron, day::Int)
    date = CALENDAR[day + 1]
    d, last, w = date.day, month_length(date.year, date.month), weekday(day)
    first = day - d + 1
    dom, dow = d in cron.fields[3].values, w in cron.fields[5].values
    for special in cron.fields[3].specials
        target = special.kind == LAST ? last : special.kind == LAST_WORKDAY ? nearest_workday(first, last, last) :
                 special.kind == BEFORE_LAST ? last - special.value : special.value <= last ? nearest_workday(first, special.value, last) : 0
        dom |= d == target
    end
    for special in cron.fields[5].specials
        dow |= w == special.value && (special.kind == NTH_WEEKDAY ? (d - 1) ÷ 7 + 1 == special.occurrence : d + 7 > last)
    end
    DayStatus(date.month in cron.fields[4].values, dom, dow, or_rule(cron) ? dom || dow : dom && dow)
end
function scheduled_day(cron::Cron, day::Int)
    status = day_status(cron, day)
    status.month && status.condition
end
function fire_times(cron::Cron, low::Int, high::Int, holidays::Set{Int}; backward::Bool = false, limit::Int = 0)
    first_day, last_day = low ÷ 1440, high ÷ 1440
    days = backward ? (last_day:-1:first_day) : (first_day:last_day)
    indices = backward ? (length(cron.times):-1:1) : eachindex(cron.times)
    result = Int[]
    for day in days
        (day in holidays || !scheduled_day(cron, day)) && continue
        for index in indices
            time = 1440day + cron.times[index]
            low <= time <= high || continue
            push!(result, time)
            limit > 0 && length(result) == limit && return result
        end
    end
    result
end

function word_list(parts::Vector{String}, either::Bool = false)
    length(parts) < 2 && return join(parts)
    join(parts[1:end-1], ", ") * (either ? " or " : " and ") * parts[end]
end
function value_name(kind::FieldKind, value::Int)
    kind == MONTH ? MONTH_NAMES[value] : kind == DAY_OF_WEEK ? WEEKDAY_NAMES[value + 1] : string(value)
end
function value_list(field::CronField, either::Bool = false)
    values, parts = field.values, String[]
    first = 1
    while first <= length(values)
        last = first
        while last < length(values) && values[last + 1] == values[last] + 1
            last += 1
        end
        if last - first >= 2
            push!(parts, "$(value_name(field.kind, values[first])) through $(value_name(field.kind, values[last]))")
        else
            append!(parts, [value_name(field.kind, values[index]) for index in first:last])
        end
        first = last + 1
    end
    word_list(parts, either)
end
function stepped(field::CronField)
    values = field.values
    (length(values) < 2 || values[1] != 0 || values[2] < 2) && return 0
    step = values[2]
    values == collect(0:step:MAXIMUM[Int(field.kind)]) ? step : 0
end
function day_phrase(field::CronField, either::Bool = false)
    parts = String[]
    if !isempty(field.values)
        push!(parts, field.kind == DAY_OF_WEEK ? value_list(field, either) :
                     "$(length(field.values) == 1 ? "day" : "days") $(value_list(field))")
    end
    append!(parts, special_phrase.(field.specials))
    word_list(parts, either) * (field.kind == DAY_OF_MONTH || !isempty(field.specials) ? " of the month" : "")
end
function description(cron::Cron)
    minute, hour, dom, month, dow = cron.fields
    if length(cron.times) <= 4
        text = "At " * word_list(clock_text.(cron.times))
    else
        ms, hs = stepped(minute), stepped(hour)
        text = length(minute.values) == 60 ? "Every minute" : ms > 0 ? "Every $ms minutes" :
               length(minute.values) == 1 ? "At minute $(minute.values[1])" : "At minutes $(value_list(minute))"
        if length(hour.values) == 24
            startswith(text, "At minute") && (text *= " of every hour")
        elseif hs > 0
            text *= ", every $hs hours"
        elseif hour.values[end] - hour.values[1] + 1 == length(hour.values)
            text *= @sprintf(", between %02d:00 and %02d:59", hour.values[1], hour.values[end])
        else
            text *= ", during hours $(value_list(hour))"
        end
    end
    dfull, ufull = length(dom.values) == 31, length(dow.values) == 7
    if or_rule(cron)
        !dfull && !ufull && (text *= ", on $(day_phrase(dom)) or on $(day_phrase(dow))")
    elseif !dfull && !ufull
        text *= ", on $(day_phrase(dom)) if it is $(day_phrase(dow, true))"
    elseif !dfull
        text *= ", on $(day_phrase(dom))"
    elseif !ufull
        text *= ", on $(day_phrase(dow))"
    end
    length(month.values) != 12 && (text *= ", in $(value_list(month))")
    text
end

Base.@kwdef mutable struct SchedulerJob
    cron::Cron
    enabled::Bool = true
    duration::Int = 1
    policy::Policy = ALLOW
end
struct Scheduler
    jobs::Dict{String,SchedulerJob}
    holidays::Set{Int}
end
Scheduler() = Scheduler(Dict{String,SchedulerJob}(), Set{Int}())
function require_job(state::Scheduler, id::AbstractString)
    haskey(state.jobs, id) || fail("unknown job")
    state.jobs[id]
end
function require_new_id(state::Scheduler, id::AbstractString)
    occursin(r"^[a-z][a-z0-9_]{0,15}$", id) || fail("invalid id")
    haskey(state.jobs, id) && fail("duplicate job")
end
ordered_ids(state::Scheduler) = sort!(collect(keys(state.jobs)))
enabled_jobs(state::Scheduler) = [id => state.jobs[id] for id in ordered_ids(state) if state.jobs[id].enabled]
function combined_report(state::Scheduler, window::Window, conflicts::Bool)
    jobs = enabled_jobs(state)
    incidence = falses(length(jobs), window.high - window.low + 1)
    for (index, (_, job)) in enumerate(jobs)
        for time in fire_times(job.cron, window.low, window.high, state.holidays)
            incidence[index, time - window.low + 1] = true
        end
    end
    if conflicts
        counts = vec(sum(incidence; dims = 1))
        positions = findall(>=(2), counts)
        total = length(positions)
        peak = isempty(positions) ? 0 : maximum(counts[positions])
        rows = ["CONFLICTS $total peak $peak"]
        for position in Iterators.take(positions, 100)
            ids = [jobs[index].first for index in eachindex(jobs) if incidence[index, position]]
            push!(rows, "$(datetime_text(window.low + position - 1)) $(counts[position]) $(join(ids, " "))")
        end
    else
        pairs = findall(incidence)
        total = length(pairs)
        rows = ["TIMELINE $total"]
        for pair in Iterators.take(pairs, 100)
            push!(rows, "$(datetime_text(window.low + pair[2] - 1)) $(jobs[pair[1]].first)")
        end
    end
    total > 100 && push!(rows, "... $(total - 100) more")
    rows
end
function week_report(state::Scheduler, first::Int, original::AbstractString)
    counts = zeros(Int, 24, 7)
    for offset in 0:6
        day = first + offset
        day in state.holidays && continue
        for (_, job) in enabled_jobs(state)
            scheduled_day(job.cron, day) || continue
            for hour in job.cron.fields[2].values
                counts[hour + 1, offset + 1] += length(job.cron.fields[1].values)
            end
        end
    end
    rows = ["WEEK $original $(sum(counts))"]
    for offset in 0:6
        hours = @view counts[:, offset + 1]
        heat = join([count == 0 ? "." : count < 10 ? string(count) : "+" for count in hours])
        push!(rows, "$(date_text(first + offset)) $heat $(sum(hours))")
    end
    rows
end
function calendar_report(state::Scheduler, job::SchedulerJob, first::Int, original::AbstractString, id::AbstractString)
    date = CALENDAR[first + 1]
    marks = [!scheduled_day(job.cron, first + day - 1) ? '-' : first + day - 1 in state.holidays ? 'x' : '*'
             for day in 1:month_length(date.year, date.month)]
    days = count(==('*'), marks)
    cells = fill("...", weekday(first))
    append!(cells, [@sprintf("%02d%c", day, mark) for (day, mark) in enumerate(marks)])
    append!(cells, fill("...", mod(-length(cells), 7)))
    rows = ["CALENDAR $id $original days $days runs $(days * length(job.cron.times))", "Sun Mon Tue Wed Thu Fri Sat"]
    append!(rows, [join(week, " ") for week in Iterators.partition(cells, 7)])
    rows
end
function simulation_report(state::Scheduler, window::Window)
    jobs = enabled_jobs(state)
    events = zeros(Int, window.high - window.low + 1441)
    details = String[]
    for (id, job) in jobs
        started = skipped = replaced = busy = 0
        last_end = nothing
        for time in fire_times(job.cron, window.low, window.high, state.holidays)
            if !isnothing(last_end) && last_end > time
                if job.policy == FORBID
                    skipped += 1
                    continue
                elseif job.policy == REPLACE
                    events[last_end - window.low + 1] += 1
                    events[time - window.low + 1] -= 1
                    busy -= last_end - time
                    replaced += 1
                end
            end
            last_end = time + job.duration
            events[time - window.low + 1] += 1
            events[last_end - window.low + 1] -= 1
            started += 1
            busy += job.duration
        end
        push!(details, "$id $(job.policy) started $started skipped $skipped replaced $replaced busy $busy")
    end
    running = cumsum(events)
    peak = maximum(running)
    header = "SIMULATE $(length(jobs)) peak $peak"
    peak > 0 && (header *= " at $(datetime_text(window.low + argmax(running) - 1))")
    [header; details]
end

function execute!(state::Scheduler, line::AbstractString)::Vector{String}
    words = split(line, ' '; keepempty = false)
    command = words[1]
    expected = get(ARITIES, command, nothing)
    isnothing(expected) && fail("unknown command")
    (expected < 0 ? length(words) >= -expected : length(words) == expected) || fail("wrong arguments")
    job = command in ("REMOVE", "RENAME", "ENABLE", "DISABLE", "RUNTIME", "EXPAND", "DESCRIBE",
                      "MATCH", "NEXT", "PREV", "COUNT", "GAP", "OVERLAP", "CALENDAR") ? require_job(state, words[2]) : nothing
    if command == "JOB"
        require_new_id(state, words[2])
        cron = parse_cron(words[3:end])
        state.jobs[words[2]] = SchedulerJob(cron = cron)
        return ["JOB $(words[2]) added"]
    elseif command == "VALIDATE"
        cron = parse_cron(words[2:end])
        return ["VALID $(cron.expanded) $(or_rule(cron) ? "OR" : "AND") $(length(cron.times))"]
    elseif command == "REMOVE"
        delete!(state.jobs, words[2])
        return ["REMOVE $(words[2])"]
    elseif command == "RENAME"
        require_new_id(state, words[3])
        delete!(state.jobs, words[2])
        state.jobs[words[3]] = job
        return ["RENAME $(words[2]) $(words[3])"]
    elseif command == "ENABLE" || command == "DISABLE"
        desired = command == "ENABLE"
        job.enabled == desired && fail(desired ? "already enabled" : "already disabled")
        job.enabled = desired
        return ["$command $(words[2])"]
    elseif command == "RUNTIME"
        duration = positive(words[3], 4, 1440, "invalid duration")
        policy = findfirst(p -> string(p) == words[4], instances(Policy))
        isnothing(policy) && fail("invalid policy")
        job.duration, job.policy = duration, instances(Policy)[policy]
        return ["RUNTIME $(words[2]) $duration $(job.policy)"]
    elseif command == "LIST"
        rows = ["LIST $(length(state.jobs))"]
        for id in ordered_ids(state)
            current = state.jobs[id]
            push!(rows, "$id $(current.enabled ? "on" : "off") $(current.duration) $(current.policy) $(current.cron.text)")
        end
        return rows
    elseif command == "EXPAND"
        index = findfirst(==(words[3]), FIELD_NAMES)
        isnothing(index) && fail("invalid field")
        field = job.cron.fields[index]
        return [join(["EXPAND $(words[2]) $(words[3]) $(length(field.values))"; string.(field.values); special_text.(field.specials)], " ")]
    elseif command == "DESCRIBE"
        return ["DESCRIBE $(words[2]) $(description(job.cron))"]
    elseif command == "MATCH"
        time = read_datetime(words, 3)
        day = time ÷ 1440
        status = day_status(job.cron, day)
        reasons = String[]
        time % 60 in job.cron.fields[1].values || push!(reasons, "minute")
        time ÷ 60 % 24 in job.cron.fields[2].values || push!(reasons, "hour")
        !status.condition && !status.dom && push!(reasons, "day-of-month")
        status.month || push!(reasons, "month")
        !status.condition && !status.dow && push!(reasons, "day-of-week")
        day in state.holidays && push!(reasons, "excluded")
        return ["MATCH $(words[2]) $(datetime_text(time)) " * (isempty(reasons) ? "yes" : "no $(join(reasons, " "))")]
    elseif command == "NEXT" || command == "PREV"
        base = read_datetime(words, 3)
        count = positive(words[5], 2, 50, "invalid count")
        backward = command == "PREV"
        times = fire_times(job.cron, backward ? base - 527040 : base + 1, backward ? base - 1 : base + 527040,
                           state.holidays; backward, limit = count)
        rows = ["$command $(words[2]) $(length(times))"]
        append!(rows, ["$(datetime_text(time)) $(backward ? "-" : "+")$(span_text(abs(time - base)))" for time in times])
        length(times) < count && push!(rows, "NONE")
        return rows
    elseif command == "COUNT"
        window = read_window(words, 3)
        times = fire_times(job.cron, window.low, window.high, state.holidays)
        return ["COUNT $(words[2]) runs $(length(times)) days $(length(unique(times .÷ 1440)))"]
    elseif command == "GAP"
        base = read_datetime(words, 3)
        times = fire_times(job.cron, base, base + 44640, state.holidays)
        length(times) < 2 && return ["GAP $(words[2]) runs $(length(times)) none"]
        gaps = diff(times)
        longest = argmax(gaps)
        histogram = Dict{Int,Int}()
        for gap in gaps
            histogram[gap] = get(histogram, gap, 0) + 1
        end
        rows = ["GAP $(words[2]) runs $(length(times)) shortest $(span_text(minimum(gaps))) longest $(span_text(maximum(gaps))) from $(datetime_text(times[longest])) to $(datetime_text(times[longest + 1]))"]
        append!(rows, ["$(span_text(gap)) $(histogram[gap])" for gap in sort!(collect(keys(histogram)))])
        return rows
    elseif command == "OVERLAP"
        other = require_job(state, words[3])
        window = read_window(words, 4)
        first = fire_times(job.cron, window.low, window.high, state.holidays)
        other_times = Set(fire_times(other.cron, window.low, window.high, state.holidays))
        times = filter(in(other_times), first)
        suffix = isempty(times) ? "" : " first $(datetime_text(times[1])) last $(datetime_text(times[end]))"
        return ["OVERLAP $(words[2]) $(words[3]) $(length(times))$suffix"]
    elseif command in ("TIMELINE", "CONFLICTS", "SIMULATE")
        window = read_window(words, 2)
        return command == "SIMULATE" ? simulation_report(state, window) : combined_report(state, window, command == "CONFLICTS")
    elseif command == "WEEK"
        first = read_date(words[2])
        return week_report(state, first, words[2])
    elseif command == "CALENDAR"
        first = read_month(words[3])
        return calendar_report(state, job, first, words[3], words[2])
    elseif command == "EXCLUDE" || command == "INCLUDE"
        day = read_date(words[2])
        if command == "EXCLUDE"
            day in state.holidays && fail("already excluded")
            push!(state.holidays, day)
        else
            day in state.holidays || fail("not excluded")
            delete!(state.holidays, day)
        end
        return ["$command $(date_text(day)) holidays $(length(state.holidays))"]
    end
    ["HOLIDAYS $(length(state.holidays))"; date_text.(sort!(collect(state.holidays)))]
end

function main()
    state = Scheduler()
    count = parse(Int, readline())
    for _ in 1:count
        line = readline()
        rows = try
            execute!(state, line)
        catch error
            error isa CommandError || rethrow()
            ["ERROR $(error.message)"]
        end
        for row in rows
            println(row)
        end
    end
end
main()
