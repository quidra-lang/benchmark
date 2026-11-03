"""Deterministic layered graph layout and its four file reports."""

from collections import Counter, deque
from functools import cmp_to_key
from pathlib import Path

import acyclic_layering
import canvas
import coordinates
import crossing
import graph_io


class Edge:
    def __init__(self, number, source, target):
        self.number = number
        self.source = source
        self.target = target
        self.upper = source
        self.lower = target
        self.reversed = False
        self.transitive = False
        self.chain = []
        self.span = 0
        self.crossings = 0
        self.route = []
        self.bends = 0
        self.length = 0


def reachable(start, neighbors):
    found = {start}
    pending = [start]
    while pending:
        vertex = pending.pop()
        for following in neighbors[vertex]:
            if following not in found:
                found.add(following)
                pending.append(following)
    return found


def order_snapshot(orders):
    return tuple(tuple(layer) for layer in orders)


def copy_order(orders):
    return [list(layer) for layer in orders]


class GraphLayout:
    def __init__(self, graph):
        self.graph = graph
        self.name = graph.name
        self.settings = graph.settings
        self.ids = sorted(graph.nodes)
        self.node_number = {node: number for number, node in enumerate(self.ids)}
        self.labels = [graph.nodes[node] for node in self.ids]
        self.node_count = len(self.ids)
        self.edges = [Edge(number, self.node_number[source], self.node_number[target])
                      for number, (source, target) in enumerate(graph.edges)]
        self.names = list(map(str, self.ids))
        self.widths = [len(label) + 2 for label in self.labels]
        self.drawn = []
        self.sweep_records = []
        self.sift_records = []
        self.random_state = self.settings["seed"]
        self.best_run = None
        self.best_sweep = None
        self.best_crossings = None
        self.path = None

    def process(self):
        self.analyze_graph()
        self.prepare_dag()
        self.assign_layers()
        self.insert_dummies()
        self.make_initial_order()
        self.reduce_crossings()
        self.finish_crossing_counts()
        self.coordinates = coordinates.assign(self.orders, self.upper, self.lower,
                                               self.widths, self.node_count, self.settings)
        self.x = self.coordinates.x
        self.route_geometry()
        self.draw_lines_and_arrows()
        self.build_routes()
        self.find_path()
        self.draw_highlights_and_boxes()

    def analyze_graph(self):
        count = self.node_count
        upper = [[] for _ in range(count)]
        lower = [[] for _ in range(count)]
        undirected = [set() for _ in range(count)]
        for edge in self.edges:
            lower[edge.source].append(edge.target)
            upper[edge.target].append(edge.source)
            undirected[edge.source].add(edge.target)
            undirected[edge.target].add(edge.source)
        self.sources = sum(not upper[v] and bool(lower[v]) for v in range(count))
        self.sinks = sum(not lower[v] and bool(upper[v]) for v in range(count))
        self.isolated = sum(not upper[v] and not lower[v] for v in range(count))
        remaining = set(range(count))
        self.components = 0
        while remaining:
            component = reachable(min(remaining), undirected)
            remaining.difference_update(component)
            self.components += 1
        closure = [reachable(vertex, lower) for vertex in range(count)]
        remaining = set(range(count))
        self.strong_components = []
        while remaining:
            first = min(remaining)
            component = sorted(vertex for vertex in remaining
                               if vertex in closure[first] and first in closure[vertex])
            remaining.difference_update(component)
            if len(component) >= 2:
                self.strong_components.append(component)

    def prepare_dag(self):
        original = [(edge.source, edge.target) for edge in self.edges]
        self.acyclic = acyclic_layering.acyclic_order(self.node_count, original)
        position = {vertex: index for index, vertex in enumerate(self.acyclic)}
        for edge in self.edges:
            if position[edge.source] > position[edge.target]:
                edge.reversed = True
                edge.upper, edge.lower = edge.target, edge.source
        dag = [(edge.upper, edge.lower) for edge in self.edges]
        _, lower = acyclic_layering.neighbors(self.node_count, dag)
        if self.settings["reduce"] == "on":
            closure = [reachable(vertex, lower) for vertex in range(self.node_count)]
            for edge in self.edges:
                if not edge.reversed:
                    edge.transitive = any(following != edge.lower and edge.lower in closure[following]
                                          for following in lower[edge.upper])
        self.drawn = [edge for edge in self.edges if not edge.transitive]

    def assign_layers(self):
        dag = [(edge.upper, edge.lower) for edge in self.drawn]
        result = acyclic_layering.assign_heights(self.node_count, dag, self.settings)
        heights, self.coffman_labels, self.dummies_before, self.promotion_rounds, self.promotions = result
        highest = max(heights)
        levels = [highest - height for height in heights]
        used = set(levels)
        for edge in self.drawn:
            used.update(range(levels[edge.upper] + 1, levels[edge.lower]))
        number = {level: index for index, level in enumerate(sorted(used))}
        self.vertex_layer = [number[level] for level in levels]
        self.layer_count = len(used)

    def insert_dummies(self):
        for edge in self.drawn:
            first = self.vertex_layer[edge.upper]
            last = self.vertex_layer[edge.lower]
            edge.span = last - first
            edge.chain = [edge.upper]
            for layer in range(first + 1, last):
                vertex = len(self.vertex_layer)
                self.vertex_layer.append(layer)
                self.names.append(f"d{vertex - self.node_count + 1}")
                self.widths.append(1)
                edge.chain.append(vertex)
            edge.chain.append(edge.lower)
        self.vertex_count = len(self.vertex_layer)
        self.upper = [[] for _ in range(self.vertex_count)]
        self.lower = [[] for _ in range(self.vertex_count)]
        self.gaps = [[] for _ in range(self.layer_count - 1)]
        for edge in self.drawn:
            for first, second in zip(edge.chain, edge.chain[1:]):
                self.gaps[self.vertex_layer[first]].append((first, second, edge.number))
                self.lower[first].append(second)
                self.upper[second].append(first)

    def make_initial_order(self):
        self.initial_order = [[] for _ in range(self.layer_count)]
        visited = set()

        def visit(vertex):
            if vertex in visited:
                return
            visited.add(vertex)
            self.initial_order[self.vertex_layer[vertex]].append(vertex)
            for following in self.lower[vertex]:
                visit(following)

        for vertex in range(self.node_count):
            visit(vertex)
        self.initial_crossings = crossing.total(self.gaps, self.initial_order)

    def next_random(self):
        self.random_state = 48271 * self.random_state % 2147483647
        return self.random_state

    def starting_order(self, run):
        orders = copy_order(self.initial_order)
        if run > 0:
            for layer in orders:
                for last in range(len(layer) - 1, 0, -1):
                    chosen = self.next_random() % (last + 1)
                    layer[last], layer[chosen] = layer[chosen], layer[last]
        return orders

    def reorder_layer(self, orders, layer, reference):
        position = crossing.positions(orders)
        current = orders[layer]
        movable = [vertex for vertex in current if reference[vertex]]
        keys = {}
        for vertex in movable:
            neighbors = sorted(position[neighbor] for neighbor in reference[vertex])
            if self.settings["heuristic"] == "barycenter":
                keys[vertex] = sum(neighbors), len(neighbors)
            else:
                size = len(neighbors)
                keys[vertex] = neighbors[(size - 1) // 2] + neighbors[size // 2], 1

        def compare(first, second):
            a, b = keys[first]
            c, d = keys[second]
            difference = a * d - c * b
            return (difference > 0) - (difference < 0)

        reordered = iter(sorted(movable, key=cmp_to_key(compare)))
        orders[layer] = [next(reordered) if reference[vertex] else vertex for vertex in current]

    def adjacent_exchanges(self, orders):
        swaps = 0
        position = crossing.positions(orders)
        while True:
            changed = False
            for layer in orders:
                for index in range(len(layer) - 1):
                    first, second = layer[index:index + 2]
                    before = crossing.adjacent_cost(first, second, self.upper, self.lower, position)
                    after = crossing.adjacent_cost(second, first, self.upper, self.lower, position)
                    if before > after:
                        layer[index], layer[index + 1] = second, first
                        position[first], position[second] = index + 1, index
                        swaps += 1
                        changed = True
            if not changed:
                return swaps

    def perform_sweep(self, orders, sweep):
        before = crossing.positions(orders)
        if sweep % 2:
            layers = range(1, self.layer_count)
            reference = self.upper
        else:
            layers = range(self.layer_count - 2, -1, -1)
            reference = self.lower
        for layer in layers:
            self.reorder_layer(orders, layer, reference)
        after = crossing.positions(orders)
        moved = sum(before[vertex] != after[vertex] for vertex in range(self.vertex_count))
        swaps = self.adjacent_exchanges(orders)
        return moved, swaps, crossing.total(self.gaps, orders)

    def run_sweeps(self, run):
        orders = self.starting_order(run)
        count = crossing.total(self.gaps, orders)
        self.sweep_records.append((run, 0, "initial", 0, 0, count))
        history = [order_snapshot(orders)]
        best_order = history[0]
        best_count = count
        best_sweep = 0
        sweep = 1
        while True:
            if count == 0 or sweep - 1 == self.settings["sweeps"]:
                break
            if sweep - 1 >= 2 and history[-1] == history[-3]:
                break
            moved, swaps, count = self.perform_sweep(orders, sweep)
            direction = "down" if sweep % 2 else "up"
            self.sweep_records.append((run, sweep, direction, moved, swaps, count))
            snapshot = order_snapshot(orders)
            history.append(snapshot)
            if count < best_count:
                best_count = count
                best_order = snapshot
                best_sweep = sweep
            sweep += 1
        if self.best_crossings is None or best_count < self.best_crossings:
            self.best_crossings = best_count
            self.best_run = run
            self.best_sweep = best_sweep
            self.orders = copy_order(best_order)

    def sift(self):
        round_number = 0
        while True:
            round_number += 1
            moves = 0
            for vertex in range(self.vertex_count):
                layer = self.vertex_layer[vertex]
                original = self.orders[layer].index(vertex)
                remaining = [other for other in self.orders[layer] if other != vertex]
                costs = []
                for position in range(len(remaining) + 1):
                    self.orders[layer] = remaining[:position] + [vertex] + remaining[position:]
                    costs.append(crossing.local_cost(self.gaps, self.orders, layer))
                minimum = min(costs)
                chosen = original if costs[original] == minimum else costs.index(minimum)
                self.orders[layer] = remaining[:chosen] + [vertex] + remaining[chosen:]
                moves += chosen != original
            count = crossing.total(self.gaps, self.orders)
            self.sift_records.append((round_number, moves, count))
            if moves == 0:
                break

    def reduce_crossings(self):
        for run in range(self.settings["restarts"] + 1):
            self.run_sweeps(run)
        if self.settings["sifting"] == "on":
            self.sift()

    def finish_crossing_counts(self):
        self.position = crossing.positions(self.orders)
        self.crossings_by_gap = crossing.gap_counts(self.gaps, self.orders)
        self.final_crossings = sum(self.crossings_by_gap)
        self.brute_crossings = sum(crossing.brute_force(segments, self.position) for segments in self.gaps)
        for segments in self.gaps:
            for index, (p1, q1, first_edge) in enumerate(segments):
                for p2, q2, second_edge in segments[index + 1:]:
                    upper_difference = self.position[p1] - self.position[p2]
                    lower_difference = self.position[q1] - self.position[q2]
                    if upper_difference * lower_difference < 0:
                        self.edges[first_edge].crossings += 1
                        self.edges[second_edge].crossings += 1

    def assign_tracks(self, segments):
        bent = [(p, q, edge) for p, q, edge in segments if self.x[p] != self.x[q]]
        upper_counts = Counter(p for p, q, edge in bent)
        buses = {}
        for segment in bent:
            p, q, _ = segment
            key = ("upper", p) if upper_counts[p] >= 2 else ("lower", q)
            buses.setdefault(key, []).append(segment)
        bus_details = []
        for (kind, vertex), members in buses.items():
            values = [self.x[endpoint] for p, q, edge in members for endpoint in (p, q)]
            bus_details.append((min(values), max(values), 0 if kind == "upper" else 1,
                                self.x[vertex], members))
        bus_details.sort(key=lambda bus: bus[:4])
        ends = []
        tracks = {}
        for low, high, kind, coordinate, members in bus_details:
            chosen = next((index for index, end in enumerate(ends) if end + 1 < low), len(ends))
            if chosen == len(ends):
                ends.append(high)
            else:
                ends[chosen] = high
            for p, q, _ in members:
                tracks[p, q] = chosen + 1
        total = len(ends)
        gap = max(self.settings["layer_gap"], total + 2)
        offsets = {segment: track + (gap - 2 - total) // 2 for segment, track in tracks.items()}
        return total, gap, offsets

    def route_geometry(self):
        self.track_counts = []
        self.gap_widths = []
        self.segment_offsets = {}
        for segments in self.gaps:
            tracks, gap, offsets = self.assign_tracks(segments)
            self.track_counts.append(tracks)
            self.gap_widths.append(gap)
            self.segment_offsets.update(offsets)
        vertical = self.settings["direction"] in ("TB", "BT")
        self.thickness = [1 if vertical else max(self.widths[v] for v in layer)
                          for layer in self.orders]
        self.band_starts = [0]
        for layer in range(self.layer_count - 1):
            self.band_starts.append(self.band_starts[-1] + self.thickness[layer] + self.gap_widths[layer])
        self.main_length = self.band_starts[-1] + self.thickness[-1]
        self.secondary_length = max(value + extent for value, extent in zip(self.x, self.coordinates.right)) + 1
        self.canvas = canvas.Canvas(self.settings["direction"], self.main_length, self.secondary_length)
        for edge in self.drawn:
            size = 1 if vertical else self.widths[edge.upper]
            upper_band = self.band_starts[self.vertex_layer[edge.upper]]
            lower_band = self.band_starts[self.vertex_layer[edge.lower]]
            edge.upper_endpoint = upper_band + size, self.x[edge.upper]
            edge.lower_endpoint = lower_band - 1, self.x[edge.lower]

    def draw_lines_and_arrows(self):
        vertical = self.settings["direction"] in ("TB", "BT")
        for vertex in range(self.vertex_count):
            layer = self.vertex_layer[vertex]
            beginning = self.band_starts[layer]
            end = beginning + self.thickness[layer] - 1
            if vertex >= self.node_count:
                self.canvas.main_line(beginning, end, self.x[vertex])
            elif not vertical and self.lower[vertex]:
                self.canvas.main_line(beginning + self.widths[vertex], end, self.x[vertex])
        for layer, segments in enumerate(self.gaps):
            beginning = self.band_starts[layer] + self.thickness[layer]
            gap = self.gap_widths[layer]
            for first, second, _ in segments:
                offset = self.segment_offsets.get((first, second))
                self.canvas.segment(beginning, gap, self.x[first], self.x[second], offset)
        for edge in self.drawn:
            endpoint = edge.upper_endpoint if edge.reversed else edge.lower_endpoint
            self.canvas.arrow(endpoint, edge.reversed)

    def build_routes(self):
        for edge in self.drawn:
            points = [edge.upper_endpoint]
            bent = 0
            for first, second in zip(edge.chain, edge.chain[1:]):
                if self.x[first] == self.x[second]:
                    continue
                layer = self.vertex_layer[first]
                main = self.band_starts[layer] + self.thickness[layer] + self.segment_offsets[first, second]
                points.append((main, self.x[first]))
                points.append((main, self.x[second]))
                bent += 1
            points.append(edge.lower_endpoint)
            edge.route = [self.canvas.cell(*point) for point in points]
            if edge.reversed:
                edge.route.reverse()
            edge.bends = 2 * bent
            edge.length = 1 + sum(abs(row2 - row1) + abs(column2 - column1)
                                  for (row1, column1), (row2, column2) in zip(edge.route, edge.route[1:]))

    def find_path(self):
        if self.graph.path is None:
            return
        start, end = (self.node_number[node] for node in self.graph.path)
        following = [[] for _ in range(self.node_count)]
        for edge in self.drawn:
            following[edge.source].append(edge.target)
        parent = {start: None}
        pending = deque([start])
        while pending:
            vertex = pending.popleft()
            for neighbor in sorted(following[vertex]):
                if neighbor not in parent:
                    parent[neighbor] = vertex
                    pending.append(neighbor)
        if end in parent:
            reverse = []
            vertex = end
            while vertex is not None:
                reverse.append(vertex)
                vertex = parent[vertex]
            self.path = list(reversed(reverse))

    def draw_highlights_and_boxes(self):
        on_path = set(self.path or ())
        if self.path is not None:
            by_endpoints = {(edge.source, edge.target): edge for edge in self.drawn}
            for first, second in zip(self.path, self.path[1:]):
                self.canvas.highlight_route(by_endpoints[first, second].route)
        for vertex in range(self.node_count):
            band = self.band_starts[self.vertex_layer[vertex]]
            self.canvas.box(self.labels[vertex], band, self.x[vertex],
                            self.coordinates.left[vertex], vertex in on_path)

    def edge_name(self, edge):
        return f"{self.ids[edge.source]}->{self.ids[edge.target]}"

    def display_sequence(self, vertices):
        return " ".join(self.names[vertex] for vertex in vertices)

    def band_extent(self, layer):
        first = self.band_starts[layer]
        last = first + self.thickness[layer] - 1
        if self.settings["direction"] in ("BT", "RL"):
            return self.main_length - 1 - last, self.main_length - 1 - first
        return first, last

    def layer_line(self, layer):
        vertices = self.orders[layer]
        first, last = self.band_extent(layer)
        low = min(self.x[v] - self.coordinates.left[v] for v in vertices)
        high = max(self.x[v] + self.coordinates.right[v] for v in vertices)
        positions = " ".join(f"{self.names[v]}@{self.x[v]}" for v in vertices)
        return f"layer {layer} band {first} {last} extent {low} {high} : {positions}"

    def vertex_line(self, vertex):
        aligned = " ".join(f"{variant} {self.coordinates.aligned[variant][vertex]}"
                           for variant in coordinates.VARIANTS)
        return (f"vertex {self.names[vertex]} layer {self.vertex_layer[vertex]} pos {self.position[vertex]} "
                f"{aligned} x {self.x[vertex]}")

    def edge_line(self, edge):
        beginning = f"edge {self.ids[edge.source]} {self.ids[edge.target]}"
        if edge.transitive:
            return beginning + " transitive"
        if edge.reversed:
            beginning += " reversed"
        chain = list(reversed(edge.chain)) if edge.reversed else edge.chain
        path = " ".join(str(self.x[vertex]) for vertex in chain)
        route = " ".join(f"{row},{column}" for row, column in edge.route)
        return (f"{beginning} span {edge.span} crossings {edge.crossings} bends {edge.bends} "
                f"path {path} route {route}")

    def layout_lines(self):
        lines = [f"graph {self.name}"]
        settings = " ".join(f"{name}={self.settings[name]}" for name in graph_io.DEFAULTS)
        lines.append("settings " + settings)
        lines.append("acyclic " + self.display_sequence(self.acyclic))
        if self.coffman_labels is not None:
            labels = " ".join(f"{self.names[v]}:{label}" for v, label in enumerate(self.coffman_labels))
            lines.append("labels " + labels)
        for round_number, vertex, difference in self.promotions:
            lines.append(f"promote {round_number} {self.names[vertex]} {difference}")
        for run, sweep, direction, moved, swaps, count in self.sweep_records:
            line = f"sweep {run} {sweep} {direction}"
            if sweep:
                line += f" moved {moved} swaps {swaps}"
            lines.append(line + f" crossings {count}")
        lines.append(f"best run {self.best_run} sweep {self.best_sweep} crossings {self.best_crossings}")
        for round_number, moves, count in self.sift_records:
            lines.append(f"sift {round_number} moves {moves} crossings {count}")
        for layer in range(self.layer_count):
            lines.append(self.layer_line(layer))
        for gap, segments in enumerate(self.gaps):
            lines.append(f"between {gap} {gap + 1} segments {len(segments)} "
                         f"crossings {self.crossings_by_gap[gap]} tracks {self.track_counts[gap]} "
                         f"gap {self.gap_widths[gap]}")
        variants = " ".join(f"{variant}={self.coordinates.blocks[variant]}/{self.coordinates.widths[variant]}"
                            for variant in coordinates.VARIANTS)
        lines.append(f"bk conflicts {len(self.coordinates.conflicts)} {variants} smallest {self.coordinates.smallest}")
        for layer in self.orders:
            for vertex in layer:
                lines.append(self.vertex_line(vertex))
        lines.extend(self.edge_line(edge) for edge in self.edges)
        lines.append("end")
        return lines

    def edge_set_line(self, name, edges):
        names = " ".join(self.edge_name(edge) for edge in edges)
        return f"{name} {len(edges)}" + (" " + names if names else "")

    def statistics_lines(self):
        lines = [f"graph {self.name}"]
        lines.append(f"nodes {self.node_count} edges {len(self.edges)} "
                     f"self_loops {self.graph.self_loops} duplicates {self.graph.duplicates}")
        lines.append(f"sources {self.sources} sinks {self.sinks} isolated {self.isolated} components {self.components}")
        for component in self.strong_components:
            lines.append("scc " + self.display_sequence(component))
        lines.append(self.edge_set_line("reversed", [edge for edge in self.edges if edge.reversed]))
        lines.append(self.edge_set_line("transitive", [edge for edge in self.edges if edge.transitive]))
        maximum_nodes = max(sum(vertex < self.node_count for vertex in layer) for layer in self.orders)
        maximum_vertices = max(map(len, self.orders))
        lines.append(f"layers {self.layer_count} max_nodes {maximum_nodes} max_vertices {maximum_vertices}")
        if self.settings["promotion"] == "on":
            lines.append(f"promotion rounds {self.promotion_rounds} accepted {len(self.promotions)} "
                         f"dummies_before {self.dummies_before}")
        else:
            lines.append("promotion off")
        spans = Counter(edge.span for edge in self.drawn)
        span_total = sum(edge.span for edge in self.drawn)
        lines.append(f"dummies {self.vertex_count - self.node_count} span_total {span_total} "
                     f"span_max {max(spans, default=0)}")
        if spans:
            lines.append("spans " + " ".join(f"{span}:{count}" for span, count in sorted(spans.items())))
        else:
            lines.append("spans none")
        long_edges = [edge for edge in self.drawn if edge.span >= 2]
        vertical = sum(len({self.x[v] for v in edge.chain[1:-1]}) == 1 for edge in long_edges)
        lines.append(f"long_edges {len(long_edges)} vertical {vertical}")
        lines.append(f"crossings initial {self.initial_crossings} swept {self.best_crossings} "
                     f"best_run {self.best_run} best_sweep {self.best_sweep} "
                     f"final {self.final_crossings} brute {self.brute_crossings}")
        segments = [segment for gap in self.gaps for segment in gap]
        straight = sum(self.x[first] == self.x[second] for first, second, edge in segments)
        offset = sum(abs(self.x[first] - self.x[second]) for first, second, edge in segments)
        lines.append(f"segments {len(segments)} straight {straight} bent {len(segments) - straight} offset {offset}")
        route_length = sum(edge.length for edge in self.drawn)
        bends = sum(edge.bends for edge in self.drawn)
        route_line = f"routes length {route_length} bends {bends}"
        if self.drawn:
            longest = max(self.drawn, key=lambda edge: edge.length)
            route_line += f" longest {self.edge_name(longest)} {longest.length}"
        lines.append(route_line)
        lines.append(f"canvas width {self.canvas.columns} height {self.canvas.rows} "
                     f"crossing_cells {self.canvas.crossing_cells()}")
        if self.graph.path is not None:
            source, target = self.graph.path
            line = f"path {source} {target}"
            if self.path is None:
                line += " none"
            else:
                line += f" hops {len(self.path) - 1} : " + self.display_sequence(self.path)
            lines.append(line)
        lines.append("end")
        return lines

    def csv_lines(self):
        return [f"{self.name},{run},{sweep},{count}"
                for run, sweep, direction, moved, swaps, count in self.sweep_records]

    def drawing_lines(self):
        return [f"graph {self.name} {self.canvas.columns}x{self.canvas.rows}"] + self.canvas.drawing_lines()


def main():
    defaults = graph_io.read_defaults()
    graphs = graph_io.read_graphs(defaults)
    layouts = []
    statistics = []
    crossings = ["graph,run,sweep,crossings"]
    drawings = []
    totals = Counter()
    for graph in graphs:
        totals["graphs"] += 1
        if graph.error is not None:
            kind, number = graph.error
            error = [f"graph {graph.name}", f"error {kind} line {number}", "end"]
            layouts.extend(error)
            statistics.extend(error)
            drawings.append([f"graph {graph.name} error {kind}"])
            totals["errors"] += 1
            continue
        layout = GraphLayout(graph)
        layout.process()
        layouts.extend(layout.layout_lines())
        statistics.extend(layout.statistics_lines())
        crossings.extend(layout.csv_lines())
        drawings.append(layout.drawing_lines())
        totals["laid_out"] += 1
        totals["nodes"] += layout.node_count
        totals["edges"] += len(layout.edges)
        totals["dummies"] += layout.vertex_count - layout.node_count
        totals["crossings_initial"] += layout.initial_crossings
        totals["crossings_final"] += layout.final_crossings
    names = ("graphs", "laid_out", "errors", "nodes", "edges", "dummies", "crossings_initial", "crossings_final")
    statistics.append("summary " + " ".join(f"{name} {totals[name]}" for name in names))
    output = Path("output")
    output.mkdir(exist_ok=True)
    for filename, lines in (("layout.txt", layouts), ("stats.txt", statistics), ("crossings.csv", crossings)):
        (output / filename).write_text("".join(line + "\n" for line in lines), encoding="ascii", newline="\n")
    drawing_text = "\n\n".join("\n".join(block) for block in drawings)
    (output / "drawings.txt").write_text(drawing_text + ("\n" if drawings else ""), encoding="ascii", newline="\n")


if __name__ == "__main__":
    main()
