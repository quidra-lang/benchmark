from collections import Counter
from pathlib import Path
import sys

from codegen import BINARY, CONDITIONAL, INVERSE, JUMPS, NEGATED, TRANSFERS, Instruction, generate
from lexer import CompileError, tokenize
from parser import Node, Parser, statement_children
from semantic import Analyzer, can_complete
from vm import Execution, RuntimeFault, calculate


RULES = ("const-jump", "not-compare", "not-jump", "invert-branch", "thread", "jump-next", "unreachable")
PUSHING = frozenset(("PUSH", "LOADG", "LOADL", "READ"))
POPPING = frozenset(("POP", "STOREG", "STOREL", "JUMPF", "JUMPT", "RETV",
                     "ADD", "SUB", "MUL", "DIV", "MOD", "LT", "LE", "GT", "GE", "EQ", "NE"))
REPORTS = ("listing.txt", "output.txt", "diagnostics.txt", "stats.txt")


class Program:
    def __init__(self, name):
        self.name = name
        self.lines = []
        self.inputs = []
        self.error = None
        self.warnings = []
        self.folds = 0
        self.peephole = [0] * len(RULES)

    def compile(self):
        self.source_text = dict(self.lines)
        try:
            tokens = tokenize(self.lines)
            declarations = Parser(tokens).parse()
            self.analysis = Analyzer(declarations, tokens[-1].position).analyze()
        except CompileError as error:
            self.error = error
            return
        self.warnings, reachable = collect_warnings(self.analysis)
        self.globals = [node for node in declarations if node.kind == "global"]
        functions = [node for node in self.analysis.functions if node in reachable]
        folder = Folder()
        for variable in self.globals:
            if variable.initializer is not None:
                variable.initializer = folder.expression(variable.initializer)
        for function in functions:
            function.body = folder.statement(function.body)
        self.folds = folder.count
        main_function = self.analysis.globals["main"]
        self.units, self.global_size = generate(self.globals, functions, main_function)
        function_table = {function.name: function for function in functions}
        for unit in self.units:
            unit.after, counts = optimize(unit.before)
            for index, count in enumerate(counts):
                self.peephole[index] += count
            analyze_flow(unit, function_table)
            unit.recursive = unit.function is not None and is_recursive(unit.function)
        self.before, before_owners, before_starts = link_units(self.units, "before")
        self.after, self.owners, after_starts = link_units(self.units, "after")
        self.execution = Execution(self.after, self.owners, after_starts, self.global_size, self.inputs).run()
        self.comparison = Execution(self.before, before_owners, before_starts, self.global_size, self.inputs).run()


def collect_warnings(analysis):
    warnings = []
    for variable in analysis.variables:
        if variable.read_accesses == 0:
            role = "parameter" if variable.kind == "parameter" else "variable"
            warnings.append((variable.name_position, f"unused {role} '{variable.name}'"))
    for function in analysis.functions:
        pending = [function.body]
        while pending:
            statement = pending.pop()
            if statement.kind == "block":
                for index, child in enumerate(statement.statements[:-1]):
                    if not can_complete(child):
                        warnings.append((statement.statements[index + 1].position, "unreachable statement"))
                        break
            pending.extend(statement_children(statement))
    reachable = set()
    pending = [analysis.globals["main"]]
    while pending:
        function = pending.pop()
        if function not in reachable:
            reachable.add(function)
            pending.extend(function.calls)
    for function in analysis.functions:
        if function not in reachable:
            warnings.append((function.name_position, f"function '{function.name}' is never called"))
    warnings.sort(key=lambda warning: warning[0])
    return warnings, reachable


def is_recursive(function):
    visited = set()
    pending = list(function.calls)
    while pending:
        current = pending.pop()
        if current is function:
            return True
        if current not in visited:
            visited.add(current)
            pending.extend(current.calls)
    return False


def literal_value(node, kind, value):
    return node.kind == kind and node.value == value


class Folder:
    def __init__(self):
        self.count = 0

    def literal(self, node, value):
        self.count += 1
        kind = "boolean" if node.type == "bool" else "integer"
        value = bool(value) if kind == "boolean" else value
        return Node(kind, node.position, value=value, type=node.type)

    def identity(self, expression):
        self.count += 1
        return expression

    def expression(self, node):
        if node.kind == "unary":
            node.operand = self.expression(node.operand)
            if node.operand.kind in ("integer", "boolean"):
                op = "NEG" if node.operator == "-" else "NOT"
                try:
                    value = calculate(op, int(node.operand.value))
                except RuntimeFault:
                    return node
                return self.literal(node, value)
        elif node.kind == "binary":
            node.left = self.expression(node.left)
            node.right = self.expression(node.right)
            left, right, operator = node.left, node.right, node.operator
            if left.kind in ("integer", "boolean") and right.kind in ("integer", "boolean"):
                a, b = int(left.value), int(right.value)
                try:
                    if operator == "&&":
                        value = a != 0 and b != 0
                    elif operator == "||":
                        value = a != 0 or b != 0
                    else:
                        value = calculate(BINARY[operator], a, b)
                except RuntimeFault:
                    pass
                else:
                    return self.literal(node, value)
            if operator == "&&" and literal_value(left, "boolean", False):
                return self.literal(node, False)
            if operator == "||" and literal_value(left, "boolean", True):
                return self.literal(node, True)
            if operator == "&&" and literal_value(left, "boolean", True):
                return self.identity(right)
            if operator == "||" and literal_value(left, "boolean", False):
                return self.identity(right)
            if operator == "+" and literal_value(left, "integer", 0):
                return self.identity(right)
            if operator == "*" and literal_value(left, "integer", 1):
                return self.identity(right)
            if operator in ("+", "-") and literal_value(right, "integer", 0):
                return self.identity(left)
            if operator in ("*", "/") and literal_value(right, "integer", 1):
                return self.identity(left)
            if operator == "&&" and literal_value(right, "boolean", True):
                return self.identity(left)
            if operator == "||" and literal_value(right, "boolean", False):
                return self.identity(left)
        elif node.kind == "array":
            node.index = self.expression(node.index)
        elif node.kind == "call":
            node.arguments = [self.expression(argument) for argument in node.arguments]
        return node

    def statement(self, node):
        kind = node.kind
        if kind == "declaration":
            if node.initializer is not None:
                node.initializer = self.expression(node.initializer)
        elif kind == "assignment":
            if node.index is not None:
                node.index = self.expression(node.index)
            node.value = self.expression(node.value)
        elif kind == "call_statement":
            node.expression = self.expression(node.expression)
        elif kind == "print":
            node.arguments = [self.expression(argument) for argument in node.arguments]
        elif kind == "return":
            if node.value is not None:
                node.value = self.expression(node.value)
        elif kind == "block":
            node.statements = [self.statement(child) for child in node.statements]
        elif kind == "if":
            node.condition = self.expression(node.condition)
            if node.condition.kind == "boolean":
                selected = node.then if node.condition.value else node.otherwise
                replacement = self.statement(selected) if selected is not None else Node("empty", node.position)
                self.count += 1
                return replacement
            node.then = self.statement(node.then)
            if node.otherwise is not None:
                node.otherwise = self.statement(node.otherwise)
        elif kind == "while":
            node.condition = self.expression(node.condition)
            if literal_value(node.condition, "boolean", False):
                self.count += 1
                return Node("empty", node.position)
            node.body = self.statement(node.body)
        elif kind == "for":
            if node.initial is not None:
                node.initial = self.statement(node.initial)
            if node.condition is not None:
                node.condition = self.expression(node.condition)
            if node.update is not None:
                node.update = self.statement(node.update)
            node.body = self.statement(node.body)
        return node


def jumps_on(op, value):
    return (value == 0) == (op == "JUMPF")


def delete_instruction(code, position):
    del code[position]
    for index, instruction in enumerate(code):
        if instruction.op in JUMPS and instruction.args[0] > position:
            code[index] = instruction._replace(args=(instruction.args[0] - 1,))


def rewrite_at(code, index, targets):
    first = code[index]
    second = code[index + 1] if index + 1 < len(code) else None
    free = second is not None and index + 1 not in targets
    if free and first.op == "PUSH" and second.op in CONDITIONAL:
        if jumps_on(second.op, first.args[0]):
            code[index] = Instruction("JUMP", second.args, second.position)
            delete_instruction(code, index + 1)
        else:
            delete_instruction(code, index + 1)
            delete_instruction(code, index)
        return 1
    if free and first.op in NEGATED and second.op == "NOT":
        code[index] = first._replace(op=NEGATED[first.op])
        delete_instruction(code, index + 1)
        return 2
    if free and first.op == "NOT" and second.op in CONDITIONAL:
        code[index] = Instruction(INVERSE[second.op], second.args, second.position)
        delete_instruction(code, index + 1)
        return 3
    if free and first.op in CONDITIONAL and first.args[0] == index + 2 and second.op == "JUMP":
        code[index] = Instruction(INVERSE[first.op], second.args, first.position)
        delete_instruction(code, index + 1)
        return 4
    if first.op in JUMPS:
        target = first.args[0]
        if target < len(code):
            destination = code[target]
            new_target = None
            if destination.op == "JUMP":
                new_target = destination.args[0]
            elif destination.op == "PUSH" and target + 1 < len(code):
                following = code[target + 1]
                if following.op in CONDITIONAL:
                    new_target = following.args[0] if jumps_on(following.op, destination.args[0]) else target + 2
            if new_target is not None and new_target != target:
                code[index] = first._replace(args=(new_target,))
                return 5
        if target == index + 1:
            if first.op == "JUMP":
                delete_instruction(code, index)
            else:
                code[index] = Instruction("POP", (), first.position)
            return 6
    if free and first.op in TRANSFERS:
        delete_instruction(code, index + 1)
        return 7
    return 0


def optimize(original):
    code = list(original)
    counts = [0] * len(RULES)
    while True:
        targets = {instruction.args[0] for instruction in code if instruction.op in JUMPS}
        for index in range(len(code)):
            rule = rewrite_at(code, index, targets)
            if rule:
                counts[rule - 1] += 1
                break
        else:
            return code, counts


def successors(code, index):
    instruction = code[index]
    result = []
    if instruction.op not in TRANSFERS and index + 1 < len(code):
        result.append(index + 1)
    if instruction.op in JUMPS:
        target = instruction.args[0]
        if target < len(code) and target not in result:
            result.append(target)
    return result


def stack_effect(instruction, functions):
    op, args = instruction.op, instruction.args
    if op in PUSHING:
        return 1
    if op in POPPING:
        return -1
    if op == "STOREA":
        return -2
    if op == "CALL":
        return -args[1] + int(functions[args[0]].type != "void")
    if op == "PRINT":
        return -args[0]
    return 0


def analyze_flow(unit, functions):
    code = unit.after
    leaders = {0}
    for index, instruction in enumerate(code):
        if instruction.op in JUMPS and instruction.args[0] < len(code):
            leaders.add(instruction.args[0])
        if instruction.op in JUMPS or instruction.op in TRANSFERS:
            if index + 1 < len(code):
                leaders.add(index + 1)
    starts = sorted(leaders)
    block_numbers = {start: number for number, start in enumerate(starts)}
    unit.blocks = []
    for number, start in enumerate(starts):
        end = starts[number + 1] - 1 if number + 1 < len(starts) else len(code) - 1
        following = [block_numbers[target] for target in successors(code, end)]
        unit.blocks.append((start, end, following))
    depths = {0: 0}
    pending = [0]
    maximum = 0
    while pending:
        index = pending.pop()
        after = depths[index] + stack_effect(code[index], functions)
        maximum = max(maximum, after)
        for target in successors(code, index):
            if target not in depths:
                depths[target] = after
                pending.append(target)
    unit.depth = maximum


def link_units(units, version):
    addresses = {}
    offset = 0
    for unit in units:
        addresses[unit.name] = offset
        setattr(unit, version + "_start", offset)
        offset += len(getattr(unit, version))
    code, owners = [], []
    for unit in units:
        start = addresses[unit.name]
        for instruction in getattr(unit, version):
            args = instruction.args
            if instruction.op in JUMPS:
                args = (start + args[0],)
            elif instruction.op == "CALL":
                args = (addresses[args[0]], args[1])
            code.append(instruction._replace(args=args))
            owners.append(unit.name)
    starts = {address: name for name, address in addresses.items()}
    return code, owners, starts


def spelling(instruction):
    return " ".join([instruction.op] + [str(argument) for argument in instruction.args])


def format_position(position):
    return f"{position[0]}:{position[1]}"


def position_display(program, position):
    line, column = position
    return ["  " + program.source_text[line], " " * (column + 1) + "^"]


def listing(program):
    lines = []
    if program.globals:
        lines.append("globals:")
        for variable in program.globals:
            type_name = variable.type if variable.size is None else f"int[{variable.size}]"
            lines.append(f"  {variable.address} {variable.name} {type_name}")
    else:
        lines.append("globals: none")
    lines.append("functions:")
    for unit in program.units:
        signature = ""
        callees = "main"
        if unit.function is not None:
            parameter_types = ",".join(parameter.type for parameter in unit.function.parameters)
            signature = f" {unit.function.type}({parameter_types})"
            callees = ",".join(sorted(function.name for function in unit.function.calls)) or "-"
        line = f"  {unit.name}{signature} address={unit.before_start}->{unit.after_start}"
        line += f" size={len(unit.before)}->{len(unit.after)} slots={len(unit.slots)}"
        line += f" stack={unit.depth} blocks={len(unit.blocks)} calls={callees}"
        if unit.recursive:
            line += " recursive"
        lines.append(line)
        for number, slot in enumerate(unit.slots):
            lines.append(f"    slot {number} {slot.name} {slot.type}")
    lines.append("references:")
    for declaration in program.globals + program.analysis.functions:
        used_lines = sorted({position[0] for position in declaration.references})
        used = " ".join(str(line) for line in used_lines) or "-"
        lines.append(f"  {declaration.name} defined {declaration.name_position[0]} used {used}")
    for version in ("before", "after"):
        code = getattr(program, version)
        lines.append(f"{version} peephole: {len(code)} instructions")
        for unit in program.units:
            lines.append(unit.name + ":")
            start = getattr(unit, version + "_start")
            for address in range(start, start + len(getattr(unit, version))):
                lines.append(f"{address:5d}  {spelling(code[address])}")
    lines.append("control flow:")
    for unit in program.units:
        lines.append("  " + unit.name)
        for number, (start, end, following) in enumerate(unit.blocks):
            line = f"    B{number} {unit.after_start + start}-{unit.after_start + end}"
            if following:
                line += " -> " + " ".join(f"B{target}" for target in following)
            lines.append(line)
    return lines


def diagnostics(program):
    if program.error is not None:
        error = program.error
        lines = [f"{error.kind} error {format_position(error.position)}: {error.message}"]
        lines.extend(position_display(program, error.position))
        lines.append("status: compile error")
        return lines
    lines = [f"warning {format_position(position)}: {message}" for position, message in program.warnings]
    execution = program.execution
    if execution.error is None:
        lines.append("status: ok")
        return lines
    instruction = program.after[execution.error_pc]
    owner = program.owners[execution.error_pc]
    lines.append(f"runtime error {format_position(instruction.position)}: {execution.error} in {owner}")
    lines.extend(position_display(program, instruction.position))
    callers = list(reversed(execution.frames[1:]))
    for frame in callers[:5]:
        address = frame.return_address - 1
        caller_position = format_position(program.after[address].position)
        lines.append(f"  called from {program.owners[address]} at {caller_position}")
    if len(callers) > 5:
        lines.append(f"  ... {len(callers) - 5} more")
    lines.append("status: runtime error")
    return lines


def statistics(program):
    execution = program.execution
    comparison = program.comparison
    same = execution.output == comparison.output and execution.error == comparison.error
    lines = [f"code: {len(program.before)} -> {len(program.after)}", f"folds: {program.folds}",
             f"peephole: {sum(program.peephole)}"]
    for rule, count in zip(RULES, program.peephole):
        lines.append(f"  {rule} {count}")
    lines.append(f"executed: {execution.executed}")
    lines.append(f"executed before peephole: {comparison.executed}")
    lines.append("behaviour: " + ("same" if same else "different"))
    lines.append(f"max call depth: {execution.max_depth}")
    lines.append(f"max stack: {execution.max_stack}")
    opcodes, functions, source_lines = Counter(), Counter(), Counter()
    for address, (instruction, count) in enumerate(zip(program.after, execution.counts)):
        opcodes[instruction.op] += count
        functions[program.owners[address]] += count
        source_lines[instruction.position[0]] += count
    lines.append("opcodes:")
    for op, count in sorted(opcodes.items(), key=lambda item: (-item[1], item[0])):
        if count:
            lines.append(f"  {op} {count}")
    lines.append("functions:")
    names = [unit.name for unit in program.units if unit.function is not None]
    names.sort(key=lambda name: (-functions[name], name))
    for name in names:
        lines.append(f"  {name} calls={execution.calls[name]} executed={functions[name]}")
    lines.append("calls:")
    pairs = sorted(execution.pairs.items(), key=lambda item: (-item[1], item[0][0], item[0][1]))
    for (caller, callee), count in pairs:
        lines.append(f"  {caller} -> {callee} {count}")
    lines.append("hot lines:")
    executed_lines = [(line, count) for line, count in source_lines.items() if count]
    executed_lines.sort(key=lambda item: (-item[1], item[0]))
    for line, count in executed_lines[:5]:
        lines.append(f"  line {line}: {count}")
    lines.append(f"coverage: {len(executed_lines)} of {len(source_lines)} lines")
    unexecuted = sorted(line for line, count in source_lines.items() if count == 0)
    lines.append("not executed: " + (" ".join(str(line) for line in unexecuted) or "none"))
    lines.append("hot spots:")
    hot_spots = [(address, count) for address, count in enumerate(execution.counts) if count]
    hot_spots.sort(key=lambda item: (-item[1], item[0]))
    for address, count in hot_spots[:5]:
        lines.append(f"  pc={address} count={count} {spelling(program.after[address])}")
    return lines


def summary(programs):
    compiled = [program for program in programs if program.error is None]
    errors = Counter(program.error.kind for program in programs if program.error is not None)
    runtime_errors = sum(program.execution.error is not None for program in compiled)
    folds = sum(program.folds for program in compiled)
    peephole = [sum(program.peephole[index] for program in compiled) for index in range(len(RULES))]
    executed = sum(program.execution.executed for program in compiled)
    lines = ["== summary ==", f"programs: {len(programs)}", f"compiled: {len(compiled)}"]
    lines.append(f"compile errors: lexical {errors['lexical']} syntax {errors['syntax']} semantic {errors['semantic']}")
    lines.append(f"runtime errors: {runtime_errors}")
    lines.append(f"folds: {folds}")
    lines.append(f"peephole: {sum(peephole)}")
    for rule, count in zip(RULES, peephole):
        lines.append(f"  {rule} {count}")
    lines.append(f"executed: {executed}")
    rows = [["program", "status", "code", "executed", "output"]]
    for program in programs:
        if program.error is not None:
            rows.append([program.name, program.error.kind + " error", "-", "-", "-"])
        else:
            execution = program.execution
            status = "ok" if execution.error is None else "runtime error"
            rows.append([program.name, status, str(len(program.after)), str(execution.executed), str(len(execution.output))])
    widths = [max(len(row[column]) for row in rows) for column in range(5)]
    for row in rows:
        fields = []
        for column, (value, width) in enumerate(zip(row, widths)):
            fields.append(value.ljust(width) if column < 2 else value.rjust(width))
        lines.append("  " + "  ".join(fields))
    return lines


def read_programs():
    programs = []
    source = Path("input/program.src").read_text(encoding="ascii").splitlines()
    for number, line in enumerate(source, 1):
        if line.startswith("#program "):
            programs.append(Program(line[len("#program "):]))
        else:
            programs[-1].lines.append((number, line))
    by_name = {program.name: program for program in programs}
    inputs = Path("input/input.txt").read_text(encoding="ascii").splitlines()
    current = None
    for line in inputs:
        if line.startswith("#input "):
            current = by_name[line[len("#input "):]]
        else:
            current.inputs.extend(int(value) for value in line.split(" "))
    return programs


def main():
    sys.setrecursionlimit(1000000)
    programs = read_programs()
    reports = {name: [] for name in REPORTS}
    for program in programs:
        program.compile()
        heading = f"== program {program.name} =="
        for report in reports.values():
            report.append(heading)
        reports["diagnostics.txt"].extend(diagnostics(program))
        if program.error is not None:
            reports["listing.txt"].append("not compiled")
            reports["stats.txt"].append("not compiled")
        else:
            reports["listing.txt"].extend(listing(program))
            reports["output.txt"].extend(program.execution.output)
            reports["stats.txt"].extend(statistics(program))
    reports["stats.txt"].extend(summary(programs))
    for name, lines in reports.items():
        Path("output", name).write_text("\n".join(lines) + "\n", encoding="ascii", newline="\n")


if __name__ == "__main__":
    main()
