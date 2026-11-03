"""Design and analyze a plane truss, its moving loads, modes and drawings."""

from bisect import bisect_right
from math import floor, sqrt
from pathlib import Path
from types import SimpleNamespace

from assembly import assemble, load_vectors, member_geometry, member_properties, member_weight
from design import PI, buckling, select_section, slenderness, slenderness_limit, utilization
from model_io import read_model
from postprocess import Result, axial_forces, equilibrium_residual, reactions, superpose
from solver import cholesky, solve


def total(values):
    result = 0.0
    for value in values:
        result += value
    return result


def real(value, digits=4):
    text = format(value, f".{digits}f")
    return text[1:] if text.startswith("-") and float(text) == 0 else text


def rounded(value):
    return float(real(value))


def select(items, key, minimum=False):
    operation = min if minimum else max
    return operation(items, key=lambda item: rounded(key(item)))


def extreme_index(values, minimum=False):
    return select(range(len(values)), lambda index: values[index], minimum)


def write_lines(name, lines):
    with open("output/" + name, "w", encoding="ascii", newline="\n") as destination:
        for line in lines:
            destination.write(line + "\n")


def renumber(nodes, members):
    neighbors = [set() for _ in nodes]
    for member in members:
        neighbors[member.start].add(member.end)
        neighbors[member.end].add(member.start)
    key = lambda node: (len(neighbors[node]), nodes[node].identifier)
    queue = [min(range(len(nodes)), key=key)]
    visited = set(queue)
    for node in queue:
        following = sorted(neighbors[node] - visited, key=key)
        queue.extend(following)
        visited.update(following)
    return queue[::-1], neighbors


def numbering_metrics(numbers, neighbors, members):
    bandwidth = max(abs(numbers[member.start] - numbers[member.end]) for member in members)
    profile = sum(numbers[node] - min(numbers[item] for item in adjacent | {node})
                  for node, adjacent in enumerate(neighbors))
    return bandwidth, profile


class Canvas:
    def __init__(self, nodes, horizontal, vertical):
        self.x0 = min(node.x for node in nodes)
        self.x1 = max(node.x for node in nodes)
        self.y0 = min(node.y for node in nodes)
        self.y1 = max(node.y for node in nodes)
        self.horizontal, self.vertical = horizontal, vertical
        self.width = floor((self.x1 - self.x0) / horizontal + 0.5) + 5
        self.height = floor((self.y1 - self.y0) / vertical + 0.5) + 5
        self.grid = [[" "] * self.width for _ in range(self.height)]

    def position(self, x, y):
        return (floor((x - self.x0) / self.horizontal + 0.5) + 2,
                floor((self.y1 - y) / self.vertical + 0.5) + 2)

    def put(self, column, row, character):
        if 0 <= column < self.width and 0 <= row < self.height:
            self.grid[row][column] = character

    def line(self, first, last, character):
        column, row = first
        final_column, final_row = last
        dc, dr = abs(final_column - column), -abs(final_row - row)
        sc = 1 if column < final_column else -1
        sr = 1 if row < final_row else -1
        error = dc + dr
        while True:
            self.put(column, row, character)
            if (column, row) == last:
                break
            twice = 2 * error
            if twice >= dr:
                error += dr
                column += sc
            if twice <= dc:
                error += dc
                row += sr

    def framed(self):
        border = "+" + "-" * self.width + "+"
        return [border] + ["|" + "".join(row) + "|" for row in self.grid] + [border]


class Truss:
    def __init__(self, model):
        self.model = model
        self.nodes, self.members = model.nodes, model.members
        self.settings = model.settings
        self.order, self.neighbors = renumber(self.nodes, self.members)
        self.numbers = [0] * len(self.nodes)
        for number, node in enumerate(self.order):
            self.numbers[node] = number
        self.node_dofs = [(2 * number, 2 * number + 1) for number in self.numbers]
        self.degrees = 2 * len(self.nodes)
        self.owners = [None] * self.degrees
        for node, directions in enumerate(self.node_dofs):
            for axis, degree in enumerate(directions):
                self.owners[degree] = node, axis
        self.prescribed = [0.0] * self.degrees
        self.support_directions = []
        for support in model.supports:
            for axis in range(2):
                if support.fixed[axis]:
                    degree = self.node_dofs[support.node][axis]
                    self.prescribed[degree] = support.prescribed[axis]
                    self.support_directions.append((support.node, axis, degree))
        self.restrained = sorted(degree for _, _, degree in self.support_directions)
        restrained = set(self.restrained)
        self.free = [degree for degree in range(self.degrees) if degree not in restrained]
        self.geometry = member_geometry(self.nodes, self.members, self.node_dofs)
        self.groups = {}
        for number, member in enumerate(self.members):
            self.groups.setdefault(member.group, []).append(number)
        self.combination_definitions = {combination.name: combination for combination in model.combinations}
        self.result_order = [("case", case.name) for case in model.cases]
        self.result_order.extend(("combination", combination.name) for combination in model.combinations)
        self.deck = self.settings["deck"]
        self.deck_x = [self.nodes[node].x for node in self.deck]
        self.units = {}

    def system(self, choices, removed=None):
        properties = member_properties(self.model, choices, self.geometry)
        matrix = assemble(self.geometry, properties, self.degrees, removed)
        free_matrix = [[matrix[row][column] for column in self.free] for row in self.free]
        lower, unstable = cholesky(free_matrix, self.free)
        return SimpleNamespace(properties=properties, matrix=matrix, free_matrix=free_matrix,
                               lower=lower, unstable=unstable, removed=removed)

    def displacement(self, system, force, settlement=False):
        displacement = [0.0] * self.degrees
        for degree in self.restrained:
            displacement[degree] = self.prescribed[degree] if settlement else 0.0
        right = []
        for degree in self.free:
            value = force[degree]
            for restrained in self.restrained:
                value -= system.matrix[degree][restrained] * displacement[restrained]
            right.append(value)
        solution = solve(system.lower, right)
        for degree, value in zip(self.free, solution):
            displacement[degree] = value
        return displacement

    def case_result(self, system, case):
        loading = load_vectors(case, self.geometry, system.properties, self.node_dofs,
                               self.degrees, system.removed)
        displacement = self.displacement(system, loading.total, loading.settlement)
        forces = axial_forces(self.geometry, system.properties, displacement,
                              loading.temperature, system.removed)
        reaction = reactions(system.matrix, displacement, loading.total, self.restrained)
        return Result(case.name, displacement, forces, reaction, loading.external)

    def analyze(self, system, combination=None):
        combinations = self.model.combinations if combination is None else [combination]
        needed = {name for item in combinations for name, _ in item.terms}
        results = {}
        for case in self.model.cases:
            if combination is None or case.name in needed:
                results[case.name] = self.case_result(system, case)
        for item in combinations:
            results[item.name] = superpose(item, results)
        return results

    def unit_result(self, node):
        if node not in self.units:
            force = [0.0] * self.degrees
            force[self.node_dofs[node][1]] = -1000.0
            displacement = self.displacement(self.final_system, force)
            temperature = [0.0] * len(self.members)
            forces = axial_forces(self.geometry, self.properties, displacement, temperature)
            reaction = reactions(self.final_system.matrix, displacement, force, self.restrained)
            self.units[node] = Result("unit", displacement, forces, reaction, force)
        return self.units[node]

    def design_sections(self):
        choices = [member.section for member in self.members]
        history = []
        for round_number in range(1, 11):
            system = self.system(choices)
            results = self.analyze(system)
            combinations = [results[item.name] for item in self.model.combinations]
            limits = [slenderness_limit(number, combinations, self.settings["slenderness"])
                      for number in range(len(self.members))]
            utilizations = [[utilization(result.forces[number], member, shape) for result in combinations]
                            for number, (member, shape) in enumerate(zip(system.properties, self.geometry))]
            maximum = select(((value, number, case) for number, row in enumerate(utilizations)
                              for case, value in enumerate(row)), lambda item: item[0])
            weight = total(member_weight(member, shape) for member, shape in zip(system.properties, self.geometry))
            changes = []
            for name, members in self.groups.items():
                chosen = select_section(members, self.model.sections, system.properties,
                                        self.geometry, combinations, limits)
                current = choices[members[0]]
                if chosen != current:
                    largest = select((value for number in members for value in utilizations[number]), lambda value: value)
                    changes.append((name, current, chosen, largest))
            value, member, case = maximum
            history.append(f"round {round_number} weight {real(weight / 1000)} max_utilization {real(value)} "
                           f"at {self.members[member].identifier} {combinations[case].name} changes {len(changes)}")
            for name, current, chosen, largest in changes:
                history.append(f"change {name} {self.model.sections[current].name} {self.model.sections[chosen].name} "
                               f"utilization {real(largest)}")
            converged = not changes
            if converged or round_number == 10:
                break
            for name, _, chosen, _ in changes:
                for member in self.groups[name]:
                    choices[member] = chosen
        self.choices, self.final_system = choices, system
        self.properties, self.results = system.properties, results
        self.combinations, self.limits = combinations, limits
        self.utilizations, self.weight = utilizations, weight
        self.governing_cases = [extreme_index(row) for row in utilizations]
        self.governing = [row[case] for row, case in zip(utilizations, self.governing_cases)]
        status = "converged" if converged else "not_converged"
        history.append(f"result {status} rounds {round_number}")
        return history

    def design_report(self, history):
        lines = list(history)
        for name, members in self.groups.items():
            member = select(members, lambda number: self.governing[number])
            section = self.model.sections[self.choices[members[0]]].name
            lines.append(f"group {name} section {section} members {len(members)} "
                         f"utilization {real(self.governing[member])} at {self.members[member].identifier}")
        for number, (member, properties, shape) in enumerate(zip(self.members, self.properties, self.geometry)):
            section = self.model.sections[self.choices[number]].name
            utilization_value = self.governing[number]
            slender = slenderness(properties, shape)
            limit = self.limits[number]
            verdict = "ok" if utilization_value <= 1 and slender <= limit else "over"
            combination = self.combinations[self.governing_cases[number]].name
            lines.append(f"member {member.identifier} group {member.group} section {section} "
                         f"utilization {real(utilization_value)} governing {combination} slenderness {real(slender)} "
                         f"limit {real(limit)} {verdict}")
        ranking = sorted(range(len(self.members)), key=lambda number: -rounded(self.governing[number]))
        for rank, number in enumerate(ranking[:5], 1):
            lines.append(f"rank {rank} member {self.members[number].identifier} utilization {real(self.governing[number])}")
        for number, member in enumerate(self.members):
            values = [result.forces[number] / 1000 for result in self.combinations]
            largest, smallest = extreme_index(values), extreme_index(values, True)
            lines.append(f"envelope {member.identifier} max {real(values[largest])} {self.combinations[largest].name} "
                         f"min {real(values[smallest])} {self.combinations[smallest].name}")
        for section, description in enumerate(self.model.sections):
            members = [number for number, choice in enumerate(self.choices) if choice == section]
            if members:
                length = total(self.geometry[number].length for number in members)
                lines.append(f"section {description.name} members {len(members)} length {real(length)}")
        lines.append("weight " + real(self.weight / 1000))
        return lines

    def magnitudes(self, result):
        values = []
        for x, y in self.node_dofs:
            horizontal, vertical = result.displacement[x], result.displacement[y]
            values.append(sqrt(horizontal * horizontal + vertical * vertical))
        return values

    def result_summary(self, kind, result):
        magnitudes = self.magnitudes(result)
        node = extreme_index(magnitudes)
        energy = total(force * force * shape.length / (2 * member.young * member.area)
                       for force, shape, member in zip(result.forces, self.geometry, self.properties)) / 1000
        reactions_total = [total(result.reactions[directions[axis]] for directions in self.node_dofs) / 1000
                           for axis in range(2)]
        forces_total = [total(result.external[directions[axis]] for directions in self.node_dofs) / 1000
                        for axis in range(2)]
        scale = max(1, max(abs(value) for value in result.external), max(abs(value) for value in result.reactions))
        equilibrium = "ok" if equilibrium_residual(result, self.geometry) <= 0.000001 * scale else "failed"
        return (f"{kind} {result.name} equilibrium {equilibrium} max_displacement {real(magnitudes[node])} "
                f"at {self.nodes[node].identifier} energy {real(energy)} "
                f"reactions {real(reactions_total[0])} {real(reactions_total[1])} "
                f"loads {real(forces_total[0])} {real(forces_total[1])}")

    def analysis_report(self):
        indeterminacy = len(self.members) + len(self.restrained) - 2 * len(self.nodes)
        before = numbering_metrics(list(range(len(self.nodes))), self.neighbors, self.members)
        after = numbering_metrics(self.numbers, self.neighbors, self.members)
        order = " ".join(str(self.nodes[node].identifier) for node in self.order)
        lines = [f"model nodes {len(self.nodes)} members {len(self.members)} supports {len(self.model.supports)} "
                 f"free_dofs {len(self.free)} restrained_dofs {len(self.restrained)} indeterminacy {indeterminacy}",
                 "renumbering " + order, f"bandwidth before {before[0]} after {after[0]}",
                 f"profile before {before[1]} after {after[1]}"]
        for member, shape in zip(self.members, self.geometry):
            lines.append(f"member {member.identifier} nodes {self.nodes[member.start].identifier} "
                         f"{self.nodes[member.end].identifier} length {real(shape.length)} "
                         f"cos {real(shape.cosine, 6)} sin {real(shape.sine, 6)}")
        for kind, name in self.result_order:
            lines.append(self.result_summary(kind, self.results[name]))
        for node, axis, degree in self.support_directions:
            values = [result.reactions[degree] / 1000 for result in self.combinations]
            largest, smallest = extreme_index(values), extreme_index(values, True)
            line = (f"reaction_envelope {self.nodes[node].identifier} {'xy'[axis]} "
                    f"max {real(values[largest])} {self.combinations[largest].name} "
                    f"min {real(values[smallest])} {self.combinations[smallest].name}")
            if axis == 1:
                uplift = "yes" if any(value < 0 for value in values) else "no"
                line += " uplift " + uplift
            lines.append(line)
        displacements = [self.magnitudes(result) for result in self.combinations]
        for node, description in enumerate(self.nodes):
            values = [magnitudes[node] for magnitudes in displacements]
            largest = extreme_index(values)
            lines.append(f"displacement_envelope {description.identifier} max {real(values[largest])} "
                         f"{self.combinations[largest].name}")
        lines.extend(self.deflection_report())
        lines.extend(self.removal_report())
        return lines

    def deflection_report(self):
        name, ratio = self.settings["deflection"]
        result = self.results[name]
        fixed = {node for node, axis, _ in self.support_directions if axis == 1}
        anchors = [position for position, node in enumerate(self.deck) if node in fixed]
        lines = []
        for first, last in zip(anchors, anchors[1:]):
            left, right = self.deck[first], self.deck[last]
            xa, xb = self.deck_x[first], self.deck_x[last]
            va, vb = result.displacement[self.node_dofs[left][1]], result.displacement[self.node_dofs[right][1]]
            interior = list(range(first + 1, last))
            deflections = [abs(result.displacement[self.node_dofs[self.deck[index]][1]]
                               - (va + (vb - va) * (self.deck_x[index] - xa) / (xb - xa))) for index in interior]
            chosen = extreme_index(deflections)
            maximum, node = deflections[chosen], self.deck[interior[chosen]]
            limit = (xb - xa) / ratio
            verdict = "ok" if maximum <= limit else "exceeded"
            lines.append(f"deflection {name} span {self.nodes[left].identifier} {self.nodes[right].identifier} "
                         f"max {real(maximum)} at {self.nodes[node].identifier} limit {real(limit)} {verdict}")
            unit = self.unit_result(node)
            virtual = total(force * (unit_force / 1000) * shape.length / (member.young * member.area)
                            for force, unit_force, shape, member in
                            zip(result.forces, unit.forces, self.geometry, self.properties))
            stiffness = -result.displacement[self.node_dofs[node][1]]
            verified = "ok" if abs(virtual - stiffness) <= 0.000001 * max(1, abs(stiffness)) else "failed"
            lines.append(f"virtual_work {name} node {self.nodes[node].identifier} stiffness {real(stiffness)} "
                         f"virtual {real(virtual)} {verified}")
        return lines

    def removal_report(self):
        combination = self.combination_definitions[self.settings["removal"]]
        lines = []
        for removed, description in enumerate(self.members):
            system = self.system(self.choices, removed)
            if system.unstable is not None:
                node, axis = self.owners[system.unstable]
                lines.append(f"removal {description.identifier} unstable at {self.nodes[node].identifier} {'xy'[axis]}")
                continue
            result = self.analyze(system, combination)[combination.name]
            members = [number for number in range(len(self.members)) if number != removed]
            values = [utilization(result.forces[number], system.properties[number], self.geometry[number])
                      for number in members]
            largest = extreme_index(values)
            magnitudes = self.magnitudes(result)
            node = extreme_index(magnitudes)
            lines.append(f"removal {description.identifier} stable max_utilization {real(values[largest])} "
                         f"at {self.members[members[largest]].identifier} max_displacement {real(magnitudes[node])} "
                         f"at {self.nodes[node].identifier}")
        return lines

    def ordinate(self, ordinates, position):
        if position < self.deck_x[0] or position > self.deck_x[-1]:
            return 0.0
        if position == self.deck_x[-1]:
            return ordinates[-1]
        index = bisect_right(self.deck_x, position) - 1
        first, last = self.deck_x[index], self.deck_x[index + 1]
        return ordinates[index] + (ordinates[index + 1] - ordinates[index]) * (position - first) / (last - first)

    def vehicle_range(self, ordinates, positions, axles):
        effects = [total(load * self.ordinate(ordinates, position - offset) for offset, load in axles)
                   for position in positions]
        largest, smallest = extreme_index(effects), extreme_index(effects, True)
        return effects[largest], positions[largest], effects[smallest], positions[smallest]

    def influence_report(self):
        member_ordinates = [[] for _ in self.members]
        reaction_ordinates = {degree: [] for _, _, degree in self.support_directions}
        for node in self.deck:
            result = self.unit_result(node)
            for number, force in enumerate(result.forces):
                member_ordinates[number].append(force / 1000)
            for degree, ordinates in reaction_ordinates.items():
                ordinates.append(result.reactions[degree] / 1000)
        lines = []
        for number in self.settings["influence"]:
            ordinates = member_ordinates[number]
            lines.append(f"influence {self.members[number].identifier}")
            for node, ordinate in zip(self.deck, ordinates):
                lines.append(f"node {self.nodes[node].identifier} {real(ordinate)}")
            largest, smallest = extreme_index(ordinates), extreme_index(ordinates, True)
            positive = total(value for value in ordinates if value > 0)
            negative = total(value for value in ordinates if value < 0)
            lines.append(f"max {real(ordinates[largest])} at {self.nodes[self.deck[largest]].identifier} "
                         f"min {real(ordinates[smallest])} at {self.nodes[self.deck[smallest]].identifier} "
                         f"positive {real(positive)} negative {real(negative)}")
            crossings = []
            for index, (first, last) in enumerate(zip(ordinates, ordinates[1:])):
                if (first > 0 and last < 0) or (first < 0 and last > 0):
                    position = (self.deck_x[index] + (self.deck_x[index + 1] - self.deck_x[index])
                                * first / (first - last))
                    crossings.append(position)
            text = "crossings " + str(len(crossings))
            if crossings:
                text += " " + " ".join(real(position, 1) for position in crossings)
            lines.append(text)
        step, axles = self.settings["vehicle"]
        positions = list(range(self.deck_x[0], self.deck_x[-1] + axles[-1][0] + 1, step))
        lines.append(f"vehicle axles {len(axles)} positions {len(positions)}")
        member_ranges = []
        for member, ordinates in zip(self.members, member_ordinates):
            largest, high_position, smallest, low_position = self.vehicle_range(ordinates, positions, axles)
            member_ranges.append((largest, smallest))
            lines.append(f"vehicle_member {member.identifier} max {real(largest)} at {high_position} "
                         f"min {real(smallest)} at {low_position}")
        for node, axis, degree in self.support_directions:
            largest, high_position, smallest, low_position = self.vehicle_range(reaction_ordinates[degree], positions, axles)
            lines.append(f"vehicle_reaction {self.nodes[node].identifier} {'xy'[axis]} "
                         f"max {real(largest)} at {high_position} min {real(smallest)} at {low_position}")
        name, dead_factor, vehicle_factor = self.settings["rating"]
        dead = self.results[name]
        ratings = []
        for number, (member, properties, shape) in enumerate(zip(self.members, self.properties, self.geometry)):
            largest, smallest = member_ranges[number]
            dead_force = dead.forces[number] / 1000
            tension_capacity = properties.area * properties.yield_stress / 1000
            compression_capacity = min(properties.area * properties.yield_stress, buckling(properties, shape)) / 1000
            tension, compression = "none", "none"
            if rounded(largest) > 0:
                rating = (tension_capacity - dead_factor * dead_force) / (vehicle_factor * largest)
                tension = real(rating)
                ratings.append((number, "tension", rating))
            if rounded(smallest) < 0:
                rating = (compression_capacity + dead_factor * dead_force) / (vehicle_factor * (-smallest))
                compression = real(rating)
                ratings.append((number, "compression", rating))
            lines.append(f"rating {member.identifier} tension {tension} compression {compression}")
        number, kind, rating = select(ratings, lambda item: item[2], minimum=True)
        lines.append(f"rating_min {real(rating)} at {self.members[number].identifier} {kind}")
        return lines

    def vibration_report(self):
        name, mode_count, iterations = self.settings["vibration"]
        external = self.results[name].external
        masses = [-external[directions[1]] / 9.81 for directions in self.node_dofs]
        free_masses = [masses[self.owners[degree][0]] for degree in self.free]
        size = len(self.free)
        system = self.final_system
        modes = []
        lines = [f"vibration {name} mass {real(total(masses))} iterations {iterations}"]
        for mode in range(1, mode_count + 1):
            vector = [1.0] * size
            for _ in range(iterations):
                for previous in modes:
                    beta = total(previous[index] * free_masses[index] * vector[index] for index in range(size))
                    vector = [vector[index] - beta * previous[index] for index in range(size)]
                right = [free_masses[index] * vector[index] for index in range(size)]
                solution = solve(system.lower, right)
                norm = sqrt(total(free_masses[index] * solution[index] * solution[index] for index in range(size)))
                vector = [value / norm for value in solution]
            modes.append(vector)
            stiffness_product = [total(system.free_matrix[row][column] * vector[column] for column in range(size))
                                 for row in range(size)]
            numerator = total(vector[index] * stiffness_product[index] for index in range(size))
            denominator = total(free_masses[index] * vector[index] * vector[index] for index in range(size))
            eigenvalue = numerator / denominator
            frequency = sqrt(1000 * eigenvalue) / (2 * PI)
            lines.append(f"mode {mode} frequency {real(frequency)} period {real(1 / frequency)}")
            peak = max(range(size), key=lambda index: abs(vector[index]))
            normalized = [0.0] * self.degrees
            for degree, value in zip(self.free, vector):
                normalized[degree] = value / vector[peak]
            for node, (x, y) in zip(self.nodes, self.node_dofs):
                lines.append(f"node {node.identifier} {real(normalized[x])} {real(normalized[y])}")
        return lines

    def drawing_report(self):
        lines = []
        for name, magnification, horizontal, vertical in self.settings["drawing"]:
            result = self.results[name]
            canvas = Canvas(self.nodes, horizontal, vertical)
            original = [canvas.position(node.x, node.y) for node in self.nodes]
            deformed = [canvas.position(node.x + magnification * result.displacement[x],
                                        node.y + magnification * result.displacement[y])
                        for node, (x, y) in zip(self.nodes, self.node_dofs)]
            for member in self.members:
                canvas.line(original[member.start], original[member.end], ".")
            for column, row in original:
                canvas.put(column, row, "+")
            for member in self.members:
                canvas.line(deformed[member.start], deformed[member.end], "*")
            for column, row in deformed:
                canvas.put(column, row, "o")
            lines.append(f"drawing {name} magnification {magnification} columns {canvas.width} rows {canvas.height}")
            lines.extend(canvas.framed())
        horizontal, vertical = self.settings["utilization_map"]
        canvas = Canvas(self.nodes, horizontal, vertical)
        positions = [canvas.position(node.x, node.y) for node in self.nodes]
        for member, value in zip(self.members, self.governing):
            character = "#" if value >= 1 else str(floor(10 * value))
            canvas.line(positions[member.start], positions[member.end], character)
        for column, row in positions:
            canvas.put(column, row, "o")
        lines.append(f"utilization_map columns {canvas.width} rows {canvas.height}")
        lines.extend(canvas.framed())
        return lines

    def csv_reports(self):
        displacement_lines = ["case,node,dx,dy"]
        force_lines = ["case,member,force,stress,utilization"]
        reaction_lines = ["case,node,rx,ry"]
        for _, name in self.result_order:
            result = self.results[name]
            for node, (x, y) in zip(self.nodes, self.node_dofs):
                displacement_lines.append(f"{name},{node.identifier},{real(result.displacement[x])},"
                                          f"{real(result.displacement[y])}")
            for member, properties, shape, force in zip(self.members, self.properties, self.geometry, result.forces):
                value = utilization(force, properties, shape)
                force_lines.append(f"{name},{member.identifier},{real(force / 1000)},"
                                   f"{real(force / properties.area)},{real(value)}")
            for support in self.model.supports:
                x, y = self.node_dofs[support.node]
                reaction_lines.append(f"{name},{self.nodes[support.node].identifier},{real(result.reactions[x] / 1000)},"
                                      f"{real(result.reactions[y] / 1000)}")
        return displacement_lines, force_lines, reaction_lines

    def run(self):
        history = self.design_sections()
        displacement_lines, force_lines, reaction_lines = self.csv_reports()
        outputs = [("analysis.txt", self.analysis_report()), ("displacements.csv", displacement_lines),
                   ("member_forces.csv", force_lines), ("reactions.csv", reaction_lines),
                   ("design.txt", self.design_report(history)), ("influence.txt", self.influence_report()),
                   ("drawing.txt", self.drawing_report()), ("vibration.txt", self.vibration_report())]
        Path("output").mkdir(exist_ok=True)
        for name, lines in outputs:
            write_lines(name, lines)


def main():
    Truss(read_model()).run()


if __name__ == "__main__":
    main()
