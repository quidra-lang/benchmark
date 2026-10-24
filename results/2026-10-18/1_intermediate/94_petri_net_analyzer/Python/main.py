import itertools
import math
import re
import sys
from dataclasses import dataclass

OMEGA = math.inf
INTEGER_LITERAL = re.compile(r"0|[1-9][0-9]{0,9}")
MAX_LIMIT = 2000
MAX_SET_PLACES = 12
RANDOM_MULTIPLIER = 48271
RANDOM_MODULUS = 2147483647
DEFINITION_ARITY = {"place": (2, 3), "transition": (1, 2), "arc": (3,), "inhibit": (3,)}
COMMAND_ARITY = {
    "MARKING": 0,
    "RESET": 0,
    "SET": 2,
    "ENABLED": 0,
    "FIRE": 1,
    "UNDO": 1,
    "SIMULATE": 3,
    "CONFLICTS": 0,
    "REACH": 1,
    "GRAPH": 1,
    "COVER": 1,
    "PATH": 2,
    "INCIDENCE": 0,
    "PINV": 0,
    "TINV": 0,
    "SIPHONS": 0,
    "TRAPS": 0,
    "CLASSIFY": 0,
    "WORKFLOW": 1,
    "SHOW": 0,
}
LIMIT_COMMANDS = {"REACH", "GRAPH", "COVER", "PATH", "WORKFLOW"}


class InputError(Exception):
    pass


@dataclass
class Place:
    name: str
    tokens: int
    capacity: int | None


@dataclass
class Transition:
    name: str
    priority: int


@dataclass
class TreeNode:
    marking: tuple
    parent: int | None
    transition: int | None
    old: bool
    dead: bool = False


class ReachabilityGraph:
    def __init__(self, start):
        self.markings = [start]
        self.index = {start: 0}
        self.parents = [None]
        self.edges = []
        self.found = None

    def add(self, marking, parent, transition):
        self.index[marking] = len(self.markings)
        self.markings.append(marking)
        self.parents.append((parent, transition))
        return self.index[marking]

    def path_to(self, k):
        path = []
        while self.parents[k] is not None:
            k, transition = self.parents[k]
            path.append(transition)
        path.reverse()
        return path

    def successors(self):
        return [[target for _, target in edges] for edges in self.edges]


def parse_int(text, low, high):
    if not INTEGER_LITERAL.fullmatch(text):
        return None
    value = int(text)
    return value if low <= value <= high else None


def parse_target_entry(entry):
    if entry == "*":
        return 0, None
    if entry.endswith("+") and INTEGER_LITERAL.fullmatch(entry[:-1]):
        return int(entry[:-1]), None
    if INTEGER_LITERAL.fullmatch(entry):
        value = int(entry)
        return value, value
    raise InputError(f"invalid target entry {entry}")


def format_marking(marking):
    return "(" + ",".join("w" if value == OMEGA else str(value) for value in marking) + ")"


def yes_no(condition):
    return "yes" if condition else "no"


def join_or_none(items):
    return " ".join(items) or "none"


def term_notation(coefficients, names):
    terms = []
    for coefficient, name in zip(coefficients, names):
        if coefficient == 1:
            terms.append(name)
        elif coefficient > 1:
            terms.append(f"{coefficient}*{name}")
    return " + ".join(terms)


def strictly_covers(marking, other):
    pairs = list(zip(marking, other))
    return all(a >= b for a, b in pairs) and any(a > b for a, b in pairs)


def submasks(mask):
    subset = mask
    while subset:
        yield subset
        subset = (subset - 1) & mask


def invert(successors):
    predecessors = [[] for _ in successors]
    for node, targets in enumerate(successors):
        for target in targets:
            predecessors[target].append(node)
    return predecessors


def reachable(start, successors):
    seen = {start}
    stack = [start]
    while stack:
        node = stack.pop()
        for target in successors[node]:
            if target not in seen:
                seen.add(target)
                stack.append(target)
    return seen


def strongly_connected_components(successors):
    visited = [False] * len(successors)
    finish_order = []
    for root in range(len(successors)):
        if visited[root]:
            continue
        visited[root] = True
        stack = [(root, iter(successors[root]))]
        while stack:
            node, children = stack[-1]
            for child in children:
                if not visited[child]:
                    visited[child] = True
                    stack.append((child, iter(successors[child])))
                    break
            else:
                stack.pop()
                finish_order.append(node)

    predecessors = invert(successors)
    component = [-1] * len(successors)
    count = 0
    for root in reversed(finish_order):
        if component[root] != -1:
            continue
        component[root] = count
        stack = [root]
        while stack:
            node = stack.pop()
            for parent in predecessors[node]:
                if component[parent] == -1:
                    component[parent] = count
                    stack.append(parent)
        count += 1
    return component, count


def farkas(matrix):
    size = len(matrix)
    width = len(matrix[0])
    rows = [
        tuple(row) + tuple(1 if i == k else 0 for i in range(size))
        for k, row in enumerate(matrix)
    ]
    for j in range(width):
        positives = [row for row in rows if row[j] > 0]
        negatives = [row for row in rows if row[j] < 0]
        collected = [row for row in rows if row[j] == 0]
        for positive in positives:
            for negative in negatives:
                a, b = positive[j], -negative[j]
                combined = [b * x + a * y for x, y in zip(positive, negative)]
                divisor = math.gcd(*combined)
                collected.append(tuple(value // divisor for value in combined))
        unique = list(dict.fromkeys(collected))
        supports = [
            frozenset(i for i in range(size) if row[width + i] > 0) for row in unique
        ]
        rows = [
            row
            for row, support in zip(unique, supports)
            if not any(other < support for other in supports)
        ]
    return [row[width:] for row in rows]


class Net:
    def __init__(self, name):
        self.name = name
        self.places = []
        self.transitions = []
        self.place_index = {}
        self.transition_index = {}
        self.arcs = {}
        self.inhibitors = {}

    def define(self, words):
        keyword, args = words[0], words[1:]
        if keyword not in DEFINITION_ARITY:
            raise InputError(f"unknown definition {keyword}")
        if len(args) not in DEFINITION_ARITY[keyword]:
            raise InputError("wrong number of arguments")
        if keyword == "place":
            self.add_place(*args)
        elif keyword == "transition":
            self.add_transition(*args)
        elif keyword == "arc":
            self.add_arc(*args)
        else:
            self.add_inhibitor(*args)

    def is_node(self, name):
        return name in self.place_index or name in self.transition_index

    def add_place(self, name, tokens, capacity=None):
        if self.is_node(name):
            raise InputError(f"duplicate name {name}")
        tokens = int(tokens)
        if capacity is not None:
            capacity = int(capacity)
            if tokens > capacity:
                raise InputError(f"tokens exceed capacity of {name}")
        self.place_index[name] = len(self.places)
        self.places.append(Place(name, tokens, capacity))

    def add_transition(self, name, priority="0"):
        if self.is_node(name):
            raise InputError(f"duplicate name {name}")
        self.transition_index[name] = len(self.transitions)
        self.transitions.append(Transition(name, int(priority)))

    def add_arc(self, source, target, weight):
        for node in (source, target):
            if not self.is_node(node):
                raise InputError(f"unknown node {node}")
        if (source in self.place_index) == (target in self.place_index):
            raise InputError("arc must connect a place and a transition")
        if (source, target) in self.arcs:
            raise InputError(f"duplicate arc {source} {target}")
        self.arcs[source, target] = int(weight)

    def add_inhibitor(self, place, transition, threshold):
        if place not in self.place_index:
            raise InputError(f"unknown place {place}")
        if transition not in self.transition_index:
            raise InputError(f"unknown transition {transition}")
        if (place, transition) in self.inhibitors:
            raise InputError(f"duplicate inhibitor {place} {transition}")
        self.inhibitors[place, transition] = int(threshold)

    def finish(self):
        places = range(len(self.places))
        transitions = range(len(self.transitions))
        self.pre = [[0] * len(places) for _ in transitions]
        self.post = [[0] * len(places) for _ in transitions]
        self.inhibit = [[0] * len(places) for _ in transitions]
        for (source, target), weight in self.arcs.items():
            if source in self.place_index:
                self.pre[self.transition_index[target]][self.place_index[source]] = weight
            else:
                self.post[self.transition_index[source]][self.place_index[target]] = weight
        for (place, transition), threshold in self.inhibitors.items():
            self.inhibit[self.transition_index[transition]][self.place_index[place]] = threshold

        self.place_names = [place.name for place in self.places]
        self.transition_names = [transition.name for transition in self.transitions]
        self.initial_marking = tuple(place.tokens for place in self.places)
        self.incidence = [
            [self.post[t][p] - self.pre[t][p] for t in transitions] for p in places
        ]
        self.input_places = [[p for p in places if self.pre[t][p]] for t in transitions]
        self.output_places = [[p for p in places if self.post[t][p]] for t in transitions]
        self.input_transitions = [[t for t in transitions if self.post[t][p]] for p in places]
        self.output_transitions = [[t for t in transitions if self.pre[t][p]] for p in places]

    def summary(self):
        return (
            f"net {self.name}: places={len(self.places)} "
            f"transitions={len(self.transitions)} arcs={len(self.arcs)} "
            f"inhibitors={len(self.inhibitors)}"
        )

    def disabled_reason(self, marking, t):
        pre, post, inhibit = self.pre[t], self.post[t], self.inhibit[t]
        for p, place in enumerate(self.places):
            if marking[p] < pre[p]:
                return f"insufficient tokens in {place.name}"
        for p, place in enumerate(self.places):
            if 0 < inhibit[p] <= marking[p]:
                return f"inhibited by {place.name}"
        for p, place in enumerate(self.places):
            if place.capacity is not None and marking[p] - pre[p] + post[p] > place.capacity:
                return f"capacity of {place.name} exceeded"
        return None

    def is_enabled(self, marking, t):
        return self.disabled_reason(marking, t) is None

    def enabled(self, marking):
        return [t for t in range(len(self.transitions)) if self.is_enabled(marking, t)]

    def fire(self, marking, t):
        return tuple(
            value - pre + post for value, pre, post in zip(marking, self.pre[t], self.post[t])
        )

    def reachability_graph(self, start, limit, goal=None):
        graph = ReachabilityGraph(start)
        if goal is not None and goal(start):
            graph.found = 0
            return graph
        position = 0
        while position < len(graph.markings):
            marking = graph.markings[position]
            edges = []
            for t in self.enabled(marking):
                successor = self.fire(marking, t)
                target = graph.index.get(successor)
                if target is None:
                    if len(graph.markings) == limit:
                        return None
                    target = graph.add(successor, position, t)
                    if goal is not None and goal(successor):
                        graph.found = target
                        return graph
                edges.append((t, target))
            graph.edges.append(edges)
            position += 1
        return graph

    def is_persistent(self, graph):
        for edges in graph.edges:
            for t, target in edges:
                successor = graph.markings[target]
                if any(u != t and not self.is_enabled(successor, u) for u, _ in edges):
                    return False
        return True

    def coverability_tree(self, start, limit):
        nodes = [TreeNode(start, None, None, False)]
        seen = {start}
        index = 0
        while index < len(nodes):
            node = nodes[index]
            if not node.old:
                ancestors = []
                ancestor = index
                while ancestor is not None:
                    ancestors.append(nodes[ancestor].marking)
                    ancestor = nodes[ancestor].parent
                ancestors.reverse()
                enabled = self.enabled(node.marking)
                node.dead = not enabled
                for t in enabled:
                    successor = self.accelerate(list(self.fire(node.marking, t)), ancestors)
                    if len(nodes) == limit:
                        return None
                    nodes.append(TreeNode(successor, index, t, successor in seen))
                    seen.add(successor)
            index += 1
        return nodes

    def accelerate(self, marking, ancestors):
        for previous in ancestors:
            if strictly_covers(marking, previous):
                for p, place in enumerate(self.places):
                    if place.capacity is None and marking[p] > previous[p]:
                        marking[p] = OMEGA
        return tuple(marking)

    def find_firing_sequence(self, marking, counts):
        sequence = []
        if self.extend_sequence(marking, list(counts), sequence, set()):
            return sequence
        return None

    def extend_sequence(self, marking, remaining, sequence, failed):
        if not any(remaining):
            return True
        state = tuple(remaining)
        if state in failed:
            return False
        for t in range(len(remaining)):
            if remaining[t] > 0 and self.is_enabled(marking, t):
                remaining[t] -= 1
                sequence.append(t)
                if self.extend_sequence(self.fire(marking, t), remaining, sequence, failed):
                    return True
                sequence.pop()
                remaining[t] += 1
        failed.add(state)
        return False

    def members(self, subset):
        return [p for p in range(len(self.places)) if subset >> p & 1]

    def format_set(self, subset):
        return "{" + ",".join(self.place_names[p] for p in self.members(subset)) + "}"

    def connected_transitions(self, subset):
        inputs = set()
        outputs = set()
        for p in self.members(subset):
            inputs.update(self.input_transitions[p])
            outputs.update(self.output_transitions[p])
        return inputs, outputs

    def is_siphon(self, subset):
        inputs, outputs = self.connected_transitions(subset)
        return inputs <= outputs

    def is_trap(self, subset):
        inputs, outputs = self.connected_transitions(subset)
        return outputs <= inputs

    def minimal_sets(self, predicate):
        candidates = sorted(
            range(1, 1 << len(self.places)),
            key=lambda subset: (subset.bit_count(), self.members(subset)),
        )
        minimal = []
        for subset in candidates:
            if predicate(subset) and not any(found & subset == found for found in minimal):
                minimal.append(subset)
        return minimal

    def arc_list(self, weights):
        items = [f"{name}:{weight}" for name, weight in zip(self.place_names, weights) if weight]
        return ",".join(items) or "-"


class Session:
    def __init__(self, net):
        self.net = net
        self.current = net.initial_marking
        self.history = []

    def execute(self, words):
        name, args = words[0], words[1:]
        if name not in COMMAND_ARITY:
            raise InputError(f"unknown command {name}")
        arity = COMMAND_ARITY[name]
        if len(args) != arity and not (name == "FIRE" and len(args) > arity):
            raise InputError("wrong number of arguments")
        if name in LIMIT_COMMANDS:
            limit = parse_int(args[0], 1, MAX_LIMIT)
            if limit is None:
                raise InputError(f"invalid limit {args[0]}")
            args[0] = limit
        getattr(self, "do_" + name.lower())(*args)

    def print_marking(self):
        print(f"marking {format_marking(self.current)}")

    def fire_transition(self, t):
        self.history.append(self.current)
        self.current = self.net.fire(self.current, t)

    def tokens_in(self, subset):
        return sum(self.current[p] for p in self.net.members(subset))

    def do_marking(self):
        self.print_marking()

    def do_reset(self):
        self.current = self.net.initial_marking
        self.history.clear()
        self.print_marking()

    def do_set(self, name, text):
        if name not in self.net.place_index:
            raise InputError(f"unknown place {name}")
        tokens = parse_int(text, 0, 999)
        if tokens is None:
            raise InputError(f"invalid tokens {text}")
        p = self.net.place_index[name]
        capacity = self.net.places[p].capacity
        if capacity is not None and tokens > capacity:
            raise InputError(f"tokens exceed capacity of {name}")
        marking = list(self.current)
        marking[p] = tokens
        self.current = tuple(marking)
        self.history.clear()
        self.print_marking()

    def do_enabled(self):
        enabled = self.net.enabled(self.current)
        print("enabled: " + join_or_none(self.net.transition_names[t] for t in enabled))

    def do_fire(self, *names):
        for name in names:
            if name not in self.net.transition_index:
                raise InputError(f"unknown transition {name}")
        for step, name in enumerate(names, 1):
            t = self.net.transition_index[name]
            reason = self.net.disabled_reason(self.current, t)
            if reason is not None:
                marking = format_marking(self.current)
                print(f"step {step}: {name} not enabled ({reason}) at {marking}")
                return
            self.fire_transition(t)
        print(f"fired {len(names)} -> {format_marking(self.current)}")

    def do_undo(self, text):
        count = parse_int(text, 1, 1000)
        if count is None:
            raise InputError(f"invalid count {text}")
        if count > len(self.history):
            raise InputError(f"cannot undo {count}: history size {len(self.history)}")
        self.current = self.history[-count]
        del self.history[-count:]
        self.print_marking()

    def do_simulate(self, steps_text, seed_text, mode):
        steps = parse_int(steps_text, 1, 1000)
        if steps is None:
            raise InputError(f"invalid steps {steps_text}")
        seed = parse_int(seed_text, 1, RANDOM_MODULUS - 1)
        if seed is None:
            raise InputError(f"invalid seed {seed_text}")
        if mode not in ("PRIORITY", "RANDOM"):
            raise InputError(f"invalid mode {mode}")

        net = self.net
        counts = [0] * len(net.transitions)
        state = seed
        for step in range(1, steps + 1):
            enabled = net.enabled(self.current)
            if not enabled:
                print(f"dead (steps={step - 1})")
                break
            if mode == "PRIORITY":
                chosen = max(enabled, key=lambda t: net.transitions[t].priority)
            else:
                state = RANDOM_MULTIPLIER * state % RANDOM_MODULUS
                chosen = enabled[state % len(enabled)]
            self.fire_transition(chosen)
            counts[chosen] += 1
            name = net.transition_names[chosen]
            print(f"step {step}: {name} -> {format_marking(self.current)}")
        else:
            print(f"completed (steps={steps})")
        firings = (f"{name}={count}" for name, count in zip(net.transition_names, counts))
        print("counts: " + " ".join(firings))

    def do_conflicts(self):
        net = self.net
        enabled = set(net.enabled(self.current))
        structural = []
        effective = []
        for u, v in itertools.combinations(range(len(net.transitions)), 2):
            pair = f"{net.transition_names[u]}/{net.transition_names[v]}"
            if any(a > 0 and b > 0 for a, b in zip(net.pre[u], net.pre[v])):
                structural.append(pair)
            if u in enabled and v in enabled:
                after_u = net.fire(self.current, u)
                after_v = net.fire(self.current, v)
                if not net.is_enabled(after_u, v) or not net.is_enabled(after_v, u):
                    effective.append(pair)
        print("structural: " + join_or_none(structural))
        print("effective: " + join_or_none(effective))

    def do_reach(self, limit):
        net = self.net
        graph = net.reachability_graph(self.current, limit)
        if graph is None:
            print(f"reachability graph limit {limit} exceeded")
            return
        successors = graph.successors()
        component, component_count = strongly_connected_components(successors)
        terminal = [True] * component_count
        for node, targets in enumerate(successors):
            for target in targets:
                if component[target] != component[node]:
                    terminal[component[node]] = False
        terminal_components = {c for c in range(component_count) if terminal[c]}
        dead = [k for k, targets in enumerate(successors) if not targets]

        print(f"reachable markings: {len(graph.markings)}")
        print(f"edges: {sum(len(targets) for targets in successors)}")
        print(f"components: {component_count} (terminal {len(terminal_components)})")
        print(f"dead markings: {len(dead)}")
        for k in dead:
            path = " ".join(net.transition_names[t] for t in graph.path_to(k)) or "empty"
            print(f"  M{k} {format_marking(graph.markings[k])} path {path}")
        maximum = tuple(max(column) for column in zip(*graph.markings))
        print(f"max tokens: {format_marking(maximum)}")
        print(f"bound: {max(maximum)}")
        print(f"safe: {yes_no(max(maximum) <= 1)}")

        # A home marking exists only when there is exactly one terminal component.
        home = []
        if len(terminal_components) == 1:
            home = [k for k in range(len(graph.markings)) if component[k] in terminal_components]
        print(f"home markings: {len(home)}")
        print(f"reversible: {yes_no(0 in home)}")
        print(f"persistent: {yes_no(net.is_persistent(graph))}")
        levels = self.liveness_levels(graph, component, terminal_components)
        print("liveness: " + " ".join(levels))

    def liveness_levels(self, graph, component, terminal_components):
        net = self.net
        enabled_in = [set() for _ in net.transitions]
        cyclic = [False] * len(net.transitions)
        for node, edges in enumerate(graph.edges):
            for t, target in edges:
                enabled_in[t].add(component[node])
                if component[target] == component[node]:
                    cyclic[t] = True
        levels = []
        for t, name in enumerate(net.transition_names):
            if terminal_components <= enabled_in[t]:
                level = "L4"
            elif cyclic[t]:
                level = "L3"
            elif enabled_in[t]:
                level = "L1"
            else:
                level = "L0"
            levels.append(f"{name}={level}")
        return levels

    def do_graph(self, limit):
        net = self.net
        graph = net.reachability_graph(self.current, limit)
        if graph is None:
            print(f"reachability graph limit {limit} exceeded")
            return
        for k, (marking, edges) in enumerate(zip(graph.markings, graph.edges)):
            listing = " ".join(f"{net.transition_names[t]}->M{target}" for t, target in edges)
            print(f"M{k} {format_marking(marking)}: {listing or 'dead'}")

    def do_cover(self, limit):
        net = self.net
        nodes = net.coverability_tree(self.current, limit)
        if nodes is None:
            print(f"coverability tree limit {limit} exceeded")
            return
        print(f"coverability tree nodes: {len(nodes)}")
        for i, node in enumerate(nodes):
            line = f"  {i} {format_marking(node.marking)}"
            if node.parent is None:
                line += " root"
            else:
                line += f" <- {node.parent} {net.transition_names[node.transition]}"
            if node.old:
                line += " old"
            if node.dead:
                line += " dead"
            print(line)
        bounds = tuple(max(column) for column in zip(*(node.marking for node in nodes)))
        unbounded = [name for name, bound in zip(net.place_names, bounds) if bound == OMEGA]
        print(f"bounds: {format_marking(bounds)}")
        print("unbounded: " + join_or_none(unbounded))

    def do_path(self, limit, target):
        net = self.net
        entries = target.split(",")
        if len(entries) != len(net.places):
            raise InputError(f"target needs {len(net.places)} entries")
        ranges = [parse_target_entry(entry) for entry in entries]

        def matches(marking):
            return all(
                low <= value and (high is None or value <= high)
                for value, (low, high) in zip(marking, ranges)
            )

        graph = net.reachability_graph(self.current, limit, matches)
        if graph is None:
            print(f"search limit {limit} exceeded")
        elif graph.found is None:
            print(f"unreachable (markings explored: {len(graph.markings)})")
        else:
            path = graph.path_to(graph.found)
            line = f"reached {format_marking(graph.markings[graph.found])} length={len(path)}"
            if path:
                line += ": " + " ".join(net.transition_names[t] for t in path)
            print(line)

    def do_incidence(self):
        net = self.net
        table = [[""] + net.transition_names]
        for name, row in zip(net.place_names, net.incidence):
            table.append([name] + [str(value) for value in row])
        widths = [max(len(cell) for cell in column) for column in zip(*table)]
        for row in table:
            cells = [row[0].ljust(widths[0])]
            cells += [cell.rjust(width) for cell, width in zip(row[1:], widths[1:])]
            print("  ".join(cells))

    def do_pinv(self):
        net = self.net
        semiflows = sorted(farkas(net.incidence), reverse=True)
        values = [sum(c * m for c, m in zip(y, self.current)) for y in semiflows]
        print(f"P-semiflows: {len(semiflows)}")
        for semiflow, value in zip(semiflows, values):
            print(f"  {term_notation(semiflow, net.place_names)} = {value}")
        bounds = []
        for p in range(len(net.places)):
            limits = [value // y[p] for y, value in zip(semiflows, values) if y[p] > 0]
            bounds.append(str(min(limits)) if limits else "-")
        print(f"bounds: ({','.join(bounds)})")
        print(f"conservative: {yes_no('-' not in bounds)}")

    def do_tinv(self):
        net = self.net
        transposed = [list(column) for column in zip(*net.incidence)]
        semiflows = sorted(farkas(transposed), reverse=True)
        print(f"T-semiflows: {len(semiflows)}")
        for semiflow in semiflows:
            sequence = net.find_firing_sequence(self.current, semiflow)
            if sequence is None:
                realization = "not realizable"
            else:
                realization = "realizable " + " ".join(net.transition_names[t] for t in sequence)
            print(f"  {term_notation(semiflow, net.transition_names)}: {realization}")
        consistent = all(
            any(x[t] > 0 for x in semiflows) for t in range(len(net.transitions))
        )
        print(f"consistent: {yes_no(consistent)}")

    def do_siphons(self):
        self.print_minimal_sets("minimal siphons", self.net.is_siphon)

    def do_traps(self):
        self.print_minimal_sets("minimal traps", self.net.is_trap)

    def print_minimal_sets(self, title, predicate):
        if len(self.net.places) > MAX_SET_PLACES:
            raise InputError(f"more than {MAX_SET_PLACES} places")
        sets = self.net.minimal_sets(predicate)
        print(f"{title}: {len(sets)}")
        for subset in sets:
            print(f"  {self.net.format_set(subset)} tokens={self.tokens_in(subset)}")

    def do_classify(self):
        net = self.net
        places = range(len(net.places))
        transitions = range(len(net.transitions))
        ordinary = all(weight == 1 for weight in net.arcs.values())
        pure = not any(net.pre[t][p] and net.post[t][p] for t in transitions for p in places)
        state_machine = ordinary and all(
            len(net.input_places[t]) == 1 and len(net.output_places[t]) == 1
            for t in transitions
        )
        marked_graph = ordinary and all(
            len(net.input_transitions[p]) == 1 and len(net.output_transitions[p]) == 1
            for p in places
        )
        free_choice = ordinary and all(
            len(net.output_transitions[p]) == 1 or len(net.input_places[t]) == 1
            for p in places
            for t in net.output_transitions[p]
        )
        extended_free_choice = ordinary and all(
            net.output_transitions[p] == net.output_transitions[q]
            for t in transitions
            for p in net.input_places[t]
            for q in net.input_places[t]
        )
        print(f"ordinary: {yes_no(ordinary)}")
        print(f"pure: {yes_no(pure)}")
        print(f"state machine: {yes_no(state_machine)}")
        print(f"marked graph: {yes_no(marked_graph)}")
        print(f"free choice: {yes_no(free_choice)}")
        print(f"extended free choice: {yes_no(extended_free_choice)}")
        print(f"commoner: {self.commoner_verdict(free_choice)}")

    def commoner_verdict(self, free_choice):
        net = self.net
        if not free_choice:
            return "not applicable"
        if len(net.places) > MAX_SET_PLACES:
            return "too many places"
        for siphon in net.minimal_sets(net.is_siphon):
            marked_trap = any(
                net.is_trap(trap) and self.tokens_in(trap) > 0 for trap in submasks(siphon)
            )
            if not marked_trap:
                return f"fails at {net.format_set(siphon)}"
        return "holds"

    def do_workflow(self, limit):
        net = self.net
        place_count = len(net.places)
        sources = [p for p in range(place_count) if not net.input_transitions[p]]
        sinks = [p for p in range(place_count) if not net.output_transitions[p]]
        if len(sources) != 1:
            print(f"workflow: no ({len(sources)} source places)")
            return
        if len(sinks) != 1:
            print(f"workflow: no ({len(sinks)} sink places)")
            return
        source, sink = sources[0], sinks[0]

        # Vertices are the places followed by the transitions.
        successors = [
            [place_count + t for t in net.output_transitions[p]] for p in range(place_count)
        ]
        successors += net.output_places
        forward = reachable(source, successors)
        backward = reachable(sink, invert(successors))
        names = net.place_names + net.transition_names
        for vertex, name in enumerate(names):
            if vertex not in forward or vertex not in backward:
                route = f"from {names[source]} to {names[sink]}"
                print(f"workflow: no ({name} is not on a path {route})")
                return
        print(f"workflow: source {names[source]} sink {names[sink]}")

        start = tuple(1 if p == source else 0 for p in range(place_count))
        final = tuple(1 if p == sink else 0 for p in range(place_count))
        graph = net.reachability_graph(start, limit)
        if graph is None:
            print(f"reachability graph limit {limit} exceeded")
            return
        completes = False
        if final in graph.index:
            predecessors = invert(graph.successors())
            completes = len(reachable(graph.index[final], predecessors)) == len(graph.markings)
        proper = all(marking == final for marking in graph.markings if marking[sink] >= 1)
        fired = {t for edges in graph.edges for t, _ in edges}
        no_dead = len(fired) == len(net.transitions)
        print(f"option to complete: {yes_no(completes)}")
        print(f"proper completion: {yes_no(proper)}")
        print(f"no dead transitions: {yes_no(no_dead)}")
        print(f"sound: {yes_no(completes and proper and no_dead)}")

    def do_show(self):
        net = self.net
        for place in net.places:
            capacity = "none" if place.capacity is None else place.capacity
            print(f"place {place.name} tokens={place.tokens} capacity={capacity}")
        for t, transition in enumerate(net.transitions):
            print(
                f"transition {transition.name} priority={transition.priority} "
                f"pre={net.arc_list(net.pre[t])} post={net.arc_list(net.post[t])} "
                f"inhibit={net.arc_list(net.inhibit[t])}"
            )


def main():
    # TINV searches firing sequences recursively, one level per fired transition.
    sys.setrecursionlimit(200_000)
    lines = iter(sys.stdin.read().splitlines())
    for _ in range(int(next(lines))):
        net = Net(next(lines).split(" ")[1])
        for line in lines:
            if line == "END NET":
                break
            try:
                net.define(line.split(" "))
            except InputError as error:
                print(f"error: {error}")
        net.finish()
        print(net.summary())
        session = Session(net)
        for _ in range(int(next(lines))):
            try:
                session.execute(next(lines).split(" "))
            except InputError as error:
                print(f"error: {error}")


if __name__ == "__main__":
    main()
