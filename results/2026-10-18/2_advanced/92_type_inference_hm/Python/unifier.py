class TypeVariable:
    def __init__(self):
        self.binding = None


class Type:
    def __init__(self, kind, *children):
        self.kind = kind
        self.children = children


class Scheme:
    def __init__(self, value, quantified=()):
        self.value = value
        self.quantified = frozenset(quantified)


INT = Type("int")
BOOL = Type("bool")
STRING = Type("string")


def resolve(value):
    path = []
    while isinstance(value, TypeVariable) and value.binding is not None:
        path.append(value)
        value = value.binding
    for variable in path:
        variable.binding = value
    return value


def occurs(variable, value):
    value = resolve(value)
    if isinstance(value, TypeVariable):
        return variable is value
    return any(occurs(variable, child) for child in value.children)


class UnificationFailure(Exception):
    def __init__(self, expected, found, infinite, nested):
        self.expected = expected
        self.found = found
        self.infinite = infinite
        self.nested = nested


def unify(expected, found, nested=False):
    expected, found = resolve(expected), resolve(found)
    if expected is found:
        return
    if isinstance(expected, TypeVariable):
        if occurs(expected, found):
            raise UnificationFailure(expected, found, True, nested)
        expected.binding = found
        return
    if isinstance(found, TypeVariable):
        if occurs(found, expected):
            raise UnificationFailure(expected, found, True, nested)
        found.binding = expected
        return
    if expected.kind != found.kind:
        raise UnificationFailure(expected, found, False, nested)
    for first, second in zip(expected.children, found.children):
        unify(first, second, True)


def free_variables(value):
    value = resolve(value)
    if isinstance(value, TypeVariable):
        return {value}
    variables = set()
    for child in value.children:
        variables.update(free_variables(child))
    return variables


def generalize(value, environment):
    free_in_environment = set()
    for scheme in environment.values():
        free_in_environment.update(free_variables(scheme.value) - scheme.quantified)
    return Scheme(value, free_variables(value) - free_in_environment)


def instantiate(scheme):
    replacements = {}

    def copy(value):
        value = resolve(value)
        if isinstance(value, TypeVariable):
            if value not in scheme.quantified:
                return value
            if value not in replacements:
                replacements[value] = TypeVariable()
            return replacements[value]
        return Type(value.kind, *(copy(child) for child in value.children))

    return copy(scheme.value)
