include("day_rules.jl")
include("tz_parser.jl")
include("transitions.jl")
include("resolver.jl")
include("report.jl")

read_lines(name::String) = readlines(joinpath("input", name))
year_start(year::Int) = day_number(year, 1, 1) * SECONDS_PER_DAY
function clock_seconds(text::String)
    fields = split(text, ':')
    parse(Int, fields[1]) * 3600 + parse(Int, fields[2]) * 60
end
names_or_none(names::Vector{String}, separator::String) = isempty(names) ? "none" : join(names, separator)
indented(lines::Vector{String}) = [index == 1 ? line : "  " * line for (index, line) in enumerate(lines)]
function merge_intervals(intervals::Vector{Tuple{Int,Int}})
    merged = Tuple{Int,Int}[]
    for (low, high) in sort(intervals)
        if !isempty(merged) && low <= merged[end][2]
            merged[end] = (merged[end][1], max(merged[end][2], high))
        else
            push!(merged, (low, high))
        end
    end
    merged
end
function intersect_intervals(first::Vector{Tuple{Int,Int}}, second::Vector{Tuple{Int,Int}})
    pieces = Tuple{Int,Int}[]
    for (a, b) in first, (c, d) in second
        low, high = max(a, c), min(b, d)
        low < high && push!(pieces, (low, high))
    end
    merge_intervals(pieces)
end
mutable struct ZoneLine
    stdoff::Int
    rules_text::String
    rule_set::Union{Nothing,String}
    save::Int
    format::String
    until::Union{Nothing,Until}
    start::Int
    end_time::Int
end
function ZoneLine(fields::Vector{String})
    stdoff = parse_stdoff(fields[1])
    rules_text = fields[2]
    rule_set = nothing
    save = 0
    if '0' <= first(rules_text) <= '9'
        save = parse_save(rules_text)
    elseif rules_text != "-"
        rule_set = rules_text
    end
    check_format(fields[3], rule_set !== nothing)
    until = length(fields) > 3 ? parse_until(fields[4:end]) : nothing
    ZoneLine(stdoff, rules_text, rule_set, save, fields[3], until, NEG_INFINITY, POS_INFINITY)
end
function rules_notation(line::ZoneLine)
    line.rule_set !== nothing && return line.rule_set
    line.rules_text == "-" ? "-" : clock_text(line.save)
end
function until_notation(line::ZoneLine)
    until = line.until
    "$(until.year_text) $(until.month_text) $(until.day_text) $(clock_text(until.time))$(until.time_type)"
end
mutable struct SourceLine
    number::Int
    fields::Vector{String}
    kind::Symbol
    block::Union{Nothing,Int}
    position::Int
    zone_line::Union{Nothing,ZoneLine}
    field_error::Bool
    error::Union{Nothing,String}
end
function SourceLine(number::Int, content::AbstractString)
    fields = split_fields(content)
    kind = if startswith(content, ' ')
        :continuation
    elseif fields[1] == "Rule"
        :rule
    elseif fields[1] == "Zone"
        :zone
    elseif fields[1] == "Link"
        :link
    else
        :unknown
    end
    SourceLine(number, fields, kind, nothing, 0, nothing, false, nothing)
end
accepts_continuation(line::SourceLine) = line.kind == :zone && length(line.fields) >= 6 || line.kind == :continuation && length(line.fields) >= 4
mutable struct Block
    name::String
    number::Int
    lines::Vector{Int}
    defined::Bool
end
Block(first::SourceLine) = Block(first.fields[2], first.number, Int[], false)
struct Zone
    name::String
    lines::Vector{ZoneLine}
    aliases::Vector{String}
    applied::Dict{Int,Int}
    timeline::Timeline
end
function zone_rule_sets(zone::Zone)
    names = String[]
    for line in zone.lines
        if line.rule_set !== nothing && !(line.rule_set in names)
            push!(names, line.rule_set)
        end
    end
    names
end
line_number_at(zone::Zone, time::Int) = findfirst(line -> line.start <= time < line.end_time, zone.lines)
function parse_rule(line::SourceLine)
    fields = line.fields
    from_year = parse_year(fields[3])
    to_year = parse_to(fields[4], from_year)
    fields[5] != "-" && throw(DefinitionFieldError("syntax error"))
    month = parse_month(fields[6])
    day = parse_day_spec(fields[7], month)
    at, kind = parse_time(fields[8])
    save = parse_save(fields[9])
    letter = parse_letter(fields[10])
    Rule(line.number, fields, fields[2], from_year, to_year, month, day, at, kind, save, letter)
end
struct Database
    lines::Vector{SourceLine}
    blocks::Vector{Block}
    rules::Vector{Rule}
    rule_sets::Dict{String,Vector{Int}}
    rule_order::Vector{String}
    sequences::Dict{String,Vector{RuleInstance}}
    zones::Dict{String,Zone}
    aliases::Dict{String,String}
end
function Database(raw_lines::Vector{String})
    lines = SourceLine[]
    for (number, raw) in enumerate(raw_lines)
        content = line_content(raw)
        isempty(content) || push!(lines, SourceLine(number, content))
    end
    database = Database(lines, Block[], Rule[], Dict{String,Vector{Int}}(), String[], Dict{String,Vector{RuleInstance}}(), Dict{String,Zone}(), Dict{String,String}())
    assemble_blocks!(database)
    for line in database.lines
        try
            parse_fields!(database, line)
        catch error
            error isa DefinitionFieldError || rethrow()
            line.field_error = true
            line.error = error.message
        end
    end
    zone_names = Set{String}()
    for line in database.lines
        line.zone_line === nothing || (line.error = structural_error(database, line, zone_names))
    end
    for name in database.rule_order
        database.sequences[name] = instance_sequence(database.rules, database.rule_sets[name])
    end
    for block in database.blocks
        block.defined = all(index -> database.lines[index].error === nothing, block.lines)
        if block.defined
            zone = define_zone(database, block)
            database.zones[zone.name] = zone
        end
    end
    for line in database.lines
        line.kind == :link && line.error === nothing && register_link!(database, line)
    end
    database
end
function assemble_blocks!(database::Database)
    previous = nothing
    for (index, line) in enumerate(database.lines)
        block = nothing
        if line.kind == :zone
            push!(database.blocks, Block(line))
            block = length(database.blocks)
        elseif line.kind == :continuation && previous !== nothing && accepts_continuation(database.lines[previous])
            block = database.lines[previous].block
        end
        if block !== nothing
            line.block = block
            line.position = length(database.blocks[block].lines) + 1
            push!(database.blocks[block].lines, index)
        end
        previous = index
    end
end
function parse_fields!(database::Database, line::SourceLine)
    (line.kind == :unknown || line.kind == :continuation && line.block === nothing) && throw(DefinitionFieldError("syntax error"))
    low, high = line.kind == :rule ? (10, 10) : line.kind == :zone ? (5, 9) : line.kind == :continuation ? (3, 7) : (3, 3)
    low <= length(line.fields) <= high || throw(DefinitionFieldError("syntax error"))
    if line.kind == :rule
        rule = parse_rule(line)
        if !haskey(database.rule_sets, rule.name)
            push!(database.rule_order, rule.name)
            database.rule_sets[rule.name] = Int[]
        end
        push!(database.rules, rule)
        push!(database.rule_sets[rule.name], length(database.rules))
    elseif line.kind == :zone
        line.zone_line = ZoneLine(line.fields[3:end])
    elseif line.kind == :continuation
        line.zone_line = ZoneLine(line.fields)
    end
end
function structural_error(database::Database, line::SourceLine, names::Set{String})
    zone_line = line.zone_line
    if line.kind == :zone
        name = line.fields[2]
        name in names && return "duplicate zone " * name
        push!(names, name)
    end
    if zone_line.rule_set !== nothing && !haskey(database.rule_sets, zone_line.rule_set)
        return "unknown rule " * zone_line.rule_set
    end
    zone_line.until === nothing && return nothing
    block = database.blocks[line.block]
    if line.kind == :continuation
        previous = database.lines[block.lines[line.position - 1]]
        if !previous.field_error && zone_line.until.value <= previous.zone_line.until.value
            return "until not increasing"
        end
    end
    line.position == length(block.lines) ? "missing continuation" : nothing
end
function define_zone(database::Database, block::Block)
    lines = ZoneLine[database.lines[index].zone_line for index in block.lines]
    applied = Dict{Int,Int}()
    switches = Period[]
    start = NEG_INFINITY
    for line in lines
        line.start = start
        line_switches = Tuple{Int,Int,String}[]
        if line.rule_set !== nothing
            instances = database.sequences[line.rule_set]
            run = run_instances(instances, database.rules, line.stdoff, start, line.until)
            line.end_time = run.end_time
            if run.last_pre_start !== nothing
                rule = database.rules[run.last_pre_start]
                push!(line_switches, (start, rule.save, rule.letter))
            else
                standard = findfirst(instance -> database.rules[instance.rule].save == 0, instances)
                letter = standard === nothing ? "" : database.rules[instances[standard].rule].letter
                push!(line_switches, (start, 0, letter))
            end
            for (time, index) in run.applied
                rule = database.rules[index]
                push!(line_switches, (time, rule.save, rule.letter))
                applied[rule.number] = get(applied, rule.number, 0) + 1
            end
        else
            if line.until !== nothing
                line.end_time = line.until.value - adjustment(line.until.time_type, line.stdoff, line.save)
            end
            push!(line_switches, (start, line.save, ""))
        end
        for (time, save, letter) in line_switches
            push!(switches, Period(time, line.stdoff + save, save != 0, abbreviation(line.format, save, letter)))
        end
        start = line.end_time
    end
    periods = Period[]
    for period in switches
        (isempty(periods) || !same_state(periods[end], period)) && push!(periods, period)
    end
    Zone(block.name, lines, String[], applied, Timeline(periods))
end
function register_link!(database::Database, line::SourceLine)
    target, alias = line.fields[2], line.fields[3]
    if !haskey(database.zones, target)
        line.error = "unknown link target " * target
    elseif haskey(database.zones, alias) || haskey(database.aliases, alias)
        line.error = "duplicate link " * alias
    else
        database.aliases[alias] = target
        push!(database.zones[target].aliases, alias)
    end
end
find_zone(database::Database, word::String) = get(database.zones, word, get(database.zones, get(database.aliases, word, ""), nothing))
error_lines(database::Database) = ["line $(line.number): $(line.error)" for line in database.lines if line.error !== nothing]
offset_shift(timeline::Timeline, index::Int) = timeline.periods[index].offset - timeline.periods[index - 1].offset
transitions_between(timeline::Timeline, low::Int, high::Int) = [index for index in 2:length(timeline.periods) if low <= timeline.starts[index] < high]
change_at(timeline::Timeline, index::Int) = change_text(timeline.starts[index], timeline.periods[index - 1], timeline.periods[index])
function transition_line(timeline::Timeline, index::Int)
    time = timeline.starts[index]
    shift = offset_shift(timeline, index)
    kind = shift > 0 ? "gap " * duration_text(shift) : shift < 0 ? "overlap " * duration_text(-shift) : "no shift"
    before = local_text(time + timeline.periods[index - 1].offset)
    after = local_text(time + timeline.periods[index].offset)
    "$(change_at(timeline, index)) (local $before -> $after, $kind)"
end
function shifts_text(timeline::Timeline, indices::Vector{Int})
    gaps = overlaps = unchanged = 0
    for index in indices
        shift = offset_shift(timeline, index)
        if shift > 0
            gaps += 1
        elseif shift < 0
            overlaps += 1
        else
            unchanged += 1
        end
    end
    "gaps $gaps, overlaps $overlaps, no shift $unchanged"
end
function candidate_text(timeline::Timeline, local_time::Int, index::Int)
    period = timeline.periods[index]
    "$(ut_text(local_time - period.offset)) ($(state_text(period)))"
end
function chosen_candidate(found::Vector{Int}, option::Union{Nothing,String})
    length(found) == 1 && return found[1]
    if length(found) == 2
        option == "EARLIER" && return found[1]
        option == "LATER" && return found[2]
    end
    nothing
end
function unresolved_text(timeline::Timeline, local_time::Int, found::Vector{Int})
    !isempty(found) && return "AMBIGUOUS " * join([candidate_text(timeline, local_time, index) for index in found], " or ")
    index = skipping_transition(timeline, local_time)
    time = timeline.starts[index]
    before = local_text(time + timeline.periods[index - 1].offset)
    after = local_text(time + timeline.periods[index].offset)
    "NONEXISTENT gap $before to $after at $(ut_text(time))"
end
function working_hours(timeline::Timeline, start::Int, end_time::Int)
    pieces = Tuple{Int,Int}[]
    for index in nearby(timeline, start, end_time)
        period = timeline.periods[index]
        low = max(start - period.offset, period.start)
        high = min(end_time - period.offset, end_of(timeline, index))
        low < high && push!(pieces, (low, high))
    end
    merge_intervals(pieces)
end
function parse_value(kind::Symbol, word::String)
    year = parse(Int, word[1:4])
    MIN_YEAR <= year <= MAX_YEAR || return nothing
    kind == :year && return year
    month, day = parse(Int, word[6:7]), parse(Int, word[9:10])
    (1 <= month <= 12 && 1 <= day <= days_in_month(year, month)) || return nothing
    kind == :date && return day_number(year, month, day)
    hour, minute, second = parse(Int, word[12:13]), parse(Int, word[15:16]), parse(Int, word[18:19])
    (hour <= 23 && minute <= 59 && second <= 59) || return nothing
    time_value(year, month, day, hour, minute, second)
end
struct QueryError <: Exception
    message::String
end
abstract type QueryArgument end
struct ZoneArgument <: QueryArgument
    zone::Zone
end
struct NumericArgument <: QueryArgument
    value::Int
end
zone_value(argument::ZoneArgument) = argument.zone
numeric_value(argument::NumericArgument) = argument.value
function argument_kinds(command::String, argument_count::Int)
    command == "TOUTC" && return [:zone, :local]
    command in ("TOLOCAL", "OFFSET") && return [:zone, :ut]
    command == "CONVERT" && return [:zone, :zone, :local]
    command == "TRANSITIONS" && return [:zone, :year, :year]
    command == "DURATION" && return [:zone, :local, :local]
    vcat(:date, fill(:zone, argument_count - 1))
end
function process_query(database::Database, line::String, work_start::Int, work_end::Int)
    words = String.(split(line, ' '))
    command = popfirst!(words)
    option = nothing
    if command in ("TOUTC", "CONVERT") && words[end] in ("EARLIER", "LATER")
        option = pop!(words)
    end
    values = QueryArgument[]
    for (kind, word) in zip(argument_kinds(command, length(words)), words)
        if kind == :zone
            zone = find_zone(database, word)
            zone === nothing && throw(QueryError("unknown zone " * word))
            push!(values, ZoneArgument(zone))
        else
            value = parse_value(kind, word)
            value === nothing && throw(QueryError("invalid value " * word))
            push!(values, NumericArgument(value))
        end
    end
    if command == "MEETING"
        day = numeric_value(values[1])
        start = day * SECONDS_PER_DAY + work_start
        end_time = day * SECONDS_PER_DAY + work_end
        zones = [zone_value(value) for value in values[2:end]]
        common = working_hours(zones[1].timeline, start, end_time)
        for zone in zones[2:end]
            common = intersect_intervals(common, working_hours(zone.timeline, start, end_time))
        end
        parts = String[]
        for (low, high) in common
            members = String[]
            for (word, zone) in zip(words[2:end], zones)
                period = period_at(zone.timeline, low)
                push!(members, "$word $(local_text(low + period.offset)) $(period.abbreviation)")
            end
            push!(parts, "$(ut_text(low)) to $(ut_text(high)) ($(duration_text(high - low))) [$(join(members, ", "))]")
        end
        return (isempty(parts) ? "NONE" : join(parts, "; "), nothing)
    elseif command == "CONVERT"
        source, target, local_time = zone_value(values[1]), zone_value(values[2]), numeric_value(values[3])
        found = candidates(source.timeline, local_time)
        index = chosen_candidate(found, option)
        index === nothing && return (unresolved_text(source.timeline, local_time, found), nothing)
        time = local_time - source.timeline.periods[index].offset
        period = period_at(target.timeline, time)
        target_local = time + period.offset
        shift = fld(target_local, SECONDS_PER_DAY) - fld(local_time, SECONDS_PER_DAY)
        shift_text = shift > 0 ? "+$shift" : string(shift)
        return "$(local_text(target_local)) ($(state_text(period))) at $(ut_text(time)), day shift $shift_text", nothing
    end
    timeline = zone_value(values[1]).timeline
    first_value = numeric_value(values[2])
    if command == "TOUTC"
        found = candidates(timeline, first_value)
        index = chosen_candidate(found, option)
        return (index === nothing ? unresolved_text(timeline, first_value, found) : candidate_text(timeline, first_value, index), nothing)
    elseif command == "TOLOCAL"
        period = period_at(timeline, first_value)
        return "$(local_text(first_value + period.offset)) ($(state_text(period)))", nothing
    elseif command == "OFFSET"
        index = index_at(timeline, first_value)
        text = state_text(timeline.periods[index])
        index > 1 && (text *= " since " * ut_text(timeline.starts[index]))
        index < length(timeline.periods) && (text *= " until " * ut_text(timeline.starts[index + 1]))
        return text, nothing
    elseif command == "TRANSITIONS"
        last_year = numeric_value(values[3])
        first_value > last_year && throw(QueryError("invalid range"))
        selected = transitions_between(timeline, year_start(first_value), year_start(last_year + 1))
        block = vcat([line], [transition_line(timeline, index) for index in selected], [shifts_text(timeline, selected)])
        return "transitions: $(length(selected))", block
    end
    locals = [first_value, numeric_value(values[3])]
    offsets = Int[]
    for (position, local_time) in enumerate(locals)
        found = candidates(timeline, local_time)
        length(found) == 2 && return ("AMBIGUOUS " * words[position + 1], nothing)
        isempty(found) && return ("NONEXISTENT " * words[position + 1], nothing)
        push!(offsets, timeline.periods[found[1]].offset)
    end
    elapsed = (locals[2] - offsets[2]) - (locals[1] - offsets[1])
    "$(elapsed) s ($(duration_text(elapsed))), wall clock $(duration_text(locals[2] - locals[1])), offset change $(offset_text(offsets[2] - offsets[1]))", nothing
end
function rule_text(rule::Rule)
    fields = rule.fields
    "rule $(rule.name) $(fields[3]) $(fields[4]) $(fields[6]) $(fields[7]) $(clock_text(rule.at))$(rule.at_type) $(clock_text(rule.save)) $(fields[10])"
end
function database_block(database::Database)
    rule_lines = [line for line in database.lines if line.kind == :rule]
    link_lines = [line for line in database.lines if line.kind == :link]
    valid_rules = count(line -> line.error === nothing, rule_lines)
    valid_links = count(line -> line.error === nothing, link_lines)
    zones = collect(values(database.zones))
    used = Set{String}()
    for zone in zones
        union!(used, zone_rule_sets(zone))
    end
    unused = [name for name in database.rule_order if !(name in used)]
    invalid = ["$(block.name) (line $(block.number))" for block in database.blocks if !block.defined]
    zone_lines = sum((length(zone.lines) for zone in zones); init = 0)
    lines = ["DATABASE", "rule lines: $valid_rules valid, $(length(rule_lines) - valid_rules) invalid",
        "zones: $(length(zones)) defined, $(length(database.blocks) - length(zones)) invalid", "zone lines: $zone_lines in defined zones",
        "links: $valid_links defined, $(length(link_lines) - valid_links) invalid", "errors: $(length(error_lines(database)))",
        "unused rules: " * names_or_none(unused, " "), "invalid zones: " * names_or_none(invalid, ", ")]
    for name in database.rule_order
        rules = database.rules[database.rule_sets[name]]
        first_year = minimum(rule.from_year for rule in rules)
        last_year = any(rule -> rule.fields[4] == "max", rules) ? "max" : string(maximum(rule.to_year for rule in rules))
        zone_count = count(zone -> name in zone_rule_sets(zone), zones)
        push!(lines, "rule set $name: lines $(length(rules)), years $first_year-$last_year, zones $zone_count")
    end
    lines
end
function dst_lines(timeline::Timeline, reference::Int)
    indices = [index for index in eachindex(timeline.periods) if timeline.periods[index].dst]
    if isempty(indices)
        lines = ["dst years: none"]
    else
        years = [split_time(timeline.starts[index])[1] for index in indices]
        lines = ["dst years: $(minimum(years))-$(maximum(years))"]
    end
    year = split_time(reference)[1]
    low, high = year_start(year), year_start(year + 1)
    pieces = Tuple{Int,Int}[]
    for index in indices
        start, end_time = max(low, timeline.starts[index]), min(high, end_of(timeline, index))
        start < end_time && push!(pieces, (start, end_time))
    end
    total = 0
    for (start, end_time) in merge_intervals(pieces)
        push!(lines, "dst period: $(ut_text(start)) to $(ut_text(end_time)) ($(duration_text(end_time - start)))")
        total += end_time - start
    end
    push!(lines, "dst total $year: $(duration_text(total))")
    lines
end
function zone_block(database::Database, zone::Zone, reference::Int)
    timeline = zone.timeline
    periods = timeline.periods
    lines = ["ZONE " * zone.name, "aliases: " * names_or_none(zone.aliases, " ")]
    for (number, line) in enumerate(zone.lines)
        text = "line $number: $(offset_text(line.stdoff)) $(rules_notation(line)) $(line.format)"
        number > 1 && (text *= " from " * ut_text(line.start))
        line.until !== nothing && (text *= " until $(until_notation(line)) = $(ut_text(line.end_time))")
        push!(lines, "$text, transitions $(length(transitions_between(timeline, line.start, line.end_time)))")
    end
    for name in zone_rule_sets(zone), index in database.rule_sets[name]
        rule = database.rules[index]
        push!(lines, "$(rule_text(rule)), applied $(get(zone.applied, rule.number, 0))")
    end
    offsets = [period.offset for period in periods]
    push!(lines, "offset range: $(offset_text(minimum(offsets))) to $(offset_text(maximum(offsets)))")
    states = String[]
    state_counts = Int[]
    for period in periods
        state = state_text(period)
        index = findfirst(==(state), states)
        if index === nothing
            push!(states, state)
            push!(state_counts, 1)
        else
            state_counts[index] += 1
        end
    end
    for (state, frequency) in zip(states, state_counts)
        push!(lines, "state $state, periods $frequency")
    end
    index = index_at(timeline, reference)
    period = periods[index]
    push!(lines, "reference: $(local_text(reference + period.offset)) ($(state_text(period))), line $(line_number_at(zone, reference))")
    previous = index > 1 ? change_at(timeline, index) : "none"
    next = index < length(periods) ? change_at(timeline, index + 1) : "none"
    push!(lines, "previous transition: " * previous)
    push!(lines, "next transition: " * next)
    every = collect(2:length(periods))
    push!(lines, "transitions: $(length(every)), $(shifts_text(timeline, every))")
    append!(lines, dst_lines(timeline, reference))
    lines
end
function main()
    database = Database(read_lines("tzdata.txt"))
    params = read_lines("params.txt")
    reference = parse_value(:ut, String(split(params[1], ' ')[2]))
    work = String.(split(params[2], ' '))
    work_start, work_end = clock_seconds(work[2]), clock_seconds(work[3])
    answers = String[]
    transition_blocks = Vector{String}[]
    for line in read_lines("queries.txt")
        try
            result, block = process_query(database, line, work_start, work_end)
            push!(answers, line * " => " * result)
            block === nothing || push!(transition_blocks, block)
        catch error
            error isa QueryError || rethrow()
            push!(answers, line * " => ERROR " * error.message)
        end
    end
    blocks = [indented(database_block(database))]
    for name in sort!(collect(keys(database.zones)))
        push!(blocks, indented(zone_block(database, database.zones[name], reference)))
    end
    mkpath("output")
    write_lines("output/answers.txt", answers)
    write_lines("output/errors.txt", error_lines(database))
    write_blocks("output/transitions.txt", transition_blocks)
    write_blocks("output/zone_summary.txt", blocks)
end

main()
