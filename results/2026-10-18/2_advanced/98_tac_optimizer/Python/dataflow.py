"""Ordered fixed-point analyses and immutable instruction-boundary snapshots."""


def reaching_transfer(instruction, number, state):
    destination = instruction.destination
    if destination is None:
        return set(state)
    return {(variable, definition) for variable, definition in state if variable != destination} | {
        (destination, number)}


def live_transfer(instruction, state):
    result = set(state)
    result.discard(instruction.destination)
    result.update(instruction.used_variables())
    return result


def expression_transfer(instruction, number, state):
    result = set(state)
    expression = instruction.expression()
    if expression is not None:
        result.add(expression)
    if instruction.kind == "store":
        result = {value for value in result if value[:2] != ("load", instruction.name)}
    if instruction.kind == "call":
        result = {value for value in result if value[0] != "load"}
    if instruction.destination is not None:
        result = {value for value in result if instruction.destination not in value[2:]}
    return result


def copy_transfer(instruction, number, state):
    destination = instruction.destination
    result = {pair for pair in state if destination not in pair} if destination is not None else set(state)
    if (instruction.kind == "copy" and isinstance(instruction.a, str)
            and destination != instruction.a):
        result.add((destination, instruction.a))
    return result


class DataFlow:
    def __init__(self, graph):
        self.graph = graph
        self.iterations = {}
        expressions, copies = set(), set()
        for number, instruction in graph.instructions.items():
            if graph.block_of[number] not in graph.reachable:
                continue
            expression = instruction.expression()
            if expression is not None:
                expressions.add(expression)
            if (instruction.kind == "copy" and isinstance(instruction.a, str)
                    and instruction.destination != instruction.a):
                copies.add((instruction.destination, instruction.a))
        self.reaching_in, self.reaching_out = self.forward("reaching", reaching_transfer, set())
        self.live_in, self.live_out = self.liveness()
        self.expression_in, self.expression_out = self.forward("expressions", expression_transfer, expressions)
        self.copy_in, self.copy_out = self.forward("copies", copy_transfer, copies)
        self.reaching_before = self.boundaries(self.reaching_in, reaching_transfer)
        self.expression_before = self.boundaries(self.expression_in, expression_transfer)
        self.copy_before = self.boundaries(self.copy_in, copy_transfer)
        self.live_before, self.live_after = {}, {}
        for block_number in sorted(graph.reachable):
            state = set(self.live_out[block_number])
            for number in reversed(graph.blocks[block_number].instructions):
                self.live_after[number] = set(state)
                state = live_transfer(graph.instructions[number], state)
                self.live_before[number] = set(state)

    def forward(self, kind, transfer, universe):
        graph = self.graph
        incoming = {}
        outgoing = {number: set(universe) for number in graph.reachable}
        iterations = 0
        while True:
            changed = False
            iterations += 1
            for number in graph.reverse_postorder:
                predecessors = graph.reachable_predecessors[number]
                if kind == "reaching":
                    state = set()
                    for predecessor in predecessors:
                        state.update(outgoing[predecessor])
                    if number == 1:
                        state.update((parameter, 0) for parameter in graph.function.parameters)
                elif number == 1:
                    state = set()
                else:
                    state = set(outgoing[predecessors[0]])
                    for predecessor in predecessors[1:]:
                        state.intersection_update(outgoing[predecessor])
                incoming[number] = set(state)
                for instruction_number in graph.blocks[number].instructions:
                    state = transfer(graph.instructions[instruction_number], instruction_number, state)
                if state != outgoing[number]:
                    outgoing[number] = state
                    changed = True
            if not changed:
                self.iterations[kind] = iterations
                return incoming, outgoing

    def liveness(self):
        graph = self.graph
        incoming = {number: set() for number in graph.reachable}
        outgoing = {}
        iterations = 0
        while True:
            changed = False
            iterations += 1
            for number in graph.postorder:
                state = set()
                for successor in graph.blocks[number].successors:
                    state.update(incoming[successor])
                outgoing[number] = set(state)
                for instruction_number in reversed(graph.blocks[number].instructions):
                    state = live_transfer(graph.instructions[instruction_number], state)
                if state != incoming[number]:
                    incoming[number] = state
                    changed = True
            if not changed:
                self.iterations["liveness"] = iterations
                return incoming, outgoing

    def boundaries(self, incoming, transfer):
        result = {}
        for block_number in sorted(self.graph.reachable):
            state = set(incoming[block_number])
            for number in self.graph.blocks[block_number].instructions:
                result[number] = set(state)
                state = transfer(self.graph.instructions[number], number, state)
        return result
