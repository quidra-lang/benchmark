import re
from collections import Counter
from math import atan2, pi, sqrt
from pathlib import Path

from plot import Canvas
from predicates import circumcenter, d2, dot, fraction, incircle, orient
from proximity import (
    DisjointSets,
    dijkstra,
    greedy_route,
    is_gabriel,
    is_relative_neighbor,
    kruskal,
    nearest_components,
    nearest_neighbors,
)
from triangulation import Triangulation
from voronoi import bounded_area, clipped_area, neighbor_order, outward, position, squared_radius


OUTPUT_SECTIONS = {
    "triangulation.txt": (
        "input", "summary", "insertions", "triangles", "edges", "hull", "convex_layers", "quality"
    ),
    "voronoi.txt": ("vertices", "voronoi_edges", "cells"),
    "derived.txt": (
        "nearest", "components", "mst", "proximity", "degrees", "empty_circle",
        "extent", "spanner", "alpha", "sites", "queries"
    ),
    "plot.txt": ("delaunay_plot", "voronoi_plot"),
}


def words(values):
    return " ".join(map(str, values))


def read_points():
    points = [None]
    accepted = {}
    rejected = []
    line_count = 0
    integer_word = re.compile(r"-?[0-9]+")
    with Path("input/points.txt").open(encoding="ascii") as source:
        for line_count, raw in enumerate(source, 1):
            line = raw.removesuffix("\n")
            if not line or line.startswith("#"):
                continue
            fields = line.split(" ")
            if len(fields) != 2 or any(integer_word.fullmatch(field) is None for field in fields):
                rejected.append(f"reject {line_count} format")
                continue
            point = tuple(map(int, fields))
            if any(value < 0 or value > 1000 for value in point):
                rejected.append(f"reject {line_count} range")
                continue
            if point in accepted:
                rejected.append(f"reject {line_count} duplicate {accepted[point]}")
                continue
            accepted[point] = len(points)
            points.append(point)
    return points, line_count, rejected


def read_params():
    params = {
        "plot": (61, 31),
        "plot_layers": ["edges", "hull", "sites"],
        "sections": ["summary"],
        "alpha": [],
        "queries": [],
    }
    with Path("input/params.txt").open(encoding="ascii") as source:
        for raw in source:
            line = raw.removesuffix("\n")
            if not line or line.startswith("#"):
                continue
            name, *values = line.split(" ")
            if name == "query":
                params["queries"].append(line.removeprefix("query "))
            elif name in ("plot", "alpha"):
                params[name] = list(map(int, values))
            else:
                params[name] = values
    return params


class Report:
    def __init__(self, points, line_count, rejected, params):
        self.points = points
        self.n = len(points) - 1
        self.line_count = line_count
        self.rejected = rejected
        self.params = params
        self.site_at = {points[site]: site for site in range(1, self.n + 1)}
        self.shortest_paths = {}

    def analyze(self):
        self.build_triangulation()
        self.analyze_triangles()
        self.analyze_voronoi()
        self.analyze_proximity()
        self.analyze_extent()
        self.analyze_layers()
        self.analyze_spanner()
        self.analyze_alpha()
        self.answers = [self.answer_query(query) for query in self.params["queries"]]
        self.draw_plots()

    def build_triangulation(self):
        self.mesh = Triangulation(self.points)
        self.insertions = []
        for site in range(4, self.n + 1):
            self.insertions.append((site, self.mesh.insert(site)))
        self.triangles = [None, *self.mesh.triangles()]
        self.t = len(self.triangles) - 1
        self.edge_triangles = {}
        for number, (a, b, c) in enumerate(self.triangles[1:], 1):
            for edge in ((a, b), (b, c), (c, a)):
                self.edge_triangles[edge] = number
        self.edges = sorted({tuple(sorted(edge)) for edge in self.mesh.directed})
        self.e = len(self.edges)
        self.length2 = {edge: d2(self.points[edge[0]], self.points[edge[1]]) for edge in self.edges}
        self.hull_next = dict(self.mesh.hull_edges())
        self.hull_prev = {following: site for site, following in self.hull_next.items()}
        start = min(self.hull_next)
        self.hull = [start]
        while self.hull_next[self.hull[-1]] != start:
            self.hull.append(self.hull_next[self.hull[-1]])
        self.h = len(self.hull)
        self.hull_edges = list(zip(self.hull, self.hull[1:] + self.hull[:1]))
        self.hull_perimeter = 0.0
        self.hull_area2 = 0
        for first, second in self.hull_edges:
            x1, y1 = self.points[first]
            x2, y2 = self.points[second]
            self.hull_perimeter += sqrt(d2(self.points[first], self.points[second]))
            self.hull_area2 += x1 * y2 - x2 * y1
        adjacent = [set() for _ in self.points]
        for first, second in self.edges:
            adjacent[first].add(second)
            adjacent[second].add(first)
        self.neighbors = [None]
        for site in range(1, self.n + 1):
            self.neighbors.append(
                neighbor_order(site, adjacent[site], self.mesh.directed, self.hull_next)
            )
        self.degree = [0] + [len(order) for order in self.neighbors[1:]]

    def analyze_triangles(self):
        self.area2 = [0]
        self.kind = [None]
        self.min_angles = [0.0]
        self.max_angles = [0.0]
        self.angle_bins = [0] * 6
        self.min_angle_total = 0.0
        for a, b, c in self.triangles[1:]:
            pa, pb, pc = self.points[a], self.points[b], self.points[c]
            area = orient(pa, pb, pc)
            products = (dot(pa, pb, pc), dot(pb, pc, pa), dot(pc, pa, pb))
            lengths = (d2(pb, pc), d2(pc, pa), d2(pa, pb))
            if 0 in products:
                kind = "right"
            elif min(products) < 0:
                kind = "obtuse"
            else:
                kind = "acute"
            shortest = min(range(3), key=lengths.__getitem__)
            longest = max(range(3), key=lengths.__getitem__)
            minimum = atan2(area, products[shortest]) * 180.0 / pi
            maximum = atan2(area, products[longest]) * 180.0 / pi
            self.area2.append(area)
            self.kind.append(kind)
            self.min_angles.append(minimum)
            self.max_angles.append(maximum)
            self.min_angle_total += minimum
            self.angle_bins[int(minimum // 10)] += 1
        self.kind_counts = Counter(self.kind[1:])
        self.minimum_triangle = min(range(1, self.t + 1), key=self.min_angles.__getitem__)
        self.maximum_triangle = max(range(1, self.t + 1), key=self.max_angles.__getitem__)

    def analyze_voronoi(self):
        self.centers = [None]
        self.radius2 = [0.0]
        self.positions = [None]
        for triangle in self.triangles[1:]:
            a, b, c = (self.points[site] for site in triangle)
            center = circumcenter(a, b, c)
            self.centers.append(center)
            self.radius2.append(squared_radius(a, b, c))
            self.positions.append(position(center, self.points, self.hull))
        self.position_counts = Counter(self.positions[1:])
        self.duals = {}
        for first, second in self.edges:
            left = self.edge_triangles.get((first, second))
            right = self.edge_triangles.get((second, first))
            if left is not None and right is not None:
                self.duals[first, second] = f"segment {left} {right}"
            else:
                u, v = (first, second) if left is not None else (second, first)
                dx, dy = outward(self.points, u, v)
                triangle = left if left is not None else right
                self.duals[first, second] = f"ray {triangle} {dx} {dy}"
        self.cells = [None]
        self.cell_total = 0.0
        self.clip_total = 0.0
        self.largest_cell = None
        for site in range(1, self.n + 1):
            order = self.neighbors[site]
            vertices = [
                self.edge_triangles[site, other]
                for other in order if (site, other) in self.edge_triangles
            ]
            clipped = clipped_area(self.points, site, order)
            cell = {"vertices": vertices, "clip": clipped, "area": None}
            if site in self.hull_next:
                cell["incoming"] = outward(self.points, site, self.hull_next[site])
                cell["outgoing"] = outward(self.points, self.hull_prev[site], site)
            else:
                centers = [self.centers[number] for number in vertices]
                cell["area"] = bounded_area(self.points[site], centers)
                self.cell_total += cell["area"]
                if self.largest_cell is None or cell["area"] > self.cells[self.largest_cell]["area"]:
                    self.largest_cell = site
            self.clip_total += clipped
            self.cells.append(cell)

    def analyze_proximity(self):
        self.nearest = nearest_neighbors(self.points, self.neighbors)
        self.mutual_pairs = [
            (site, self.nearest[site]) for site in range(1, self.n + 1)
            if site < self.nearest[site] and self.nearest[self.nearest[site]] == site
        ]
        self.closest_pair = min(self.edges, key=lambda edge: (self.length2[edge], *edge))
        self.components = nearest_components(self.nearest)
        self.component_number = [0] * (self.n + 1)
        self.component_pairs = []
        for number, sites in enumerate(self.components, 1):
            for site in sites:
                self.component_number[site] = number
            self.component_pairs.append(next(
                (site, self.nearest[site]) for site in sites
                if site < self.nearest[site] and self.nearest[self.nearest[site]] == site
            ))
        self.nn_edges = {tuple(sorted((site, self.nearest[site]))) for site in range(1, self.n + 1)}
        self.mst = kruskal(self.points, self.edges)
        self.mst_set = set(self.mst)
        self.mst_length = 0.0
        for edge in self.mst:
            self.mst_length += sqrt(self.length2[edge])
        self.gabriel = {edge for edge in self.edges if is_gabriel(self.points, edge, self.mesh.directed)}
        self.rng = {edge for edge in self.edges if is_relative_neighbor(self.points, edge)}
        self.graph_degrees = {}
        for name, edges in (("gg", self.gabriel), ("rng", self.rng), ("mst", self.mst)):
            degrees = [0] * (self.n + 1)
            for first, second in edges:
                degrees[first] += 1
                degrees[second] += 1
            self.graph_degrees[name] = degrees

    def circle_relation(self, support, site):
        if len(support) == 1:
            return 0 if support[0] == site else -1
        if len(support) == 2:
            first, second = support
            return -dot(self.points[site], self.points[first], self.points[second])
        a, b, c = (self.points[vertex] for vertex in support)
        return incircle(a, b, c, self.points[site])

    def circle_order(self, first, second, third):
        if orient(self.points[first], self.points[second], self.points[third]) > 0:
            return first, second, third
        return first, third, second

    def enclosing_circle(self):
        support = None
        for i, first in enumerate(self.hull):
            if support is not None and self.circle_relation(support, first) >= 0:
                continue
            support = (first,)
            for j in range(i):
                second = self.hull[j]
                if self.circle_relation(support, second) >= 0:
                    continue
                support = (first, second)
                for k in range(j):
                    third = self.hull[k]
                    if self.circle_relation(support, third) < 0:
                        support = self.circle_order(first, second, third)
        boundary = [site for site in range(1, self.n + 1) if self.circle_relation(support, site) == 0]
        diameter = None
        for offset, first in enumerate(boundary):
            for second in boundary[offset + 1:]:
                if all(dot(self.points[site], self.points[first], self.points[second]) == 0
                       for site in boundary):
                    diameter = first, second
                    break
            if diameter is not None:
                break
        if diameter is not None:
            first, second = (self.points[site] for site in diameter)
            center = (first[0] + second[0], first[1] + second[1], 2)
            radius2 = float(d2(first, second)) / 4.0
        else:
            ordered = self.circle_order(*boundary)
            a, b, c = (self.points[site] for site in ordered)
            center = circumcenter(a, b, c)
            radius2 = squared_radius(a, b, c)
        return center, radius2, boundary

    def analyze_extent(self):
        self.empty_candidates = [number for number in range(1, self.t + 1)
                                 if self.positions[number] == "inside"]
        self.empty_vertex = None
        if self.empty_candidates:
            self.empty_vertex = max(self.empty_candidates, key=self.radius2.__getitem__)
        self.diameter = None
        self.diameter2 = -1
        for first in range(1, self.n):
            for second in range(first + 1, self.n + 1):
                length2 = d2(self.points[first], self.points[second])
                if length2 > self.diameter2:
                    self.diameter = first, second
                    self.diameter2 = length2
        self.width = None
        self.width_edge = None
        for first, second in self.hull_edges:
            maximum = max(orient(self.points[first], self.points[second], self.points[site])
                          for site in self.hull)
            width = maximum / sqrt(d2(self.points[first], self.points[second]))
            if self.width is None or width < self.width:
                self.width = width
                self.width_edge = first, second
        self.enclosing_center, self.enclosing_radius2, self.enclosing_sites = self.enclosing_circle()

    def analyze_layers(self):
        remaining = set(range(1, self.n + 1))
        self.layers = []
        self.depth = [0] * (self.n + 1)
        while remaining:
            if len(remaining) <= 2:
                layer = sorted(remaining)
            else:
                ordered = sorted(remaining, key=lambda site: self.points[site])
                lower = []
                for site in ordered:
                    while len(lower) >= 2 and orient(
                        self.points[lower[-2]], self.points[lower[-1]], self.points[site]
                    ) <= 0:
                        lower.pop()
                    lower.append(site)
                upper = []
                for site in reversed(ordered):
                    while len(upper) >= 2 and orient(
                        self.points[upper[-2]], self.points[upper[-1]], self.points[site]
                    ) <= 0:
                        upper.pop()
                    upper.append(site)
                layer = lower[:-1] + upper[:-1]
                start = layer.index(min(layer))
                layer = layer[start:] + layer[:start]
            self.layers.append(layer)
            for site in layer:
                self.depth[site] = len(self.layers)
            remaining.difference_update(layer)

    def shortest_from(self, site):
        if site not in self.shortest_paths:
            self.shortest_paths[site] = dijkstra(self.points, self.neighbors, site)
        return self.shortest_paths[site]

    def analyze_spanner(self):
        self.pair_count = self.n * (self.n - 1) // 2
        self.maximum_stretch = None
        self.stretch_pair = None
        self.stretch_length = 0.0
        self.stretch_distance = 0.0
        total = 0.0
        for first in range(1, self.n):
            distances, _ = self.shortest_from(first)
            for second in range(first + 1, self.n + 1):
                length = distances[second]
                distance = sqrt(d2(self.points[first], self.points[second]))
                stretch = length / distance
                total += stretch
                if self.maximum_stretch is None or stretch > self.maximum_stretch:
                    self.maximum_stretch = stretch
                    self.stretch_pair = first, second
                    self.stretch_length = length
                    self.stretch_distance = distance
        self.mean_stretch = total / self.pair_count

    def analyze_alpha(self):
        self.alpha_results = []
        for alpha in self.params["alpha"]:
            selected = [number for number in range(1, self.t + 1) if self.radius2[number] <= alpha]
            incidence = Counter()
            area2 = 0
            for number in selected:
                a, b, c = self.triangles[number]
                area2 += self.area2[number]
                for edge in ((a, b), (b, c), (c, a)):
                    incidence[tuple(sorted(edge))] += 1
            edges = set(incidence)
            for edge in self.gabriel:
                if self.length2[edge] <= 4 * alpha:
                    edges.add(edge)
            sets = DisjointSets(self.n)
            incident_sites = set()
            for first, second in sorted(edges):
                sets.union(first, second)
                incident_sites.update((first, second))
            self.alpha_results.append({
                "alpha": alpha,
                "triangles": len(selected),
                "edges": len(edges),
                "boundary": sum(value == 1 for value in incidence.values()),
                "dangling": sum(incidence[edge] == 0 for edge in edges),
                "isolated": self.n - len(incident_sites),
                "components": sets.count,
                "holes": sets.count - (self.n - len(edges) + len(selected)),
                "area2": area2,
            })

    def locate_query(self, query):
        nearest = min(range(1, self.n + 1), key=lambda site: (d2(self.points[site], query), site))
        location = "outside"
        if query in self.site_at:
            location = f"vertex {self.site_at[query]}"
        else:
            for first, second in self.edges:
                if orient(self.points[first], self.points[second], query) == 0 and dot(
                    query, self.points[first], self.points[second]
                ) < 0:
                    location = f"edge {first} {second}"
                    break
            else:
                for a, b, c in self.triangles[1:]:
                    if (orient(self.points[a], self.points[b], query) > 0
                            and orient(self.points[b], self.points[c], query) > 0
                            and orient(self.points[c], self.points[a], query) > 0):
                        location = f"triangle {a} {b} {c}"
                        break
        return f"{location} nearest {nearest} d2 {d2(self.points[nearest], query)}"

    def walk_query(self, query):
        path, outside = self.mesh.visibility_walk(query, self.triangles, self.edge_triangles)
        stopping = f"triangle {path[-1]}" if outside is None else f"outside {words(outside)}"
        return f"steps {len(path) - 1} {stopping} path {words(path)}"

    def natural_query(self, query):
        count = 0
        sites = set()
        for triangle in self.triangles[1:]:
            a, b, c = (self.points[site] for site in triangle)
            if incircle(a, b, c, query) > 0:
                count += 1
                sites.update(triangle)
        return f"triangles {count} sites {words(sorted(sites)) if sites else '-'}"

    def route_query(self, first, second):
        path, length = greedy_route(self.points, self.neighbors, first, second)
        return f"hops {len(path) - 1} length {length:.3f} path {words(path)}"

    def path_query(self, first, second):
        distances, previous = self.shortest_from(first)
        path = [second]
        while path[-1] != first:
            path.append(previous[path[-1]])
        path.reverse()
        length = distances[second]
        stretch = "-" if first == second else f"{length / sqrt(d2(self.points[first], self.points[second])):.3f}"
        return f"length {length:.3f} stretch {stretch} hops {len(path) - 1} sites {words(path)}"

    def neighbors_query(self, site):
        return f"degree {self.degree[site]} sites {words(self.neighbors[site])}"

    def edge_query(self, first, second):
        edge = tuple(sorted((first, second)))
        if edge in self.length2:
            gabriel = "yes" if edge in self.gabriel else "no"
            rng = "yes" if edge in self.rng else "no"
            mst = "yes" if edge in self.mst_set else "no"
            return (f"delaunay len2 {self.length2[edge]} gabriel {gabriel} rng {rng} "
                    f"mst {mst} dual {self.duals[edge]}")
        crossings = []
        a, b = self.points[first], self.points[second]
        for u, v in self.edges:
            p, q = self.points[u], self.points[v]
            if orient(a, b, p) * orient(a, b, q) < 0 and orient(p, q, a) * orient(p, q, b) < 0:
                crossings.append(f"{u}-{v}")
        answer = f"missing crossings {len(crossings)}"
        if crossings:
            answer += " " + " ".join(crossings)
        return answer

    def answer_query(self, query):
        name, *values = query.split(" ")
        arguments = tuple(map(int, values))
        if name in ("route", "path", "neighbors", "edge"):
            if any(site < 1 or site > self.n for site in arguments):
                return f"{query} error unknown_site"
            if name == "edge" and arguments[0] == arguments[1]:
                return f"{query} error same_site"
        if name == "locate":
            answer = self.locate_query(arguments)
        elif name == "walk":
            answer = self.walk_query(arguments)
        elif name == "natural":
            answer = self.natural_query(arguments)
        elif name == "route":
            answer = self.route_query(*arguments)
        elif name == "path":
            answer = self.path_query(*arguments)
        elif name == "neighbors":
            answer = self.neighbors_query(*arguments)
        else:
            answer = self.edge_query(*arguments)
        return f"{query} {answer}"

    def draw_plots(self):
        canvas = Canvas(*self.params["plot"])
        for layer in self.params["plot_layers"]:
            if layer == "sites":
                for point in self.points[1:]:
                    canvas.mark(point, "o")
            elif layer == "circle":
                if self.empty_vertex is not None:
                    canvas.mark(self.centers[self.empty_vertex], "@")
            else:
                edges, character = {
                    "edges": (self.edges, "."),
                    "mst": (self.mst, "*"),
                    "hull": (self.hull_edges, "#"),
                }[layer]
                for first, second in edges:
                    canvas.line(self.points[first], self.points[second], character)
        self.delaunay_plot = canvas.framed()
        canvas = Canvas(*self.params["plot"])
        canvas.draw_voronoi(self.points)
        self.voronoi_plot = canvas.framed()

    def section_input(self):
        return [f"lines {self.line_count}", f"accepted {self.n}",
                f"rejected {len(self.rejected)}", *self.rejected]

    def section_summary(self):
        flips = sum(insertion["flips"] for _, insertion in self.insertions)
        outside = sum(insertion["kind"] == "outside" for _, insertion in self.insertions)
        if self.insertions:
            site, insertion = max(self.insertions, key=lambda item: (item[1]["flips"], -item[0]))
            maximum = f"max_flips {site} {insertion['flips']}"
        else:
            maximum = "max_flips none"
        return [
            f"sites {self.n}",
            f"triangles {self.t}",
            f"edges {self.e}",
            f"hull_vertices {self.h}",
            f"interior_sites {self.n - self.h}",
            f"euler {self.n - self.e + self.t}",
            f"flips {flips}",
            f"outside_insertions {outside}",
            maximum,
            f"acute {self.kind_counts['acute']}",
            f"right {self.kind_counts['right']}",
            f"obtuse {self.kind_counts['obtuse']}",
        ]

    def section_insertions(self):
        lines = [f"init {words(self.mesh.initial)}"]
        for site, insertion in self.insertions:
            if insertion["kind"] == "inside":
                description = "inside " + words(insertion["containing"])
            else:
                description = f"outside {insertion['visible']}"
            lines.append(
                f"insert {site} {description} flips {insertion['flips']} "
                f"triangles {insertion['triangle_count']} hull {insertion['hull_count']}"
            )
        return lines

    def section_triangles(self):
        lines = []
        for number, (a, b, c) in enumerate(self.triangles[1:], 1):
            adjacent = [self.edge_triangles.get(edge, "-") for edge in ((c, b), (a, c), (b, a))]
            lines.append(f"tri {number} {a} {b} {c} area2 {self.area2[number]} "
                         f"{self.kind[number]} adj {words(adjacent)}")
        return lines

    def section_edges(self):
        lines = []
        for edge in self.edges:
            first, second = edge
            left = self.edge_triangles.get((first, second), "-")
            right = self.edge_triangles.get((second, first), "-")
            kind = "inner" if left != "-" and right != "-" else "hull"
            lines.append(f"edge {first} {second} {kind} len2 {self.length2[edge]} "
                         f"left {left} right {right}")
        return lines

    def section_hull(self):
        return [f"hull_vertices {self.h}", f"order {words(self.hull)}",
                f"perimeter {self.hull_perimeter:.3f}", f"area2 {self.hull_area2}"]

    def section_convex_layers(self):
        lines = [f"layers {len(self.layers)}"]
        for number, layer in enumerate(self.layers, 1):
            lines.append(f"layer {number} size {len(layer)} sites {words(layer)}")
        return lines

    def section_quality(self):
        minimum = self.minimum_triangle
        maximum = self.maximum_triangle
        lines = [
            f"min_angle {self.min_angles[minimum]:.3f} tri {minimum}",
            f"max_angle {self.max_angles[maximum]:.3f} tri {maximum}",
            f"mean_min_angle {self.min_angle_total / self.t:.3f}",
        ]
        for index, count in enumerate(self.angle_bins):
            lines.append(f"bin {index * 10} {(index + 1) * 10} {count}")
        return lines

    def section_vertices(self):
        lines = [f"{name} {self.position_counts[name]}" for name in ("inside", "on", "outside")]
        for number in range(1, self.t + 1):
            x, y, denominator = self.centers[number]
            lines.append(f"v {number} {fraction(x, denominator)} {fraction(y, denominator)} "
                         f"r {sqrt(self.radius2[number]):.3f} {self.positions[number]}")
        return lines

    def section_voronoi_edges(self):
        lines = [f"segments {self.e - self.h}", f"rays {self.h}"]
        for edge in self.edges:
            lines.append(f"ve {words(edge)} {self.duals[edge]}")
        return lines

    def section_cells(self):
        lines = [f"bounded {self.n - self.h}", f"unbounded {self.h}",
                 f"total_area {self.cell_total:.3f}", f"clip_total {self.clip_total:.3f}"]
        if self.largest_cell is None:
            lines.append("largest none")
        else:
            area = self.cells[self.largest_cell]["area"]
            lines.append(f"largest {self.largest_cell} area {area:.3f}")
        for site, cell in enumerate(self.cells[1:], 1):
            vertices = words(cell["vertices"])
            count = len(cell["vertices"])
            if cell["area"] is None:
                lines.append(f"cell {site} unbounded {count} clip {cell['clip']:.3f} "
                             f"from {words(cell['incoming'])} vertices {vertices} "
                             f"to {words(cell['outgoing'])}")
            else:
                lines.append(f"cell {site} bounded {count} area {cell['area']:.3f} "
                             f"clip {cell['clip']:.3f} vertices {vertices}")
        return lines

    def section_nearest(self):
        lines = [f"mutual_pairs {len(self.mutual_pairs)}",
                 f"closest_pair {words(self.closest_pair)} d2 {self.length2[self.closest_pair]}"]
        for site in range(1, self.n + 1):
            other = self.nearest[site]
            mutual = "mutual" if self.nearest[other] == site else "-"
            lines.append(f"nn {site} {other} d2 {d2(self.points[site], self.points[other])} {mutual}")
        return lines

    def section_components(self):
        lines = [f"components {len(self.components)}"]
        for number, sites in enumerate(self.components, 1):
            pair = self.component_pairs[number - 1]
            lines.append(f"component {number} size {len(sites)} pair {words(pair)} sites {words(sites)}")
        return lines

    def section_mst(self):
        longest = self.mst[-1]
        lines = [f"edges {self.n - 1}", f"total_length {self.mst_length:.3f}",
                 f"longest {words(longest)} len2 {self.length2[longest]}"]
        for edge in self.mst:
            lines.append(f"mst {words(edge)} len2 {self.length2[edge]}")
        return lines

    def section_proximity(self):
        lines = [f"delaunay {self.e}", f"gabriel {len(self.gabriel)}", f"rng {len(self.rng)}",
                 f"mst {self.n - 1}", f"nn {len(self.nn_edges)}"]
        for edge in self.edges:
            if edge in self.rng and edge not in self.mst_set:
                lines.append(f"rng_extra {words(edge)} len2 {self.length2[edge]}")
        return lines

    def section_degrees(self):
        counts = Counter(self.degree[1:])
        lines = [f"min {min(counts)}", f"max {max(counts)}"]
        for degree in sorted(counts):
            lines.append(f"degree {degree} count {counts[degree]}")
        return lines

    def section_empty_circle(self):
        lines = [f"candidates {len(self.empty_candidates)}"]
        if self.empty_vertex is None:
            return [*lines, "none"]
        number = self.empty_vertex
        x, y, denominator = self.centers[number]
        lines.extend([
            f"vertex {number}",
            f"center {fraction(x, denominator)} {fraction(y, denominator)}",
            f"radius {sqrt(self.radius2[number]):.3f}",
            f"sites {words(self.triangles[number])}",
        ])
        return lines

    def section_extent(self):
        x, y, denominator = self.enclosing_center
        return [
            f"diameter {words(self.diameter)} d2 {self.diameter2}",
            f"width {self.width:.3f} edge {words(self.width_edge)}",
            f"enclosing_center {fraction(x, denominator)} {fraction(y, denominator)}",
            f"enclosing_radius {sqrt(self.enclosing_radius2):.3f}",
            f"enclosing_sites {words(self.enclosing_sites)}",
        ]

    def section_spanner(self):
        return [
            f"pairs {self.pair_count}",
            f"max_stretch {self.maximum_stretch:.3f} pair {words(self.stretch_pair)} "
            f"length {self.stretch_length:.3f} distance {self.stretch_distance:.3f}",
            f"mean_stretch {self.mean_stretch:.3f}",
        ]

    def section_alpha(self):
        lines = []
        for result in self.alpha_results:
            lines.append(
                f"alpha {result['alpha']} triangles {result['triangles']} edges {result['edges']} "
                f"boundary {result['boundary']} dangling {result['dangling']} isolated {result['isolated']} "
                f"components {result['components']} holes {result['holes']} area2 {result['area2']}"
            )
        return lines

    def section_sites(self):
        lines = []
        for site in range(1, self.n + 1):
            x, y = self.points[site]
            position = "hull" if site in self.hull_next else "inner"
            lines.append(
                f"site {site} {x} {y} {position} dt {self.degree[site]} "
                f"gg {self.graph_degrees['gg'][site]} rng {self.graph_degrees['rng'][site]} "
                f"mst {self.graph_degrees['mst'][site]} nn {self.nearest[site]} "
                f"comp {self.component_number[site]} depth {self.depth[site]}"
            )
        return lines

    def section_queries(self):
        return self.answers

    def section_delaunay_plot(self):
        return self.delaunay_plot

    def section_voronoi_plot(self):
        return self.voronoi_plot

    def write(self):
        owners = {section: filename for filename, sections in OUTPUT_SECTIONS.items() for section in sections}
        contents = {filename: [] for filename in OUTPUT_SECTIONS}
        for section in self.params["sections"]:
            lines = contents[owners[section]]
            lines.append(f"[{section}]")
            lines.extend(getattr(self, f"section_{section}")())
        output = Path("output")
        output.mkdir(parents=True, exist_ok=True)
        for filename, lines in contents.items():
            text = "\n".join(lines) + ("\n" if lines else "")
            (output / filename).write_text(text, encoding="ascii", newline="\n")


def main():
    points, line_count, rejected = read_points()
    report = Report(points, line_count, rejected, read_params())
    report.analyze()
    report.write()


if __name__ == "__main__":
    main()
