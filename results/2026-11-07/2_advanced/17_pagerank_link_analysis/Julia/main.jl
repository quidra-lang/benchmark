include("graph_io.jl")
include("components.jl")
include("pagerank.jl")
include("hits.jl")
include("report.jl")

const REGIONS = ["CORE", "IN", "OUT", "TUBE", "IN_TENDRIL", "OUT_TENDRIL", "OTHER"]
const QUANTITIES = ["in_degree", "pagerank", "cheirank", "authority", "hub", "trustrank", "harmonic"]
line(parts...) = join(parts, " ")
ordered_sum(values) = foldl(+, values; init=0.0)
rank_order(values) = sort(collect(eachindex(values)); by=node -> (-scaled(values[node]), node))
top_list(values, limit) = first([node for node in rank_order(values) if scaled(values[node]) > 0], min(limit, count(value -> scaled(value) > 0, values)))

function positions(order)
    ranks = zeros(Int, length(order))
    for (position, node) in enumerate(order)
        ranks[node] = position
    end
    ranks
end

function joined_blocks(blocks)
    lines = String[]
    for block in blocks
        !isempty(lines) && push!(lines, "")
        append!(lines, block)
    end
    lines
end

function distribution(values)
    counts = Dict{Int,Int}()
    for value in values
        counts[value] = get(counts, value, 0) + 1
    end
    [line(value, counts[value]) for value in sort(collect(keys(counts)))]
end

function graph_data(input)
    pages = input.pages
    n = length(pages)
    index_of = Dict(page.id => node for (node, page) in enumerate(pages))
    accepted, ignored = Set{Tuple{Int,Int}}(), Tuple{Int,Int,Int,String}[]
    for (number, source, target) in input.records
        if !haskey(index_of, source) || !haskey(index_of, target)
            push!(ignored, (number, source, target, "unknown"))
        elseif source == target
            push!(ignored, (number, source, target, "self"))
        elseif (index_of[source], index_of[target]) in accepted
            push!(ignored, (number, source, target, "duplicate"))
        else
            push!(accepted, (index_of[source], index_of[target]))
        end
    end
    links = sort(collect(accepted))
    successors, predecessors = [Int[] for _ in pages], [Int[] for _ in pages]
    for (source, target) in links
        push!(successors[source], target)
        push!(predecessors[target], source)
    end
    forward = [[(source, 1) for source in sources] for sources in predecessors]
    reverse = [[(target, 1) for target in targets] for targets in successors]
    inter = [(u, v) for (u, v) in links if pages[u].host != pages[v].host]
    (; pages, n, index_of, links, accepted, ignored, successors, predecessors, forward, reverse, inter)
end

function undirected_data(g)
    adjacent = [Set{Int}() for _ in 1:g.n]
    for (u, v) in g.links
        push!(adjacent[u], v)
        push!(adjacent[v], u)
    end
    neighbors = [sort(collect(group)) for group in adjacent]
    closed = possible = eligible = 0
    local_sum = 0.0
    for group in neighbors
        degree = length(group)
        degree < 2 && continue
        own = count(group[j] in adjacent[group[i]] for i in eachindex(group) for j in i+1:length(group))
        choices = div(degree * (degree - 1), 2)
        closed += own
        possible += choices
        eligible += 1
        local_sum += own / choices
    end
    remaining, removed, kcore = length.(neighbors), falses(g.n), zeros(Int, g.n)
    level, left = 0, g.n
    while left > 0
        node = findfirst(i -> !removed[i] && remaining[i] <= level, 1:g.n)
        if isnothing(node)
            level += 1
            continue
        end
        removed[node] = true
        kcore[node] = level
        left -= 1
        for child in neighbors[node]
            !removed[child] && (remaining[child] -= 1)
        end
    end
    weak = weak_components(neighbors)
    (; neighbors, edges=div(sum(length.(neighbors)), 2), closed, possible, eligible, clustering=local_sum / eligible,
        kcore, degeneracy=maximum(kcore), weak_count=maximum(weak), weak_largest=maximum(count(==(label), weak) for label in unique(weak)))
end

function component_data(g)
    groups = sort([sort(group) for group in strong_components(g.successors)]; by=first)
    labels = zeros(Int, g.n)
    for (number, group) in enumerate(groups)
        labels[group] .= number
    end
    incoming, outgoing, edges = zeros(Int, length(groups)), zeros(Int, length(groups)), Set{Tuple{Int,Int}}()
    for (u, v) in g.links
        first, second = labels[u], labels[v]
        if first != second
            outgoing[first] += 1
            incoming[second] += 1
            push!(edges, (first, second))
        end
    end
    successors, pending, depths = [Int[] for _ in groups], zeros(Int, length(groups)), zeros(Int, length(groups))
    for (u, v) in sort(collect(edges))
        push!(successors[u], v)
        pending[v] += 1
    end
    ready = findall(==(0), pending)
    while !isempty(ready)
        node = pop!(ready)
        for child in successors[node]
            depths[child] = max(depths[child], depths[node] + 1)
            pending[child] -= 1
            pending[child] == 0 && push!(ready, child)
        end
    end
    core = findmax(length.(groups))[2]
    (; groups, labels, incoming, outgoing, edge_count=length(edges), depth=maximum(depths), core, singletons=count(group -> length(group) == 1, groups))
end

function bowtie(g, table)
    core = table.groups[table.core]
    forward, backward = reachable(g.successors, core), reachable(g.predecessors, core)
    regions = [node in core ? 1 : backward[node] ? 2 : forward[node] ? 3 : 7 for node in 1:g.n]
    from_in = reachable(g.successors, findall(==(2), regions))
    to_out = reachable(g.predecessors, findall(==(3), regions))
    for node in 1:g.n
        regions[node] != 7 && continue
        regions[node] = from_in[node] ? (to_out[node] ? 4 : 5) : to_out[node] ? 6 : 7
    end
    regions
end

function distance_data(g)
    pairs = total = diameter = 0
    diameter_pair = (1, 1)
    histogram, harmonic = zeros(Int, g.n), zeros(g.n)
    for source in 1:g.n
        distances = bfs_distances(g.successors, [source])
        for target in 1:g.n
            steps = distances[target]
            (source == target || steps < 0) && continue
            pairs += 1
            total += steps
            histogram[steps] += 1
            harmonic[target] += 1 / steps
            if steps > diameter
                diameter, diameter_pair = steps, (source, target)
            end
        end
    end
    effective, cumulative = diameter, 0
    for steps in 1:diameter
        cumulative += histogram[steps]
        if 10 * cumulative >= 9 * pairs
            effective = steps
            break
        end
    end
    (; pairs, total, diameter, diameter_pair, histogram, harmonic, effective)
end

function kendall(first, second)
    numerator, n = 0, length(first)
    for i in 1:n, j in i+1:n
        dx, dy = first[i] - first[j], second[i] - second[j]
        (dx == 0 || dy == 0) && continue
        numerator += (dx > 0) == (dy > 0) ? 1 : -1
    end
    fraction(numerator, div(n * (n - 1), 2))
end

function salsa(n, links)
    degree, targets, neighbors = zeros(Int, n), [Int[] for _ in 1:n], [Int[] for _ in 1:n]
    for (u, v) in links
        degree[v] += 1
        push!(targets[u], v)
    end
    for group in targets, i in 1:length(group)-1
        first, second = group[i], group[i + 1]
        push!(neighbors[first], second)
        push!(neighbors[second], first)
    end
    labels = weak_components(neighbors)
    side = findall(>(0), degree)
    sizes, masses, values = zeros(Int, n), zeros(Int, n), zeros(n)
    for node in side
        sizes[labels[node]] += 1
        masses[labels[node]] += degree[node]
    end
    for node in side
        values[node] = (sizes[labels[node]] * degree[node]) / (length(side) * masses[labels[node]])
    end
    values
end

function run_pagerank(edges, teleport, damping, p)
    power_iteration(edges, teleport, damping, p.iterations, p.tolerance)
end

function analyze(input)
    p, g = input.settings, graph_data(input)
    u, table = undirected_data(g), component_data(g)
    regions, distances = bowtie(g, table), distance_data(g)
    everyone = collect(1:g.n)
    trusted = sort([g.index_of[id] for id in p.trusted])
    pr = run_pagerank(g.forward, everyone, p.damping, p)
    cr = run_pagerank(g.reverse, everyone, p.damping, p)
    tr = run_pagerank(g.forward, trusted, p.damping, p)
    authority, hub = hits(g.n, everyone, g.inter, p.hits_iterations)
    order, rank, cheirank_rank = rank_order(pr.values), positions(rank_order(pr.values)), positions(rank_order(cr.values))
    trust_ratio = tr.values ./ pr.values
    trust_distance = bfs_distances(g.successors, trusted)
    suspects = [node for node in first(order, min(p.spam_top, g.n)) if scaled(trust_ratio[node], 4) / 10000 < p.spam_threshold]
    suspect_hosts = sort(unique([g.pages[node].host for node in suspects]))
    demoted, removed = nothing, 0
    if !isempty(suspects)
        kept = [(a, b) for (a, b) in g.links if !(g.pages[a].host == g.pages[b].host && g.pages[a].host in suspect_hosts)]
        edges = [Tuple{Int,Int}[] for _ in everyone]
        for (a, b) in kept
            push!(edges[b], (a, 1))
        end
        demoted = run_pagerank(edges, everyone, p.damping, p)
        removed = length(g.links) - length(kept)
    end
    sweeps = [(; damping, run=run_pagerank(g.forward, everyone, damping, p)) for damping in p.sweep]
    results = [query_result(query, g, p, order, rank, pr.values) for query in input.queries]
    hosts = host_data(g, p)
    (; input, p, g, u, table, regions, distances, pr, cr, tr, authority, hub, order, rank, cheirank_rank, trust_ratio, trust_distance,
        suspects, suspect_hosts, demoted, removed, sweeps, results, hosts)
end

function query_result(query, g, p, order, rank, pagerank)
    include = [word for word in query.words if !startswith(word, "-")]
    exclude = [word[2:end] for word in query.words if startswith(word, "-")]
    matches = [node for node in order if all(word in g.pages[node].words for word in include) && !any(word in g.pages[node].words for word in exclude)]
    root = first(matches, min(p.root_limit, length(matches)))
    in_base = falses(g.n)
    for node in root
        in_base[node] = true
        for group in (g.successors[node], g.predecessors[node]), child in first(group, min(p.neighbor_limit, length(group)))
            in_base[child] = true
        end
    end
    base = findall(in_base)
    inside = [(a, b) for (a, b) in g.links if in_base[a] && in_base[b]]
    links = [(a, b) for (a, b) in inside if g.pages[a].host != g.pages[b].host]
    seeds = sort([g.index_of[id] for id in query.seeds])
    personalized = run_pagerank(g.forward, seeds, p.damping, p)
    top = top_list(personalized.values, p.top_k)
    sub = nothing
    if !isempty(links)
        authority, hub = hits(g.n, base, links, p.hits_iterations)
        sa, sh = salsa(g.n, links), salsa(g.n, [(b, a) for (a, b) in links])
        at, ht, sat, sht = [top_list(values, p.top_k) for values in (authority, hub, sa, sh)]
        cited, citing = at[1], ht[1]
        cocitation, coupling = zeros(Int, g.n), zeros(Int, g.n)
        for source in g.predecessors[cited], target in g.successors[source]
            target != cited && (cocitation[target] += 1)
        end
        for target in g.successors[citing], source in g.predecessors[target]
            source != citing && (coupling[source] += 1)
        end
        ranked_counts(values) = first(sort(findall(>(0), values); by=node -> (-values[node], node)), min(p.top_k, count(>(0), values)))
        sub = (; authority, hub, sa, sh, at, ht, sat, sht, cited, citing, cocitation, coupling,
            related=ranked_counts(cocitation), similar=ranked_counts(coupling))
    end
    (; query, matches, root, base, links, dropped=length(inside) - length(links), personalized, top,
        reach=count(reachable(g.successors, seeds)), seed_mass=ordered_sum(personalized.values[seeds]), global_overlap=count(node -> rank[node] <= p.top_k, top), sub)
end

function host_data(g, p)
    names = sort(unique([page.host for page in g.pages]))
    index = Dict(name => number for (number, name) in enumerate(names))
    of_page = [index[page.host] for page in g.pages]
    n = length(names)
    members = [findall(==(number), of_page) for number in 1:n]
    weights, internal, outgoing, incoming = zeros(Int, n, n), zeros(Int, n), zeros(Int, n), zeros(Int, n)
    for (u, v) in g.links
        a, b = of_page[u], of_page[v]
        if a == b
            internal[a] += 1
        else
            weights[a, b] += 1
            outgoing[a] += 1
            incoming[b] += 1
        end
    end
    edges = [(a, b) for a in 1:n for b in 1:n if weights[a, b] > 0]
    adjacency = [[b for b in 1:n if weights[a, b] > 0] for a in 1:n]
    groups = strong_components(adjacency)
    in_edges = [[(a, weights[a, b]) for a in 1:n if weights[a, b] > 0] for b in 1:n]
    run = run_pagerank(in_edges, collect(1:n), p.damping, p)
    heavy = first(sort(edges; by=edge -> (-weights[edge...], edge...)), min(p.top_k, length(edges)))
    (; names, members, weights, internal, outgoing, incoming, edges, reciprocal=count(weights[b, a] > 0 for (a, b) in edges),
        component_count=length(groups), largest=maximum(length.(groups)), run, rank=positions(rank_order(run.values)), heavy)
end

ids(g, nodes) = [g.pages[node].id for node in nodes]
describe(g, position, node, values...) = line(position, g.pages[node].id, values..., g.pages[node].host, g.pages[node].title)
rank_lines(g, nodes, values) = [describe(g, rank, node, fixed(values[node])) for (rank, node) in enumerate(nodes)]
representative(a, members) = members[findmin(a.rank[members])[2]]

function graph_stats(a)
    g, u, t, d = a.g, a.u, a.table, a.distances
    ind, outd = length.(g.predecessors), length.(g.successors)
    intra = count(g.pages[x].host == g.pages[y].host for (x, y) in g.links)
    lines = [line("pages", g.n), line("hosts", length(a.hosts.names)), line("link_rows", length(a.input.records)), line("links", length(g.links))]
    append!(lines, [line("ignored_$reason", count(record -> record[4] == reason, g.ignored)) for reason in ("unknown", "self", "duplicate")])
    append!(lines, [line("ignored line", number, "$source,$target", reason) for (number, source, target, reason) in g.ignored])
    append!(lines, [line("intra_host_links", intra), line("inter_host_links", length(g.links) - intra), line("mean_degree", fixed(length(g.links) / g.n, 4)),
        line("reciprocity", fraction(count((v, u) in g.accepted for (u, v) in g.links), length(g.links)))])
    for (name, values) in (("dangling", outd), ("no_in_links", ind))
        nodes = findall(==(0), values)
        push!(lines, line(name, length(nodes), ids(g, nodes)...))
    end
    for (name, values) in (("in", ind), ("out", outd))
        largest = maximum(values)
        push!(lines, line("max_$(name)_degree", largest, "pages", ids(g, findall(==(largest), values))...))
    end
    append!(lines, ["", "in_degree_distribution", distribution(ind)..., "", "out_degree_distribution", distribution(outd)..., "",
        line("undirected_links", u.edges), line("transitivity", fraction(u.closed, u.possible)), line("average_clustering", fixed(u.clustering, 4), "pages", u.eligible),
        line("degeneracy", u.degeneracy, "pages", count(==(u.degeneracy), u.kcore)), "core_distribution", distribution(u.kcore)..., "",
        line("strong_components", length(t.groups), "largest", length(t.groups[t.core]), "singletons", t.singletons, "condensation_links", t.edge_count),
        line("weak_components", u.weak_count, "largest", u.weak_largest), line("condensation_depth", t.depth)])
    for (number, group) in enumerate(t.groups)
        length(group) < 2 && continue
        push!(lines, line("scc", number, "size", length(group), "min", g.pages[group[1]].id, "incoming", t.incoming[number], "outgoing", t.outgoing[number], "pagerank", fixed(ordered_sum(a.pr.values[group]))) * (t.outgoing[number] == 0 ? " sink" : ""))
    end
    append!(lines, ["", line("bowtie core_scc", t.core)])
    for (region, name) in enumerate(REGIONS)
        members = findall(==(region), a.regions)
        own = line(name, length(members), "pagerank", fixed(ordered_sum(a.pr.values[members])))
        !isempty(members) && (own *= line(" top", g.pages[representative(a, members)].id))
        1 <= length(members) <= 10 && (own *= line(" pages", ids(g, members)...))
        push!(lines, own)
    end
    counts = zeros(Int, 7, 7)
    for (source, target) in g.links
        counts[a.regions[source], a.regions[target]] += 1
    end
    push!(lines, "region_links")
    for first in 1:7, second in 1:7
        counts[first, second] > 0 && push!(lines, line(REGIONS[first], REGIONS[second], counts[first, second]))
    end
    source, target = d.diameter_pair
    append!(lines, ["", "distances", line("reachable_pairs", d.pairs), line("average", fraction(d.total, d.pairs)),
        line("diameter", d.diameter, "from", g.pages[source].id, "to", g.pages[target].id), line("effective_diameter", d.effective)])
    append!(lines, [line(steps, d.histogram[steps]) for steps in 1:d.diameter])
    lines
end

function pagerank_csv(a)
    lines = ["id,in_degree,out_degree,scc,region,kcore,harmonic,pagerank,pagerank_rank,cheirank,cheirank_rank,authority,hub,trustrank,trust_ratio,trust_distance"]
    for node in 1:a.g.n
        push!(lines, join([a.g.pages[node].id, length(a.g.predecessors[node]), length(a.g.successors[node]), a.table.labels[node], REGIONS[a.regions[node]], a.u.kcore[node],
            fixed(a.distances.harmonic[node]), fixed(a.pr.values[node]), a.rank[node], fixed(a.cr.values[node]), a.cheirank_rank[node], fixed(a.authority[node]), fixed(a.hub[node]),
            fixed(a.tr.values[node]), fixed(a.trust_ratio[node], 4), a.trust_distance[node]], ','))
    end
    lines
end

function rankings(a)
    p, g = a.p, a.g
    values = [a.pr.values, a.cr.values, a.authority, a.hub, a.tr.values, a.distances.harmonic]
    blocks = Vector{String}[]
    for (name, scores) in zip(QUANTITIES[2:end], values)
        own = [line(name, "top", p.top_k); rank_lines(g, top_list(scores, p.top_k), scores)]
        if name == "pagerank"
            push!(own, line("dangling_mass", fixed(ordered_sum(a.pr.values[findall(isempty, g.successors)]))))
            contribution(source) = (p.damping * a.pr.values[source]) / length(g.successors[source])
            for node in top_list(scores, p.top_k)
                contributors = sort(g.predecessors[node]; by=source -> (-scaled(contribution(source)), source))
                push!(own, line("contributors", g.pages[node].id, [line(g.pages[source].id, fixed(contribution(source))) for source in first(contributors, min(3, length(contributors)))]...))
            end
        end
        push!(blocks, own)
    end
    quantities = [length.(g.predecessors), [scaled.(scores) for scores in values]...]
    correlation = ["correlation"]
    for i in 1:7, j in i+1:7
        push!(correlation, line(QUANTITIES[i], QUANTITIES[j], kendall(quantities[i], quantities[j])))
    end
    push!(blocks, correlation)
    sweep_lines = ["damping_sweep"]
    for sweep in a.sweeps
        order = rank_order(sweep.run.values)
        ranks = positions(order)
        shift = findmax(abs.(ranks .- a.rank))[2]
        push!(sweep_lines, line("damping", fixed(sweep.damping, 4), "overlap", count(node -> ranks[node] <= p.top_k && a.rank[node] <= p.top_k, 1:g.n),
            "footrule", sum(abs.(ranks .- a.rank)), "kendall", kendall(scaled.(a.pr.values), scaled.(sweep.run.values)), "largest_shift", g.pages[shift].id, a.rank[shift], ranks[shift]),
            line("top", ids(g, first(order, min(p.top_k, g.n)))...))
    end
    push!(blocks, sweep_lines)
    spam = [line("spam top", p.spam_top, "threshold", fixed(p.spam_threshold, 4))]
    for node in a.suspects
        push!(spam, line("suspect", g.pages[node].id, "rank", a.rank[node], "pagerank", fixed(a.pr.values[node]), "trustrank", fixed(a.tr.values[node]),
            "trust_ratio", fixed(a.trust_ratio[node], 4), "trust_distance", a.trust_distance[node], "kcore", a.u.kcore[node], g.pages[node].host))
    end
    append!(spam, [line("count", length(a.suspects)), "trust_by_distance"])
    distances = sort(unique(filter(>=(0), a.trust_distance)))
    -1 in a.trust_distance && push!(distances, -1)
    for distance in distances
        members = findall(==(distance), a.trust_distance)
        push!(spam, line(distance == -1 ? "unreachable" : distance, "pages", length(members), "trustrank", fixed(ordered_sum(a.tr.values[members])), "pagerank", fixed(ordered_sum(a.pr.values[members]))))
    end
    push!(blocks, spam)
    demotion = ["demotion none"]
    if !isnothing(a.demoted)
        demotion = [line("demotion hosts", a.suspect_hosts..., "removed_links", a.removed)]
        ranks = positions(rank_order(a.demoted.values))
        append!(demotion, [describe(g, rank, node, fixed(a.demoted.values[node]), "was", a.rank[node]) for (rank, node) in enumerate(top_list(a.demoted.values, p.top_k))])
        append!(demotion, [line("suspect", g.pages[node].id, "before", a.rank[node], "after", ranks[node]) for node in a.suspects])
    end
    push!(blocks, demotion)
    h = a.hosts
    host = [line("host_graph hosts", length(h.names), "links", length(h.edges), "reciprocal", h.reciprocal, "strong_components", h.component_count, "largest", h.largest), line("host_links top", p.top_k)]
    append!(host, [line(h.names[u], h.names[v], h.weights[u, v]) for (u, v) in h.heavy])
    push!(blocks, host)
    joined_blocks(blocks)
end

function convergence(a)
    p = a.p
    damping = fixed(p.damping, 4)
    runs = [("pagerank damping $damping", a.pr), ("cheirank damping $damping", a.cr), ("trustrank damping $damping seeds $(length(p.trusted))", a.tr)]
    append!(runs, [("sweep damping $(fixed(s.damping, 4))", s.run) for s in a.sweeps])
    !isnothing(a.demoted) && push!(runs, ("demoted damping $damping", a.demoted))
    append!(runs, [("personalized query $(r.query.number) damping $damping", r.personalized) for r in a.results])
    push!(runs, ("host_pagerank damping $damping hosts $(length(a.hosts.names))", a.hosts.run))
    lines = [line("iterations", p.iterations, "tolerance", fixed(p.tolerance, 10))]
    for (heading, run) in runs
        append!(lines, ["", heading])
        append!(lines, [line("iteration", step, "l1", fixed(run.changes[step], 10)) for step in 10:10:p.iterations])
        push!(lines, line("converged_at", run.converged == 0 ? "none" : run.converged))
    end
    lines
end

function query_lines(a, result)
    g, p, q = a.g, a.p, result.query
    lines = [line("query", q.number, "words", q.words..., "seeds", q.seeds...), line("matched", length(result.matches), "root", length(result.root), "base", length(result.base),
        "links", length(result.links), "dropped_intra_host", result.dropped), "results"]
    append!(lines, rank_lines(g, first(result.matches, min(p.top_k, length(result.matches))), a.pr.values))
    push!(lines, line("personalized reach", result.reach, "seed_mass", fixed(result.seed_mass)))
    append!(lines, rank_lines(g, result.top, result.personalized.values))
    push!(lines, line("overlap_with_global", result.global_overlap))
    if isnothing(result.sub)
        push!(lines, "hits none")
        return lines
    end
    s = result.sub
    for (heading, top, values) in (("hits authorities", s.at, s.authority), ("hits hubs", s.ht, s.hub), ("salsa authorities", s.sat, s.sa), ("salsa hubs", s.sht, s.sh))
        push!(lines, heading)
        append!(lines, rank_lines(g, top, values))
    end
    push!(lines, line("hits_salsa_overlap authorities", length(intersect(s.at, s.sat)), "hubs", length(intersect(s.ht, s.sht)), "authority_hosts", length(unique([g.pages[node].host for node in s.at]))),
        line("related_to", g.pages[s.cited].id, "citing", length(g.predecessors[s.cited])))
    append!(lines, [describe(g, rank, node, s.cocitation[node]) for (rank, node) in enumerate(s.related)])
    push!(lines, line("coupled_to", g.pages[s.citing].id, "cited", length(g.successors[s.citing])))
    append!(lines, [describe(g, rank, node, s.coupling[node]) for (rank, node) in enumerate(s.similar)])
    lines
end

function hosts_csv(a)
    h, g = a.hosts, a.g
    lines = ["host,pages,core_pages,internal_links,internal_density,outgoing_links,incoming_links,dangling_pages,page_score_sum,top_page,score,rank"]
    for (number, name) in enumerate(h.names)
        members = h.members[number]
        size = length(members)
        density = size >= 2 ? h.internal[number] / (size * (size - 1)) : 0.0
        push!(lines, join([name, size, count(node -> a.regions[node] == 1, members), h.internal[number], fixed(density, 4), h.outgoing[number], h.incoming[number],
            count(node -> isempty(g.successors[node]), members), fixed(ordered_sum(a.pr.values[members])), g.pages[representative(a, members)].id, fixed(h.run.values[number]), h.rank[number]], ','))
    end
    lines
end

function main()
    a = analyze(read_input("input"))
    mkpath("output")
    outputs = [("graph_stats.txt", graph_stats(a)), ("pagerank.csv", pagerank_csv(a)), ("rankings.txt", rankings(a)), ("convergence.txt", convergence(a)),
        ("queries.txt", joined_blocks([query_lines(a, result) for result in a.results])), ("hosts.csv", hosts_csv(a))]
    for (name, lines) in outputs
        write_lines(joinpath("output", name), lines)
    end
end

main()
