"""Process a translation unit and report expansion, inclusions, and diagnostics."""

from collections import Counter, defaultdict, namedtuple
from itertools import groupby
from pathlib import Path
from types import SimpleNamespace

import definitions
import expression
from expander import Expander
from include_manager import BRANCHES, STARTS, IncludeManager, directive_name
from lexer import Token, lex_definition, read_token, render


CONDITIONALS = (*STARTS, *BRANCHES, "endif")
Header = namedtuple("Header", "rendering name quoted")


class DirectiveError(Exception):
    pass


class Inclusion:
    def __init__(self, source, depth):
        self.source, self.depth = source, depth
        self.display_file, self.offset = source.path, 0
        self.stack, self.segment = [], []

    def position(self, physical):
        return self.display_file, physical + self.offset

    def skipping(self):
        return bool(self.stack) and not self.stack[-1].active


def separator_needed(left, right):
    if left == "/" and right[0] in "/*":
        return True
    _, _, end = read_token(left + right)
    return end != len(left)


def output_render(tokens):
    pieces = []
    previous = None
    for token in tokens:
        if previous is not None and (token.space or separator_needed(previous, token.spelling)):
            pieces.append(" ")
        pieces.append(token.spelling)
        previous = token.spelling
    return "".join(pieces)


def following(heading, items):
    return heading + "".join(" " + item for item in items)


def header_specification(tokens, position=0):
    if position >= len(tokens):
        return None, position
    token = tokens[position]
    if token.kind in ("string", "header"):
        text = token.spelling
        return Header(text, text[1:-1], text.startswith('"')), position + 1
    if token.spelling == "<":
        closing = position + 1
        while closing < len(tokens) and tokens[closing].spelling != ">":
            closing += 1
        if closing == len(tokens):
            raise DirectiveError("missing terminating > character")
        text = "<" + render(tokens[position + 1:closing]) + ">"
        return Header(text, text[1:-1], False), closing + 1
    return None, position


def decimal_token(token):
    return token.kind == "number" and all("0" <= character <= "9" for character in token.spelling)


class Preprocessor:
    def __init__(self):
        self.macros, self.ever_defined = {}, set()
        self.saved = defaultdict(list)
        self.poisoned = set()
        self.manager = IncludeManager()
        self.expander = Expander(self.macros, self.diagnostic)
        self.output, self.history, self.diagnostics = [], [], []
        self.tree, self.conditional_records, self.regions = ["main.c"], [], []
        self.diagnostic_counts, self.condition_counts = Counter(), Counter()
        self.previous = None

    def diagnostic(self, position, kind, message):
        filename, line = position
        self.diagnostics.append(f"{filename}:{line}: {kind}: {message}")
        self.diagnostic_counts[kind] += 1

    def event(self, position, content):
        filename, line = position
        self.history.append(f"{filename}:{line}: {content}")

    def poison_check(self, context, tokens):
        for token in tokens:
            if token.kind == "identifier" and token.spelling in self.poisoned:
                self.diagnostic(context.position(token.line), "error", f'attempt to use poisoned "{token.spelling}"')

    def unused_check(self, macro):
        if macro.main_file and macro.expanded == 0 and macro.tested == 0:
            self.diagnostic(macro.position, "warning", f'macro "{macro.name}" is not used')

    def define(self, tokens, position, main_file):
        try:
            macro = definitions.parse(tokens, position, main_file)
        except definitions.DefinitionError as error:
            self.diagnostic(position, "error", str(error))
            return
        previous = self.macros.get(macro.name)
        if previous is None:
            self.macros[macro.name] = macro
            self.ever_defined.add(macro.name)
            operation = "define"
        elif previous.identical(macro):
            operation = "identical"
        else:
            self.unused_check(previous)
            filename, line = previous.position
            self.diagnostic(position, "warning", f'"{macro.name}" redefined (previous definition at {filename}:{line})')
            self.macros[macro.name] = macro
            self.ever_defined.add(macro.name)
            operation = "redefine"
        self.event(position, operation + " " + macro.signature())

    def undefine(self, tokens, position):
        error = definitions.check_name(tokens, "undef")
        if error is not None:
            self.diagnostic(position, "error", error)
            return
        if len(tokens) >= 2:
            self.diagnostic(position, "warning", "extra tokens at end of #undef directive")
        name = tokens[0].spelling
        if name in self.macros:
            self.unused_check(self.macros[name])
            del self.macros[name]
            self.event(position, "undef " + name)
        else:
            self.event(position, "undef " + name + " (not defined)")

    def process_defines(self):
        contents = Path("input/defines.txt").read_bytes().decode("ascii")
        for number, line in enumerate(contents.split("\n"), 1):
            if not line:
                continue
            if "=" in line:
                name, value = line.split("=", 1)
                text = name + " " + value
            else:
                text = line + " 1"
            self.define(lex_definition(text, number), ("defines.txt", number), False)

    def marker(self, filename, line, flag=None):
        text = f'# {line} "{filename}"'
        if flag is not None:
            text += " " + str(flag)
        self.output.append(text)
        self.previous = filename, line - 1

    def output_line(self, context, physical, text):
        filename, line = context.position(physical)
        previous_file, previous_line = self.previous
        if filename == previous_file and previous_line < line <= previous_line + 8:
            self.output.extend([""] * (line - previous_line - 1))
        else:
            self.marker(filename, line)
        self.output.append(text)
        self.previous = filename, line
        context.source.output_lines += 1

    def flush(self, context):
        segment, context.segment = context.segment, []
        if not segment:
            return
        self.poison_check(context, segment)
        expanded = self.expander.expand(segment, context)
        for physical, group in groupby(expanded, key=lambda token: token.line):
            self.output_line(context, physical, output_render(list(group)))

    def macro_defined(self, name):
        if name in self.macros:
            self.macros[name].tested += 1
            return True
        return name in definitions.BUILTINS or name == "__has_include"

    def replace_operators(self, context, operands):
        replaced, position = [], 0
        while position < len(operands):
            token = operands[position]
            if token.kind == "identifier" and token.spelling == "defined":
                index = position + 1
                parenthesized = index < len(operands) and operands[index].spelling == "("
                if parenthesized:
                    index += 1
                if index == len(operands) or operands[index].kind != "identifier":
                    raise DirectiveError('operator "defined" requires an identifier')
                name = operands[index].spelling
                index += 1
                if parenthesized:
                    if index == len(operands) or operands[index].spelling != ")":
                        raise DirectiveError('missing \')\' after "defined"')
                    index += 1
                value = self.macro_defined(name)
            elif token.kind == "identifier" and token.spelling == "__has_include":
                index = position + 1
                if index == len(operands) or operands[index].spelling != "(":
                    raise DirectiveError('missing \'(\' after "__has_include"')
                header, index = header_specification(operands, index + 1)
                if header is None or not header.name:
                    raise DirectiveError('operator "__has_include" requires a header-name')
                if index == len(operands) or operands[index].spelling != ")":
                    raise DirectiveError('missing \')\' after "__has_include" operand')
                index += 1
                value = self.manager.search(header.name, header.quoted) is not None
            else:
                replaced.append(token)
                position += 1
                continue
            replaced.append(Token("number", str(int(value)), token.line, token.space))
            position = index
        return replaced

    def test(self, context, logical, name, operands):
        position = context.position(logical.tokens[0].line)
        self.poison_check(context, operands)
        if name not in ("if", "elif"):
            if not operands:
                self.diagnostic(position, "error", "no macro name given in #" + name + " directive")
                return None, None
            if operands[0].kind != "identifier":
                self.diagnostic(position, "error", "macro names must be identifiers")
                return None, None
            if len(operands) >= 2:
                self.diagnostic(position, "warning", "extra tokens at end of #" + name + " directive")
            defined = self.macro_defined(operands[0].spelling)
            value = not defined if name in ("ifndef", "elifndef") else defined
            return int(value), None
        try:
            replaced = self.replace_operators(context, operands)
        except DirectiveError as error:
            self.diagnostic(position, "error", str(error))
            return None, None
        expanded = self.expander.expand(replaced, context)
        try:
            tree = expression.parse(expanded, name)
            value = expression.evaluate(tree, lambda message: self.diagnostic(position, "warning", message))
        except expression.ExpressionError as error:
            self.diagnostic(position, "error", str(error))
            return None, expanded
        return value, expanded

    def test_description(self, name, value, expanded):
        if value is None:
            description = "not taken (error)"
        else:
            description = "taken" if value != 0 else "not taken"
            if name in ("if", "elif"):
                description += f" (value {value})"
        if expanded is not None:
            description += " [" + output_render(expanded) + "]"
        return description

    def close_region(self, context, block, end):
        start = block.skip_start
        if start is not None and end >= start:
            filename, first = context.position(start)
            last = context.position(end)[1]
            self.regions.append(f"{filename}:{first}-{last} lines={end - start + 1}")
            context.source.skipped_lines += end - start + 1
        block.skip_start = None

    def conditional_record(self, position, depth, name, operands, description):
        filename, line = position
        directive = "#" + name
        if operands:
            directive += " " + render(operands)
        self.conditional_records.append(f"{filename}:{line}: " + "  " * depth + directive + " => " + description)
        for prefix, category in (("taken", "taken"), ("not taken", "not_taken"), ("skipped", "skipped"),
                                 ("not evaluated", "not_evaluated"), ("closes", "endif")):
            if description.startswith(prefix):
                self.condition_counts[category] += 1
                break

    def conditional(self, context, logical, name, operands):
        position = context.position(logical.tokens[0].line)
        if name in STARTS:
            parent = not context.stack or context.stack[-1].active
            block = SimpleNamespace(kind=name, position=position, parent=parent, chosen=False,
                                    active=False, else_seen=False, skip_start=None)
            if parent:
                value, expanded = self.test(context, logical, name, operands)
                if value is not None and value != 0:
                    block.chosen, block.active = True, True
                else:
                    block.skip_start = logical.end + 1
                description = self.test_description(name, value, expanded)
            else:
                description = "skipped"
            self.conditional_record(position, len(context.stack), name, operands, description)
            context.stack.append(block)
            return
        if not context.stack:
            self.diagnostic(position, "error", "#" + name + " without #if")
            return
        block, depth = context.stack[-1], len(context.stack) - 1
        self.close_region(context, block, logical.start - 1)
        if name == "endif":
            context.stack.pop()
            if block.parent and operands:
                self.diagnostic(position, "warning", "extra tokens at end of #endif directive")
            description = f"closes #{block.kind} at line {block.position[1]}"
        else:
            if block.else_seen:
                self.diagnostic(position, "error", "#" + name + " after #else")
            if name == "else":
                if block.parent and operands:
                    self.diagnostic(position, "warning", "extra tokens at end of #else directive")
                block.else_seen = True
                if block.parent:
                    block.active = not block.chosen
                    block.chosen = True
                    description = "taken" if block.active else "not taken"
                else:
                    block.active, description = False, "skipped"
            elif not block.parent:
                block.active, description = False, "skipped"
            elif block.chosen:
                block.active, description = False, "not evaluated"
            else:
                value, expanded = self.test(context, logical, name, operands)
                block.active = value is not None and value != 0
                if block.active:
                    block.chosen = True
                description = self.test_description(name, value, expanded)
            if block.parent and not block.active:
                block.skip_start = logical.end + 1
        self.conditional_record(position, depth, name, operands, description)

    def include(self, context, logical, operands):
        position = context.position(logical.tokens[0].line)
        try:
            sequence = operands
            header, consumed = header_specification(sequence)
            if header is None and sequence:
                sequence = self.expander.expand(sequence, context)
                header, consumed = header_specification(sequence)
            if header is None:
                raise DirectiveError('#include expects "FILENAME" or <FILENAME>')
            if consumed < len(sequence):
                self.diagnostic(position, "warning", "extra tokens at end of #include directive")
            if not header.name:
                raise DirectiveError("empty filename in #include")
        except DirectiveError as error:
            self.diagnostic(position, "error", str(error))
            return
        prefix = "  " * (context.depth + 1) + str(logical.tokens[0].line) + ": "
        path = self.manager.search(header.name, header.quoted)
        if path is None:
            self.tree.append(prefix + header.rendering + " [not found]")
            self.diagnostic(position, "error", "cannot find include file " + header.rendering)
            return
        previous = self.manager.files.get(path)
        if previous is not None and previous.once:
            self.tree.append(prefix + path + " [skipped: pragma once]")
            previous.skipped += 1
            return
        if previous is not None and previous.guard is not None and previous.guard in self.macros:
            self.tree.append(prefix + path + " [skipped: guard " + previous.guard + "]")
            previous.skipped += 1
            return
        if context.depth + 1 > 8:
            self.tree.append(prefix + path + " [too deep]")
            self.diagnostic(position, "error", "#include nested too deeply")
            return
        self.tree.append(prefix + path)
        self.marker(path, 1, 1)
        self.process_file(path, context.depth + 1)
        filename, line = context.position(logical.end + 1)
        self.marker(filename, line, 2)

    def line_directive(self, context, logical, operands):
        position = context.position(logical.tokens[0].line)
        if not operands or not decimal_token(operands[0]):
            operands = self.expander.expand(operands, context)
        if len(operands) not in (1, 2) or not decimal_token(operands[0]) or len(operands) == 2 and operands[1].kind != "string":
            self.diagnostic(position, "error", "invalid #line directive")
            return
        line = int(operands[0].spelling)
        if not 1 <= line <= 2147483647:
            self.diagnostic(position, "error", "line number out of range")
            return
        context.offset = line - (logical.end + 1)
        if len(operands) == 2:
            context.display_file = operands[1].spelling[1:-1]

    def macro_pragma(self, position, operands, operation):
        if len(operands) != 4 or operands[1].spelling != "(" or operands[2].kind != "string" or operands[3].spelling != ")":
            self.diagnostic(position, "error", "invalid #pragma " + operation + " directive")
            return
        name = operands[2].spelling[1:-1]
        if operation == "push_macro":
            self.saved[name].append(self.macros.get(name))
            self.event(position, "push " + name)
        elif not self.saved[name]:
            self.diagnostic(position, "warning", f'no matching push_macro for "{name}"')
        else:
            macro = self.saved[name].pop()
            if macro is None:
                self.macros.pop(name, None)
                self.event(position, "pop " + name + " (undefined)")
            else:
                self.macros[name] = macro
                self.event(position, "pop " + name)

    def pragma(self, context, logical, operands):
        position = context.position(logical.tokens[0].line)
        name = operands[0].spelling if operands and operands[0].kind == "identifier" else None
        if name == "once":
            if len(operands) >= 2:
                self.diagnostic(position, "warning", "extra tokens at end of #pragma once directive")
            if context.depth == 0:
                self.diagnostic(position, "warning", "#pragma once in main file")
            context.source.once = True
        elif len(operands) >= 2 and operands[0].spelling == "GCC" and operands[1].spelling == "poison":
            if any(token.kind != "identifier" for token in operands[2:]):
                self.diagnostic(position, "error", "invalid #pragma GCC poison directive")
                return
            for token in operands[2:]:
                if token.spelling in self.macros:
                    self.diagnostic(position, "warning", f'poisoning existing macro "{token.spelling}"')
                self.poisoned.add(token.spelling)
        elif name in ("push_macro", "pop_macro"):
            self.macro_pragma(position, operands, name)
        else:
            text = "#pragma" + (" " + render(operands) if operands else "")
            self.output_line(context, logical.tokens[0].line, text)

    def directive(self, context, logical, name, operands):
        if len(logical.tokens) == 1:
            return
        poisoning = name == "pragma" and len(operands) >= 2 and operands[0].spelling == "GCC" and operands[1].spelling == "poison"
        if not poisoning:
            self.poison_check(context, operands)
        position = context.position(logical.tokens[0].line)
        if name == "define":
            self.define(operands, position, context.depth == 0)
        elif name == "undef":
            self.undefine(operands, position)
        elif name == "include":
            self.include(context, logical, operands)
        elif name == "line":
            self.line_directive(context, logical, operands)
        elif name in ("error", "warning"):
            text = "#" + name + (" " + render(operands) if operands else "")
            self.diagnostic(position, name, text)
        elif name == "pragma":
            self.pragma(context, logical, operands)
        else:
            self.diagnostic(position, "error", "invalid preprocessing directive #" + logical.tokens[1].spelling)

    def process_file(self, path, depth):
        source = self.manager.load(path)
        source.entered += 1
        context = Inclusion(source, depth)
        for logical in source.lines:
            tokens = logical.tokens
            is_directive = bool(tokens) and tokens[0].spelling == "#"
            name = directive_name(tokens)
            operands = tokens[2:]
            if is_directive and name in CONDITIONALS:
                self.flush(context)
                self.conditional(context, logical, name, operands)
            elif context.skipping():
                continue
            elif is_directive:
                self.flush(context)
                self.directive(context, logical, name, operands)
            else:
                context.segment.extend(tokens)
        self.flush(context)
        for block in context.stack:
            self.close_region(context, block, source.physical_lines)
        for block in context.stack:
            self.diagnostic(block.position, "error", "unterminated #" + block.kind)

    def include_report(self):
        lines = self.tree + ["", "== files =="]
        for path in sorted(self.manager.files):
            source = self.manager.files[path]
            guard = source.guard if source.guard is not None else "-"
            once = "yes" if source.once else "no"
            lines.append(f"{path} entered={source.entered} skipped={source.skipped} lines={source.physical_lines} "
                         f"output_lines={source.output_lines} skipped_lines={source.skipped_lines} guard={guard} once={once}")
        lines.append("")
        current, has_path = "main.o:", False
        for path in self.manager.files:
            if len(current) + 1 + len(path) > 76 and has_path:
                lines.append(current + " \\")
                current, has_path = " ", False
            current += " " + path
            has_path = True
        lines.append(current)
        return lines

    def references(self):
        references = {}
        for name, macro in self.macros.items():
            parameters = set(macro.parameters or ())
            references[name] = sorted({token.spelling for token in macro.replacement
                                       if token.kind == "identifier" and token.spelling in self.macros
                                       and token.spelling not in parameters})
        return references

    def recursive(self, name, references):
        pending, seen = list(references[name]), set()
        while pending:
            current = pending.pop()
            if current == name:
                return True
            if current not in seen:
                seen.add(current)
                pending.extend(references[current])
        return False

    def macro_report(self):
        lines = ["== history ==", *self.history, "", "== table =="]
        references = self.references()
        for name in sorted(self.macros):
            macro = self.macros[name]
            definition = "#define " + macro.signature()
            if macro.replacement:
                definition += " " + render(macro.replacement)
            lines.append(definition)
            filename, line = macro.position
            recursive = "yes" if self.recursive(name, references) else "no"
            lines.append(f"  at {filename}:{line} expanded={macro.expanded} tested={macro.tested} recursive={recursive}")
            lines.append(following("  refs:", references[name]))
        object_like = sum(macro.parameters is None for macro in self.macros.values())
        lines.extend(["", f"macros={len(self.macros)} object_like={object_like} function_like={len(self.macros) - object_like}"])
        lines.append(following("undefined:", sorted(self.ever_defined - self.macros.keys())))
        counts = self.expander.builtin_counts
        lines.append(f"builtins: __COUNTER__={counts['__COUNTER__']} __FILE__={counts['__FILE__']} __LINE__={counts['__LINE__']}")
        return lines

    def conditional_report(self):
        lines = self.conditional_records + ["", "== skipped regions ==", *self.regions, ""]
        counts = self.condition_counts
        lines.append(f"directives={len(self.conditional_records)} taken={counts['taken']} not_taken={counts['not_taken']} "
                     f"skipped={counts['skipped']} not_evaluated={counts['not_evaluated']} endif={counts['endif']} regions={len(self.regions)}")
        return lines

    def write_reports(self):
        diagnostic_lines = self.diagnostics + [f"errors={self.diagnostic_counts['error']} warnings={self.diagnostic_counts['warning']}"]
        reports = (("preprocessed.txt", self.output), ("includes.txt", self.include_report()),
                   ("macros.txt", self.macro_report()), ("conditionals.txt", self.conditional_report()),
                   ("diagnostics.txt", diagnostic_lines))
        output = Path("output")
        output.mkdir(exist_ok=True)
        for name, lines in reports:
            text = "\n".join(line.rstrip(" ") for line in lines) + "\n"
            (output / name).write_text(text, encoding="ascii", newline="\n")

    def run(self):
        self.process_defines()
        self.marker("main.c", 1)
        self.process_file("main.c", 0)
        for name in sorted(self.macros):
            self.unused_check(self.macros[name])
        self.write_reports()


def main():
    Preprocessor().run()


if __name__ == "__main__":
    main()
