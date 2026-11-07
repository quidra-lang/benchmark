struct Labeling
    labels::Matrix{Int}
    count::Int
    provisional::Int
end

function find_label!(parents, label)
    while parents[label] != label
        parents[label] = parents[parents[label]]
        label = parents[label]
    end
    label
end

function merge_labels!(parents, first, second)
    a, b = find_label!(parents, first), find_label!(parents, second)
    a != b && (parents[max(a, b)] = min(a, b))
end

function label_components(mask, connectivity)
    height, width = size(mask)
    previous = connectivity == 4 ? [(-1, 0), (0, -1)] : [(-1, 0), (-1, -1), (0, -1), (1, -1)]
    provisional = zeros(Int, height, width)
    parents = Int[]
    for y in 0:height-1, x in 0:width-1
        mask[y + 1, x + 1] || continue
        neighbors = Int[]
        for (dx, dy) in previous
            occupied(mask, x + dx, y + dy) && push!(neighbors, provisional[y + dy + 1, x + dx + 1])
        end
        if isempty(neighbors)
            push!(parents, length(parents) + 1)
            provisional[y + 1, x + 1] = length(parents)
        else
            provisional[y + 1, x + 1] = neighbors[1]
            for other in neighbors[2:end]
                merge_labels!(parents, neighbors[1], other)
            end
        end
    end
    numbers = zeros(Int, length(parents))
    labels = zeros(Int, height, width)
    next_number = 0
    for y in 1:height, x in 1:width
        provisional[y, x] == 0 && continue
        root = find_label!(parents, provisional[y, x])
        if numbers[root] == 0
            next_number += 1
            numbers[root] = next_number
        end
        labels[y, x] = numbers[root]
    end
    Labeling(labels, next_number, length(parents))
end

function bit_quad_euler(mask, connectivity)
    singles = triples = diagonals = 0
    for y in -1:size(mask, 1)-1, x in -1:size(mask, 2)-1
        tl, tr = occupied(mask, x, y), occupied(mask, x + 1, y)
        bl, br = occupied(mask, x, y + 1), occupied(mask, x + 1, y + 1)
        amount = tl + tr + bl + br
        if amount == 1
            singles += 1
        elseif amount == 3
            triples += 1
        elseif amount == 2 && ((tl && br) || (tr && bl))
            diagonals += 1
        end
    end
    div(singles - triples + (connectivity == 8 ? -2 * diagonals : 2 * diagonals), 4)
end
