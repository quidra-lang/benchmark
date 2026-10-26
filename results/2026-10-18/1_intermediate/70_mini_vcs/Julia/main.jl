const Tree=Dict{String,String}
struct CommandError <: Exception
    message::String
end
fail(s) = throw(CommandError(s))
check(b, s) = b ? nothing : fail(s)
paths(trees...) = sort!(collect(union((Set(keys(t)) for t in trees)...)))
agree(a, b, p) = get(a, p, nothing)==get(b, p, nothing)
differing(a, b) = [p for p in paths(a, b) if !agree(a, b, p)]
function matchpath!(target, source, p)
    haskey(source, p) ? (target[p]=source[p]) : delete!(target, p)
end
function changes(a, b)
    lines=String[]
    for p in differing(a, b)
        push!(
            lines,
            !haskey(a, p) ? "A $p: $(b[p])" :
            !haskey(b, p) ? "D $p: $(a[p])" : "M $p: $(a[p]) -> $(b[p])",
        )
    end
    isempty(lines) ? ["(no changes)"] : lines
end
function merge_trees(base, ours, theirs)
    merged=Tree()
    conflicts=String[]
    for p in paths(base, ours, theirs)
        if agree(theirs, base, p) || agree(ours, theirs, p)
            matchpath!(merged, ours, p)
        elseif agree(ours, base, p)
            matchpath!(merged, theirs, p)
        else
            push!(conflicts, p)
            matchpath!(merged, ours, p)
        end
    end
    merged, conflicts
end
function globmatch(text, pattern)
    previous=falses(length(text)+1)
    previous[1]=true
    for c in pattern
        next=falses(length(text)+1)
        c=='*' && (next[1]=previous[1])
        for i in eachindex(text)
            next[i+1]=c=='*' ? previous[i+1] || next[i] : previous[i] && (c=='?' || c==text[i])
        end
        previous=next
    end
    previous[end]
end
struct Commit
    id::String
    sequence::Int
    parents::Vector{Int}
    tree::Tree
    message::String
end
struct StashEntry
    label::String
    base::Int
    tree::Tree
end
mutable struct Repository
    commits::Vector{Commit}
    active::Dict{String,Int}
    branches::Dict{String,Int}
    tags::Dict{String,Int}
    branch::Union{Nothing,String}
    detached::Int
    work::Tree
    index::Tree
    conflicts::Set{String}
    operation::Union{Nothing,Tuple{String,Int}}
    stash::Vector{StashEntry}
    ignores::Vector{String}
end
function createcommit!(r, parents, tree, message)
    sequence=length(r.commits)
    lines=["commit $sequence"]
    append!(lines, ["parent $(r.commits[p].id)" for p in parents])
    append!(lines, ["file $p $(tree[p])" for p in sort!(collect(keys(tree)))])
    push!(lines, "message $message")
    h=0
    for c in join(lines, "\n")*"\n"
        h=mod(h*131+Int(c), 2147483647)
    end
    id=lpad(string(h; base = 16), 8, '0')
    push!(r.commits, Commit(id, sequence, copy(parents), copy(tree), message))
    r.active[id]=sequence+1
    sequence+1
end
function Repository()
    r=Repository(
        Commit[],
        Dict{String,Int}(),
        Dict{String,Int}(),
        Dict{String,Int}(),
        "main",
        1,
        Tree(),
        Tree(),
        Set{String}(),
        nothing,
        StashEntry[],
        String[],
    )
    root=createcommit!(r, Int[], Tree(), "init")
    r.branches["main"]=root
    r
end
head(r) = r.branch===nothing ? r.detached : r.branches[r.branch]
headtree(r) = r.commits[head(r)].tree
parenttree(r, c) = isempty(c.parents) ? Tree() : r.commits[c.parents[1]].tree
function movehead!(r, c)
    r.branch===nothing ? (r.detached=c) : (r.branches[r.branch]=c)
end
function revision(r, rev)
    parts=split(rev, '~')
    anchor=parts[1]
    c=anchor=="HEAD" ? head(r) :
      haskey(r.branches, anchor) ? r.branches[anchor] :
      haskey(r.tags, anchor) ? r.tags[anchor] : get(r.active, anchor, 0)
    check(c!=0, "unknown revision '$rev'")
    for _ in 1:(length(parts)==2 ? parse(Int, parts[2]) : 0)
        check(!isempty(r.commits[c].parents), "unknown revision '$rev'")
        c=r.commits[c].parents[1]
    end
    c
end
function distances(r, start)
    result=Dict(start=>0)
    queue=[start]
    at=1
    while at<=length(queue)
        c=queue[at]
        at+=1
        for p in r.commits[c].parents
            if !haskey(result, p)
                result[p]=result[c]+1
                push!(queue, p)
            end
        end
    end
    result
end
isancestor(r, a, b) = haskey(distances(r, b), a)
function mergebase(r, a, b)
    da=distances(r, a)
    db=distances(r, b)
    common=intersect(Set(keys(da)), Set(keys(db)))
    parents=Set{Int}()
    for c in common
        union!(parents, r.commits[c].parents)
    end
    candidates=collect(setdiff(common, parents))
    candidates[argmin([(max(da[c], db[c]), -r.commits[c].sequence) for c in candidates])]
end
function reachable(r, roots)
    result=Set{Int}()
    for c in roots
        union!(result, keys(distances(r, c)))
    end
    result
end
function commit_summary(r, c)
    value=r.commits[c]
    references=String[]
    if c==head(r)
        push!(references, r.branch===nothing ? "HEAD" : "HEAD -> $(r.branch)")
    end
    for name in sort!(collect(keys(r.branches)))
        r.branches[name]==c && name!=r.branch && push!(references, name)
    end
    for name in sort!(collect(keys(r.tags)))
        r.tags[name]==c && push!(references, "tag: $name")
    end
    value.id*(isempty(references) ? "" : " ("*join(references, ", ")*")")*" "*value.message
end
ignored(r, p) =
    !haskey(r.index, p) && !(p in r.conflicts) && any(pattern->globmatch(p, pattern), r.ignores)
function checkprogress(r)
    r.operation===nothing || fail("$(r.operation[1]) in progress")
end
uncommitted(r) = r.index!=headtree(r) || any(p->!agree(r.work, r.index, p), keys(r.index))
checkclean(r) = check(!uncommitted(r), "uncommitted changes")
function checkoverwrite(r, selected)
    h=headtree(r)
    for p in sort!(collect(selected))
        check(
            agree(r.index, h, p) && agree(r.work, h, p),
            "local changes to '$p' would be overwritten",
        )
    end
end
function switchtree!(r, tree)
    selected=differing(headtree(r), tree)
    checkoverwrite(r, selected)
    for p in selected
        matchpath!(r.index, tree, p)
        matchpath!(r.work, tree, p)
    end
end
function recordcommit!(r, parents, tree, message)
    c=createcommit!(r, parents, tree, message)
    movehead!(r, c)
    old=r.commits[parents[1]].tree
    added=count(p->!haskey(old, p), keys(tree))
    modified=count(p->haskey(old, p) && old[p]!=tree[p], keys(tree))
    deleted=count(p->!haskey(tree, p), keys(old))
    println(
        "[$(r.branch===nothing ? "detached HEAD" : r.branch) $(r.commits[c].id)] $message ($added added, $modified modified, $deleted deleted)",
    )
end
function applychange!(r, base, theirs, kind, target, message, parents, common = 0)
    h=headtree(r)
    merged, conflicts=merge_trees(base, h, theirs)
    selected=differing(h, merged)
    checkoverwrite(r, union(Set(selected), Set(conflicts)))
    if kind=="merge"
        println("Merge base $(r.commits[common].id)")
    elseif isempty(conflicts) && merged==h
        println("nothing to commit")
        return
    end
    for p in selected
        matchpath!(r.index, merged, p)
        matchpath!(r.work, merged, p)
    end
    if isempty(conflicts)
        recordcommit!(r, parents, merged, message)
        return
    end
    for p in conflicts
        r.work[p]="<<<<<<< $(get(h,p,"(deleted)")) ======= $(get(theirs,p,"(deleted)")) >>>>>>>"
        println("CONFLICT $p")
    end
    r.conflicts=Set(conflicts)
    r.operation=(kind, target)
    println(
        kind=="merge" ? "Automatic merge failed; fix conflicts and then commit the result." :
        kind=="revert" ? "error: could not revert $(r.commits[target].id)" :
        "error: could not apply $(r.commits[target].id)",
    )
end
function status(r)
    h=headtree(r)
    lines=String[]
    println(
        r.branch===nothing ? "HEAD detached at $(r.commits[head(r)].id)" : "On branch $(r.branch)",
    )
    if r.operation!==nothing
        kind, c=r.operation
        title=kind=="merge" ? "Merging" : kind=="revert" ? "Reverting" : "Cherry-picking"
        println("$title $(r.commits[c].id)")
    end
    for p in sort!(collect(union(Set(paths(h, r.index, r.work)), r.conflicts)))
        if p in r.conflicts
            push!(lines, "UU $p")
        elseif haskey(r.index, p)
            x=!haskey(h, p) ? "A" : h[p]!=r.index[p] ? "M" : "."
            y=!haskey(r.work, p) ? "D" : r.work[p]!=r.index[p] ? "M" : "."
            (x!="." || y!=".") && push!(lines, x*y*" "*p)
        else
            haskey(h, p) && push!(lines, "D. $p")
            haskey(r.work, p) && !ignored(r, p) && push!(lines, "?? $p")
        end
    end
    foreach(println, isempty(lines) ? ["nothing to commit, working tree clean"] : lines)
end
function execute!(r, line)
    words=String.(split(line, ' '; limit = 2))
    command=words[1]
    argument=length(words)==1 ? "" : words[2]
    args=isempty(argument) ? String[] :
         command in ("COMMIT", "AMEND") ? [argument] :
         String.(split(argument, ' '; limit = command=="WRITE" ? 2 : 0))
    h=head(r)
    hc=r.commits[h]
    ht=hc.tree
    if command=="WRITE"
        r.work[args[1]]=args[2]
    elseif command=="REMOVE"
        p=args[1]
        check(haskey(r.work, p), "no such file '$p'")
        delete!(r.work, p)
    elseif command=="IGNORE"
        push!(r.ignores, args[1])
    elseif command=="ADD"
        p=args[1]
        if p=="ALL"
            selected=[p for p in paths(r.work, r.index) if !ignored(r, p)]
            for p in selected
                matchpath!(r.index, r.work, p)
            end
            empty!(r.conflicts)
        else
            check(!(haskey(r.work, p) && ignored(r, p)), "path '$p' is ignored")
            check(
                haskey(r.work, p) || haskey(r.index, p) || p in r.conflicts,
                "pathspec '$p' did not match any files",
            )
            matchpath!(r.index, r.work, p)
            delete!(r.conflicts, p)
        end
    elseif command=="RM"
        p=args[1]
        check(haskey(r.index, p), "pathspec '$p' did not match any files")
        delete!(r.index, p)
        delete!(r.work, p)
        delete!(r.conflicts, p)
    elseif command=="UNSTAGE"
        p=args[1]
        check(haskey(r.index, p) || haskey(ht, p), "pathspec '$p' did not match any files")
        matchpath!(r.index, ht, p)
    elseif command in ("RESTORE", "CAT")
        p=args[1]
        tree=length(args)==1 ? (command=="RESTORE" ? r.index : r.work) :
             r.commits[revision(r, args[2])].tree
        check(
            haskey(tree, p),
            length(args)==2 ? "path '$p' does not exist in '$(args[2])'" :
            command=="CAT" ? "no such file '$p'" : "pathspec '$p' did not match any files",
        )
        if command=="CAT"
            println(tree[p])
        else
            r.work[p]=tree[p]
            if length(args)==2
                r.index[p]=tree[p]
                delete!(r.conflicts, p)
            end
        end
    elseif command=="COMMIT"
        check(isempty(r.conflicts), "unresolved conflicts")
        if r.operation!==nothing && r.operation[1]=="merge"
            recordcommit!(r, [h, r.operation[2]], r.index, args[1])
            r.operation=nothing
        elseif r.index==ht
            println("nothing to commit")
        else
            recordcommit!(r, [h], r.index, args[1])
            r.operation=nothing
        end
    elseif command=="AMEND"
        checkprogress(r)
        check(!isempty(hc.parents), "cannot amend the root commit")
        recordcommit!(r, hc.parents, r.index, args[1])
    elseif command=="STATUS"
        status(r)
    elseif command=="LS"
        tree=isempty(args) ? r.work : r.commits[revision(r, args[1])].tree
        isempty(tree) && println("(empty)")
        for p in sort!(collect(keys(tree)))
            println(p, " ", tree[p])
        end
    elseif command=="DIFF"
        if isempty(args)
            old=r.index
            new=Tree(p=>r.work[p] for p in keys(r.index) if haskey(r.work, p))
        elseif args[1]=="STAGED"
            old=ht
            new=r.index
        else
            a=revision(r, args[1])
            b=revision(r, args[2])
            old=r.commits[a].tree
            new=r.commits[b].tree
        end
        foreach(println, changes(old, new))
    elseif command=="LOG"
        limit=isempty(args) ? typemax(Int) : parse(Int, args[1])
        c=h
        printed=0
        while true
            println(commit_summary(r, c))
            printed+=1
            (isempty(r.commits[c].parents) || printed==limit) && break
            c=r.commits[c].parents[1]
        end
    elseif command=="SHOW"
        c=revision(r, isempty(args) ? "HEAD" : args[1])
        value=r.commits[c]
        println("commit ", commit_summary(r, c))
        println(
            "parents: ",
            isempty(value.parents) ? "none" : join([r.commits[p].id for p in value.parents], ' '),
        )
        foreach(println, changes(parenttree(r, value), value.tree))
    elseif command=="BLAME"
        p=args[1]
        check(haskey(ht, p), "path '$p' does not exist in 'HEAD'")
        c=h
        text=ht[p]
        while !isempty(r.commits[c].parents)
            parent=r.commits[c].parents[1]
            get(r.commits[parent].tree, p, nothing)==text || break
            c=parent
        end
        println("$(r.commits[c].id) ($(r.commits[c].message)) $text")
    elseif command in ("BRANCH", "TAG")
        refs=command=="BRANCH" ? r.branches : r.tags
        noun=lowercase(command)
        remove=args[1]=="-d"
        name=args[remove ? 2 : 1]
        if remove
            check(haskey(refs, name), "no such $noun '$name'")
            c=refs[name]
            if command=="BRANCH"
                check(name!=r.branch, "cannot delete current branch '$name'")
                check(isancestor(r, c, h), "branch '$name' is not fully merged")
            end
            delete!(refs, name)
            println("Deleted $noun $name (was $(r.commits[c].id))")
        else
            check(!haskey(refs, name), "$noun '$name' already exists")
            c=revision(r, length(args)==2 ? args[2] : "HEAD")
            refs[name]=c
            println("Created $noun $name at $(r.commits[c].id)")
        end
    elseif command in ("BRANCHES", "TAGS")
        if command=="BRANCHES"
            r.branch===nothing && println("* (HEAD detached at $(hc.id))")
            for name in sort!(collect(keys(r.branches)))
                value=r.commits[r.branches[name]]
                println(name==r.branch ? "*" : " ", " $name $(value.id) $(value.message)")
            end
        else
            isempty(r.tags) && println("(no tags)")
            for name in sort!(collect(keys(r.tags)))
                value=r.commits[r.tags[name]]
                println("$name $(value.id) $(value.message)")
            end
        end
    elseif command=="SWITCH"
        name=args[1]
        check(haskey(r.branches, name), "no such branch '$name'")
        if name==r.branch
            println("Already on '$name'")
        else
            checkprogress(r)
            switchtree!(r, r.commits[r.branches[name]].tree)
            r.branch=name
            println("Switched to branch '$name'")
        end
    elseif command=="DETACH"
        c=revision(r, args[1])
        checkprogress(r)
        switchtree!(r, r.commits[c].tree)
        r.branch=nothing
        r.detached=c
        println("HEAD is now at $(r.commits[c].id) $(r.commits[c].message)")
    elseif command=="MERGEBASE"
        a=revision(r, args[1])
        b=revision(r, args[2])
        println(r.commits[mergebase(r, a, b)].id)
    elseif command=="MERGE"
        c=revision(r, args[1])
        checkprogress(r)
        if isancestor(r, c, h)
            println("Already up to date")
        elseif isancestor(r, h, c)
            switchtree!(r, r.commits[c].tree)
            movehead!(r, c)
            println("Fast-forward $(hc.id)..$(r.commits[c].id)")
        else
            checkclean(r)
            base=mergebase(r, h, c)
            applychange!(
                r,
                r.commits[base].tree,
                r.commits[c].tree,
                "merge",
                c,
                "Merge $(args[1])",
                [h, c],
                base,
            )
        end
    elseif command in ("REVERT", "CHERRYPICK")
        c=revision(r, args[1])
        checkprogress(r)
        checkclean(r)
        value=r.commits[c]
        parent=parenttree(r, value)
        if command=="REVERT"
            applychange!(r, value.tree, parent, "revert", c, "Revert \"$(value.message)\"", [h])
        else
            applychange!(r, parent, value.tree, "cherry-pick", c, value.message, [h])
        end
    elseif command=="RESET"
        c=revision(r, args[2])
        tree=r.commits[c].tree
        if args[1]=="HARD"
            for p in union(Set(paths(r.index, tree)), r.conflicts)
                matchpath!(r.work, tree, p)
            end
        end
        args[1]!="SOFT" && (r.index=copy(tree))
        movehead!(r, c)
        empty!(r.conflicts)
        r.operation=nothing
        println("HEAD is now at $(r.commits[c].id) $(r.commits[c].message)")
    elseif command=="REBASE"
        upstream=revision(r, args[1])
        checkprogress(r)
        if isancestor(r, upstream, h)
            println("Already up to date")
            return
        end
        checkclean(r)
        upstream_ancestors=distances(r, upstream)
        replay=Int[]
        c=h
        while !haskey(upstream_ancestors, c)
            push!(replay, c)
            c=r.commits[c].parents[1]
        end
        reverse!(replay)
        tree=r.commits[upstream].tree
        plans=Union{Nothing,Tree}[]
        for c in replay
            value=r.commits[c]
            merged, conflicts=merge_trees(parenttree(r, value), tree, value.tree)
            check(
                isempty(conflicts),
                "could not rebase $(value.id): conflict in '$(isempty(conflicts) ? "" : conflicts[1])'",
            )
            if merged==tree
                push!(plans, nothing)
            else
                push!(plans, merged)
                tree=merged
            end
        end
        switchtree!(r, tree)
        tip=upstream
        for (c, picked) in zip(replay, plans)
            value=r.commits[c]
            if picked===nothing
                println("skip $(value.id) $(value.message)")
            else
                next=createcommit!(r, [tip], picked, value.message)
                println("pick $(value.id) -> $(r.commits[next].id) $(value.message)")
                tip=next
            end
        end
        movehead!(r, tip)
        println("HEAD is now at $(r.commits[tip].id) $(r.commits[tip].message)")
    elseif command=="STASH"
        option=isempty(args) ? "" : args[1]
        if option=="LIST"
            isempty(r.stash) && println("(no stash entries)")
            for (i, e) in enumerate(r.stash)
                println("stash@{$(i-1)}: $(e.label)")
            end
        elseif option=="DROP"
            check(!isempty(r.stash), "no stash entries")
            e=popfirst!(r.stash)
            println("Dropped stash@{0}: $(e.label)")
        elseif option=="POP"
            check(!isempty(r.stash), "no stash entries")
            checkprogress(r)
            checkclean(r)
            e=r.stash[1]
            merged, conflicts=merge_trees(r.commits[e.base].tree, ht, e.tree)
            check(
                isempty(conflicts),
                "stash conflict in '$(isempty(conflicts) ? "" : conflicts[1])'",
            )
            selected=differing(ht, merged)
            checkoverwrite(r, selected)
            for p in selected
                matchpath!(r.work, merged, p)
            end
            popfirst!(r.stash)
            println("Restored stash@{0}: $(e.label)")
            foreach(println, changes(ht, merged))
        else
            checkprogress(r)
            if !uncommitted(r)
                println("No local changes to save")
                return
            end
            tracked=paths(r.index, ht)
            saved=Tree(p=>r.work[p] for p in tracked if haskey(r.work, p))
            for p in tracked
                matchpath!(r.work, ht, p)
            end
            r.index=copy(ht)
            label="WIP on $(r.branch===nothing ? "(no branch)" : r.branch): $(hc.id) $(hc.message)"
            pushfirst!(r.stash, StashEntry(label, h, saved))
            println("Saved stash@{0}: $label")
        end
    elseif command=="DESCRIBE"
        c=revision(r, isempty(args) ? "HEAD" : args[1])
        ds=distances(r, c)
        best=nothing
        distance=0
        for name in sort!(collect(keys(r.tags)))
            target=r.tags[name]
            if haskey(ds, target) && (best===nothing || ds[target]<distance)
                best=name
                distance=ds[target]
            end
        end
        check(best!==nothing, "no tag can describe '$(r.commits[c].id)'")
        println(distance==0 ? best : "$best-$distance-g$(r.commits[c].id)")
    elseif command in ("GRAPH", "GC")
        roots=[h; collect(values(r.branches)); collect(values(r.tags))]
        if command=="GC"
            append!(roots, [e.base for e in r.stash])
            r.operation!==nothing && push!(roots, r.operation[2])
            kept=reachable(r, roots)
            removed=[id for (id, c) in r.active if !(c in kept)]
            for id in removed
                delete!(r.active, id)
            end
            println("Removed unreachable commits: $(length(removed))")
        else
            selected=sort!(collect(reachable(r, roots)); by = c->r.commits[c].sequence, rev = true)
            lanes=Int[]
            for c in selected
                !(c in lanes) && push!(lanes, c)
                at=findfirst(==(c), lanes)
                symbols=[i==at ? "*" : lane==c ? "/" : "|" for (i, lane) in enumerate(lanes)]
                println(join(symbols, ' '), " ", commit_summary(r, c))
                lanes=[lane for (i, lane) in enumerate(lanes) if i==at || lane!=c]
                parents=r.commits[c].parents
                if isempty(parents)
                    deleteat!(lanes, at)
                else
                    lanes[at]=parents[1]
                    length(parents)==2 && !(parents[2] in lanes) && insert!(lanes, at+1, parents[2])
                end
            end
        end
    end
end
function main()
    repository=Repository()
    for line in eachline()
        line=="EXIT" && break
        try
            execute!(repository, line)
        catch e
            e isa CommandError || rethrow()
            println("error: $(e.message)")
        end
    end
end
main()
