using Printf

include("dataset.jl")
include("distances.jl")
include("agglomerative.jl")
include("dendrogram.jl")
include("validation.jl")

function format_real(value)
    text = @sprintf("%.4f", value)
    text == "-0.0000" ? "0.0000" : text
end
format_optional(value) = isnothing(value) ? "-" : format_real(value)
format_reals(values) = join((format_real(value) for value in values), " ")
format_integers(values) = join(values, " ")
four_digit(value) = parse(Float64, format_real(value))
ari_text(value) = "$(numerator(value))/$(denominator(value)) $(format_real(Float64(value)))"
ari_greater(first, second) = numerator(first) * denominator(second) > numerator(second) * denominator(first)
pair_values(matrix) = [matrix[i, j] for i in axes(matrix, 1) for j in (i + 1):size(matrix, 1)]
histogram_bin(value, maximum_distance) = min(9, floor(Int, 10.0 * value / maximum_distance))

function centroid(vectors)
    [sequential_sum(vector[f] for vector in vectors) / length(vectors) for f in eachindex(vectors[1])]
end

function cluster_members(partition, groups)
    members = [Int[] for _ in 1:groups]
    for (i, number) in enumerate(partition)
        push!(members[number], i)
    end
    members
end

function majority_class(row)
    best = 1
    for t in 2:length(row)
        row[t] > row[best] && (best = t)
    end
    best
end

function join_parts(parts)
    lines = String[]
    for part in parts
        !isempty(lines) && push!(lines, "")
        append!(lines, part)
    end
    lines
end

function partition_ari(first, second)
    adjusted_rand_index(contingency_table(first, second, maximum(first), maximum(second)))
end

mutable struct Minstd
    state::Int
end
function draw!(generator::Minstd)
    generator.state = 48271 * generator.state % 2147483647
    generator.state
end

struct ClusterTree
    merges::Vector{ClusteringMerge}
    n::Int
    children::Vector{Tuple{Int,Int}}
    order::Vector{Int}
    members::Vector{Vector{Int}}
    depths::Vector{Int}
    subtree_heights::Vector{Float64}
end

function ClusterTree(merges, n)
    children = ordered_children(merges, n)
    order = leaf_order(children, n)
    members = [[u] for u in 1:n]
    depths = zeros(Int, n)
    maxima = zeros(n)
    subtree_heights = Float64[]
    for merge in merges
        push!(members, vcat(members[merge.a], members[merge.b]))
        push!(depths, 1 + max(depths[merge.a], depths[merge.b]))
        value = max(merge.height, maxima[merge.a], maxima[merge.b])
        push!(maxima, value)
        push!(subtree_heights, value)
    end
    ClusterTree(merges, n, children, order, members, depths, subtree_heights)
end

root_node(tree) = 2 * tree.n - 1
node_height(tree, node) = node <= tree.n ? 0.0 : tree.merges[node - tree.n].height
tree_heights(tree) = [merge.height for merge in tree.merges]

function tree_partition(tree, selected)
    owner = collect(1:tree.n)
    for (step, chosen) in enumerate(selected)
        if chosen
            for u in tree.members[tree.n + step]
                owner[u] = tree.n + step
            end
        end
    end
    numbers = zeros(Int, 2 * tree.n - 1)
    groups = 0
    for u in tree.order
        if numbers[owner[u]] == 0
            groups += 1
            numbers[owner[u]] = groups
        end
    end
    [numbers[owner[u]] for u in 1:tree.n]
end

cut_at_height(tree, height) = tree_partition(tree, [value <= height for value in tree.subtree_heights])
cut_into(tree, k) = tree_partition(tree, [step <= tree.n - k for step in 1:length(tree.merges)])

function cophenetic_matrix(tree)
    matrix = zeros(tree.n, tree.n)
    for merge in tree.merges
        for i in tree.members[merge.a], j in tree.members[merge.b]
            matrix[i, j] = merge.height
            matrix[j, i] = merge.height
        end
    end
    matrix
end

function joining_heights(tree)
    heights = zeros(tree.n)
    for merge in tree.merges, child in (merge.a, merge.b)
        child <= tree.n && (heights[child] = merge.height)
    end
    heights
end

function height_sequence(tree, step, depth)
    depth == 0 && return Float64[]
    merge = tree.merges[step]
    values = [merge.height]
    for child in (merge.a, merge.b)
        child > tree.n && append!(values, height_sequence(tree, child - tree.n, depth - 1))
    end
    values
end

function newick(tree, node, ids)
    node <= tree.n && return ids[node]
    upper, lower = tree.children[node - tree.n]
    height = node_height(tree, node)
    "($(newick(tree, upper, ids)):$(format_real(height - node_height(tree, upper))),$(newick(tree, lower, ids)):$(format_real(height - node_height(tree, lower))))"
end

struct Evaluation
    partition::Vector{Int}
    sizes::Vector{Int}
    silhouette::Union{Nothing,Float64}
    dunn::Union{Nothing,Float64}
    wss::Float64
    ch::Union{Nothing,Float64}
    ari::Rational{Int}
end
function evaluation_text(value)
    "sizes $(format_integers(value.sizes)) silhouette $(format_optional(value.silhouette)) dunn $(format_optional(value.dunn)) wss $(format_real(value.wss)) ch $(format_optional(value.ch)) ari $(ari_text(value.ari))"
end

struct LinkageResult
    method::Symbol
    tree::ClusterTree
    cophenetic::Vector{Float64}
    correlation::Float64
    height_cuts::Vector{Evaluation}
    count_cuts::Vector{Evaluation}
    label_partition::Vector{Int}
end

mutable struct Study
    features::Vector{String}
    settings::Settings
    n::Int
    ids::Vector{String}
    labels::Vector{String}
    classes::Vector{String}
    targets::Vector{Int}
    raw::Vector{Vector{Float64}}
    means::Vector{Float64}
    deviations::Vector{Float64}
    vectors::Vector{Vector{Float64}}
    delta::Matrix{Float64}
    distance_pairs::Vector{Float64}
    distance_max::Float64
    neighbors::Vector{Int}
    results::Vector{LinkageResult}
    chosen_index::Int
    position::Int
end

function build_study(features, observations, settings)
    n = length(observations)
    ids = [row.id for row in observations]
    labels = [row.label for row in observations]
    classes = sort(unique(labels))
    targets = [searchsortedfirst(classes, label) for label in labels]
    raw = [row.values for row in observations]
    means, deviations = feature_statistics(raw)
    vectors = settings.standardize ? standardize(raw, means, deviations) : raw
    delta = distance_matrix(vectors, settings.distance)
    distance_pairs = pair_values(delta)
    neighbors = Int[]
    for i in 1:n
        best = i == 1 ? 2 : 1
        for j in 1:n
            j != i && delta[i, j] < delta[i, best] && (best = j)
        end
        push!(neighbors, best)
    end
    study = Study(features, settings, n, ids, labels, classes, targets, raw, means, deviations, vectors,
        delta, distance_pairs, maximum(distance_pairs), neighbors, LinkageResult[], 1, 1)
    study.results = [analyse_linkage(study, method) for method in settings.linkages]
    for r in eachindex(study.results), k in eachindex(settings.cut_counts)
        if ari_greater(study.results[r].count_cuts[k].ari, study.results[study.chosen_index].count_cuts[study.position].ari)
            study.chosen_index = r
            study.position = k
        end
    end
    study
end

chosen_result(study) = study.results[study.chosen_index]
selected_cut(study) = chosen_result(study).count_cuts[study.position]
selected_partition(study) = selected_cut(study).partition
kappa(study) = study.settings.cut_counts[study.position]
selected_members(study) = cluster_members(selected_partition(study), kappa(study))
class_table(study, partition) = contingency_table(partition, study.targets, maximum(partition), length(study.classes))
label_ari(study, partition) = adjusted_rand_index(class_table(study, partition))
match_count(study, partition) = sum(maximum(row) for row in eachrow(class_table(study, partition)))

function mean_silhouette(partition, delta)
    groups = maximum(partition)
    groups < 2 ? nothing : sequential_sum(silhouette_values(partition, groups, delta)) / length(partition)
end

function centroids(study, partition)
    [centroid([study.vectors[i] for i in group]) for group in cluster_members(partition, maximum(partition))]
end

function within_sum(study, partition)
    centers = centroids(study, partition)
    sequential_sum(squared_distance(study.vectors[i], centers[number]) for (i, number) in enumerate(partition))
end

function evaluate_partition(study, partition)
    groups = maximum(partition)
    members = cluster_members(partition, groups)
    sizes = length.(members)
    wss = within_sum(study, partition)
    diameter, separation = 0.0, Inf
    for i in 1:study.n, j in (i + 1):study.n
        if partition[i] == partition[j]
            diameter = max(diameter, study.delta[i, j])
        else
            separation = min(separation, study.delta[i, j])
        end
    end
    dunn = groups >= 2 && diameter > 0 ? separation / diameter : nothing
    ch = nothing
    if 2 <= groups < study.n
        overall = centroid(study.vectors)
        centers = centroids(study, partition)
        bss = sequential_sum(size * squared_distance(center, overall) for (size, center) in zip(sizes, centers))
        ch = (bss / (groups - 1)) / (wss / (study.n - groups))
    end
    Evaluation(partition, sizes, mean_silhouette(partition, study.delta), dunn, wss, ch, label_ari(study, partition))
end

function analyse_linkage(study, method)
    tree = ClusterTree(agglomerate(study.delta, method), study.n)
    cophenetic = pair_values(cophenetic_matrix(tree))
    height_cuts = [evaluate_partition(study, cut_at_height(tree, height)) for height in study.settings.cut_heights]
    count_cuts = [evaluate_partition(study, cut_into(tree, k)) for k in study.settings.cut_counts]
    LinkageResult(method, tree, cophenetic, correlation(study.distance_pairs, cophenetic), height_cuts, count_cuts, cut_into(tree, length(study.classes)))
end

function linkage_table(study)
    lines = ["method,step,a,b,height,size"]
    for result in study.results, (step, merge) in enumerate(result.tree.merges)
        push!(lines, "$(result.method),$step,$(merge.a - 1),$(merge.b - 1),$(format_real(merge.height)),$(merge.size)")
    end
    lines
end

function clusters_table(study)
    header = ["id", "label"]
    for result in study.results
        for j in eachindex(study.settings.cut_heights)
            push!(header, "$(result.method)_h$j")
        end
        for k in study.settings.cut_counts
            push!(header, "$(result.method)_k$k")
        end
    end
    lines = [join(header, ',')]
    for i in 1:study.n
        fields = [study.ids[i], study.labels[i]]
        for result in study.results, cut in Iterators.flatten((result.height_cuts, result.count_cuts))
            push!(fields, string(cut.partition[i]))
        end
        push!(lines, join(fields, ','))
    end
    lines
end

function dendrogram_report(study)
    parts = Vector{String}[]
    for result in study.results
        tree = result.tree
        maximum_height = maximum(tree_heights(tree))
        cuts = [column(height, maximum_height, study.settings.width) for height in study.settings.cut_heights]
        lines = ["dendrogram $(result.method) height_max $(format_real(maximum_height)) width $(study.settings.width)"]
        append!(lines, dendrogram_rows(tree.merges, tree.children, tree.order, study.ids, study.labels, maximum_height, cuts, study.settings.width))
        for (height, x) in zip(study.settings.cut_heights, cuts)
            push!(lines, "cut $(format_real(height)) column $(x <= study.settings.width ? string(x) : "-")")
        end
        push!(parts, lines)
    end
    join_parts(parts)
end

trees_report(study) = ["$(result.method) $(newick(result.tree, root_node(result.tree), study.ids));" for result in study.results]
pair_text(study, pair) = "$(format_real(study.delta[pair[1], pair[2]])) $(study.ids[pair[1]]) $(study.ids[pair[2]])"

function data_part(study)
    settings, n = study.settings, study.n
    lines = ["data n $n features $(length(study.features)) classes $(length(study.classes)) distance $(settings.distance) standardize $(settings.standardize ? "yes" : "no")"]
    for f in eachindex(study.features)
        push!(lines, "feature $(study.features[f]) mean $(format_real(study.means[f])) sd $(format_real(study.deviations[f]))")
    end
    smallest, largest = (1, 2), (1, 2)
    for i in 1:n, j in (i + 1):n
        study.delta[i, j] < study.delta[smallest...] && (smallest = (i, j))
        study.delta[i, j] > study.delta[largest...] && (largest = (i, j))
    end
    count = length(study.distance_pairs)
    push!(lines, "distances pairs $count min $(pair_text(study, smallest)) max $(pair_text(study, largest)) mean $(format_real(sequential_sum(study.distance_pairs) / count))")
    nearest_mean = sequential_sum(study.delta[i, study.neighbors[i]] for i in 1:n) / n
    reciprocal = count_true(i < study.neighbors[i] && study.neighbors[study.neighbors[i]] == i for i in 1:n)
    push!(lines, "nearest_neighbors mean $(format_real(nearest_mean)) reciprocal_pairs $reciprocal")
    push!(lines, "labels " * evaluation_text(evaluate_partition(study, copy(study.targets))))
    lines
end

count_true(values) = sum(value ? 1 : 0 for value in values)

function correlation_part(study)
    columns = [[row[f] for row in study.raw] for f in eachindex(study.features)]
    lines = ["correlation " * join(study.features, ' ')]
    for (f, first) in enumerate(columns)
        push!(lines, study.features[f] * " " * format_reals(correlation(first, second) for second in columns))
    end
    lines
end

function histogram_part(study)
    counts = zeros(Int, 10)
    for value in study.distance_pairs
        counts[histogram_bin(value, study.distance_max) + 1] += 1
    end
    highest = maximum(counts)
    lines = ["histogram"]
    for b in 0:9
        count = counts[b + 1]
        line = "$(format_real(b * study.distance_max / 10)) $(format_real((b + 1) * study.distance_max / 10)) $count"
        bar_length = count * 50 ÷ highest
        bar_length > 0 && (line *= " " * repeat("#", bar_length))
        push!(lines, line)
    end
    lines
end

function inconsistency_line(study, tree, step)
    sequence = height_sequence(tree, step, study.settings.inconsistency_depth)
    size = length(sequence)
    mean = sequential_sum(sequence) / size
    deviation = size == 1 ? 0.0 : sqrt(sequential_sum((value - mean) * (value - mean) for value in sequence) / (size - 1))
    coefficient = size == 1 ? 0.0 : (tree.merges[step].height - mean) / deviation
    "step $step height $(format_real(tree.merges[step].height)) mean $(format_real(mean)) sd $(format_real(deviation)) count $size coefficient $(format_real(coefficient))"
end

function linkage_part(study, result)
    settings, n, tree = study.settings, study.n, result.tree
    heights = tree_heights(tree)
    leaf_path = sequential_sum(study.delta[tree.order[r], tree.order[r + 1]] for r in 1:(n - 1))
    inversions = [step for step in 2:(n - 1) if heights[step] < heights[step - 1]]
    lines = ["linkage $(result.method)", "cophenetic $(format_real(result.correlation)) leaf_path $(format_real(leaf_path))",
        "heights min $(format_real(minimum(heights))) max $(format_real(maximum(heights))) inversions $(length(inversions))"]
    for step in inversions
        push!(lines, "inversion step $step height $(format_real(heights[step])) previous $(format_real(heights[step - 1]))")
    end
    ordered = sort(tree.subtree_heights)
    gaps = [ordered[n - k + 1] - ordered[n - k] for k in 2:settings.gap_max_k]
    suggested = 2
    for k in 3:settings.gap_max_k
        four_digit(gaps[k - 1]) > four_digit(gaps[suggested - 1]) && (suggested = k)
    end
    push!(lines, "gaps " * format_reals(gaps), "suggested_k $suggested")
    joining = joining_heights(tree)
    late = sort(collect(1:n), by=i -> (-joining[i], i))[1:settings.list_size]
    push!(lines, "late_joiners " * join(("$(study.ids[i]):$(format_real(joining[i]))" for i in late), ' '))
    kinds = zeros(Int, 3)
    for merge in tree.merges
        leaves = (merge.a <= n ? 1 : 0) + (merge.b <= n ? 1 : 0)
        kinds[3 - leaves] += 1
    end
    push!(lines, "merges leaf_leaf $(kinds[1]) leaf_cluster $(kinds[2]) cluster_cluster $(kinds[3]) depth $(tree.depths[root_node(tree)])")
    matches = match_count(study, result.label_partition)
    push!(lines, "label_cut k $(length(study.classes)) purity $matches/$n $(format_real(matches / n))")
    push!(lines, "inconsistency depth $(settings.inconsistency_depth_text)")
    for step in (n - settings.inconsistency_count):(n - 1)
        push!(lines, inconsistency_line(study, tree, step))
    end
    for (height, cut) in zip(settings.cut_heights, result.height_cuts)
        push!(lines, "cut height $(format_real(height)) clusters $(length(cut.sizes)) $(evaluation_text(cut))")
    end
    for (k, cut) in zip(settings.cut_counts, result.count_cuts)
        push!(lines, "cut k $k $(evaluation_text(cut))")
    end
    lines
end

function mst_part(study, single)
    n = study.n
    edges = minimum_spanning_tree(study.delta)
    total = sequential_sum(edge.weight for edge in edges)
    weights = sort([edge.weight for edge in edges])
    heights_match = all(abs(weight - height) <= 0.000000001 for (weight, height) in zip(weights, tree_heights(single.tree)))
    linked = falses(n, n)
    for edge in edges
        linked[edge.parent, edge.child] = true
        linked[edge.child, edge.parent] = true
    end
    nn_edges = count_true(linked[i, study.neighbors[i]] for i in 1:n)
    lines = ["mst total $(format_real(total)) heights $(heights_match ? "match" : "mismatch") nn_edges $nn_edges/$n"]
    ordered = sort(collect(eachindex(edges)), by=i -> (edges[i].weight, i))
    for (k, cut) in zip(study.settings.cut_counts, single.count_cuts)
        components = collect(1:n)
        for number in ordered[1:(n - k)]
            edge = edges[number]
            old, new = components[edge.child], components[edge.parent]
            for u in 1:n
                components[u] == old && (components[u] = new)
            end
        end
        agrees = true
        for i in 1:n, j in (i + 1):n
            if (components[i] == components[j]) != (cut.partition[i] == cut.partition[j])
                agrees = false
            end
        end
        push!(lines, "mst partition k $k $(agrees ? "match" : "mismatch")")
    end
    lines
end

function compare_part(study)
    method, label_count = study.settings.compare_linkage, length(study.classes)
    lines = ["compare linkage $method k $label_count"]
    for kind in DISTANCE_TYPES
        delta = distance_matrix(study.vectors, kind)
        tree = ClusterTree(agglomerate(delta, method), study.n)
        cophenetic = correlation(pair_values(delta), pair_values(cophenetic_matrix(tree)))
        partition = cut_into(tree, label_count)
        push!(lines, "metric $kind cophenetic $(format_real(cophenetic)) silhouette $(format_optional(mean_silhouette(partition, delta))) ari $(ari_text(label_ari(study, partition)))")
    end
    lines
end

function cophenetic_part(study)
    lines = ["cophenetic_matrix", "linkage " * join((result.method for result in study.results), ' ')]
    for first in study.results
        push!(lines, "$(first.method) " * format_reals(correlation(first.cophenetic, second.cophenetic) for second in study.results))
    end
    lines
end

function agreement_part(study)
    lines = ["agreement k $(length(study.classes))", "linkage " * join((result.method for result in study.results), ' ')]
    for first in study.results
        push!(lines, "$(first.method) " * format_reals(Float64(partition_ari(first.label_partition, second.label_partition)) for second in study.results))
    end
    lines
end

function summary_part(study)
    ranking = sort(collect(eachindex(study.results)), by=i -> (-four_digit(study.results[i].correlation), i))
    lines = ["summary", "cophenetic_ranking " * join((study.results[i].method for i in ranking), ' ')]
    for (position, k) in enumerate(study.settings.cut_counts)
        best = 1
        for r in 2:length(study.results)
            if ari_greater(study.results[r].count_cuts[position].ari, study.results[best].count_cuts[position].ari)
                best = r
            end
        end
        push!(lines, "best_ari k $k $(study.results[best].method) $(ari_text(study.results[best].count_cuts[position].ari))")
    end
    for result in study.results
        best = 1
        for position in 2:length(study.settings.cut_counts)
            if four_digit(result.count_cuts[position].silhouette) > four_digit(result.count_cuts[best].silhouette)
                best = position
            end
        end
        push!(lines, "best_silhouette $(result.method) k $(study.settings.cut_counts[best]) $(format_optional(result.count_cuts[best].silhouette))")
    end
    push!(lines, "selected $(chosen_result(study).method) k $(kappa(study))")
    lines
end

function validation_report(study)
    parts = [data_part(study), correlation_part(study), histogram_part(study)]
    for result in study.results
        push!(parts, linkage_part(study, result))
    end
    single = findfirst(result -> result.method == :single, study.results)
    !isnothing(single) && push!(parts, mst_part(study, study.results[single]))
    append!(parts, [compare_part(study), cophenetic_part(study), agreement_part(study), summary_part(study)])
    join_parts(parts)
end

function cluster_separation(study, first, second)
    best = Inf
    for i in first, j in second
        best = min(best, study.delta[i, j])
    end
    best
end

function selection_part(study)
    selected = selected_partition(study)
    members = selected_members(study)
    table = class_table(study, selected)
    silhouettes = silhouette_values(selected, kappa(study), study.delta)
    cut = selected_cut(study)
    lines = ["selected linkage $(chosen_result(study).method) k $(kappa(study)) ari $(ari_text(cut.ari)) silhouette $(format_optional(cut.silhouette))"]
    for (g, group) in enumerate(members)
        size = length(group)
        silhouette = sequential_sum(silhouettes[i] for i in group) / size
        majority = majority_class(table[g, :])
        count = table[g, majority]
        means = [sequential_sum(study.raw[i][f] for i in group) / size for f in eachindex(study.features)]
        medoid, medoid_sum = group[1], Inf
        for i in group
            total = sequential_sum(study.delta[i, j] for j in group)
            if total < medoid_sum
                medoid, medoid_sum = i, total
            end
        end
        widest = nothing
        for position in eachindex(group), offset in (position + 1):length(group)
            i, j = group[position], group[offset]
            if isnothing(widest) || study.delta[i, j] > study.delta[widest...]
                widest = (i, j)
            end
        end
        diameter = isnothing(widest) ? "0.0000 - -" : pair_text(study, widest)
        nearest, nearest_separation = 0, Inf
        for (h, other) in enumerate(members)
            h == g && continue
            value = cluster_separation(study, group, other)
            if value < nearest_separation
                nearest, nearest_separation = h, value
            end
        end
        push!(lines, "cluster $g size $size silhouette $(format_real(silhouette)) majority $(study.classes[majority]) purity $count/$size $(format_real(count / size))")
        push!(lines, "  mean " * format_reals(means))
        push!(lines, "  medoid $(study.ids[medoid]) diameter $diameter nearest $nearest separation $(format_real(nearest_separation))")
    end
    lines
end

function centroid_part(study)
    centers = centroids(study, selected_partition(study))
    lines = ["centroid_distances"]
    for (g, first) in enumerate(centers)
        push!(lines, "$g " * format_reals(sqrt(squared_distance(first, second)) for second in centers))
    end
    lines
end

function profile_part(study)
    width = maximum(length.(study.features))
    lines = ["profile_bars"]
    for (g, group) in enumerate(selected_members(study))
        push!(lines, "cluster $g")
        for (f, name) in enumerate(study.features)
            zeta = sequential_sum((study.raw[i][f] - study.means[f]) / study.deviations[f] for i in group) / length(group)
            bar_length = min(10, floor(Int, abs(zeta) * 4.0))
            bar = repeat("#", bar_length)
            left = zeta < 0 ? repeat(" ", 10 - bar_length) * bar : repeat(" ", 10)
            right = zeta < 0 ? repeat(" ", 10) : bar * repeat(" ", 10 - bar_length)
            push!(lines, rpad(name, width) * " " * left * "|" * right * " " * format_real(zeta))
        end
    end
    lines
end

function contingency_part(study)
    table = class_table(study, selected_partition(study))
    lines = ["contingency", "cluster " * join(study.classes, ' ') * " total"]
    for g in axes(table, 1)
        row = table[g, :]
        push!(lines, "$g $(format_integers(row)) $(sum(row))")
    end
    totals = [sum(table[:, t]) for t in axes(table, 2)]
    push!(lines, "total $(format_integers(totals)) $(study.n)")
    matches = match_count(study, selected_partition(study))
    push!(lines, "purity $matches/$(study.n) $(format_real(matches / study.n))")
    lines
end

function misplaced_part(study)
    table = class_table(study, selected_partition(study))
    majority = [majority_class(table[g, :]) for g in axes(table, 1)]
    lines = ["misplaced"]
    count = 0
    for (i, number) in enumerate(selected_partition(study))
        if study.targets[i] != majority[number]
            count += 1
            push!(lines, "$(study.ids[i]) label $(study.labels[i]) cluster $number majority $(study.classes[majority[number]])")
        end
    end
    push!(lines, "count $count")
    lines
end

function weakest_part(study)
    selected = selected_partition(study)
    silhouettes = silhouette_values(selected, kappa(study), study.delta)
    order = sort(collect(1:study.n), by=i -> (silhouettes[i], i))
    lines = ["weakest"]
    for i in order[1:study.settings.list_size]
        push!(lines, "$(study.ids[i]) label $(study.labels[i]) cluster $(selected[i]) silhouette $(format_real(silhouettes[i]))")
    end
    lines
end

function feature_part(study)
    members = selected_members(study)
    selected = selected_partition(study)
    ratios = Float64[]
    for f in eachindex(study.features)
        overall = sequential_sum(vector[f] for vector in study.vectors) / study.n
        means = [sequential_sum(study.vectors[i][f] for i in group) / length(group) for group in members]
        between = sequential_sum(length(group) * (mean - overall) * (mean - overall) for (group, mean) in zip(members, means))
        within = sequential_sum((study.vectors[i][f] - means[number]) * (study.vectors[i][f] - means[number]) for (i, number) in enumerate(selected))
        push!(ratios, (between / (kappa(study) - 1)) / (within / (study.n - kappa(study))))
    end
    ranking = sort(collect(eachindex(ratios)), by=f -> (-four_digit(ratios[f]), f))
    lines = ["features"]
    for (rank, f) in enumerate(ranking)
        push!(lines, "$rank $(study.features[f]) f_ratio $(format_real(ratios[f]))")
    end
    lines
end

function class_counts(study, tree, node)
    counts = zeros(Int, length(study.classes))
    for i in tree.members[node]
        counts[study.targets[i]] += 1
    end
    join(counts, '/')
end

function top_merges_part(study)
    tree = chosen_result(study).tree
    lines = ["top_merges"]
    for step in (study.n - study.settings.inconsistency_count):(study.n - 1)
        merge = tree.merges[step]
        push!(lines, "step $step height $(format_real(merge.height)) a $(merge.a - 1) $(length(tree.members[merge.a])) $(class_counts(study, tree, merge.a)) b $(merge.b - 1) $(length(tree.members[merge.b])) $(class_counts(study, tree, merge.b))")
    end
    lines
end

function drop_feature_part(study)
    lines = ["drop_feature"]
    for (f, name) in enumerate(study.features)
        reduced = [[value for (j, value) in enumerate(vector) if j != f] for vector in study.vectors]
        delta = distance_matrix(reduced, study.settings.distance)
        partition = cut_into(ClusterTree(agglomerate(delta, chosen_result(study).method), study.n), kappa(study))
        push!(lines, "$name ari_selected $(ari_text(partition_ari(partition, selected_partition(study)))) ari_labels $(ari_text(label_ari(study, partition)))")
    end
    lines
end

function nearest_center(vector, centers)
    best, best_value = 1, squared_distance(vector, centers[1])
    for g in 2:length(centers)
        value = squared_distance(vector, centers[g])
        if value < best_value
            best, best_value = g, value
        end
    end
    best
end

function refinement_part(study)
    limit = study.settings.refine_iterations
    selected = selected_partition(study)
    centers = centroids(study, selected)
    previous = copy(selected)
    iterations = limit
    for t in 1:limit
        assignment = [nearest_center(vector, centers) for vector in study.vectors]
        if assignment == previous
            iterations = t
            break
        end
        for (g, group) in enumerate(cluster_members(assignment, kappa(study)))
            !isempty(group) && (centers[g] = centroid([study.vectors[i] for i in group]))
        end
        previous = assignment
    end
    changed = count_true(before != after for (before, after) in zip(selected, previous))
    sizes = length.(cluster_members(previous, kappa(study)))
    ["refinement max_iterations $limit",
        "iterations $iterations changed $changed wss $(format_real(within_sum(study, selected))) -> $(format_real(within_sum(study, previous)))",
        "sizes $(format_integers(sizes)) silhouette $(format_optional(mean_silhouette(previous, study.delta)))",
        "ari_selected $(ari_text(partition_ari(previous, selected))) ari_labels $(ari_text(label_ari(study, previous)))"]
end

function jaccard_values(study, partition, restricted)
    table = contingency_table(restricted, partition, kappa(study), maximum(partition))
    totals = [sum(table[:, h]) for h in axes(table, 2)]
    values = Float64[]
    for row in eachrow(table)
        size = sum(row)
        best = 0 // 1
        if size > 0
            for (h, common) in enumerate(row)
                candidate = common // (size + totals[h] - common)
                candidate > best && (best = candidate)
            end
        end
        push!(values, Float64(best))
    end
    values
end

function stability_part(study)
    settings, n = study.settings, study.n
    generator = Minstd(settings.seed)
    size = n * settings.percent ÷ 100
    aris = Float64[]
    jaccards = Vector{Float64}[]
    lines = ["stability replicates $(settings.replicates) percent $(settings.percent) seed $(settings.seed)"]
    for b in 1:settings.replicates
        array = collect(1:n)
        for t in 0:(size - 1)
            j = t + draw!(generator) % (n - t)
            array[t + 1], array[j + 1] = array[j + 1], array[t + 1]
        end
        sample = sort(array[1:size])
        delta = [study.delta[u, w] for u in sample, w in sample]
        partition = cut_into(ClusterTree(agglomerate(delta, chosen_result(study).method), size), kappa(study))
        restricted = [selected_partition(study)[u] for u in sample]
        ari = partition_ari(partition, restricted)
        coefficients = jaccard_values(study, partition, restricted)
        push!(lines, "replicate $b size $size ari $(ari_text(ari)) jaccard $(format_reals(coefficients))")
        push!(aris, Float64(ari))
        push!(jaccards, coefficients)
    end
    push!(lines, "mean_ari " * format_real(sequential_sum(aris) / settings.replicates))
    push!(lines, "mean_jaccard " * format_reals(sequential_sum(values[g] for values in jaccards) / settings.replicates for g in 1:kappa(study)))
    lines
end

function distance_map_part(study)
    order = chosen_result(study).tree.order
    frame = "+" * repeat("-", study.n) * "+"
    lines = ["distance_map $(chosen_result(study).method)", frame]
    shades = collect("@%#*+=-:. ")
    for u in order
        cells = join(shades[histogram_bin(study.delta[u, w], study.distance_max) + 1] for w in order)
        push!(lines, "|" * cells * "|")
    end
    push!(lines, frame)
    lines
end

function profiles_report(study)
    join_parts([selection_part(study), centroid_part(study), profile_part(study), contingency_part(study),
        misplaced_part(study), weakest_part(study), feature_part(study), top_merges_part(study),
        drop_feature_part(study), refinement_part(study), stability_part(study), distance_map_part(study)])
end

function main()
    features, observations = read_observations()
    settings = read_settings()
    study = build_study(features, observations, settings)
    mkpath("output")
    write_lines("linkage.csv", linkage_table(study))
    write_lines("clusters.csv", clusters_table(study))
    write_lines("dendrogram.txt", dendrogram_report(study))
    write_lines("trees.txt", trees_report(study))
    write_lines("validation.txt", validation_report(study))
    write_lines("profiles.txt", profiles_report(study))
end

main()
