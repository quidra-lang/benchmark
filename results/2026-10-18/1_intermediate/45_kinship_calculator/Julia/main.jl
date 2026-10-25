const SCALE = 1 << 37
const SEX_INDEX = Dict("M" => 1, "F" => 2, "X" => 3)
const ORDINALS = ("first", "second", "third", "fourth", "fifth",
                  "sixth", "seventh", "eighth", "ninth", "tenth")
const TERMS = Dict(
    "parent" => ("father", "mother", "parent"),
    "child" => ("son", "daughter", "child"),
    "sibling" => ("brother", "sister", "sibling"),
    "pibling" => ("uncle", "aunt", "pibling"),
    "nibling" => ("nephew", "niece", "nibling"),
    "spouse" => ("husband", "wife", "spouse"),
    "late" => ("late husband", "late wife", "late spouse"),
    "survivor" => ("widower", "widow", "surviving spouse"),
    "ex" => ("ex-husband", "ex-wife", "ex-spouse"),
    "stepparent" => ("stepfather", "stepmother", "stepparent"),
    "stepchild" => ("stepson", "stepdaughter", "stepchild"),
    "stepsibling" => ("stepbrother", "stepsister", "stepsibling"),
    "stepgrandparent" => ("stepgrandfather", "stepgrandmother", "stepgrandparent"),
    "stepgrandchild" => ("stepgrandson", "stepgranddaughter", "stepgrandchild"),
    "parent-in-law" => ("father-in-law", "mother-in-law", "parent-in-law"),
    "child-in-law" => ("son-in-law", "daughter-in-law", "child-in-law"),
    "sibling-in-law" => ("brother-in-law", "sister-in-law", "sibling-in-law"),
)
const STEPS = Dict(
    "parent" => ("parent", nothing), "father" => ("parent", "M"),
    "mother" => ("parent", "F"), "child" => ("child", nothing),
    "son" => ("child", "M"), "daughter" => ("child", "F"),
    "sibling" => ("sibling", nothing), "brother" => ("sibling", "M"),
    "sister" => ("sibling", "F"), "spouse" => ("spouse", nothing),
    "husband" => ("spouse", "M"), "wife" => ("spouse", "F"),
)
const MODIFYING = ("PERSON", "DEATH", "REMOVE", "PARENT", "UNPARENT", "SPOUSE", "DIVORCE")

struct CommandError <: Exception
    reason::String
end
fail(reason) = throw(CommandError(reason))
gendered(kind, sex) = TERMS[kind][SEX_INDEX[sex]]
generation_prefix(g) = g == 1 ? "" : repeat("great-", g - 2) * "grand"

function ordinal(k)
    k <= 10 && return ORDINALS[k]
    suffix = k % 100 in (11, 12, 13) ? "th" :
             k % 10 == 1 ? "st" : k % 10 == 2 ? "nd" : k % 10 == 3 ? "rd" : "th"
    return "$k$suffix"
end

function kinship_term(da, db, sex)
    da == 0 && db == 0 && return "self"
    da == 0 && return generation_prefix(db) * gendered("parent", sex)
    db == 0 && return generation_prefix(da) * gendered("child", sex)
    da == 1 && db == 1 && return gendered("sibling", sex)
    da == 1 && return generation_prefix(db - 1) * gendered("pibling", sex)
    db == 1 && return generation_prefix(da - 1) * gendered("nibling", sex)
    r = abs(da - db)
    removal = r == 0 ? "" : r == 1 ? " once removed" :
              r == 2 ? " twice removed" : " $r times removed"
    return ordinal(min(da, db) - 1) * " cousin" * removal
end

mutable struct Person
    sex::String
    birth::Int
    name::String
    death::Union{Nothing,Int}
    parents::Vector{String}
end

mutable struct Marriage
    first::String
    second::String
    start::Int
    finish::Union{Nothing,Int}
    status::String
    died::Union{Nothing,String}
end
involves(m::Marriage, x) = x == m.first || x == m.second
other(m::Marriage, x) = x == m.first ? m.second : m.first
life_years(p) = string(p.birth, '-', isnothing(p.death) ? "" : p.death)

mutable struct Family
    persons::Dict{String,Person}
    marriages::Vector{Marriage}
end
Family() = Family(Dict{String,Person}(), Marriage[])

function person(f, x)
    haskey(f.persons, x) || fail("UNKNOWN PERSON $x")
    return f.persons[x]
end
parents(f, x) = f.persons[x].parents
children(f, x) = [y for (y, p) in f.persons if x in p.parents]
common_parents(f, x, y) = count(p -> p in parents(f, y), parents(f, x))
are_siblings(f, x, y) = x != y && common_parents(f, x, y) > 0
siblings(f, x) = [y for y in keys(f.persons) if are_siblings(f, x, y)]
age_key(f, x) = (f.persons[x].birth, x)
age_order(f, ids) = sort!(collect(ids); by=x -> age_key(f, x))

function person_list(f, ids)
    ordered = age_order(f, ids)
    return isempty(ordered) ? "-" : join(ordered, ' ')
end

records_of(f, x) = [m for m in f.marriages if involves(m, x)]
function current_record(f, x)
    for m in f.marriages
        m.status == "current" && involves(m, x) && return m
    end
    return nothing
end
function spouse(f, x)
    m = current_record(f, x)
    return isnothing(m) ? nothing : other(m, x)
end
function last_record(f, a, b)
    for m in Iterators.reverse(f.marriages)
        involves(m, a) && involves(m, b) && return m
    end
    return nothing
end
function partners(f, x)
    latest = Dict{String,Marriage}()
    for m in f.marriages
        involves(m, x) && (latest[other(m, x)] = m)
    end
    return Set(y for (y, m) in latest if m.status != "divorced")
end
step_related(f, px, py) = any(p -> any(q -> q in partners(f, p), py), px)

function generation_distances(f, start, upward)
    distances = Dict(start => 0)
    queue = [start]
    next = 1
    while next <= length(queue)
        x = queue[next]
        next += 1
        for y in (upward ? parents(f, x) : children(f, x))
            if !haskey(distances, y)
                distances[y] = distances[x] + 1
                push!(queue, y)
            end
        end
    end
    return distances
end
lineage(f, x, up) = sort!([(g, y) for (y, g) in generation_distances(f, x, up) if y != x])
is_ancestor(f, a, b) = a != b && haskey(generation_distances(f, b, true), a)
grandparents(f, x) = [y for (y, g) in generation_distances(f, x, true) if g == 2]

struct Apex
    id::String
    da::Int
    db::Int
    shares::Int
end
function apex(f, a, b)
    ua = generation_distances(f, a, true)
    ub = generation_distances(f, b, true)
    haskey(ub, a) && return Apex(a, 0, ub[a], 0)
    haskey(ua, b) && return Apex(b, ua[b], 0, 0)
    shared = [c for c in keys(ua) if haskey(ub, c)]
    isempty(shared) && return nothing
    c = first(sort!(shared; by=c -> (ua[c] + ub[c], ua[c], c)))
    da, db = ua[c], ub[c]
    shares = count(y -> ua[y] == da && ub[y] == db, shared)
    return Apex(c, da, db, shares)
end
function blood_term(ap, sex)
    prefix = ap.shares == 1 ? "half-" : ap.shares >= 4 ? "double " : ""
    return prefix * kinship_term(ap.da, ap.db, sex)
end

function relationship(f, a, b, sex=f.persons[a].sex)
    a == b && return ["self"]
    terms = String[]
    ap = apex(f, a, b)
    !isnothing(ap) && push!(terms, blood_term(ap, sex))
    m = last_record(f, a, b)
    if isnothing(m)
        any(p -> a in p.parents && b in p.parents, values(f.persons)) && push!(terms, "co-parent")
    elseif m.status == "current"
        push!(terms, gendered("spouse", sex))
    elseif m.status == "widowed"
        push!(terms, gendered(m.died == a ? "late" : "survivor", sex))
    else
        push!(terms, gendered("ex", sex))
    end
    pa, pb = parents(f, a), parents(f, b)
    qa, qb = partners(f, a), partners(f, b)
    a ∉ pb && any(p -> p in qa, pb) && push!(terms, gendered("stepparent", sex))
    b ∉ pa && any(p -> p in qb, pa) && push!(terms, gendered("stepchild", sex))
    common_parents(f, a, b) == 0 && step_related(f, pa, pb) &&
        push!(terms, gendered("stepsibling", sex))
    !is_ancestor(f, a, b) && any(g -> g in qa, grandparents(f, b)) &&
        push!(terms, gendered("stepgrandparent", sex))
    !is_ancestor(f, b, a) && any(g -> g in qb, grandparents(f, a)) &&
        push!(terms, gendered("stepgrandchild", sex))
    any(q -> a in parents(f, q), qb) && push!(terms, gendered("parent-in-law", sex))
    any(q -> b in parents(f, q), qa) && push!(terms, gendered("child-in-law", sex))
    if any(q -> are_siblings(f, a, q), qb) || any(q -> are_siblings(f, q, b), qa)
        push!(terms, gendered("sibling-in-law", sex))
    end
    return terms
end
function relationship_text(f, a, b)
    terms = relationship(f, a, b)
    return isempty(terms) ? "no relation" : join(terms, ", ")
end

function kinship(f, a, b, memo)
    key = a <= b ? (a, b) : (b, a)
    haskey(memo, key) && return memo[key]
    if a == b
        value = (SCALE + inbreeding(f, a, memo)) ÷ 2
    else
        x, y = f.persons[a].birth >= f.persons[b].birth ? (a, b) : (b, a)
        total = 0
        for p in parents(f, x)
            total += kinship(f, p, y, memo)
        end
        value = total ÷ 2
    end
    memo[key] = value
    return value
end
function inbreeding(f, x, memo)
    ps = parents(f, x)
    return length(ps) == 2 ? kinship(f, ps[1], ps[2], memo) : 0
end
coefficient_memo() = Dict{Tuple{String,String},Int}()
function fraction_text(value)
    d = gcd(value, SCALE)
    return string(value ÷ d, '/', SCALE ÷ d)
end
function lineage_length(f, x, memo)
    if !haskey(memo, x)
        height = 0
        for p in parents(f, x)
            height = max(height, lineage_length(f, p, memo))
        end
        memo[x] = height + 1
    end
    return memo[x]
end
function upward_path(f, start, depths)
    path = [start]
    while depths[last(path)] > 0
        x = last(path)
        candidates = [p for p in parents(f, x) if haskey(depths, p) && depths[p] == depths[x] - 1]
        push!(path, minimum(candidates))
    end
    return path
end
function census_status(f, x, year)
    last = nothing
    for m in records_of(f, x)
        m.start <= year && (last = m)
    end
    isnothing(last) && return "single"
    if isnothing(last.finish) || last.finish > year
        return "married $(other(last, x))"
    end
    return last.status
end
function step_targets(f, x, kind)
    kind == "parent" && return parents(f, x)
    kind == "child" && return children(f, x)
    kind == "sibling" && return siblings(f, x)
    s = spouse(f, x)
    return isnothing(s) ? String[] : [s]
end

function tree_visit!(lines, visited, f, x, depth)
    indent = repeat("  ", depth + 1)
    if x in visited
        push!(lines, "$indent$x (see above)")
        return
    end
    push!(visited, x)
    p = f.persons[x]
    s = spouse(f, x)
    push!(lines, "$indent$x $(p.name) $(life_years(p))" * (isnothing(s) ? "" : " = $s"))
    for child in age_order(f, children(f, x))
        tree_visit!(lines, visited, f, child, depth + 1)
    end
end
function pedigree_enter!(lines, entered, f, x, k, g, depth)
    p = f.persons[x]
    push!(lines, "$(repeat("  ", g + 1))$k $x $(p.name) $(life_years(p))")
    push!(entered, x)
    if g < depth
        ps = sort(parents(f, x); by=y -> (SEX_INDEX[f.persons[y].sex], y))
        for (i, parent) in enumerate(ps)
            pedigree_enter!(lines, entered, f, parent, 2k + i - 1, g + 1, depth)
        end
    end
end

mutable struct Calculator
    family::Family
    history::Vector{Tuple{String,Family}}
end
Calculator() = Calculator(Family(), Tuple{String,Family}[])

function process!(calc, cmd, args)
    f = calc.family
    lines = String[]
    if cmd == "PERSON"
        x, sex, birth, name = args
        haskey(f.persons, x) && fail("DUPLICATE PERSON $x")
        f.persons[x] = Person(sex, parse(Int, birth), name, nothing, String[])
        push!(lines, "ADDED $x $name $sex $birth")
    elseif cmd == "DEATH"
        x = args[1]
        year = parse(Int, args[2])
        p = person(f, x)
        !isnothing(p.death) && fail("ALREADY DECEASED $x")
        year < p.birth && fail("BAD YEAR $x")
        for m in records_of(f, x)
            (year < m.start || (!isnothing(m.finish) && year < m.finish)) && fail("BAD YEAR $x")
        end
        late = sort!([c for c in children(f, x) if f.persons[c].birth > year + 1])
        !isempty(late) && fail("AFTER DEATH $(first(late)) $x")
        p.death = year
        m = current_record(f, x)
        if isnothing(m)
            push!(lines, "DIED $x $year")
        else
            m.finish, m.status, m.died = year, "widowed", x
            push!(lines, "DIED $x $year spouse=$(other(m, x))")
        end
    elseif cmd == "REMOVE"
        x = args[1]
        person(f, x)
        for p in values(f.persons)
            filter!(y -> y != x, p.parents)
        end
        filter!(m -> !involves(m, x), f.marriages)
        delete!(f.persons, x)
        push!(lines, "REMOVED $x")
    elseif cmd == "PARENT"
        child, parent = args
        c, p = person(f, child), person(f, parent)
        child == parent && fail("SAME PERSON $child")
        parent in c.parents && fail("ALREADY PARENT $child $parent")
        length(c.parents) == 2 && fail("TOO MANY PARENTS $child")
        is_ancestor(f, child, parent) && fail("CYCLE $child $parent")
        p.birth + 12 > c.birth && fail("AGE GAP $child $parent")
        !isnothing(p.death) && p.death + 1 < c.birth && fail("AFTER DEATH $child $parent")
        push!(c.parents, parent)
        push!(lines, "LINKED $child $parent $(gendered("parent", p.sex))")
    elseif cmd == "UNPARENT"
        child, parent = args
        c = person(f, child)
        person(f, parent)
        parent ∉ c.parents && fail("NOT PARENT $child $parent")
        filter!(p -> p != parent, c.parents)
        push!(lines, "UNLINKED $child $parent")
    elseif cmd == "SPOUSE"
        a, b = args[1:2]
        year = parse(Int, args[3])
        person(f, a)
        person(f, b)
        a == b && fail("SAME PERSON $a")
        for x in (a, b)
            !isnothing(f.persons[x].death) && fail("DECEASED $x")
        end
        for x in (a, b)
            !isnothing(spouse(f, x)) && fail("ALREADY MARRIED $x")
        end
        (is_ancestor(f, a, b) || is_ancestor(f, b, a) || are_siblings(f, a, b)) &&
            fail("CLOSE KIN $a $b")
        for x in (a, b)
            year < f.persons[x].birth + 16 && fail("TOO YOUNG $x")
        end
        for x in (a, b)
            any(m -> !isnothing(m.finish) && m.finish >= year, records_of(f, x)) && fail("BAD YEAR $x")
        end
        push!(f.marriages, Marriage(a, b, year, nothing, "current", nothing))
        push!(lines, "MARRIED $a $b $year")
    elseif cmd == "DIVORCE"
        a, b = args[1:2]
        year = parse(Int, args[3])
        person(f, a)
        person(f, b)
        spouse(f, a) != b && fail("NOT MARRIED $a $b")
        m = current_record(f, a)
        year <= m.start && fail("BAD YEAR $a")
        m.finish, m.status = year, "divorced"
        push!(lines, "DIVORCED $a $b $year")
    elseif cmd == "UNDO"
        isempty(calc.history) && fail("NOTHING TO UNDO")
        line, previous = pop!(calc.history)
        calc.family = previous
        push!(lines, "UNDONE $line")
    elseif cmd == "INFO"
        x = args[1]
        p = person(f, x)
        push!(lines, "INFO $x $(p.name) $(p.sex) $(life_years(p))",
              "  parents: $(person_list(f, p.parents))")
        for m in records_of(f, x)
            finish = isnothing(m.finish) ? "" : string(m.finish)
            push!(lines, "  marriage: $(other(m, x)) $(m.start)-$finish $(m.status)")
        end
        push!(lines, "  children: $(person_list(f, children(f, x)))",
              "  siblings: $(person_list(f, siblings(f, x)))",
              "  inbreeding: $(fraction_text(inbreeding(f, x, coefficient_memo())))")
    elseif cmd == "RELATION" || cmd == "KINSHIP" || cmd == "PATH" || cmd == "COMMON"
        a, b = args
        person(f, a)
        person(f, b)
        if cmd == "RELATION"
            push!(lines, "RELATION $a $b: $(relationship_text(f, a, b))")
        elseif cmd == "KINSHIP"
            push!(lines, "KINSHIP $a $b $(fraction_text(kinship(f, a, b, coefficient_memo())))")
        elseif cmd == "PATH"
            ap = apex(f, a, b)
            if isnothing(ap)
                push!(lines, "PATH $a $b none")
            else
                depths = generation_distances(f, ap.id, false)
                left, right = upward_path(f, a, depths), upward_path(f, b, depths)
                route = vcat(left, reverse(right[1:end-1]))
                push!(lines, "PATH $a $b $(ap.da + ap.db): $(join(route, ' '))")
            end
        else
            ua, ub = generation_distances(f, a, true), generation_distances(f, b, true)
            shared = Set(c for c in keys(ua) if haskey(ub, c))
            nearest = [c for c in shared if !any(child -> child in shared, children(f, c))]
            sort!(nearest; by=c -> (ua[c] + ub[c], c))
            push!(lines, "COMMON $a $b $(length(nearest))")
            for c in nearest
                push!(lines, "  $c $(ua[c]) $(ub[c])")
            end
        end
    elseif cmd == "RELATIVES" || cmd == "WHO"
        x = args[1]
        person(f, x)
        query = cmd == "WHO" ? join(args[2:end], ' ') : ""
        entries = String[]
        for y in sort!(collect(keys(f.persons)))
            y == x && continue
            terms = relationship(f, y, x)
            if cmd == "RELATIVES"
                !isempty(terms) && push!(entries, "  $y: $(join(terms, ", "))")
            else
                neutral = relationship(f, y, x, "X")
                for i in eachindex(terms)
                    if query == terms[i] || query == neutral[i]
                        push!(entries, "  $y: $(terms[i])")
                        break
                    end
                end
            end
        end
        push!(lines, cmd == "WHO" ? "WHO $x $query $(length(entries))" : "RELATIVES $x $(length(entries))")
        append!(lines, entries)
    elseif cmd == "ANCESTORS" || cmd == "DESCENDANTS"
        x = args[1]
        person(f, x)
        entries = lineage(f, x, cmd == "ANCESTORS")
        push!(lines, "$cmd $x $(length(entries))")
        for (g, y) in entries
            term = cmd == "ANCESTORS" ? kinship_term(0, g, f.persons[y].sex) : kinship_term(g, 0, f.persons[y].sex)
            push!(lines, "  $g $y $term")
        end
    elseif cmd == "COUSINS"
        x = args[1]
        degree = parse(Int, args[2])
        person(f, x)
        matches = Tuple{Int,String,String}[]
        for y in keys(f.persons)
            y == x && continue
            ap = apex(f, y, x)
            if !isnothing(ap) && min(ap.da, ap.db) >= 2 && min(ap.da, ap.db) - 1 == degree
                push!(matches, (abs(ap.da - ap.db), y, blood_term(ap, f.persons[y].sex)))
            end
        end
        sort!(matches)
        push!(lines, "COUSINS $x $degree $(length(matches))")
        for (_, y, term) in matches
            push!(lines, "  $y $term")
        end
    elseif cmd == "SIBLINGS"
        x = args[1]
        person(f, x)
        entries = String[]
        earlier = 0
        for y in age_order(f, keys(f.persons))
            y == x && continue
            shared = common_parents(f, x, y)
            kind = shared == 2 ? "full" : shared == 1 ? "half" :
                   step_related(f, parents(f, x), parents(f, y)) ? "step" : ""
            isempty(kind) && continue
            if kind != "step" && isless(age_key(f, y), age_key(f, x))
                earlier += 1
            end
            push!(entries, "  $y $kind $(f.persons[y].birth)")
        end
        push!(lines, "SIBLINGS $x $(length(entries)) order=$(earlier + 1)")
        append!(lines, entries)
    elseif cmd == "GENERATIONS"
        x = args[1]
        person(f, x)
        groups = Dict{Int,Vector{Person}}()
        for (g, y) in lineage(f, x, false)
            push!(get!(groups, g, Person[]), f.persons[y])
        end
        push!(lines, "GENERATIONS $x $(length(groups))")
        for g in sort!(collect(keys(groups)))
            members = groups[g]
            births = [p.birth for p in members]
            living = count(p -> isnothing(p.death), members)
            push!(lines, "  $g $(length(members)) $living $(minimum(births))-$(maximum(births))")
        end
    elseif cmd == "TREE"
        x = args[1]
        person(f, x)
        push!(lines, "TREE $x $(length(lineage(f, x, false)))")
        tree_visit!(lines, Set{String}(), f, x, 0)
    elseif cmd == "PEDIGREE"
        x = args[1]
        depth = parse(Int, args[2])
        person(f, x)
        entries, entered = String[], Set{String}()
        pedigree_enter!(entries, entered, f, x, 1, 0, depth)
        push!(lines, "PEDIGREE $x $depth entries=$(length(entries)) distinct=$(length(entered))")
        append!(lines, entries)
    elseif cmd == "TIMELINE"
        x = args[1]
        p = person(f, x)
        events = Tuple{Int,Int,String,String}[(p.birth, 0, "", "born")]
        for m in records_of(f, x)
            q = other(m, x)
            push!(events, (m.start, 1, q, "married $q"))
            if m.status == "divorced"
                push!(events, (m.finish, 3, q, "divorced $q"))
            elseif m.status == "widowed" && m.died == q
                push!(events, (m.finish, 4, q, "widowed $q"))
            end
        end
        cs = children(f, x)
        for c in cs
            push!(events, (f.persons[c].birth, 2, c, "child $c"))
        end
        for (label, relatives) in (("parent", p.parents), ("child", cs))
            for y in relatives
                death = f.persons[y].death
                if !isnothing(death) && death >= p.birth && (isnothing(p.death) || death <= p.death)
                    push!(events, (death, 5, y, "lost $label $y"))
                end
            end
        end
        !isnothing(p.death) && push!(events, (p.death, 6, "", "died"))
        sort!(events; by=e -> (e[1], e[2], e[3]))
        push!(lines, "TIMELINE $x $(length(events))")
        for (year, _, _, text) in events
            push!(lines, "  $year $text")
        end
    elseif cmd == "CENSUS"
        year = parse(Int, args[1])
        residents = [x for (x, p) in f.persons if p.birth <= year && (isnothing(p.death) || p.death > year)]
        push!(lines, "CENSUS $year $(length(residents))")
        for x in age_order(f, residents)
            push!(lines, "  $x $(year - f.persons[x].birth) $(census_status(f, x, year))")
        end
    elseif cmd == "FIND"
        x, route = args
        person(f, x)
        current = Set([x])
        for step in split(route, '.')
            kind, sex = STEPS[step]
            following = Set{String}()
            for y in current, z in step_targets(f, y, kind)
                (isnothing(sex) || f.persons[z].sex == sex) && push!(following, z)
            end
            current = following
        end
        delete!(current, x)
        push!(lines, "FIND $x $route $(length(current))")
        for y in sort!(collect(current))
            push!(lines, "  $y: $(relationship_text(f, y, x))")
        end
    elseif cmd == "TERM"
        da, db = parse(Int, args[1]), parse(Int, args[2])
        sex = args[3]
        push!(lines, "TERM $da $db $sex $(kinship_term(da, db, sex))")
    elseif cmd == "STATS"
        living = count(p -> isnothing(p.death), values(f.persons))
        links = sum((length(p.parents) for p in values(f.persons)); init=0)
        couples = count(m -> m.status == "current", f.marriages)
        founders = count(p -> isempty(p.parents), values(f.persons))
        memo = Dict{String,Int}()
        longest = maximum((lineage_length(f, x, memo) for x in keys(f.persons)); init=0)
        push!(lines, "STATS persons=$(length(f.persons)) living=$living links=$links couples=$couples founders=$founders generations=$longest")
    elseif cmd == "AUDIT"
        entries = String[]
        for m in f.marriages
            ap = apex(f, m.first, m.second)
            !isnothing(ap) && push!(entries, "  marriage $(m.first) $(m.second) $(blood_term(ap, f.persons[m.first].sex))")
        end
        memo = coefficient_memo()
        for x in sort!(collect(keys(f.persons)))
            value = inbreeding(f, x, memo)
            value != 0 && push!(entries, "  inbred $x $(fraction_text(value))")
        end
        push!(lines, "AUDIT $(length(entries))")
        append!(lines, entries)
    end
    return lines
end

function execute!(calc, line)
    words = String.(split(line, ' '))
    cmd, args = first(words), words[2:end]
    try
        saved = cmd in MODIFYING ? deepcopy(calc.family) : nothing
        lines = process!(calc, cmd, args)
        cmd in MODIFYING && push!(calc.history, (line, saved))
        return lines
    catch err
        err isa CommandError || rethrow()
        return ["ERROR $(err.reason)"]
    end
end

function main()
    calc = Calculator()
    n = parse(Int, readline())
    for _ in 1:n
        for line in execute!(calc, readline())
            println(line)
        end
    end
end

main()
