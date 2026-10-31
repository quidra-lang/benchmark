"""Snapshot-based code editing, folding, CSE temporaries, and preheaders."""

from tac_parser import Instruction, calculate


def rewrite(function, replacements, insertions=None):
    insertions = insertions or {}
    result, number = [], 0
    for index, line in enumerate(function.code):
        result.extend(insertions.get(index, ()))
        if isinstance(line, str):
            result.append(line)
        else:
            number += 1
            result.extend(replacements.get(number, (line,)))
    result.extend(insertions.get(len(function.code), ()))
    function.code = result


def fold(instruction):
    if instruction.kind not in ("bin", "if"):
        return instruction
    first, second = instruction.a, instruction.b
    first_constant, second_constant = isinstance(first, int), isinstance(second, int)
    if first_constant and second_constant:
        if instruction.operation in ("/", "%") and second == 0:
            return instruction
        result = calculate(instruction.operation, first, second)
        if instruction.kind == "if":
            return Instruction("goto", name=instruction.name) if result else None
        if -2147483648 <= result <= 2147483647:
            return Instruction("copy", instruction.destination, result)
        return instruction
    if instruction.kind != "bin" or first_constant == second_constant:
        return instruction
    operation = instruction.operation
    replacement = None
    if operation == "+" and (first == 0 or second == 0):
        replacement = second if first_constant else first
    elif operation == "-" and second == 0:
        replacement = first
    elif operation == "*" and (first == 1 or second == 1):
        replacement = second if first_constant else first
    elif operation == "/" and second == 1:
        replacement = first
    elif operation == "*" and (first == 0 or second == 0):
        replacement = 0
    if replacement is None:
        return instruction
    return Instruction("copy", instruction.destination, replacement)


def cse_replacements(function, graph, sources, candidates):
    function.temporary_serial += 1
    temporary = f"_t{function.temporary_serial}"
    replacements = {}
    for number in sources:
        instruction = graph.instructions[number]
        replacements[number] = (instruction._replace(destination=temporary),
                                Instruction("copy", instruction.destination, temporary))
    for number in candidates:
        replacements[number] = (Instruction("copy", graph.instructions[number].destination, temporary),)
    return temporary, replacements


def hoist(function, graph, loop, moves):
    header = graph.blocks[loop.header]
    outside = [number for number in header.predecessors if number not in loop.blocks]
    replacements = {number: () for number in moves}
    instructions = [graph.instructions[number] for number in moves]
    if (loop.header != 1 and len(outside) == 1
            and graph.blocks[outside[0]].successors == [loop.header]):
        preheader = graph.blocks[outside[0]]
        last = preheader.instructions[-1]
        position = graph.positions[last]
        if graph.instructions[last].kind not in ("goto", "if"):
            position += 1
        insertion = instructions
        destination = f"B{preheader.number}"
    else:
        function.preheader_serial += 1
        label = f"_p{function.preheader_serial}"
        position = header.start
        insertion = [label, *instructions]
        destination = "new " + label
        for number in outside:
            last = graph.blocks[number].instructions[-1]
            instruction = graph.instructions[last]
            if instruction.kind in ("goto", "if") and instruction.name in header.labels:
                replacements[last] = (instruction._replace(name=label),)
    rewrite(function, replacements, {position: insertion})
    return destination


def remove_unreachable(function, graph):
    blocks = [number for number in graph.blocks if number not in graph.reachable]
    deleted_lines = set()
    for number in blocks:
        block = graph.blocks[number]
        deleted_lines.update(range(block.start, block.end))
    numbers = {position: number for number, position in graph.positions.items()}
    remaining = [(line, numbers.get(index)) for index, line in enumerate(function.code)
                 if index not in deleted_lines]
    jumps = []
    for index, (line, number) in enumerate(remaining):
        if isinstance(line, str) or line.kind not in ("goto", "if"):
            continue
        labels, following = [], index + 1
        while following < len(remaining) and isinstance(remaining[following][0], str):
            labels.append(remaining[following][0])
            following += 1
        if line.name in labels:
            jumps.append(number)
    removed_jumps = set(jumps)
    remaining = [(line, number) for line, number in remaining if number not in removed_jumps]
    targets = {line.name for line, number in remaining
               if not isinstance(line, str) and line.kind in ("goto", "if")}
    labels = [line for line, number in remaining if isinstance(line, str) and line not in targets]
    function.code = [line for line, number in remaining if not isinstance(line, str) or line in targets]
    return blocks, jumps, labels
