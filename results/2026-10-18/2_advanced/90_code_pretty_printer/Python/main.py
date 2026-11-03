"""Pretty printer for the benchmark's small C-like language.

The formatter builds a concrete syntax tree, constructs a Wadler-style
document, decides flat or broken groups by lookahead, and independently
reformats its own output to check idempotency. It writes only under output/.
"""

from pathlib import Path

from doc_builder import (
    BREAK_PARENT, HARDLINE, LINE, SOFTLINE, align, all_groups,
    concat, group, if_break, nest, suffix, text,
)
from lexer import SourceError, attach_comments, first_comment_blank, lexical_analysis
from parser import Parser
from printer import layout
from report import diff_lines, doc_tree, write_lines


def read_profiles(path="input/style.txt"):
    """Read the ten required profile settings and retain profile order."""
    profiles = {}
    current = None
    for line in Path(path).read_text(encoding="ascii").splitlines():
        if not line:
            continue
        if line.startswith("[") and line.endswith("]"):
            current = line[1:-1]
            profiles[current] = {}
            continue
        key, value = line.split("=", 1)
        if key in ("width", "indent", "max_blank_lines", "comment_column"):
            value = int(value)
        elif key in ("space_around_operators", "space_after_keyword",
                     "indent_case_labels", "add_braces", "remove_parens"):
            value = value == "yes"
        profiles[current][key] = value
    return profiles


def read_sources(path="input/sources.txt"):
    """Retain headers verbatim and separate source lines without trimming them."""
    source_files = []
    for line in Path(path).read_text(encoding="ascii").splitlines():
        if line.startswith("=== "):
            marker, filename, profile = line.split(" ")
            entry = {
                "header": line,
                "filename": filename,
                "profile": profile,
                "lines": [],
            }
            source_files.append(entry)
        else:
            source_files[-1]["lines"].append(line)
    return source_files


def check_comment_positions(tokens):
    """Reject the earliest comment whose own-line position cannot be preserved."""
    for token in tokens:
        for comment in token["leading"]:
            if (token["trailing_comma"] or
                    (comment["own_line"] and not token["allowed"])):
                raise SourceError(
                    comment["line"], comment["column"],
                    "comment not allowed here",
                )


class DocumentFormatter:
    """Construct normalized documents directly from the concrete parse tree."""

    def __init__(self, profile, tokens):
        self.profile = profile
        self.tokens = tokens
        self.indent_width = profile["indent"]
        self.max_blank = profile["max_blank_lines"]
        self.spaced_operators = profile["space_around_operators"]
        self.separator = " " if self.spaced_operators else ""
        self.operator_break = LINE if self.spaced_operators else SOFTLINE
        self.keyword_gap = " " if profile["space_after_keyword"] else ""
        self.kr = profile["brace_style"] == "kr"

    def sep(self, blank):
        """One mandatory newline followed by up to M preserved blank lines."""
        return concat([
            HARDLINE, *([HARDLINE] * min(blank, self.max_blank))
        ])

    def pre_blank(self, tok):
        return first_comment_blank(tok)

    def comments(self, comments, following):
        """Render comments with the source's own-line/inline relationship."""
        documents = []
        for i, comment in enumerate(comments):
            documents.append(text(comment["text"]))
            next_entry = (
                comments[i + 1] if i + 1 < len(comments) else following
            )
            if next_entry is None:
                continue
            if comment["own_line"]:
                documents.append(HARDLINE)
                documents.extend(
                    HARDLINE for _ in range(
                        min(next_entry["blank"], self.max_blank)
                    )
                )
            else:
                documents.append(text(" "))
        return concat(documents)

    def t(self, tok, leading=None):
        """Token document, including inline leading comments and suffixes."""
        prefix = tok["leading"] if leading is None else leading
        trailing = tok["trailing"]
        return concat([
            self.comments(prefix, tok),
            text(tok["text"]),
            suffix(" ".join(comment["text"] for comment in trailing))
            if trailing else None,
        ])

    def splitting_comments(self, close):
        """Own-line prefix H and inline suffix G before a closing brace."""
        comments = close["leading"]
        last_own = -1
        for i, comment in enumerate(comments):
            if comment["own_line"]:
                last_own = i
        return comments[:last_own + 1], comments[last_own + 1:]

    def closing_comments(self, comments, preceding):
        if not comments:
            return None
        return concat([
            self.sep(comments[0]["blank"]) if preceding else None,
            self.comments(comments, None),
        ])

    def whole_file(self, items, end_token):
        """Concatenate item documents, preserving blank lines and end comments."""
        pieces = []
        for index, item in enumerate(items):
            if index:
                pieces.append(self.sep(self.pre_blank(item["first"])))
            pieces.append(self.item(item))
        if end_token["leading"]:
            pieces.append(
                self.sep(end_token["leading"][0]["blank"]) if items else None
            )
            pieces.append(self.comments(end_token["leading"], None))
        return concat(pieces)

    def item(self, item):
        if item["tag"] == "function":
            return concat([
                self.t(item["typ"]), " ", self.t(item["name"]),
                self.list_doc(item["parameters"]), HARDLINE,
                self.block(item["body"]),
            ])
        return self.variable(item)

    def parameter(self, param):
        pieces = [self.t(param["typ"]), " ", self.t(param["name"])]
        for opening, closing in param["brackets"]:
            pieces.extend([self.t(opening), self.t(closing)])
        return concat(pieces)

    def variable(self, statement):
        pieces = [self.t(statement["typ"]), " ", self.t(statement["name"])]
        for opening, expression, closing in statement["dimensions"]:
            pieces.append(self.t(opening))
            if expression is not None:
                pieces.append(self.expr(expression, 0))
            pieces.append(self.t(closing))
        if statement["equals"] is not None:
            pieces.extend([
                self.separator, self.t(statement["equals"]),
                self.separator, self.initializer(statement["initializer"]),
            ])
        if statement["semi"] is not None:
            pieces.append(self.t(statement["semi"]))
        return concat(pieces)

    def initializer(self, entry):
        if entry["tag"] == "list":
            return self.list_doc(entry)
        return self.expr(entry, 0)

    def list_contents(self, entry):
        elements = []
        for item in entry["elements"]:
            if entry["role"] == "(" and item["tag"] == "parameter":
                elements.append(self.parameter(item))
            elif entry["role"] == "{" and item["tag"] == "list":
                elements.append(self.list_doc(item))
            else:
                elements.append(self.initializer(item) if entry["role"] == "{"
                                else self.expr(item, 0))
        return elements

    def list_force_marker(self, entry):
        """A trailing comment anywhere inside the list forces its group to break."""
        first = entry["left"]["index"]
        last = entry["right"]["index"]
        any_trailing = any(
            self.tokens[index]["trailing"]
            for index in range(first, last)
        )
        return BREAK_PARENT if any_trailing else None

    def list_doc(self, entry):
        """Render all nonempty lists as groups with a single coherent break mode."""
        left, right = entry["left"], entry["right"]
        elements = self.list_contents(entry)
        if not elements:
            return concat([self.t(left), self.t(right)])
        separated = [SOFTLINE, elements[0]]
        for comma, element in zip(entry["commas"], elements[1:]):
            separated.extend([self.t(comma), LINE, element])
        if entry["role"] == "{":
            separated.append(if_break(",", ""))
            trailing = entry["trailing"]
            if trailing is not None and trailing["trailing"]:
                separated.append(suffix(
                    " ".join(comment["text"] for comment in trailing["trailing"])
                ))
        return group(concat([
            self.list_force_marker(entry),
            self.t(left),
            nest(self.indent_width, concat(separated)),
            SOFTLINE, self.t(right),
        ]))

    def block(self, entry):
        """Blocks are always on multiple lines when nonempty."""
        opening, closing = entry["left"], entry["right"]
        statements = entry["statements"]
        own, inline = self.splitting_comments(closing)
        if not statements and not own:
            return concat([self.t(opening), self.t(closing, inline)])
        body = []
        for index, statement in enumerate(statements):
            if index:
                body.append(self.sep(self.pre_blank(statement["first"])))
            else:
                body.append(HARDLINE)
            body.append(self.statement(statement))
        body.append(self.closing_comments(own, bool(statements)))
        return concat([
            self.t(opening), nest(self.indent_width, concat(body)),
            HARDLINE, self.t(closing, inline),
        ])

    def body(self, entry):
        """Obey the K&R/Allman brace position and optional inserted braces."""
        if entry["tag"] == "block":
            return concat([
                " " if self.kr else HARDLINE, self.block(entry),
            ])
        if self.profile["add_braces"]:
            return concat([
                " " if self.kr else HARDLINE, "{",
                nest(self.indent_width, concat([HARDLINE, self.statement(entry)])),
                HARDLINE, "}",
            ])
        return nest(self.indent_width, concat([HARDLINE, self.statement(entry)]))

    def simple(self, item):
        if item["tag"] == "assign":
            return concat([
                self.expr(item["left"], 0), self.separator,
                self.t(item["op"]), self.separator,
                self.expr(item["right"], 0),
            ])
        return self.expr(item["expr"], 0)

    def if_statement(self, entry):
        parts = [
            self.t(entry["keyword"]), self.keyword_gap,
            self.t(entry["left"]), self.expr(entry["test"], 0),
            self.t(entry["right"]), self.body(entry["body"]),
        ]
        if entry["else_token"] is not None:
            before = entry["body"]
            separator = (
                " " if self.kr and (
                    before["tag"] == "block" or self.profile["add_braces"]
                ) else HARDLINE
            )
            parts.extend([separator, self.t(entry["else_token"])])
            alternative = entry["alternative"]
            if alternative["tag"] == "if":
                parts.extend([" ", self.if_statement(alternative)])
            else:
                parts.append(self.body(alternative))
        return concat(parts)

    def while_statement(self, entry):
        return concat([
            self.t(entry["keyword"]), self.keyword_gap,
            self.t(entry["left"]), self.expr(entry["test"], 0),
            self.t(entry["right"]), self.body(entry["body"]),
        ])

    def for_statement(self, entry):
        contents = []
        initial = entry["initial"]
        if initial is not None:
            contents.append(
                self.variable(initial) if initial["tag"] == "variable"
                else self.simple(initial)
            )
        contents.append(self.t(entry["first_semi"]))
        if entry["condition"] is not None:
            contents.extend([LINE, self.expr(entry["condition"], 0)])
        contents.append(self.t(entry["second_semi"]))
        if entry["update"] is not None:
            contents.extend([LINE, self.simple(entry["update"])])
        loop = group(align(concat(contents)))
        return concat([
            self.t(entry["keyword"]), self.keyword_gap,
            self.t(entry["left"]), loop, self.t(entry["right"]),
            self.body(entry["body"]),
        ])

    def clause(self, item):
        contents = [self.t(item["label"])]
        if item["value"] is not None:
            contents.extend([" ", self.expr(item["value"], 0)])
        contents.append(self.t(item["colon"]))
        statements = item["statements"]
        if statements:
            inner = [HARDLINE, self.statement(statements[0])]
            for statement in statements[1:]:
                inner.extend([
                    self.sep(self.pre_blank(statement["first"])),
                    self.statement(statement),
                ])
            contents.append(nest(self.indent_width, concat(inner)))
        return concat(contents)

    def switch_statement(self, entry):
        closing = entry["closing"]
        clauses = entry["clauses"]
        own, inline = self.splitting_comments(closing)
        header = [
            self.t(entry["keyword"]), self.keyword_gap,
            self.t(entry["left"]), self.expr(entry["test"], 0),
            self.t(entry["right"]), " " if self.kr else HARDLINE,
            self.t(entry["opening"]),
        ]
        if not clauses and not own:
            return concat([header, self.t(closing, inline)])
        inner = []
        for index, clause in enumerate(clauses):
            inner.append(
                self.sep(self.pre_blank(clause["first"])) if index else HARDLINE
            )
            inner.append(self.clause(clause))
        inner.append(self.closing_comments(own, bool(clauses)))
        extra = self.indent_width if self.profile["indent_case_labels"] else 0
        return concat([
            header, nest(extra, concat(inner)),
            HARDLINE, self.t(closing, inline),
        ])

    def statement(self, item):
        tag = item["tag"]
        if tag == "block":
            return self.block(item)
        if tag == "variable":
            return self.variable(item)
        if tag == "simple_stmt":
            return concat([self.simple(item["value"]), self.t(item["semi"])])
        if tag == "return":
            contents = [self.t(item["keyword"])]
            if item["expr"] is not None:
                contents.extend([" ", self.expr(item["expr"], 0)])
            return concat([contents, self.t(item["semi"])])
        if tag == "flow":
            return concat([self.t(item["keyword"]), self.t(item["semi"])])
        if tag == "if":
            return self.if_statement(item)
        if tag == "while":
            return self.while_statement(item)
        if tag == "for":
            return self.for_statement(item)
        if tag == "switch":
            return self.switch_statement(item)
        raise ValueError(f"unexpected statement: {tag}")

    def opened(self, entry, minimum):
        """Remove redundant parentheses, transferring both trailing suffixes."""
        while self.profile["remove_parens"] and entry["tag"] == "paren":
            inner = entry["inner"]
            if self.level(inner) < minimum:
                break
            left, right = entry["left"], entry["right"]
            if left["leading"] or right["leading"]:
                break
            inner_first = self.first_token(inner)
            inner_last = self.last_token(inner)
            if left["trailing"]:
                inner_first["trailing"][:0] = left["trailing"]
                left["trailing"] = []
            if right["trailing"]:
                inner_last["trailing"].extend(right["trailing"])
                right["trailing"] = []
            entry = inner
        return entry

    def level(self, entry):
        return entry.get("level", 8)

    def first_token(self, entry):
        return entry["first"]

    def last_token(self, entry):
        tag = entry["tag"]
        if tag == "primary":
            return entry["value"]
        if tag == "paren":
            return entry["right"]
        if tag == "unary":
            return self.last_token(entry["operand"])
        if tag == "binary":
            return self.last_token(entry["right"])
        if tag == "conditional":
            return self.last_token(entry["no"])
        if tag == "call":
            return entry["arguments"]["right"]
        if tag == "index":
            return entry["right"]
        if tag == "member":
            return entry["member"]
        raise ValueError(tag)

    def binary(self, entry):
        """Flatten the left spine at fixed precedence without flattening RHS."""
        precedence = entry["level"]
        operators = []
        operands = []
        current = entry
        while current["tag"] == "binary" and current["level"] == precedence:
            operators.append(current["op"])
            operands.append(current["right"])
            current = self.opened(current["left"], precedence)
        operators.reverse()
        operands.reverse()
        contents = []
        for op, operand in zip(operators, operands):
            contents.extend([
                self.operator_break, self.t(op),
                self.separator, self.expr(operand, precedence + 1),
            ])
        return group(concat([
            self.expr(current, precedence),
            nest(self.indent_width, concat(contents)),
        ]))

    def conditional(self, entry):
        contents = []
        current = entry
        while True:
            contents.extend([
                self.operator_break, self.t(current["question"]),
                self.separator, self.expr(current["yes"], 0),
                self.operator_break, self.t(current["colon"]),
                self.separator,
            ])
            following = self.opened(current["no"], 0)
            if following["tag"] != "conditional":
                contents.append(self.expr(following, 0))
                break
            contents.append(self.expr(following["test"], 1))
            current = following
        return group(concat([
            self.expr(entry["test"], 1),
            nest(self.indent_width, concat(contents)),
        ]))

    def postfix_piece(self, entry):
        tag = entry["tag"]
        if tag == "call":
            return self.list_doc(entry["arguments"])
        if tag == "index":
            return concat([
                self.t(entry["left"]), self.expr(entry["index"], 0),
                self.t(entry["right"]),
            ])
        if tag == "member":
            return concat([self.t(entry["dot"]), self.t(entry["member"])])
        raise ValueError(tag)

    def postfix(self, entry):
        """Split at member-access boundaries and break only long method chains."""
        operators = []
        current = entry
        while current["tag"] in ("call", "index", "member"):
            operators.append(current)
            current = self.opened(current["target"], 8)
        operators.reverse()
        segments = [[]]
        for operation in operators:
            if operation["tag"] == "member":
                segments.append([])
            segments[-1].append(operation)
        segments_with_call = [
            index for index, segment in enumerate(segments)
            if index > 0 and any(part["tag"] == "call" for part in segment)
        ]
        head = self.expr(current, 8)
        if len(segments_with_call) < 2:
            return concat([
                head, *[self.postfix_piece(op) for op in operators],
            ])
        split_at = segments_with_call[0]
        preceding = [
            self.postfix_piece(op)
            for segment in segments[:split_at] for op in segment
        ]
        following = []
        for segment in segments[split_at:]:
            following.append(SOFTLINE)
            following.extend(self.postfix_piece(op) for op in segment)
        return group(concat([
            head, *preceding, nest(self.indent_width, concat(following)),
        ]))

    def expr(self, entry, minimum):
        entry = self.opened(entry, minimum)
        tag = entry["tag"]
        if tag == "primary":
            return self.t(entry["value"])
        if tag == "paren":
            return concat([
                self.t(entry["left"]), self.expr(entry["inner"], 0),
                self.t(entry["right"]),
            ])
        if tag == "unary":
            return concat([
                self.t(entry["op"]), self.expr(entry["operand"], 8),
            ])
        if tag == "binary":
            return self.binary(entry)
        if tag == "conditional":
            return self.conditional(entry)
        if tag in ("call", "index", "member"):
            return self.postfix(entry)
        raise ValueError(f"unexpected expression: {tag}")


def render_once(lines, profile):
    """Parse all code first, then verify comments, build docs and lay them out."""
    tokens, comments, items = lexical_analysis(lines)
    attach_comments(tokens, comments, items)
    syntax = Parser(tokens).parse()
    check_comment_positions(tokens)
    builder = DocumentFormatter(profile, tokens)
    first_function = next((item for item in syntax if item["tag"] == "function"), None)
    if not syntax and not tokens[-1]["leading"]:
        return {
            "lines": [], "comments": comments, "document": None,
            "first_function": None,
        }
    document = builder.whole_file(syntax, tokens[-1])
    formatted = layout(document, profile)
    # The tree of the first function is built once with this formatter. A
    # separate source pass will build its own independent tree later.
    return {
        "lines": formatted,
        "comments": comments,
        "document": document,
        "first_function": first_function,
        "builder": builder,
    }


def first_differing_line(a, b):
    for i, (left, right) in enumerate(zip(a, b), 1):
        if left != right:
            return i
    return min(len(a), len(b)) + 1


def format_source(file, profiles):
    """Format a file twice and keep the diagnostic data for all five outputs."""
    profile = profiles[file["profile"]]
    original = [line.rstrip(" ") for line in file["lines"]]
    result = {**file, "original": original, "error": None}
    try:
        first = render_once(file["lines"], profile)
    except SourceError as error:
        result.update({
            "formatted": original, "error": error,
            "idempotency": f"{file['filename']}: skipped (syntax error)",
            "diagnostics": [
                f"{file['filename']}:{error.line}:{error.column}: "
                f"error: {error.message}"
            ],
        })
        return result

    result["first"] = first
    result["formatted"] = first["lines"]
    try:
        second = render_once(first["lines"], profile)
    except SourceError as error:
        result["idempotency"] = (
            f"{file['filename']}: unstable (second pass: "
            f"{error.line}:{error.column}: {error.message})"
        )
    else:
        if first["lines"] == second["lines"]:
            result["idempotency"] = f"{file['filename']}: stable"
        else:
            difference = first_differing_line(first["lines"], second["lines"])
            result["idempotency"] = (
                f"{file['filename']}: unstable at line {difference}"
            )
    diagnostics = []
    for lineno, line in enumerate(first["lines"], 1):
        if len(line) > profile["width"]:
            diagnostics.append(
                f"{file['filename']}:{lineno}: warning: line too long "
                f"({len(line)} > {profile['width']})"
            )
    result["diagnostics"] = diagnostics
    return result


def output_formatted(results):
    lines = []
    for item in results:
        lines.append(item["header"])
        lines.extend(item["formatted"])
    return lines


def output_idempotency(results):
    return [item["idempotency"] for item in results]


def output_diagnostics(results):
    rows = []
    for item in results:
        rows.extend(item["diagnostics"])
    return rows if rows else ["no diagnostics"]


def output_tree(results):
    lines = []
    for item in results:
        lines.append(f"=== {item['filename']}")
        if item["error"] is not None:
            lines.append("syntax error")
            continue
        first = item["first"]
        formatted = first["lines"]
        document = first["document"]
        groups = list(all_groups(document)) if document else []
        lines.append(
            f"metrics lines={len(formatted)} "
            f"longest={max(map(len, formatted), default=0)} "
            f"comments={len(first['comments'])} "
            f"groups={len(groups)} "
            f"broken={sum(g['mode'] in ('break', 'forced') for g in groups)} "
            f"forced={sum(g['mode'] == 'forced' for g in groups)}"
        )
        if first["first_function"] is None:
            lines.append("no function")
        else:
            function = first["first_function"]
            lines.append(f"function {function['name']['text']}")
            function_doc = first["builder"].item(function)
            # Record the layout mode on groups of this document, using the
            # same starting layout state as the entire formatting pass.
            layout(function_doc, read_profile(item))
            lines.extend(doc_tree(function_doc))
    return lines


def read_profile(file):
    """Use the current task's profile table stored at the entry."""
    return file["profile_values"]


def output_changes(results):
    lines = []
    for item in results:
        lines.append(f"=== {item['filename']}")
        if item["error"] is not None:
            lines.append("skipped (syntax error)")
        else:
            lines.extend(diff_lines(item["original"], item["formatted"]))
    return lines


def main():
    profiles = read_profiles()
    sources = read_sources()
    results = []
    for file in sources:
        file["profile_values"] = profiles[file["profile"]]
        results.append(format_source(file, profiles))
    write_lines("formatted.txt", output_formatted(results))
    write_lines("idempotency.txt", output_idempotency(results))
    write_lines("diagnostics.txt", output_diagnostics(results))
    write_lines("doc_tree.txt", output_tree(results))
    write_lines("changes.txt", output_changes(results))


if __name__ == "__main__":
    main()
