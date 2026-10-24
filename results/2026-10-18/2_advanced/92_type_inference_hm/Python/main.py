from functools import cache
from pathlib import Path
import sys

from evaluator import Builtin, Closure, Evaluator, RuntimeFailure
from inference import Inferencer, InferenceError
from lexer import tokenize
from parser import OPERATORS, Parser, SyntaxFailure
from unifier import BOOL, INT, STRING, Scheme, Type, TypeVariable, free_variables, resolve


def print_value(value):
    if isinstance(value, bool):
        return "true" if value else "false"
    if isinstance(value, int):
        return str(value)
    if isinstance(value, str):
        escaped = value.replace("\\", "\\\\").replace('"', '\\"')
        escaped = escaped.replace("\n", "\\n").replace("\t", "\\t")
        return '"' + escaped + '"'
    if isinstance(value, tuple):
        return "(" + print_value(value[0]) + ", " + print_value(value[1]) + ")"
    if isinstance(value, list):
        return "[" + "; ".join(print_value(item) for item in value) + "]"
    return "<fun>"


class TypePrinter:
    def __init__(self, quantified=None):
        self.names = {}
        self.quantified = quantified

    def print(self, value):
        value = resolve(value)
        if isinstance(value, TypeVariable):
            if value not in self.names:
                index = len(self.names)
                prefix = "'_" if self.quantified is not None and value not in self.quantified else "'"
                suffix = str(index // 26) if index >= 26 else ""
                self.names[value] = prefix + chr(97 + index % 26) + suffix
            return self.names[value]
        if value.kind in ("int", "bool", "string"):
            return value.kind
        first = resolve(value.children[0])
        left = self.print(first)
        first_kind = None if isinstance(first, TypeVariable) else first.kind
        if value.kind == "list":
            if first_kind in ("pair", "function"):
                left = "(" + left + ")"
            return left + " list"
        second = resolve(value.children[1])
        right = self.print(second)
        second_kind = None if isinstance(second, TypeVariable) else second.kind
        if value.kind == "pair":
            if first_kind in ("pair", "function"):
                left = "(" + left + ")"
            if second_kind in ("pair", "function"):
                right = "(" + right + ")"
            return left + " * " + right
        if first_kind == "function":
            left = "(" + left + ")"
        return left + " -> " + right


def format_declared_type(expression):
    if expression.kind == "type_variable":
        return expression.value
    if expression.kind in ("int", "bool", "string"):
        return expression.kind
    first = expression.children[0]
    left = format_declared_type(first)
    if expression.kind == "list":
        if first.kind in ("pair", "function"):
            left = "(" + left + ")"
        return left + " list"
    second = expression.children[1]
    right = format_declared_type(second)
    if expression.kind == "pair":
        if first.kind in ("pair", "function"):
            left = "(" + left + ")"
        if second.kind in ("pair", "function"):
            right = "(" + right + ")"
        return left + " * " + right
    if first.kind == "function":
        left = "(" + left + ")"
    return left + " -> " + right


def signature_type(expression, variables):
    if expression.kind == "type_variable":
        if expression.value not in variables:
            variables[expression.value] = TypeVariable()
        return variables[expression.value]
    return Type(expression.kind, *(signature_type(child, variables) for child in expression.children))


def identical_types(first, second):
    first, second = resolve(first), resolve(second)
    if isinstance(first, TypeVariable) or isinstance(second, TypeVariable):
        return first is second
    return first.kind == second.kind and all(identical_types(left, right)
                                            for left, right in zip(first.children, second.children))


def signature_matches(inferred, declared, assignments):
    inferred, declared = resolve(inferred), resolve(declared)
    if isinstance(inferred, TypeVariable):
        if inferred in assignments:
            return identical_types(assignments[inferred], declared)
        assignments[inferred] = declared
        return True
    if isinstance(declared, TypeVariable) or inferred.kind != declared.kind:
        return False
    return all(signature_matches(first, second, assignments)
               for first, second in zip(inferred.children, declared.children))


def check_signatures(group, signatures):
    for binding, signature in zip(group.bindings, signatures):
        if signature is None:
            continue
        declared = signature_type(signature[1], {})
        inferred = binding.scheme.value
        if not signature_matches(inferred, declared, {}):
            raise InferenceError("signature", binding.position, name=binding.name,
                                 inferred=inferred, declared=declared)
        binding.scheme = Scheme(declared, free_variables(declared))


def edit_distance(first, second):
    previous = list(range(len(second) + 1))
    for row, left in enumerate(first, 1):
        current = [row]
        for column, right in enumerate(second, 1):
            current.append(min(current[-1] + 1, previous[column] + 1,
                               previous[column - 1] + (left != right)))
        previous = current
    return previous[-1]


def name_candidate(name, candidates):
    choices = []
    for candidate in candidates:
        distance = edit_distance(name, candidate)
        if distance <= 2 and distance < len(name):
            choices.append((distance, candidate))
    return min(choices)[1] if choices else None


def type_error_message(error):
    details = error.details
    printer = TypePrinter()
    if error.kind == "unbound":
        name = details["name"]
        message = f"unbound variable '{name}'"
        candidate = name_candidate(name, details["candidates"])
        if candidate is not None:
            message += f" (did you mean '{candidate}'?)"
        return message
    if error.kind == "not_function":
        return "expected a function but found " + printer.print(details["found"])
    if error.kind == "check":
        message = "expected " + printer.print(details["expected"]) + " but found " + printer.print(details["found"])
        failure = details["failure"]
        if failure.infinite:
            variable, value = failure.expected, failure.found
            if not isinstance(variable, TypeVariable):
                variable, value = value, variable
            message += " (infinite type " + printer.print(variable) + " = " + printer.print(value) + ")"
        elif failure.nested:
            message += " (" + printer.print(failure.expected) + " vs " + printer.print(failure.found) + ")"
        return message
    name = details["name"]
    if error.kind == "duplicate_pattern":
        return f"variable '{name}' is bound twice in this pattern"
    if error.kind == "duplicate_let":
        return f"variable '{name}' is bound twice in this let"
    if error.kind == "recursive_function":
        return f"'{name}' in let rec must be a function"
    return f"'{name}' has type " + printer.print(details["inferred"]) + " but its signature is " + printer.print(details["declared"])


def built_in_environments():
    first, second = TypeVariable(), TypeVariable()
    fst = Scheme(Type("function", Type("pair", first, second), first), (first, second))
    first, second = TypeVariable(), TypeVariable()
    snd = Scheme(Type("function", Type("pair", first, second), second), (first, second))
    result = TypeVariable()
    types = {
        "fst": fst,
        "snd": snd,
        "not": Scheme(Type("function", BOOL, BOOL)),
        "string_of_int": Scheme(Type("function", INT, STRING)),
        "failwith": Scheme(Type("function", STRING, result), (result,)),
    }

    def failwith(value, position):
        raise RuntimeFailure(position, "failure " + print_value(value))

    values = {
        "fst": Builtin(lambda value, position: value[0]),
        "snd": Builtin(lambda value, position: value[1]),
        "not": Builtin(lambda value, position: not value),
        "string_of_int": Builtin(lambda value, position: str(value)),
        "failwith": Builtin(failwith),
    }
    return types, values


def leading_parameters(expression):
    parameters = []
    while expression.kind == "fun":
        parameters.append(expression.value.spelling)
        expression = expression.children[0]
    return parameters, expression


def format_binding(binding):
    parameters, body = leading_parameters(binding.expression)
    return " ".join([binding.name] + parameters + ["=", format_expression(body)])


def format_group(group):
    prefix = "let rec " if group.rec_position is not None else "let "
    return prefix + " and ".join(format_binding(binding) for binding in group.bindings)


def ends_with_match(expression):
    if expression.kind == "match":
        return True
    if expression.kind in ("let", "fun"):
        return ends_with_match(expression.children[0])
    if expression.kind == "if":
        return ends_with_match(expression.children[2])
    return False


def format_pattern(pattern):
    kind = pattern.kind
    if kind in ("wildcard", "name"):
        return pattern.value
    if kind in ("integer", "boolean", "string"):
        return print_value(pattern.value)
    if kind == "list":
        return "[" + "; ".join(format_pattern(child) for child in pattern.children) + "]"
    first, second = pattern.children
    left, right = format_pattern(first), format_pattern(second)
    if kind == "pair":
        return "(" + left + ", " + right + ")"
    if first.kind == "cons":
        left = "(" + left + ")"
    return left + " :: " + right


def format_expression(expression, minimum=0):
    kind = expression.kind
    children = expression.children
    strength = 9
    if kind in ("integer", "boolean", "string"):
        text = print_value(expression.value)
    elif kind == "name":
        text = expression.value
    elif kind == "fun":
        strength = 0
        parameters, body = leading_parameters(expression)
        text = "fun " + " ".join(parameters) + " -> " + format_expression(body)
    elif kind == "apply":
        strength = 8
        text = format_expression(children[0], 8) + " " + format_expression(children[1], 9)
    elif kind == "binary":
        operator = expression.value.spelling
        strength, right_associative = OPERATORS[operator]
        left_minimum = strength + 1 if right_associative else strength
        right_minimum = strength if right_associative else strength + 1
        text = format_expression(children[0], left_minimum) + " " + operator + " "
        text += format_expression(children[1], right_minimum)
    elif kind == "negate":
        strength = 7
        text = "-" + format_expression(children[0], 7)
    elif kind == "if":
        strength = 0
        text = "if " + format_expression(children[0]) + " then " + format_expression(children[1])
        text += " else " + format_expression(children[2])
    elif kind == "pair":
        text = "(" + format_expression(children[0]) + ", " + format_expression(children[1]) + ")"
    elif kind == "list":
        text = "[" + "; ".join(format_expression(child) for child in children) + "]"
    elif kind == "let":
        strength = 0
        text = format_group(expression.value) + " in " + format_expression(children[0])
    elif kind == "match":
        strength = 0
        arms = []
        for index, (pattern, arm) in enumerate(expression.value):
            body = format_expression(arm)
            if index + 1 < len(expression.value) and ends_with_match(arm):
                body = "(" + body + ")"
            arms.append(format_pattern(pattern) + " -> " + body)
        text = "match " + format_expression(children[0]) + " with " + " | ".join(arms)
    return "(" + text + ")" if strength < minimum else text


def format_item(item):
    if item.kind == "signature":
        name, declared = item.value
        return "val " + name.spelling + " : " + format_declared_type(declared) + ";;"
    if item.kind == "declaration":
        return format_group(item.value) + ";;"
    return format_expression(item.value) + ";;"


def coverage_type(value):
    value = resolve(value)
    if isinstance(value, TypeVariable) or value.kind == "function":
        return ("opaque",)
    return (value.kind,) + tuple(coverage_type(child) for child in value.children)


def coverage_pattern(pattern):
    if pattern.kind in ("wildcard", "name"):
        return None
    if pattern.kind in ("integer", "boolean", "string"):
        return (pattern.kind, pattern.value), ()
    if pattern.kind == "list":
        result = (("nil",), ())
        for child in reversed(pattern.children):
            result = (("cons",), (coverage_pattern(child), result))
        return result
    tag = "pair" if pattern.kind == "pair" else "cons"
    return (tag,), tuple(coverage_pattern(child) for child in pattern.children)


def constructors(value_type):
    if value_type[0] == "bool":
        return (("boolean", False), ("boolean", True))
    if value_type[0] == "list":
        return (("nil",), ("cons",))
    if value_type[0] == "pair":
        return (("pair",),)
    return ()


def constructor_arguments(constructor, value_type):
    if constructor == ("pair",):
        return value_type[1:]
    if constructor == ("cons",):
        return value_type[1], value_type
    return ()


def specialize(matrix, constructor, arity):
    rows = []
    for row in matrix:
        if row[0] is None:
            rows.append((None,) * arity + row[1:])
        elif row[0][0] == constructor:
            rows.append(row[0][1] + row[1:])
    return tuple(rows)


@cache
def useful_pattern(matrix, query, types):
    if not query:
        return not matrix
    if not matrix:
        return True
    head = query[0]
    if head is not None:
        constructor, arguments = head
        argument_types = constructor_arguments(constructor, types[0])
        selected = specialize(matrix, constructor, len(arguments))
        return useful_pattern(selected, arguments + query[1:], argument_types + types[1:])
    possible = constructors(types[0])
    present = {row[0][0] for row in matrix if row[0] is not None}
    if possible and all(constructor in present for constructor in possible):
        for constructor in possible:
            argument_types = constructor_arguments(constructor, types[0])
            selected = specialize(matrix, constructor, len(argument_types))
            arguments = (None,) * len(argument_types)
            if useful_pattern(selected, arguments + query[1:], argument_types + types[1:]):
                return True
        return False
    default = tuple(row[1:] for row in matrix if row[0] is None)
    return useful_pattern(default, query[1:], types[1:])


def expression_nodes(expression):
    yield expression
    if expression.kind == "let":
        for binding in expression.value.bindings:
            yield from expression_nodes(binding.expression)
    for child in expression.children:
        yield from expression_nodes(child)
    if expression.kind == "match":
        for pattern, arm in expression.value:
            yield from expression_nodes(arm)


def recursion_classification(expression, targets, references):
    parameters, body = leading_parameters(expression)
    calls = []

    def visit(node, tail):
        kind = node.kind
        children = node.children
        if kind == "name":
            if references.get(node) in targets:
                calls.append(False)
            return
        if kind == "apply":
            arguments = []
            function = node
            while function.kind == "apply":
                arguments.append(function.children[1])
                function = function.children[0]
            if function.kind == "name" and references.get(function) in targets:
                calls.append(tail)
            else:
                visit(function, False)
            for argument in reversed(arguments):
                visit(argument, False)
            return
        if kind == "if":
            visit(children[0], False)
            visit(children[1], tail)
            visit(children[2], tail)
            return
        if kind == "match":
            visit(children[0], False)
            for pattern, arm in node.value:
                visit(arm, tail)
            return
        if kind == "let":
            for binding in node.value.bindings:
                visit(binding.expression, False)
            visit(children[0], tail)
            return
        if kind == "binary" and node.value.spelling in ("&&", "||"):
            visit(children[0], False)
            visit(children[1], tail)
            return
        for child in children:
            visit(child, False)

    visit(body, True)
    if not calls:
        return ""
    return "tail recursive" if all(calls) else "recursive"


class Symbol:
    def __init__(self, name, position, top_level=False):
        self.name = name
        self.position = position
        self.top_level = top_level
        self.used = False


class StaticChecks:
    def __init__(self):
        self.symbols = []
        self.references = {}
        self.groups = []
        self.warnings = []

    def symbol(self, name, position, top_level=False):
        symbol = Symbol(name, position, top_level)
        self.symbols.append(symbol)
        return symbol

    def bind_pattern(self, pattern, environment):
        if pattern.kind == "name":
            environment[pattern.value] = self.symbol(pattern.value, pattern.position)
        for child in pattern.children:
            self.bind_pattern(child, environment)

    def group(self, group, environment, top_level=False):
        symbols = [self.symbol(binding.name, binding.position, top_level) for binding in group.bindings]
        self.groups.append((group, set(symbols)))
        inner = environment.copy()
        inner.update((symbol.name, symbol) for symbol in symbols)
        right_environment = inner if group.rec_position is not None else environment
        for binding in group.bindings:
            self.expression(binding.expression, right_environment)
        return inner

    def match_warnings(self, expression):
        useful_pattern.cache_clear()
        matrix = ()
        matched_type = (coverage_type(expression.children[0].inferred),)
        for index, (pattern, arm) in enumerate(expression.value):
            query = (coverage_pattern(pattern),)
            if index and not useful_pattern(matrix, query, matched_type):
                self.warnings.append((pattern.position, 2, "this match case is unused"))
            matrix += (query,)
        if useful_pattern(matrix, (None,), matched_type):
            self.warnings.append((expression.position, 1, "this match is not exhaustive"))

    def expression(self, expression, environment):
        kind = expression.kind
        if kind == "name":
            symbol = environment.get(expression.value)
            self.references[expression] = symbol
            if symbol is not None:
                symbol.used = True
            return
        if kind == "fun":
            inner = environment.copy()
            parameter = expression.value
            if parameter.spelling != "_":
                inner[parameter.spelling] = self.symbol(parameter.spelling, parameter.position)
            self.expression(expression.children[0], inner)
            return
        if kind == "let":
            inner = self.group(expression.value, environment)
            self.expression(expression.children[0], inner)
            return
        if kind == "match":
            self.expression(expression.children[0], environment)
            self.match_warnings(expression)
            for pattern, arm in expression.value:
                inner = environment.copy()
                self.bind_pattern(pattern, inner)
                self.expression(arm, inner)
            return
        for child in expression.children:
            self.expression(child, environment)

    def item(self, item, environment_names):
        environment = dict.fromkeys(environment_names)
        if item.kind == "declaration":
            self.group(item.value, environment, top_level=True)
        else:
            self.expression(item.value, environment)
        for group, targets in self.groups:
            if group.rec_position is None:
                continue
            referenced = any(self.references.get(node) in targets for binding in group.bindings
                             for node in expression_nodes(binding.expression))
            if not referenced:
                self.warnings.append((group.rec_position, 3, "unused rec flag"))
            for binding in group.bindings:
                binding.classification = recursion_classification(binding.expression, targets, self.references)
        for symbol in self.symbols:
            if not symbol.top_level and not symbol.used and not symbol.name.startswith("_"):
                self.warnings.append((symbol.position, 4, f"unused variable '{symbol.name}'"))
        return sorted(self.warnings, key=lambda warning: (warning[0][1:], warning[1]))


def classification_suffix(binding):
    return " (" + binding.classification + ")" if binding.classification else ""


def syntax_error_message(token):
    if token.kind == "invalid":
        return token.value
    if token.kind == "EOF":
        return "unexpected end of file"
    return "unexpected '" + token.spelling + "'"


class Reports:
    def __init__(self, sources):
        self.sources = {filename: source.splitlines() for filename, source in sources.items()}
        self.lines = []
        self.current_file = None
        self.statistics = {
            filename: dict.fromkeys(("items", "bindings", "syntax", "type", "runtime", "warnings", "calls"), 0)
            for filename in sources
        }

    def report(self, kind, position, message):
        filename, line, column = position
        counter = "warnings" if kind == "warning" else kind.split()[0]
        self.statistics[self.current_file][counter] += 1
        self.lines.append(f"{filename}:{line}:{column}: {kind}: {message}")
        source_lines = self.sources[filename]
        if line <= len(source_lines):
            self.lines.append("    " + source_lines[line - 1])
            self.lines.append(" " * (column + 3) + "^")

    def finish(self):
        self.lines.append("== summary ==")
        for filename, counts in self.statistics.items():
            summary = " ".join(f"{name}={count}" for name, count in counts.items())
            self.lines.append(filename + ": " + summary)
        return self.lines


class MiniML:
    def __init__(self, sources):
        self.sources = sources
        self.type_environment, self.value_environment = built_in_environments()
        self.reports = Reports(sources)
        self.types = []
        self.values = []
        self.formatted = []

    def unused_signature(self, signature):
        name = signature[0]
        self.reports.report("warning", name.position, f"signature for '{name.spelling}' is never used")

    def write_types(self, item, inferred, local_bindings):
        if item.kind == "declaration":
            for binding in item.value.bindings:
                text = binding.name + " : " + TypePrinter().print(binding.scheme.value)
                self.types.append(text + classification_suffix(binding))
        else:
            self.types.append("- : " + TypePrinter().print(inferred))
        for binding in sorted(local_bindings, key=lambda binding: binding.position[1:]):
            filename, line, column = binding.position
            printer = TypePrinter(binding.scheme.quantified)
            text = f"  {binding.name} ({line}:{column}) : " + printer.print(binding.scheme.value)
            self.types.append(text + classification_suffix(binding))

    def process_item(self, item, pending, evaluator, counts):
        self.formatted.append(format_item(item))
        if item.kind == "signature":
            name = item.value[0].spelling
            if name in pending:
                self.unused_signature(pending[name])
            pending[name] = item.value
            return
        signatures = []
        if item.kind == "declaration":
            signatures = [pending.pop(binding.name, None) for binding in item.value.bindings]
        inferencer = Inferencer()
        inferred = None
        try:
            if item.kind == "declaration":
                inferencer.group(item.value, self.type_environment)
                check_signatures(item.value, signatures)
            else:
                inferred = inferencer.expression(item.value, self.type_environment)
        except InferenceError as error:
            self.reports.report("type error", error.position, type_error_message(error))
            return
        warnings = StaticChecks().item(item, self.type_environment)
        self.write_types(item, inferred, inferencer.local_bindings)
        for position, priority, message in warnings:
            self.reports.report("warning", position, message)
        try:
            if item.kind == "declaration":
                environment = evaluator.group(item.value, self.value_environment)
                values = [environment[binding.name] for binding in item.value.bindings]
            else:
                value = evaluator.expression(item.value, self.value_environment)
        except RuntimeFailure as error:
            self.reports.report("runtime error", error.position, error.message)
            return
        if item.kind == "declaration":
            types = self.type_environment.copy()
            for binding, value in zip(item.value.bindings, values):
                self.values.append(binding.name + " = " + print_value(value))
                types[binding.name] = binding.scheme
            self.type_environment = types
            self.value_environment = environment
            counts["bindings"] += len(item.value.bindings)
        else:
            self.values.append("- = " + print_value(value))

    def process_file(self, filename):
        self.reports.current_file = filename
        counts = self.reports.statistics[filename]
        self.types.append(f"== {filename} ==")
        self.values.append(f"== {filename} ==")
        self.formatted.append(f"(* {filename} *)")
        pending = {}
        evaluator = Evaluator()
        parser = Parser(tokenize(self.sources[filename], filename))
        while parser.peek().kind != "EOF":
            counts["items"] += 1
            try:
                item = parser.item()
            except SyntaxFailure as error:
                self.reports.report("syntax error", error.token.position, syntax_error_message(error.token))
                parser.recover()
                continue
            self.process_item(item, pending, evaluator, counts)
        for signature in sorted(pending.values(), key=lambda signature: signature[0].position[1:]):
            self.unused_signature(signature)
        counts["calls"] = evaluator.calls

    def run(self):
        for filename in self.sources:
            self.process_file(filename)
        return {
            "types.txt": self.types,
            "values.txt": self.values,
            "errors.txt": self.reports.finish(),
            "formatted.ml": self.formatted,
        }


def main():
    sys.setrecursionlimit(30000)
    sources = {}
    for filename in ("prelude.ml", "program.ml"):
        sources[filename] = (Path("input") / filename).read_text(encoding="ascii")
    output = Path("output")
    output.mkdir(exist_ok=True)
    for filename, lines in MiniML(sources).run().items():
        (output / filename).write_text("\n".join(lines) + "\n", encoding="ascii", newline="\n")


if __name__ == "__main__":
    main()
