"""Parse, typeset, annotate and report mathematical formulas as ASCII boxes."""

from collections import Counter
from pathlib import Path

import canvas
import layout
import lexer
import parser
from boxes import Box, COMMAND_DISPLAY, LARGE_GLYPHS, delimiter_glyph


ATOM_KINDS = parser.ATOM_KINDS | {"reference"}
STACKED_COMMANDS = frozenset((r"\sum", r"\prod", r"\lim", r"\max", r"\min"))
BRACE_ACCENTS = frozenset(("overbrace", "underbrace"))
DELIMITER_PAIRS = {"(": ")", "[": "]", "|": "|", r"\{": r"\}"}


class Formula:
    def __init__(self, number, line):
        self.number = number
        self.line = line
        self.nodes = []
        self.tag = self.label = self.tag_string = None
        self.error = None
        self.warnings = []
        try:
            self.tokens = lexer.tokenize(line)
            parser.check_braces(self.tokens)
            reader = parser.Parser(self.tokens)
            self.nodes = reader.parse()
            self.tag, self.label = reader.tag, reader.label
        except lexer.FormulaError as error:
            self.error = error.column, error.message


def read_inputs():
    parameters = {}
    for line in Path("input/params.txt").read_text(encoding="ascii").splitlines():
        name, value = line.split(" ")
        parameters[name] = int(value)
    lines = Path("input/formulas.txt").read_text(encoding="ascii").splitlines()
    formulas = [Formula(number, line) for number, line in enumerate(lines, 1)]
    return parameters, formulas


def reference_table(formulas):
    counter = 0
    for formula in formulas:
        if formula.error is not None:
            continue
        if formula.tag is not None:
            formula.tag_string = "(" + formula.tag.value + ")"
        elif formula.label is not None:
            counter += 1
            formula.tag_string = f"({counter})"
    references = {}
    for formula in formulas:
        if formula.error is not None or formula.label is None:
            continue
        label = formula.label
        if label.value in references:
            formula.warnings.append((label.column, f'duplicate label "{label.value}"'))
        else:
            references[label.value] = formula.tag_string
    return references


def walk_nodes(node):
    yield node
    children = (cell for row in node.children for cell in row) if node.kind == "matrix" else node.children
    for child in children:
        if child is not None:
            yield from walk_nodes(child)


def collect_warnings(formula, references):
    for element in formula.nodes:
        for node in walk_nodes(element):
            if node.kind == "identifier" and node.value in lexer.COMMAND_NAMES:
                message = f"{node.value} is a command name; write \\" + node.value
                formula.warnings.append((node.column, message))
            elif node.kind == "reference" and node.value not in references:
                formula.warnings.append((node.column, f'undefined reference "{node.value}"'))
            elif node.kind == "delim":
                left, right = node.value
                if left != "." and right != "." and DELIMITER_PAIRS.get(left) != right:
                    message = "\\left" + left + " closed by \\right" + right
                    formula.warnings.append((node.column, message))
    formula.warnings.sort(key=lambda warning: warning[0])


def center(box, width):
    return (width - box.width) // 2


def draw_delimiter(box, delimiter, x, height):
    for y, character in enumerate(delimiter_glyph(delimiter, height)):
        box.draw(character, x, y)


def delimiter_string(delimiter):
    return "" if delimiter == "." else delimiter[-1]


class Typesetter:
    def __init__(self, parameters, references):
        self.parameters = parameters
        self.references = references

    def typeset(self, node, style="normal"):
        if node.kind in ATOM_KINDS:
            return self.atom(node, style)
        return getattr(self, node.kind)(node, style)

    def atom(self, node, style):
        if node.kind == "text":
            description = f'text "{node.value}"'
            display = node.value
        elif node.kind == "reference":
            description = f'eqref "{node.value}"'
            display = self.references.get(node.value, "(??)")
        else:
            description = f'atom "{node.value}"'
            display = COMMAND_DISPLAY[node.value] if node.kind == "command" else node.value
        if node.kind == "command" and node.value in LARGE_GLYPHS and style == "normal":
            glyph = LARGE_GLYPHS[node.value]
            result = Box(len(glyph[0]), 3, 1, description)
            for y, line in enumerate(glyph):
                result.draw(line, 0, y)
        else:
            result = Box(len(display), 1, 0, description)
            result.draw(display)
        return result

    def row(self, node, style):
        types, gaps = layout.spacing(node.children, style, self.parameters)
        children = [self.typeset(child, style) for child in node.children]
        return layout.row(children, gaps)

    def script(self, node, style):
        base_node, sub_node, sup_node = node.children
        base = self.typeset(base_node, style)
        sub = self.typeset(sub_node, "script") if sub_node is not None else None
        sup = self.typeset(sup_node, "script") if sup_node is not None else None
        sub_width, sub_height = (sub.width, sub.height) if sub is not None else (0, 0)
        sup_width, sup_height = (sup.width, sup.height) if sup is not None else (0, 0)
        stacked = (style == "normal" and (
            base_node.kind == "command" and base_node.value in STACKED_COMMANDS
            or base_node.kind == "accent" and base_node.value in BRACE_ACCENTS
        ))
        if stacked:
            width = max(base.width, sub_width, sup_width)
            result = Box(width, sup_height + base.height + sub_height,
                         sup_height + base.baseline, "limits")
            result.add(base, center(base, width), sup_height, "base: ")
            if sub is not None:
                result.add(sub, center(sub, width), sup_height + base.height, "sub: ")
            if sup is not None:
                result.add(sup, center(sup, width), 0, "sup: ")
            return result
        sup_top = (-1 if base.baseline == 0 else 0) - sup_height + 1
        sub_top = base.height if base.descent == 0 else base.height - 1
        top = min(0, sup_top) if sup is not None else 0
        bottom = max(base.height - 1, sub_top + sub_height - 1) if sub is not None else base.height - 1
        result = Box(base.width + max(sub_width, sup_width), bottom - top + 1,
                     base.baseline - top, "scripts")
        result.add(base, 0, -top, "base: ")
        if sub is not None:
            result.add(sub, base.width, sub_top - top, "sub: ")
        if sup is not None:
            result.add(sup, base.width, sup_top - top, "sup: ")
        return result

    def frac(self, node, style):
        numerator, denominator = (self.typeset(child, style) for child in node.children)
        if style == "normal":
            width = max(numerator.width, denominator.width) + 2
            result = Box(width, numerator.height + 1 + denominator.height, numerator.height, "frac")
            result.add(numerator, center(numerator, width), 0, "num: ")
            result.add(denominator, center(denominator, width), numerator.height + 1, "den: ")
            result.draw("-" * width, 0, numerator.height)
            return result
        if node.children[0].kind in ("row", "frac"):
            numerator = self.delimit(numerator, "(", ")")
        if node.children[1].kind in ("row", "frac"):
            denominator = self.delimit(denominator, "(", ")")
        slash = Box(1, 1, 0, 'atom "/"')
        slash.draw("/")
        return layout.row([numerator, slash, denominator], [0, 0], "slash", ["num: ", "", "den: "])

    def binom(self, node, style):
        upper, lower = (self.typeset(child, style) for child in node.children)
        width = max(upper.width, lower.width)
        height = upper.height + 1 + lower.height
        result = Box(width + 2, height, upper.height, "binom")
        result.add(upper, center(upper, width) + 1, 0, "upper: ")
        result.add(lower, center(lower, width) + 1, upper.height + 1, "lower: ")
        draw_delimiter(result, "(", 0, height)
        draw_delimiter(result, ")", width + 1, height)
        return result

    def overset(self, node, style):
        placed = self.typeset(node.children[0], "script")
        base = self.typeset(node.children[1], style)
        width = max(placed.width, base.width)
        result = Box(width, placed.height + base.height, placed.height + base.baseline, "overset")
        result.add(placed, center(placed, width), 0, "over: ")
        result.add(base, center(base, width), placed.height, "base: ")
        return result

    def underset(self, node, style):
        placed = self.typeset(node.children[0], "script")
        base = self.typeset(node.children[1], style)
        width = max(placed.width, base.width)
        result = Box(width, base.height + placed.height, base.baseline, "underset")
        result.add(base, center(base, width), 0, "base: ")
        result.add(placed, center(placed, width), base.height, "under: ")
        return result

    def radical(self, body, index=None):
        height = body.height
        extra = max(0, index.width - 1) if index is not None else 0
        top = max(0, index.height - height) if index is not None else 0
        result = Box(extra + height + 1 + body.width, height + 1 + top,
                     body.baseline + 1 + top, "root" if index is not None else "sqrt")
        result.draw("_" * body.width, extra + height + 1, top)
        result.draw("\\", extra, height + top)
        for row in range(1, height + 1):
            result.draw("/", extra + height - row + 1, row + top)
        if index is not None:
            result.add(index, 0, height - index.height + top, "index: ")
            result.add(body, extra + height + 1, 1 + top, "body: ")
        else:
            result.add(body, extra + height + 1, 1)
        return result

    def sqrt(self, node, style):
        return self.radical(self.typeset(node.children[0], style))

    def root(self, node, style):
        index = self.typeset(node.children[0], "script")
        body = self.typeset(node.children[1], style)
        return self.radical(body, index)

    def delimit(self, body, left, right):
        left_width = 0 if left == "." else 1
        right_width = 0 if right == "." else 1
        result = Box(left_width + body.width + right_width, body.height, body.baseline,
                     f"delim {left} {right}")
        result.add(body, left_width, 0)
        draw_delimiter(result, left, 0, body.height)
        draw_delimiter(result, right, left_width + body.width, body.height)
        return result

    def delim(self, node, style):
        return self.delimit(self.typeset(node.children[0], style), *node.value)

    def matrix(self, node, style):
        cells = [[self.typeset(cell, style) for cell in row] for row in node.children]
        row_count, column_count = len(cells), len(cells[0])
        widths = [max(row[column].width for row in cells) for column in range(column_count)]
        ascents = [max(cell.baseline for cell in row) for row in cells]
        descents = [max(cell.descent for cell in row) for row in cells]
        heights = [ascent + descent + 1 for ascent, descent in zip(ascents, descents)]
        column_gap, row_gap = self.parameters["col_gap"], self.parameters["row_gap"]
        body_width = sum(widths) + column_gap * (column_count - 1)
        body_height = sum(heights) + row_gap * (row_count - 1)
        environment = node.value
        shift = 0 if environment == "matrix" else 2
        extra = 0 if environment == "matrix" else 2 if environment == "cases" else 4
        result = Box(body_width + extra, body_height, (body_height - 1) // 2,
                     f"{environment} rows={row_count} cols={column_count}")
        y = 0
        for row_index, row in enumerate(cells):
            x = shift
            for column_index, cell in enumerate(row):
                offset = 0 if environment == "cases" else center(cell, widths[column_index])
                role = f"cell {row_index + 1},{column_index + 1}: "
                result.add(cell, x + offset, y + ascents[row_index] - cell.baseline, role)
                x += widths[column_index] + column_gap
            y += heights[row_index] + row_gap
        if environment == "cases":
            draw_delimiter(result, r"\{", 0, body_height)
        elif environment != "matrix":
            left, right = {"pmatrix": ("(", ")"), "bmatrix": ("[", "]"), "vmatrix": ("|", "|")}[environment]
            draw_delimiter(result, left, 0, body_height)
            draw_delimiter(result, right, body_width + 3, body_height)
        return result

    def accent(self, node, style):
        body = self.typeset(node.children[0], style)
        name = node.value
        width = body.width
        if name in ("hat", "dot", "tilde"):
            width = max(width, 1)
        elif name == "vec":
            width = max(width, 2)
        elif name in BRACE_ACCENTS:
            width += 2
        baseline = body.baseline if name == "underbrace" else body.baseline + 1
        result = Box(width, body.height + 1, baseline, name)
        if name == "underbrace":
            result.add(body, 1, 0)
            result.draw("\\" + "-" * body.width + "/", 0, body.height)
        elif name == "overbrace":
            result.add(body, 1, 1)
            result.draw("/" + "-" * body.width + "\\")
        else:
            result.add(body, 0, 1)
            if name == "overline":
                result.draw("_" * width)
            elif name == "vec":
                result.draw("-" * (width - 1) + ">")
            else:
                result.draw({"hat": "^", "dot": ".", "tilde": "~"}[name], (width - 1) // 2, 0)
        return result


def build_lines(breaks, types, boxes, starts, parameters):
    result = []
    position = 0
    alignment = None
    while position < len(boxes):
        if position == 0:
            indentation = 0
        elif alignment is None:
            indentation = parameters["indent"]
        elif types[position][0] == "relation":
            indentation = alignment[0]
        else:
            indentation = alignment[0] + alignment[1] + parameters["rel_space"]
        ends = sorted(end for end in breaks if end > position) + [len(boxes)]
        candidates = [(end, starts[end - 1] + boxes[end - 1].width - starts[position]) for end in ends]
        fitting = [candidate for candidate in candidates if indentation + candidate[1] <= parameters["width"]]
        end, width = fitting[-1] if fitting else candidates[0]
        result.append((position, end, indentation, width))
        if position == 0:
            for index in range(end):
                if types[index][0] == "relation":
                    alignment = starts[index], boxes[index].width
                    break
        position = end
    return result


def place_formula(formula, typesetter, parameters):
    nodes = formula.nodes
    types, gaps = layout.spacing(nodes, "normal", parameters)
    boxes = [typesetter.typeset(node) for node in nodes]
    starts = []
    x = 0
    for index, box in enumerate(boxes):
        starts.append(x)
        x += box.width
        if index < len(gaps):
            x += gaps[index]
    relations = {index for index in range(1, len(nodes)) if types[index][0] == "relation"}
    plus_minus = {index for index in range(1, len(nodes))
                  if nodes[index].kind == "symbol" and nodes[index].value in ("+", "-")
                  and types[index][0] == "binary"}
    punctuation = {index for index in range(1, len(nodes)) if types[index - 1][1] == "punctuation"}
    for breaks in (relations, relations | plus_minus, relations | plus_minus | punctuation):
        plan = build_lines(breaks, types, boxes, starts, parameters)
        if all(indentation + width <= parameters["width"] for start, end, indentation, width in plan):
            break
    roots, overfull = [], []
    width, height = 0, 0
    for number, (start, end, indentation, line_width) in enumerate(plan, 1):
        line = layout.row(boxes[start:end], gaps[start:end - 1], f"line {number}")
        roots.append((line, indentation, height))
        height += line.height
        width = max(width, indentation + line.width)
        if indentation + line_width > parameters["width"]:
            overfull.append((number, indentation + line_width))
    if formula.tag_string is not None:
        tag = formula.tag_string
        tx = parameters["width"] - len(tag)
        last, last_x, last_y = roots[-1]
        if tx >= last_x + last.width + 2:
            ty = last_y + last.baseline
        else:
            ty = height
            height += 1
        tag_box = Box(len(tag), 1, 0, f'tag "{tag}"')
        tag_box.draw(tag)
        roots.append((tag_box, tx, ty))
        width = max(width, tx + tag_box.width)
    return roots, len(plan), width, height, overfull


def tree_notation(node):
    kind = node.kind
    if kind in ("identifier", "number", "command"):
        return node.value
    if kind == "symbol":
        return "'" + node.value + "'"
    if kind == "text":
        return '"' + node.value + '"'
    if kind == "reference":
        return f'(eqref "{node.value}")'
    if kind == "row":
        return "(row" + "".join(" " + tree_notation(child) for child in node.children) + ")"
    if kind == "matrix":
        rows = ["[" + " ".join(tree_notation(cell) for cell in row) + "]" for row in node.children]
        return "(" + node.value + " " + " ".join(rows) + ")"
    if kind == "delim":
        delimiters = ["'" + value + "'" if len(value) == 1 else value for value in node.value]
        return "(delim " + " ".join(delimiters) + " " + tree_notation(node.children[0]) + ")"
    if kind == "script":
        base, sub, sup = node.children
        name = "sup" if sub is None else "sub" if sup is None else "subsup"
        children = [child for child in (base, sub, sup) if child is not None]
    else:
        name = node.value if kind == "accent" else kind
        children = node.children
    return "(" + name + " " + " ".join(tree_notation(child) for child in children) + ")"


class LinearNotation:
    def __init__(self, parameters, references):
        self.parameters = parameters
        self.references = references

    def row(self, nodes, style):
        types, gaps = layout.spacing(nodes, style, self.parameters)
        parts = []
        for index, node in enumerate(nodes):
            if index:
                parts.append(" " * gaps[index - 1])
            parts.append(self.node(node, style))
        return "".join(parts)

    def parenthesize(self, node, style, kinds):
        value = self.node(node, style)
        return "(" + value + ")" if node.kind in kinds else value

    def node(self, node, style="normal"):
        kind = node.kind
        if kind in ("identifier", "number", "symbol", "text"):
            return node.value
        if kind == "command":
            return COMMAND_DISPLAY[node.value]
        if kind == "reference":
            return self.references.get(node.value, "(??)")
        if kind == "row":
            return self.row(node.children, style)
        if kind == "frac":
            return "/".join(self.parenthesize(child, style, ("row", "frac")) for child in node.children)
        if kind == "script":
            base, sub, sup = node.children
            result = self.parenthesize(base, style, ("row", "frac", "script"))
            if sub is not None:
                result += "_" + self.parenthesize(sub, "script", ("row", "frac"))
            if sup is not None:
                result += "^" + self.parenthesize(sup, "script", ("row", "frac"))
            return result
        if kind == "delim":
            left, right = node.value
            return delimiter_string(left) + self.node(node.children[0], style) + delimiter_string(right)
        if kind == "matrix":
            rows = [", ".join(self.node(cell, style) for cell in row) for row in node.children]
            return node.value + "[" + "; ".join(rows) + "]"
        if kind == "root":
            return "root(" + self.node(node.children[0], "script") + ", " + self.node(node.children[1], style) + ")"
        if kind in ("overset", "underset"):
            return kind + "(" + self.node(node.children[0], "script") + ", " + self.node(node.children[1], style) + ")"
        name = node.value if kind == "accent" else kind
        return name + "(" + ", ".join(self.node(child, style) for child in node.children) + ")"


def diagnostic(formula, column, message, warning=False):
    prefix = "warning: " if warning else ""
    return [
        f"formula {formula.number}, column {column}: {prefix}{message}",
        "  " + formula.line,
        " " * (column + 1) + "^",
    ]


class Reports:
    def __init__(self, parameters, formulas, references):
        self.parameters = parameters
        self.formulas = formulas
        self.references = references
        self.typesetter = Typesetter(parameters, references)
        self.linear = LinearNotation(parameters, references)
        self.rendered = []
        self.boxes = []
        self.trees = []
        self.errors = []
        self.box_kinds = Counter()
        self.total_boxes = self.max_depth = 0
        self.valid_count = self.error_count = self.warning_count = self.overfull_count = 0

    def record_error(self, formula):
        self.error_count += 1
        self.rendered.append("(error)")
        self.boxes.append(f"formula {formula.number}: error")
        self.trees.append(f"formula {formula.number}: error")
        self.errors.extend(diagnostic(formula, *formula.error))

    def record_valid(self, formula):
        self.valid_count += 1
        collect_warnings(formula, self.references)
        roots, line_count, width, height, overfull = place_formula(formula, self.typesetter, self.parameters)
        self.rendered.extend(canvas.draw(roots, width, height))
        entries = list(canvas.box_lines(roots))
        depth = max(level for line, level, kind in entries) + 1
        self.total_boxes += len(entries)
        self.max_depth = max(self.max_depth, depth)
        self.boxes.append(f"formula {formula.number}: lines={line_count} width={width} height={height} "
                          f"boxes={len(entries)} depth={depth}")
        for line, level, kind in entries:
            self.boxes.append(line)
            self.box_kinds[kind] += 1
        tree = " ".join(tree_notation(node) for node in formula.nodes)
        linear = self.linear.row(formula.nodes, "normal").rstrip(" ")
        self.trees.append(f"formula {formula.number}: {tree}")
        self.trees.append("  linear:" + (" " + linear if linear else ""))
        if formula.tag_string is not None:
            self.trees.append("  tag: " + formula.tag_string)
        self.warning_count += len(formula.warnings)
        for column, message in formula.warnings:
            self.errors.extend(diagnostic(formula, column, message, warning=True))
        self.overfull_count += len(overfull)
        for number, occupied in overfull:
            self.errors.append(f"formula {formula.number}: line {number} is overfull "
                               f"(width {occupied} > {self.parameters['width']})")

    def build(self):
        for index, formula in enumerate(self.formulas):
            if index:
                self.rendered.append("")
            self.rendered.append(f"formula {formula.number}")
            if formula.error is not None:
                self.record_error(formula)
            else:
                self.record_valid(formula)
        self.boxes.append(f"summary: boxes={self.total_boxes} max_depth={self.max_depth}")
        self.boxes.extend(f"  {kind}: {self.box_kinds[kind]}" for kind in sorted(self.box_kinds))
        self.errors.append(f"formulas={len(self.formulas)} rendered={self.valid_count} errors={self.error_count} "
                           f"warnings={self.warning_count} overfull={self.overfull_count}")

    def write(self):
        directory = Path("output")
        directory.mkdir(exist_ok=True)
        outputs = (("rendered.txt", self.rendered), ("boxes.txt", self.boxes),
                   ("trees.txt", self.trees), ("errors.txt", self.errors))
        for filename, lines in outputs:
            with (directory / filename).open("w", encoding="ascii", newline="\n") as destination:
                destination.write("\n".join(lines) + "\n")


def main():
    parameters, formulas = read_inputs()
    references = reference_table(formulas)
    reports = Reports(parameters, formulas, references)
    reports.build()
    reports.write()


if __name__ == "__main__":
    main()
