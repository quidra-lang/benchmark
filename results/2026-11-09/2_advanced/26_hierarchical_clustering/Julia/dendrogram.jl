function ordered_children(merges, n)
    minimums = collect(1:n)
    children = Tuple{Int,Int}[]
    for merge in merges
        push!(children, minimums[merge.a] < minimums[merge.b] ? (merge.a, merge.b) : (merge.b, merge.a))
        push!(minimums, min(minimums[merge.a], minimums[merge.b]))
    end
    children
end

function leaf_order(children, n)
    order = Int[]
    pending = [n + length(children)]
    while !isempty(pending)
        node = pop!(pending)
        if node <= n
            push!(order, node)
        else
            upper, lower = children[node - n]
            push!(pending, lower, upper)
        end
    end
    order
end

function column(height, maximum_height, width)
    position = floor(height / maximum_height * width)
    position > width ? width + 1 : Int(position)
end

function dendrogram_rows(merges, children, order, ids, labels, maximum_height, cuts, width)
    n = length(order)
    grid = zeros(Int, n, width + 1)
    anchors = zeros(Int, 2 * n - 1)
    for (row, leaf) in enumerate(order)
        anchors[leaf] = row
    end
    for x in cuts
        if x <= width
            for row in 1:n
                grid[row, x + 1] = max(grid[row, x + 1], 1)
            end
        end
    end
    columns = [column(merge.height, maximum_height, width) for merge in merges]
    for (step, (upper, lower)) in enumerate(children)
        x = columns[step]
        grid[anchors[upper], x + 1] = 4
        grid[anchors[lower], x + 1] = 4
        for row in (anchors[upper] + 1):(anchors[lower] - 1)
            grid[row, x + 1] = max(grid[row, x + 1], 3)
        end
        for child in (upper, lower)
            start = child <= n ? 0 : columns[child - n] + 1
            for position in start:(x - 1)
                grid[anchors[child], position + 1] = max(grid[anchors[child], position + 1], 2)
            end
        end
        anchors[n + step] = (anchors[upper] + anchors[lower]) ÷ 2
    end
    id_width, label_width = maximum(length.(ids)), maximum(length.(labels))
    marks = collect(" :-|+")
    rows = String[]
    for (row, leaf) in enumerate(order)
        cells = join(marks[grid[row, x + 1] + 1] for x in 0:width)
        push!(rows, rstrip(rpad(ids[leaf], id_width) * " " * rpad(labels[leaf], label_width) * " " * cells))
    end
    scale = join(x % 10 == 0 ? '+' : '-' for x in 0:width)
    push!(rows, repeat(" ", id_width + label_width + 2) * scale)
    rows
end
