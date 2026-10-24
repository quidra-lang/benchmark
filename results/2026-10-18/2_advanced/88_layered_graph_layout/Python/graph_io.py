"""Ordered graph blocks, settings, and first-error validation."""

from pathlib import Path
import re


DEFAULTS = {
    "layering": "longest", "width": 4, "promotion": "off",
    "heuristic": "barycenter", "sweeps": 12, "node_sep": 2,
    "dummy_sep": 1, "layer_gap": 3, "direction": "TB",
    "sifting": "off", "reduce": "off", "restarts": 0, "seed": 1,
}
CHOICES = {
    "layering": ("longest", "coffman"), "promotion": ("on", "off"),
    "heuristic": ("barycenter", "median"),
    "direction": ("TB", "BT", "LR", "RL"),
    "sifting": ("on", "off"), "reduce": ("on", "off"),
}
RANGES = {
    "width": (1, 40), "sweeps": (0, 50), "node_sep": (1, 9),
    "dummy_sep": (1, 9), "layer_gap": (2, 9),
    "restarts": (0, 9), "seed": (1, 2147483646),
}
INTEGER = re.compile(r"[0-9]{1,10}\Z")


def setting_value(name, word):
    if name in CHOICES:
        return word if word in CHOICES[name] else None
    if name in RANGES and INTEGER.fullmatch(word):
        value = int(word)
        low, high = RANGES[name]
        if low <= value <= high:
            return value
    return None


def input_lines(filename):
    contents = Path("input", filename).read_bytes().decode("ascii")
    for number, line in enumerate(contents.split("\n"), 1):
        if line and not line.startswith("#"):
            yield number, line.split(" ")


def read_defaults():
    settings = DEFAULTS.copy()
    for _, (name, word) in input_lines("params.txt"):
        settings[name] = setting_value(name, word)
    return settings


class Graph:
    def __init__(self, name, defaults):
        self.name = name
        self.settings = defaults.copy()
        self.nodes = {}
        self.edges = []
        self.edge_set = set()
        self.path = None
        self.self_loops = 0
        self.duplicates = 0
        self.error = None

    def accept(self, fields):
        kind = fields[0]
        if kind == "OPTION":
            name, word = fields[1:]
            value = setting_value(name, word)
            if value is None:
                return "bad_option"
            self.settings[name] = value
        elif kind == "NODE":
            node = int(fields[1])
            if node in self.nodes:
                return "duplicate_node"
            if len(self.nodes) == 40:
                return "too_many_nodes"
            self.nodes[node] = fields[2]
        else:
            first, second = map(int, fields[1:])
            if first not in self.nodes or second not in self.nodes:
                return "unknown_node"
            if kind == "PATH":
                self.path = first, second
            elif first == second:
                self.self_loops += 1
            elif (first, second) in self.edge_set:
                self.duplicates += 1
            else:
                self.edge_set.add((first, second))
                self.edges.append((first, second))
        return None


def read_graphs(defaults):
    graphs = []
    for number, fields in input_lines("graphs.txt"):
        if fields[0] == "GRAPH":
            graph = Graph(fields[1], defaults)
            graphs.append(graph)
        elif fields[0] == "END":
            if graph.error is None and not graph.nodes:
                graph.error = "no_nodes", number
        elif graph.error is None:
            error = graph.accept(fields)
            if error is not None:
                graph.error = error, number
    return graphs
