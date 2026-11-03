"""Element types, sequential conversion, spacing and row box assembly."""

from boxes import Box, COMMAND_TYPES, SYMBOL_TYPES
from lexer import GREEK


TYPES = ("ordinary", "operator", "binary", "relation", "open", "close", "punctuation")
SPACING = (
    (0, 1, "B", "R", 0, 0, 0),
    (1, 1, None, "R", 0, 0, 0),
    ("B", "B", None, None, "B", None, None),
    ("R", "R", None, 0, "R", 0, 0),
    (0, 0, None, 0, 0, 0, 0),
    (0, 1, "B", "R", 0, 0, 0),
    ("P", "P", None, "P", "P", "P", "P"),
)


def element_types(node):
    if node.kind == "symbol":
        kind = SYMBOL_TYPES.get(node.value, "ordinary")
    elif node.kind == "command":
        kind = COMMAND_TYPES[node.value]
    elif node.kind == "delim":
        return "open", "close"
    elif node.kind == "script":
        return element_types(node.children[0])
    elif node.kind in ("overset", "underset"):
        return element_types(node.children[1])
    else:
        kind = "ordinary"
    return kind, kind


def converted_types(nodes):
    result = [list(element_types(node)) for node in nodes]
    for index, current in enumerate(result):
        if current[0] == "binary" and (index == 0 or result[index - 1][1] in (
                "binary", "operator", "relation", "open", "punctuation")):
            current[:] = ("ordinary", "ordinary")
        if current[0] in ("relation", "close", "punctuation") and index and result[index - 1][1] == "binary":
            result[index - 1][:] = ("ordinary", "ordinary")
    if result and result[-1][1] == "binary":
        result[-1][:] = ("ordinary", "ordinary")
    return result


def word_element(node):
    if node.kind == "script":
        return word_element(node.children[0])
    return node.kind == "command" and (node.value[1:] in GREEK or node.value == r"\infty")


def alphanumeric(node):
    if node.kind in ("identifier", "number") or word_element(node):
        return True
    if node.kind == "script":
        return alphanumeric(node.children[0])
    return (node.kind == "accent" and node.value in ("overline", "hat", "vec", "dot", "tilde")
            and alphanumeric(node.children[0]))


def spacing(nodes, style, parameters):
    types = converted_types(nodes)
    values = {
        "B": parameters["bin_space"] if style == "normal" else 0,
        "R": parameters["rel_space"] if style == "normal" else 0,
        "P": parameters["punct_space"] if style == "normal" else 0,
    }
    gaps = []
    for index, (first, second) in enumerate(zip(nodes, nodes[1:])):
        if alphanumeric(first) and alphanumeric(second) and (word_element(first) or word_element(second)):
            gaps.append(1)
        else:
            entry = SPACING[TYPES.index(types[index][1])][TYPES.index(types[index + 1][0])]
            gaps.append(values[entry] if isinstance(entry, str) else entry)
    return types, gaps


def row(children, gaps, description="row", roles=None):
    ascent = max((child.baseline for child in children), default=0)
    descent = max((child.descent for child in children), default=0)
    width = sum(child.width for child in children) + sum(gaps)
    result = Box(width, ascent + descent + 1, ascent, description)
    if roles is None:
        roles = [""] * len(children)
    x = 0
    for index, child in enumerate(children):
        result.add(child, x, ascent - child.baseline, roles[index])
        x += child.width
        if index < len(gaps):
            x += gaps[index]
    return result
