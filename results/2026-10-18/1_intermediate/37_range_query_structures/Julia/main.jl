@enum Kind SEG LAZY FEN RFEN SPARSE SQRT PERSIST GRID
@enum Operation SUM MIN MAX GCD
const ARRAY_KINDS = (SEG, LAZY, FEN, RFEN, SPARSE, SQRT, PERSIST)
const KINDS = Dict(string(kind) => kind for kind in instances(Kind))
const OPERATIONS = Dict(string(op) => op for op in instances(Operation))

struct CommandError <: Exception
    message::String
end
fail(message::String) = throw(CommandError(message))
numbers(values) = join(values, " ")
lowbit(value::Int) = value & -value
function combine(op::Operation, a::Int, b::Int)
    op == SUM && return a + b
    op == MIN && return min(a, b)
    op == MAX && return max(a, b)
    gcd(a, b)
end
leaf_value(op::Operation, value::Int) = op == GCD ? abs(value) : value

struct Aggregate
    total::Int
    low::Int
    high::Int
end
aggregate(values) = Aggregate(sum(values), minimum(values), maximum(values))
combine(a::Aggregate, b::Aggregate) = Aggregate(a.total + b.total, min(a.low, b.low), max(a.high, b.high))
describe(value::Aggregate) = "sum=$(value.total) min=$(value.low) max=$(value.high)"
struct Answer
    value::Int
    visited::Int
end
struct Report
    text::String
    values::Vector{Int}
end
report(answer::Answer) = Report("sum=$(answer.value) visited=$(answer.visited)", [answer.value])
Base.@kwdef mutable struct Counts
    visited::Int = 0
    covered::Int = 0
    pushes::Int = 0
end
struct Span
    left::Int
    right::Int
end
struct Layout
    n::Int
    lower::Vector{Int}
    upper::Vector{Int}
    nodes::Vector{Int}
end
function Layout(n::Int)
    lower, upper = fill(-1, 4n), zeros(Int, 4n)
    function visit(node::Int, left::Int, right::Int)
        lower[node], upper[node] = left, right
        if left < right
            middle = div(left + right, 2)
            visit(2node, left, middle)
            visit(2node + 1, middle + 1, right)
        end
    end
    visit(1, 0, n - 1)
    Layout(n, lower, upper, findall(x -> x >= 0, lower))
end
covered(shape::Layout, node::Int, left::Int, right::Int) = left <= shape.lower[node] && shape.upper[node] <= right
middle(shape::Layout, node::Int) = div(shape.lower[node] + shape.upper[node], 2)

struct Segment
    shape::Layout
    op::Operation
    values::Vector{Int}
end
function Segment(contents::Vector{Int}, op::Operation)
    tree = Segment(Layout(length(contents)), op, zeros(Int, 4length(contents)))
    function build(node::Int)
        if tree.shape.lower[node] == tree.shape.upper[node]
            tree.values[node] = leaf_value(op, contents[tree.shape.lower[node] + 1])
        else
            build(2node)
            build(2node + 1)
            segment_pull!(tree, node)
        end
    end
    build(1)
    tree
end
segment_pull!(tree::Segment, node::Int) = tree.values[node] = combine(tree.op, tree.values[2node], tree.values[2node + 1])
function segment_query(tree::Segment, node::Int, left::Int, right::Int)
    covered(tree.shape, node, left, right) && return Answer(tree.values[node], 1)
    mid = middle(tree.shape, node)
    if right <= mid
        result = segment_query(tree, 2node, left, right)
    elseif left > mid
        result = segment_query(tree, 2node + 1, left, right)
    else
        a = segment_query(tree, 2node, left, right)
        b = segment_query(tree, 2node + 1, left, right)
        result = Answer(combine(tree.op, a.value, b.value), a.visited + b.visited)
    end
    Answer(result.value, result.visited + 1)
end
function query(tree::Segment, left::Int, right::Int)
    result = segment_query(tree, 1, left, right)
    Report("$(lowercase(string(tree.op)))=$(result.value) visited=$(result.visited)", [result.value])
end
function segment_update!(tree::Segment, node::Int, index::Int, value::Int)
    if tree.shape.lower[node] == tree.shape.upper[node]
        tree.values[node] = leaf_value(tree.op, value)
        return 1
    end
    child = index <= middle(tree.shape, node) ? 2node : 2node + 1
    visited = segment_update!(tree, child, index, value)
    segment_pull!(tree, node)
    visited + 1
end
function dump_structure(tree::Segment)
    rows = ["SEG DUMP $(tree.op) nodes=$(length(tree.shape.nodes))"]
    for node in tree.shape.nodes
        push!(rows, "NODE $node $(tree.shape.lower[node]) $(tree.shape.upper[node]) $(tree.values[node])")
    end
    rows
end

struct LazyTree
    shape::Layout
    values::Vector{Aggregate}
    assignments::Vector{Union{Nothing,Int}}
    additions::Vector{Int}
end
function LazyTree(contents::Vector{Int})
    n = length(contents)
    tree = LazyTree(Layout(n), fill(Aggregate(0, 0, 0), 4n), Union{Nothing,Int}[nothing for _ in 1:4n], zeros(Int, 4n))
    function build(node::Int)
        if tree.shape.lower[node] == tree.shape.upper[node]
            value = contents[tree.shape.lower[node] + 1]
            tree.values[node] = Aggregate(value, value, value)
        else
            build(2node)
            build(2node + 1)
            lazy_pull!(tree, node)
        end
    end
    build(1)
    tree
end
lazy_pull!(tree::LazyTree, node::Int) = tree.values[node] = combine(tree.values[2node], tree.values[2node + 1])
function lazy_apply!(tree::LazyTree, node::Int, value::Int, assign::Bool)
    size = tree.shape.upper[node] - tree.shape.lower[node] + 1
    previous = tree.values[node]
    tree.values[node] = assign ? Aggregate(value * size, value, value) :
        Aggregate(previous.total + value * size, previous.low + value, previous.high + value)
    if size > 1
        if assign
            tree.assignments[node] = value
            tree.additions[node] = 0
        else
            tree.additions[node] += value
        end
    end
end
function lazy_push!(tree::LazyTree, node::Int, counts::Counts)
    assignment, addition = tree.assignments[node], tree.additions[node]
    isnothing(assignment) && addition == 0 && return
    for child in 2node:(2node + 1)
        isnothing(assignment) || lazy_apply!(tree, child, assignment, true)
        addition == 0 || lazy_apply!(tree, child, addition, false)
    end
    tree.assignments[node], tree.additions[node] = nothing, 0
    counts.pushes += 1
end
function lazy_update!(tree::LazyTree, node::Int, left::Int, right::Int, value::Int, assign::Bool, counts::Counts)
    counts.visited += 1
    if covered(tree.shape, node, left, right)
        counts.covered += 1
        lazy_apply!(tree, node, value, assign)
        return
    end
    lazy_push!(tree, node, counts)
    mid = middle(tree.shape, node)
    left <= mid && lazy_update!(tree, 2node, left, right, value, assign, counts)
    right > mid && lazy_update!(tree, 2node + 1, left, right, value, assign, counts)
    lazy_pull!(tree, node)
end
function lazy_query!(tree::LazyTree, node::Int, left::Int, right::Int, counts::Counts)
    counts.visited += 1
    covered(tree.shape, node, left, right) && return tree.values[node]
    lazy_push!(tree, node, counts)
    mid = middle(tree.shape, node)
    right <= mid && return lazy_query!(tree, 2node, left, right, counts)
    left > mid && return lazy_query!(tree, 2node + 1, left, right, counts)
    a = lazy_query!(tree, 2node, left, right, counts)
    b = lazy_query!(tree, 2node + 1, left, right, counts)
    combine(a, b)
end
function query(tree::LazyTree, left::Int, right::Int)
    counts = Counts()
    value = lazy_query!(tree, 1, left, right, counts)
    Report("$(describe(value)) visited=$(counts.visited) pushes=$(counts.pushes)", [value.total, value.low, value.high])
end
function dump_structure(tree::LazyTree)
    rows = ["LAZY DUMP nodes=$(length(tree.shape.nodes))"]
    for node in tree.shape.nodes
        assignment = isnothing(tree.assignments[node]) ? "-" : string(tree.assignments[node])
        push!(rows, "NODE $node $(tree.shape.lower[node]) $(tree.shape.upper[node]) $(describe(tree.values[node])) assign=$assignment add=$(tree.additions[node])")
    end
    rows
end

struct Fenwick
    values::Vector{Int}
    tree::Vector{Int}
end
function bit_add!(tree::Vector{Int}, position::Int, value::Int)
    visited = 0
    while position <= length(tree)
        tree[position] += value
        visited += 1
        position += lowbit(position)
    end
    visited
end
function build_bit(values::Vector{Int})
    tree = zeros(Int, length(values))
    for index in eachindex(values)
        bit_add!(tree, index, values[index])
    end
    tree
end
Fenwick(values::Vector{Int}) = Fenwick(copy(values), build_bit(values))
function bit_prefix(tree::Vector{Int}, position::Int)
    value, visited = 0, 0
    while position > 0
        value += tree[position]
        visited += 1
        position -= lowbit(position)
    end
    Answer(value, visited)
end
function query(tree::Fenwick, left::Int, right::Int)
    a = bit_prefix(tree.tree, right + 1)
    b = bit_prefix(tree.tree, left)
    report(Answer(a.value - b.value, a.visited + b.visited))
end
function bit_lower(tree::Vector{Int}, rest::Int)
    n = length(tree)
    step, position, visited = 1, 0, 0
    while 2step <= n
        step *= 2
    end
    while step > 0
        if position + step <= n
            value = tree[position + step]
            visited += 1
            if value < rest
                rest -= value
                position += step
            end
        end
        step = div(step, 2)
    end
    Answer(position < n ? position : -1, visited)
end
dump_structure(tree::Fenwick) = ["FEN DUMP n=$(length(tree.tree))", "T $(numbers(tree.tree))"]
struct RangeFenwick
    first::Vector{Int}
    second::Vector{Int}
end
function RangeFenwick(values::Vector{Int})
    differences = values - vcat(0, values[1:end-1])
    RangeFenwick(build_bit(differences), build_bit(collect(0:(length(values) - 1)) .* differences))
end
function range_add!(tree::RangeFenwick, left::Int, right::Int, value::Int)
    visited = bit_add!(tree.first, left + 1, value)
    visited += bit_add!(tree.first, right + 2, -value)
    visited += bit_add!(tree.second, left + 1, value * left)
    visited += bit_add!(tree.second, right + 2, -value * (right + 1))
    visited
end
function range_prefix(tree::RangeFenwick, position::Int)
    a = bit_prefix(tree.first, position)
    b = bit_prefix(tree.second, position)
    Answer(position * a.value - b.value, a.visited + b.visited)
end
function query(tree::RangeFenwick, left::Int, right::Int)
    a = range_prefix(tree, right + 1)
    b = range_prefix(tree, left)
    report(Answer(a.value - b.value, a.visited + b.visited))
end
dump_structure(tree::RangeFenwick) = ["RFEN DUMP n=$(length(tree.first))", "B1 $(numbers(tree.first))", "B2 $(numbers(tree.second))"]

struct SparseTable
    values::Vector{Int}
    minima::Vector{Vector{Int}}
    maxima::Vector{Vector{Int}}
end
function SparseTable(values::Vector{Int})
    tree = SparseTable(copy(values), [collect(0:(length(values) - 1))], [collect(0:(length(values) - 1))])
    width = 2
    while width <= length(values)
        previous_min, previous_max = tree.minima[end], tree.maxima[end]
        low, high = Int[], Int[]
        for index in 1:(length(values) - width + 1)
            a, b = previous_min[index], previous_min[index + div(width, 2)]
            push!(low, values[a + 1] <= values[b + 1] ? a : b)
            a, b = previous_max[index], previous_max[index + div(width, 2)]
            push!(high, values[a + 1] >= values[b + 1] ? a : b)
        end
        push!(tree.minima, low)
        push!(tree.maxima, high)
        width *= 2
    end
    tree
end
function query(tree::SparseTable, left::Int, right::Int)
    level, width = 0, 1
    while 2width <= right - left + 1
        level += 1
        width *= 2
    end
    ending = right - width + 1
    a, b = tree.minima[level + 1][left + 1], tree.minima[level + 1][ending + 1]
    low = tree.values[a + 1] <= tree.values[b + 1] ? a : b
    a, b = tree.maxima[level + 1][left + 1], tree.maxima[level + 1][ending + 1]
    high = tree.values[a + 1] >= tree.values[b + 1] ? a : b
    Report("min=$(tree.values[low + 1]) minpos=$low max=$(tree.values[high + 1]) maxpos=$high level=$level", [tree.values[low + 1], tree.values[high + 1]])
end
function dump_structure(tree::SparseTable)
    rows = ["SPARSE DUMP levels=$(length(tree.minima))"]
    for level in eachindex(tree.minima)
        push!(rows, "MIN $(level - 1) $(numbers(tree.minima[level]))", "MAX $(level - 1) $(numbers(tree.maxima[level]))")
    end
    rows
end

struct SqrtBlocks
    block::Int
    raw::Vector{Int}
    tags::Vector{Int}
    sums::Vector{Int}
end
function SqrtBlocks(values::Vector{Int}, block::Int)
    sums = [sum(@view(values[first:min(first + block - 1, end)])) for first in 1:block:length(values)]
    SqrtBlocks(block, copy(values), zeros(Int, length(sums)), sums)
end
struct Partition
    cells::Vector{Int}
    blocks::UnitRange{Int}
end
describe(part::Partition) = "whole=$(length(part.blocks)) cells=$(length(part.cells))"
function partition(tree::SqrtBlocks, left::Int, right::Int)
    first, last = div(left, tree.block), div(right, tree.block)
    first == last && return Partition(collect(left:right), 1:0)
    cells = vcat(collect(left:((first + 1) * tree.block - 1)), collect((last * tree.block):right))
    Partition(cells, (first + 1):(last - 1))
end
function blocks_add!(tree::SqrtBlocks, left::Int, right::Int, value::Int)
    part = partition(tree, left, right)
    for index in part.cells
        tree.raw[index + 1] += value
        tree.sums[div(index, tree.block) + 1] += value
    end
    for block in part.blocks
        tree.tags[block + 1] += value
        tree.sums[block + 1] += value * tree.block
    end
    part
end
function query(tree::SqrtBlocks, left::Int, right::Int)
    part = partition(tree, left, right)
    value = sum((tree.raw[index + 1] + tree.tags[div(index, tree.block) + 1] for index in part.cells); init = 0)
    value += sum((tree.sums[block + 1] for block in part.blocks); init = 0)
    Report("sum=$value $(describe(part))", [value])
end
function dump_structure(tree::SqrtBlocks)
    rows = ["SQRT DUMP block=$(tree.block) blocks=$(length(tree.tags))"]
    for block in eachindex(tree.tags)
        first, ending = (block - 1) * tree.block, min(block * tree.block, length(tree.raw))
        push!(rows, "BLOCK $(block - 1) $first $(ending - 1) add=$(tree.tags[block]) sum=$(tree.sums[block]) $(numbers(@view(tree.raw[(first + 1):ending])))")
    end
    rows
end

struct Node
    total::Int
    left::Int
    right::Int
end
function append_node!(pool::Vector{Node}, value::Int, left::Int = 0, right::Int = 0)
    push!(pool, Node(value, left, right))
    length(pool)
end
function build_nodes!(pool::Vector{Node}, values::Vector{Int}, left::Int, right::Int)
    left == right && return append_node!(pool, values[left + 1])
    mid = div(left + right, 2)
    a = build_nodes!(pool, values, left, mid)
    b = build_nodes!(pool, values, mid + 1, right)
    append_node!(pool, pool[a].total + pool[b].total, a, b)
end
function change_nodes!(pool::Vector{Node}, source::Int, left::Int, right::Int, index::Int, value::Int, increment::Bool)
    node = pool[source]
    left == right && return append_node!(pool, increment ? node.total + value : value)
    mid = div(left + right, 2)
    a, b = node.left, node.right
    if index <= mid
        a = change_nodes!(pool, a, left, mid, index, value, increment)
    else
        b = change_nodes!(pool, b, mid + 1, right, index, value, increment)
    end
    append_node!(pool, pool[a].total + pool[b].total, a, b)
end
function query_nodes(pool::Vector{Node}, root::Int, nl::Int, nr::Int, left::Int, right::Int)
    node = pool[root]
    left <= nl && nr <= right && return Answer(node.total, 1)
    mid = div(nl + nr, 2)
    if right <= mid
        answer = query_nodes(pool, node.left, nl, mid, left, right)
    elseif left > mid
        answer = query_nodes(pool, node.right, mid + 1, nr, left, right)
    else
        a = query_nodes(pool, node.left, nl, mid, left, right)
        b = query_nodes(pool, node.right, mid + 1, nr, left, right)
        answer = Answer(a.value + b.value, a.visited + b.visited)
    end
    Answer(answer.value, answer.visited + 1)
end
struct Persistent
    n::Int
    position::Vector{Node}
    value::Vector{Node}
    roots::Vector{Int}
    prefixes::Vector{Int}
    domain::Vector{Int}
end
function Persistent(values::Vector{Int})
    domain = sort(unique(values))
    tree = Persistent(length(values), Node[], Node[], Int[], Int[], domain)
    push!(tree.roots, build_nodes!(tree.position, values, 0, tree.n - 1))
    push!(tree.prefixes, build_nodes!(tree.value, zeros(Int, length(domain)), 0, length(domain) - 1))
    for value in values
        rank = searchsortedfirst(domain, value) - 1
        root = change_nodes!(tree.value, tree.prefixes[end], 0, length(domain) - 1, rank, 1, true)
        push!(tree.prefixes, root)
    end
    tree
end
query(tree::Persistent, left::Int, right::Int, version::Int) =
    report(query_nodes(tree.position, tree.roots[version + 1], 0, tree.n - 1, left, right))
function persistent_set!(tree::Persistent, version::Int, index::Int, value::Int)
    before, new_version = length(tree.position), length(tree.roots)
    root = change_nodes!(tree.position, tree.roots[version + 1], 0, tree.n - 1, index, value, false)
    push!(tree.roots, root)
    new_version, length(tree.position) - before
end
function kth(tree::Persistent, left::Int, right::Int, k::Int)
    upper, lower = tree.prefixes[right + 2], tree.prefixes[left + 1]
    first, last, visited = 0, length(tree.domain) - 1, 1
    while first < last
        mid = div(first + last, 2)
        a, b = tree.value[upper].left, tree.value[lower].left
        count = tree.value[a].total - tree.value[b].total
        if k <= count
            upper, lower, last = a, b, mid
        else
            k -= count
            upper, lower, first = tree.value[upper].right, tree.value[lower].right, mid + 1
        end
        visited += 1
    end
    Answer(tree.domain[first + 1], visited)
end

struct GridTree
    height::Int
    width::Int
    values::Matrix{Int}
end
function grid_add!(grid::GridTree, row::Int, column::Int, value::Int)
    y, visited = row + 1, 0
    while y <= grid.height
        x = column + 1
        while x <= grid.width
            grid.values[y, x] += value
            visited += 1
            x += lowbit(x)
        end
        y += lowbit(y)
    end
    visited
end
function GridTree(height::Int, width::Int, values::Vector{Int})
    grid = GridTree(height, width, zeros(Int, height, width))
    for index in eachindex(values)
        grid_add!(grid, div(index - 1, width), mod(index - 1, width), values[index])
    end
    grid
end
function grid_prefix(grid::GridTree, row::Int, column::Int)
    value, visited = 0, 0
    while row > 0
        x = column
        while x > 0
            value += grid.values[row, x]
            visited += 1
            x -= lowbit(x)
        end
        row -= lowbit(row)
    end
    Answer(value, visited)
end
function grid_query(grid::GridTree, row::Int, column::Int, bottom::Int, right::Int)
    a = grid_prefix(grid, bottom + 1, right + 1)
    b = grid_prefix(grid, row, right + 1)
    c = grid_prefix(grid, bottom + 1, column)
    d = grid_prefix(grid, row, column)
    Answer(a.value - b.value - c.value + d.value, a.visited + b.visited + c.visited + d.visited)
end
function dump_structure(grid::GridTree)
    rows = ["GRID DUMP rows=$(grid.height) cols=$(grid.width)"]
    for row in 1:grid.height
        push!(rows, "ROW $row $(numbers(@view(grid.values[row, :])))")
    end
    rows
end

mutable struct Laboratory
    values::Vector{Int}
    original::Vector{Int}
    segment::Union{Nothing,Segment}
    lazy::Union{Nothing,LazyTree}
    fenwick::Union{Nothing,Fenwick}
    range_fenwick::Union{Nothing,RangeFenwick}
    sparse::Union{Nothing,SparseTable}
    blocks::Union{Nothing,SqrtBlocks}
    persistent::Union{Nothing,Persistent}
    grid::Union{Nothing,GridTree}
end
Laboratory(values::Vector{Int}) = Laboratory(copy(values), copy(values), nothing, nothing, nothing, nothing, nothing, nothing, nothing, nothing)
function structure(lab::Laboratory, kind::Kind)
    kind == SEG && return lab.segment
    kind == LAZY && return lab.lazy
    kind == FEN && return lab.fenwick
    kind == RFEN && return lab.range_fenwick
    kind == SPARSE && return lab.sparse
    kind == SQRT && return lab.blocks
    kind == PERSIST && return lab.persistent
    lab.grid
end
has_structure(lab::Laboratory, kind::Kind) = !isnothing(structure(lab, kind))
function check_index(n::Int, index::Int)
    0 <= index < n || fail("BAD INDEX $index")
end
function check_range(n::Int, left::Int, right::Int)
    check_index(n, left)
    check_index(n, right)
    left <= right || fail("BAD RANGE $left $right")
end
function check_version(tree::Persistent, version::Int)
    0 <= version < length(tree.roots) || fail("BAD VERSION $version")
end
function check_cell(tree::GridTree, row::Int, column::Int)
    0 <= row < tree.height && 0 <= column < tree.width || fail("BAD CELL $row $column")
end
function build_array!(lab::Laboratory, kind::Kind; op::Operation = SUM, block::Int = isqrt(length(lab.values)))
    values, n = lab.values, length(lab.values)
    if kind == SEG
        tree = Segment(values, op)
        lab.segment = tree
        return "SEG BUILD $op nodes=$(length(tree.shape.nodes)) maxnode=$(last(tree.shape.nodes)) root=$(tree.values[1])"
    elseif kind == LAZY
        tree = LazyTree(values)
        lab.lazy = tree
        return "LAZY BUILD nodes=$(length(tree.shape.nodes)) $(describe(tree.values[1]))"
    elseif kind == FEN
        lab.fenwick = Fenwick(values)
        return "FEN BUILD n=$n total=$(sum(values))"
    elseif kind == RFEN
        lab.range_fenwick = RangeFenwick(values)
        return "RFEN BUILD n=$n total=$(sum(values))"
    elseif kind == SPARSE
        tree = SparseTable(values)
        lab.sparse = tree
        return "SPARSE BUILD levels=$(length(tree.minima)) entries=$(sum(length, tree.minima))"
    elseif kind == SQRT
        tree = SqrtBlocks(values, block)
        lab.blocks = tree
        return "SQRT BUILD block=$block blocks=$(length(tree.tags))"
    end
    tree = Persistent(values)
    lab.persistent = tree
    "PERSIST BUILD nodes=$(length(tree.position)) distinct=$(length(tree.domain)) valuenodes=$(length(tree.value))"
end
function query_array(lab::Laboratory, kind::Kind, left::Int, right::Int; version::Int = 0)
    tree = structure(lab, kind)
    kind == PERSIST ? query(tree, left, right, version) : query(tree, left, right)
end
function check_all!(lab::Laboratory, left::Int, right::Int)
    values = @view lab.values[(left + 1):(right + 1)]
    direct = aggregate(values)
    common = foldl(gcd, values; init = 0)
    rows = ["CHECK $left $right $(describe(direct)) gcd=$common"]
    ok, different = 0, 0
    for kind in ARRAY_KINDS
        tree = structure(lab, kind)
        isnothing(tree) && continue
        expected = if kind == SEG
            [(direct.total, direct.low, direct.high, common)[Int(tree.op) + 1]]
        elseif kind == LAZY
            [direct.total, direct.low, direct.high]
        elseif kind == SPARSE
            [direct.low, direct.high]
        else
            [direct.total]
        end
        version = kind == PERSIST ? length(tree.roots) - 1 : 0
        result = query_array(lab, kind, left, right; version)
        same = result.values == expected
        if same
            ok += 1
        else
            different += 1
        end
        prefix = kind == PERSIST ? "version=$version " : ""
        push!(rows, "$kind $(same ? "OK" : "DIFF") $prefix$(result.text)")
    end
    push!(rows, "RESULT ok=$ok diff=$different")
    rows
end
function mo(values::Vector{Int}, queries::Vector{Span})
    block = isqrt(length(values))
    order = sort(collect(eachindex(queries)); by = index -> begin
        query = queries[index]
        group = div(query.left, block)
        (group, iseven(group) ? query.right : -query.right, index)
    end)
    ranks_by_value = Dict(value => index for (index, value) in enumerate(unique(values)))
    ranks = [ranks_by_value[value] for value in values]
    frequencies = zeros(Int, length(ranks_by_value))
    answers = zeros(Int, length(queries))
    left, right, moves = 0, -1, 0
    for index in order
        target = queries[index]
        moves += abs(target.left - left) + abs(target.right - right)
        while left > target.left
            left -= 1
            frequencies[ranks[left + 1]] += 1
        end
        while right < target.right
            right += 1
            frequencies[ranks[right + 1]] += 1
        end
        while left < target.left
            frequencies[ranks[left + 1]] -= 1
            left += 1
        end
        while right > target.right
            frequencies[ranks[right + 1]] -= 1
            right -= 1
        end
        answers[index] = count(value -> value > 0, frequencies)
    end
    rows = ["MO queries=$(length(queries)) block=$block moves=$moves", "ORDER $(numbers(order))"]
    for (index, query) in enumerate(queries)
        push!(rows, "ANSWER $index $(query.left) $(query.right) distinct=$(answers[index])")
    end
    rows
end

function execute!(lab::Laboratory, line::String)
    words = String.(split(line, ' '))
    command, n = words[1], length(lab.values)
    if command == "LOAD"
        removed = count(kind -> has_structure(lab, kind), ARRAY_KINDS)
        values = parse.(Int, words[2:end])
        lab.values, lab.original = values, copy(values)
        lab.segment = lab.lazy = lab.fenwick = lab.range_fenwick = nothing
        lab.sparse = lab.blocks = lab.persistent = nothing
        return ["LOAD n=$(length(values)) removed=$removed"]
    elseif command == "RESET"
        lab.values = copy(lab.original)
        op = isnothing(lab.segment) ? SUM : lab.segment.op
        block = isnothing(lab.blocks) ? 1 : lab.blocks.block
        rebuilt = 0
        for kind in ARRAY_KINDS
            if has_structure(lab, kind)
                build_array!(lab, kind; op, block)
                rebuilt += 1
            end
        end
        return ["RESET rebuilt=$rebuilt"]
    elseif command in ("ARRAY", "CHECK")
        left, right = parse.(Int, words[2:end])
        check_range(n, left, right)
        command == "CHECK" && return check_all!(lab, left, right)
        return ["$line $(numbers(@view(lab.values[(left + 1):(right + 1)])))"]
    elseif command == "MO"
        args = parse.(Int, words[2:end])
        queries = Span[]
        for index in 1:2:length(args)
            left, right = args[index], args[index + 1]
            check_range(n, left, right)
            push!(queries, Span(left, right))
        end
        return mo(lab.values, queries)
    end
    kind, action = KINDS[command], words[2]
    if action == "BUILD"
        op, block = SUM, isqrt(n)
        if kind == SEG
            haskey(OPERATIONS, words[3]) || fail("BAD OP $(words[3])")
            op = OPERATIONS[words[3]]
        elseif kind == SQRT
            block = length(words) == 3 ? parse(Int, words[3]) : block
            block <= n || fail("BAD BLOCK $block")
        elseif kind == GRID
            height, width = parse.(Int, words[3:4])
            actual = length(words) - 4
            actual == height * width || fail("BAD COUNT $actual $(height * width)")
            values = parse.(Int, words[5:end])
            lab.grid = GridTree(height, width, values)
            return ["GRID BUILD rows=$height cols=$width total=$(sum(values))"]
        end
        return [build_array!(lab, kind; op, block)]
    end
    tree = structure(lab, kind)
    isnothing(tree) && fail("NOT BUILT $kind")
    action == "DUMP" && return dump_structure(tree)
    args = parse.(Int, words[3:end])
    if kind == GRID
        row, column = args[1:2]
        check_cell(tree, row, column)
        if action == "ADD"
            visited = grid_add!(tree, row, column, args[3])
            return ["$line visited=$visited"]
        end
        bottom, right = args[3:4]
        check_cell(tree, bottom, right)
        row <= bottom && column <= right || fail("BAD RECT $row $column $bottom $right")
        result = grid_query(tree, row, column, bottom, right)
        return ["$line $(report(result).text)"]
    elseif kind == PERSIST
        action == "NODES" && return ["PERSIST NODES versions=$(length(tree.roots)) position=$(length(tree.position)) value=$(length(tree.value))"]
        if action == "KTH"
            left, right, k = args
            check_range(n, left, right)
            1 <= k <= right - left + 1 || fail("BAD K $k")
            result = kth(tree, left, right, k)
            return ["$line value=$(result.value) visited=$(result.visited)"]
        end
        version = args[1]
        check_version(tree, version)
        if action == "SET"
            check_index(n, args[2])
            new_version, created = persistent_set!(tree, version, args[2], args[3])
            return ["$line version=$new_version created=$created"]
        end
        left, right = args[2:3]
        check_range(n, left, right)
        return ["$line $(query(tree, left, right, version).text)"]
    elseif kind == FEN && action == "LOWER"
        negative = findfirst(value -> value < 0, tree.values)
        isnothing(negative) || fail("NEGATIVE $(negative - 1)")
        result = bit_lower(tree.tree, args[1])
        index = result.value < 0 ? "none" : string(result.value)
        return ["$line index=$index visited=$(result.visited)"]
    elseif kind == SEG && action == "UPDATE"
        index, value = args
        check_index(n, index)
        visited = segment_update!(tree, 1, index, value)
        lab.values[index + 1] = value
        return ["$line root=$(tree.values[1]) visited=$visited"]
    elseif kind == FEN && action in ("ADD", "PREFIX")
        index = args[1]
        check_index(n, index)
        if action == "ADD"
            value = args[2]
            visited = bit_add!(tree.tree, index + 1, value)
            tree.values[index + 1] += value
            lab.values[index + 1] += value
            return ["$line visited=$visited"]
        end
        return ["$line $(report(bit_prefix(tree.tree, index + 1)).text)"]
    end
    left, right = args[1:2]
    check_range(n, left, right)
    if action in ("ADD", "ASSIGN")
        value, assign = args[3], action == "ASSIGN"
        details = if kind == LAZY
            counts = Counts()
            lazy_update!(tree, 1, left, right, value, assign, counts)
            "visited=$(counts.visited) covered=$(counts.covered) pushes=$(counts.pushes)"
        elseif kind == RFEN
            "visited=$(range_add!(tree, left, right, value))"
        else
            describe(blocks_add!(tree, left, right, value))
        end
        selected = @view lab.values[(left + 1):(right + 1)]
        if assign
            selected .= value
        else
            selected .+= value
        end
        return ["$line $details"]
    end
    ["$line $(query(tree, left, right).text)"]
end

function main()
    eof(stdin) && return
    parse(Int, readline())
    lab = Laboratory(parse.(Int, split(readline(), ' ')))
    command_count = parse(Int, readline())
    for _ in 1:command_count
        line = readline()
        rows = try
            execute!(lab, line)
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
