from collections import deque
import sys


MAX_NODES = 20
MAX_EDGES = 60
MIN_ASSIGN_SIZE = 1
MAX_ASSIGN_SIZE = 8


class CommandError(Exception):
    pass


class Edge:
    def __init__(self, number, start, end, capacity, cost):
        self.number = number
        self.start = start
        self.end = end
        self.capacity = capacity
        self.cost = cost
        self.lower = 0
        self.flow = 0


class Arc:
    def __init__(self, edge, forward):
        self.edge = edge
        self.forward = forward

    def start(self):
        return self.edge.start if self.forward else self.edge.end

    def end(self):
        return self.edge.end if self.forward else self.edge.start

    def residual(self):
        if self.forward:
            return self.edge.capacity - self.edge.flow
        return self.edge.flow

    def cost(self):
        return self.edge.cost if self.forward else -self.edge.cost

    def push(self, amount):
        if self.forward:
            self.edge.flow += amount
        else:
            self.edge.flow -= amount

    def label(self):
        sign = "+" if self.forward else "-"
        return sign + str(self.edge.number)


class FlowPiece:
    def __init__(self, cycle, start, edges, amount):
        self.cycle = cycle
        self.start = start
        self.edges = edges
        self.amount = amount


def path_notation(names, start, arcs):
    parts = [names[start]]
    for arc in arcs:
        parts.append(arc.label())
        parts.append(names[arc.end()])
    return " ".join(parts)


def forward_arcs(edges):
    return [Arc(edge, True) for edge in edges]


def bottleneck(path):
    return min(arc.residual() for arc in path)


def push_path(path, amount):
    for arc in path:
        arc.push(amount)


def traced_path(parent, source, sink):
    path = []
    vertex = sink
    while vertex != source:
        arc = parent[vertex]
        path.append(arc)
        vertex = arc.start()
    path.reverse()
    return path


def net_outflow(edges, vertex):
    value = 0
    for edge in edges:
        if edge.start == vertex:
            value += edge.flow
        if edge.end == vertex:
            value -= edge.flow
    return value


def has_negative_cycle(node_count, edges):
    distance = [0] * node_count
    for _ in range(node_count + 1):
        updated = False
        for edge in edges:
            if distance[edge.start] + edge.cost < distance[edge.end]:
                distance[edge.end] = distance[edge.start] + edge.cost
                updated = True
        if not updated:
            return False
    return True


def first_positive(values):
    for index, value in enumerate(values):
        if value > 0:
            return index
    return None


def trace_piece(edges, remaining, balance, origin):
    walk = [origin]
    used = []
    while True:
        vertex = walk[-1]
        index = next(
            i for i, edge in enumerate(edges)
            if edge.start == vertex and remaining[i] > 0
        )
        target = edges[index].end
        used.append(index)
        if target in walk:
            cycle = used[walk.index(target):]
            amount = min(remaining[i] for i in cycle)
            for i in cycle:
                remaining[i] -= amount
            return FlowPiece(True, target, [edges[i] for i in cycle], amount)
        walk.append(target)
        if balance[target] < 0:
            amount = min(min(remaining[i] for i in used), balance[origin], -balance[target])
            for i in used:
                remaining[i] -= amount
            balance[origin] -= amount
            balance[target] += amount
            return FlowPiece(False, origin, [edges[i] for i in used], amount)


def flow_decomposition(node_count, edges):
    remaining = [edge.flow for edge in edges]
    balance = [0] * node_count
    for edge in edges:
        balance[edge.start] += edge.flow
        balance[edge.end] -= edge.flow
    pieces = []
    while first_positive(remaining) is not None:
        origin = first_positive(balance)
        if origin is None:
            origin = edges[first_positive(remaining)].start
        pieces.append(trace_piece(edges, remaining, balance, origin))
    return pieces


class FlowGraph:
    def __init__(self, node_count, edges):
        self.node_count = node_count
        self.edges = edges
        forward = [Arc(edge, True) for edge in edges]
        backward = [Arc(edge, False) for edge in edges]
        self.global_arcs = forward + backward
        self.arcs = [[] for _ in range(node_count)]
        for arc in self.global_arcs:
            self.arcs[arc.start()].append(arc)

    def breadth_first(self, source, threshold):
        level = [None] * self.node_count
        parent = [None] * self.node_count
        level[source] = 0
        queue = deque([source])
        while queue:
            vertex = queue.popleft()
            for arc in self.arcs[vertex]:
                target = arc.end()
                if arc.residual() >= threshold and level[target] is None:
                    level[target] = level[vertex] + 1
                    parent[target] = arc
                    queue.append(target)
        return level, parent

    def single_augmentation(self, source, sink, threshold):
        level, parent = self.breadth_first(source, threshold)
        if level[sink] is None:
            return None
        path = traced_path(parent, source, sink)
        amount = bottleneck(path)
        push_path(path, amount)
        return amount, path

    def edmonds_karp(self, source, sink):
        pushes = []
        result = self.single_augmentation(source, sink, 1)
        while result is not None:
            pushes.append(result)
            result = self.single_augmentation(source, sink, 1)
        return pushes

    def blocking_flow(self, source, sink, level):
        pushes = []
        pointer = [0] * self.node_count
        path = []
        vertex = source
        while True:
            if vertex == sink:
                amount = bottleneck(path)
                push_path(path, amount)
                pushes.append((amount, path))
                path = []
                vertex = source
            elif pointer[vertex] >= len(self.arcs[vertex]):
                if vertex == source:
                    return pushes
                vertex = path.pop().start()
                pointer[vertex] += 1
            else:
                arc = self.arcs[vertex][pointer[vertex]]
                target = arc.end()
                if (
                    arc.residual() > 0
                    and level[target] is not None
                    and level[target] == level[vertex] + 1
                ):
                    path.append(arc)
                    vertex = target
                else:
                    pointer[vertex] += 1

    def dinic(self, source, sink):
        pushes = []
        phases = 0
        level, _ = self.breadth_first(source, 1)
        while level[sink] is not None:
            phases += 1
            for amount, path in self.blocking_flow(source, sink, level):
                pushes.append((phases, amount, path))
            level, _ = self.breadth_first(source, 1)
        return phases, pushes

    def capacity_scaling(self, source, sink):
        largest = max((edge.capacity for edge in self.edges), default=0)
        delta = 1
        while delta * 2 <= largest:
            delta *= 2
        pushes = []
        while delta >= 1:
            result = self.single_augmentation(source, sink, delta)
            while result is not None:
                amount, path = result
                pushes.append((delta, amount, path))
                result = self.single_augmentation(source, sink, delta)
            delta //= 2
        return pushes

    def cheapest_path(self, source, sink):
        usable = [arc for arc in self.global_arcs if arc.residual() > 0]
        distance = [None] * self.node_count
        parent = [None] * self.node_count
        distance[source] = 0
        updated = True
        while updated:
            updated = False
            for arc in usable:
                start, end = arc.start(), arc.end()
                if distance[start] is None:
                    continue
                candidate = distance[start] + arc.cost()
                if distance[end] is None or candidate < distance[end]:
                    distance[end] = candidate
                    parent[end] = arc
                    updated = True
        if distance[sink] is None:
            return None
        return distance[sink], traced_path(parent, source, sink)

    def successive_shortest_paths(self, source, sink, target):
        pushes = []
        flow = 0
        cost = 0
        while target is None or flow < target:
            result = self.cheapest_path(source, sink)
            if result is None:
                break
            unit_cost, path = result
            amount = bottleneck(path)
            if target is not None:
                amount = min(amount, target - flow)
            push_path(path, amount)
            flow += amount
            cost += amount * unit_cost
            pushes.append((amount, unit_cost, path))
        return flow, cost, pushes


def maximum_flow_amount(node_count, edges, source, sink):
    FlowGraph(node_count, edges).edmonds_karp(source, sink)
    return net_outflow(edges, source)


class BipartiteMatching:
    def __init__(self, left_count, right_count, links):
        self.links = links
        self.left_partner = [None] * left_count
        self.right_partner = [None] * right_count
        self.examined = []
        for left in range(left_count):
            self.examined = [False] * right_count
            self.try_left(left)

    def try_left(self, left):
        for a, b in self.links:
            if a != left or self.examined[b]:
                continue
            self.examined[b] = True
            partner = self.right_partner[b]
            if partner is None or self.try_left(partner):
                self.right_partner[b] = left
                self.left_partner[left] = b
                return True
        return False

    def alternating_set(self):
        left_in = [partner is None for partner in self.left_partner]
        right_in = [False] * len(self.right_partner)
        changed = True
        while changed:
            changed = False
            for a, b in self.links:
                if left_in[a] and not right_in[b] and self.left_partner[a] != b:
                    right_in[b] = True
                    changed = True
            for b, partner in enumerate(self.right_partner):
                if right_in[b] and partner is not None and not left_in[partner]:
                    left_in[partner] = True
                    changed = True
        return left_in, right_in


class AssignmentSolver:
    def __init__(self, table, maximize):
        self.table = table
        self.maximize = maximize
        self.size = len(table)
        full = 1 << self.size
        self.best = [[0] * full for _ in range(self.size + 1)]
        self.ways = [[0] * full for _ in range(self.size)] + [[1] * full]
        for row in range(self.size - 1, -1, -1):
            for mask in range(full):
                for _, total, count in self.options(row, mask):
                    if self.ways[row][mask] == 0 or self.improves(total, self.best[row][mask]):
                        self.best[row][mask] = total
                        self.ways[row][mask] = count
                    elif total == self.best[row][mask]:
                        self.ways[row][mask] += count

    def improves(self, total, current):
        return total > current if self.maximize else total < current

    def options(self, row, mask):
        result = []
        for column in range(self.size):
            bit = 1 << column
            value = self.table[row][column]
            following = mask | bit
            if mask & bit or value is None or self.ways[row + 1][following] == 0:
                continue
            total = value + self.best[row + 1][following]
            result.append((column, total, self.ways[row + 1][following]))
        return result

    def feasible(self):
        return self.ways[0][0] > 0

    def optimum(self):
        return self.best[0][0], self.ways[0][0]

    def chosen_columns(self):
        columns = []
        mask = 0
        for row in range(self.size):
            for column, total, _ in self.options(row, mask):
                if total == self.best[row][mask]:
                    columns.append(column)
                    mask |= 1 << column
                    break
        return columns


class Network:
    def __init__(self):
        self.names = []
        self.index = {}
        self.demands = []
        self.edges = []
        self.owner = "none"
        self.source = None
        self.sink = None

    def node_count(self):
        return len(self.names)

    def add_node(self, name):
        self.index[name] = len(self.names)
        self.names.append(name)
        self.demands.append(0)

    def add_edge(self, start, end, capacity, cost):
        edge = Edge(len(self.edges) + 1, start, end, capacity, cost)
        self.edges.append(edge)
        return edge

    def outflow(self, vertex):
        return sum(edge.flow for edge in self.edges if edge.start == vertex)

    def inflow(self, vertex):
        return sum(edge.flow for edge in self.edges if edge.end == vertex)

    def flow_value(self):
        return net_outflow(self.edges, self.source)

    def total_cost(self):
        return sum(edge.flow * edge.cost for edge in self.edges)

    def clear_flows(self):
        for edge in self.edges:
            edge.flow = 0

    def set_owner(self, owner, source, sink):
        self.owner = owner
        self.source = source
        self.sink = sink

    def start_flow(self, source, sink):
        if self.owner != "flow" or self.source != source or self.sink != sink:
            self.clear_flows()
        self.set_owner("flow", source, sink)
        return self.flow_value()

    def graph(self):
        return FlowGraph(self.node_count(), self.edges)

    def working_edges(self):
        return [
            Edge(edge.number, edge.start, edge.end, edge.capacity, edge.cost)
            for edge in self.edges
        ]


class FlowSolver:
    def __init__(self):
        self.network = Network()
        self.output = []
        self.handlers = {
            "NODE": self.add_nodes,
            "EDGE": self.add_edge,
            "LOWER": self.set_lower,
            "CAP": self.set_capacity,
            "COST": self.set_cost,
            "DEMAND": self.set_demand,
            "RESET": self.reset,
            "CLEAR": self.clear,
            "SHOW": self.show,
            "AUGMENT": self.augment,
            "MAXFLOW": self.maxflow,
            "DINIC": self.dinic,
            "SCALING": self.scaling,
            "MINCUT": self.mincut,
            "SENSITIVITY": self.sensitivity,
            "MINCOST": self.mincost,
            "DISJOINT": self.disjoint,
            "DECOMPOSE": self.decompose,
            "VERIFY": self.verify,
            "CIRCULATION": self.circulation,
            "MATCH": self.match,
            "ASSIGN": self.assign,
        }

    def emit(self, *parts):
        self.output.append(" ".join(str(part) for part in parts))

    def require_node(self, name):
        if name not in self.network.index:
            raise CommandError(f"UNKNOWN NODE {name}")
        return self.network.index[name]

    def require_edge(self, text):
        number = int(text)
        if not 1 <= number <= len(self.network.edges):
            raise CommandError(f"UNKNOWN EDGE {text}")
        return self.network.edges[number - 1]

    def require_endpoints(self, arguments):
        source = self.require_node(arguments[0])
        sink = self.require_node(arguments[1])
        if source == sink:
            raise CommandError("SAME NODE")
        return source, sink

    def name(self, vertex):
        return self.network.names[vertex]

    def notation(self, start, arcs):
        return path_notation(self.network.names, start, arcs)

    def flow_list(self):
        for edge in self.network.edges:
            self.emit(
                "FLOW", edge.number, self.name(edge.start), self.name(edge.end),
                f"{edge.flow}/{edge.capacity}",
            )

    def add_nodes(self, arguments):
        seen = set()
        for name in arguments:
            if name in self.network.index or name in seen:
                raise CommandError(f"DUPLICATE NODE {name}")
            seen.add(name)
        if self.network.node_count() + len(arguments) > MAX_NODES:
            raise CommandError("TOO MANY NODES")
        for name in arguments:
            self.network.add_node(name)
        self.emit("NODE", f"added={len(arguments)}", f"total={self.network.node_count()}")

    def add_edge(self, arguments):
        start = self.require_node(arguments[0])
        end = self.require_node(arguments[1])
        if start == end:
            raise CommandError("SELF LOOP")
        if len(self.network.edges) == MAX_EDGES:
            raise CommandError("TOO MANY EDGES")
        cost = int(arguments[3]) if len(arguments) == 4 else 0
        edge = self.network.add_edge(start, end, int(arguments[2]), cost)
        self.emit(
            "EDGE", edge.number, arguments[0], arguments[1],
            f"cap={edge.capacity}", f"cost={edge.cost}",
        )

    def set_lower(self, arguments):
        edge = self.require_edge(arguments[0])
        lower = int(arguments[1])
        if lower > edge.capacity:
            raise CommandError("BAD BOUND")
        edge.lower = lower
        self.emit("LOWER", edge.number, f"low={edge.lower}", f"cap={edge.capacity}")

    def set_capacity(self, arguments):
        edge = self.require_edge(arguments[0])
        capacity = int(arguments[1])
        if capacity < edge.lower:
            raise CommandError("BAD BOUND")
        if capacity < edge.flow:
            raise CommandError("BELOW FLOW")
        edge.capacity = capacity
        self.emit("CAP", edge.number, f"low={edge.lower}", f"cap={edge.capacity}")

    def set_cost(self, arguments):
        edge = self.require_edge(arguments[0])
        edge.cost = int(arguments[1])
        self.emit("COST", edge.number, f"cost={edge.cost}")

    def set_demand(self, arguments):
        vertex = self.require_node(arguments[0])
        self.network.demands[vertex] = int(arguments[1])
        total = sum(self.network.demands)
        self.emit("DEMAND", arguments[0], self.network.demands[vertex], f"total={total}")

    def reset(self, arguments):
        changed = sum(edge.flow != 0 for edge in self.network.edges)
        self.emit("RESET", f"edges={changed}")
        self.network.clear_flows()
        self.network.set_owner("none", None, None)

    def clear(self, arguments):
        network = self.network
        self.emit("CLEAR", f"nodes={network.node_count()}", f"edges={len(network.edges)}")
        self.network = Network()

    def show(self, arguments):
        network = self.network
        self.emit("NETWORK", f"nodes={network.node_count()}", f"edges={len(network.edges)}")
        if network.owner == "none":
            self.emit("STATE", "none")
        elif network.owner == "circulation":
            self.emit("STATE", "circulation", f"cost={network.total_cost()}")
        else:
            self.emit(
                "STATE", "flow", self.name(network.source), self.name(network.sink),
                f"value={network.flow_value()}", f"cost={network.total_cost()}",
            )
        for vertex, name in enumerate(network.names):
            self.emit(
                "NODE", name, f"demand={network.demands[vertex]}",
                f"out={network.outflow(vertex)}", f"in={network.inflow(vertex)}",
            )
        for edge in network.edges:
            self.emit(
                "EDGE", edge.number, self.name(edge.start), self.name(edge.end),
                f"cap={edge.capacity}", f"cost={edge.cost}",
                f"low={edge.lower}", f"flow={edge.flow}",
            )

    def augment(self, arguments):
        source, sink = self.require_endpoints(arguments)
        network = self.network
        network.start_flow(source, sink)
        result = network.graph().single_augmentation(source, sink, 1)
        value = f"value={network.flow_value()}"
        if result is None:
            self.emit("AUGMENT", arguments[0], arguments[1], value, "none")
        else:
            amount, path = result
            self.emit(
                "AUGMENT", arguments[0], arguments[1], value,
                f"amount={amount}", self.notation(source, path),
            )

    def maxflow(self, arguments):
        source, sink = self.require_endpoints(arguments)
        network = self.network
        start = network.start_flow(source, sink)
        pushes = network.graph().edmonds_karp(source, sink)
        self.emit(
            "MAXFLOW", arguments[0], arguments[1], f"value={network.flow_value()}",
            f"start={start}", f"paths={len(pushes)}",
        )
        for number, (amount, path) in enumerate(pushes, 1):
            self.emit("AUG", number, f"amount={amount}", self.notation(source, path))
        self.flow_list()

    def dinic(self, arguments):
        source, sink = self.require_endpoints(arguments)
        network = self.network
        start = network.start_flow(source, sink)
        phases, pushes = network.graph().dinic(source, sink)
        self.emit(
            "DINIC", arguments[0], arguments[1], f"value={network.flow_value()}",
            f"start={start}", f"phases={phases}", f"paths={len(pushes)}",
        )
        for number, (phase, amount, path) in enumerate(pushes, 1):
            self.emit(
                "AUG", number, f"phase={phase}", f"amount={amount}",
                self.notation(source, path),
            )
        self.flow_list()

    def scaling(self, arguments):
        source, sink = self.require_endpoints(arguments)
        network = self.network
        start = network.start_flow(source, sink)
        pushes = network.graph().capacity_scaling(source, sink)
        self.emit(
            "SCALING", arguments[0], arguments[1], f"value={network.flow_value()}",
            f"start={start}", f"paths={len(pushes)}",
        )
        for number, (delta, amount, path) in enumerate(pushes, 1):
            self.emit(
                "AUG", number, f"delta={delta}", f"amount={amount}",
                self.notation(source, path),
            )
        self.flow_list()

    def mincut(self, arguments):
        source, sink = self.require_endpoints(arguments)
        network = self.network
        network.start_flow(source, sink)
        graph = network.graph()
        graph.edmonds_karp(source, sink)
        level, _ = graph.breadth_first(source, 1)
        inside = [vertex_level is not None for vertex_level in level]
        cut = [edge for edge in network.edges if inside[edge.start] and not inside[edge.end]]
        self.emit(
            "MINCUT", arguments[0], arguments[1],
            f"value={network.flow_value()}", f"edges={len(cut)}",
        )
        self.emit("SOURCE", *(name for vertex, name in enumerate(network.names) if inside[vertex]))
        self.emit("SINK", *(name for vertex, name in enumerate(network.names) if not inside[vertex]))
        for edge in cut:
            self.emit("CUT", edge.number, self.name(edge.start), self.name(edge.end), edge.capacity)

    def sensitivity(self, arguments):
        source, sink = self.require_endpoints(arguments)
        network = self.network
        count = network.node_count()
        value = maximum_flow_amount(count, network.working_edges(), source, sink)
        critical = []
        for index, edge in enumerate(network.edges):
            raised = network.working_edges()
            raised[index].capacity += 1
            up = maximum_flow_amount(count, raised, source, sink) > value
            down = False
            if edge.capacity >= 1:
                lowered = network.working_edges()
                lowered[index].capacity -= 1
                down = maximum_flow_amount(count, lowered, source, sink) < value
            if up or down:
                critical.append((edge, up, down))
        ups = sum(up for _, up, _ in critical)
        downs = sum(down for _, _, down in critical)
        self.emit(
            "SENSITIVITY", arguments[0], arguments[1],
            f"value={value}", f"up={ups}", f"down={downs}",
        )
        for edge, up, down in critical:
            self.emit(
                "CRITICAL", edge.number, self.name(edge.start), self.name(edge.end),
                "up=" + ("yes" if up else "no"), "down=" + ("yes" if down else "no"),
            )

    def mincost(self, arguments):
        source, sink = self.require_endpoints(arguments)
        network = self.network
        usable = [edge for edge in network.edges if edge.capacity >= 1]
        if has_negative_cycle(network.node_count(), usable):
            raise CommandError("NEGATIVE CYCLE")
        target = None if arguments[2] == "MAX" else int(arguments[2])
        work = network.working_edges()
        graph = FlowGraph(network.node_count(), work)
        flow, cost, pushes = graph.successive_shortest_paths(source, sink, target)
        prefix = ("MINCOST", arguments[0], arguments[1], f"k={arguments[2]}")
        if target is not None and flow < target:
            self.emit(*prefix, "infeasible", f"max={flow}")
            return
        for edge, worked in zip(network.edges, work):
            edge.flow = worked.flow
        network.set_owner("flow", source, sink)
        self.emit(*prefix, f"flow={flow}", f"cost={cost}")
        for number, (amount, unit_cost, path) in enumerate(pushes, 1):
            self.emit(
                "AUG", number, f"amount={amount}", f"cost={unit_cost}",
                self.notation(source, path),
            )
        self.flow_list()

    def disjoint(self, arguments):
        source, sink = self.require_endpoints(arguments)
        mode = arguments[2]
        network = self.network
        count = network.node_count()
        exits = list(range(count))
        node_total = count
        if mode == "VERTEX":
            node_total = 2 * count
            for vertex in range(count):
                if vertex != source and vertex != sink:
                    exits[vertex] = count + vertex
        work = [
            Edge(edge.number, exits[edge.start], edge.end, min(edge.capacity, 1), 0)
            for edge in network.edges
        ]
        if mode == "VERTEX":
            for vertex in range(count):
                if vertex != source and vertex != sink:
                    work.append(Edge(len(work) + 1, vertex, exits[vertex], 1, 0))
        FlowGraph(node_total, work).edmonds_karp(source, sink)
        paths = [piece for piece in flow_decomposition(node_total, work) if not piece.cycle]
        self.emit("DISJOINT", arguments[0], arguments[1], mode, f"count={len(paths)}")
        limit = len(network.edges)
        for number, piece in enumerate(paths, 1):
            original = [edge for edge in piece.edges if edge.number <= limit]
            self.emit("PATH", number, self.notation(piece.start, forward_arcs(original)))

    def decompose(self, arguments):
        network = self.network
        pieces = flow_decomposition(network.node_count(), network.edges)
        cycles = sum(piece.cycle for piece in pieces)
        self.emit("DECOMPOSE", f"paths={len(pieces) - cycles}", f"cycles={cycles}")
        path_number = 0
        cycle_number = 0
        for piece in pieces:
            notation = self.notation(piece.start, forward_arcs(piece.edges))
            if piece.cycle:
                cycle_number += 1
                self.emit("CYCLE", cycle_number, f"amount={piece.amount}", notation)
            else:
                path_number += 1
                self.emit("PATH", path_number, f"amount={piece.amount}", notation)

    def verify(self, arguments):
        network = self.network
        violations = []
        for edge in network.edges:
            if edge.flow < edge.lower:
                violations.append(f"LOW {edge.number} flow={edge.flow} low={edge.lower}")
        for vertex, name in enumerate(network.names):
            if network.owner == "flow":
                if vertex == network.source or vertex == network.sink:
                    continue
                need = 0
            else:
                need = network.demands[vertex]
            net = network.inflow(vertex) - network.outflow(vertex)
            if net != need:
                violations.append(f"BALANCE {name} net={net} need={need}")
        if not violations:
            self.emit("VERIFY", "ok")
            return
        self.emit("VERIFY", f"violations={len(violations)}")
        for violation in violations:
            self.emit(violation)

    def circulation(self, arguments):
        mode = arguments[0]
        network = self.network
        count = network.node_count()
        if mode == "MINCOST":
            usable = [edge for edge in network.edges if edge.capacity - edge.lower >= 1]
            if has_negative_cycle(count, usable):
                raise CommandError("NEGATIVE CYCLE")
        imbalance = sum(network.demands)
        if imbalance != 0:
            self.emit("CIRCULATION", "infeasible", f"unbalanced={imbalance}")
            return
        required = list(network.demands)
        for edge in network.edges:
            required[edge.end] -= edge.lower
            required[edge.start] += edge.lower
        super_source = count
        super_sink = count + 1
        work = [
            Edge(edge.number, edge.start, edge.end, edge.capacity - edge.lower, edge.cost)
            for edge in network.edges
        ]
        for vertex in range(count):
            if required[vertex] < 0:
                work.append(Edge(len(work) + 1, super_source, vertex, -required[vertex], 0))
        sink_edges = []
        for vertex in range(count):
            if required[vertex] > 0:
                edge = Edge(len(work) + 1, vertex, super_sink, required[vertex], 0)
                work.append(edge)
                sink_edges.append(edge)
        graph = FlowGraph(count + 2, work)
        if mode == "ANY":
            graph.edmonds_karp(super_source, super_sink)
        else:
            graph.successive_shortest_paths(super_source, super_sink, None)
        total_required = sum(edge.capacity for edge in sink_edges)
        achieved = sum(edge.flow for edge in sink_edges)
        if achieved < total_required:
            self.emit(
                "CIRCULATION", "infeasible",
                f"required={total_required}", f"achieved={achieved}",
            )
            level, _ = graph.breadth_first(super_source, 1)
            self.emit("CUT", *(network.names[v] for v in range(count) if level[v] is not None))
            return
        for edge, worked in zip(network.edges, work):
            edge.flow = edge.lower + worked.flow
        network.set_owner("circulation", None, None)
        self.emit(
            "CIRCULATION", "feasible",
            f"required={total_required}", f"cost={network.total_cost()}",
        )
        self.flow_list()

    def match(self, arguments):
        left_names = arguments[0].split(",")
        right_names = arguments[1].split(",")
        pairs = [] if arguments[2] == "-" else arguments[2].split(",")
        left_index = {}
        for name in left_names:
            if name in left_index:
                raise CommandError(f"DUPLICATE VERTEX {name}")
            left_index[name] = len(left_index)
        right_index = {}
        for name in right_names:
            if name in right_index or name in left_index:
                raise CommandError(f"DUPLICATE VERTEX {name}")
            right_index[name] = len(right_index)
        links = []
        for pair in pairs:
            left, right = pair.split("-")
            if left not in left_index:
                raise CommandError(f"UNKNOWN VERTEX {left}")
            if right not in right_index:
                raise CommandError(f"UNKNOWN VERTEX {right}")
            link = (left_index[left], right_index[right])
            if link in links:
                raise CommandError(f"DUPLICATE PAIR {left}-{right}")
            links.append(link)
        matching = BipartiteMatching(len(left_names), len(right_names), links)
        left_partner = matching.left_partner
        right_partner = matching.right_partner
        size = sum(partner is not None for partner in left_partner)
        self.emit("MATCH", f"size={size}", f"left={len(left_names)}", f"right={len(right_names)}")
        for a, partner in enumerate(left_partner):
            if partner is not None:
                self.emit("PAIR", left_names[a], right_names[partner])
        free_left = [left_names[a] for a, p in enumerate(left_partner) if p is None]
        free_right = [right_names[b] for b, p in enumerate(right_partner) if p is None]
        self.emit("FREE", ",".join(free_left) or "-", ",".join(free_right) or "-")
        left_in, right_in = matching.alternating_set()
        cover = [name for a, name in enumerate(left_names) if not left_in[a]]
        cover += [name for b, name in enumerate(right_names) if right_in[b]]
        self.emit("COVER", f"size={len(cover)}", *cover)
        if free_left:
            hall_left = [name for a, name in enumerate(left_names) if left_in[a]]
            hall_right = [name for b, name in enumerate(right_names) if right_in[b]]
            self.emit("HALL", ",".join(hall_left), ",".join(hall_right) or "-")

    def assign(self, arguments):
        mode = arguments[0]
        size = int(arguments[1])
        values = arguments[2:]
        if size < MIN_ASSIGN_SIZE or size > MAX_ASSIGN_SIZE:
            raise CommandError("BAD SIZE")
        if len(values) != size * size:
            raise CommandError("BAD LENGTH")
        table = [
            [None if text == "x" else int(text) for text in values[row * size:(row + 1) * size]]
            for row in range(size)
        ]
        solver = AssignmentSolver(table, mode == "MAX")
        if not solver.feasible():
            self.emit("ASSIGN", mode, f"n={size}", "infeasible")
            return
        total, optimal = solver.optimum()
        self.emit("ASSIGN", mode, f"n={size}", f"total={total}", f"optimal={optimal}")
        for row, column in enumerate(solver.chosen_columns()):
            self.emit("MATE", row + 1, column + 1, table[row][column])

    def execute(self, line):
        command, *arguments = line.split(" ")
        try:
            self.handlers[command](arguments)
        except CommandError as error:
            self.emit("ERROR", error)


def main():
    solver = FlowSolver()
    count = int(sys.stdin.readline())
    for _ in range(count):
        solver.execute(sys.stdin.readline().rstrip("\n"))
    sys.stdout.write("\n".join(solver.output) + "\n")


if __name__ == "__main__":
    main()
