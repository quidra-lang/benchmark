"""Lex the specified small C-like language with exact source positions."""

KEYWORDS = set(
    "int float bool string void if else while for return break continue "
    "true false switch case default".split()
)
TYPES = {"int", "float", "bool", "string", "void"}
DOUBLE = {"<=", ">=", "==", "!=", "&&", "||", "+=", "-=", "*=", "/=", "%="}
SINGLE = set("+-*/%<>=!()[]{},;.?:")
ASSIGNMENT = {"=", "+=", "-=", "*=", "/=", "%="}


class SourceError(Exception):
    def __init__(self, line, column, message):
        self.line = line
        self.column = column
        self.message = message
        super().__init__(f"{line}:{column}: {message}")


def token(kind, text, line, column, blank, index):
    return {
        "kind": kind, "text": text, "line": line, "column": column,
        "blank": blank, "index": index, "leading": [],
        "trailing": [], "allowed": False, "trailing_comma": False,
    }


def lexical_analysis(lines):
    """Return tokens, comments and an end token, retaining blank-line counts."""
    tokens = []
    comments = []
    items = []
    previous_line = 0
    for line_no, line in enumerate(lines, 1):
        column = 0
        while column < len(line):
            ch = line[column]
            if ch == " ":
                column += 1
                continue
            start = column
            kind = ""
            if line.startswith("//", column):
                kind = "line_comment"
                column = len(line)
                text = line[start:].rstrip(" ")
            elif line.startswith("/*", column):
                end = line.find("*/", column + 2)
                if end < 0:
                    raise SourceError(line_no, column + 1, "unterminated comment")
                kind = "block_comment"
                column = end + 2
                text = line[start:column]
            elif ch.isascii() and (ch.isalpha() or ch == "_"):
                column += 1
                while column < len(line) and line[column].isascii() and (
                        line[column].isalnum() or line[column] == "_"):
                    column += 1
                text = line[start:column]
                kind = "keyword" if text in KEYWORDS else "identifier"
            elif "0" <= ch <= "9":
                column += 1
                while column < len(line) and line[column].isdigit():
                    column += 1
                if column + 1 < len(line) and line[column] == "." and (
                        "0" <= line[column + 1] <= "9"):
                    column += 2
                    while column < len(line) and "0" <= line[column] <= "9":
                        column += 1
                text = line[start:column]
                kind = "number"
            elif ch == '"':
                column += 1
                closed = False
                while column < len(line):
                    if line[column] == "\\":
                        column += 2
                    elif line[column] == '"':
                        column += 1
                        closed = True
                        break
                    else:
                        column += 1
                if not closed:
                    raise SourceError(line_no, start + 1, "unterminated string")
                text = line[start:column]
                kind = "string"
            elif line[column:column + 2] in DOUBLE:
                column += 2
                text = line[start:column]
                kind = "symbol"
            elif ch in SINGLE:
                column += 1
                text = ch
                kind = "symbol"
            else:
                raise SourceError(line_no, start + 1, f"unexpected character '{ch}'")

            entry = {
                "kind": kind, "text": text, "line": line_no,
                "column": start + 1, "blank": max(0, line_no - previous_line - 1),
            }
            previous_line = line_no
            items.append(entry)
            if kind.endswith("_comment"):
                comments.append(entry)
            else:
                tokens.append(entry)
    for index, entry in enumerate(tokens):
        entry.update({
            "index": index, "leading": [], "trailing": [],
            "allowed": False, "trailing_comma": False,
        })
    end = token("end", "", len(lines) + 1, 1, 0, len(tokens))
    end["allowed"] = True
    tokens.append(end)
    return tokens, comments, items


def attach_comments(tokens, comments, items):
    """Attach each comment to the immediately applicable token in source order."""
    token_order = [entry for entry in items if not entry["kind"].endswith("_comment")]
    position = {id(entry): index for index, entry in enumerate(items)}
    for comment in comments:
        i = position[id(comment)]
        before = next((entry for entry in reversed(items[:i])
                       if not entry["kind"].endswith("_comment")), None)
        after = next((entry for entry in items[i + 1:]
                      if not entry["kind"].endswith("_comment")), None)
        following = items[i + 1] if i + 1 < len(items) else None
        comment["own_line"] = (
            comment["kind"] == "line_comment" or following is None
            or following["line"] > comment["line"]
        )
        if (before is not None and before["line"] == comment["line"]
                and (after is None or after["line"] > comment["line"])):
            before["trailing"].append(comment)
        else:
            (after if after is not None else tokens[-1])["leading"].append(comment)
    return tokens


def first_comment_blank(entry):
    if entry["leading"]:
        return entry["leading"][0]["blank"]
    return entry["blank"]
