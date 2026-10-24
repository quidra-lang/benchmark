"""DC circuit analysis by exact modified nodal analysis."""

import math
import re
import sys
from collections import Counter, defaultdict
from dataclasses import dataclass, replace
from fractions import Fraction
from itertools import count

GROUND = "0"
NODE_PATTERN = re.compile(r"0|[a-z][a-z0-9]{0,7}")
MANTISSA_PATTERN = re.compile(r"[0-9]+(\.[0-9]+|/[0-9]+)?")
SUFFIXES = (
    ("meg", Fraction(1_000_000)),
    ("k", Fraction(1000)),
    ("m", Fraction(1, 1000)),
    ("u", Fraction(1, 1_000_000)),
)
FIELD_COUNTS = {"R": 4, "V": 4, "I": 4, "E": 6, "G": 6, "F": 5, "H": 5}
VOLTAGE_SOURCES = {"V", "E", "H"}
INDEPENDENT_SOURCES = {"V", "I"}
GROUNDING_TYPES = {"R", "V", "E", "H"}
MAX_SWEEP_POINTS = 20


class CircuitError(Exception):
    pass


@dataclass
class Element:
    name: str
    n1: str
    n2: str
    value: Fraction
    c1: str | None = None
    c2: str | None = None
    vname: str | None = None

    @property
    def kind(self):
        return self.name[0]

    @property
    def terminals(self):
        if self.c1 is None:
            return (self.n1, self.n2)
        return (self.n1, self.n2, self.c1, self.c2)

    def __str__(self):
        fields = [self.name, *self.terminals]
        if self.vname is not None:
            fields.append(self.vname)
        fields.append(str(self.value))
        return " ".join(fields)


@dataclass
class Resistor:
    name: str
    end1: str
    end2: str
    resistance: Fraction

    @property
    def ends(self):
        return (self.end1, self.end2)

    def other_end(self, node):
        return self.end2 if self.end1 == node else self.end1


def parse_number(word):
    multiplier = 1
    for suffix, factor in SUFFIXES:
        if word.endswith(suffix):
            word = word.removesuffix(suffix)
            multiplier = factor
            break
    sign = 1
    if word.startswith("-"):
        word = word[1:]
        sign = -1
    if not MANTISSA_PATTERN.fullmatch(word):
        return None
    try:
        mantissa = Fraction(word)
    except ZeroDivisionError:
        return None
    return sign * multiplier * mantissa


def check_number(word):
    value = parse_number(word)
    if value is None:
        raise CircuitError(f"invalid value {word}")
    return value


def format_decimal(x):
    whole, fraction = divmod(math.floor(abs(x) * 1_000_000), 1_000_000)
    sign = "-" if x < 0 else ""
    return f"{sign}{whole}.{fraction:06d}"


def format_value(x):
    return f"{x} ({format_decimal(x)})"


def circuit_nodes(elements):
    return sorted({node for e in elements for node in e.terminals} - {GROUND})


def reachable(start, links):
    neighbors = defaultdict(list)
    for u, v in links:
        neighbors[u].append(v)
        neighbors[v].append(u)
    seen = {start}
    pending = [start]
    while pending:
        node = pending.pop()
        for neighbor in neighbors[node]:
            if neighbor not in seen:
                seen.add(neighbor)
                pending.append(neighbor)
    return seen


def floating_nodes(elements):
    links = [(e.n1, e.n2) for e in elements if e.kind in GROUNDING_TYPES]
    grounded = reachable(GROUND, links)
    return [node for node in circuit_nodes(elements) if node not in grounded]


def voltage_loops(elements):
    loops = []
    links = []
    for e in elements:
        if e.kind in VOLTAGE_SOURCES:
            # n1 is always reachable from itself, so n1 == n2 is a loop too.
            if e.n2 in reachable(e.n1, links):
                loops.append(e.name)
            links.append((e.n1, e.n2))
    return loops


def check_structure(elements):
    if not circuit_nodes(elements):
        raise CircuitError("no nodes")
    floating = floating_nodes(elements)
    if floating:
        raise CircuitError(f"floating node {floating[0]}")
    loops = voltage_loops(elements)
    if loops:
        raise CircuitError(f"voltage source loop at {loops[0]}")


def gauss_jordan(matrix, column):
    size = len(matrix)
    rows = [row + [value] for row, value in zip(matrix, column)]
    for k in range(size):
        pivot = next((r for r in range(k, size) if rows[r][k] != 0), None)
        if pivot is None:
            return None
        rows[k], rows[pivot] = rows[pivot], rows[k]
        divisor = rows[k][k]
        rows[k] = [value / divisor for value in rows[k]]
        for i in range(size):
            factor = rows[i][k]
            if i != k and factor != 0:
                rows[i] = [
                    value - factor * pivot_value
                    for value, pivot_value in zip(rows[i], rows[k])
                ]
    return [row[size] for row in rows]


def source_entries(source, value):
    if source.kind == "I":
        return [(source.n1, -value), (source.n2, value)]
    return [(source.name, value)]


def sensitivity_entries(element, operating):
    n1, n2 = element.n1, element.n2
    match element.kind:
        case "R":
            t = operating.element_current(element) / element.value
            return [(n1, t), (n2, -t)]
        case "I":
            return [(n1, -1), (n2, 1)]
        case "G":
            t = operating.difference(element.c1, element.c2)
            return [(n1, -t), (n2, t)]
        case "F":
            t = operating.current(element.vname)
            return [(n1, -t), (n2, t)]
        case "V":
            return [(element.name, 1)]
        case "E":
            return [(element.name, operating.difference(element.c1, element.c2))]
        case "H":
            return [(element.name, operating.current(element.vname))]


class Solution:
    def __init__(self, index, values):
        self.index = index
        self.values = values

    def voltage(self, node):
        if node == GROUND:
            return Fraction(0)
        return self.values[self.index[node]]

    def difference(self, node1, node2):
        return self.voltage(node1) - self.voltage(node2)

    def current(self, name):
        return self.values[self.index[name]]

    def element_current(self, element):
        match element.kind:
            case "R":
                return self.difference(element.n1, element.n2) / element.value
            case "I":
                return element.value
            case "G":
                return element.value * self.difference(element.c1, element.c2)
            case "F":
                return element.value * self.current(element.vname)
            case _:
                return self.current(element.name)


class Equations:
    def __init__(self, elements):
        self.nodes = circuit_nodes(elements)
        self.voltage_sources = [e for e in elements if e.kind in VOLTAGE_SOURCES]
        self.unknowns = self.nodes + [e.name for e in self.voltage_sources]
        self.index = {key: i for i, key in enumerate(self.unknowns)}
        size = len(self.unknowns)
        self.matrix = [[Fraction(0)] * size for _ in range(size)]
        for element in elements:
            self.stamp(element)
        self.rhs = self.column(
            entry
            for e in elements
            if e.kind in INDEPENDENT_SOURCES
            for entry in source_entries(e, e.value)
        )

    def add(self, row, column, value):
        if row != GROUND and column != GROUND:
            self.matrix[self.index[row]][self.index[column]] += value

    def stamp(self, element):
        n1, n2, w = element.n1, element.n2, element.value
        match element.kind:
            case "R":
                g = 1 / w
                self.add(n1, n1, g)
                self.add(n2, n2, g)
                self.add(n1, n2, -g)
                self.add(n2, n1, -g)
            case "G":
                self.add(n1, element.c1, w)
                self.add(n2, element.c2, w)
                self.add(n1, element.c2, -w)
                self.add(n2, element.c1, -w)
            case "F":
                self.add(n1, element.vname, w)
                self.add(n2, element.vname, -w)
            case "V" | "E" | "H":
                s = element.name
                self.add(n1, s, 1)
                self.add(s, n1, 1)
                self.add(n2, s, -1)
                self.add(s, n2, -1)
                if element.kind == "E":
                    self.add(s, element.c1, -w)
                    self.add(s, element.c2, w)
                elif element.kind == "H":
                    self.add(s, element.vname, -w)

    def column(self, entries):
        column = [Fraction(0)] * len(self.unknowns)
        for key, value in entries:
            if key != GROUND:
                column[self.index[key]] += value
        return column

    def solve(self, column):
        values = gauss_jordan(self.matrix, column)
        if values is None:
            return None
        return Solution(self.index, values)

    def injection(self, source_node, sink_node):
        return self.solve(self.column([(source_node, 1), (sink_node, -1)]))

    def source_alone(self, source, value):
        return self.solve(self.column(source_entries(source, value)))


def reduction_step(resistors, a, b, names):
    for resistor in resistors:
        if resistor.end1 == resistor.end2:
            resistors.remove(resistor)
            return f"remove {resistor.name}"
    degree = Counter(end for r in resistors for end in r.ends)
    internal = sorted(node for node in degree if node not in (a, b))
    for node in internal:
        if degree[node] == 1:
            resistor = next(r for r in resistors if node in r.ends)
            resistors.remove(resistor)
            return f"remove {resistor.name}"
    for i, x in enumerate(resistors):
        partners = [r for r in resistors[i + 1 :] if set(r.ends) == set(x.ends)]
        if partners:
            y = partners[0]
            resistance = x.resistance * y.resistance / (x.resistance + y.resistance)
            merged = Resistor(next(names), x.end1, x.end2, resistance)
            resistors.remove(x)
            resistors.remove(y)
            resistors.append(merged)
            return f"{merged.name} = {x.name} || {y.name} = {format_value(resistance)}"
    for node in internal:
        if degree[node] == 2:
            x, y = [r for r in resistors if node in r.ends]
            resistance = x.resistance + y.resistance
            u, v = x.other_end(node), y.other_end(node)
            merged = Resistor(next(names), u, v, resistance)
            resistors.remove(x)
            resistors.remove(y)
            resistors.append(merged)
            return f"{merged.name} = {x.name} + {y.name} = {format_value(resistance)}"
    return None


class Circuit:
    def __init__(self):
        self.elements = []

    def find(self, name):
        return next((e for e in self.elements if e.name == name), None)

    def check_element(self, name):
        element = self.find(name)
        if element is None:
            raise CircuitError(f"unknown element {name}")
        return element

    def check_node(self, node):
        if node != GROUND and node not in circuit_nodes(self.elements):
            raise CircuitError(f"unknown node {node}")

    def operating_point(self):
        check_structure(self.elements)
        equations = Equations(self.elements)
        operating = equations.solve(equations.rhs)
        if operating is None:
            raise CircuitError("singular matrix")
        return equations, operating

    def add_element(self, words):
        name = words[0]
        kind = name[0]
        if kind not in FIELD_COUNTS:
            raise CircuitError(f"unknown element type {name}")
        if len(words) != FIELD_COUNTS[kind]:
            raise CircuitError(f"wrong field count for {name}")
        if self.find(name) is not None:
            raise CircuitError(f"duplicate element {name}")
        nodes = words[1:5] if kind in ("E", "G") else words[1:3]
        for node in nodes:
            if not NODE_PATTERN.fullmatch(node):
                raise CircuitError(f"invalid node {node}")
        vname = None
        if kind in ("F", "H"):
            vname = words[3]
            source = self.find(vname)
            if source is None or source.kind != "V":
                raise CircuitError(f"unknown voltage source {vname}")
        value = check_number(words[-1])
        if kind == "R" and value <= 0:
            raise CircuitError(f"nonpositive resistance {name}")
        n1, n2, *controls = nodes
        self.elements.append(Element(name, n1, n2, value, *controls, vname=vname))

    def run_command(self, words):
        command, *arguments = words
        if command not in COMMANDS:
            raise CircuitError(f"unknown command {command}")
        handler, argument_count = COMMANDS[command]
        if len(arguments) != argument_count:
            raise CircuitError(f"wrong argument count for {command}")
        return handler(self, *arguments)

    def op(self):
        equations, operating = self.operating_point()
        lines = [
            f"V({node}) = {format_value(operating.voltage(node))}"
            for node in equations.nodes
        ]
        lines += [
            f"I({e.name}) = {format_value(operating.current(e.name))}"
            for e in equations.voltage_sources
        ]
        return lines

    def current(self, name):
        element = self.check_element(name)
        _, operating = self.operating_point()
        return [f"I({name}) = {format_value(operating.element_current(element))}"]

    def voltage(self, a, b):
        self.check_node(a)
        self.check_node(b)
        _, operating = self.operating_point()
        return [f"V({a},{b}) = {format_value(operating.difference(a, b))}"]

    def power(self):
        _, operating = self.operating_point()
        lines = []
        absorbed = delivered = total = Fraction(0)
        for e in self.elements:
            p = operating.difference(e.n1, e.n2) * operating.element_current(e)
            lines.append(f"P({e.name}) = {format_value(p)}")
            if p > 0:
                absorbed += p
            elif p < 0:
                delivered -= p
            total += p
        lines.append(f"absorbed = {format_value(absorbed)}")
        lines.append(f"delivered = {format_value(delivered)}")
        lines.append(f"total = {format_value(total)}")
        return lines

    def kcl(self, a):
        self.check_node(a)
        _, operating = self.operating_point()
        lines = []
        total = Fraction(0)
        for e in self.elements:
            if a not in (e.n1, e.n2):
                continue
            if e.n1 == e.n2:
                leaving = Fraction(0)
            elif e.n1 == a:
                leaving = operating.element_current(e)
            else:
                leaving = -operating.element_current(e)
            lines.append(f"I({e.name}) leaving {a} = {format_value(leaving)}")
            total += leaving
        lines.append(f"sum = {format_value(total)}")
        return lines

    def thevenin_equivalent(self, a, b):
        self.check_node(a)
        self.check_node(b)
        equations, operating = self.operating_point()
        vth = operating.difference(a, b)
        rth = equations.injection(a, b).difference(a, b)
        return vth, rth

    def thevenin(self, a, b):
        vth, rth = self.thevenin_equivalent(a, b)
        return [f"Vth = {format_value(vth)}", f"Rth = {format_value(rth)}"]

    def norton(self, a, b):
        vth, rth = self.thevenin_equivalent(a, b)
        if rth == 0:
            raise CircuitError("zero thevenin resistance")
        return [f"In = {format_value(vth / rth)}", f"Rn = {format_value(rth)}"]

    def maxpower(self, a, b):
        vth, rth = self.thevenin_equivalent(a, b)
        if rth <= 0:
            raise CircuitError("nonpositive thevenin resistance")
        pmax = (vth * vth) / (4 * rth)
        return [f"RL = {format_value(rth)}", f"Pmax = {format_value(pmax)}"]

    def tf(self, a, name):
        self.check_node(a)
        source = self.check_element(name)
        if source.kind not in INDEPENDENT_SOURCES:
            raise CircuitError(f"not an independent source {name}")
        equations, _ = self.operating_point()
        unit = equations.source_alone(source, 1)
        lines = [f"gain = {format_value(unit.voltage(a))}"]
        if source.kind == "V":
            j = unit.current(name)
            if j == 0:
                lines.append("input resistance = INFINITE")
            else:
                lines.append(f"input resistance = {format_value(-1 / j)}")
        else:
            resistance = unit.difference(source.n2, source.n1)
            lines.append(f"input resistance = {format_value(resistance)}")
        output_resistance = equations.injection(a, GROUND).voltage(a)
        lines.append(f"output resistance = {format_value(output_resistance)}")
        return lines

    def sens(self, a):
        self.check_node(a)
        equations, operating = self.operating_point()
        lines = []
        for e in self.elements:
            column = equations.column(sensitivity_entries(e, operating))
            derivative = equations.solve(column).voltage(a)
            lines.append(f"dV({a})/d{e.name} = {format_value(derivative)}")
        return lines

    def zparam(self, a, b, c, d):
        for node in (a, b, c, d):
            self.check_node(node)
        equations, _ = self.operating_point()
        z1 = equations.injection(a, b)
        z2 = equations.injection(c, d)
        return [
            f"z11 = {format_value(z1.difference(a, b))}",
            f"z12 = {format_value(z2.difference(a, b))}",
            f"z21 = {format_value(z1.difference(c, d))}",
            f"z22 = {format_value(z2.difference(c, d))}",
        ]

    def superposition(self, a):
        self.check_node(a)
        equations, _ = self.operating_point()
        lines = []
        total = Fraction(0)
        for e in self.elements:
            if e.kind in INDEPENDENT_SOURCES:
                contribution = equations.source_alone(e, e.value).voltage(a)
                lines.append(f"{e.name}: V({a}) = {format_value(contribution)}")
                total += contribution
        lines.append(f"total: V({a}) = {format_value(total)}")
        return lines

    def sweep(self, name, first_word, last_word, step_word, a):
        element = self.check_element(name)
        first = check_number(first_word)
        last = check_number(last_word)
        step = check_number(step_word)
        self.check_node(a)
        if step <= 0:
            raise CircuitError("invalid sweep step")
        if first > last:
            raise CircuitError("invalid sweep range")
        point_count = (last - first) // step + 1
        if point_count > MAX_SWEEP_POINTS:
            raise CircuitError("too many sweep points")
        if element.kind == "R" and first <= 0:
            raise CircuitError(f"nonpositive resistance {name}")
        check_structure(self.elements)
        lines = []
        for k in range(point_count):
            x = first + k * step
            trial = [replace(e, value=x) if e is element else e for e in self.elements]
            equations = Equations(trial)
            solution = equations.solve(equations.rhs)
            if solution is None:
                lines.append(f"{name} = {x}: singular matrix")
            else:
                voltage = format_value(solution.voltage(a))
                lines.append(f"{name} = {x}: V({a}) = {voltage}")
        return lines

    def matrix(self):
        check_structure(self.elements)
        equations = Equations(self.elements)
        names = [f"V({node})" for node in equations.nodes]
        names += [f"I({e.name})" for e in equations.voltage_sources]
        lines = ["unknowns: " + " ".join(names)]
        rows = zip(equations.unknowns, equations.matrix, equations.rhs)
        for label, row, value in rows:
            entries = " ".join(str(entry) for entry in row)
            lines.append(f"{label}: {entries} | {value}")
        return lines

    def req(self, a, b):
        self.check_node(a)
        self.check_node(b)
        wires = [(e.n1, e.n2) for e in self.elements if e.kind == "V"]
        group = {}
        for node in [GROUND, *circuit_nodes(self.elements)]:
            if node not in group:
                for member in reachable(node, wires):
                    group[member] = node
        if group[a] == group[b]:
            return ["Req = 0 (0.000000)"]
        edges = [
            (group[e.n1], group[e.n2], 1 / e.value)
            for e in self.elements
            if e.kind == "R" and group[e.n1] != group[e.n2]
        ]
        reached = reachable(group[a], [(p, q) for p, q, _ in edges])
        if group[b] not in reached:
            return ["Req = INFINITE"]
        index = {g: i for i, g in enumerate(sorted(reached - {group[b]}))}
        size = len(index)
        matrix = [[Fraction(0)] * size for _ in range(size)]
        for p, q, conductance in edges:
            if p not in reached:
                continue
            stamps = (
                (p, p, conductance),
                (q, q, conductance),
                (p, q, -conductance),
                (q, p, -conductance),
            )
            for row, column, value in stamps:
                if row in index and column in index:
                    matrix[index[row]][index[column]] += value
        injected = [Fraction(0)] * size
        injected[index[group[a]]] = Fraction(1)
        solution = gauss_jordan(matrix, injected)
        return [f"Req = {format_value(solution[index[group[a]]])}"]

    def reduce(self, a, b):
        self.check_node(a)
        self.check_node(b)
        if a == b:
            return ["Req = 0 (0.000000)"]
        resistors = [
            Resistor(e.name, e.n1, e.n2, e.value)
            for e in self.elements
            if e.kind == "R"
        ]
        connected = reachable(a, [r.ends for r in resistors])
        if b not in connected:
            return ["Req = INFINITE"]
        resistors = [r for r in resistors if r.end1 in connected]
        names = (f"#{k}" for k in count(1))
        lines = []
        while (line := reduction_step(resistors, a, b, names)) is not None:
            lines.append(line)
        if len(resistors) == 1:
            lines.append(f"Req = {format_value(resistors[0].resistance)}")
        else:
            lines.append(f"not series-parallel: {len(resistors)} resistors remain")
        return lines

    def check(self):
        nodes = circuit_nodes(self.elements)
        if not nodes:
            return ["no nodes"]
        degree = Counter(end for e in self.elements for end in (e.n1, e.n2))
        lines = [f"dangling node {node}" for node in nodes if degree[node] < 2]
        lines += [f"floating node {node}" for node in floating_nodes(self.elements)]
        lines += [
            f"voltage source loop at {name}" for name in voltage_loops(self.elements)
        ]
        if not lines:
            equations = Equations(self.elements)
            if equations.solve(equations.rhs) is None:
                lines.append("singular matrix")
        return lines or ["ok"]

    def alter(self, name, value_word):
        element = self.check_element(name)
        value = check_number(value_word)
        if element.kind == "R" and value <= 0:
            raise CircuitError(f"nonpositive resistance {name}")
        line = f"altered {name}: {element.value} -> {value}"
        element.value = value
        return [line]

    def delete(self, name):
        element = self.check_element(name)
        dependent = next((e for e in self.elements if e.vname == name), None)
        if dependent is not None:
            raise CircuitError(f"{name} is referenced by {dependent.name}")
        self.elements.remove(element)
        return [f"deleted {name}"]

    def clear(self):
        removed = len(self.elements)
        self.elements = []
        return [f"cleared {removed} elements"]

    def list_nodes(self):
        if not self.elements:
            return ["no nodes"]
        lines = []
        for node in sorted({t for e in self.elements for t in e.terminals}):
            names = [e.name for e in self.elements if node in e.terminals]
            lines.append(f"{node}: {' '.join(names)}")
        return lines

    def print_netlist(self):
        return [str(e) for e in self.elements] or ["empty netlist"]


COMMANDS = {
    ".OP": (Circuit.op, 0),
    ".CURRENT": (Circuit.current, 1),
    ".VOLTAGE": (Circuit.voltage, 2),
    ".POWER": (Circuit.power, 0),
    ".KCL": (Circuit.kcl, 1),
    ".THEVENIN": (Circuit.thevenin, 2),
    ".NORTON": (Circuit.norton, 2),
    ".MAXPOWER": (Circuit.maxpower, 2),
    ".TF": (Circuit.tf, 2),
    ".SENS": (Circuit.sens, 1),
    ".ZPARAM": (Circuit.zparam, 4),
    ".SUPERPOSITION": (Circuit.superposition, 1),
    ".SWEEP": (Circuit.sweep, 5),
    ".MATRIX": (Circuit.matrix, 0),
    ".REQ": (Circuit.req, 2),
    ".REDUCE": (Circuit.reduce, 2),
    ".CHECK": (Circuit.check, 0),
    ".ALTER": (Circuit.alter, 2),
    ".DELETE": (Circuit.delete, 1),
    ".CLEAR": (Circuit.clear, 0),
    ".NODES": (Circuit.list_nodes, 0),
    ".PRINT": (Circuit.print_netlist, 0),
}


def main():
    circuit = Circuit()
    for number, line in enumerate(sys.stdin, start=1):
        line = line.rstrip("\n")
        if line == ".END":
            break
        if line.startswith("*"):
            continue
        words = line.split()
        try:
            if line.startswith("."):
                output = circuit.run_command(words)
            else:
                circuit.add_element(words)
                output = []
        except CircuitError as error:
            output = [f"error: line {number}: {error}"]
        for text in output:
            print(text)


if __name__ == "__main__":
    main()
