class Closure:
    def __init__(self, parameter, body, environment):
        self.parameter = parameter
        self.body = body
        self.environment = environment


class Builtin:
    def __init__(self, behavior):
        self.behavior = behavior


class RuntimeFailure(Exception):
    def __init__(self, position, message):
        self.position = position
        self.message = message


def checked_integer(value, position):
    if not -2147483648 <= value <= 2147483647:
        raise RuntimeFailure(position, "integer overflow")
    return value


def compare_values(first, second, position):
    if isinstance(first, (Closure, Builtin)):
        raise RuntimeFailure(position, "functional value compared")
    if isinstance(first, (tuple, list)):
        for left, right in zip(first, second):
            order = compare_values(left, right, position)
            if order:
                return order
        return (len(first) > len(second)) - (len(first) < len(second))
    return (first > second) - (first < second)


def binary_operation(operator, first, second, position):
    if operator == "+":
        return checked_integer(first + second, position)
    if operator == "-":
        return checked_integer(first - second, position)
    if operator == "*":
        return checked_integer(first * second, position)
    if operator in ("/", "mod"):
        if second == 0:
            raise RuntimeFailure(position, "division by zero")
        quotient = abs(first) // abs(second)
        if (first < 0) != (second < 0):
            quotient = -quotient
        if operator == "/":
            return checked_integer(quotient, position)
        return first - second * quotient
    if operator == "^":
        return first + second
    if operator == "::":
        return [first] + second
    order = compare_values(first, second, position)
    if operator == "=":
        return order == 0
    if operator == "<>":
        return order != 0
    if operator == "<":
        return order < 0
    if operator == ">":
        return order > 0
    if operator == "<=":
        return order <= 0
    return order >= 0


def match_pattern(pattern, value, bindings):
    kind = pattern.kind
    if kind == "wildcard":
        return True
    if kind == "name":
        bindings[pattern.value] = value
        return True
    if kind in ("integer", "boolean", "string"):
        return pattern.value == value
    if kind == "cons":
        return (bool(value) and match_pattern(pattern.children[0], value[0], bindings)
                and match_pattern(pattern.children[1], value[1:], bindings))
    if kind == "list" and len(value) != len(pattern.children):
        return False
    return all(match_pattern(child, item, bindings) for child, item in zip(pattern.children, value))


class Evaluator:
    def __init__(self):
        self.calls = 0

    def expression(self, expression, environment):
        kind = expression.kind
        children = expression.children
        if kind in ("integer", "boolean", "string"):
            return expression.value
        if kind == "name":
            return environment[expression.value]
        if kind == "fun":
            return Closure(expression.value.spelling, children[0], environment.copy())
        if kind == "apply":
            function = self.expression(children[0], environment)
            argument = self.expression(children[1], environment)
            self.calls += 1
            if isinstance(function, Builtin):
                return function.behavior(argument, expression.position)
            inner = function.environment.copy()
            if function.parameter != "_":
                inner[function.parameter] = argument
            return self.expression(function.body, inner)
        if kind == "binary":
            first = self.expression(children[0], environment)
            operator = expression.value.spelling
            if operator == "&&":
                return self.expression(children[1], environment) if first else False
            if operator == "||":
                return True if first else self.expression(children[1], environment)
            second = self.expression(children[1], environment)
            return binary_operation(operator, first, second, expression.value.position)
        if kind == "negate":
            return checked_integer(-self.expression(children[0], environment), expression.value.position)
        if kind == "if":
            selected = children[1] if self.expression(children[0], environment) else children[2]
            return self.expression(selected, environment)
        if kind == "pair":
            first = self.expression(children[0], environment)
            second = self.expression(children[1], environment)
            return first, second
        if kind == "list":
            return [self.expression(child, environment) for child in children]
        if kind == "match":
            value = self.expression(children[0], environment)
            for pattern, arm in expression.value:
                bindings = {}
                if match_pattern(pattern, value, bindings):
                    inner = environment.copy()
                    inner.update(bindings)
                    return self.expression(arm, inner)
            raise RuntimeFailure(expression.position, "match failure")
        if kind == "let":
            inner = self.group(expression.value, environment)
            return self.expression(children[0], inner)

    def group(self, group, environment):
        result = environment.copy()
        if group.rec_position is not None:
            for binding in group.bindings:
                expression = binding.expression
                result[binding.name] = Closure(expression.value.spelling, expression.children[0], result)
        else:
            values = [self.expression(binding.expression, environment) for binding in group.bindings]
            for binding, value in zip(group.bindings, values):
                result[binding.name] = value
        return result
