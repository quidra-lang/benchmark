"""TAC optimization, analysis reports, allocation rewriting, and run comparison."""

from collections import Counter
from pathlib import Path

from cfg import CFG
from dataflow import DataFlow, live_transfer
from optimizations import cse_replacements, fold, hoist, remove_unreachable, rewrite
from regalloc import Allocation
from tac_parser import Function, KINDS, Program, calculate
from tac_parser import expression_string, function_lines, instruction_string, program_lines, read_program


PASS_ORDER = ("constprop", "copyprop", "cse", "dce", "licm", "unreachable")
VERSIONS = ("original", "optimized", "allocated")


def comma_list(values):
    return ",".join(str(value) for value in values) or "-"


def block_list(numbers):
    return comma_list(f"B{number}" for number in numbers)


def instruction_list(numbers):
    return comma_list(f"#{number}" for number in numbers)


def read_settings():
    lines = Path("input/params.txt").read_text(encoding="ascii").splitlines()
    registers = int(lines[0].split()[1])
    enabled = set(lines[1].split()[1:])
    rounds = int(lines[2].split()[1])
    return registers, [name for name in PASS_ORDER if name in enabled], rounds


def read_runs():
    lines = Path("input/input.txt").read_text(encoding="ascii").splitlines()
    count = int(lines[0])
    runs = []
    for line in lines[1:count + 1]:
        values = [int(word) for word in line.split()]
        runs.append(values[1:values[0] + 1])
    return runs


def reachable_instructions(graph):
    for number, instruction in graph.instructions.items():
        if graph.block_of[number] in graph.reachable:
            yield number, instruction


def reaching_numbers(flow, number, variable):
    return {definition for name, definition in flow.reaching_before[number] if name == variable}


def constant_value(graph, definitions):
    if not definitions or 0 in definitions:
        return None
    value = None
    for number in definitions:
        instruction = graph.instructions[number]
        if instruction.kind != "copy" or not isinstance(instruction.a, int):
            return None
        if value is not None and value != instruction.a:
            return None
        value = instruction.a
    return value


def constant_propagation(function, graph, flow):
    replacements, records = {}, []
    for number, original in reachable_instructions(graph):
        instruction = original
        for field in original.operand_fields():
            variable = getattr(original, field)
            if not isinstance(variable, str):
                continue
            definitions = reaching_numbers(flow, number, variable)
            value = constant_value(graph, definitions)
            if value is not None:
                instruction = instruction._replace(**{field: value})
                records.append(f"#{number}: {variable} -> {value}")
        result = fold(instruction)
        if result is None:
            records.append(f"#{number}: delete {instruction_string(instruction)}")
            replacements[number] = ()
        else:
            if result is not instruction:
                records.append(f"#{number}: fold {instruction_string(result)}")
            replacements[number] = (result,)
    rewrite(function, replacements)
    return len(records), records


def copy_propagation(function, graph, flow):
    replacements, records = {}, []
    for number, original in reachable_instructions(graph):
        instruction = original
        available = dict(flow.copy_before[number])
        for field in original.operand_fields():
            variable = getattr(original, field)
            if isinstance(variable, str) and variable in available:
                replacement = available[variable]
                instruction = instruction._replace(**{field: replacement})
                records.append(f"#{number}: {variable} -> {replacement}")
        replacements[number] = (instruction,)
    rewrite(function, replacements)
    return len(records), records


def expression_sources(graph, expression, candidate):
    block_number = graph.block_of[candidate]
    block = graph.blocks[block_number]
    for number in reversed(block.instructions):
        if number < candidate and graph.instructions[number].expression() == expression:
            return {number}
    sources, examined = set(), set()
    pending = list(graph.reachable_predecessors[block_number])
    while pending:
        number = pending.pop()
        if number in examined:
            continue
        examined.add(number)
        for instruction_number in reversed(graph.blocks[number].instructions):
            if graph.instructions[instruction_number].expression() == expression:
                sources.add(instruction_number)
                break
        else:
            pending.extend(graph.reachable_predecessors[number])
    return sources


def common_subexpressions(function, graph, flow):
    candidates = {}
    for number, instruction in reachable_instructions(graph):
        expression = instruction.expression()
        if expression is not None and expression in flow.expression_before[number]:
            candidates.setdefault(expression, []).append(number)
    replacements, records = {}, []
    changes = 0
    groups = sorted(candidates.items(), key=lambda item: item[1][0])
    for expression, numbers in groups:
        sources = set()
        for number in numbers:
            sources.update(expression_sources(graph, expression, number))
        sources.difference_update(numbers)
        temporary, edits = cse_replacements(function, graph, sources, numbers)
        replacements.update(edits)
        source_text = instruction_list(sorted(sources))
        replaced_text = instruction_list(numbers)
        records.append(f"{expression_string(expression)}: {temporary} sources={source_text} replaced={replaced_text}")
        changes += len(numbers)
    rewrite(function, replacements)
    return changes, records


def dead_code(function, graph, flow):
    replacements, records = {}, []
    for block_number in sorted(graph.reachable):
        state = set(flow.live_out[block_number])
        for number in reversed(graph.blocks[block_number].instructions):
            instruction = graph.instructions[number]
            destination = instruction.destination
            self_copy = instruction.kind == "copy" and destination == instruction.a
            dead_assignment = instruction.kind in ("copy", "bin", "load") and destination not in state
            if self_copy or dead_assignment:
                replacements[number] = ()
                records.append((number, f"#{number}: delete {instruction_string(instruction)}"))
                continue
            if instruction.kind == "call" and destination is not None and destination not in state:
                records.append((number, f"#{number}: unused result {instruction_string(instruction)}"))
                instruction = instruction._replace(destination=None)
                replacements[number] = (instruction,)
            state = live_transfer(instruction, state)
    rewrite(function, replacements)
    ordered = [record for number, record in sorted(records)]
    return len(ordered), ordered


def inside_definitions(graph, loop, definitions):
    return {number for number in definitions if number != 0 and graph.block_of[number] in loop.blocks}


def invariant_operand(graph, flow, loop, number, variable, marked):
    definitions = reaching_numbers(flow, number, variable)
    inside = inside_definitions(graph, loop, definitions)
    return not inside or len(definitions) == 1 and inside <= marked


def marked_invariants(graph, flow, loop, numbers):
    stores = {graph.instructions[number].name for number in numbers
              if graph.instructions[number].kind == "store"}
    calls = any(graph.instructions[number].kind == "call" for number in numbers)
    marked, order = set(), []
    while True:
        changed = False
        for number in numbers:
            instruction = graph.instructions[number]
            if number in marked or instruction.kind not in ("copy", "bin", "load"):
                continue
            if instruction.kind == "load" and (calls or instruction.name in stores):
                continue
            if all(invariant_operand(graph, flow, loop, number, variable, marked)
                   for variable in instruction.used_variables()):
                marked.add(number)
                order.append(number)
                changed = True
        if not changed:
            return order


def movable_invariants(graph, flow, loop, numbers, marked_order):
    definitions = Counter(graph.instructions[number].destination for number in numbers
                          if graph.instructions[number].destination is not None)
    moved, order = set(), []
    for number in marked_order:
        instruction = graph.instructions[number]
        destination = instruction.destination
        if definitions[destination] != 1 or destination in flow.live_in[loop.header]:
            continue
        block_number = graph.block_of[number]
        dominates_exits = all(block_number in graph.dominators[exit_block] for exit_block in loop.exits)
        dangerous = instruction.kind == "load" or (
            instruction.kind == "bin" and instruction.operation in ("/", "%")
            and (isinstance(instruction.b, str) or instruction.b == 0))
        dead_outside = all(destination not in flow.live_in[successor] for successor in loop.outside)
        if not dominates_exits and (dangerous or not dead_outside):
            continue
        dependencies_ready = True
        for variable in instruction.used_variables():
            reaching = reaching_numbers(flow, number, variable)
            if not inside_definitions(graph, loop, reaching) <= moved:
                dependencies_ready = False
                break
        if dependencies_ready:
            moved.add(number)
            order.append(number)
    return order


def loop_invariant_motion(function, graph, flow):
    loops = sorted(graph.loops, key=lambda loop: (len(loop.blocks), loop.header))
    for loop in loops:
        numbers = sorted(number for block in loop.blocks for number in graph.blocks[block].instructions)
        marked_order = marked_invariants(graph, flow, loop, numbers)
        moves = movable_invariants(graph, flow, loop, numbers, marked_order)
        if moves:
            destination = hoist(function, graph, loop, moves)
            record = f"B{loop.header}: hoist {instruction_list(moves)} to {destination}"
            return len(moves), [record]
    return 0, []


def unreachable_code(function, graph, flow):
    blocks, jumps, labels = remove_unreachable(function, graph)
    records = [f"remove block B{number}" for number in blocks]
    records.extend(f"remove jump #{number}" for number in jumps)
    records.extend("remove label " + label for label in labels)
    return len(records), records


PASSES = {
    "constprop": constant_propagation,
    "copyprop": copy_propagation,
    "cse": common_subexpressions,
    "dce": dead_code,
    "licm": loop_invariant_motion,
    "unreachable": unreachable_code,
}


def optimize_function(function, enabled, maximum_rounds, totals):
    original_count = len(function.instructions())
    lines = [f"== {function.name} =="]
    for round_number in range(1, maximum_rounds + 1):
        counts, records = [], []
        for name in enabled:
            graph = CFG(function)
            flow = DataFlow(graph)
            count, pass_records = PASSES[name](function, graph, flow)
            counts.append((name, count))
            totals[name] += count
            records.extend("  " + name + " " + record for record in pass_records)
        lines.append(f"round {round_number}: " + " ".join(f"{name}={count}" for name, count in counts))
        lines.extend(records)
        if all(count == 0 for name, count in counts):
            break
    final_count = len(function.instructions())
    lines.append(f"result: rounds={round_number} instructions={original_count}->{final_count}")
    return lines


def call_graph(program):
    names = [function.name for function in program.functions]
    callees = {}
    for function in program.functions:
        called = {instruction.name for instruction in function.instructions() if instruction.kind == "call"}
        callees[function.name] = [name for name in names if name in called]

    def reachable(starts):
        reached, pending = set(), list(starts)
        while pending:
            name = pending.pop()
            if name not in reached:
                reached.add(name)
                pending.extend(callees[name])
        return reached

    recursive = {name for name in names if name in reachable(callees[name])}
    return callees, reachable(("main",)), recursive


def call_graph_lines(program, heading):
    callees, reachable, recursive = call_graph(program)
    lines = [f"== call graph ({heading}) =="]
    for function in program.functions:
        name = function.name
        suffix = " (recursive)" if name in recursive else ""
        lines.append(f"{name} -> {comma_list(callees[name])}" + suffix)
    unreachable = [function.name for function in program.functions if function.name not in reachable]
    lines.append("unreachable functions: " + comma_list(unreachable))
    return lines, reachable


def definition_list(definitions):
    ordered = sorted(definitions, key=lambda item: (item[1], item[0]))
    return comma_list(f"{variable}:{number}" for variable, number in ordered)


def function_analysis(function, heading):
    graph = CFG(function)
    flow = DataFlow(graph)
    lines = [f"== {function.name} ({heading}) ==", "code:"]
    number = 0
    for line in function.code:
        if isinstance(line, str):
            lines.append(line + ":")
            continue
        number += 1
        text = f"  #{number} {instruction_string(line)}"
        if graph.block_of[number] in graph.reachable:
            variables = list(dict.fromkeys(line.used_variables()))
            if variables:
                chains = [f"{variable}:{comma_list(sorted(reaching_numbers(flow, number, variable)))}"
                          for variable in variables]
                text += " | " + " ".join(chains)
        lines.append(text)
    lines.append(f"blocks: {len(graph.blocks)}")
    for number, block in graph.blocks.items():
        first, last = block.instructions[0], block.instructions[-1]
        labels = comma_list(block.labels)
        predecessors = block_list(block.predecessors)
        successors = block_list(block.successors)
        lines.append(f"B{number} {first}-{last} labels={labels} preds={predecessors} succs={successors}")
    lines.append("unreachable: " + block_list(sorted(set(graph.blocks) - graph.reachable)))
    lines.append("order: " + block_list(graph.reverse_postorder))
    lines.append("dominators:")
    for number in sorted(graph.reachable):
        parent = graph.immediate[number]
        immediate = "-" if parent is None else f"B{parent}"
        dominators = block_list(sorted(graph.dominators[number]))
        lines.append(f"B{number} idom={immediate} dom={dominators}")
    lines.append("dominator tree:")
    stack = [(1, 0)]
    while stack:
        number, depth = stack.pop()
        lines.append("  " * depth + f"B{number}")
        children = sorted(child for child, parent in graph.immediate.items() if parent == number)
        stack.extend((child, depth + 1) for child in reversed(children))
    lines.append(f"loops: {len(graph.loops)}")
    for loop in graph.loops:
        latches = block_list(loop.latches)
        blocks = block_list(sorted(loop.blocks))
        exits = block_list(sorted(loop.exits))
        lines.append(f"header=B{loop.header} latches={latches} depth={loop.depth} blocks={blocks} exits={exits}")
    analyses = (
        ("reaching definitions", "reaching", flow.reaching_in, flow.reaching_out, definition_list),
        ("liveness", "liveness", flow.live_in, flow.live_out, lambda state: comma_list(sorted(state))),
        ("available expressions", "expressions", flow.expression_in, flow.expression_out,
         lambda state: comma_list(sorted(expression_string(value) for value in state))),
    )
    for title, key, incoming, outgoing, render in analyses:
        lines.append(f"{title}: iterations={flow.iterations[key]}")
        for number in sorted(graph.reachable):
            lines.append(f"B{number} in={render(incoming[number])} out={render(outgoing[number])}")
    return lines


def rewrite_registers(function, colors):
    names = {variable: f"R{color}" for variable, color in colors.items() if color is not None}
    code, moves = [], 0
    for line in function.code:
        if isinstance(line, str):
            code.append(line)
            continue
        changes = {}
        if line.destination is not None:
            changes["destination"] = names.get(line.destination, line.destination)
        for field in line.operand_fields():
            value = getattr(line, field)
            changes[field] = names.get(value, value) if isinstance(value, str) else value
        instruction = line._replace(**changes)
        if instruction.kind == "copy" and instruction.destination == instruction.a:
            moves += 1
        else:
            code.append(instruction)
    parameters = [names.get(parameter, parameter) for parameter in function.parameters]
    return Function(function.name, parameters, code), moves


def allocation_report(function, registers):
    graph = CFG(function)
    flow = DataFlow(graph)
    allocation = Allocation(function, graph, flow, registers)
    allocated, moves = rewrite_registers(function, allocation.colors)
    nodes = list(allocation.neighbors)
    edges = sum(len(neighbors) for neighbors in allocation.neighbors.values()) // 2
    lines = [f"== {function.name} ==", f"nodes={len(nodes)} edges={edges} registers={registers}"]
    for node in nodes:
        degree = len(allocation.neighbors[node])
        neighbors = comma_list(sorted(allocation.neighbors[node]))
        lines.append(f"{node} degree={degree} cost={allocation.costs[node]} neighbors={neighbors}")
    lines.append("simplify: " + comma_list(allocation.order))
    potential = [f"{node}({allocation.costs[node]}/{degree})" for node, degree in allocation.potential]
    lines.append("potential spills: " + comma_list(potential))
    for node in nodes:
        color = allocation.colors[node]
        destination = "spill" if color is None else f"R{color}"
        lines.append(f"{node} -> {destination}")
    pressure = max((len(state) for states in (flow.live_before, flow.live_after)
                    for state in states.values()), default=0)
    used = len({color for color in allocation.colors.values() if color is not None})
    spills = allocation.spills
    spill_uses = sum(variable in spills for instruction in function.instructions()
                     for variable in instruction.used_variables())
    spill_defs = sum(instruction.destination in spills for instruction in function.instructions())
    spill_defs += sum(parameter in spills for parameter in function.parameters)
    lines.append(f"summary: pressure={pressure} used={used} spilled={len(spills)} moves={moves} "
                 f"spill_uses={spill_uses} spill_defs={spill_defs}")
    lines.extend(function_lines(allocated))
    return allocated, lines


class Interpreter:
    def __init__(self, program, inputs):
        self.functions = {}
        for function in program.functions:
            labels, instructions = {}, []
            for line in function.code:
                if isinstance(line, str):
                    labels[line] = len(instructions)
                else:
                    instructions.append(line)
            self.functions[function.name] = function.parameters, instructions, labels
        self.arrays = {name: [0] * size for name, size in program.arrays}
        self.inputs = inputs
        self.input_position = 0
        self.output = []
        self.steps = Counter()
        self.calls = Counter()
        self.kinds = Counter()

    def value(self, operand, variables):
        return variables[operand] if isinstance(operand, str) else operand

    def call(self, name, arguments):
        parameters, instructions, labels = self.functions[name]
        variables = dict(zip(parameters, arguments))
        pushed = []
        position = 0
        self.calls[name] += 1
        while True:
            instruction = instructions[position]
            position += 1
            self.steps[name] += 1
            self.kinds[instruction.kind] += 1
            kind = instruction.kind
            if kind == "copy":
                variables[instruction.destination] = self.value(instruction.a, variables)
            elif kind == "bin":
                first = self.value(instruction.a, variables)
                second = self.value(instruction.b, variables)
                variables[instruction.destination] = calculate(instruction.operation, first, second)
            elif kind == "load":
                index = self.value(instruction.a, variables)
                variables[instruction.destination] = self.arrays[instruction.name][index]
            elif kind == "store":
                index = self.value(instruction.a, variables)
                value = self.value(instruction.b, variables)
                self.arrays[instruction.name][index] = value
            elif kind == "goto":
                position = labels[instruction.name]
            elif kind == "if":
                first = self.value(instruction.a, variables)
                second = self.value(instruction.b, variables)
                if calculate(instruction.operation, first, second):
                    position = labels[instruction.name]
            elif kind == "param":
                pushed.append(self.value(instruction.a, variables))
            elif kind == "call":
                if instruction.count:
                    arguments = pushed[-instruction.count:]
                    del pushed[-instruction.count:]
                else:
                    arguments = []
                result = self.call(instruction.name, arguments)
                if instruction.destination is not None:
                    variables[instruction.destination] = result
            elif kind == "return":
                return self.value(instruction.a, variables)
            elif kind == "read":
                variables[instruction.destination] = self.inputs[self.input_position]
                self.input_position += 1
            elif kind == "print":
                self.output.append(self.value(instruction.a, variables))

    def run(self):
        self.call("main", [])


def static_kinds(program):
    return Counter(instruction.kind for function in program.functions for instruction in function.instructions())


def comparison_report(original, optimized, allocated, runs):
    programs = dict(zip(VERSIONS, (original, optimized, allocated)))
    profiles = {version: Counter() for version in VERSIONS}
    dynamic = {version: Counter() for version in VERSIONS}
    total_steps = dict.fromkeys(VERSIONS, 0)
    original_calls = Counter()
    lines, same = [], 0
    for run_number, inputs in enumerate(runs, 1):
        lines.append(f"run {run_number}: inputs={len(inputs)}")
        outputs = []
        for version, program in programs.items():
            interpreter = Interpreter(program, inputs)
            interpreter.run()
            steps = sum(interpreter.steps.values())
            calls = sum(interpreter.calls.values())
            lines.append(f"  {version}: steps={steps} calls={calls} output={comma_list(interpreter.output)}")
            profiles[version].update(interpreter.steps)
            dynamic[version].update(interpreter.kinds)
            total_steps[version] += steps
            if version == "original":
                original_calls.update(interpreter.calls)
            outputs.append(interpreter.output)
        equal = outputs[0] == outputs[1] == outputs[2]
        same += int(equal)
        lines.append("  result: " + ("same" if equal else "different"))
    lines.append("== profile ==")
    for function in original.functions:
        name = function.name
        lines.append(f"{name}: calls={original_calls[name]} original={profiles['original'][name]} "
                     f"optimized={profiles['optimized'][name]} allocated={profiles['allocated'][name]}")
    original_kinds = static_kinds(original)
    optimized_kinds = static_kinds(optimized)
    original_instructions = sum(original_kinds.values())
    optimized_instructions = sum(optimized_kinds.values())
    lines.append("== summary ==")
    lines.append(f"runs={len(runs)} same={same} different={len(runs) - same}")
    lines.append(f"instructions: original={original_instructions} optimized={optimized_instructions}")
    lines.append("kinds: " + " ".join(f"{kind}={original_kinds[kind]}->{optimized_kinds[kind]}" for kind in KINDS))
    lines.append("steps: " + " ".join(f"{version}={total_steps[version]}" for version in VERSIONS))
    for version in VERSIONS:
        counts = " ".join(f"{kind}={dynamic[version][kind]}" for kind in KINDS)
        lines.append(f"dynamic {version}: " + counts)
    return lines


def main():
    registers, enabled, maximum_rounds = read_settings()
    runs = read_runs()
    original = read_program(Path("input/program.tac"))
    analysis, _ = call_graph_lines(original, "original")
    for function in original.functions:
        analysis.extend(function_analysis(function, "original"))
    working = Program(original.arrays, [function.copy() for function in original.functions])
    pass_lines, totals = [], Counter()
    for function in working.functions:
        pass_lines.extend(optimize_function(function, enabled, maximum_rounds, totals))
    graph_lines, reachable = call_graph_lines(working, "optimized")
    analysis.extend(graph_lines)
    removed = [function.name for function in working.functions
               if "unreachable" in enabled and function.name not in reachable]
    optimized = Program(working.arrays, [function for function in working.functions if function.name not in removed])
    pass_lines.extend(("== program ==", "removed functions: " + comma_list(removed), "== total =="))
    pass_lines.append(" ".join(f"{name}={totals[name]}" for name in enabled))
    allocated_functions, allocation_lines = [], []
    for function in optimized.functions:
        analysis.extend(function_analysis(function, "optimized"))
        allocated_function, lines = allocation_report(function, registers)
        allocated_functions.append(allocated_function)
        allocation_lines.extend(lines)
    allocated = Program(optimized.arrays, allocated_functions)
    reports = {
        "optimized.tac": program_lines(optimized),
        "analysis.txt": analysis,
        "passes.txt": pass_lines,
        "regalloc.txt": allocation_lines,
        "comparison.txt": comparison_report(original, optimized, allocated, runs),
    }
    output = Path("output")
    output.mkdir(exist_ok=True)
    for filename, lines in reports.items():
        (output / filename).write_text("\n".join(lines) + "\n", encoding="ascii", newline="\n")


if __name__ == "__main__":
    main()
