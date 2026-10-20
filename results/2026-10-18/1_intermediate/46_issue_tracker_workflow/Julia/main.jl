const TYPES = ("BUG", "TASK", "STORY")
const PRIORITIES = ("LOW", "MEDIUM", "HIGH", "CRITICAL")
const WORKFLOWS = Dict(
    "BUG" => ["OPEN", "TRIAGED", "IN_PROGRESS", "REVIEW", "RESOLVED", "CLOSED", "REOPENED"],
    "TASK" => ["OPEN", "IN_PROGRESS", "DONE"],
    "STORY" => ["BACKLOG", "READY", "IN_PROGRESS", "REVIEW", "DONE"],
)
const TRANSITIONS = Dict(
    "BUG" => Set([("OPEN", "TRIAGED"), ("TRIAGED", "IN_PROGRESS"), ("IN_PROGRESS", "REVIEW"),
                  ("REVIEW", "IN_PROGRESS"), ("REVIEW", "RESOLVED"), ("RESOLVED", "CLOSED"),
                  ("RESOLVED", "REOPENED"), ("CLOSED", "REOPENED"), ("REOPENED", "IN_PROGRESS")]),
    "TASK" => Set([("OPEN", "IN_PROGRESS"), ("IN_PROGRESS", "OPEN"), ("IN_PROGRESS", "DONE")]),
    "STORY" => Set([("BACKLOG", "READY"), ("READY", "BACKLOG"), ("READY", "IN_PROGRESS"),
                    ("IN_PROGRESS", "REVIEW"), ("REVIEW", "IN_PROGRESS"), ("REVIEW", "DONE")]),
)
const DONE_STATES = ("RESOLVED", "CLOSED", "DONE")
const ESTIMATES = (0, 1, 2, 3, 5, 8, 13, 21)
const EQUALITY = ("=", "!=")
const ORDERING = ("=", "!=", "<", "<=", ">", ">=")
const FIELD_OPERATORS = Dict(
    "id" => ORDERING, "type" => EQUALITY, "status" => EQUALITY, "priority" => ORDERING,
    "assignee" => EQUALITY, "reviewer" => EQUALITY, "estimate" => ORDERING,
    "sprint" => EQUALITY, "comments" => ORDERING, "blocked" => EQUALITY, "done" => EQUALITY,
    "title" => ("~",),
)
struct CommandError <: Exception
    reason::String
end
fail(reason) = throw(CommandError(reason))
display_value(value) = isnothing(value) ? "-" : string(value)
yes_no(value) = value ? "yes" : "no"
number_list(ids) = isempty(ids) ? "-" : join(sort!(collect(ids)), ',')

mutable struct Issue
    number::Int
    kind::String
    priority::String
    title::String
    state::String
    assignee::String
    reviewer::String
    estimate::Union{Nothing,Int}
    sprint::String
    comments::Int
    blocks::Set{Int}
    blockers::Set{Int}
    duplicate::Union{Nothing,Int}
    duplicates::Set{Int}
    history::Vector{String}
end
Issue(n, kind, priority, title) = Issue(n, kind, priority, title, WORKFLOWS[kind][1],
    "-", "-", nothing, "-", 0, Set{Int}(), Set{Int}(), nothing, Set{Int}(), String[])
done(i::Issue) = i.state in DONE_STATES
points(i::Issue) = isnothing(i.estimate) ? 0 : i.estimate
level(i::Issue) = findfirst(==(i.priority), PRIORITIES)

mutable struct Sprint
    name::String
    phase::String
    start::Int
    finish::Int
    velocity::Int
    records::Dict{Int,Int}
end
Sprint(name) = Sprint(name, "PLANNED", 0, 0, 0, Dict{Int,Int}())
mutable struct Tracker
    day::Int
    users::Set{String}
    issues::Dict{Int,Issue}
    sprints::Dict{String,Sprint}
    sprint_order::Vector{String}
end
Tracker() = Tracker(1, Set{String}(), Dict{Int,Issue}(), Dict{String,Sprint}(), String[])

function require_issue(t, id)
    n = parse(Int, id)
    haskey(t.issues, n) || fail("unknown issue")
    return t.issues[n]
end
function require_user(t, user)
    user != "-" && user ∉ t.users && fail("unknown user")
    return user
end
function require_sprint(t, name)
    haskey(t.sprints, name) || fail("unknown sprint")
    return t.sprints[name]
end
not_done(i) = done(i) && fail("issue done")
ordered_issues(t) = sort!(collect(values(t.issues)); by=i -> i.number)
unfinished_blockers(t, i) = sort!([id for id in i.blockers if !done(t.issues[id])])
blocked(t, i) = !done(i) && !isempty(unfinished_blockers(t, i))
wip_count(t, user) = count(i -> i.assignee == user && i.state == "IN_PROGRESS", values(t.issues))
function active_sprint(t)
    for name in t.sprint_order
        t.sprints[name].phase == "ACTIVE" && return t.sprints[name]
    end
    return nothing
end
members(t, s) = [i for i in ordered_issues(t) if i.sprint == s.name]
remaining(t, s) = sum((points(i) for i in members(t, s) if !done(i)); init=0)
function sprint_summary(t, s)
    ids = members(t, s)
    return "issues $(length(ids)) points $(sum((points(i) for i in ids); init=0))"
end
record!(t, i, content) = push!(i.history, "day $(t.day) $content")
blocked_states(t, ids) = Dict(id => blocked(t, t.issues[id]) for id in ids)
function notifications(t, before)
    lines = String[]
    for id in sort!(collect(keys(before)))
        after = blocked(t, t.issues[id])
        if after != before[id]
            push!(lines, "$(after ? "BLOCKED" : "UNBLOCKED") $id")
        end
    end
    return lines
end
function change_state!(t, i, target)
    before = blocked_states(t, i.blocks)
    previous = i.state
    record!(t, i, "MOVE $previous $target")
    i.state = target
    return vcat(["MOVE $(i.number) $previous $target"], notifications(t, before))
end
function reaches(t, start, goal)
    pending = [start]
    visited = Set{Int}()
    while !isempty(pending)
        id = pop!(pending)
        id == goal && return true
        id in visited && continue
        push!(visited, id)
        append!(pending, t.issues[id].blocks)
    end
    return false
end

abstract type QueryNode end
struct QueryCondition <: QueryNode
    field::String
    operator::String
    value::Union{Nothing,Int,String}
end
struct NotNode <: QueryNode
    child::QueryNode
end
struct BinaryNode <: QueryNode
    operator::String
    left::QueryNode
    right::QueryNode
end
function condition(t, token)
    m = match(r"^([a-z]*)(>=|<=|!=|=|<|>|~)(.*)$", token)
    isnothing(m) && fail("syntax near $token")
    field, op, text = String.(m.captures)
    (isempty(field) || isempty(text)) && fail("syntax near $token")
    haskey(FIELD_OPERATORS, field) || fail("unknown field $field")
    op in FIELD_OPERATORS[field] || fail("bad operator $token")
    value = if field in ("id", "estimate", "comments") && occursin(r"^[0-9]{1,6}$", text)
        parse(Int, text)
    elseif field == "estimate" && text == "-" && op in EQUALITY
        nothing
    elseif field == "priority" && text in PRIORITIES
        findfirst(==(text), PRIORITIES)
    elseif field == "type" && text in TYPES
        text
    elseif field == "status" && any(states -> text in states, values(WORKFLOWS))
        text
    elseif field in ("assignee", "reviewer") && (text == "-" || text in t.users)
        text
    elseif field == "sprint" && (text == "-" || haskey(t.sprints, text))
        text
    elseif field in ("blocked", "done") && text in ("yes", "no")
        text
    elseif field == "title"
        lowercase(text)
    else
        fail("bad value $token")
    end
    return QueryCondition(field, op, value)
end
mutable struct QueryParser
    tokens::Vector{String}
    conditions::Vector{Union{Nothing,QueryCondition}}
    position::Int
end
function accept!(p, token)
    if p.position <= length(p.tokens) && p.tokens[p.position] == token
        p.position += 1
        return true
    end
    return false
end
function parse_factor!(p)
    accept!(p, "NOT") && return NotNode(parse_factor!(p))
    if accept!(p, "(")
        node = parse_expression!(p)
        accept!(p, ")")
        return node
    end
    node = p.conditions[p.position]
    p.position += 1
    return node
end
function parse_term!(p)
    node = parse_factor!(p)
    while accept!(p, "AND")
        node = BinaryNode("AND", node, parse_factor!(p))
    end
    return node
end
function parse_expression!(p)
    node = parse_term!(p)
    while accept!(p, "OR")
        node = BinaryNode("OR", node, parse_term!(p))
    end
    return node
end
function parse_query(t, text)
    tokens = [String(m.match) for m in eachmatch(r"[()]|[^ ()]+", text)]
    conditions = Union{Nothing,QueryCondition}[nothing for _ in tokens]
    operand, depth = true, 0
    for (i, token) in enumerate(tokens)
        if operand
            if token == "("
                depth += 1
            elseif token in ("AND", "OR", ")")
                fail("syntax near $token")
            elseif token != "NOT"
                conditions[i] = condition(t, token)
                operand = false
            end
        elseif token in ("AND", "OR")
            operand = true
        elseif token == ")" && depth > 0
            depth -= 1
        else
            fail("syntax near $token")
        end
    end
    (operand || depth != 0) && fail("syntax at end")
    return parse_expression!(QueryParser(tokens, conditions, 1))
end
function field_value(t, i, field)
    field == "id" && return i.number
    field == "type" && return i.kind
    field == "status" && return i.state
    field == "priority" && return level(i)
    field == "assignee" && return i.assignee
    field == "reviewer" && return i.reviewer
    field == "estimate" && return i.estimate
    field == "sprint" && return i.sprint
    field == "comments" && return i.comments
    field == "blocked" && return yes_no(blocked(t, i))
    field == "done" && return yes_no(done(i))
    return lowercase(i.title)
end
matches(n::NotNode, t, i) = !matches(n.child, t, i)
matches(n::BinaryNode, t, i) = n.operator == "AND" ?
    matches(n.left, t, i) && matches(n.right, t, i) : matches(n.left, t, i) || matches(n.right, t, i)
function matches(n::QueryCondition, t, i)
    actual = field_value(t, i, n.field)
    n.operator == "~" && return occursin(n.value, actual)
    n.operator == "=" && return actual == n.value
    n.operator == "!=" && return actual != n.value
    isnothing(actual) && return false
    n.operator == "<" && return actual < n.value
    n.operator == "<=" && return actual <= n.value
    n.operator == ">" && return actual > n.value
    return actual >= n.value
end

function process_sprint!(t, args)
    cmd, name = args[1:2]
    if cmd == "NEW"
        haskey(t.sprints, name) && fail("sprint exists")
        t.sprints[name] = Sprint(name)
        push!(t.sprint_order, name)
        return ["SPRINT NEW $name"]
    end
    s = require_sprint(t, name)
    if cmd in ("ADD", "REMOVE")
        i = require_issue(t, args[3])
        s.phase == "ENDED" && fail("sprint ended")
        if cmd == "ADD"
            not_done(i)
            i.sprint != "-" && t.sprints[i.sprint].phase != "ENDED" && fail("in sprint $(i.sprint)")
            i.state == "BACKLOG" && fail("not ready")
            i.sprint = name
        else
            i.sprint != name && fail("not in sprint")
            not_done(i)
            i.sprint = "-"
        end
        record!(t, i, "SPRINT $cmd $name")
        return ["SPRINT $cmd $name $(i.number) $(sprint_summary(t, s))"]
    elseif cmd == "START"
        s.phase != "PLANNED" && fail("sprint not planned")
        active = active_sprint(t)
        !isnothing(active) && fail("sprint active $(active.name)")
        isempty(members(t, s)) && fail("sprint empty")
        s.phase, s.start = "ACTIVE", t.day
        s.records[t.day] = remaining(t, s)
        return ["SPRINT START $name day $(t.day) $(sprint_summary(t, s)) remaining $(remaining(t, s))"]
    end
    s.phase != "ACTIVE" && fail("sprint not active")
    s.records[t.day] = remaining(t, s)
    ids = members(t, s)
    finished, returned = filter(done, ids), filter(i -> !done(i), ids)
    s.velocity = sum((points(i) for i in finished); init=0)
    s.phase, s.finish = "ENDED", t.day
    lines = ["SPRINT END $name day $(t.day) velocity $(s.velocity) done $(length(finished)) returned $(length(returned))"]
    for i in returned
        i.sprint = "-"
        record!(t, i, "SPRINT RETURN $name")
        push!(lines, "RETURNED $(i.number)")
    end
    return lines
end
function process_command!(t, line)
    words = String.(split(line, ' '))
    cmd, args = words[1], words[2:end]
    if cmd == "DAY"
        day = parse(Int, args[1])
        day < t.day && fail("day backwards")
        t.day = day
        return ["DAY $day"]
    elseif cmd == "USER"
        user = args[1]
        user in t.users && fail("user exists")
        push!(t.users, user)
        return ["USER $user"]
    elseif cmd == "CREATE"
        id, kind, priority = parse(Int, args[1]), args[2], args[3]
        haskey(t.issues, id) && fail("issue exists")
        kind in TYPES || fail("bad type")
        priority in PRIORITIES || fail("bad priority")
        i = Issue(id, kind, priority, join(args[4:end], ' '))
        t.issues[id] = i
        record!(t, i, "CREATE $kind $priority")
        return ["CREATE $id $kind $priority $(i.state)"]
    elseif cmd == "SPRINT"
        return process_sprint!(t, args)
    elseif cmd == "QUERY"
        tree = parse_query(t, join(args, ' '))
        found = [i for i in values(t.issues) if matches(tree, t, i)]
        sort!(found; by=i -> (-level(i), i.number))
        lines = ["QUERY $(length(found))"]
        for i in found
            push!(lines, "$(i.number) $(i.kind) $(i.priority) $(i.state) $(i.assignee) $(display_value(i.estimate)) $(i.title)")
        end
        return lines
    elseif cmd == "BOARD"
        lines = ["BOARD"]
        for kind in TYPES
            parts = [kind]
            for state in WORKFLOWS[kind]
                count_issue = count(i -> i.kind == kind && i.state == state, values(t.issues))
                push!(parts, state, string(count_issue))
            end
            push!(lines, join(parts, ' '))
        end
        finished = count(done, values(t.issues))
        push!(lines, "TOTAL $(length(t.issues)) open $(length(t.issues) - finished) done $finished")
        return lines
    elseif cmd == "WORKLOAD"
        lines = ["WORKLOAD $(length(t.users))"]
        for user in sort!(collect(t.users))
            assigned = [i for i in values(t.issues) if i.assignee == user && !done(i)]
            progress = count(i -> i.state == "IN_PROGRESS", assigned)
            review = count(i -> i.state == "REVIEW", assigned)
            reviewing = count(i -> i.reviewer == user && i.state == "REVIEW", values(t.issues))
            total = sum((points(i) for i in assigned); init=0)
            push!(lines, "$user assigned $(length(assigned)) in_progress $progress review $review reviewing $reviewing points $total")
        end
        return lines
    elseif cmd == "SPRINTS"
        lines = ["SPRINTS $(length(t.sprints))"]
        for name in t.sprint_order
            s = t.sprints[name]
            if s.phase == "PLANNED"
                push!(lines, "$name PLANNED $(sprint_summary(t, s))")
            elseif s.phase == "ACTIVE"
                push!(lines, "$name ACTIVE start $(s.start) $(sprint_summary(t, s)) remaining $(remaining(t, s))")
            else
                push!(lines, "$name ENDED start $(s.start) end $(s.finish) velocity $(s.velocity)")
            end
        end
        return lines
    elseif cmd == "BURNDOWN"
        s = require_sprint(t, args[1])
        s.phase == "PLANNED" && fail("sprint not started")
        last = s.phase == "ACTIVE" ? t.day : s.finish
        lines = ["BURNDOWN $(s.name) $(s.phase) days $(last - s.start + 1)"]
        value = 0
        for day in s.start:last
            value = get(s.records, day, value)
            push!(lines, "day $day $value")
        end
        return lines
    elseif cmd == "LINK" || cmd == "UNLINK"
        relation = args[2]
        relation in (cmd == "LINK" ? ("BLOCKS", "DUPLICATES") : ("BLOCKS",)) || fail("bad link")
        a, b = require_issue(t, args[1]), require_issue(t, args[3])
        if cmd == "UNLINK"
            b.number in a.blocks || fail("no link")
            before = blocked_states(t, [b.number])
            delete!(a.blocks, b.number)
            delete!(b.blockers, a.number)
            record!(t, a, "UNLINK BLOCKS $(b.number)")
            record!(t, b, "UNLINK BLOCKED_BY $(a.number)")
            return vcat(["UNLINK $(a.number) BLOCKS $(b.number)"], notifications(t, before))
        end
        a === b && fail("self link")
        if relation == "BLOCKS"
            b.number in a.blocks && fail("link exists")
            reaches(t, b.number, a.number) && fail("cycle")
            not_done(b)
            before = blocked_states(t, [b.number])
            push!(a.blocks, b.number)
            push!(b.blockers, a.number)
            record!(t, a, "LINK BLOCKS $(b.number)")
            record!(t, b, "LINK BLOCKED_BY $(a.number)")
            return vcat(["LINK $(a.number) BLOCKS $(b.number)"], notifications(t, before))
        end
        a.kind != b.kind && fail("type mismatch")
        not_done(a)
        !isnothing(b.duplicate) && fail("target is duplicate")
        a.duplicate = b.number
        push!(b.duplicates, a.number)
        record!(t, a, "LINK DUPLICATES $(b.number)")
        record!(t, b, "LINK DUPLICATED_BY $(a.number)")
        lines = vcat(["LINK $(a.number) DUPLICATES $(b.number)"], change_state!(t, a, a.kind == "BUG" ? "CLOSED" : "DONE"))
        if a.sprint != "-" && t.sprints[a.sprint].phase != "ENDED"
            record!(t, a, "SPRINT REMOVE $(a.sprint)")
            a.sprint = "-"
        end
        return lines
    end
    i = require_issue(t, args[1])
    id = i.number
    if cmd == "SHOW"
        return ["ISSUE $id $(i.kind) $(i.priority) $(i.state) blocked $(yes_no(blocked(t, i)))",
                "TITLE $(i.title)", "PEOPLE assignee $(i.assignee) reviewer $(i.reviewer)",
                "PLAN estimate $(display_value(i.estimate)) sprint $(i.sprint) comments $(i.comments)",
                "LINKS blocks $(number_list(i.blocks)) blocked_by $(number_list(i.blockers)) duplicate_of $(display_value(i.duplicate)) duplicated_by $(number_list(i.duplicates))"]
    elseif cmd == "HISTORY"
        return vcat(["HISTORY $id $(length(i.history))"], i.history)
    elseif cmd == "COMMENT"
        user = require_user(t, args[2])
        i.comments += 1
        record!(t, i, "COMMENT $user $(join(args[3:end], ' '))")
        return ["COMMENT $id $(i.comments)"]
    end
    target = args[2]
    if cmd == "PRIORITY"
        target in PRIORITIES || fail("bad priority")
        not_done(i)
        target == i.priority && fail("no change")
        old = i.priority
        i.priority = target
        record!(t, i, "PRIORITY $old $target")
        return ["PRIORITY $id $old $target"]
    elseif cmd == "ASSIGN" || cmd == "REVIEWER"
        require_user(t, target)
        not_done(i)
        target == (cmd == "ASSIGN" ? i.assignee : i.reviewer) && fail("no change")
        if cmd == "ASSIGN"
            target == "-" && i.state in ("IN_PROGRESS", "REVIEW") && fail("assignee required")
            i.state == "IN_PROGRESS" && wip_count(t, target) >= 3 && fail("wip limit $target")
            i.state == "REVIEW" && target == i.reviewer && fail("reviewer is assignee")
            i.assignee = target
        else
            target == "-" && i.state == "REVIEW" && fail("reviewer required")
            i.state == "REVIEW" && target == i.assignee && fail("reviewer is assignee")
            i.reviewer = target
        end
        record!(t, i, "$cmd $target")
        return ["$cmd $id $target"]
    elseif cmd == "ESTIMATE"
        value = parse(Int, target)
        value in ESTIMATES || fail("bad estimate")
        not_done(i)
        value == i.estimate && fail("no change")
        old = display_value(i.estimate)
        i.estimate = value
        record!(t, i, "ESTIMATE $old $value")
        return ["ESTIMATE $id $old $value"]
    end
    !isnothing(i.duplicate) && fail("duplicate of $(i.duplicate)")
    target in WORKFLOWS[i.kind] || fail("bad state")
    (i.state, target) in TRANSITIONS[i.kind] || fail("cannot move $(i.state) to $target")
    if target == "IN_PROGRESS"
        active = active_sprint(t)
        i.kind == "STORY" && (isnothing(active) || i.sprint != active.name) && fail("not in active sprint")
        i.assignee == "-" && fail("no assignee")
        wip_count(t, i.assignee) >= 3 && fail("wip limit $(i.assignee)")
    elseif target == "REVIEW"
        i.reviewer == "-" && fail("no reviewer")
        i.reviewer == i.assignee && fail("reviewer is assignee")
    end
    if target in ("DONE", "RESOLVED")
        blockers = unfinished_blockers(t, i)
        !isempty(blockers) && fail("blocked by $(first(blockers))")
    end
    target == "READY" && isnothing(i.estimate) && fail("no estimate")
    return change_state!(t, i, target)
end
function execute!(t, line)
    result = try
        process_command!(t, line)
    catch err
        err isa CommandError || rethrow()
        ["ERROR $(err.reason)"]
    end
    active = active_sprint(t)
    !isnothing(active) && (active.records[t.day] = remaining(t, active))
    return result
end
function main()
    tracker = Tracker()
    count = parse(Int, readline())
    for _ in 1:count
        for line in execute!(tracker, readline())
            println(line)
        end
    end
end
main()
