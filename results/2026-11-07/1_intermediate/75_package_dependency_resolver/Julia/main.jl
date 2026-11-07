struct CommandError <: Exception
    message::String
end
fail(s) = throw(CommandError(s))
check(b, s) = b ? nothing : fail(s)
struct Version
    core::NTuple{3,Int}
    pre::Vector{String}
end
numberpart(s) =
    !isempty(s) && length(s)<=4 && all(c->'0'<=c<='9', s) && (length(s)==1 || first(s)!='0')
digitpart(s) = !isempty(s) && all(c->'0'<=c<='9', s)
function parseversion(s)
    pieces=split(s, '-'; keepempty = true)
    length(pieces)<=2 || return nothing
    core=split(pieces[1], '.'; keepempty = true)
    length(core)==3 && all(numberpart, core) || return nothing
    pre=String[]
    if length(pieces)==2
        pre=String.(split(pieces[2], '.'; keepempty = true))
        all(
            x->!isempty(x) &&
               all(c->'0'<=c<='9' || 'a'<=c<='z', x) &&
               (!digitpart(x) || numberpart(x)),
            pre,
        ) || return nothing
    end
    Version(Tuple(parse.(Int, core)), pre)
end
versiontext(v) = join(v.core, '.')*(isempty(v.pre) ? "" : "-"*join(v.pre, '.'))
function compareversions(a, b)
    a.core!=b.core && return a.core<b.core ? -1 : 1
    isempty(a.pre)!=isempty(b.pre) && return isempty(a.pre) ? 1 : -1
    for (x, y) in zip(a.pre, b.pre)
        x==y && continue
        xn=digitpart(x)
        yn=digitpart(y)
        xn!=yn && return xn ? -1 : 1
        return (xn ? parse(Int, x)<parse(Int, y) : x<y) ? -1 : 1
    end
    length(a.pre)==length(b.pre) ? 0 : length(a.pre)<length(b.pre) ? -1 : 1
end
struct Alternative
    comparisons::Vector{Tuple{String,Version}}
    precore::Set{NTuple{3,Int}}
end
struct Constraint
    text::String
    alternatives::Vector{Alternative}
end
function upperversion(v, k)
    core=collect(v.core)
    core[k]+=1
    core[(k+1):end].=0
    Version(Tuple(core), String[])
end
function parseterm(term)
    op=""
    pattern=term
    for symbol in (">=", "<=", ">", "<", "=", "^", "~")
        if startswith(term, symbol)
            op=symbol
            pattern=term[(length(symbol)+1):end]
            break
        end
    end
    parsed=parseversion(pattern)
    precore=nothing
    if parsed!==nothing && !isempty(parsed.pre)
        k=3
        lower=parsed
        precore=parsed.core
    else
        parts=split(pattern, '.'; keepempty = true)
        1<=length(parts)<=3 || return nothing
        k=0
        wildcard=false
        numbers=Int[]
        for part in parts
            if numberpart(part) && !wildcard
                k+=1
                push!(numbers, parse(Int, part))
            elseif part in ("x", "*")
                wildcard=true
            else
                return nothing
            end
        end
        append!(numbers, zeros(Int, 3-k))
        lower=Version(Tuple(numbers), String[])
    end
    comparisons=Tuple{String,Version}[]
    if k==0
        op in (">", "<") && push!(comparisons, ("<", Version((0, 0, 0), ["0"])))
    elseif op in ("", "=")
        if k==3
            push!(comparisons, ("=", lower))
        else
            append!(comparisons, [(">=", lower), ("<", upperversion(lower, k))])
        end
    elseif op==">"
        push!(comparisons, k==3 ? (">", lower) : (">=", upperversion(lower, k)))
    elseif op=="<="
        push!(comparisons, k==3 ? ("<=", lower) : ("<", upperversion(lower, k)))
    elseif op in (">=", "<")
        push!(comparisons, (op, lower))
    else
        at=op=="~" ? (k==1 ? 1 : 2) :
           (lower.core[1]!=0 || k==1 ? 1 : lower.core[2]!=0 || k==2 ? 2 : 3)
        append!(comparisons, [(">=", lower), ("<", upperversion(lower, at))])
    end
    comparisons, precore
end
function parseconstraint(text)
    alternatives=Alternative[]
    for part in split(text, " || "; keepempty = true)
        comparisons=Tuple{String,Version}[]
        cores=Set{NTuple{3,Int}}()
        for term in split(part, ' '; keepempty = true)
            parsed=parseterm(term)
            parsed===nothing && return nothing
            append!(comparisons, parsed[1])
            parsed[2]!==nothing && push!(cores, parsed[2])
        end
        push!(alternatives, Alternative(comparisons, cores))
    end
    Constraint(text, alternatives)
end
function allows(c, v)
    any(c.alternatives) do alt
        (isempty(v.pre) || v.core in alt.precore) && all(alt.comparisons) do (op, bound)
            cmp=compareversions(v, bound)
            op=="=" ? cmp==0 : op==">" ? cmp>0 : op==">=" ? cmp>=0 : op=="<" ? cmp<0 : cmp<=0
        end
    end
end
normalform(c) = join(
    [
        isempty(a.comparisons) ? "*" : join([op*versiontext(v) for (op, v) in a.comparisons], ' ') for a in c.alternatives
    ],
    " || ",
)
function requireversion(s)
    v=parseversion(s)
    check(v!==nothing, "invalid version '$s'")
    v
end
function requireconstraint(s)
    c=parseconstraint(s)
    check(c!==nothing, "invalid constraint '$s'")
    c
end
struct Link
    name::String
    constraint::Constraint
end
mutable struct Release
    name::String
    text::String
    version::Version
    dependencies::Vector{Link}
    conflicts::Vector{Link}
    yanked::Bool
end
struct Snapshot
    requests::Vector{Link}
    installed::Dict{String,Int}
end
mutable struct Manager
    registry::Vector{Release}
    requests::Vector{Link}
    installed::Dict{String,Int}
    held::Set{String}
    advisories::Dict{String,Link}
    history::Vector{Snapshot}
end
Manager() =
    Manager(Release[], Link[], Dict{String,Int}(), Set{String}(), Dict{String,Link}(), Snapshot[])
knownnames(m) = sort!(unique([r.name for r in m.registry]))
newest(m, name) = sort!(
    [i for i in eachindex(m.registry) if m.registry[i].name==name];
    lt = (a, b)->compareversions(m.registry[a].version, m.registry[b].version)>0,
)
function advisoryids(m, index)
    r=m.registry[index]
    sort!([
        id for (id, link) in m.advisories if link.name==r.name && allows(link.constraint, r.version)
    ])
end
function findrelease(m, name, text)
    at=findfirst(r->r.name==name && r.text==text, m.registry)
    check(at!==nothing, "$name@$text is not registered")
    at
end
function requireinstalled(m, name)
    check(haskey(m.installed, name), "$name is not installed")
    m.installed[name]
end
function displayrelease(m, index)
    r=m.registry[index]
    notes=String[]
    r.yanked && push!(notes, "yanked")
    get(m.installed, r.name, 0)==index && push!(notes, "installed")
    "$(r.name)@$(r.text)"*(isempty(notes) ? "" : " ("*join(notes, ", ")*")")
end
function resolve(m, requests, preferred, audit)
    selected=Dict{String,Int}()
    chains=Dict{String,Vector{String}}()
    bestsize=-1
    failure=String[]
    usable(i) =
        (!m.registry[i].yanked || get(m.installed, m.registry[i].name, 0)==i) &&
        (!audit || isempty(advisoryids(m, i)))
    function recordfailure(chain, reason, culprit = "")
        if length(selected)>bestsize
            bestsize=length(selected)
            failure=["UNSATISFIABLE"; ["  "*s for s in chain]; "  "*reason]
            !isempty(culprit) && append!(failure, ["    "*s for s in chains[culprit]])
        end
        false
    end
    function search(pending)
        isempty(pending) && return true
        link, chain=first(pending)
        rest=pending[2:end]
        name=link.name
        c=link.constraint
        if haskey(selected, name)
            r=m.registry[selected[name]]
            allows(c, r.version) && return search(rest)
            return recordfailure(chain, "$name@$(r.text) was selected by:", name)
        end
        if name in m.held
            index=m.installed[name]
            allows(c, m.registry[index].version) && usable(index) ||
                return recordfailure(chain, "$name@$(m.registry[index].text) is held")
            candidates=[index]
        else
            candidates=[i for i in newest(m, name) if allows(c, m.registry[i].version) && usable(i)]
            if name in preferred && get(m.installed, name, 0) in candidates
                index=m.installed[name]
                candidates=[index; filter(!=(index), candidates)]
            end
            isempty(candidates) &&
                return recordfailure(chain, "no version of $name matches $(c.text)")
        end
        for index in candidates
            r=m.registry[index]
            culprit=""
            for other in sort!(collect(keys(selected)))
                s=m.registry[selected[other]]
                if any(x->x.name==other && allows(x.constraint, s.version), r.conflicts) ||
                   any(x->x.name==name && allows(x.constraint, r.version), s.conflicts)
                    culprit=other
                    break
                end
            end
            if !isempty(culprit)
                recordfailure(
                    chain,
                    "$name@$(r.text) conflicts with $culprit@$(m.registry[selected[culprit]].text), which was selected by:",
                    culprit,
                )
                continue
            end
            selected[name]=index
            chains[name]=chain
            dependencies=[
                (dep, [chain; "$name@$(r.text) requires $(dep.name) $(dep.constraint.text)"]) for
                dep in r.dependencies
            ]
            search([dependencies; rest]) && return true
            delete!(selected, name)
            delete!(chains, name)
        end
        false
    end
    pending=[(link, ["requested $(link.name) $(link.constraint.text)"]) for link in requests]
    success=search(pending)
    success, selected, failure
end
function dependency_names(m, name, installed)
    [link.name for link in m.registry[installed[name]].dependencies]
end
function plan(m, new)
    lines=String[]
    counts=zeros(Int, 4)
    pending=Set(keys(new))
    while !isempty(pending)
        name=first([
            n for
            n in sort!(collect(pending)) if all(d->!(d in pending), dependency_names(m, n, new))
        ])
        delete!(pending, name)
        r=m.registry[new[name]]
        if !haskey(m.installed, name)
            push!(lines, "install $name@$(r.text)")
            counts[1]+=1
        elseif new[name]!=m.installed[name]
            old=m.registry[m.installed[name]]
            up=compareversions(r.version, old.version)>0
            word=up ? "upgrade" : "downgrade"
            push!(lines, "$word $name $(old.text) -> $(r.text)")
            counts[up ? 2 : 3]+=1
        end
    end
    pending=setdiff(Set(keys(m.installed)), Set(keys(new)))
    while !isempty(pending)
        name=first([
            n for n in sort!(collect(pending)) if
            all(other->!(n in dependency_names(m, other, m.installed)), pending)
        ])
        delete!(pending, name)
        push!(lines, "remove $name@$(m.registry[m.installed[name]].text)")
        counts[4]+=1
    end
    isempty(lines) ? ["no changes"] :
    [
        lines;
        "$(counts[1]) installed, $(counts[2]) upgraded, $(counts[3]) downgraded, $(counts[4]) removed"
    ]
end
function update!(m, requests, installed)
    push!(m.history, Snapshot(m.requests, m.installed))
    m.requests=requests
    m.installed=installed
    intersect!(m.held, keys(installed))
end
function resolved!(m, requests, preferred; audit = false, apply = true)
    success, installed, failure=resolve(m, requests, preferred, audit)
    success || return failure
    lines=plan(m, installed)
    apply && update!(m, requests, installed)
    lines
end
firstdependent(m, name) = minimum([
    other for other in keys(m.installed) if name in dependency_names(m, other, m.installed)
])
function reachable(m, roots)
    found=Set{String}()
    queue=collect(roots)
    while !isempty(queue)
        name=pop!(queue)
        name in found && continue
        push!(found, name)
        append!(queue, dependency_names(m, name, m.installed))
    end
    found
end
function treelines(m, roots)
    shown=Set{String}()
    lines=String[]
    function visit(name, c, prefix, indent)
        r=m.registry[m.installed[name]]
        body=prefix*"$name@$(r.text)"*(c===nothing ? "" : " [$(c.text)]")
        if name in shown
            push!(lines, body*" (*)")
            return
        end
        push!(shown, name)
        push!(lines, body)
        for (i, dep) in enumerate(r.dependencies)
            last=i==length(r.dependencies)
            visit(
                dep.name,
                dep.constraint,
                indent*(last ? "`-- " : "|-- "),
                indent*(last ? "    " : "|   "),
            )
        end
    end
    for root in roots
        at=findfirst(x->x.name==root, m.requests)
        visit(root, at===nothing ? nothing : m.requests[at].constraint, "", "")
    end
    isempty(lines) ? ["(empty)"] : lines
end
function execute!(m, line)
    pieces=split(line, ' '; limit = 2)
    command=pieces[1]
    rest=length(pieces)==2 ? String(pieces[2]) : ""
    args=String.(split(rest, ' '; keepempty = true))
    lines=String[]
    if command=="PKG"
        clauses=split(rest, "; ")
        name, text=String.(split(clauses[1], ' '))
        v=requireversion(text)
        check(
            !any(r->r.name==name && r.text==text, m.registry),
            "$name@$text is already registered",
        )
        deps=Link[]
        conflicts=Link[]
        for clause in clauses[2:end]
            kind, other, c=String.(split(clause, ' '; limit = 3))
            link=Link(other, requireconstraint(c))
            push!(kind=="DEP" ? deps : conflicts, link)
        end
        push!(m.registry, Release(name, text, v, deps, conflicts, false))
        return ["registered $name@$text"]
    elseif command in ("YANK", "INFO")
        name, text=args
        index=findrelease(m, name, text)
        r=m.registry[index]
        if command=="YANK"
            check(!r.yanked, "$name@$text is already yanked")
            r.yanked=true
            return ["yanked $name@$text"]
        end
        return [
            displayrelease(m, index);
            ["  requires $(x.name) $(x.constraint.text)" for x in r.dependencies];
            ["  conflicts with $(x.name) $(x.constraint.text)" for x in r.conflicts];
            ["  advisory $id" for id in advisoryids(m, index)]
        ]
    elseif command=="VERSIONS"
        parts=String.(split(rest, ' '; limit = 2))
        name=parts[1]
        c=length(parts)==2 ? requireconstraint(parts[2]) : nothing
        check(name in knownnames(m), "unknown package $name")
        lines=[
            displayrelease(m, i) for
            i in newest(m, name) if c===nothing || allows(c, m.registry[i].version)
        ]
        return isempty(lines) ? ["no matching versions"] : lines
    elseif command=="DEPENDENTS"
        name=args[1]
        v=length(args)==2 ? requireversion(args[2]) : nothing
        for other in knownnames(m), i in newest(m, other), dep in m.registry[i].dependencies
            if dep.name==name && (v===nothing || allows(dep.constraint, v))
                push!(lines, "$other@$(m.registry[i].text) requires $name $(dep.constraint.text)")
            end
        end
        return isempty(lines) ? ["no dependents"] : lines
    elseif command=="COMPARE"
        a=requireversion(args[1])
        b=requireversion(args[2])
        cmp=compareversions(a, b)
        return ["$(args[1]) $(cmp<0 ? "<" : cmp>0 ? ">" : "=") $(args[2])"]
    elseif command=="MATCH"
        parts=String.(split(rest, ' '; limit = 2))
        v=requireversion(parts[1])
        c=requireconstraint(parts[2])
        return [allows(c, v) ? "yes" : "no"]
    elseif command=="RANGE"
        return [normalform(requireconstraint(rest))]
    elseif command in ("INSTALL", "SIMULATE")
        parts=String.(split(rest, ' '; limit = 2))
        name=parts[1]
        c=requireconstraint(length(parts)==2 ? parts[2] : "*")
        check(name in knownnames(m), "unknown package $name")
        requests=copy(m.requests)
        at=findfirst(x->x.name==name, requests)
        if at===nothing
            push!(requests, Link(name, c))
        else
            requests[at]=Link(name, c)
        end
        return resolved!(m, requests, Set(keys(m.installed)); apply = command=="INSTALL")
    elseif command=="REMOVE"
        name=rest
        at=findfirst(x->x.name==name, m.requests)
        if at===nothing
            haskey(m.installed, name) && fail("$name is required by $(firstdependent(m,name))")
            fail("$name is not installed")
        end
        requests=filter(x->x.name!=name, m.requests)
        kept=reachable(m, [x.name for x in requests])
        installed=Dict(n=>i for (n, i) in m.installed if n in kept)
        if name in kept
            lines=[
                "$name@$(m.registry[m.installed[name]].text) is still required by $(firstdependent(m,name))",
            ]
            installed=m.installed
        else
            lines=plan(m, installed)
        end
        update!(m, requests, installed)
        return lines
    elseif command=="UPGRADE"
        preferred=Set{String}()
        if !isempty(rest)
            requireinstalled(m, rest)
            preferred=setdiff(Set(keys(m.installed)), Set([rest]))
        end
        return resolved!(m, m.requests, preferred)
    elseif command=="ROLLBACK"
        check(!isempty(m.history), "nothing to roll back")
        snapshot=pop!(m.history)
        lines=plan(m, snapshot.installed)
        m.requests=snapshot.requests
        m.installed=snapshot.installed
        intersect!(m.held, keys(m.installed))
        return lines
    elseif command=="HOLD"
        index=requireinstalled(m, rest)
        check(!(rest in m.held), "$rest is already held")
        push!(m.held, rest)
        return ["held $rest@$(m.registry[index].text)"]
    elseif command=="UNHOLD"
        check(rest in m.held, "$rest is not held")
        delete!(m.held, rest)
        return ["released $rest"]
    elseif command=="WHY"
        index=requireinstalled(m, rest)
        roots=[x.name for x in m.requests]
        rest in roots && return ["$rest@$(m.registry[index].text) is explicitly installed"]
        parents=Dict(x=>"" for x in roots)
        queue=sort(roots)
        at=1
        while at<=length(queue)
            name=queue[at]
            at+=1
            for dep in sort(dependency_names(m, name, m.installed))
                if !haskey(parents, dep)
                    parents[dep]=name
                    push!(queue, dep)
                end
            end
        end
        path=[rest]
        while !isempty(parents[last(path)])
            push!(path, parents[last(path)])
        end
        return [
            join(["$name@$(m.registry[m.installed[name]].text)" for name in reverse(path)], " -> "),
        ]
    elseif command=="TREE"
        if !isempty(rest)
            requireinstalled(m, rest)
        end
        return treelines(m, isempty(rest) ? sort([x.name for x in m.requests]) : [rest])
    elseif command=="OUTDATED"
        for name in sort!(collect(keys(m.installed)))
            cur=m.installed[name]
            constraints=[link.constraint for link in m.requests if link.name==name]
            for i in values(m.installed), dep in m.registry[i].dependencies
                dep.name==name && push!(constraints, dep.constraint)
            end
            versions=newest(m, name)
            wanted=first(
                i for i in versions if (!m.registry[i].yanked || i==cur) &&
                    all(c->allows(c, m.registry[i].version), constraints)
            )
            latest=findfirst(
                i->isempty(m.registry[i].version.pre) && !m.registry[i].yanked,
                versions,
            )
            latestindex=latest===nothing ? 0 : versions[latest]
            if wanted!=cur || (
                latestindex!=0 &&
                compareversions(m.registry[latestindex].version, m.registry[cur].version)>0
            )
                push!(
                    lines,
                    "$name $(m.registry[cur].text) $(m.registry[wanted].text) $(latestindex==0 ? "-" : m.registry[latestindex].text)",
                )
            end
        end
        return isempty(lines) ? ["all packages are up to date"] : lines
    elseif command=="LOCK"
        lines=[
            "$name@$(m.registry[m.installed[name]].text)" for
            name in sort!(collect(keys(m.installed)))
        ]
        return isempty(lines) ? ["(empty)"] : lines
    elseif command=="STATUS"
        lines=[
            "$(r.name) $(r.constraint.text) -> $(m.registry[m.installed[r.name]].text)" for
            r in m.requests
        ]
        isempty(lines) && push!(lines, "no requests")
        push!(
            lines,
            "$(length(m.installed)) installed, $(length(m.held)) held, $(length(m.history)) snapshots",
        )
        return lines
    elseif command=="ADVISORY"
        id, name, text=String.(split(rest, ' '; limit = 3))
        check(!haskey(m.advisories, id), "advisory $id already exists")
        c=requireconstraint(text)
        m.advisories[id]=Link(name, c)
        return ["advisory $id recorded"]
    elseif command=="AUDIT"
        rest=="FIX" && return resolved!(m, m.requests, Set(keys(m.installed)); audit = true)
        for name in sort!(collect(keys(m.installed)))
            cur=m.installed[name]
            ids=advisoryids(m, cur)
            isempty(ids) && continue
            fixes=[
                i for i in reverse(newest(m, name)) if
                compareversions(m.registry[i].version, m.registry[cur].version)>0 &&
                    isempty(m.registry[i].version.pre) &&
                    !m.registry[i].yanked &&
                    isempty(advisoryids(m, i))
            ]
            push!(
                lines,
                "$name@$(m.registry[cur].text): $(join(ids,", ")) ($(isempty(fixes) ? "no fix" : "fix: "*m.registry[first(fixes)].text))",
            )
        end
        return isempty(lines) ? ["no known vulnerabilities"] : lines
    end
    lines
end
function main()
    manager=Manager()
    count=parse(Int, readline())
    for _ in 1:count
        line=readline()
        try
            foreach(println, execute!(manager, line))
        catch e
            e isa CommandError || rethrow()
            println("error: $(e.message)")
        end
    end
end
main()
