"""Read the specified PDDL expressions without interpreting domain validity."""

import re
from collections import namedtuple
from types import SimpleNamespace


Atom = namedtuple("Atom", "predicate terms")


def expressions(text):
    cleaned = "\n".join(line.split(";", 1)[0] for line in text.splitlines())
    roots = []
    stack = [roots]
    for token in re.findall(r"\(|\)|[^ ()\n]+", cleaned):
        if token == "(":
            child = []
            stack[-1].append(child)
            stack.append(child)
        elif token == ")":
            stack.pop()
        else:
            stack[-1].append(token)
    return roots


def typed_list(words):
    result, pending = [], []
    index = 0
    while index < len(words):
        if words[index] == "-":
            result.extend((name, words[index + 1]) for name in pending)
            pending = []
            index += 2
        else:
            pending.append(words[index])
            index += 1
    result.extend((name, "object") for name in pending)
    return result


def atom(expression):
    return Atom(expression[0], tuple(expression[1:]))


def elements(expression, empty=True):
    conjunction = expression[0] == "and" and all(isinstance(item, list) for item in expression[1:])
    return expression[1:] if conjunction and (empty or len(expression) > 1) else [expression]


def literal(expression):
    if expression[0] == "not" and len(expression) == 2 and isinstance(expression[1], list):
        return False, atom(expression[1])
    return True, atom(expression)


def read_domain(text):
    expression = expressions(text)[0]
    domain = SimpleNamespace(name=expression[1][1], parents={"object": None},
                             type_order=["object"], predicates={}, actions=[])
    for section in expression[2:]:
        if section[0] == ":types":
            for name in section[1:]:
                if name != "-" and name not in domain.parents:
                    domain.parents[name] = "object"
                    domain.type_order.append(name)
            for name, parent in typed_list(section[1:]):
                domain.parents[name] = parent
        elif section[0] == ":predicates":
            for declaration in section[1:]:
                domain.predicates[declaration[0]] = tuple(kind for _, kind in typed_list(declaration[1:]))
        elif section[0] == ":action":
            fields = dict(zip(section[2::2], section[3::2]))
            condition = [literal(item) for item in elements(fields[":precondition"])] if ":precondition" in fields else []
            effects, cost = [], 1
            for item in elements(fields[":effect"], empty=False):
                if item[0] == "increase" and len(item) == 3 and item[1] == ["total-cost"]:
                    cost = int(item[2])
                else:
                    effects.append(literal(item))
            domain.actions.append(SimpleNamespace(name=section[1], parameters=typed_list(fields[":parameters"]),
                                                  condition=condition, effects=effects, cost=cost))
    return domain


def read_problems(text):
    problems = []
    for expression in expressions(text):
        sections = {section[0]: section[1:] for section in expression[2:]}
        problems.append(SimpleNamespace(name=expression[1][1], objects=dict(typed_list(sections[":objects"])),
                                        initial=[atom(item) for item in sections[":init"]],
                                        goals=[atom(item) for item in elements(sections[":goal"][0], empty=False)]))
    return problems
