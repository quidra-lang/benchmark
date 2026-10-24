"""Preserve document order while building nested policy and expression trees."""

from pathlib import Path

from expressions import parse


class Element:
    def __init__(self, kind, identifier, behavior, parent):
        self.kind, self.identifier, self.behavior, self.parent = kind.lower(), identifier, behavior, parent
        self.targets, self.children = [], []
        self.condition = None
        self.obligations, self.advice = [], []


def target(text):
    alternatives = []
    for alternative in text.split(" | "):
        clauses = []
        for clause in alternative.split(" & "):
            reference, operator, literal = clause.split(" ")
            clauses.append((reference.rstrip("!"), reference.endswith("!"), operator, parse(literal)))
        alternatives.append(clauses)
    return alternatives


def read_policies(path="input/policies.txt"):
    elements, stack = [], []
    for raw_line in Path(path).read_text(encoding="ascii").splitlines():
        line = raw_line.lstrip(" ")
        if not line or line.startswith("#"):
            continue
        keyword, _, rest = line.partition(" ")
        if keyword in ("POLICYSET", "POLICY", "RULE"):
            identifier, behavior = rest.split()
            element = Element(keyword, identifier, behavior, stack[-1] if stack else None)
            if stack:
                stack[-1].children.append(element)
            elements.append(element)
            stack.append(element)
        elif keyword == "END":
            stack.pop()
        elif keyword == "TARGET":
            stack[-1].targets.append(target(rest))
        elif keyword == "CONDITION":
            stack[-1].condition = parse(rest)
        else:
            parts = rest.split(" ", 2)
            effect, identifier = parts[:2]
            arguments = []
            if len(parts) == 3:
                for part in parts[2].split(";"):
                    name, expression = part.strip().split("=", 1)
                    arguments.append((name, parse(expression)))
            collection = stack[-1].obligations if keyword == "OBLIGATION" else stack[-1].advice
            collection.append((effect, identifier, arguments))
    return elements[0], elements
