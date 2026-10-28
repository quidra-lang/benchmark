mutable struct HeapObject
    number::Int
    size::Int
    fields::Vector{Int}
    address::Int
    marked::Bool
    moves::Int
    age::Int
    count::Int
end
HeapObject(number,p,d) = HeapObject(number,1+p+d,zeros(Int,p),0,false,0,0,0)
mutable struct ObjectPair
    count::Int
    words::Int
end
ObjectPair() = ObjectPair(0,0)
function add_object!(pair,obj)
    pair.count += 1
    pair.words += obj.size
end
Base.show(io::IO,pair::ObjectPair) = print(io,pair.count,' ',pair.words)
pair_of(objects) = ObjectPair(length(objects),sum((o.size for o in objects);init=0))
mutable struct CollectionRecord
    number::Int
    line::Int
    request::Int
    kind::String
    live::ObjectPair
    freed::ObjectPair
    moved::ObjectPair
    promoted::ObjectPair
    stack::Int
    work::Int
    before::Tuple{Int,Int}
    after::Tuple{Int,Int}
end
CollectionRecord(n,line,request,kind,blocks) = CollectionRecord(
    n,
    line,
    request,
    kind,
    ObjectPair(),
    ObjectPair(),
    ObjectPair(),
    ObjectPair(),
    0,
    0,
    (total_free(blocks),largest_free(blocks)),
    (0,0)
)
mutable struct Collector
    kind::String
    size::Int
    young::Int
    promotion_age::Int
    base::Int
    top::Int
    objects::Vector{HeapObject}
    placed::Vector{HeapObject}
    records::Vector{CollectionRecord}
    remembered::Set{Int}
    barriers::Int
    remembers::Int
    increments::Int
    decrements::Int
    released::Vector{HeapObject}
    reports::Vector{Vector{String}}
    deaths::Vector{Int}
end
Collector(entry,size,deaths) = Collector(
    entry.kind,
    size,
    entry.young,
    entry.age,
    0,
    0,
    HeapObject[],
    HeapObject[],
    CollectionRecord[],
    Set{Int}(),
    0,
    0,
    0,
    0,
    HeapObject[],
    Vector{String}[],
    deaths
)
by_address(objects) = sort(collect(objects),by=o->o.address)
function free_blocks(objects,start,stop)
    blocks = Tuple{Int,Int}[]
    position = start
    for obj in by_address(objects)
        start <= obj.address < stop || continue
        obj.address > position && push!(blocks,(position,obj.address-position))
        position = obj.address+obj.size
    end
    position < stop && push!(blocks,(position,stop-position))
    blocks
end
function first_fit(blocks,size)
    for (address,length) in blocks
        length >= size && return address
    end
    nothing
end
total_free(blocks) = sum((n for (_,n) in blocks);init=0)
largest_free(blocks) = maximum((n for (_,n) in blocks);init=0)
is_young(state,obj) = obj.address < state.young
old_blocks(state) = free_blocks(state.objects,state.young,state.size)
function free_list(state)
    state.kind in ("MARK_SWEEP","REFCOUNT") && return free_blocks(state.objects,0,state.size)
    stop = state.kind == "MARK_COMPACT" ? state.size : state.base+(state.kind == "COPYING" ? state.size : state.young)÷2
    blocks = state.top < stop ? [(state.top,stop-state.top)] : Tuple{Int,Int}[]
    state.kind == "GENERATIONAL" ? vcat(blocks,old_blocks(state)) : blocks
end
function inactive_range(state)
    state.kind in ("COPYING","GENERATIONAL") || return (0,0)
    half = (state.kind == "COPYING" ? state.size : state.young)÷2
    first = half-state.base
    first,first+half
end
function finish_record!(state,record)
    blocks = free_list(state)
    record.after = (total_free(blocks),largest_free(blocks))
    push!(state.records,record)
end
function dec2(a,b)
    q = (200a+b)÷(2b)
    "$(q÷100).$(lpad(string(q%100),2,'0'))"
end
pct(a,b) = b == 0 ? "-" : dec2(100a,b)
fragmentation(blocks) = pct(total_free(blocks)-largest_free(blocks),total_free(blocks))
function class_table(values)
    counts = zeros(Int,5)
    for value in values
        index = findfirst(limit->value <= limit,(1,3,7,15))
        counts[isnothing(index) ? 5 : index] += 1
    end
    join(("$label:$(counts[i])" for (i,label) in enumerate(("1","2-3","4-7","8-15","16+"))),' ')
end
function heap_map(size,objects,reachable,inactive)
    cells = fill('.',size)
    first,last = inactive
    cells[(first+1):last] .= '-'
    for obj in objects
        letter = Char(Int('A')+(obj.number-1)%26)
        header,body = obj.number in reachable ? (letter,lowercase(letter)) : ('#','=')
        cells[obj.address+1] = header
        cells[(obj.address+2):(obj.address+obj.size)] .= body
    end
    String(cells)
end
