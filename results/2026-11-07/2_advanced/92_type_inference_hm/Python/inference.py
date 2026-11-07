from unifier import BOOL, INT, STRING, Scheme, Type, TypeVariable
from unifier import UnificationFailure, generalize, instantiate, resolve, unify


class InferenceError(Exception):
    def __init__(self, kind, position, **details):
        self.kind = kind
        self.position = position
        self.details = details


def operator_types(operator):
    if operator in ("+", "-", "*", "/", "mod"):
        return INT, INT, INT
    if operator == "^":
        return STRING, STRING, STRING
    if operator in ("&&", "||"):
        return BOOL, BOOL, BOOL
    variable = TypeVariable()
    if operator == "::":
        sequence = Type("list", variable)
        return variable, sequence, sequence
    return variable, variable, BOOL


class Inferencer:
    def __init__(self):
        self.local_bindings = []

    def check(self, expected, found, position):
        try:
            unify(expected, found)
        except UnificationFailure as failure:
            raise InferenceError("check", position, expected=expected, found=found, failure=failure) from None

    def expression(self, expression, environment):
        kind = expression.kind
        children = expression.children
        if kind in ("integer", "boolean", "string"):
            result = {"integer": INT, "boolean": BOOL, "string": STRING}[kind]
        elif kind == "name":
            if expression.value not in environment:
                raise InferenceError("unbound", expression.position, name=expression.value,
                                     candidates=tuple(environment))
            result = instantiate(environment[expression.value])
        elif kind == "fun":
            argument = TypeVariable()
            inner = environment.copy()
            if expression.value.spelling != "_":
                inner[expression.value.spelling] = Scheme(argument)
            result = Type("function", argument, self.expression(children[0], inner))
        elif kind == "apply":
            function = resolve(self.expression(children[0], environment))
            if isinstance(function, TypeVariable):
                argument, result = TypeVariable(), TypeVariable()
                function.binding = Type("function", argument, result)
            elif function.kind == "function":
                argument, result = function.children
            else:
                raise InferenceError("not_function", children[0].position, found=function)
            found = self.expression(children[1], environment)
            self.check(argument, found, children[1].position)
        elif kind == "binary":
            first, second, result = operator_types(expression.value.spelling)
            self.check(first, self.expression(children[0], environment), children[0].position)
            self.check(second, self.expression(children[1], environment), children[1].position)
        elif kind == "negate":
            self.check(INT, self.expression(children[0], environment), children[0].position)
            result = INT
        elif kind == "if":
            self.check(BOOL, self.expression(children[0], environment), children[0].position)
            result = self.expression(children[1], environment)
            found = self.expression(children[2], environment)
            self.check(result, found, children[2].position)
        elif kind == "pair":
            first = self.expression(children[0], environment)
            second = self.expression(children[1], environment)
            result = Type("pair", first, second)
        elif kind == "list":
            element = TypeVariable()
            for child in children:
                self.check(element, self.expression(child, environment), child.position)
            result = Type("list", element)
        elif kind == "match":
            matched = self.expression(children[0], environment)
            result = TypeVariable()
            for pattern, arm in expression.value:
                bindings = {}
                pattern_type = self.pattern(pattern, bindings)
                self.check(matched, pattern_type, pattern.position)
                inner = environment.copy()
                inner.update((name, Scheme(value)) for name, value in bindings.items())
                self.check(result, self.expression(arm, inner), arm.position)
        elif kind == "let":
            inner = self.group(expression.value, environment, local=True)
            result = self.expression(children[0], inner)
        expression.inferred = result
        return result

    def pattern(self, pattern, bindings):
        kind = pattern.kind
        children = pattern.children
        if kind == "wildcard":
            return TypeVariable()
        if kind == "name":
            if pattern.value in bindings:
                raise InferenceError("duplicate_pattern", pattern.position, name=pattern.value)
            result = TypeVariable()
            bindings[pattern.value] = result
            return result
        if kind in ("integer", "boolean", "string"):
            return {"integer": INT, "boolean": BOOL, "string": STRING}[kind]
        if kind == "pair":
            first = self.pattern(children[0], bindings)
            second = self.pattern(children[1], bindings)
            return Type("pair", first, second)
        element = TypeVariable()
        sequence = Type("list", element)
        if kind == "cons":
            self.check(element, self.pattern(children[0], bindings), children[0].position)
            self.check(sequence, self.pattern(children[1], bindings), children[1].position)
        else:
            for child in children:
                self.check(element, self.pattern(child, bindings), child.position)
        return sequence

    def group(self, group, environment, local=False):
        names = set()
        for binding in group.bindings:
            if binding.name in names:
                raise InferenceError("duplicate_let", binding.position, name=binding.name)
            names.add(binding.name)
            if group.rec_position is not None and binding.expression.kind != "fun":
                raise InferenceError("recursive_function", binding.position, name=binding.name)
        if group.rec_position is None:
            inferred = [self.expression(binding.expression, environment) for binding in group.bindings]
        else:
            inferred = [TypeVariable() for binding in group.bindings]
            recursive = environment.copy()
            for binding, value in zip(group.bindings, inferred):
                recursive[binding.name] = Scheme(value)
            for binding, expected in zip(group.bindings, inferred):
                found = self.expression(binding.expression, recursive)
                self.check(expected, found, binding.position)
        result = environment.copy()
        for binding, value in zip(group.bindings, inferred):
            binding.scheme = generalize(value, environment)
            result[binding.name] = binding.scheme
        if local:
            self.local_bindings.extend(group.bindings)
        return result
