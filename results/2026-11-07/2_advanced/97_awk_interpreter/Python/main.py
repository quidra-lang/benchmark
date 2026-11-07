from pathlib import Path
import sys

import awk_builtins
from awk_builtins import RuntimeIssue
from lexer import SyntaxIssue, tokenize
from parser import COMPARISONS, STATEMENTS, Parser
from streams import Streams, parse_arguments, read_records
from values_fields import (UNINITIALIZED, Record, compare, describe, input_value, number,
                           split_pieces, string, subscript_order, to_number, to_string, truth)


SPECIAL_NAMES = frozenset(("FILENAME", "FNR", "FS", "NF", "NR", "OFS", "ORS", "SUBSEP"))


class StaticIssue(Exception):
    def __init__(self, position, message):
        super().__init__(message)
        self.position, self.message = position, message


class Transfer(Exception):
    def __init__(self, kind, value=UNINITIALIZED):
        super().__init__(kind)
        self.kind, self.value = kind, value


class Analysis:
    def __init__(self, items):
        self.items = items
        self.functions = [item for item in items if item.kind == "function"]
        self.rules = [item for item in items if item.kind == "rule"]
        self.function_table = {}
        self.global_names = set(SPECIAL_NAMES)
        self.bindings = {(None, name) for name in SPECIAL_NAMES}
        self.array_names = set()
        self.statement_lines = set()
        self.nodes = []
        self.errors = []

    def error(self, position, priority, message):
        self.errors.append((position, priority, message))

    def declarations(self):
        for function in self.functions:
            if function.name in self.function_table:
                self.error(function.name_position, 0, f"function {function.name} redefined")
            else:
                self.function_table[function.name] = function
            function.parameter_names = set()
            for parameter in function.parameters:
                if parameter.name in function.parameter_names:
                    self.error(parameter.position, 1, f"duplicate parameter {parameter.name}")
                function.parameter_names.add(parameter.name)

    def resolve(self, node, function):
        local = function is not None and node.name in function.parameter_names
        binding = (function if local else None, node.name)
        node.binding = binding
        self.bindings.add(binding)
        if not local:
            self.global_names.add(node.name)
        if node.name in self.function_table:
            self.error(node.position, 2, f"function {node.name} used as variable")

    def collect(self):
        for item in self.items:
            function = item if item.kind == "function" else None
            pending = [item]
            while pending:
                node = pending.pop()
                self.nodes.append(node)
                if node.kind in STATEMENTS:
                    self.statement_lines.add(node.position[0])
                if node.kind in ("name", "array", "parameter"):
                    self.resolve(node, function)
                elif node.kind == "call":
                    target = self.function_table.get(node.name)
                    if target is None:
                        self.error(node.position, 3, f"undefined function {node.name}")
                    else:
                        node.function = target
                        if len(node.arguments) > len(target.parameters):
                            self.error(node.position, 4, f"too many arguments to {node.name}")
                pending.extend(reversed(node.children))

    def arrays(self):
        links = []
        for node in self.nodes:
            if node.kind == "array":
                self.array_names.add(node.binding)
            elif node.kind in ("membership", "delete", "for_in"):
                self.array_names.add(node.array.binding)
            elif node.kind == "builtin" and node.name == "split":
                self.array_names.add(node.arguments[1].binding)
            elif node.kind == "call":
                for argument, parameter in zip(node.arguments, node.function.parameters):
                    if argument.kind == "name":
                        links.append((argument.binding, parameter.binding))
        parents = {binding: binding for binding in self.bindings}

        def root(binding):
            while parents[binding] != binding:
                parents[binding] = parents[parents[binding]]
                binding = parents[binding]
            return binding

        for first, second in links:
            parents[root(first)] = root(second)
        array_roots = {root(binding) for binding in self.array_names}
        self.array_names = {binding for binding in self.bindings if root(binding) in array_roots}

    def prepare(self):
        self.declarations()
        self.collect()
        if self.errors:
            position, priority, message = min(self.errors)
            raise StaticIssue(position, message)
        self.arrays()
        return self


def arithmetic(operator, first, second, position):
    a, b = to_number(first), to_number(second)
    if operator in ("/", "%"):
        if b == 0:
            raise RuntimeIssue(position, "division by zero")
        quotient = abs(a) // abs(b)
        if (a < 0) != (b < 0):
            quotient = -quotient
        result = quotient if operator == "/" else a - quotient * b
    elif operator == "^":
        if b < 0:
            raise RuntimeIssue(position, "negative exponent")
        result = a ** b
    elif operator == "+":
        result = a + b
    elif operator == "-":
        result = a - b
    else:
        result = a * b
    return number(result)


class Engine:
    def __init__(self, analysis, options, operands):
        self.analysis, self.options, self.operands = analysis, options, operands
        self.global_names = set(analysis.global_names)
        self.globals = {name: {} if (None, name) in analysis.array_names else UNINITIALIZED
                        for name in self.global_names}
        self.globals.update(FILENAME=string(""), FNR=number(0), FS=string(" "), NF=number(0),
                            NR=number(0), OFS=string(" "), ORS=string("\n"), SUBSEP=string(chr(28)))
        self.locals = []
        self.record = Record(lambda name: self.globals[name])
        self.streams = Streams()
        self.lines = {line: 0 for line in analysis.statement_lines}
        self.phase = "BEGIN"
        self.exit_status = 0
        self.error = None
        self.operand_position = 0
        self.current_operand = None
        self.input_lines = []
        self.input_position = 0
        for rule in analysis.rules:
            rule.count = 0
            rule.inside = False
        for function in analysis.functions:
            function.call_count = 0
            function.active_calls = 0
            function.max_depth = 0

    def variable(self, binding):
        scope, name = binding
        if scope is not None:
            return self.locals[-1][name]
        if name == "NF":
            return number(len(self.record.fields))
        return self.globals[name]

    def global_value(self, name):
        return self.variable((None, name))

    def assign_global_input(self, name, text):
        self.global_names.add(name)
        self.globals[name] = input_value(text)

    def subscript(self, expressions):
        values = []
        for expression in expressions:
            values.append(to_string(self.evaluate(expression)))
        separator = to_string(self.global_value("SUBSEP"))
        return separator.join(values)

    def location(self, node):
        if node.kind == "name":
            return "variable", node.binding
        if node.kind == "array":
            key = self.subscript(node.indexes)
            return "array", self.variable(node.binding), key
        index = to_number(self.evaluate(node.index))
        if index < 0:
            raise RuntimeIssue(node.position, "negative field index")
        return "field", index

    def read(self, location):
        kind = location[0]
        if kind == "variable":
            return self.variable(location[1])
        if kind == "field":
            return self.record.read(location[1])
        array, key = location[1:]
        if key not in array:
            array[key] = UNINITIALIZED
        return array[key]

    def store(self, location, value, position):
        kind = location[0]
        if kind == "field":
            self.record.write(location[1], value)
        elif kind == "array":
            location[1][location[2]] = value
        else:
            scope, name = location[1]
            if scope is not None:
                self.locals[-1][name] = value
            elif name == "NF":
                size = to_number(value)
                if size < 0:
                    raise RuntimeIssue(position, "negative NF")
                self.record.resize(size)
            else:
                self.globals[name] = value

    def evaluate(self, node):
        kind = node.kind
        if kind == "number":
            return number(node.value)
        if kind == "string":
            return string(node.value)
        if kind in ("name", "array", "field"):
            return self.read(self.location(node))
        if kind == "paren":
            return self.evaluate(node.expression)
        if kind == "assignment":
            location = self.location(node.location)
            value = self.evaluate(node.value)
            if node.operator != "=":
                value = arithmetic(node.operator[:-1], self.read(location), value, node.position)
            self.store(location, value, node.position)
            return self.read(location)
        if kind == "increment":
            location = self.location(node.location)
            old = to_number(self.read(location))
            value = old + node.delta
            self.store(location, number(value), node.position)
            return number(value if node.prefix else old)
        if kind == "conditional":
            branch = node.first if truth(self.evaluate(node.condition)) else node.second
            return self.evaluate(branch)
        if kind == "unary":
            value = self.evaluate(node.operand)
            if node.operator == "!":
                return number(int(not truth(value)))
            integer = to_number(value)
            return number(-integer if node.operator == "-" else integer)
        if kind == "membership":
            key = self.subscript(node.indexes)
            return number(int(key in self.variable(node.array.binding)))
        if kind == "binary":
            first = self.evaluate(node.left)
            operator = node.operator
            if operator == "||" and truth(first):
                return number(1)
            if operator == "&&" and not truth(first):
                return number(0)
            second = self.evaluate(node.right)
            if operator in ("&&", "||"):
                return number(int(truth(second)))
            if operator == "concat":
                return string(to_string(first) + to_string(second))
            if operator in COMPARISONS:
                order = compare(first, second)
                result = {"<": order < 0, "<=": order <= 0, "==": order == 0,
                          "!=": order != 0, ">=": order >= 0, ">": order > 0}[operator]
                return number(int(result))
            return arithmetic(operator, first, second, node.position)
        if kind == "call":
            return self.call(node)
        if kind == "builtin":
            return self.builtin(node)
        return self.getline(node)

    def call(self, node):
        function = node.function
        local = {}
        for index, parameter in enumerate(function.parameters):
            is_array = parameter.binding in self.analysis.array_names
            if index < len(node.arguments):
                argument = node.arguments[index]
                value = self.variable(argument.binding) if is_array else self.evaluate(argument)
            else:
                value = {} if is_array else UNINITIALIZED
            local[parameter.name] = value
        function.call_count += 1
        function.active_calls += 1
        function.max_depth = max(function.max_depth, function.active_calls)
        self.locals.append(local)
        try:
            self.statement(function.body)
        except Transfer as transfer:
            if transfer.kind == "return":
                return transfer.value
            raise
        finally:
            self.locals.pop()
            function.active_calls -= 1
        return UNINITIALIZED

    def builtin(self, node):
        name, arguments = node.name, node.arguments
        if name == "length":
            if not arguments:
                return number(len(to_string(self.record.zero)))
            argument = arguments[0]
            if argument.kind == "name" and argument.binding in self.analysis.array_names:
                return number(len(self.variable(argument.binding)))
            return number(len(to_string(self.evaluate(argument))))
        if name == "split":
            text = to_string(self.evaluate(arguments[0]))
            separator = to_string(self.evaluate(arguments[2])) if len(arguments) == 3 else to_string(self.global_value("FS"))
            array = self.variable(arguments[1].binding)
            array.clear()
            pieces = split_pieces(text, separator)
            for index, piece in enumerate(pieces, 1):
                array[str(index)] = input_value(piece)
            return number(len(pieces))
        if name == "close":
            filename = to_string(self.evaluate(arguments[0]))
            return number(self.streams.close(filename))
        values = [self.evaluate(argument) for argument in arguments]
        return awk_builtins.invoke(name, values, node.position)

    def getline(self, node):
        if node.filename is not None:
            filename = to_string(self.evaluate(node.filename))
            status, line = self.streams.getline(filename)
        elif self.phase == "END":
            return number(0)
        else:
            line = self.next_record()
            status = int(line is not None)
        if status == 1:
            if node.target is None:
                self.record.set(line)
            else:
                location = self.location(node.target)
                self.store(location, input_value(line), node.position)
        return number(status)

    def output(self, node):
        arguments = [self.evaluate(argument) for argument in node.arguments]
        if node.kind == "print":
            if not arguments:
                arguments = [self.record.zero]
            separator = to_string(self.global_value("OFS"))
            text = separator.join(to_string(value) for value in arguments)
            text += to_string(self.global_value("ORS"))
        else:
            text = awk_builtins.format_output(arguments, node.position)
        filename = to_string(self.evaluate(node.filename)) if node.filename is not None else None
        self.streams.write(text, filename, node.redirect, node.redirect_position)

    def loop_body(self, body):
        try:
            self.statement(body)
        except Transfer as transfer:
            if transfer.kind == "break":
                return False
            if transfer.kind != "continue":
                raise
        return True

    def statement(self, node):
        kind = node.kind
        if kind == "block":
            for child in node.statements:
                self.statement(child)
            return
        if kind == "empty":
            return
        self.lines[node.position[0]] += 1
        if kind == "expression_statement":
            self.evaluate(node.expression)
        elif kind in ("print", "printf"):
            self.output(node)
        elif kind == "if":
            branch = node.first if truth(self.evaluate(node.condition)) else node.second
            if branch is not None:
                self.statement(branch)
        elif kind == "while":
            while truth(self.evaluate(node.condition)):
                if not self.loop_body(node.body):
                    break
        elif kind == "do":
            while True:
                if not self.loop_body(node.body):
                    break
                if not truth(self.evaluate(node.condition)):
                    break
        elif kind == "for":
            if node.initial is not None:
                self.evaluate(node.initial)
            while node.condition is None or truth(self.evaluate(node.condition)):
                if not self.loop_body(node.body):
                    break
                if node.update is not None:
                    self.evaluate(node.update)
        elif kind == "for_in":
            keys = sorted(self.variable(node.array.binding), key=subscript_order)
            for key in keys:
                location = ("variable", node.variable.binding)
                self.store(location, input_value(key), node.variable.position)
                if not self.loop_body(node.body):
                    break
        elif kind == "delete":
            array = self.variable(node.array.binding)
            if node.indexes is None:
                array.clear()
            else:
                key = self.subscript(node.indexes)
                array.pop(key, None)
        elif kind == "next":
            if self.phase in ("BEGIN", "END"):
                raise RuntimeIssue(node.position, "next used in BEGIN or END")
            raise Transfer("next")
        elif kind == "exit":
            if node.value is not None:
                self.exit_status = to_number(self.evaluate(node.value))
            raise Transfer("exit")
        elif kind == "return":
            value = self.evaluate(node.value) if node.value is not None else UNINITIALIZED
            raise Transfer("return", value)
        else:
            raise Transfer(kind)

    def next_record(self):
        while True:
            if self.input_position < len(self.input_lines):
                line = self.input_lines[self.input_position]
                self.input_position += 1
                self.current_operand.records += 1
                self.globals["NR"] = number(to_number(self.global_value("NR")) + 1)
                self.globals["FNR"] = number(to_number(self.global_value("FNR")) + 1)
                return line
            if self.operand_position == len(self.operands):
                return None
            operand = self.operands[self.operand_position]
            self.operand_position += 1
            if operand.kind == "assignment":
                self.assign_global_input(operand.name, operand.value)
            else:
                self.current_operand = operand
                self.input_lines = read_records(operand.name)
                self.input_position = 0
                self.globals["FILENAME"] = string(operand.name)
                self.globals["FNR"] = number(0)

    def run_actions(self, phase):
        self.phase = phase
        for rule in self.analysis.rules:
            if rule.flavor == phase:
                rule.count += 1
                self.statement(rule.action)

    def matches(self, rule):
        if rule.flavor == "all":
            return True
        if rule.flavor == "pattern":
            return truth(self.evaluate(rule.patterns[0]))
        if not rule.inside and truth(self.evaluate(rule.patterns[0])):
            rule.inside = True
        if not rule.inside:
            return False
        if truth(self.evaluate(rule.patterns[1])):
            rule.inside = False
        return True

    def run_records(self):
        if not any(rule.flavor != "BEGIN" for rule in self.analysis.rules):
            return
        self.phase = "records"
        rules = [rule for rule in self.analysis.rules if rule.flavor not in ("BEGIN", "END")]
        while True:
            line = self.next_record()
            if line is None:
                return
            self.record.set(line)
            try:
                for rule in rules:
                    if self.matches(rule):
                        rule.count += 1
                        if rule.action is None:
                            text = to_string(self.record.zero) + to_string(self.global_value("ORS"))
                            self.streams.write(text)
                        else:
                            self.statement(rule.action)
            except Transfer as transfer:
                if transfer.kind != "next":
                    raise

    def execute(self):
        try:
            for name, text in self.options:
                self.assign_global_input(name, text)
            try:
                self.run_actions("BEGIN")
                self.run_records()
            except Transfer as transfer:
                if transfer.kind != "exit":
                    raise
            try:
                self.run_actions("END")
            except Transfer as transfer:
                if transfer.kind != "exit":
                    raise
        except RuntimeIssue as error:
            self.error = error

    def statistics(self):
        if self.error is None:
            status = f"status: exit {self.exit_status}"
        else:
            line, column = self.error.position
            status = f"status: runtime error at {line}:{column}: {self.error.message}"
        lines = [status, "[inputs]"]
        for operand in self.operands:
            if operand.kind == "file":
                lines.append(f"{operand.name} records={operand.records}")
        lines.append("[getline]")
        for name, source in self.streams.inputs.items():
            suffix = f"reads={source.reads}" if source.ever_opened else "missing"
            lines.append(f"{name} {suffix}")
        lines.append("[rules]")
        for rule in self.analysis.rules:
            line, column = rule.position
            lines.append(f"{line}:{column} {rule.flavor} count={rule.count}")
        lines.append("[functions]")
        for function in self.analysis.functions:
            lines.append(f"{function.name} calls={function.call_count} depth={function.max_depth}")
        lines.append("[outputs]")
        stdout = self.streams.stdout
        lines.append(f"stdout.txt writes={stdout.writes} bytes={len(stdout.content())}")
        for name, output in self.streams.outputs.items():
            lines.append(f"{name} writes={output.writes} bytes={len(output.content())}")
        lines.append("[lines]")
        for line in sorted(self.lines):
            lines.append(f"{line} count={self.lines[line]}")
        lines.append("[globals]")
        for name in sorted(self.global_names):
            value = self.global_value(name)
            text = f"array ({len(value)})" if (None, name) in self.analysis.array_names else describe(value)
            lines.append(f"{name} = {text}")
        return lines


def main():
    sys.setrecursionlimit(100000)
    options, operands = parse_arguments(Path("input/args.txt").read_text(encoding="ascii"))
    source = Path("input/program.awk").read_text(encoding="ascii")
    try:
        items = Parser(tokenize(source)).parse()
        analysis = Analysis(items).prepare()
    except SyntaxIssue as error:
        line, column = error.position
        statistics = [f"status: syntax error at {line}:{column}"]
        streams = Streams()
    except StaticIssue as error:
        line, column = error.position
        statistics = [f"status: error at {line}:{column}: {error.message}"]
        streams = Streams()
    else:
        engine = Engine(analysis, options, operands)
        engine.execute()
        statistics = engine.statistics()
        streams = engine.streams
    streams.save()
    Path("output/stats.txt").write_text("\n".join(statistics) + "\n", encoding="ascii", newline="\n")


if __name__ == "__main__":
    main()
