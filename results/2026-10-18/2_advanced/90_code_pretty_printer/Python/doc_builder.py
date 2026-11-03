"""Immutable-ish normalized Wadler documents and group structure utilities."""


def text(value):
    return {"kind": "text", "value":str(value)}


def symbol(kind):
    return {"kind": kind}


LINE = symbol("line")
SOFTLINE = symbol("softline")
HARDLINE = symbol("hardline")
BREAK_PARENT = symbol("break_parent")


def suffix(value):
    return {"kind": "suffix", "value": value}


def if_break(broken, flat):
    return {"kind": "if_break", "broken": broken, "flat": flat}


def concat(*parts):
    """Flatten child concatenations and merge adjacent text while retaining order."""
    elements = []

    def add(part):
        if part is None:
            return
        if isinstance(part, str):
            part = text(part)
        if isinstance(part, (list, tuple)):
            for child in part:
                add(child)
            return
        if part["kind"] == "concat":
            for child in part["items"]:
                add(child)
        elif part["kind"] == "text":
            value = part["value"]
            if not value:
                return
            if elements and elements[-1]["kind"] == "text":
                elements[-1] = text(elements[-1]["value"] + value)
            else:
                elements.append(text(value))
        else:
            elements.append(part)

    for part in parts:
        add(part)
    if not elements:
        return text("")
    if len(elements) == 1:
        return elements[0]
    return {"kind": "concat", "items": elements}


def force_broken(document):
    kind = document["kind"]
    if kind in ("hardline", "break_parent"):
        return True
    if kind == "concat":
        return any(force_broken(child) for child in document["items"])
    if kind in ("group", "nest", "align"):
        return force_broken(document["child"])
    return False


def group(child):
    normalized = concat(child)
    return {
        "kind": "group", "child": normalized,
        "forced": force_broken(normalized), "mode": None,
    }


def nest(amount, child):
    return {"kind": "nest", "amount": amount, "child": concat(child)}


def align(child):
    return {"kind": "align", "child": concat(child)}


def all_groups(document):
    if document["kind"] == "group":
        yield document
        yield from all_groups(document["child"])
    elif document["kind"] in ("nest", "align"):
        yield from all_groups(document["child"])
    elif document["kind"] == "concat":
        for child in document["items"]:
            yield from all_groups(child)
