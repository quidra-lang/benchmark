from collections import deque
from itertools import combinations, count, pairwise
import re
import sys


MAX_VERTICES = 16
MAX_DIMENSION = 4
MAX_EXACT_VERTICES = 12
MAX_CLASSIFY_VERTICES = 5
SHOWN_EMBEDDINGS = 5

NAME = r"[a-z][a-z0-9]{0,7}"
NUMBER = r"(?:0|[1-9][0-9]{0,2})"
PATTERNS = {
    "name": re.compile(NAME),
    "graph": re.compile(NAME),
    "number": re.compile(NUMBER),
    "edge": re.compile(f"{NUMBER}-{NUMBER}"),
}


class CommandError(Exception):
    pass


class Graph:
    def __init__(self, n, edges=()):
        self.n = n
        self.adj = [set() for _ in range(n)]
        for u, v in edges:
            self.add_edge(u, v)

    def add_edge(self, u, v):
        self.adj[u].add(v)
        self.adj[v].add(u)

    def has_edge(self, u, v):
        return v in self.adj[u]

    def edges(self):
        return [(u, v) for u in range(self.n) for v in sorted(self.adj[u]) if u < v]

    def edge_count(self):
        return sum(map(len, self.adj)) // 2


def yes_no(flag):
    return "yes" if flag else "no"


def inverse(labels):
    vertex_at = [0] * len(labels)
    for vertex, label in enumerate(labels):
        vertex_at[label] = vertex
    return vertex_at


def check_range(value, minimum, maximum):
    if value < minimum:
        raise CommandError("bad value")
    if value > maximum:
        raise CommandError("too large")


def check_size(vertices):
    if vertices > MAX_VERTICES:
        raise CommandError("too large")


def custom_graph(n, edge_words):
    check_range(n, 1, MAX_VERTICES)
    graph = Graph(n)
    for word in edge_words:
        u, v = map(int, word.split("-"))
        if u >= n or v >= n or u == v:
            raise CommandError(f"bad edge {word}")
        if graph.has_edge(u, v):
            raise CommandError(f"duplicate edge {word}")
        graph.add_edge(u, v)
    return graph


def cycle_graph(n):
    check_range(n, 3, MAX_VERTICES)
    return Graph(n, [(i, (i + 1) % n) for i in range(n)])


def path_graph(n):
    check_range(n, 1, MAX_VERTICES)
    return Graph(n, [(i, i + 1) for i in range(n - 1)])


def complete_graph(n):
    check_range(n, 1, MAX_VERTICES)
    return Graph(n, combinations(range(n), 2))


def bipartite_graph(a, b):
    if a == 0 or b == 0:
        raise CommandError("bad value")
    check_size(a + b)
    return Graph(a + b, [(i, a + j) for i in range(a) for j in range(b)])


def star_graph(k):
    check_range(k, 1, MAX_VERTICES - 1)
    return Graph(k + 1, [(0, i) for i in range(1, k + 1)])


def wheel_graph(k):
    check_range(k, 3, MAX_VERTICES - 1)
    spokes = [(0, i) for i in range(1, k + 1)]
    rim = [(i, i % k + 1) for i in range(1, k + 1)]
    return Graph(k + 1, spokes + rim)


def petersen_graph():
    edges = []
    for i in range(5):
        edges += [(i, (i + 1) % 5), (i, i + 5), (5 + i, 5 + (i + 2) % 5)]
    return Graph(10, edges)


def hypercube_graph(d):
    check_range(d, 1, MAX_DIMENSION)
    n = 1 << d
    return Graph(n, [(v, v ^ (1 << bit)) for v in range(n) for bit in range(d)])


def circulant_graph(n, jumps):
    check_range(n, 3, MAX_VERTICES)
    if any(j == 0 or 2 * j > n for j in jumps) or any(a >= b for a, b in pairwise(jumps)):
        raise CommandError("bad value")
    return Graph(n, [(i, (i + j) % n) for i in range(n) for j in jumps])


def grid_graph(rows, columns):
    if rows == 0 or columns == 0:
        raise CommandError("bad value")
    check_size(rows * columns)
    edges = []
    for x in range(rows):
        for y in range(columns):
            vertex = x * columns + y
            if y + 1 < columns:
                edges.append((vertex, vertex + 1))
            if x + 1 < rows:
                edges.append((vertex, vertex + columns))
    return Graph(rows * columns, edges)


def complement(graph):
    pairs = combinations(range(graph.n), 2)
    return Graph(graph.n, [(u, v) for u, v in pairs if not graph.has_edge(u, v)])


def line_graph(graph):
    edges = graph.edges()
    if not edges:
        raise CommandError("no edges")
    check_size(len(edges))
    pairs = combinations(range(len(edges)), 2)
    return Graph(len(edges), [(i, j) for i, j in pairs if set(edges[i]) & set(edges[j])])


def cartesian_product(first, second):
    check_size(first.n * second.n)
    width = second.n
    edges = [(x * width + y, x * width + z) for y, z in second.edges() for x in range(first.n)]
    edges += [(x * width + y, w * width + y) for x, w in first.edges() for y in range(width)]
    return Graph(first.n * width, edges)


def disjoint_union(first, second):
    check_size(first.n + second.n)
    shifted = [(u + first.n, v + first.n) for u, v in second.edges()]
    return Graph(first.n + second.n, first.edges() + shifted)


def relabel(graph, permutation):
    if sorted(permutation) != list(range(graph.n)):
        raise CommandError("bad permutation")
    return Graph(graph.n, [(permutation[u], permutation[v]) for u, v in graph.edges()])


def induced_subgraph(graph, vertices):
    if any(v >= graph.n for v in vertices) or len(set(vertices)) < len(vertices):
        raise CommandError("bad vertices")
    pairs = combinations(range(len(vertices)), 2)
    edges = [(i, j) for i, j in pairs if graph.has_edge(vertices[i], vertices[j])]
    return Graph(len(vertices), edges)


def canonize(graph):
    labels = CanonicalForm(graph).labels
    return Graph(graph.n, [(labels[u], labels[v]) for u, v in graph.edges()])


def distances_from(graph, root):
    distance = [None] * graph.n
    distance[root] = 0
    queue = deque([root])
    while queue:
        u = queue.popleft()
        for w in graph.adj[u]:
            if distance[w] is None:
                distance[w] = distance[u] + 1
                queue.append(w)
    return distance


def components(graph):
    seen = set()
    result = []
    for root in range(graph.n):
        if root not in seen:
            distance = distances_from(graph, root)
            component = [v for v in range(graph.n) if distance[v] is not None]
            seen.update(component)
            result.append(component)
    return result


def is_bipartite(graph):
    for component in components(graph):
        depth = distances_from(graph, component[0])
        if any(depth[u] == depth[w] for u in component for w in graph.adj[u]):
            return False
    return True


def girth(graph):
    lengths = []
    for root in range(graph.n):
        distance = [None] * graph.n
        parent = [None] * graph.n
        distance[root] = 0
        queue = deque([root])
        while queue:
            u = queue.popleft()
            for w in graph.adj[u]:
                if distance[w] is None:
                    distance[w] = distance[u] + 1
                    parent[w] = u
                    queue.append(w)
                elif w != parent[u]:
                    lengths.append(distance[u] + distance[w] + 1)
    return min(lengths, default=None)


def count_triangles(graph):
    return sum(1 for u, v in graph.edges() for w in graph.adj[u] & graph.adj[v] if w > v)


def maximum_clique(graph):
    best = []

    def extend(clique, candidates):
        nonlocal best
        if len(clique) > len(best):
            best = clique
        for v in candidates:
            extend(clique + [v], [w for w in candidates if w > v and graph.has_edge(v, w)])

    extend([], list(range(graph.n)))
    return best


def colouring_with(graph, limit):
    colours = []

    def extend(used):
        v = len(colours)
        if v == graph.n:
            return True
        for colour in range(min(used + 1, limit)):
            if all(colours[w] != colour for w in graph.adj[v] if w < v):
                colours.append(colour)
                if extend(max(used, colour + 1)):
                    return True
                colours.pop()
        return False

    return colours if extend(0) else None


def chromatic_colouring(graph, clique_size):
    for limit in count(clique_size):
        colours = colouring_with(graph, limit)
        if colours is not None:
            return limit, colours


class Invariants:
    def __init__(self, graph):
        self.vertices = graph.n
        self.edges = graph.edge_count()
        self.degrees = sorted(map(len, graph.adj), reverse=True)
        self.triangles = count_triangles(graph)
        self.sizes = sorted(map(len, components(graph)), reverse=True)
        length = girth(graph)
        self.girth = "none" if length is None else length
        self.bipartite = yes_no(is_bipartite(graph))
        if len(self.sizes) == 1:
            eccentricities = [max(distances_from(graph, v)) for v in range(graph.n)]
            self.diameter = max(eccentricities)
            self.radius = min(eccentricities)
        else:
            self.diameter = self.radius = "INF"


def rank(keys):
    position = {key: index for index, key in enumerate(sorted(set(keys)))}
    return [position[key] for key in keys]


def degree_colouring(graph):
    return rank([len(neighbours) for neighbours in graph.adj])


def refine(graph, colours):
    rounds = 0
    while True:
        signatures = [
            (colours[v], tuple(sorted(colours[w] for w in graph.adj[v])))
            for v in range(graph.n)
        ]
        refined = rank(signatures)
        if max(refined) == max(colours):
            return colours, rounds
        colours = refined
        rounds += 1


def stable_colouring(graph):
    return refine(graph, degree_colouring(graph))


def individualise(colours, vertex):
    chosen = colours[vertex]
    return [
        colour if colour < chosen or other == vertex else colour + 1
        for other, colour in enumerate(colours)
    ]


def cells_of(colours):
    cells = [[] for _ in range(max(colours) + 1)]
    for vertex, colour in enumerate(colours):
        cells[colour].append(vertex)
    return cells


def refinement_profile(graph):
    colours, rounds = stable_colouring(graph)
    return rounds, [len(cell) for cell in cells_of(colours)]


def leaf_string(graph, labels):
    vertex_at = inverse(labels)
    return "".join(
        "1" if graph.has_edge(vertex_at[i], vertex_at[j]) else "0"
        for i, j in combinations(range(graph.n), 2)
    )


class CanonicalForm:
    def __init__(self, graph):
        self.graph = graph
        self.nodes = 0
        self.leaves = 0
        self.string = None
        self.labels = None
        self.best_leaves = []
        self.visit(stable_colouring(graph)[0])

    def visit(self, colours):
        self.nodes += 1
        if max(colours) == self.graph.n - 1:
            self.record_leaf(colours)
            return
        cells = cells_of(colours)
        target = min((cell for cell in cells if len(cell) > 1), key=len)
        for vertex in target:
            child, _ = refine(self.graph, individualise(colours, vertex))
            self.visit(child)

    def record_leaf(self, labels):
        self.leaves += 1
        string = leaf_string(self.graph, labels)
        if self.string is None or string > self.string:
            self.string = string
            self.labels = labels
            self.best_leaves = [labels]
        elif string == self.string:
            self.best_leaves.append(labels)

    def automorphisms(self):
        vertex_at = inverse(self.labels)
        return [[vertex_at[label] for label in leaf] for leaf in self.best_leaves]


def orbits(items, automorphisms, image):
    result = []
    seen = set()
    for item in items:
        if item not in seen:
            orbit = sorted({image(sigma, item) for sigma in automorphisms})
            seen.update(orbit)
            result.append(orbit)
    return result


def embeddings(pattern, target):
    earlier = [[u for u in pattern.adj[v] if u < v] for v in range(pattern.n)]
    mapping = []

    def extend():
        v = len(mapping)
        if v == pattern.n:
            yield list(mapping)
            return
        for w in range(target.n):
            if w not in mapping and all(target.has_edge(w, mapping[u]) for u in earlier[v]):
                mapping.append(w)
                yield from extend()
                mapping.pop()

    return extend()


def is_induced(pattern, target, mapping):
    return all(
        target.has_edge(mapping[u], mapping[v]) == pattern.has_edge(u, v)
        for u, v in combinations(range(pattern.n), 2)
    )


def parse_word(kind, word):
    if not PATTERNS[kind].fullmatch(word):
        raise CommandError("bad arguments")
    return int(word) if kind == "number" else word


def parse_arguments(kinds, words):
    fixed = kinds
    repeated = None
    minimum = len(kinds)
    if kinds and kinds[-1][-1] in "*+":
        *fixed, repeated = kinds
        minimum = len(fixed) + 1 if repeated.endswith("+") else len(fixed)
    if len(words) < minimum or (repeated is None and len(words) > len(fixed)):
        raise CommandError("bad arguments")
    values = [parse_word(kind, word) for kind, word in zip(fixed, words)]
    if repeated is not None:
        values.append([parse_word(repeated[:-1], word) for word in words[len(fixed):]])
    return values


class GraphLab:
    def __init__(self):
        self.graphs = {}
        self.commands = {
            "GRAPH": (("name", "number", "edge*"), custom_graph),
            "CYCLE": (("name", "number"), cycle_graph),
            "PATH": (("name", "number"), path_graph),
            "COMPLETE": (("name", "number"), complete_graph),
            "BIPARTITE": (("name", "number", "number"), bipartite_graph),
            "STAR": (("name", "number"), star_graph),
            "WHEEL": (("name", "number"), wheel_graph),
            "PETERSEN": (("name",), petersen_graph),
            "HYPERCUBE": (("name", "number"), hypercube_graph),
            "CIRCULANT": (("name", "number", "number+"), circulant_graph),
            "GRID": (("name", "number", "number"), grid_graph),
            "COMPLEMENT": (("name", "graph"), complement),
            "LINE": (("name", "graph"), line_graph),
            "PRODUCT": (("name", "graph", "graph"), cartesian_product),
            "UNION": (("name", "graph", "graph"), disjoint_union),
            "RELABEL": (("name", "graph", "number*"), relabel),
            "INDUCED": (("name", "graph", "number+"), induced_subgraph),
            "CANONIZE": (("name", "graph"), canonize),
            "DELETE": (("graph",), self.delete),
            "LIST": ((), self.list_graphs),
            "SHOW": (("graph",), self.show),
            "INVARIANTS": (("graph",), self.invariants),
            "REFINE": (("graph", "number*"), self.refine_partition),
            "CANON": (("graph",), self.canon),
            "ISO": (("graph", "graph"), self.isomorphism),
            "AUT": (("graph",), self.automorphism_group),
            "SUBISO": (("graph", "graph"), self.subgraph_isomorphism),
            "CLASSIFY": (("number",), self.classify),
        }

    def execute(self, line):
        command, *words = line.split(" ")
        try:
            if command not in self.commands:
                raise CommandError(f"unknown command {command}")
            kinds, handler = self.commands[command]
            arguments = parse_arguments(kinds, words)
            for kind, value in zip(kinds, arguments):
                if kind == "graph" and value not in self.graphs:
                    raise CommandError(f"no graph {value}")
            if kinds[:1] == ("name",):
                self.define(arguments[0], handler, kinds[1:], arguments[1:])
            else:
                handler(*arguments)
        except CommandError as error:
            print(f"error: {error}")

    def define(self, name, build, kinds, arguments):
        inputs = [
            self.graphs[value] if kind == "graph" else value
            for kind, value in zip(kinds, arguments)
        ]
        graph = build(*inputs)
        status = "redefined" if name in self.graphs else "defined"
        self.graphs[name] = graph
        print(status, name, "n", graph.n, "m", graph.edge_count())

    def delete(self, name):
        del self.graphs[name]
        print("deleted", name)

    def list_graphs(self):
        print("graphs", len(self.graphs))
        for name in sorted(self.graphs):
            graph = self.graphs[name]
            print(name, "n", graph.n, "m", graph.edge_count())

    def show(self, name):
        graph = self.graphs[name]
        print("graph", name, "n", graph.n, "m", graph.edge_count())
        for v in range(graph.n):
            print(f"{v}:", *sorted(graph.adj[v]))

    def invariants(self, name):
        graph = self.graphs[name]
        info = Invariants(graph)
        print("invariants", name)
        print("degrees", *info.degrees)
        print("edges", info.edges, "triangles", info.triangles)
        print("components", len(info.sizes), "sizes", *info.sizes)
        print("girth", info.girth, "diameter", info.diameter, "radius", info.radius)
        print("bipartite", info.bipartite)
        if graph.n > MAX_EXACT_VERTICES:
            print("clique -")
            print("chromatic -")
            return
        clique = maximum_clique(graph)
        print("clique", len(clique), *clique)
        chromatic, colours = chromatic_colouring(graph, len(clique))
        print("chromatic", chromatic, *colours)

    def refine_partition(self, name, vertices):
        graph = self.graphs[name]
        if any(v >= graph.n for v in vertices):
            raise CommandError("bad vertices")
        colours, rounds = stable_colouring(graph)
        for v in vertices:
            if colours.count(colours[v]) == 1:
                raise CommandError(f"singleton {v}")
            colours, extra = refine(graph, individualise(colours, v))
            rounds += extra
        cells = cells_of(colours)
        print("refine", name, "rounds", rounds, "cells", len(cells))
        for colour, cell in enumerate(cells):
            print(f"{colour}:", *cell)

    def canon(self, name):
        form = CanonicalForm(self.graphs[name])
        print("canon", name, "nodes", form.nodes, "leaves", form.leaves)
        print("labels", *form.labels)
        print("string", form.string or "-")

    def isomorphism(self, first_name, second_name):
        first = self.graphs[first_name]
        second = self.graphs[second_name]
        a = Invariants(first)
        b = Invariants(second)
        checks = [
            ("vertices", a.vertices, b.vertices, True),
            ("edges", a.edges, b.edges, True),
            ("degrees", a.degrees, b.degrees, False),
            ("triangles", a.triangles, b.triangles, True),
            ("components", len(a.sizes), len(b.sizes), True),
            ("girth", a.girth, b.girth, True),
            ("diameter", a.diameter, b.diameter, True),
            ("bipartite", a.bipartite, b.bipartite, True),
            ("refinement", refinement_profile(first), refinement_profile(second), False),
        ]
        for label, left, right, shown in checks:
            if left != right:
                values = (left, right) if shown else ()
                print("not isomorphic", label, *values)
                return
        first_form = CanonicalForm(first)
        second_form = CanonicalForm(second)
        if first_form.string != second_form.string:
            print("not isomorphic canonical")
            return
        vertex_at = inverse(second_form.labels)
        print("isomorphic")
        print("mapping", *(vertex_at[label] for label in first_form.labels))

    def automorphism_group(self, name):
        graph = self.graphs[name]
        automorphisms = CanonicalForm(graph).automorphisms()
        vertex_orbits = orbits(range(graph.n), automorphisms, lambda sigma, v: sigma[v])
        edge_orbits = orbits(
            graph.edges(),
            automorphisms,
            lambda sigma, edge: tuple(sorted(sigma[end] for end in edge)),
        )
        print("aut", name, "order", len(automorphisms))
        print("vertex orbits", len(vertex_orbits))
        for orbit in vertex_orbits:
            print("orbit", *orbit)
        print("edge orbits", len(edge_orbits))
        for orbit in edge_orbits:
            print("orbit", *(f"{u}-{v}" for u, v in orbit))
        vertex_transitive = yes_no(len(vertex_orbits) == 1)
        edge_transitive = yes_no(len(edge_orbits) == 1)
        print("transitive vertex", vertex_transitive, "edge", edge_transitive)

    def subgraph_isomorphism(self, pattern_name, target_name):
        pattern = self.graphs[pattern_name]
        target = self.graphs[target_name]
        total = 0
        induced_total = 0
        shown = []
        for mapping in embeddings(pattern, target):
            induced = is_induced(pattern, target, mapping)
            total += 1
            induced_total += induced
            if len(shown) < SHOWN_EMBEDDINGS:
                shown.append((mapping, induced))
        symmetries = len(CanonicalForm(pattern).best_leaves)
        print("subiso", pattern_name, target_name, "embeddings", total, "induced", induced_total)
        print("copies", total // symmetries, "induced", induced_total // symmetries)
        for mapping, induced in shown:
            suffix = ["induced"] if induced else []
            print("embedding", *mapping, *suffix)

    def classify(self, n):
        check_range(n, 1, MAX_CLASSIFY_VERTICES)
        pairs = list(combinations(range(n), 2))
        layers = [{CanonicalForm(Graph(n)).string}]
        for _ in range(len(pairs)):
            following = set()
            for string in layers[-1]:
                edges = [pair for pair, bit in zip(pairs, string) if bit == "1"]
                for pair, bit in zip(pairs, string):
                    if bit == "0":
                        following.add(CanonicalForm(Graph(n, edges + [pair])).string)
            layers.append(following)
        print("classify", n, "total", sum(map(len, layers)))
        for m, layer in enumerate(layers):
            strings = [string or "-" for string in sorted(layer)]
            print("edges", m, "count", len(layer), *strings)


def main():
    lines = sys.stdin.read().splitlines()
    lab = GraphLab()
    for line in lines[1:int(lines[0]) + 1]:
        lab.execute(line)


if __name__ == "__main__":
    main()
