"""Interference, exact spill priorities, and optimistic copy-biased colouring."""

from fractions import Fraction

from dataflow import live_transfer


class Allocation:
    def __init__(self, function, graph, flow, registers):
        nodes = set(function.parameters)
        for number, instruction in graph.instructions.items():
            if graph.block_of[number] in graph.reachable:
                nodes.update(instruction.used_variables())
                if instruction.destination is not None:
                    nodes.add(instruction.destination)
        self.neighbors = {node: set() for node in sorted(nodes)}
        self.costs = dict.fromkeys(self.neighbors, 0)
        self.partners = {node: set() for node in self.neighbors}
        for block_number in sorted(graph.reachable):
            block = graph.blocks[block_number]
            state = set(flow.live_out[block_number])
            for number in reversed(block.instructions):
                instruction = graph.instructions[number]
                destination = instruction.destination
                if destination is not None:
                    partner = instruction.a if instruction.kind == "copy" else None
                    for variable in state:
                        if variable != destination and variable != partner:
                            self.edge(destination, variable)
                state = live_transfer(instruction, state)
            weight = 10 ** graph.depth[block_number]
            for number in block.instructions:
                instruction = graph.instructions[number]
                occurrences = instruction.used_variables()
                if instruction.destination is not None:
                    occurrences.append(instruction.destination)
                for variable in occurrences:
                    self.costs[variable] += weight
        entry = flow.live_in[1] | set(function.parameters)
        for parameter in function.parameters:
            self.costs[parameter] += 1
            for variable in entry - {parameter}:
                self.edge(parameter, variable)
        for instruction in function.instructions():
            if (instruction.kind == "copy" and isinstance(instruction.a, str)
                    and instruction.destination != instruction.a):
                first, second = instruction.destination, instruction.a
                if first in self.partners:
                    self.partners[first].add(second)
                if second in self.partners:
                    self.partners[second].add(first)
        self.order, self.potential = [], []
        remaining = set(nodes)
        while remaining:
            degrees = {node: len(self.neighbors[node] & remaining) for node in remaining}
            simple = [node for node in remaining if degrees[node] < registers]
            if simple:
                chosen = min(simple, key=lambda node: (degrees[node], node))
            else:
                chosen = min(remaining, key=lambda node: (Fraction(self.costs[node], degrees[node]), node))
                self.potential.append((chosen, degrees[chosen]))
            self.order.append(chosen)
            remaining.remove(chosen)
        self.colors = {}
        for node in reversed(self.order):
            occupied = {self.colors[neighbor] for neighbor in self.neighbors[node]
                        if self.colors.get(neighbor) is not None}
            free = set(range(registers)) - occupied
            if not free:
                self.colors[node] = None
                continue
            preferred = {self.colors[partner] for partner in self.partners[node]
                         if self.colors.get(partner) in free}
            self.colors[node] = min(preferred if preferred else free)
        self.spills = {node for node, color in self.colors.items() if color is None}

    def edge(self, first, second):
        self.neighbors[first].add(second)
        self.neighbors[second].add(first)
