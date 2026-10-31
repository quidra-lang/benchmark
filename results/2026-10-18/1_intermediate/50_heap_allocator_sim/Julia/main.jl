using Printf

mutable struct Block
    start::Int
    size::Int
    owner::String
    requested::Int
    data::Vector{Int}
    stamp::Int
end
Block(a::Int, s::Int) = Block(a, s, "", 0, Int[], 0)
used(b::Block) = !isempty(b.owner)
area(b::Block) = "$(b.start)+$(b.size)"
mutable struct Heap
    size::Int
    mode::String
    rover::Int
    age::Int
    blocks::Vector{Block}
end
function register!(h::Heap, b::Block)
    h.age += 1
    b.stamp = h.age
    b
end
function Heap(s::Int, m::String)
    h = Heap(s, m, 0, 0, Block[])
    push!(h.blocks, register!(h, Block(0, s)))
    h
end
power2(x::Int) = x > 0 && (x & (x - 1)) == 0
classof(x::Int) = ndigits(x; base=2) - 1
function required(h::Heap, n::Int)
    s = cld(n, 8) * 8 + 8
    if h.mode == "BUDDY"
        p = 32
        while p < s
            p *= 2
        end
        return p
    end
    s
end
usedtotal(h::Heap) = sum((b.size for b in h.blocks if used(b)); init=0)
function frag(h::Heap)
    sizes = [b.size for b in h.blocks if !used(b)]
    f = sum(sizes)
    f == 0 ? 0 : div((f - maximum(sizes)) * 100, f)
end
function halve!(h::Heap, i::Int, s::Int)
    b = h.blocks[i]
    while b.size > s
        b.size = div(b.size, 2)
        insert!(h.blocks, i + 1, register!(h, Block(b.start + b.size, b.size)))
    end
end
function allocate!(h::Heap, s::Int, al::Int)
    ri = findfirst(b -> b.start <= h.rover < b.start + b.size, h.blocks)
    choices = Tuple{Tuple{Int,Int},Int,Int}[]
    for (i, b) in enumerate(h.blocks)
        used(b) && continue
        p = cld(b.start + 8, al) * al - 8
        if 0 < p - b.start < 16
            p += al
        end
        p + s > b.start + b.size && continue
        rank = if h.mode == "NEXT"
            (mod(i - ri, length(h.blocks)), 0)
        elseif h.mode in ("BEST", "BUDDY")
            (b.size, b.start)
        elseif h.mode == "WORST"
            (-b.size, b.start)
        elseif h.mode == "SEGFIT"
            (classof(b.size), -b.stamp)
        else
            (b.start, 0)
        end
        push!(choices, (rank, i, p))
    end
    isempty(choices) && return nothing
    _, i, p = minimum(choices)
    if h.mode == "BUDDY"
        halve!(h, i, s)
        b = h.blocks[i]
    else
        old = h.blocks[i]
        parts = Block[]
        if p > old.start
            push!(parts, register!(h, Block(old.start, p - old.start)))
        end
        b = Block(p, old.start + old.size - p)
        push!(parts, b)
        if b.size - s >= 16
            push!(parts, register!(h, Block(p + s, b.size - s)))
            b.size = s
        end
        splice!(h.blocks, i:i, parts)
    end
    b.owner = "@"
    if h.mode == "NEXT"
        h.rover = mod(b.start + b.size, h.size)
    end
    b
end
function coalesce!(h::Heap, i::Int)
    merges = 0
    if h.mode == "BUDDY"
        while h.blocks[i].size < h.size
            b = h.blocks[i]
            a = xor(b.start, b.size)
            j = findfirst(x -> !used(x) && x.start == a && x.size == b.size, h.blocks)
            j === nothing && break
            i = min(i, j)
            h.blocks[i].size += h.blocks[i + 1].size
            deleteat!(h.blocks, i + 1)
            merges += 1
        end
    else
        if i < length(h.blocks) && !used(h.blocks[i + 1])
            h.blocks[i].size += h.blocks[i + 1].size
            deleteat!(h.blocks, i + 1)
            merges += 1
        end
        if i > 1 && !used(h.blocks[i - 1])
            i -= 1
            h.blocks[i].size += h.blocks[i + 1].size
            deleteat!(h.blocks, i + 1)
            merges += 1
        end
    end
    register!(h, h.blocks[i]), merges
end
function release!(h::Heap, b::Block)
    b.owner = ""
    b.requested = 0
    empty!(b.data)
    coalesce!(h, findfirst(x -> x === b, h.blocks))
end
function resizeblock!(h::Heap, b::Block, s::Int)
    i = findfirst(x -> x === b, h.blocks)
    if s <= b.size
        if h.mode == "BUDDY"
            s == b.size && return "kept"
            halve!(h, i, s)
        else
            b.size - s < 16 && return "kept"
            insert!(h.blocks, i + 1, Block(b.start + s, b.size - s))
            b.size = s
            coalesce!(h, i + 1)
        end
        return "shrunk"
    end
    if h.mode == "BUDDY"
        z = b.size
        j = i
        while z < s
            j += 1
            if mod(b.start, 2z) != 0 || j > length(h.blocks)
                return nothing
            end
            p = h.blocks[j]
            (used(p) || p.size != z) && return nothing
            z *= 2
        end
        deleteat!(h.blocks, (i + 1):j)
        b.size = s
        return "grown"
    end
    if i < length(h.blocks) && !used(h.blocks[i + 1])
        z = b.size + h.blocks[i + 1].size
        if z >= s
            deleteat!(h.blocks, i + 1)
            b.size = z
            if z - s >= 16
                b.size = s
                insert!(h.blocks, i + 1, register!(h, Block(b.start + s, z - s)))
            end
            return "grown"
        end
    end
    nothing
end
mutable struct Allocator
    heap::Union{Nothing,Heap}
    live::Dict{String,Block}
    freed::Set{String}
    roots::Set{String}
    refs::Dict{String,Set{String}}
    histories::Dict{String,Vector{String}}
    counts::Vector{Int}
    peak::Int
end
Allocator(h=nothing) = Allocator(h, Dict{String,Block}(), Set{String}(), Set{String}(), Dict{String,Set{String}}(), Dict{String,Vector{String}}(), zeros(Int, 6), 0)
struct CommandError <: Exception
    text::String
end
fail(s) = throw(CommandError(s))
function record!(a::Allocator, id::String, line::String)
    println(line)
    push!(get!(a.histories, id, String[]), line)
end
function live(a::Allocator, id::String)
    haskey(a.live, id) && return a.live[id]
    fail((id in a.freed ? "USE AFTER FREE " : "UNKNOWN ID ") * id)
end
function bounds(a::Allocator, id::String, off::Int, len::Int)
    b = live(a, id)
    off + len > b.requested && fail("OUT OF BOUNDS $id")
    b
end
function reachable(a::Allocator)
    seen = copy(a.roots)
    todo = collect(seen)
    while !isempty(todo)
        id = pop!(todo)
        for dst in get(a.refs, id, Set{String}())
            if !(dst in seen)
                push!(seen, dst)
                push!(todo, dst)
            end
        end
    end
    seen
end
function malloc!(a::Allocator, word::String, id::String, n::Int, al::Int=8, value::Int=-1)
    n == 0 && fail("BAD SIZE")
    haskey(a.live, id) && fail("DUPLICATE ID $id")
    b = allocate!(a.heap, required(a.heap, n), al)
    if b === nothing
        a.counts[5] += 1
        fail("OUT OF MEMORY $id")
    end
    b.owner = id
    b.requested = n
    b.data = fill(value, n)
    a.live[id] = b
    delete!(a.freed, id)
    a.counts[1] += 1
    record!(a, id, "$word $id addr=$(b.start + 8) block=$(b.size)")
end
function releaseid!(a::Allocator, id::String)
    b = pop!(a.live, id)
    z = b.size
    push!(a.freed, id)
    delete!(a.roots, id)
    delete!(a.refs, id)
    for targets in values(a.refs)
        delete!(targets, id)
    end
    f, m = release!(a.heap, b)
    "block=$z merges=$m free=$(area(f))"
end
function freeid!(a::Allocator, id::String)
    id in a.freed && fail("DOUBLE FREE $id")
    haskey(a.live, id) || fail("UNKNOWN ID $id")
    details = releaseid!(a, id)
    a.counts[2] += 1
    record!(a, id, "FREE $id $details")
end
function tree(h::Heap, start::Int, size::Int, depth::Int)
    label = repeat(" ", 2depth) * "$start+$size"
    i = findfirst(b -> b.start == start && b.size == size, h.blocks)
    if i !== nothing
        b = h.blocks[i]
        println(label, used(b) ? " USED $(b.owner)" : " FREE")
    else
        println(label, " split")
        half = div(size, 2)
        tree(h, start, half, depth + 1)
        tree(h, start + half, half, depth + 1)
    end
end
function experiment(mode::String, size::Int, seed::Int, ops::Int, maxreq::Int)
    h = Heap(size, mode)
    x = seed
    active = Block[]
    ok = bad = peak = 0
    for _ in 1:ops
        x = mod(48271x, 2147483647)
        alloc = isempty(active) || mod(x, 3) != 0
        x = mod(48271x, 2147483647)
        if alloc
            b = allocate!(h, required(h, 1 + mod(x, maxreq)), 8)
            if b === nothing
                bad += 1
            else
                ok += 1
                push!(active, b)
            end
        else
            b = splice!(active, mod(x, length(active)) + 1)
            release!(h, b)
        end
        peak = max(peak, usedtotal(h))
    end
    println("BENCH $mode ok=$ok fail=$bad peak=$peak used=$(usedtotal(h)) frag=$(frag(h)) blocks=$(length(h.blocks))")
end
function execute!(a::Allocator, words::Vector{String})
    cmd = words[1]
    v = words[2:end]
    num(i) = parse(Int, v[i])
    h = a.heap
    if cmd == "HEAP"
        s, m = num(1), v[2]
        (s % 8 != 0 || !(32 <= s <= 65536) || (m == "BUDDY" && !power2(s))) && fail("BAD HEAP SIZE")
        fresh = Allocator(Heap(s, m))
        for name in fieldnames(Allocator)
            setfield!(a, name, getfield(fresh, name))
        end
        println("HEAP size=$s mode=$m")
    elseif cmd == "BENCH"
        s, seed, ops, maxreq = num.(1:4)
        (!power2(s) || !(32 <= s <= 65536)) && fail("BAD HEAP SIZE")
        println("BENCH heap=$s seed=$seed ops=$ops maxreq=$maxreq")
        for m in ("FIRST", "NEXT", "BEST", "WORST", "SEGFIT", "BUDDY")
            experiment(m, s, seed, ops, maxreq)
        end
    elseif h === nothing
        fail("NO HEAP")
    elseif cmd in ("MALLOC", "CALLOC", "MEMALIGN")
        al, n, value = 8, num(2), -1
        if cmd == "CALLOC"
            n = num(2) * num(3)
            value = 0
        elseif cmd == "MEMALIGN"
            h.mode == "BUDDY" && fail("UNSUPPORTED IN BUDDY MODE")
            al, n = num(2), num(3)
            (!power2(al) || !(8 <= al <= 4096)) && fail("BAD ALIGNMENT")
        end
        malloc!(a, cmd, v[1], n, al, value)
    elseif cmd == "FREE"
        freeid!(a, v[1])
    elseif cmd == "REALLOC"
        id, n = v[1], num(2)
        if n == 0
            freeid!(a, id)
        elseif id in a.freed
            fail("USE AFTER FREE $id")
        elseif !haskey(a.live, id)
            malloc!(a, "MALLOC", id, n)
        else
            b = a.live[id]
            data = fill(-1, n)
            k = min(n, b.requested)
            data[1:k] = b.data[1:k]
            origin = b.start + 8
            kind = resizeblock!(h, b, required(h, n))
            if kind === nothing
                moved = allocate!(h, required(h, n), 8)
                if moved === nothing
                    a.counts[5] += 1
                    fail("OUT OF MEMORY $id")
                end
                moved.owner = id
                a.live[id] = moved
                release!(h, b)
                b = moved
                a.counts[4] += 1
                kind = "moved from=$origin"
            end
            b.requested, b.data = n, data
            a.counts[3] += 1
            record!(a, id, "REALLOC $id addr=$(b.start + 8) block=$(b.size) $kind")
        end
    elseif cmd in ("FILL", "READ")
        id, off, len = v[1], num(2), num(3)
        b = bounds(a, id, off, len)
        if cmd == "FILL"
            b.data[(off + 1):(off + len)] .= num(4)
            println("FILL $id $off+$len = $(num(4))")
        else
            text = join((x == -1 ? "?" : string(x) for x in b.data[(off + 1):(off + len)]), " ")
            println("READ $id $off+$len = $text")
        end
    elseif cmd == "COPY"
        dst, doff, src, soff, len = v[1], num(2), v[3], num(4), num(5)
        d = bounds(a, dst, doff, len)
        s = bounds(a, src, soff, len)
        d.data[(doff + 1):(doff + len)] = copy(s.data[(soff + 1):(soff + len)])
        println("COPY $dst $doff+$len from $src $soff")
    elseif cmd in ("ROOT", "UNROOT")
        id = v[1]
        live(a, id)
        if cmd == "ROOT"
            push!(a.roots, id)
        else
            id in a.roots || fail("NOT ROOT $id")
            delete!(a.roots, id)
        end
        println("$cmd $id")
    elseif cmd in ("LINK", "UNLINK")
        src, dst = v
        live(a, src)
        live(a, dst)
        targets = get!(a.refs, src, Set{String}())
        if cmd == "LINK"
            push!(targets, dst)
        else
            dst in targets || fail("NO LINK $src $dst")
            delete!(targets, dst)
        end
        println("$cmd $src $dst")
    elseif cmd == "GC"
        seen = reachable(a)
        garbage = sort([b for (id, b) in a.live if !(id in seen)]; by=b -> b.start)
        println("GC collected=$(length(garbage)) bytes=$(sum((b.size for b in garbage); init=0))")
        for b in garbage
            id = b.owner
            record!(a, id, "COLLECT $id $(releaseid!(a, id))")
        end
        a.counts[6] += length(garbage)
    elseif cmd == "SBRK"
        k = num(1)
        valid = h.mode == "BUDDY" ? k == h.size && 2h.size <= 65536 : k % 8 == 0 && k >= 16 && h.size + k <= 65536
        valid || fail("BAD SBRK SIZE")
        push!(h.blocks, Block(h.size, k))
        h.size += k
        f, _ = coalesce!(h, length(h.blocks))
        println("SBRK heap=$(h.size) free=$(area(f))")
    elseif cmd == "TRIM"
        old = h.size
        if h.mode == "BUDDY"
            while !used(h.blocks[end]) && 2h.blocks[end].size == h.size
                h.size -= pop!(h.blocks).size
            end
        elseif length(h.blocks) >= 2 && !used(h.blocks[end])
            h.size = pop!(h.blocks).start
        end
        h.rover >= h.size && (h.rover = 0)
        println("TRIM heap=$(h.size) released=$(old - h.size)")
    elseif cmd == "COMPACT"
        h.mode == "BUDDY" && fail("UNSUPPORTED IN BUDDY MODE")
        packed = filter(used, h.blocks)
        moves = Tuple{Block,Int}[]
        pos = 0
        for b in packed
            if b.start != pos
                push!(moves, (b, b.start + 8))
                b.start = pos
            end
            pos += b.size
        end
        free = pos == h.size ? "none" : "$pos+$(h.size - pos)"
        pos < h.size && push!(packed, register!(h, Block(pos, h.size - pos)))
        h.blocks, h.rover = packed, 0
        a.counts[4] += length(moves)
        println("COMPACT moved=$(length(moves)) free=$free")
        for (b, origin) in moves
            record!(a, b.owner, "MOVE $(b.owner) $origin -> $(b.start + 8)")
        end
    elseif cmd == "WHO"
        p = num(1)
        if p >= h.size
            println("WHO $p outside")
        else
            b = h.blocks[findfirst(b -> b.start <= p < b.start + b.size, h.blocks)]
            if !used(b)
                println("WHO $p free $(area(b))")
            elseif p < b.start + 8
                println("WHO $p header $(b.owner)")
            else
                d = p - b.start - 8
                region = d < b.requested ? "data" : "slack"
                println("WHO $p $region $(b.owner)+$d")
            end
        end
    elseif cmd == "DUMP"
        tail = h.mode == "NEXT" ? " rover=$(h.rover)" : ""
        println("DUMP mode=$(h.mode) heap=$(h.size) blocks=$(length(h.blocks))$tail")
        for b in h.blocks
            println("$(b.start) $(b.size) ", used(b) ? "USED $(b.owner) req=$(b.requested)" : "FREE")
        end
    elseif cmd == "MAP"
        println("MAP heap=$(h.size)")
        chars = Char[]
        for b in h.blocks
            push!(chars, used(b) ? 'H' : 'F')
            for k in 0:(div(b.size, 8) - 2)
                push!(chars, used(b) ? (8k < b.requested ? '#' : '-') : '.')
            end
        end
        for first in 1:64:length(chars)
            @printf("%05d %s\n", (first - 1) * 8, join(chars[first:min(first + 63, end)]))
        end
    elseif cmd == "FREELIST"
        free = filter(b -> !used(b), h.blocks)
        h.mode == "SEGFIT" && sort!(free; by=b -> -b.stamp)
        println("FREELIST count=$(length(free))")
        for k in sort(unique(classof(b.size) for b in free))
            println("$(2^k)-$(2^(k + 1) - 1): ", join((area(b) for b in free if classof(b.size) == k), " "))
        end
    elseif cmd == "TREE"
        h.mode == "BUDDY" || fail("REQUIRES BUDDY MODE")
        println("TREE heap=$(h.size)")
        tree(h, 0, h.size, 0)
    elseif cmd == "STATS"
        u = filter(used, h.blocks)
        f = filter(b -> !used(b), h.blocks)
        ft = sum((b.size for b in f); init=0)
        largest = maximum((b.size for b in f); init=0)
        req = sum((b.requested for b in u); init=0)
        println("STATS used=$(usedtotal(h)) used_blocks=$(length(u)) free=$ft free_blocks=$(length(f)) largest=$largest frag=$(frag(h)) requested=$req peak=$(a.peak)")
        names = ("allocs", "frees", "reallocs", "moves", "failures", "collected")
        println("OPS ", join(("$(names[i])=$(a.counts[i])" for i in 1:6), " "))
    elseif cmd == "LEAKS"
        seen = reachable(a)
        ids = sort(collect(keys(a.live)))
        req = sum((a.live[id].requested for id in ids); init=0)
        lost = count(id -> !(id in seen), ids)
        println("LEAKS count=$(length(ids)) requested=$req lost=$lost")
        for id in ids
            b = a.live[id]
            status = id in seen ? "reachable" : "lost"
            println("LEAK $id addr=$(b.start + 8) block=$(b.size) req=$(b.requested) $status")
        end
    elseif cmd == "HISTORY"
        id = v[1]
        lines = get(a.histories, id, String[])
        println("HISTORY $id events=$(length(lines))")
        foreach(println, lines)
    end
end
function main()
    a = Allocator()
    n = parse(Int, readline())
    for _ in 1:n
        words = String.(split(readline()))
        try
            execute!(a, words)
        catch e
            e isa CommandError || rethrow()
            println("ERROR ", e.text)
        end
        a.heap !== nothing && (a.peak = max(a.peak, usedtotal(a.heap)))
    end
end
main()
