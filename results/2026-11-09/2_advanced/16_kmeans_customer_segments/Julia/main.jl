include("transactions.jl")
include("features.jl")
include("kmeans.jl")
include("validation.jl")
include("profiles.jl")
include("report.jl")

mutable struct Minstd
    state::Int
end

function draw!(generator)
    generator.state = mod(48271 * generator.state, 2147483647)
end

nearest_gaps(points, chosen) = [minimum(squared_distance(point, points[index]) for index in chosen) for point in points]

function maximin(points, k, number)
    center = mean_point(points)
    spreads = [squared_distance(point, center) for point in points]
    order = sort(collect(eachindex(points)); by=index -> (spreads[index], index))
    chosen = [order[number]]
    while length(chosen) < k
        push!(chosen, findmax(nearest_gaps(points, chosen))[2])
    end
    chosen
end

function initial_seeds(method, points, k, number, generator)
    method == "maximin" && return maximin(points, k, number)
    chosen = Int[]
    if method == "forgy"
        while length(chosen) < k
            index = mod(draw!(generator), length(points)) + 1
            !(index in chosen) && push!(chosen, index)
        end
        return chosen
    end
    push!(chosen, mod(draw!(generator), length(points)) + 1)
    while length(chosen) < k
        gaps = nearest_gaps(points, chosen)
        threshold = (draw!(generator) / 2147483647) * ordered_sum(gaps)
        total, selected = 0.0, 0
        for (index, gap) in enumerate(gaps)
            total += gap
            if total > threshold
                selected = index
                break
            end
        end
        selected == 0 && (selected = findlast(>(0), gaps))
        push!(chosen, selected)
    end
    chosen
end

struct Improvement
    labels::Vector{Int}
    passes::Int
    transfers::Int
    sse::Float64
end

function improve(points, initial_labels, k, max_passes)
    labels = copy(initial_labels)
    sizes, centers = cluster_sizes(labels, k), cluster_centers(points, labels, k)
    passes = transfers = 0
    moved = true
    while moved && passes < max_passes
        moved = false
        passes += 1
        for (index, point) in enumerate(points)
            own = labels[index]
            sizes[own] == 1 && continue
            removal = (sizes[own] / (sizes[own] - 1)) * squared_distance(point, centers[own])
            target, target_cost = 0, 0.0
            for q in 1:k
                q == own && continue
                cost = (sizes[q] / (sizes[q] + 1)) * squared_distance(point, centers[q])
                if target == 0 || cost < target_cost
                    target, target_cost = q, cost
                end
            end
            if target_cost < removal
                labels[index] = target
                sizes[own] -= 1
                sizes[target] += 1
                centers[own] = cluster_center(points, labels, own)
                centers[target] = cluster_center(points, labels, target)
                transfers += 1
                moved = true
            end
        end
    end
    Improvement(labels, passes, transfers, sse(points, labels, cluster_centers(points, labels, k)))
end

struct Run
    method::String
    number::Int
    seeds::Vector{Int}
    lloyd::LloydResult
    lloyd_sse::Float64
    improved::Improvement
end

function Run(method, number, seeds, points, max_iterations)
    result = lloyd(points, points[seeds], max_iterations)
    Run(method, number, seeds, result, sse(points, result.labels, result.centers), improve(points, result.labels, length(seeds), max_iterations))
end

best_run(runs) = runs[findmin([four_decimal(run.improved.sse) for run in runs])[2]]

struct Solution
    k::Int
    members::Vector{Vector{Int}}
    sizes::Vector{Int}
    labels::Vector{Int}
    centers::Vector{Vector{Float64}}
    sse::Float64
end

function Solution(points, labels, k)
    members = [[index for (index, label) in enumerate(labels) if label == j] for j in 1:k]
    sort!(members; by=group -> (-length(group), group[1]))
    ordered = zeros(Int, length(labels))
    for (number, group) in enumerate(members)
        ordered[group] .= number
    end
    centers = cluster_centers(points, ordered, k)
    Solution(k, members, length.(members), ordered, centers, sse(points, ordered, centers))
end

Base.@kwdef mutable struct Candidate
    k::Int
    runs::Vector{Run}
    method_bests::Vector{Run}
    best::Run
    solution::Solution
    silhouettes::Vector{Float64} = Float64[]
    silhouette::Float64 = 0.0
    calinski_harabasz::Float64 = 0.0
    davies_bouldin::Float64 = 0.0
    elbow::Float64 = 0.0
    hartigan::Union{Nothing,Float64} = nothing
    rule_numbers::Vector{Int} = Int[]
    names::Vector{String} = String[]
end

function category_totals(customers)
    totals = Dict{String,Int}()
    for customer in customers, (category, spend) in customer.category_spend
        totals[category] = get(totals, category, 0) + spend
    end
    totals
end

category_ranking(totals) = sort([category for (category, value) in totals if value > 0]; by=category -> (-totals[category], category))
yes_no(flag) = flag ? "yes" : "no"

function join_blocks(blocks)
    lines = String[]
    for block in blocks
        !isempty(lines) && push!(lines, "")
        append!(lines, block)
    end
    lines
end

function rfm_scores(customers)
    n = length(customers)
    [[1 + div(5 * count(other -> other.recency > customer.recency, customers), n),
        1 + div(5 * count(other -> other.frequency < customer.frequency, customers), n),
        1 + div(5 * count(other -> other.spend < customer.spend, customers), n)] for customer in customers]
end

function gini(spends)
    ordered = sort(spends)
    n, total = length(ordered), sum(ordered)
    weighted = sum(position * spend for (position, spend) in enumerate(ordered))
    (2 * weighted - (n + 1) * total) / (n * total)
end

lower_median(values) = sort(values)[div(length(values) - 1, 2) + 1]

function analyze(params, data, rules)
    generator = Minstd(params.seed)
    reference_orders = group_orders(data.valid_rows, 1, params.reference_day)
    customer_orders = orders_by_customer(reference_orders)
    customers = eligible_customers(reference_orders, params.reference_day)
    n = length(customers)
    numbers = Dict(customer.id => number for (number, customer) in enumerate(customers))
    means, sds = standardization(transformed.(customers))
    points = [standardize(transformed(customer), means, sds) for customer in customers]
    candidates = Candidate[]
    for k in params.k_min:params.k_max
        runs, method_bests = Run[], Run[]
        for method in params.methods
            method_runs = [Run(method, number, initial_seeds(method, points, k, number, generator), points, params.max_iterations) for number in 1:params.restarts]
            append!(runs, method_runs)
            push!(method_bests, best_run(method_runs))
        end
        best = best_run(method_bests)
        push!(candidates, Candidate(; k, runs, method_bests, best, solution=Solution(points, best.improved.labels, k)))
    end
    table = distance_table(points)
    for (index, candidate) in enumerate(candidates)
        solution = candidate.solution
        candidate.silhouettes = silhouettes(table, solution.labels, solution.sizes)
        candidate.silhouette = mean(candidate.silhouettes)
        candidate.calinski_harabasz = calinski_harabasz(points, solution.centers, solution.sizes, solution.sse)
        candidate.davies_bouldin = davies_bouldin(points, solution.labels, solution.centers, solution.sizes)
        candidate.elbow = elbow(candidate.k, params.k_min, params.k_max, solution.sse, candidates[1].solution.sse, candidates[end].solution.sse)
        index < length(candidates) && (candidate.hartigan = hartigan(solution.sse, candidates[index + 1].solution.sse, n, candidate.k))
        candidate.rule_numbers = [rule_number(rules, center) for center in solution.centers]
        for (position, number) in enumerate(candidate.rule_numbers)
            repeats = count(==(number), candidate.rule_numbers[1:position-1])
            push!(candidate.names, rules[number].name * (repeats == 0 ? "" : "_$(repeats + 1)"))
        end
    end
    elbow_candidate = candidates[1 + findmax([four_decimal(c.elbow) for c in candidates[2:end-1]])[2]]
    silhouette_candidate = candidates[findmax([four_decimal(c.silhouette) for c in candidates])[2]]
    ch_candidate = candidates[findmax([four_decimal(c.calinski_harabasz) for c in candidates])[2]]
    db_candidate = candidates[findmin([four_decimal(c.davies_bouldin) for c in candidates])[2]]
    hartigan_index = findfirst(c -> !isnothing(c.hartigan) && c.hartigan <= 10, candidates)
    hartigan_vote = isnothing(hartigan_index) ? params.k_max : candidates[hartigan_index].k
    votes = [("elbow", elbow_candidate.k), ("silhouette", silhouette_candidate.k), ("calinski_harabasz", ch_candidate.k), ("davies_bouldin", db_candidate.k), ("hartigan", hartigan_vote)]
    vote_counts = [count(vote -> vote[2] == candidate.k, votes) for candidate in candidates]
    index = first(sort(collect(eachindex(candidates)); by=i -> (-vote_counts[i], -four_decimal(candidates[i].silhouette), candidates[i].k)))
    final, final_votes = candidates[index], vote_counts[index]
    k, labels, centers, names = final.k, final.solution.labels, final.solution.centers, final.names
    distances, others = Float64[], Tuple{Int,Float64}[]
    for (point, label) in zip(points, labels)
        squared = [squared_distance(point, center) for center in centers]
        other = first(sort([j for j in 1:k if j != label]; by=j -> (squared[j], j)))
        push!(distances, sqrt(squared[label]))
        push!(others, (other, sqrt(squared[other])))
    end
    scores = rfm_scores(customers)
    codes = [join(score) for score in scores]
    total_spend = sum(customer.spend for customer in customers)
    overall_categories = category_totals(customers)
    category_names = sort(collect(keys(overall_categories)))
    segment_customers = [customers[members] for members in final.solution.members]
    segment_spends = [sum(customer.spend for customer in members) for members in segment_customers]
    segment_categories = category_totals.(segment_customers)
    rankings = category_ranking.(segment_categories)
    segment_sse = [ordered_sum(squared_distance(points[number], centers[segment]) for number in members) for (segment, members) in enumerate(final.solution.members)]
    sample_size = div(n * params.subsample_percent, 100)
    jaccards = [Float64[] for _ in 1:k]
    for _ in 1:params.subsamples
        order = collect(1:n)
        for t in 1:sample_size
            j = t + mod(draw!(generator), n - t + 1)
            order[t], order[j] = order[j], order[t]
        end
        sample = sort(order[1:sample_size])
        result = lloyd(points[sample], centers, params.max_iterations)
        for segment in 1:k
            in_segment = labels[sample] .== segment
            best = 0.0
            for j in 1:k
                both = count(member && label == j for (member, label) in zip(in_segment, result.labels))
                either = count(member || label == j for (member, label) in zip(in_segment, result.labels))
                either > 0 && (best = max(best, both / either))
            end
            push!(jaccards[segment], best)
        end
    end
    (; params, data, rules, reference_orders, customer_orders, customers, n, numbers, means, sds, points, candidates, votes, final,
        final_votes, k, labels, centers, names, distances, others, scores, codes, total_spend, overall_categories, category_names, segment_customers,
        segment_spends, segment_categories, rankings, segment_sse, jaccards)
end

ids(a, numbers) = join([a.customers[number].id for number in numbers], " ")
candidate(a, k) = a.candidates[k - a.params.k_min + 1]
run_summary(run) = "$(run.method) restart $(run.number) sse $(real_text(run.improved.sse))"

function features_lines(a)
    lines = ["customer,recency,frequency,monetary,basket,categories,tenure,z_recency,z_frequency,z_monetary,z_basket,z_categories,z_tenure"]
    for (customer, point) in zip(a.customers, a.points)
        fields = [customer.id, string(customer.recency), string(customer.frequency), amount(customer.spend), real_text(customer.basket), string(customer.categories), string(customer.tenure)]
        append!(fields, real_text.(point))
        push!(lines, join(fields, ','))
    end
    lines
end

function runs_lines(a)
    blocks = Vector{String}[]
    for candidate in a.candidates
        lines = ["k $(candidate.k)"]
        for run in candidate.runs
            push!(lines, "run $(run.method) $(run.number) seeds $(ids(a, run.seeds)) iterations $(run.lloyd.iterations) converged $(yes_no(run.lloyd.converged)) reseeds $(run.lloyd.reseeds) sse $(real_text(run.lloyd_sse)) passes $(run.improved.passes) transfers $(run.improved.transfers) refined $(real_text(run.improved.sse))")
        end
        append!(lines, ["best $(run_summary(run))" for run in candidate.method_bests])
        push!(lines, "chosen $(run_summary(candidate.best))", "sizes " * join(candidate.solution.sizes, " "))
        push!(blocks, lines)
    end
    join_blocks(blocks)
end

function selection_lines(a)
    indices, votes, names, stability = ["indices"], ["votes"], ["segments"], ["stability"]
    for (position, candidate) in enumerate(a.candidates)
        h = isnothing(candidate.hartigan) ? "-" : real_text(candidate.hartigan)
        push!(indices, "k=$(candidate.k) sse $(real_text(candidate.solution.sse)) elbow $(real_text(candidate.elbow)) silhouette $(real_text(candidate.silhouette)) calinski_harabasz $(real_text(candidate.calinski_harabasz)) davies_bouldin $(real_text(candidate.davies_bouldin)) hartigan $h")
        push!(names, "k=$(candidate.k) " * join(["$name:$size" for (name, size) in zip(candidate.names, candidate.solution.sizes)], " "))
        parts = ["k=$(candidate.k)"]
        bests = candidate.method_bests
        for i in eachindex(bests), j in i+1:length(bests)
            push!(parts, "$(bests[i].method):$(bests[j].method) $(real_text(adjusted_rand_index(bests[i].improved.labels, bests[j].improved.labels)))")
        end
        push!(parts, "final")
        for run in bests
            push!(parts, "$(run.method) $(real_text(adjusted_rand_index(run.improved.labels, candidate.solution.labels)))")
        end
        following = position < length(a.candidates) ? real_text(adjusted_rand_index(candidate.solution.labels, a.candidates[position + 1].solution.labels)) : "-"
        push!(parts, "next $following")
        push!(stability, join(parts, " "))
    end
    append!(votes, ["$criterion k=$k" for (criterion, k) in a.votes])
    push!(votes, "chosen k=$(a.k) votes $(a.final_votes)")
    join_blocks([indices, votes, names, stability])
end

function recommendation(a, number)
    customer = a.customers[number]
    index = findfirst(category -> get(customer.category_spend, category, 0) <= 0, a.rankings[a.labels[number]])
    isnothing(index) ? "-" : a.rankings[a.labels[number]][index]
end

function segments_lines(a)
    lines = ["customer,segment,name,distance,other,other_distance,silhouette,recommend"]
    for (number, customer) in enumerate(a.customers)
        label, (other, distance) = a.labels[number], a.others[number]
        push!(lines, join([customer.id, string(label), a.names[label], real_text(a.distances[number]), string(other), real_text(distance), real_text(a.final.silhouettes[number]), recommendation(a, number)], ','))
    end
    lines
end

function related(a, members, k)
    !(a.params.k_min <= k <= a.params.k_max) && return "k=$k -"
    labels = candidate(a, k).solution.labels
    counts = [count(number -> labels[number] == j, members) for j in 1:k]
    best = findmax(counts)[2]
    "k=$k segment $best shared $(counts[best])"
end

function segment_profile(a, segment)
    members, customers = a.final.solution.members[segment], a.segment_customers[segment]
    size, center, spend = length(members), a.centers[segment], a.segment_spends[segment]
    lines = ["segment $segment $(a.names[segment]) rule $(a.final.rule_numbers[segment]) size $size share $(real_text(size / a.n)) revenue $(amount(spend)) revenue_share $(real_text(spend / a.total_spend))", "  center " * reals(center)]
    original = original_scale(center, a.means, a.sds)
    push!(lines, "  value " * join(["$name $(real_text(value))" for (name, value) in zip(FEATURE_NAMES, original)], " "))
    order = sort(collect(eachindex(center)); by=feature -> (-abs(center[feature]), feature))
    traits = [(center[f] > 0 ? "high_" : "low_") * FEATURE_NAMES[f] for f in order[1:2]]
    push!(lines, "  traits " * join(traits, " "))
    recency, frequency, monetary, basket, categories, tenure = [lower_median([values[f] for values in raw_values.(customers)]) for f in 1:6]
    spend_median = lower_median([customer.spend for customer in customers])
    push!(lines, "  median recency $(Int(recency)) frequency $(Int(frequency)) monetary $(amount(spend_median)) basket $(real_text(basket)) categories $(Int(categories)) tenure $(Int(tenure))")
    push!(lines, "  related " * join([related(a, members, k) for k in (a.k - 1, a.k + 1)], " "))
    top = sort(members; by=number -> (-a.customers[number].spend, number))
    push!(lines, "  top_customers " * join(["$(a.customers[number].id) $(amount(a.customers[number].spend))" for number in top[1:min(end, a.params.top_customers)]], " "))
    gaps = Float64[]
    overdue = 0
    bins = zeros(Int, length(a.params.order_bins) + 1)
    gross = returned = cancelled = 0
    for customer in customers
        if customer.frequency >= 2
            active = customer.tenure - customer.recency
            intervals = customer.frequency - 1
            push!(gaps, active / intervals)
            overdue += customer.recency * intervals > a.params.overdue_factor * active
        end
        for order in customer.orders
            index = count(bound -> order.net >= bound * 100, a.params.order_bins) + 1
            bins[index] += 1
        end
        for order in a.customer_orders[customer.id]
            cancelled += order.net <= 0
            for row in order.rows
                gross += max(row.amount, 0)
                returned -= min(row.amount, 0)
            end
        end
    end
    mean_gap = isempty(gaps) ? "-" : real_text(mean(gaps))
    push!(lines, "  cadence customers $(length(gaps)) mean_gap $mean_gap overdue $overdue", "  order_sizes " * join(bins, " "),
        "  sse $(real_text(a.segment_sse[segment])) share $(real_text(a.segment_sse[segment] / a.final.solution.sse))", "  gini $(real_text(gini([customer.spend for customer in customers])))",
        "  returns rate $(real_text(returned / gross)) returned $(amount(returned)) cancelled $cancelled")
    silhouettes = a.final.silhouettes[members]
    push!(lines, "  silhouette $(real_text(mean(silhouettes))) negative $(count(<(0), silhouettes))")
    scores = [sum(a.scores[number][part] for number in members) / size for part in 1:3]
    code_counts = Dict{String,Int}()
    for number in members
        code_counts[a.codes[number]] = get(code_counts, a.codes[number], 0) + 1
    end
    mode = first(sort(collect(keys(code_counts)); by=code -> (-code_counts[code], code)))
    push!(lines, "  rfm r $(real_text(scores[1])) f $(real_text(scores[2])) m $(real_text(scores[3])) mode $mode $(code_counts[mode])")
    parts = ["  categories"]
    for category in a.rankings[segment][1:min(end, a.params.top_categories)]
        share = a.segment_categories[segment][category] / spend
        lift = share / (a.overall_categories[category] / a.total_spend)
        push!(parts, "$category $(real_text(share)) $(real_text(lift))")
    end
    push!(lines, join(parts, " "))
    outliers = Int[]
    if size >= 2
        distances = a.distances[members]
        limit = mean(distances) + a.params.outlier_sd * sample_sd(distances)
        outliers = [number for number in members if a.distances[number] > limit]
    end
    push!(lines, "  outliers $(length(outliers))" * (isempty(outliers) ? "" : " " * ids(a, outliers)))
    lines
end

function profiles_lines(a)
    blocks = [["segments k=$(a.k) customers $(a.n) revenue $(amount(a.total_spend)) gini $(real_text(gini([customer.spend for customer in a.customers])))"]]
    append!(blocks, [segment_profile(a, segment) for segment in 1:a.k])
    numbers = join(1:a.k, " ")
    mix = ["category_mix $numbers"]
    for category in a.category_names
        shares = [get(totals, category, 0) / spend for (totals, spend) in zip(a.segment_categories, a.segment_spends)]
        push!(mix, category * " " * reals(shares))
    end
    recency = ["rfm_recency $numbers"]
    for score in 5:-1:1
        counts = zeros(Int, a.k)
        for (number, scores) in enumerate(a.scores)
            scores[1] == score && (counts[a.labels[number]] += 1)
        end
        push!(recency, "r=$score " * join(counts, " "))
    end
    push!(recency, "ari rfm_codes $(real_text(adjusted_rand_index(a.codes, a.labels)))")
    distances = ["center_distances"]
    for (segment, center) in enumerate(a.centers)
        push!(distances, "$segment " * reals([sqrt(squared_distance(center, other)) for other in a.centers]))
    end
    append!(blocks, [mix, recency, distances])
    join_blocks(blocks)
end

function robustness_lines(a)
    sample_size = div(a.n * a.params.subsample_percent, 100)
    subsamples = ["subsamples $(a.params.subsamples) size $sample_size"]
    for (segment, values) in enumerate(a.jaccards)
        push!(subsamples, "segment $segment $(a.names[segment]) mean_jaccard $(real_text(mean(values))) min_jaccard $(real_text(minimum(values)))")
    end
    ablation = ["ablation"]
    for (feature, name) in enumerate(FEATURE_NAMES)
        points = [point[setdiff(eachindex(point), [feature])] for point in a.points]
        seeds = maximin(points, a.k, 1)
        run = Run("maximin", 1, seeds, points, a.params.max_iterations)
        push!(ablation, "without $name seeds $(ids(a, seeds)) iterations $(run.lloyd.iterations) converged $(yes_no(run.lloyd.converged)) transfers $(run.improved.transfers) sse $(real_text(run.improved.sse)) ari $(real_text(adjusted_rand_index(run.improved.labels, a.labels)))")
    end
    members = a.final.solution.members[1]
    points = a.points[members]
    seeds = maximin(points, 2, 1)
    run = Run("maximin", 1, seeds, points, a.params.max_iterations)
    parts = Solution(points, run.improved.labels, 2)
    before, after = a.segment_sse[1], run.improved.sse
    drilldown = ["drilldown segment 1 $(a.names[1]) size $(length(members)) seeds $(ids(a, members[seeds])) iterations $(run.lloyd.iterations) converged $(yes_no(run.lloyd.converged)) transfers $(run.improved.transfers)",
        "sse before $(real_text(before)) after $(real_text(after)) gain $(real_text(before - after))"]
    for (part, (size, center)) in enumerate(zip(parts.sizes, parts.centers))
        push!(drilldown, "part $part size $size center $(reals(center))")
    end
    join_blocks([subsamples, ablation, drilldown])
end

function tracking_lines(a)
    p = a.params
    periods = ["periods $(p.periods) days $(p.period_days)"]
    for q in 1:p.periods
        first, last = p.reference_day - q * p.period_days + 1, p.reference_day - (q - 1) * p.period_days
        revenue, active, acquired = (zeros(Int, a.k) for _ in 1:3)
        for (customer, label) in zip(a.customers, a.labels)
            nets = [order.net for order in customer.orders if first <= order.day <= last]
            if !isempty(nets)
                revenue[label] += sum(nets)
                active[label] += 1
            end
            acquired[label] += first <= p.reference_day - customer.tenure <= last
        end
        push!(periods, "period $q days $first $last revenue $(join(amount.(revenue), " ")) active $(join(active, " ")) acquired $(join(acquired, " "))")
    end
    snapshot = eligible_customers(group_orders(a.data.valid_rows, 1, p.snapshot_day), p.snapshot_day)
    origins = Dict{String,Int}()
    for customer in snapshot
        point = standardize(transformed(customer), a.means, a.sds)
        origins[customer.id] = findmin([squared_distance(point, center) for center in a.centers])[2]
    end
    table = zeros(Int, a.k + 1, a.k)
    moved = String[]
    stayed = new = 0
    for (customer, label) in zip(a.customers, a.labels)
        origin = get(origins, customer.id, a.k + 1)
        table[origin, label] += 1
        if origin == a.k + 1
            new += 1
        elseif origin == label
            stayed += 1
        else
            push!(moved, "$(customer.id) $origin $label")
        end
    end
    lost = count(id -> !haskey(a.numbers, id), keys(origins))
    migration = ["migration day $(p.snapshot_day) customers $(length(origins))", "from\\to " * join(1:a.k, " ")]
    for origin in 1:a.k+1
        label = origin == a.k + 1 ? "none" : string(origin)
        push!(migration, "$label " * join(table[origin, :], " "))
    end
    push!(migration, "moved_customers")
    append!(migration, moved)
    push!(migration, "stayed $stayed moved $(length(moved)) new $new lost $lost")
    first, last = p.reference_day + 1, p.reference_day + p.outcome_days
    purchases = orders_by_customer([order for order in group_orders(a.data.valid_rows, first, last) if order.net > 0])
    outcome = ["outcome days $first $last"]
    for (segment, customers) in enumerate(a.segment_customers)
        buyers = spend = 0
        for customer in customers
            if haskey(purchases, customer.id)
                buyers += 1
                spend += sum(order.net for order in purchases[customer.id])
            end
        end
        size = length(customers)
        push!(outcome, "segment $segment $(a.names[segment]) size $size buyers $buyers rate $(real_text(buyers / size)) revenue $(amount(spend)) per_customer $(real_text((spend / 100) / size))")
    end
    outsiders = [id for id in keys(purchases) if !haskey(a.numbers, id)]
    outsider_spend = sum((order.net for id in outsiders for order in purchases[id]); init=0)
    push!(outcome, "unsegmented buyers $(length(outsiders)) revenue $(amount(outsider_spend))")
    join_blocks([periods, migration, outcome])
end

function summary_lines(a)
    used = [row for row in a.data.valid_rows if row.day <= a.params.reference_day]
    valid = count(order -> order.net > 0, a.reference_orders)
    excluded = sort([id for id in a.data.customers if !haskey(a.numbers, id)])
    excluded_text = isempty(excluded) ? "-" : join(excluded, " ")
    data = ["rows $(a.data.row_count) duplicates $(a.data.duplicates) zero $(a.data.free) used $(length(used)) returns $(count(row -> row.amount < 0, used)) later $(count(row -> row.day > a.params.reference_day, a.data.valid_rows))",
        "orders $(length(a.reference_orders)) valid $valid cancelled $(length(a.reference_orders) - valid)", "customers $(length(a.data.customers)) clustered $(a.n) excluded $(length(excluded))", "excluded_ids $excluded_text"]
    categories = String[]
    for category in a.category_names
        total = a.overall_categories[category]
        buyers = count(customer -> get(customer.category_spend, category, 0) > 0, a.customers)
        push!(categories, "category $category revenue $(amount(total)) share $(real_text(total / a.total_spend)) customers $buyers")
    end
    features, correlations = String[], ["correlation " * join(FEATURE_NAMES, " ")]
    raw = raw_values.(a.customers)
    for (feature, name) in enumerate(FEATURE_NAMES)
        column = [values[feature] for values in raw]
        transform = SQRT_FEATURES[feature] ? "sqrt" : "none"
        push!(features, "feature $name transform $transform raw_mean $(real_text(mean(column))) raw_sd $(real_text(sample_sd(column))) mean $(real_text(a.means[feature])) sd $(real_text(a.sds[feature]))")
        push!(correlations, name * " " * reals([correlation(a.points, feature, second) for second in eachindex(FEATURE_NAMES)]))
    end
    join_blocks([data, categories, features, correlations])
end

function main()
    a = analyze(read_params(joinpath("input", "params.txt")), read_transactions(joinpath("input", "transactions.csv")), read_rules(joinpath("input", "segment_rules.txt")))
    mkpath("output")
    for (name, lines) in [("features.csv", features_lines(a)), ("runs.txt", runs_lines(a)), ("selection.txt", selection_lines(a)), ("segments.csv", segments_lines(a)),
        ("profiles.txt", profiles_lines(a)), ("robustness.txt", robustness_lines(a)), ("tracking.txt", tracking_lines(a)), ("summary.txt", summary_lines(a))]
        write_lines(joinpath("output", name), lines)
    end
end

main()
