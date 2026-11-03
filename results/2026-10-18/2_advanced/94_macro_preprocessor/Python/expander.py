"""Value-based Prosser rescanning, arguments, stringizing, and token pastes."""

import sys
from collections import Counter, deque

from definitions import BUILTINS, VARIADIC_NAME
from lexer import Token, single_token


class Expander:
    def __init__(self, macros, diagnostic):
        self.macros, self.diagnostic = macros, diagnostic
        self.counter, self.depth = 0, 0
        self.builtin_counts = Counter()

    def error(self, context, token, message):
        self.diagnostic(context.position(token.line), "error", message)

    def builtin(self, token, context):
        self.builtin_counts[token.spelling] += 1
        if token.spelling == "__FILE__":
            kind, spelling = "string", '"' + context.display_file + '"'
        elif token.spelling == "__LINE__":
            kind, spelling = "number", str(context.position(token.line)[1])
        else:
            kind, spelling = "number", str(self.counter)
            self.counter += 1
        return Token(kind, spelling, token.line, token.space)

    def collect(self, pending, macro, token, context):
        arguments, separators, nesting = [[]], [], 0
        closing, consumed = None, None
        for index, current in enumerate(pending):
            if index == 0:
                continue
            if current.spelling == ")" and nesting == 0:
                closing, consumed = current, index + 1
                break
            if current.spelling == "," and nesting == 0:
                separators.append(current)
                arguments.append([])
            else:
                if current.spelling == "(":
                    nesting += 1
                elif current.spelling == ")":
                    nesting -= 1
                arguments[-1].append(current)
        if closing is None:
            self.error(context, token, f'unterminated argument list invoking macro "{macro.name}"')
            return None
        count = len(arguments)
        fixed = len(macro.parameters) - int(macro.variadic)
        error = None
        if (not macro.variadic and fixed == 0
                and (count != 1 or arguments[0])):
            error = f'macro "{macro.name}" passed {count} arguments, but takes just 0'
        elif count < fixed:
            error = f'macro "{macro.name}" requires {fixed} arguments, but only {count} given'
        elif count > fixed and not macro.variadic:
            error = f'macro "{macro.name}" passed {count} arguments, but takes just {fixed}'
        if error is not None:
            self.error(context, token, error)
            return None
        raw = dict(zip(macro.parameters[:fixed], arguments[:fixed]))
        if macro.variadic:
            variable = []
            for index in range(fixed, count):
                if index > fixed:
                    variable.append(separators[index - 1])
                variable.extend(arguments[index])
            raw[VARIADIC_NAME] = variable
        return raw, consumed, closing

    def stringize(self, tokens, sharp):
        pieces = []
        for index, token in enumerate(tokens):
            if index and token.space:
                pieces.append(" ")
            spelling = token.spelling
            if token.kind in ("string", "character"):
                spelling = spelling.replace("\\", "\\\\").replace('"', '\\"')
            pieces.append(spelling)
        return Token("string", '"' + "".join(pieces) + '"', sharp.line, sharp.space)

    def paste(self, left, right, token, context):
        if left.kind == "placemarker":
            return [right._replace(space=left.space)]
        if right.kind == "placemarker":
            return [left]
        spelling = left.spelling + right.spelling
        kind = single_token(spelling)
        if kind is not None:
            return [Token(kind, spelling, left.line, left.space, left.hide & right.hide)]
        self.error(context, token, f'pasting "{left.spelling}" and "{right.spelling}" does not give a valid preprocessing token')
        return [left, right._replace(space=False)]

    def substitute(self, macro, raw, token, hide, context):
        replacement, items, expanded = macro.replacement, [], {}
        index = 0
        while index < len(replacement):
            current = replacement[index]
            if current.spelling == "#" and macro.parameters is not None:
                parameter = replacement[index + 1].spelling
                items.append([self.stringize(raw[parameter], current)])
                index += 2
                continue
            if current.spelling == "##":
                items.append(current)
            elif current.kind == "identifier" and current.spelling in raw:
                adjacent = (index > 0 and replacement[index - 1].spelling == "##"
                            or index + 1 < len(replacement) and replacement[index + 1].spelling == "##")
                if adjacent:
                    sequence = raw[current.spelling]
                else:
                    if current.spelling not in expanded:
                        expanded[current.spelling] = self.expand(raw[current.spelling], context)
                    sequence = expanded[current.spelling]
                if sequence:
                    items.append([sequence[0]._replace(space=current.space), *sequence[1:]])
                else:
                    items.append([Token("placemarker", "", current.line, current.space)])
            else:
                items.append([current])
            index += 1
        pasted, index = [], 0
        while index < len(items):
            item = items[index]
            if isinstance(item, Token):
                left = pasted.pop()
                right = items[index + 1]
                if isinstance(right, Token):
                    right = [right]
                pasted.extend(self.paste(left, right[0], token, context))
                pasted.extend(right[1:])
                index += 2
            else:
                pasted.extend(item)
                index += 1
        result, carry_space = [], False
        for current in pasted:
            if current.kind == "placemarker":
                carry_space = carry_space or current.space
            else:
                result.append(current._replace(line=token.line, space=current.space or carry_space,
                                               hide=current.hide | hide))
                carry_space = False
        if result:
            result[0] = result[0]._replace(space=token.space)
        return result

    def expand(self, sequence, context):
        self.depth += 1
        sys.setrecursionlimit(max(sys.getrecursionlimit(), 8 * (self.depth + len(sequence) + 1) + 1000))
        try:
            pending, result = deque(sequence), []
            while pending:
                token = pending.popleft()
                if token.kind != "identifier" or token.spelling in token.hide:
                    result.append(token)
                    continue
                if token.spelling in BUILTINS:
                    result.append(self.builtin(token, context))
                    continue
                macro = self.macros.get(token.spelling)
                if macro is None or macro.parameters is not None and (not pending or pending[0].spelling != "("):
                    result.append(token)
                    continue
                raw = {}
                hide = token.hide | {macro.name}
                if macro.parameters is not None:
                    collected = self.collect(pending, macro, token, context)
                    if collected is None:
                        result.append(token)
                        continue
                    raw, consumed, closing = collected
                    for _ in range(consumed):
                        pending.popleft()
                    hide = (token.hide & closing.hide) | {macro.name}
                replacement = self.substitute(macro, raw, token, hide, context)
                macro.expanded += 1
                if not replacement and token.space and pending:
                    pending[0] = pending[0]._replace(space=True)
                pending.extendleft(reversed(replacement))
            return result
        finally:
            self.depth -= 1
