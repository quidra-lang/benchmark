module BTreeIndex

struct CommandError <: Exception
    message::String
end
fail(message) = throw(CommandError(message))

struct Entry
    key::Int
    value::String
end
Base.:(==)(a::Entry, b::Entry) = a.key == b.key && a.value == b.value
entry_display(entry::Entry) = "$(entry.key)=$(entry.value)"
struct Node
    entries::Vector{Entry}
    kids::Vector{Int}
end
Node() = Node(Entry[], Int[])
Base.copy(node::Node) = Node(copy(node.entries), copy(node.kids))
Base.:(==)(a::Node, b::Node) = a.entries == b.entries && a.kids == b.kids
notation(node::Node) = "[" * join((entry.key for entry in node.entries), " ") * "]"
mutable struct Tree
    degree::Int
    root::Int
    pages::Dict{Int,Node}
    splits::Int
    merges::Int
    borrows::Int
end
Tree(degree::Int) = Tree(degree, 0, Dict(0 => Node()), 0, 0, 0)
Base.copy(tree::Tree) = Tree(tree.degree, tree.root, Dict(page => copy(node) for (page, node) in tree.pages), tree.splits, tree.merges, tree.borrows)
function allocate!(tree::Tree, node::Node = Node())
    page = 0
    while haskey(tree.pages, page)
        page += 1
    end
    tree.pages[page] = node
    page
end
function node_position(node::Node, key::Int)
    found = findfirst(entry -> entry.key >= key, node.entries)
    isnothing(found) ? length(node.entries) + 1 : found
end
struct Search
    page::Int
    at::Int
    found::Bool
    path::Vector{Int}
end
function search_tree(tree::Tree, key::Int)
    page = tree.root
    path = Int[]
    while true
        push!(path, page)
        node = tree.pages[page]
        at = node_position(node, key)
        found = at <= length(node.entries) && node.entries[at].key == key
        (found || isempty(node.kids)) && return Search(page, at, found, path)
        page = node.kids[at]
    end
end
function inorder(tree::Tree)
    result = Entry[]
    function visit(page)
        node = tree.pages[page]
        for j in eachindex(node.entries)
            isempty(node.kids) || visit(node.kids[j])
            push!(result, node.entries[j])
        end
        isempty(node.kids) || visit(last(node.kids))
    end
    visit(tree.root)
    result
end
key_count(tree::Tree) = sum(length(node.entries) for node in values(tree.pages))
function height(tree::Tree)
    result = 0
    node = tree.pages[tree.root]
    while !isempty(node.kids)
        result += 1
        node = tree.pages[first(node.kids)]
    end
    result
end
function check_tree(tree::Tree)
    reference = Ref{Union{Nothing,Int}}(nothing)
    bound_text(value, lower) = isnothing(value) ? (lower ? "-inf" : "+inf") : string(value)
    function visit(page, location, depth, lower, upper)
        node = tree.pages[page]
        n = length(node.entries)
        minimum = page == tree.root ? (isempty(node.kids) ? 0 : 1) : tree.degree - 1
        maximum = 2 * tree.degree - 1
        detail = " at=$location node=$(notation(node))"
        if n < minimum || n > maximum
            return "FAIL COUNT$detail keys=$n allowed=$(minimum)..$(maximum)"
        end
        for j in 1:(n - 1)
            if node.entries[j].key >= node.entries[j + 1].key
                return "FAIL ORDER$detail $(node.entries[j].key)>=$(node.entries[j + 1].key)"
            end
        end
        for entry in node.entries
            if (!isnothing(lower) && entry.key <= lower) || (!isnothing(upper) && entry.key >= upper)
                return "FAIL RANGE$detail key=$(entry.key) low=$(bound_text(lower, true)) high=$(bound_text(upper, false))"
            end
        end
        if isempty(node.kids)
            if isnothing(reference[])
                reference[] = depth
            elseif depth != reference[]
                return "FAIL DEPTH$detail depth=$depth expected=$(reference[])"
            end
        else
            for j in eachindex(node.kids)
                problem = visit(node.kids[j], "$(location).$(j - 1)", depth + 1,
                    j == 1 ? lower : node.entries[j - 1].key, j > n ? upper : node.entries[j].key)
                isnothing(problem) || return problem
            end
        end
        nothing
    end
    visit(tree.root, "root", 0, nothing, nothing)
end
tree_status(tree::Tree) = isnothing(check_tree(tree)) ? "OK" : "DAMAGED"
function changes(tree::Tree, before::Dict{Int,Node})
    writes = sum(!haskey(before, page) || node != before[page] for (page, node) in tree.pages)
    frees = count(page -> !haskey(tree.pages, page), keys(before))
    (writes = writes, frees = frees)
end
mutable struct Trace
    enabled::Bool
    lines::Vector{String}
    cases::Vector{String}
end
Trace(enabled) = Trace(enabled, String[], String[])
function step!(trace::Union{Nothing,Trace}, text::String)
    isnothing(trace) || !trace.enabled || push!(trace.lines, text)
    nothing
end
function add_case!(trace::Union{Nothing,Trace}, name::String)
    isnothing(trace) || push!(trace.cases, name)
    nothing
end
function split_child!(tree::Tree, page::Int, at::Int, trace)
    parent = tree.pages[page]
    left_page = parent.kids[at]
    left = tree.pages[left_page]
    degree = tree.degree
    middle = left.entries[degree]
    right = Node(left.entries[(degree + 1):end], isempty(left.kids) ? Int[] : left.kids[(degree + 1):end])
    right_page = allocate!(tree, right)
    step!(trace, "STEP split page=$left_page keys=$(notation(left)) up=$(middle.key) new=$right_page")
    resize!(left.entries, degree - 1)
    isempty(left.kids) || resize!(left.kids, degree)
    insert!(parent.entries, at, middle)
    insert!(parent.kids, at + 1, right_page)
    tree.splits += 1
end
function put_entry!(tree::Tree, entry::Entry, trace = nothing)
    found = search_tree(tree, entry.key)
    if found.found
        node = tree.pages[found.page]
        old = node.entries[found.at].value
        node.entries[found.at] = entry
        return (added = false, old = old)
    end
    if length(tree.pages[tree.root].entries) == 2 * tree.degree - 1
        tree.root = allocate!(tree, Node(Entry[], [tree.root]))
        step!(trace, "STEP grow page=$(tree.root)")
        split_child!(tree, tree.root, 1, trace)
    end
    page = tree.root
    while true
        node = tree.pages[page]
        at = node_position(node, entry.key)
        if isempty(node.kids)
            insert!(node.entries, at, entry)
            step!(trace, "STEP place page=$page keys=$(notation(node))")
            return (added = true, old = nothing)
        end
        if length(tree.pages[node.kids[at]].entries) == 2 * tree.degree - 1
            split_child!(tree, page, at, trace)
            entry.key > node.entries[at].key && (at += 1)
        end
        page = node.kids[at]
    end
end
function merge_children!(tree::Tree, page::Int, at::Int, name::String, trace)
    parent = tree.pages[page]
    left_page, right_page = parent.kids[at], parent.kids[at + 1]
    left, right = tree.pages[left_page], tree.pages[right_page]
    push!(left.entries, parent.entries[at])
    append!(left.entries, right.entries)
    append!(left.kids, right.kids)
    deleteat!(parent.entries, at)
    deleteat!(parent.kids, at + 1)
    delete!(tree.pages, right_page)
    tree.merges += 1
    step!(trace, "STEP $name page=$page merge=$left_page+$right_page keys=$(notation(left))")
    if page == tree.root && isempty(parent.entries)
        tree.root = left_page
        delete!(tree.pages, page)
        step!(trace, "STEP shrink page=$left_page")
    end
    left_page
end
function borrow_child!(tree::Tree, page::Int, at::Int, from_left::Bool, trace)
    parent = tree.pages[page]
    child_page = parent.kids[at]
    sibling_page = parent.kids[at + (from_left ? -1 : 1)]
    child, sibling = tree.pages[child_page], tree.pages[sibling_page]
    separator = at - Int(from_left)
    if from_left
        pushfirst!(child.entries, parent.entries[separator])
        parent.entries[separator] = pop!(sibling.entries)
        isempty(sibling.kids) || pushfirst!(child.kids, pop!(sibling.kids))
    else
        push!(child.entries, parent.entries[separator])
        parent.entries[separator] = popfirst!(sibling.entries)
        isempty(sibling.kids) || push!(child.kids, popfirst!(sibling.kids))
    end
    tree.borrows += 1
    side = from_left ? "left" : "right"
    step!(trace, "STEP 3a-$side page=$page child=$child_page from=$sibling_page keys=$(notation(child))")
end
function erase_entry!(tree::Tree, page::Int, key::Int, trace = nothing)
    node = tree.pages[page]
    at = node_position(node, key)
    if at <= length(node.entries) && node.entries[at].key == key
        if isempty(node.kids)
            add_case!(trace, "1")
            deleteat!(node.entries, at)
            step!(trace, "STEP 1 page=$page keys=$(notation(node))")
        else
            left, right = node.kids[at], node.kids[at + 1]
            if length(tree.pages[left].entries) >= tree.degree || length(tree.pages[right].entries) >= tree.degree
                predecessor = length(tree.pages[left].entries) >= tree.degree
                child = predecessor ? left : right
                extreme = tree.pages[child]
                while !isempty(extreme.kids)
                    extreme = tree.pages[predecessor ? last(extreme.kids) : first(extreme.kids)]
                end
                replacement = predecessor ? last(extreme.entries) : first(extreme.entries)
                name, detail = predecessor ? ("2a", "pred") : ("2b", "succ")
                add_case!(trace, name)
                step!(trace, "STEP $name page=$page $detail=$(replacement.key)")
                erase_entry!(tree, child, replacement.key, trace)
                node.entries[at] = replacement
            else
                add_case!(trace, "2c")
                child = merge_children!(tree, page, at, "2c", trace)
                erase_entry!(tree, child, key, trace)
            end
        end
    else
        child = node.kids[at]
        if length(tree.pages[child].entries) == tree.degree - 1
            if at > 1 && length(tree.pages[node.kids[at - 1]].entries) >= tree.degree
                add_case!(trace, "3a-left")
                borrow_child!(tree, page, at, true, trace)
            elseif at < length(node.kids) && length(tree.pages[node.kids[at + 1]].entries) >= tree.degree
                add_case!(trace, "3a-right")
                borrow_child!(tree, page, at, false, trace)
            else
                name = at > 1 ? "3b-left" : "3b-right"
                add_case!(trace, name)
                child = merge_children!(tree, page, at > 1 ? at - 1 : at, name, trace)
            end
        end
        erase_entry!(tree, child, key, trace)
    end
    nothing
end
function scan_tree(tree::Tree, lower::Int, upper::Int)
    visited = 0
    result = Entry[]
    function visit(page)
        visited += 1
        node = tree.pages[page]
        n = length(node.entries)
        for j in 1:(n + 1)
            if !isempty(node.kids) && (j == 1 || node.entries[j - 1].key < upper) && (j > n || node.entries[j].key > lower)
                visit(node.kids[j])
            end
            if j <= n && lower <= node.entries[j].key <= upper
                push!(result, node.entries[j])
            end
        end
    end
    visit(tree.root)
    (entries = result, visited = visited)
end
function dump_tree(tree::Tree, page::Int = tree.root)
    node = tree.pages[page]
    result = ["("]
    for j in eachindex(node.entries)
        isempty(node.kids) || append!(result, dump_tree(tree, node.kids[j]))
        push!(result, entry_display(node.entries[j]))
    end
    isempty(node.kids) || append!(result, dump_tree(tree, last(node.kids)))
    push!(result, ")")
end
function load_tree(degree::Int, tokens::Vector{String})
    tree = Tree(degree)
    empty!(tree.pages)
    at = 1
    peek() = at <= length(tokens) ? tokens[at] : ""
    syntax() = fail("ERROR SYNTAX $at")
    function expect(text)
        peek() == text || syntax()
        at += 1
    end
    function read_entry()
        text = peek()
        text in ("", "(", ")") && syntax()
        fields = split(text, '='; limit = 2)
        at += 1
        Entry(parse(Int, fields[1]), String(fields[2]))
    end
    function read_node()
        expect("(")
        page = allocate!(tree)
        node = tree.pages[page]
        internal = peek() == "("
        internal && push!(node.kids, read_node())
        while peek() != ")"
            push!(node.entries, read_entry())
            internal && push!(node.kids, read_node())
        end
        expect(")")
        page
    end
    tree.root = read_node()
    at <= length(tokens) && syntax()
    tree
end
struct Group
    entries::Vector{Entry}
    kids::Vector{Group}
end
function compact_tree(source::Tree)
    entries = inorder(source)
    candidates = Group[]
    degree = source.degree
    local level
    while true
        n = length(entries)
        g = div(n + 2 * degree, 2 * degree)
        d, r = divrem(n - g + 1, g)
        level = Group[]
        separators = Entry[]
        at, child_at = 1, 1
        for i in 1:g
            amount = d + Int(i <= r)
            kids = isempty(candidates) ? Group[] : candidates[child_at:(child_at + amount)]
            push!(level, Group(entries[at:(at + amount - 1)], kids))
            at += amount
            child_at += amount + 1
            if i < g
                push!(separators, entries[at])
                at += 1
            end
        end
        g == 1 && break
        entries, candidates = separators, level
    end
    tree = Tree(degree)
    empty!(tree.pages)
    function assign_pages(group::Group)
        page = allocate!(tree)
        kids = Int[assign_pages(child) for child in group.kids]
        tree.pages[page] = Node(copy(group.entries), kids)
        page
    end
    tree.root = assign_pages(only(level))
    tree
end

@enum CursorKind UNSET AT_KEY BEGINNING ENDING
struct Cursor
    kind::CursorKind
    key::Int
end
mutable struct Laboratory
    index::Union{Nothing,Tree}
    saved::Union{Nothing,Tree}
    cursor::Cursor
    trace::Bool
end
Laboratory() = Laboratory(nothing, nothing, Cursor(UNSET, 0), false)

function execute!(lab::Laboratory, words::Vector{String})
    command, args = words[1], words[2:end]
    if command == "TRACE"
        lab.trace = args[1] == "ON"
        return ["TRACE $(args[1])"]
    elseif command in ("CREATE", "LOAD")
        degree = parse(Int, args[1])
        2 <= degree <= 5 || fail("ERROR BAD DEGREE $degree")
        tree = command == "CREATE" ? Tree(degree) : load_tree(degree, args[2:end])
        lab.index = tree
        lab.cursor = Cursor(UNSET, 0)
        return [command == "CREATE" ? "CREATE t=$degree" : "LOAD t=$degree nodes=$(length(tree.pages)) keys=$(key_count(tree)) $(tree_status(tree))"]
    end
    tree = lab.index
    isnothing(tree) && fail("ERROR NO INDEX")
    needs_valid = command in ("INSERT", "BULKLOAD", "DELETE", "DELRANGE", "RANGE", "COUNT", "MIN", "MAX", "FLOOR", "CEIL", "RANK", "SELECT", "SEEK", "NEXT", "PREV", "HEIGHT", "COMPACT")
    needs_valid && !isnothing(check_tree(tree)) && fail("ERROR DAMAGED")
    command in ("DELRANGE", "RANGE", "COUNT") && parse(Int, args[1]) > parse(Int, args[2]) && fail("ERROR BAD RANGE $(args[1]) $(args[2])")
    command == "SELECT" && !(1 <= parse(Int, args[1]) <= key_count(tree)) && fail("ERROR BAD POSITION $(args[1])")
    command in ("NEXT", "PREV") && lab.cursor.kind == UNSET && fail("ERROR NO CURSOR")
    command == "RESTORE" && isnothing(lab.saved) && fail("ERROR NO SAVE")
    if command == "INSERT"
        key = parse(Int, args[1])
        before = Dict(page => copy(node) for (page, node) in tree.pages)
        splits = tree.splits
        trace = Trace(lab.trace)
        result = put_entry!(tree, Entry(key, args[2]), trace)
        delta = changes(tree, before)
        text = result.added ? "INSERT $key NEW splits=$(tree.splits - splits) height=$(height(tree)) writes=$(delta.writes)" :
            "INSERT $key UPDATED old=$(result.old) writes=$(delta.writes)"
        return vcat(trace.lines, [text])
    elseif command == "BULKLOAD"
        before = Dict(page => copy(node) for (page, node) in tree.pages)
        splits, added = tree.splits, 0
        for i in 1:2:length(args)
            added += put_entry!(tree, Entry(parse(Int, args[i]), args[i + 1])).added
        end
        pairs = div(length(args), 2)
        return ["BULKLOAD pairs=$pairs new=$added updated=$(pairs - added) splits=$(tree.splits - splits) height=$(height(tree)) writes=$(changes(tree, before).writes)"]
    elseif command == "DELETE"
        key = parse(Int, args[1])
        found = search_tree(tree, key)
        found.found || return ["DELETE $key NOT FOUND"]
        old = tree.pages[found.page].entries[found.at].value
        before = Dict(page => copy(node) for (page, node) in tree.pages)
        trace = Trace(lab.trace)
        erase_entry!(tree, tree.root, key, trace)
        delta = changes(tree, before)
        return vcat(trace.lines, ["DELETE $key REMOVED value=$old cases=$(join(trace.cases, ',')) height=$(height(tree)) writes=$(delta.writes) frees=$(delta.frees)"])
    elseif command == "DELRANGE"
        lower, upper = parse.(Int, args)
        before = Dict(page => copy(node) for (page, node) in tree.pages)
        merges, borrows = tree.merges, tree.borrows
        selected = [entry.key for entry in inorder(tree) if lower <= entry.key <= upper]
        for key in selected
            erase_entry!(tree, tree.root, key)
        end
        delta = changes(tree, before)
        return ["DELRANGE $lower $upper removed=$(length(selected)) merges=$(tree.merges - merges) borrows=$(tree.borrows - borrows) height=$(height(tree)) writes=$(delta.writes) frees=$(delta.frees)"]
    elseif command == "GET"
        key = parse(Int, args[1])
        result = search_tree(tree, key)
        outcome = result.found ? "FOUND value=$(tree.pages[result.page].entries[result.at].value)" : "NOT FOUND"
        path = join((notation(tree.pages[page]) for page in result.path), " -> ")
        return ["GET $key $outcome path=$path"]
    elseif command in ("RANGE", "COUNT")
        lower, upper = parse.(Int, args)
        result = scan_tree(tree, lower, upper)
        text = "$command $lower $upper count=$(length(result.entries)) visited=$(result.visited)"
        command == "RANGE" && !isempty(result.entries) && (text *= " " * join(entry_display.(result.entries), " "))
        return [text]
    elseif command in ("MIN", "MAX", "FLOOR", "CEIL", "RANK", "SELECT", "SEEK", "NEXT", "PREV")
        entries = inorder(tree)
        if command in ("MIN", "MAX")
            isempty(entries) && return ["$command EMPTY"]
            return ["$command $(entry_display(command == "MIN" ? first(entries) : last(entries)))"]
        elseif command == "SELECT"
            return ["SELECT $(args[1]) $(entry_display(entries[parse(Int, args[1])]))"]
        elseif command == "RANK"
            return ["RANK $(args[1]) $(count(entry -> entry.key < parse(Int, args[1]), entries))"]
        elseif command in ("FLOOR", "CEIL", "SEEK")
            key = parse(Int, args[1])
            chosen = command == "FLOOR" ? findlast(entry -> entry.key <= key, entries) : findfirst(entry -> entry.key >= key, entries)
            if command == "SEEK"
                lab.cursor = isnothing(chosen) ? Cursor(ENDING, 0) : Cursor(AT_KEY, entries[chosen].key)
            end
            text = isnothing(chosen) ? (command == "SEEK" ? "END" : "NONE") : entry_display(entries[chosen])
            return ["$command $key $text"]
        end
        cursor = lab.cursor
        if command == "NEXT"
            chosen = cursor.kind == ENDING ? nothing : findfirst(entry -> cursor.kind == BEGINNING || entry.key > cursor.key, entries)
        else
            chosen = cursor.kind == BEGINNING ? nothing : findlast(entry -> cursor.kind == ENDING || entry.key < cursor.key, entries)
        end
        if isnothing(chosen)
            lab.cursor = Cursor(command == "NEXT" ? ENDING : BEGINNING, 0)
            return ["$command $(command == "NEXT" ? "END" : "BEGIN")"]
        end
        lab.cursor = Cursor(AT_KEY, entries[chosen].key)
        return ["$command $(entry_display(entries[chosen]))"]
    elseif command == "PRINT"
        level, depth = [tree.root], 0
        result = String[]
        while !isempty(level)
            push!(result, "LEVEL $depth " * join((notation(tree.pages[page]) for page in level), " "))
            level = Int[child for page in level for child in tree.pages[page].kids]
            depth += 1
        end
        return result
    elseif command == "PAGES"
        return ["PAGE $page $(notation(tree.pages[page])) kids=$(isempty(tree.pages[page].kids) ? "-" : join(tree.pages[page].kids, ','))" for page in sort!(collect(keys(tree.pages)))]
    elseif command == "DUMP"
        return ["DUMP $(tree.degree) $(join(dump_tree(tree), ' '))"]
    elseif command == "HEIGHT"
        return ["HEIGHT $(height(tree))"]
    elseif command == "STATS"
        n = length(tree.pages)
        leaves = count(node -> isempty(node.kids), values(tree.pages))
        nkeys = key_count(tree)
        fill = div(100 * nkeys, (2 * tree.degree - 1) * n)
        return ["STATS t=$(tree.degree) nodes=$n leaves=$leaves keys=$nkeys fill=$fill% splits=$(tree.splits) merges=$(tree.merges) borrows=$(tree.borrows)"]
    elseif command == "VERIFY"
        problem = check_tree(tree)
        return ["VERIFY $(isnothing(problem) ? "OK" : problem)"]
    elseif command == "REBUILD"
        entries = inorder(tree)
        rebuilt = Tree(tree.degree)
        for entry in entries
            put_entry!(rebuilt, entry)
        end
        lab.index = rebuilt
        return ["REBUILD entries=$(length(entries)) keys=$(key_count(rebuilt)) nodes=$(length(rebuilt.pages)) splits=$(rebuilt.splits) height=$(height(rebuilt))"]
    elseif command == "COMPACT"
        compacted = compact_tree(tree)
        lab.index = compacted
        return ["COMPACT nodes=$(length(tree.pages))->$(length(compacted.pages)) height=$(height(compacted))"]
    elseif command == "SAVE"
        lab.saved = copy(tree)
        return ["SAVE nodes=$(length(tree.pages)) keys=$(key_count(tree)) $(tree_status(tree))"]
    else
        restored = copy(lab.saved::Tree)
        lab.index = restored
        return ["RESTORE nodes=$(length(restored.pages)) keys=$(key_count(restored)) $(tree_status(restored))"]
    end
end

function main()
    eof(stdin) && return
    commands = parse(Int, readline())
    lab = Laboratory()
    for _ in 1:commands
        words = String.(split(readline(), ' '))
        try
            foreach(println, execute!(lab, words))
        catch error
            error isa CommandError || rethrow()
            println(error.message)
        end
    end
end
main()
end
