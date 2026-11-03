"""Stack-based group layout, first-line lookahead and trailing suffixes."""


def fits(remaining, candidate, rest):
    """Walk a flattened first line, including the continuation after a group."""
    if remaining < 0:
        return False
    check = [candidate]
    next_existing = len(rest) - 1
    while True:
        if not check:
            if next_existing < 0:
                return True
            check.append(rest[next_existing])
            next_existing -= 1
        indent, mode, doc = check.pop()
        kind = doc["kind"]
        if kind == "text":
            remaining -= len(doc["value"])
        elif kind == "if_break":
            remaining -= len(doc["broken"] if mode == "break" else doc["flat"])
        elif kind == "line":
            if mode == "break":
                return True
            remaining -= 1
        elif kind == "softline":
            if mode == "break":
                return True
        elif kind == "hardline":
            return True
        elif kind == "concat":
            check.extend(
                (indent, mode, child) for child in reversed(doc["items"])
            )
        elif kind == "group":
            child_mode = "break" if doc["forced"] else mode
            check.append((indent, child_mode, doc["child"]))
        elif kind in ("nest", "align"):
            check.append((indent, mode, doc["child"]))
        if remaining < 0:
            return False


def layout(document, profile):
    """Render one complete document and record each encountered group's mode."""
    width = profile["width"]
    column = profile["comment_column"]
    result = []
    current = ""
    pending = []
    stack = [(0, "break", document)]

    def finalize():
        nonlocal current
        output = current.rstrip(" ")
        if pending:
            comment_text = " ".join(pending)
            if (column > 0 and len(output) < column - 1
                    and column - 1 + len(comment_text) <= width):
                output += " " * (column - 1 - len(output)) + comment_text
            else:
                output += " " + comment_text
            pending.clear()
        result.append(output)

    while stack:
        indentation, mode, doc = stack.pop()
        kind = doc["kind"]
        if kind == "text":
            current += doc["value"]
        elif kind == "if_break":
            current += doc["broken"] if mode == "break" else doc["flat"]
        elif kind == "line":
            if mode == "flat":
                current += " "
            else:
                finalize()
                current = " " * indentation
        elif kind == "softline":
            if mode == "break":
                finalize()
                current = " " * indentation
        elif kind == "hardline":
            finalize()
            current = " " * indentation
        elif kind == "concat":
            stack.extend(
                (indentation, mode, child)
                for child in reversed(doc["items"])
            )
        elif kind == "nest":
            stack.append((indentation + doc["amount"], mode, doc["child"]))
        elif kind == "align":
            stack.append((len(current), mode, doc["child"]))
        elif kind == "suffix":
            pending.append(doc["value"])
        elif kind == "break_parent":
            pass
        elif kind == "group":
            if mode == "flat":
                next_mode = "flat"
            elif doc["forced"]:
                next_mode = "forced"
            elif fits(width - len(current), (indentation, "flat", doc["child"]), stack):
                next_mode = "flat"
            else:
                next_mode = "break"
            doc["mode"] = next_mode
            stack.append(
                (indentation, "flat" if next_mode == "flat" else "break",
                 doc["child"])
            )
        else:
            raise ValueError(f"unknown document kind: {kind}")
    finalize()
    return result
