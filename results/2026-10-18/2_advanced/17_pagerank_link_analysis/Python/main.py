import os

from components import bfs_distances, reachable, strong_components, weak_components
from graph_io import read_input
from hits import hits
from pagerank import power_iteration
from report import fixed, fraction, scaled, write_lines


INPUT_DIR = "input"
OUTPUT_DIR = "output"
REGIONS = ("CORE", "IN", "OUT", "TUBE", "IN_TENDRIL", "OUT_TENDRIL", "OTHER")
CORE, IN, OUT, TUBE, IN_TENDRIL, OUT_TENDRIL, OTHER = range(len(REGIONS))
QUANTITIES = ("in_degree", "pagerank", "cheirank", "authority", "hub", "trustrank", "harmonic")
CONTRIBUTOR_LIMIT = 3
REGION_LIST_LIMIT = 10
PAGERANK_HEADER = (
    "id,in_degree,out_degree,scc,region,kcore,harmonic,pagerank,pagerank_rank,"
    "cheirank,cheirank_rank,authority,hub,trustrank,trust_ratio,trust_distance"
)
HOSTS_HEADER = (
    "host,pages,core_pages,internal_links,internal_density,outgoing_links,"
    "incoming_links,dangling_pages,page_score_sum,top_page,score,rank"
)


def line(*parts):
    return " ".join(str(part) for part in parts)


def total(values):
    result = 0.0
    for value in values:
        result += value
    return result


def joined_blocks(blocks):
    lines = []
    for block in blocks:
        if lines:
            lines.append("")
        lines.extend(block)
    return lines


def rank_order(values):
    return sorted(range(len(values)), key=lambda node: (-scaled(values[node]), node))


def positions(order):
    rank = [0] * len(order)
    for position, node in enumerate(order, 1):
        rank[node] = position
    return rank


def top_list(values, limit):
    return [node for node in rank_order(values) if scaled(values[node]) > 0][:limit]


def ranked_counts(counts, limit):
    nodes = [node for node in range(len(counts)) if counts[node] > 0]
    nodes.sort(key=lambda node: (-counts[node], node))
    return nodes[:limit]


def distribution(values):
    counts = {}
    for value in values:
        counts[value] = counts.get(value, 0) + 1
    return sorted(counts.items())


def run_pagerank(edges, teleport, damping, settings):
    return power_iteration(edges, teleport, damping, settings.iterations, settings.tolerance)


def classify_links(records, index_of):
    accepted = set()
    ignored = []
    for record in records:
        if record.source not in index_of or record.target not in index_of:
            ignored.append((record, "unknown"))
            continue
        link = index_of[record.source], index_of[record.target]
        if link[0] == link[1]:
            ignored.append((record, "self"))
        elif link in accepted:
            ignored.append((record, "duplicate"))
        else:
            accepted.add(link)
    return accepted, ignored


class Graph:
    def __init__(self, pages, links):
        self.pages = pages
        self.count = len(pages)
        self.links = sorted(links)
        self.link_set = set(self.links)
        self.successors = [[] for _ in pages]
        self.predecessors = [[] for _ in pages]
        for source, target in self.links:
            self.successors[source].append(target)
            self.predecessors[target].append(source)

    def host(self, node):
        return self.pages[node].host

    def intra_host(self, source, target):
        return self.host(source) == self.host(target)

    def inter_host_links(self, links=None):
        links = self.links if links is None else links
        return [
            (source, target) for source, target in links if not self.intra_host(source, target)
        ]

    def dangling(self):
        return [node for node in range(self.count) if not self.successors[node]]

    def ident(self, node):
        return self.pages[node].ident

    def forward_edges(self):
        return [[(source, 1) for source in sources] for sources in self.predecessors]

    def reverse_edges(self):
        return [[(target, 1) for target in targets] for targets in self.successors]

    def ids(self, nodes):
        return [self.ident(node) for node in nodes]

    def describe(self, position, node, *values):
        page = self.pages[node]
        return line(position, page.ident, *values, page.host, page.title)


def kcore_numbers(adjacent):
    count = len(adjacent)
    remaining = [len(group) for group in adjacent]
    removed = [False] * count
    core = [0] * count
    level = 0
    left = count
    while left > 0:
        candidate = next(
            (node for node in range(count) if not removed[node] and remaining[node] <= level),
            None,
        )
        if candidate is None:
            level += 1
            continue
        removed[candidate] = True
        core[candidate] = level
        left -= 1
        for neighbor in adjacent[candidate]:
            if not removed[neighbor]:
                remaining[neighbor] -= 1
    return core


class Undirected:
    def __init__(self, graph):
        self.adjacent = [set() for _ in range(graph.count)]
        for source, target in graph.links:
            self.adjacent[source].add(target)
            self.adjacent[target].add(source)
        self.neighbors = [sorted(group) for group in self.adjacent]
        self.edge_count = sum(len(group) for group in self.neighbors) // 2
        self.closed = 0
        self.possible = 0
        self.eligible = 0
        local_sum = 0.0
        for neighbors in self.neighbors:
            degree = len(neighbors)
            if degree < 2:
                continue
            closed = self.closed_pairs(neighbors)
            possible = degree * (degree - 1) // 2
            self.closed += closed
            self.possible += possible
            self.eligible += 1
            local_sum += closed / possible
        self.average_clustering = local_sum / self.eligible
        self.kcore = kcore_numbers(self.adjacent)
        self.degeneracy = max(self.kcore)
        labels = weak_components(self.neighbors)
        sizes = [0] * graph.count
        for label in labels:
            sizes[label] += 1
        self.weak_count = max(labels) + 1
        self.weak_largest = max(sizes)

    def closed_pairs(self, neighbors):
        count = 0
        for position, first in enumerate(neighbors):
            for second in neighbors[position + 1:]:
                if second in self.adjacent[first]:
                    count += 1
        return count


def longest_path(count, edges):
    successors = [[] for _ in range(count)]
    pending = [0] * count
    for source, target in edges:
        successors[source].append(target)
        pending[target] += 1
    length = [0] * count
    ready = [node for node in range(count) if pending[node] == 0]
    while ready:
        node = ready.pop()
        for target in successors[node]:
            length[target] = max(length[target], length[node] + 1)
            pending[target] -= 1
            if pending[target] == 0:
                ready.append(target)
    return max(length)


class ComponentTable:
    def __init__(self, graph):
        groups = [sorted(group) for group in strong_components(graph.successors)]
        groups.sort(key=lambda group: group[0])
        self.groups = groups
        self.label = [0] * graph.count
        for number, group in enumerate(groups):
            for node in group:
                self.label[node] = number
        self.incoming = [0] * len(groups)
        self.outgoing = [0] * len(groups)
        edges = set()
        for source, target in graph.links:
            first, second = self.label[source], self.label[target]
            if first != second:
                self.outgoing[first] += 1
                self.incoming[second] += 1
                edges.add((first, second))
        self.edge_count = len(edges)
        self.depth = longest_path(len(groups), edges)
        self.core = 0
        for number, group in enumerate(groups):
            if len(group) > len(groups[self.core]):
                self.core = number
        self.singletons = sum(1 for group in groups if len(group) == 1)

    def is_sink(self, number):
        return self.outgoing[number] == 0 and len(self.groups[number]) >= 2


def bowtie_regions(graph, core_pages):
    forward = reachable(graph.successors, core_pages)
    backward = reachable(graph.predecessors, core_pages)
    in_core = [False] * graph.count
    for node in core_pages:
        in_core[node] = True
    regions = [OTHER] * graph.count
    for node in range(graph.count):
        if in_core[node]:
            regions[node] = CORE
        elif backward[node]:
            regions[node] = IN
        elif forward[node]:
            regions[node] = OUT
    in_pages = [node for node in range(graph.count) if regions[node] == IN]
    out_pages = [node for node in range(graph.count) if regions[node] == OUT]
    from_in = reachable(graph.successors, in_pages)
    to_out = reachable(graph.predecessors, out_pages)
    for node in range(graph.count):
        if in_core[node] or backward[node] or forward[node]:
            continue
        if from_in[node] and to_out[node]:
            regions[node] = TUBE
        elif from_in[node]:
            regions[node] = IN_TENDRIL
        elif to_out[node]:
            regions[node] = OUT_TENDRIL
    return regions


class DistanceStats:
    def __init__(self, graph):
        count = graph.count
        self.pairs = 0
        self.total = 0
        self.diameter = 0
        self.diameter_pair = None
        self.histogram = [0] * count
        self.harmonic = [0.0] * count
        for source in range(count):
            distance = bfs_distances(graph.successors, [source])
            for target in range(count):
                steps = distance[target]
                if target == source or steps < 0:
                    continue
                self.pairs += 1
                self.total += steps
                self.histogram[steps] += 1
                self.harmonic[target] += 1 / steps
                if steps > self.diameter:
                    self.diameter = steps
                    self.diameter_pair = source, target

    def effective_diameter(self):
        reached = 0
        for steps in range(1, self.diameter + 1):
            reached += self.histogram[steps]
            if 10 * reached >= 9 * self.pairs:
                return steps
        return self.diameter


class PageScores:
    def __init__(self, graph, settings, trusted, harmonic):
        everyone = list(range(graph.count))
        self.damping = settings.damping
        self.pagerank_run = run_pagerank(graph.forward_edges(), everyone, self.damping, settings)
        self.cheirank_run = run_pagerank(graph.reverse_edges(), everyone, self.damping, settings)
        self.trustrank_run = run_pagerank(graph.forward_edges(), trusted, self.damping, settings)
        self.pagerank = self.pagerank_run.values
        self.cheirank = self.cheirank_run.values
        self.trustrank = self.trustrank_run.values
        self.order = rank_order(self.pagerank)
        self.rank = positions(self.order)
        self.cheirank_rank = positions(rank_order(self.cheirank))
        self.trust_ratio = [trust / score for trust, score in zip(self.trustrank, self.pagerank)]
        self.trust_distance = bfs_distances(graph.successors, trusted)
        self.authority, self.hub = hits(
            graph.count, everyone, graph.inter_host_links(), settings.hits_iterations
        )
        self.harmonic = harmonic

    def contribution(self, graph, source):
        return self.damping * self.pagerank[source] / len(graph.successors[source])

    def representative(self, nodes):
        return min(nodes, key=lambda node: self.rank[node])


def kendall(first, second):
    count = len(first)
    concordant = 0
    discordant = 0
    for i in range(count):
        for x, y in zip(first[i + 1:], second[i + 1:]):
            dx = first[i] - x
            dy = second[i] - y
            if dx == 0 or dy == 0:
                continue
            if (dx > 0) == (dy > 0):
                concordant += 1
            else:
                discordant += 1
    return fraction(concordant - discordant, count * (count - 1) // 2)


class SweepResult:
    def __init__(self, damping, graph, scores, settings):
        limit = settings.top_k
        self.damping = damping
        self.run = run_pagerank(graph.forward_edges(), list(range(graph.count)), damping, settings)
        order = rank_order(self.run.values)
        rank = positions(order)
        base = scores.rank
        self.overlap = sum(
            1 for node in range(graph.count) if rank[node] <= limit and base[node] <= limit
        )
        self.footrule = sum(abs(rank[node] - base[node]) for node in range(graph.count))
        self.correlation = kendall(
            [scaled(value) for value in scores.pagerank],
            [scaled(value) for value in self.run.values],
        )
        self.shift = 0
        for node in range(graph.count):
            if abs(rank[node] - base[node]) > abs(rank[self.shift] - base[self.shift]):
                self.shift = node
        self.shift_rank = rank[self.shift]
        self.top = order[:limit]


class SpamReport:
    def __init__(self, graph, scores, settings):
        self.suspects = [
            node for node in scores.order[:settings.spam_top]
            if scaled(scores.trust_ratio[node], 4) / 10000 < settings.spam_threshold
        ]
        self.hosts = sorted({graph.host(node) for node in self.suspects})
        self.removed = 0
        self.run = None
        self.rank = None
        if self.suspects:
            kept = [
                (source, target) for source, target in graph.links
                if not (graph.intra_host(source, target) and graph.host(source) in self.hosts)
            ]
            self.removed = len(graph.links) - len(kept)
            demoted = Graph(graph.pages, kept)
            everyone = list(range(graph.count))
            self.run = run_pagerank(demoted.forward_edges(), everyone, settings.damping, settings)
            self.rank = positions(rank_order(self.run.values))


def trust_distance_groups(trust_distance):
    distances = sorted({value for value in trust_distance if value >= 0})
    if -1 in trust_distance:
        distances.append(-1)
    groups = []
    for value in distances:
        members = [node for node, own in enumerate(trust_distance) if own == value]
        groups.append((value, members))
    return groups


def title_matches(words, include, exclude):
    return all(word in words for word in include) and not any(word in words for word in exclude)


def base_membership(graph, root, limit):
    in_base = [False] * graph.count
    for node in root:
        in_base[node] = True
        for neighbor in graph.successors[node][:limit]:
            in_base[neighbor] = True
        for neighbor in graph.predecessors[node][:limit]:
            in_base[neighbor] = True
    return in_base


def salsa_scores(count, links):
    degree = [0] * count
    targets = [[] for _ in range(count)]
    for source, target in links:
        degree[target] += 1
        targets[source].append(target)
    neighbors = [[] for _ in range(count)]
    for group in targets:
        for first, second in zip(group, group[1:]):
            neighbors[first].append(second)
            neighbors[second].append(first)
    labels = weak_components(neighbors)
    side = [node for node in range(count) if degree[node] > 0]
    size = [0] * count
    mass = [0] * count
    for node in side:
        size[labels[node]] += 1
        mass[labels[node]] += degree[node]
    scores = [0.0] * count
    for node in side:
        label = labels[node]
        scores[node] = (size[label] * degree[node]) / (len(side) * mass[label])
    return scores


def cocitation_counts(graph, page):
    counts = [0] * graph.count
    for citing in graph.predecessors[page]:
        for cited in graph.successors[citing]:
            if cited != page:
                counts[cited] += 1
    return counts


def coupling_counts(graph, page):
    counts = [0] * graph.count
    for cited in graph.successors[page]:
        for citing in graph.predecessors[cited]:
            if citing != page:
                counts[citing] += 1
    return counts


class QueryResult:
    def __init__(self, query, graph, scores, settings, index_of):
        limit = settings.top_k
        include = [word for word in query.words if not word.startswith("-")]
        exclude = [word[1:] for word in query.words if word.startswith("-")]
        self.query = query
        self.matches = [
            node for node in scores.order
            if title_matches(graph.pages[node].words, include, exclude)
        ]
        root = self.matches[:settings.root_limit]
        self.root_size = len(root)
        in_base = base_membership(graph, root, settings.neighbor_limit)
        base = [node for node in range(graph.count) if in_base[node]]
        self.base_size = len(base)
        inside = [
            (source, target) for source, target in graph.links
            if in_base[source] and in_base[target]
        ]
        self.subgraph = graph.inter_host_links(inside)
        self.dropped = len(inside) - len(self.subgraph)
        seeds = sorted(index_of[ident] for ident in query.seeds)
        self.personalized = run_pagerank(graph.forward_edges(), seeds, settings.damping, settings)
        self.reach = sum(reachable(graph.successors, seeds))
        self.seed_mass = total(self.personalized.values[node] for node in seeds)
        self.personalized_top = top_list(self.personalized.values, limit)
        self.global_overlap = sum(
            1 for node in self.personalized_top if scores.rank[node] <= limit
        )
        self.subgraph_scores = None
        if self.subgraph:
            self.subgraph_scores = SubgraphScores(graph, base, self.subgraph, settings)


class SubgraphScores:
    def __init__(self, graph, base, subgraph, settings):
        limit = settings.top_k
        self.authority, self.hub = hits(graph.count, base, subgraph, settings.hits_iterations)
        self.salsa_authority = salsa_scores(graph.count, subgraph)
        reversed_links = [(target, source) for source, target in subgraph]
        self.salsa_hub = salsa_scores(graph.count, reversed_links)
        self.authority_top = top_list(self.authority, limit)
        self.hub_top = top_list(self.hub, limit)
        self.salsa_authority_top = top_list(self.salsa_authority, limit)
        self.salsa_hub_top = top_list(self.salsa_hub, limit)
        self.authority_overlap = len(set(self.authority_top) & set(self.salsa_authority_top))
        self.hub_overlap = len(set(self.hub_top) & set(self.salsa_hub_top))
        self.authority_hosts = len({graph.host(node) for node in self.authority_top})
        self.cited = self.authority_top[0]
        self.cocitation = cocitation_counts(graph, self.cited)
        self.related = ranked_counts(self.cocitation, limit)
        self.citing = self.hub_top[0]
        self.coupling = coupling_counts(graph, self.citing)
        self.similar = ranked_counts(self.coupling, limit)


class HostGraph:
    def __init__(self, graph, settings):
        self.names = sorted({page.host for page in graph.pages})
        count = len(self.names)
        index = {name: number for number, name in enumerate(self.names)}
        self.of_page = [index[page.host] for page in graph.pages]
        self.members = [[] for _ in range(count)]
        for node in range(graph.count):
            self.members[self.of_page[node]].append(node)
        self.weight = [[0] * count for _ in range(count)]
        self.internal = [0] * count
        self.outgoing = [0] * count
        self.incoming = [0] * count
        for source, target in graph.links:
            first, second = self.of_page[source], self.of_page[target]
            if first == second:
                self.internal[first] += 1
            else:
                self.weight[first][second] += 1
                self.outgoing[first] += 1
                self.incoming[second] += 1
        self.edges = [
            (first, second) for first in range(count) for second in range(count)
            if self.weight[first][second] > 0
        ]
        self.reciprocal = sum(1 for first, second in self.edges if self.weight[second][first] > 0)
        adjacency = [[] for _ in range(count)]
        for first, second in self.edges:
            adjacency[first].append(second)
        components = strong_components(adjacency)
        self.component_count = len(components)
        self.largest = max(len(component) for component in components)
        in_edges = [[] for _ in range(count)]
        for first, second in self.edges:
            in_edges[second].append((first, self.weight[first][second]))
        everyone = list(range(count))
        self.run = run_pagerank(in_edges, everyone, settings.damping, settings)
        self.rank = positions(rank_order(self.run.values))
        heavy = sorted(
            self.edges, key=lambda edge: (-self.weight[edge[0]][edge[1]], edge[0], edge[1])
        )
        self.heavy = heavy[:settings.top_k]


def link_lines(graph, records, ignored):
    reasons = [reason for _, reason in ignored]
    intra = sum(1 for source, target in graph.links if graph.intra_host(source, target))
    reciprocal = sum(1 for source, target in graph.links if (target, source) in graph.link_set)
    in_degrees = [len(sources) for sources in graph.predecessors]
    out_degrees = [len(targets) for targets in graph.successors]
    no_in = [node for node in range(graph.count) if in_degrees[node] == 0]
    max_in = max(in_degrees)
    max_out = max(out_degrees)
    max_in_pages = [node for node in range(graph.count) if in_degrees[node] == max_in]
    max_out_pages = [node for node in range(graph.count) if out_degrees[node] == max_out]
    lines = [
        line("pages", graph.count),
        line("hosts", len({page.host for page in graph.pages})),
        line("link_rows", len(records)),
        line("links", len(graph.links)),
        line("ignored_unknown", reasons.count("unknown")),
        line("ignored_self", reasons.count("self")),
        line("ignored_duplicate", reasons.count("duplicate")),
    ]
    for record, reason in ignored:
        link = f"{record.source},{record.target}"
        lines.append(line("ignored", "line", record.line, link, reason))
    lines += [
        line("intra_host_links", intra),
        line("inter_host_links", len(graph.links) - intra),
        line("mean_degree", fixed(len(graph.links) / graph.count, 4)),
        line("reciprocity", fraction(reciprocal, len(graph.links))),
        line("dangling", len(graph.dangling()), *graph.ids(graph.dangling())),
        line("no_in_links", len(no_in), *graph.ids(no_in)),
        line("max_in_degree", max_in, "pages", *graph.ids(max_in_pages)),
        line("max_out_degree", max_out, "pages", *graph.ids(max_out_pages)),
    ]
    for name, degrees in (("in_degree", in_degrees), ("out_degree", out_degrees)):
        lines += ["", name + "_distribution"]
        lines += [line(value, count) for value, count in distribution(degrees)]
    return lines


def undirected_lines(undirected):
    degeneracy_pages = undirected.kcore.count(undirected.degeneracy)
    lines = [
        "",
        line("undirected_links", undirected.edge_count),
        line("transitivity", fraction(undirected.closed, undirected.possible)),
        line(
            "average_clustering", fixed(undirected.average_clustering, 4),
            "pages", undirected.eligible,
        ),
        line("degeneracy", undirected.degeneracy, "pages", degeneracy_pages),
        "core_distribution",
    ]
    lines += [line(value, count) for value, count in distribution(undirected.kcore)]
    return lines


def component_lines(graph, table, undirected, scores):
    lines = [
        "",
        line(
            "strong_components", len(table.groups), "largest", len(table.groups[table.core]),
            "singletons", table.singletons, "condensation_links", table.edge_count,
        ),
        line("weak_components", undirected.weak_count, "largest", undirected.weak_largest),
        line("condensation_depth", table.depth),
    ]
    for number, group in enumerate(table.groups):
        if len(group) < 2:
            continue
        parts = [
            "scc", number + 1, "size", len(group), "min", graph.ident(group[0]),
            "incoming", table.incoming[number], "outgoing", table.outgoing[number],
            "pagerank", fixed(total(scores.pagerank[node] for node in group)),
        ]
        if table.is_sink(number):
            parts.append("sink")
        lines.append(line(*parts))
    return lines


def bowtie_lines(graph, table, regions, scores):
    lines = ["", line("bowtie", "core_scc", table.core + 1)]
    for region, name in enumerate(REGIONS):
        members = [node for node in range(graph.count) if regions[node] == region]
        score_sum = total(scores.pagerank[node] for node in members)
        parts = [name, len(members), "pagerank", fixed(score_sum)]
        if members:
            parts += ["top", graph.ident(scores.representative(members))]
        if 1 <= len(members) <= REGION_LIST_LIMIT:
            parts += ["pages", *graph.ids(members)]
        lines.append(line(*parts))
    counts = [[0] * len(REGIONS) for _ in REGIONS]
    for source, target in graph.links:
        counts[regions[source]][regions[target]] += 1
    lines.append("region_links")
    for first, first_name in enumerate(REGIONS):
        for second, second_name in enumerate(REGIONS):
            if counts[first][second] > 0:
                lines.append(line(first_name, second_name, counts[first][second]))
    return lines


def distance_lines(graph, distances):
    source, target = distances.diameter_pair
    lines = [
        "",
        "distances",
        line("reachable_pairs", distances.pairs),
        line("average", fraction(distances.total, distances.pairs)),
        line(
            "diameter", distances.diameter,
            "from", graph.ident(source), "to", graph.ident(target),
        ),
        line("effective_diameter", distances.effective_diameter()),
    ]
    for steps in range(1, distances.diameter + 1):
        lines.append(line(steps, distances.histogram[steps]))
    return lines


def pagerank_csv_lines(graph, table, regions, undirected, scores):
    lines = [PAGERANK_HEADER]
    for node, page in enumerate(graph.pages):
        fields = [
            page.ident,
            len(graph.predecessors[node]),
            len(graph.successors[node]),
            table.label[node] + 1,
            REGIONS[regions[node]],
            undirected.kcore[node],
            fixed(scores.harmonic[node]),
            fixed(scores.pagerank[node]),
            scores.rank[node],
            fixed(scores.cheirank[node]),
            scores.cheirank_rank[node],
            fixed(scores.authority[node]),
            fixed(scores.hub[node]),
            fixed(scores.trustrank[node]),
            fixed(scores.trust_ratio[node], 4),
            scores.trust_distance[node],
        ]
        lines.append(",".join(str(field) for field in fields))
    return lines


def rank_lines(graph, nodes, values):
    return [
        graph.describe(position, node, fixed(values[node]))
        for position, node in enumerate(nodes, 1)
    ]


def score_block(name, graph, values, limit):
    return [line(name, "top", limit)] + rank_lines(graph, top_list(values, limit), values)


def pagerank_block(graph, scores, limit):
    top = top_list(scores.pagerank, limit)
    lines = score_block("pagerank", graph, scores.pagerank, limit)
    dangling_mass = total(scores.pagerank[node] for node in graph.dangling())
    lines.append(line("dangling_mass", fixed(dangling_mass)))
    for node in top:
        contributors = sorted(
            graph.predecessors[node],
            key=lambda source: (-scaled(scores.contribution(graph, source)), source),
        )
        parts = ["contributors", graph.ident(node)]
        for source in contributors[:CONTRIBUTOR_LIMIT]:
            parts += [graph.ident(source), fixed(scores.contribution(graph, source))]
        lines.append(line(*parts))
    return lines


def correlation_block(graph, scores):
    series = {
        "in_degree": [len(sources) for sources in graph.predecessors],
        "pagerank": [scaled(value) for value in scores.pagerank],
        "cheirank": [scaled(value) for value in scores.cheirank],
        "authority": [scaled(value) for value in scores.authority],
        "hub": [scaled(value) for value in scores.hub],
        "trustrank": [scaled(value) for value in scores.trustrank],
        "harmonic": [scaled(value) for value in scores.harmonic],
    }
    lines = ["correlation"]
    for position, first in enumerate(QUANTITIES):
        for second in QUANTITIES[position + 1:]:
            lines.append(line(first, second, kendall(series[first], series[second])))
    return lines


def sweep_block(graph, scores, sweeps):
    lines = ["damping_sweep"]
    for sweep in sweeps:
        lines.append(line(
            "damping", fixed(sweep.damping, 4), "overlap", sweep.overlap,
            "footrule", sweep.footrule, "kendall", sweep.correlation,
            "largest_shift", graph.ident(sweep.shift), scores.rank[sweep.shift], sweep.shift_rank,
        ))
        lines.append(line("top", *graph.ids(sweep.top)))
    return lines


def spam_block(graph, scores, undirected, spam, settings):
    threshold = fixed(settings.spam_threshold, 4)
    lines = [line("spam", "top", settings.spam_top, "threshold", threshold)]
    for node in spam.suspects:
        lines.append(line(
            "suspect", graph.ident(node), "rank", scores.rank[node],
            "pagerank", fixed(scores.pagerank[node]), "trustrank", fixed(scores.trustrank[node]),
            "trust_ratio", fixed(scores.trust_ratio[node], 4),
            "trust_distance", scores.trust_distance[node],
            "kcore", undirected.kcore[node], graph.host(node),
        ))
    lines += [line("count", len(spam.suspects)), "trust_by_distance"]
    for value, members in trust_distance_groups(scores.trust_distance):
        lines.append(line(
            "unreachable" if value == -1 else value, "pages", len(members),
            "trustrank", fixed(total(scores.trustrank[node] for node in members)),
            "pagerank", fixed(total(scores.pagerank[node] for node in members)),
        ))
    return lines


def demotion_block(graph, scores, spam, limit):
    if not spam.suspects:
        return ["demotion none"]
    lines = [line("demotion", "hosts", *spam.hosts, "removed_links", spam.removed)]
    values = spam.run.values
    for position, node in enumerate(top_list(values, limit), 1):
        lines.append(graph.describe(position, node, fixed(values[node]), "was", scores.rank[node]))
    for node in spam.suspects:
        lines.append(line(
            "suspect", graph.ident(node), "before", scores.rank[node], "after", spam.rank[node]
        ))
    return lines


def host_graph_block(hosts, limit):
    lines = [
        line(
            "host_graph", "hosts", len(hosts.names), "links", len(hosts.edges),
            "reciprocal", hosts.reciprocal, "strong_components", hosts.component_count,
            "largest", hosts.largest,
        ),
        line("host_links", "top", limit),
    ]
    for first, second in hosts.heavy:
        lines.append(line(hosts.names[first], hosts.names[second], hosts.weight[first][second]))
    return lines


def rankings_lines(graph, scores, undirected, sweeps, spam, hosts, settings):
    limit = settings.top_k
    return joined_blocks([
        pagerank_block(graph, scores, limit),
        score_block("cheirank", graph, scores.cheirank, limit),
        score_block("authority", graph, scores.authority, limit),
        score_block("hub", graph, scores.hub, limit),
        score_block("trustrank", graph, scores.trustrank, limit),
        score_block("harmonic", graph, scores.harmonic, limit),
        correlation_block(graph, scores),
        sweep_block(graph, scores, sweeps),
        spam_block(graph, scores, undirected, spam, settings),
        demotion_block(graph, scores, spam, limit),
        host_graph_block(hosts, limit),
    ])


def convergence_block(heading, run):
    lines = ["", heading]
    for step in range(10, len(run.changes) + 1, 10):
        lines.append(line("iteration", step, "l1", fixed(run.changes[step - 1], 10)))
    lines.append(line("converged_at", "none" if run.converged_at is None else run.converged_at))
    return lines


def convergence_lines(scores, sweeps, spam, results, hosts, settings):
    damping = fixed(settings.damping, 4)
    lines = [line("iterations", settings.iterations, "tolerance", fixed(settings.tolerance, 10))]
    lines += convergence_block(line("pagerank", "damping", damping), scores.pagerank_run)
    lines += convergence_block(line("cheirank", "damping", damping), scores.cheirank_run)
    lines += convergence_block(
        line("trustrank", "damping", damping, "seeds", len(settings.trusted)), scores.trustrank_run
    )
    for sweep in sweeps:
        lines += convergence_block(line("sweep", "damping", fixed(sweep.damping, 4)), sweep.run)
    if spam.run is not None:
        lines += convergence_block(line("demoted", "damping", damping), spam.run)
    for result in results:
        heading = line("personalized", "query", result.query.number, "damping", damping)
        lines += convergence_block(heading, result.personalized)
    heading = line("host_pagerank", "damping", damping, "hosts", len(hosts.names))
    lines += convergence_block(heading, hosts.run)
    return lines


def query_block(graph, scores, result, limit):
    query = result.query
    lines = [
        line("query", query.number, "words", *query.words, "seeds", *query.seeds),
        line(
            "matched", len(result.matches), "root", result.root_size, "base", result.base_size,
            "links", len(result.subgraph), "dropped_intra_host", result.dropped,
        ),
        "results",
    ]
    lines += rank_lines(graph, result.matches[:limit], scores.pagerank)
    lines.append(line("personalized", "reach", result.reach, "seed_mass", fixed(result.seed_mass)))
    lines += rank_lines(graph, result.personalized_top, result.personalized.values)
    lines.append(line("overlap_with_global", result.global_overlap))
    sub = result.subgraph_scores
    if sub is None:
        lines.append("hits none")
        return lines
    lines.append("hits authorities")
    lines += rank_lines(graph, sub.authority_top, sub.authority)
    lines.append("hits hubs")
    lines += rank_lines(graph, sub.hub_top, sub.hub)
    lines.append("salsa authorities")
    lines += rank_lines(graph, sub.salsa_authority_top, sub.salsa_authority)
    lines.append("salsa hubs")
    lines += rank_lines(graph, sub.salsa_hub_top, sub.salsa_hub)
    lines.append(line(
        "hits_salsa_overlap", "authorities", sub.authority_overlap,
        "hubs", sub.hub_overlap, "authority_hosts", sub.authority_hosts,
    ))
    citing = graph.predecessors[sub.cited]
    lines.append(line("related_to", graph.ident(sub.cited), "citing", len(citing)))
    for position, node in enumerate(sub.related, 1):
        lines.append(graph.describe(position, node, sub.cocitation[node]))
    cited = graph.successors[sub.citing]
    lines.append(line("coupled_to", graph.ident(sub.citing), "cited", len(cited)))
    for position, node in enumerate(sub.similar, 1):
        lines.append(graph.describe(position, node, sub.coupling[node]))
    return lines


def hosts_csv_lines(graph, regions, scores, hosts):
    lines = [HOSTS_HEADER]
    for number, name in enumerate(hosts.names):
        members = hosts.members[number]
        size = len(members)
        density = hosts.internal[number] / (size * (size - 1)) if size >= 2 else 0.0
        fields = [
            name,
            size,
            sum(1 for node in members if regions[node] == CORE),
            hosts.internal[number],
            fixed(density, 4),
            hosts.outgoing[number],
            hosts.incoming[number],
            sum(1 for node in members if not graph.successors[node]),
            fixed(total(scores.pagerank[node] for node in members)),
            graph.ident(scores.representative(members)),
            fixed(hosts.run.values[number]),
            hosts.rank[number],
        ]
        lines.append(",".join(str(field) for field in fields))
    return lines


def main():
    pages, records, queries, settings = read_input(INPUT_DIR)
    pages.sort(key=lambda page: page.ident)
    index_of = {page.ident: node for node, page in enumerate(pages)}
    accepted, ignored = classify_links(records, index_of)
    graph = Graph(pages, accepted)
    undirected = Undirected(graph)
    table = ComponentTable(graph)
    regions = bowtie_regions(graph, table.groups[table.core])
    distances = DistanceStats(graph)
    trusted = sorted(index_of[ident] for ident in settings.trusted)
    scores = PageScores(graph, settings, trusted, distances.harmonic)
    sweeps = [SweepResult(damping, graph, scores, settings) for damping in settings.sweep]
    spam = SpamReport(graph, scores, settings)
    results = [QueryResult(query, graph, scores, settings, index_of) for query in queries]
    hosts = HostGraph(graph, settings)

    stats = link_lines(graph, records, ignored)
    stats += undirected_lines(undirected)
    stats += component_lines(graph, table, undirected, scores)
    stats += bowtie_lines(graph, table, regions, scores)
    stats += distance_lines(graph, distances)
    query_blocks = [query_block(graph, scores, result, settings.top_k) for result in results]
    outputs = {
        "graph_stats.txt": stats,
        "pagerank.csv": pagerank_csv_lines(graph, table, regions, undirected, scores),
        "rankings.txt": rankings_lines(graph, scores, undirected, sweeps, spam, hosts, settings),
        "convergence.txt": convergence_lines(scores, sweeps, spam, results, hosts, settings),
        "queries.txt": joined_blocks(query_blocks),
        "hosts.csv": hosts_csv_lines(graph, regions, scores, hosts),
    }
    os.makedirs(OUTPUT_DIR, exist_ok=True)
    for name, lines in outputs.items():
        write_lines(os.path.join(OUTPUT_DIR, name), lines)


if __name__ == "__main__":
    main()
