const METHODS = [
    "NEXTFIT", "FIRSTFIT", "BESTFIT", "WORSTFIT", "ALMOSTWORST",
    "HARMONIC", "KBOUNDED", "FFD", "BFD", "WFD"
]
const PARAMETERIZED = ("HARMONIC", "KBOUNDED")
const Item = Tuple{Int,Int}
const Rect = NTuple{3,Int}
const Placement = Tuple{Int,Int,Int,Int,Int,Bool}

struct CommandError <: Exception
    reason::String
end
fail(reason) = throw(CommandError(reason))
ceiling(a, b) = cld(a, b)
item_text(item::Item) = string(item[1], ":", item[2])
descending(items::Vector{Item}) = sort(items; by=item -> (-item[2], item[1]))

mutable struct Bin
    items::Vector{Item}
    load::Int
    category::Union{Nothing,Int}
end
Bin(category=nothing) = Bin(Item[], 0, category)
function put!(bin::Bin, item::Item)
    push!(bin.items, item)
    bin.load += item[2]
end
copy_bin(bin::Bin) = Bin(copy(bin.items), bin.load, bin.category)

mutable struct Packing
    method::String
    parameter::Int
    bins::Vector{Bin}
    steps::Vector{Tuple{Item,Int,Int,Bool,Union{Nothing,Int},Union{Nothing,Int}}}
    inspections::Int
    closes::Int
end
Packing(method, parameter) = Packing(
    method, parameter, Bin[],
    Tuple{Item,Int,Int,Bool,Union{Nothing,Int},Union{Nothing,Int}}[], 0, 0
)

function packing_name(packing::Packing)
    packing.method in PARAMETERIZED ?
        string(packing.method, " k=", packing.parameter) : packing.method
end

function packing_header(packing::Packing, capacity::Int, total::Int)
    result = string(packing_name(packing), " bins=", length(packing.bins),
                    " inspections=", packing.inspections,
                    " waste=", length(packing.bins)*capacity - total)
    packing.method == "KBOUNDED" && (result *= " closes=$(packing.closes)")
    result
end

function pack(items::Vector{Item}, capacity::Int, method::String, parameter::Int=0)
    packing = Packing(method, parameter)
    order = method in ("FFD", "BFD", "WFD") ? descending(items) : items
    active = Int[]
    current = Dict{Int,Int}()
    for item in order
        size = item[2]
        previous = packing.inspections
        chosen = nothing
        closed = nothing
        category = nothing
        if method == "NEXTFIT"
            if !isempty(packing.bins)
                packing.inspections += 1
                if packing.bins[end].load + size <= capacity
                    chosen = length(packing.bins)
                end
            end
        elseif method in ("FIRSTFIT", "FFD", "KBOUNDED")
            candidates = method == "KBOUNDED" ? active : collect(eachindex(packing.bins))
            for index in candidates
                packing.inspections += 1
                if packing.bins[index].load + size <= capacity
                    chosen = index
                    break
                end
            end
        elseif method == "HARMONIC"
            category = min(div(capacity, size), parameter)
            if haskey(current, category)
                packing.inspections += 1
                index = current[category]
                packing.bins[index].load + size <= capacity && (chosen = index)
            end
        else
            packing.inspections += length(packing.bins)
            fitting = [index for index in eachindex(packing.bins)
                       if packing.bins[index].load + size <= capacity]
            if !isempty(fitting)
                if method in ("BESTFIT", "BFD")
                    chosen = argmax(index -> (packing.bins[index].load, -index), fitting)
                else
                    sort!(fitting; by=index -> (packing.bins[index].load, index))
                    chosen = method == "ALMOSTWORST" && length(fitting) >= 2 ?
                        fitting[2] : fitting[1]
                end
            end
        end
        opened = isnothing(chosen)
        if opened
            if method == "KBOUNDED" && length(active) == parameter
                closed = argmax(index -> (packing.bins[index].load, -index), active)
                deleteat!(active, findfirst(==(closed), active))
                packing.closes += 1
            end
            push!(packing.bins, Bin(category))
            chosen = length(packing.bins)
            if method == "KBOUNDED"
                push!(active, chosen)
            elseif method == "HARMONIC"
                current[category] = chosen
            end
        end
        put!(packing.bins[chosen], item)
        push!(packing.steps, (item, chosen, packing.inspections - previous,
                              opened, closed, category))
    end
    packing
end

function bounds(items::Vector{Item}, capacity::Int)
    total = sum(item[2] for item in items)
    thresholds = sort(collect(union(Set([0]), Set(item[2] for item in items
                                                 if 2*item[2] <= capacity))))
    rows = NTuple{5,Int}[]
    for alpha in thresholds
        first = [size for (_, size) in items if size > capacity-alpha]
        second = [size for (_, size) in items if 2*size > capacity && size <= capacity-alpha]
        third = [size for (_, size) in items if 2*size <= capacity && size >= alpha]
        excess = sum(third) - (length(second)*capacity - sum(second))
        bound = length(first) + length(second) +
                (excess > 0 ? ceiling(excess, capacity) : 0)
        push!(rows, (alpha, length(first), length(second), length(third), bound))
    end
    (ceiling(total, capacity), maximum(row[5] for row in rows), rows)
end

mutable struct ExactSearch
    items::Vector{Item}
    capacity::Int
    limit::Int
    lower::Int
    best::Vector{Bin}
    live::Vector{Bin}
    remaining::Vector{Int}
    nodes::Int
    status::Union{Nothing,String}
    events::Vector{String}
end

function ExactSearch(items::Vector{Item}, capacity::Int, limit::Int,
                     lower::Int, incumbent::Vector{Bin})
    ordered = descending(items)
    remaining = zeros(Int, length(ordered)+1)
    for i in length(ordered):-1:1
        remaining[i] = remaining[i+1] + ordered[i][2]
    end
    ExactSearch(ordered, capacity, limit, lower, copy_bin.(incumbent),
                Bin[], remaining, 0, nothing, String[])
end

function visit!(search::ExactSearch, index::Int)
    if search.nodes == search.limit
        search.status = "limit"
        return
    end
    search.nodes += 1
    count = length(search.live)
    used = search.remaining[1] - search.remaining[index]
    free = count*search.capacity - used
    excess = search.remaining[index] - free
    minimum = count + (excess > 0 ? ceiling(excess, search.capacity) : 0)
    minimum >= length(search.best) && return
    if index == length(search.items)+1
        search.best = copy_bin.(search.live)
        push!(search.events, "IMPROVE bins=$count nodes=$(search.nodes)")
        count == search.lower && (search.status = "bound")
        return
    end
    item = search.items[index]
    seen = Set{Int}()
    for bin in search.live
        load = bin.load
        load in seen && continue
        push!(seen, load)
        if load + item[2] <= search.capacity
            put!(bin, item)
            visit!(search, index+1)
            pop!(bin.items)
            bin.load = load
            search.status !== nothing && return
        end
    end
    if count+1 < length(search.best)
        bin = Bin()
        put!(bin, item)
        push!(search.live, bin)
        visit!(search, index+1)
        pop!(search.live)
    end
end

mutable struct Shelf
    bottom::Int
    height::Int
    used::Int
    items::Vector{Tuple{Int,Int}}
end
Shelf(bottom, height) = Shelf(bottom, height, 0, Tuple{Int,Int}[])

mutable struct Sheet
    free::Vector{NTuple{4,Int}}
    placements::Vector{Placement}
    area::Int
end
Sheet(width, height) = Sheet([(0, 0, width, height)], Placement[], 0)

mutable struct PackingLab
    items::Union{Nothing,Vector{Item}}
    capacity::Int
    output::Vector{String}
end
PackingLab() = PackingLab(nothing, 0, String[])
emit!(lab::PackingLab, parts...) = push!(lab.output, join(string.(parts), " "))
total(lab::PackingLab) = sum(item[2] for item in lab.items)

function bin_line!(lab::PackingLab, number::Int, bin::Bin,
                   capacity::Int; classes=false, over=false)
    text = "BIN $number load=$(bin.load)/$capacity items=" *
           join(item_text.(bin.items), " ")
    classes && (text *= " class=$(bin.category)")
    over && (text *= " OVER")
    emit!(lab, text)
end
function bin_lines!(lab::PackingLab, bins::Vector{Bin}; classes=false)
    for (number, bin) in enumerate(bins)
        bin_line!(lab, number, bin, lab.capacity; classes=classes)
    end
end

function run_method(lab::PackingLab, method::String, args)
    parameter = method in PARAMETERIZED ? parse(Int, args[1]) : 0
    method in PARAMETERIZED && parameter == 0 && fail("BAD PARAMETER")
    pack(lab.items, lab.capacity, method, parameter)
end

function cmd_items!(lab::PackingLab, args)
    capacity = parse(Int, args[1])
    capacity == 0 && fail("BAD CAPACITY")
    items = Item[(i, parse(Int, size)) for (i, size) in enumerate(args[2:end])]
    for (i, size) in items
        (size == 0 || size > capacity) && fail("BAD ITEM $i")
    end
    lab.capacity, lab.items = capacity, items
    emit!(lab, "ITEMS count=$(length(items)) capacity=$capacity total=$(total(lab))")
end

function cmd_random!(lab::PackingLab, args)
    count, capacity, seed = parse.(Int, args)
    (count == 0 || count > 40) && fail("BAD COUNT")
    capacity == 0 && fail("BAD CAPACITY")
    (seed == 0 || seed >= 2147483647) && fail("BAD SEED")
    items = Item[]
    value = seed
    for i in 1:count
        value = mod(48271*value, 2147483647)
        push!(items, (i, mod(value, capacity)+1))
    end
    lab.capacity, lab.items = capacity, items
    emit!(lab, "RANDOM count=$count capacity=$capacity total=$(total(lab))")
    emit!(lab, "SIZES ", join((item[2] for item in items), " "))
end

function show_method!(lab::PackingLab, method::String, args)
    result = run_method(lab, method, args)
    emit!(lab, packing_header(result, lab.capacity, total(lab)))
    bin_lines!(lab, result.bins; classes=method=="HARMONIC")
end

function cmd_trace!(lab::PackingLab, args)
    method = String(args[1])
    result = run_method(lab, method, args[2:end])
    emit!(lab, "TRACE ", packing_header(result, lab.capacity, total(lab)))
    for (index, (item, bin, inspected, opened, closed, category)) in enumerate(result.steps)
        text = "STEP $index item=$(item_text(item)) bin=$bin inspected=$inspected"
        opened && (text *= " new")
        !isnothing(closed) && (text *= " closed=$closed")
        !isnothing(category) && (text *= " class=$category")
        emit!(lab, text)
    end
end

function cmd_reduce!(lab::PackingLab, args)
    method = String(args[1])
    result = run_method(lab, method, args[2:end])
    bins = result.bins
    before = length(bins)
    events = String[]
    while true
        eliminated = false
        sources = sort(collect(eachindex(bins)); by=i -> (bins[i].load, i))
        for source in sources
            loads = [bin.load for bin in bins]
            moves = Tuple{Item,Int}[]
            success = true
            for item in descending(bins[source].items)
                fitting = [i for i in eachindex(bins)
                           if i != source && loads[i]+item[2] <= lab.capacity]
                if isempty(fitting)
                    success = false
                    break
                end
                destination = argmax(i -> (loads[i], -i), fitting)
                loads[destination] += item[2]
                push!(moves, (item, destination))
            end
            if success
                movement = join(("$(item_text(item))->$dest" for (item, dest) in moves), " ")
                push!(events, "ELIMINATE bin=$source load=$(bins[source].load) moves=$movement")
                for (item, dest) in moves
                    put!(bins[dest], item)
                end
                deleteat!(bins, source)
                eliminated = true
                break
            end
        end
        eliminated || break
    end
    emit!(lab, "REDUCE $(packing_name(result)) before=$before after=$(length(bins)) eliminated=$(before-length(bins))")
    foreach(event -> emit!(lab, event), events)
    bin_lines!(lab, bins; classes=method=="HARMONIC")
end

function cmd_bounds!(lab::PackingLab)
    l1, l2, rows = bounds(lab.items, lab.capacity)
    emit!(lab, "BOUNDS total=$(total(lab)) L1=$l1 L2=$l2")
    for (alpha, j1, j2, j3, bound) in rows
        emit!(lab, "ALPHA $alpha j1=$j1 j2=$j2 j3=$j3 bound=$bound")
    end
end

function cmd_compare!(lab::PackingLab, args)
    k = parse(Int, args[1])
    k == 0 && fail("BAD PARAMETER")
    l1, l2, _ = bounds(lab.items, lab.capacity)
    results = [pack(lab.items, lab.capacity, method, k) for method in METHODS]
    sort!(results; by=p -> (length(p.bins), p.method))
    emit!(lab, "COMPARE k=$k L1=$l1 L2=$l2")
    for result in results
        count = length(result.bins)
        emit!(lab, "$(result.method) bins=$count gap=$(count-l2) waste=$(count*lab.capacity-total(lab)) inspections=$(result.inspections)")
    end
end

function cmd_exact!(lab::PackingLab, args)
    limit = parse(Int, args[1])
    limit == 0 && fail("BAD PARAMETER")
    length(lab.items) >= 21 && fail("TOO MANY ITEMS")
    initial = pack(lab.items, lab.capacity, "FFD").bins
    _, l2, _ = bounds(lab.items, lab.capacity)
    emit!(lab, "EXACT ffd=$(length(initial)) L2=$l2")
    search = ExactSearch(lab.items, lab.capacity, limit, l2, initial)
    if length(initial) == l2
        search.status = "bound"
    else
        visit!(search, 1)
    end
    for event in search.events
        emit!(lab, event)
    end
    status = isnothing(search.status) ? "complete" : search.status
    emit!(lab, "RESULT bins=$(length(search.best)) nodes=$(search.nodes) status=$status")
    bin_lines!(lab, search.best)
end

function cmd_check!(lab::PackingLab, args)
    labels = parse.(Int, args)
    (length(labels) != length(lab.items) || any(==(0), labels)) &&
        fail("BAD ASSIGNMENT")
    bins = Dict{Int,Bin}()
    for (label, item) in zip(labels, lab.items)
        bin = get!(bins, label) do
            Bin()
        end
        put!(bin, item)
    end
    overfull = count(bin -> bin.load > lab.capacity, values(bins))
    _, l2, _ = bounds(lab.items, lab.capacity)
    emit!(lab, "CHECK bins=$(length(bins)) over=$overfull L2=$l2 status=$(overfull==0 ? "valid" : "invalid")")
    for label in sort(collect(keys(bins)))
        bin_line!(lab, label, bins[label], lab.capacity; over=bins[label].load > lab.capacity)
    end
end

function cover_lines!(lab::PackingLab, method::String, bins::Vector{Bin})
    covered = [bin for bin in bins if bin.load >= lab.capacity]
    rest = findfirst(bin -> bin.load < lab.capacity, bins)
    remaining = isnothing(rest) ? 0 : bins[rest].load
    emit!(lab, "$method covered=$(length(covered)) rest=$remaining")
    bin_lines!(lab, covered)
    if !isnothing(rest)
        emit!(lab, "REST items=", join(item_text.(bins[rest].items), " "))
    end
end

function cmd_cover!(lab::PackingLab)
    emit!(lab, "COVER total=$(total(lab)) upper=$(div(total(lab), lab.capacity))")
    sequential = Bin[]
    for item in lab.items
        if isempty(sequential) || sequential[end].load >= lab.capacity
            push!(sequential, Bin())
        end
        put!(sequential[end], item)
    end
    cover_lines!(lab, "DNF", sequential)
    available = descending(lab.items)
    paired = Bin[]
    while !isempty(available)
        bin = Bin()
        put!(bin, popfirst!(available))
        while bin.load < lab.capacity && !isempty(available)
            put!(bin, pop!(available))
        end
        push!(paired, bin)
    end
    cover_lines!(lab, "BIGSMALL", paired)
end

function machine_lines!(lab::PackingLab, machines::Vector{Bin})
    for (number, bin) in enumerate(machines)
        items = isempty(bin.items) ? "-" : join(item_text.(bin.items), " ")
        emit!(lab, "MACHINE $number load=$(bin.load) items=$items")
    end
end

function cmd_multifit!(lab::PackingLab, args)
    count = parse(Int, args[1])
    count == 0 && fail("BAD PARAMETER")
    total_size = total(lab)
    largest = maximum(item[2] for item in lab.items)
    lower = max(ceiling(total_size, count), largest)
    upper = max(ceiling(2*total_size, count), largest)
    emit!(lab, "MULTIFIT m=$count lower=$lower upper=$upper")
    while lower < upper
        middle = div(lower+upper, 2)
        bins = length(pack(lab.items, middle, "FFD").bins)
        success = bins <= count
        emit!(lab, "TRY cap=$middle bins=$bins $(success ? "ok" : "fail")")
        if success
            upper = middle
        else
            lower = middle+1
        end
    end
    machines = pack(lab.items, upper, "FFD").bins
    append!(machines, [Bin() for _ in 1:(count-length(machines))])
    emit!(lab, "RESULT cap=$upper makespan=$(maximum(bin.load for bin in machines))")
    machine_lines!(lab, machines)
    lpt = [Bin() for _ in 1:count]
    for item in descending(lab.items)
        index = argmin(i -> (lpt[i].load, i), eachindex(lpt))
        put!(lpt[index], item)
    end
    emit!(lab, "LPT makespan=$(maximum(bin.load for bin in lpt))")
    machine_lines!(lab, lpt)
end

function maximal_patterns(capacity::Int, pieces::Vector{Tuple{Int,Int}})
    patterns = Tuple{Vector{Int},Int}[]
    function enumerate_prefix!(index::Int, remaining::Int, prefix::Vector{Int})
        size = pieces[index][1]
        maximum = div(remaining, size)
        if index == length(pieces)
            push!(patterns, (vcat(prefix, [maximum]), remaining-maximum*size))
            return
        end
        for count in maximum:-1:0
            enumerate_prefix!(index+1, remaining-count*size, vcat(prefix, [count]))
        end
    end
    enumerate_prefix!(1, capacity, Int[])
    patterns
end

function cmd_cutstock!(lab::PackingLab, args)
    capacity = parse(Int, args[1])
    capacity == 0 && fail("BAD CAPACITY")
    pieces = Tuple{Int,Int}[]
    seen = Set{Int}()
    for (number, token) in enumerate(args[2:end])
        size, demand = parse.(Int, split(token, ':'))
        (size == 0 || size > capacity || demand == 0) &&
            fail("BAD PIECE $number")
        size in seen && fail("DUPLICATE PIECE $number")
        push!(seen, size)
        push!(pieces, (size, demand))
    end
    sort!(pieces; by=x -> -x[1])
    patterns = maximal_patterns(capacity, pieces)
    remaining = [demand for (_, demand) in pieces]
    uses = zeros(Int, length(patterns))
    while any(>(0), remaining)
        chosen = argmax(i -> (
            sum(min(count, needed) for (count, needed)
                in zip(patterns[i][1], remaining)), -i
        ), eachindex(patterns))
        uses[chosen] += 1
        remaining = [max(0, needed-count) for (needed, count)
                     in zip(remaining, patterns[chosen][1])]
    end
    cut = [sum(uses[p]*patterns[p][1][index] for p in eachindex(patterns))
           for index in eachindex(pieces)]
    quantity = sum(size*demand for (size, demand) in pieces)
    bars = sum(uses)
    emit!(lab, "CUTSTOCK L=$capacity pieces=$(length(pieces)) patterns=$(length(patterns))")
    for (number, (counts, trim)) in enumerate(patterns)
        breakdown = join(("$count" * "x" * "$size" for (count, (size, _))
                          in zip(counts, pieces) if count > 0), "+")
        emit!(lab, "PATTERN $number $breakdown rest=$trim")
    end
    for (number, use) in enumerate(uses)
        use > 0 && emit!(lab, "USE $number bars=$use")
    end
    for ((size, demand), count) in zip(pieces, cut)
        emit!(lab, "PIECE $size demand=$demand cut=$count")
    end
    trim = sum(uses[i]*patterns[i][2] for i in eachindex(patterns))
    surplus = sum(cut) - sum(demand for (_, demand) in pieces)
    emit!(lab, "TOTAL bars=$bars trim=$trim surplus=$surplus waste=$(bars*capacity-quantity)")
    sizes = [size for (size, demand) in pieces for _ in 1:demand]
    items = Item[(i, size) for (i, size) in enumerate(sizes)]
    ffd = length(pack(items, capacity, "FIRSTFIT").bins)
    emit!(lab, "FFD bars=$ffd waste=$(ffd*capacity-quantity)")
    emit!(lab, "LOWER bars=$(ceiling(quantity, capacity))")
end

function rectangles(tokens)
    Rect[(i, parse(Int, split(token, 'x')[1]), parse(Int, split(token, 'x')[2]))
         for (i, token) in enumerate(tokens)]
end

function draw!(lab::PackingLab, width::Int, height::Int, placements::Vector{Placement})
    cells = [fill('.', width) for _ in 1:height]
    for (number, x, y, w, h, _) in placements
        letter = Char(Int('A') + number - 1)
        for row in y:(y+h-1), column in x:(x+w-1)
            cells[row+1][column+1] = letter
        end
    end
    for row in height:-1:1
        emit!(lab, join(cells[row]))
    end
end

function shelf_method!(lab::PackingLab, method::String, width::Int,
                       rects::Vector{Rect}, area::Int)
    shelves = Shelf[]
    placements = Placement[]
    for (number, w, h) in rects
        chosen = nothing
        if method == "NFDH"
            if !isempty(shelves) && shelves[end].used + w <= width
                chosen = length(shelves)
            end
        else
            fitting = [i for i in eachindex(shelves) if shelves[i].used + w <= width]
            if !isempty(fitting)
                chosen = method == "FFDH" ? fitting[1] :
                    argmax(i -> (shelves[i].used, -i), fitting)
            end
        end
        if isnothing(chosen)
            bottom = isempty(shelves) ? 0 : shelves[end].bottom + shelves[end].height
            push!(shelves, Shelf(bottom, h))
            chosen = length(shelves)
        end
        shelf = shelves[chosen]
        push!(shelf.items, (number, shelf.used))
        push!(placements, (number, shelf.used, shelf.bottom, w, h, false))
        shelf.used += w
    end
    height = shelves[end].bottom + shelves[end].height
    emit!(lab, "$method height=$height shelves=$(length(shelves)) util=$(div(area*100, width*height))")
    for (number, shelf) in enumerate(shelves)
        items = join(("$(Char(Int('A')+item-1))@$x" for (item, x) in shelf.items), " ")
        emit!(lab, "LEVEL $number y=$(shelf.bottom) h=$(shelf.height) used=$(shelf.used) items=$items")
    end
    draw!(lab, width, height, placements)
end

function cmd_shelf!(lab::PackingLab, args)
    width = parse(Int, args[1])
    width == 0 && fail("BAD CAPACITY")
    rects = rectangles(args[2:end])
    for (number, w, h) in rects
        (w == 0 || h == 0 || w > width) && fail("BAD RECT $number")
    end
    sort!(rects; by=rect -> (-rect[3], -rect[2], rect[1]))
    area = sum(w*h for (_, w, h) in rects)
    emit!(lab, "SHELF W=$width rects=$(length(rects)) area=$area")
    for method in ("NFDH", "FFDH", "BFDH")
        shelf_method!(lab, method, width, rects, area)
    end
    heights = zeros(Int, width)
    placements = Placement[]
    for (number, w, h) in rects
        x = argmin(column -> (maximum(heights[column+1:column+w]), column),
                   0:(width-w))
        y = maximum(heights[x+1:x+w])
        heights[x+1:x+w] .= y+h
        push!(placements, (number, x, y, w, h, false))
    end
    height = maximum(heights)
    emit!(lab, "SKYLINE height=$height util=$(div(area*100, width*height))")
    for (number, x, y, w, h, _) in placements
        emit!(lab, "PLACE $(Char(Int('A')+number-1)) x=$x y=$y w=$w h=$h")
    end
    draw!(lab, width, height, placements)
end

function free_rectangle(sheets::Vector{Sheet}, width::Int, height::Int,
                        rotate::Bool, rule::String)
    chosen = nothing
    best = nothing
    for (number, sheet) in enumerate(sheets)
        for (index, (_, _, fw, fh)) in enumerate(sheet.free)
            fits = width <= fw && height <= fh
            fits_rotated = rotate && height <= fw && width <= fh
            (fits || fits_rotated) || continue
            if rule == "FIRST"
                return (number, index)
            end
            key = (fw*fh, number, index)
            if isnothing(best) || key < best
                best, chosen = key, (number, index)
            end
        end
    end
    chosen
end

function cmd_guillotine!(lab::PackingLab, args)
    width, height = parse.(Int, args[1:2])
    (width == 0 || height == 0) && fail("BAD CAPACITY")
    mode, rule = args[3], args[4]
    rects = rectangles(args[5:end])
    rotate = mode == "ROTATE"
    for (number, w, h) in rects
        fits = w <= width && h <= height
        swapped = rotate && h <= width && w <= height
        (w == 0 || h == 0 || !(fits || swapped)) && fail("BAD RECT $number")
    end
    sort!(rects; by=rect -> (-rect[2]*rect[3], rect[1]))
    sheets = Sheet[]
    rotated_count = 0
    for (number, w, h) in rects
        chosen = free_rectangle(sheets, w, h, rotate, rule)
        if isnothing(chosen)
            push!(sheets, Sheet(width, height))
            chosen = (length(sheets), 1)
        end
        sheet_number, index = chosen
        sheet = sheets[sheet_number]
        x, y, fw, fh = sheet.free[index]
        deleteat!(sheet.free, index)
        rotated = !(w <= fw && h <= fh)
        pw, ph = rotated ? (h, w) : (w, h)
        rotated_count += rotated
        push!(sheet.placements, (number, x, y, pw, ph, rotated))
        sheet.area += w*h
        rw, rh = fw-pw, fh-ph
        children = rw <= rh ?
            ((x, y+ph, fw, rh), (x+pw, y, rw, ph)) :
            ((x, y+ph, pw, rh), (x+pw, y, rw, fh))
        for child in children
            child[3] > 0 && child[4] > 0 && push!(sheet.free, child)
        end
    end
    area = sum(sheet.area for sheet in sheets)
    utilization = div(area*100, length(sheets)*width*height)
    emit!(lab, "GUILLOTINE W=$width H=$height mode=$mode rule=$rule rects=$(length(rects)) sheets=$(length(sheets)) rotated=$rotated_count util=$utilization")
    for (number, sheet) in enumerate(sheets)
        emit!(lab, "SHEET $number placed=$(length(sheet.placements)) area=$(sheet.area)")
        for (item, x, y, w, h, rotated) in sheet.placements
            text = "PLACE $(Char(Int('A')+item-1)) x=$x y=$y w=$w h=$h"
            emit!(lab, text * (rotated ? " rotated" : ""))
        end
        free = isempty(sheet.free) ? "none" :
            join(("$x,$y,$w" * "x$h" for (x, y, w, h) in sheet.free), " ")
        emit!(lab, "FREE ", free)
        draw!(lab, width, height, sheet.placements)
    end
end

function execute!(lab::PackingLab, line::String)
    words = String.(split(strip(line)))
    command = words[1]
    args = words[2:end]
    try
        if !(command in ("ITEMS", "RANDOM", "CUTSTOCK", "SHELF", "GUILLOTINE")) &&
           isnothing(lab.items)
            fail("NO ITEMS")
        end
        if command in METHODS
            show_method!(lab, command, args)
        elseif command == "ITEMS"
            cmd_items!(lab, args)
        elseif command == "RANDOM"
            cmd_random!(lab, args)
        elseif command == "TRACE"
            cmd_trace!(lab, args)
        elseif command == "REDUCE"
            cmd_reduce!(lab, args)
        elseif command == "BOUNDS"
            cmd_bounds!(lab)
        elseif command == "COMPARE"
            cmd_compare!(lab, args)
        elseif command == "EXACT"
            cmd_exact!(lab, args)
        elseif command == "CHECK"
            cmd_check!(lab, args)
        elseif command == "COVER"
            cmd_cover!(lab)
        elseif command == "MULTIFIT"
            cmd_multifit!(lab, args)
        elseif command == "CUTSTOCK"
            cmd_cutstock!(lab, args)
        elseif command == "SHELF"
            cmd_shelf!(lab, args)
        elseif command == "GUILLOTINE"
            cmd_guillotine!(lab, args)
        end
    catch error
        if error isa CommandError
            emit!(lab, "ERROR ", error.reason)
        else
            rethrow()
        end
    end
end

function main()
    count = parse(Int, readline(stdin))
    lab = PackingLab()
    for _ in 1:count
        execute!(lab, readline(stdin))
    end
    isempty(lab.output) || println(join(lab.output, "\n"))
end

main()
