"""Read dot directives and assemble blocks without expanding their text."""

import re


BODY_KINDS = {"paragraph", "item", "enum", "quote", "term"}
SETTING_NAMES = {"width", "indent", "align"}
PREAMBLE_NAMES = {"page", "header", "footer"}
BLOCK_NAMES = {
    "title", "author", "h1", "h2", "item", "enum", "quote", "term",
    "table", "verbatim", "toc", "lot", "index", "bibliography",
}
DIRECTIVE_NAMES = SETTING_NAMES | PREAMBLE_NAMES | BLOCK_NAMES | {
    "newpage", "hyphenation", "bib",
}
EMPTY_ARGUMENT_NAMES = {
    "newpage", "verbatim", "toc", "lot", "index", "bibliography",
}
DICTIONARY_WORD = re.compile(r"[a-z]+(?:-[a-z]+)*")


def valid_argument(name, argument):
    if name in {"width", "indent", "page"}:
        if re.fullmatch(r"[0-9]{1,9}", argument) is None:
            return False
        lower, upper = {"width": (20, 80), "indent": (0, 8),
                        "page": (10, 100)}[name]
        return lower <= int(argument) <= upper
    if name == "align":
        return argument in {"left", "right", "center", "justify"}
    if name in {"header", "footer"}:
        return argument.count("|") == 2
    if name in EMPTY_ARGUMENT_NAMES:
        return argument == ""
    if name == "hyphenation":
        return bool(argument) and all(
            DICTIONARY_WORD.fullmatch(word)
            for word in argument.split(" ")
        )
    if name == "bib":
        key, separator, fields = argument.partition(" ")
        if not separator or re.fullmatch(r"[a-z0-9]+", key) is None:
            return False
        parts = fields.split("|")
        return (len(parts) == 3 and bool(parts[0]) and bool(parts[2])
                and re.fullmatch(r"[0-9]{4}", parts[1]) is not None)
    if name == "term":
        term, separator, description = argument.partition("|")
        return bool(separator and term and description)
    if name == "table":
        columns = argument.partition(" ")[0]
        return re.fullmatch(r"[lrc]+", columns) is not None
    return bool(argument)


def parse_document(lines):
    document = {
        "blocks": [],
        "warnings": [],
        "height": 40,
        "page_width": 60,
        "header": ("", "", ""),
        "footer": ("", "", ""),
        "hyphenation_words": [],
        "bibliography": [],
    }
    settings = {"width": 60, "indent": 0, "align": "left"}
    accepted_preamble = set()
    open_body = None
    inner_block = None
    pending_page_break = False

    def create_block(kind, line_number, argument=""):
        nonlocal pending_page_break
        if not document["blocks"]:
            document["page_width"] = settings["width"]
        block = {
            "kind": kind,
            "line_number": line_number,
            "argument": argument,
            "page_break": pending_page_break,
            **settings,
        }
        pending_page_break = False
        document["blocks"].append(block)
        if kind in BODY_KINDS:
            block["body_lines"] = []
        if kind in {"table", "verbatim"}:
            block["inner_lines"] = []
        return block

    for line_number, line in enumerate(lines, 1):
        if inner_block is not None:
            if line == ".end":
                inner_block = None
            else:
                inner_block["inner_lines"].append((line_number, line))
            continue
        if not line:
            open_body = None
            continue
        if not line.startswith("."):
            if open_body is None:
                open_body = create_block("paragraph", line_number)
            open_body["body_lines"].append((line_number, line))
            continue

        open_body = None
        name, _, argument = line[1:].partition(" ")
        warning = None
        if name not in DIRECTIVE_NAMES:
            warning = f"unknown directive .{name}"
        elif not valid_argument(name, argument):
            warning = f"bad argument for .{name}"
        elif name in PREAMBLE_NAMES and document["blocks"]:
            warning = f".{name} ignored after the preamble"
        elif name in PREAMBLE_NAMES and name in accepted_preamble:
            warning = f"duplicate .{name}"
        if warning is not None:
            document["warnings"].append((line_number, warning))
            continue

        if name in SETTING_NAMES:
            settings[name] = argument if name == "align" else int(argument)
        elif name in PREAMBLE_NAMES:
            accepted_preamble.add(name)
            if name == "page":
                document["height"] = int(argument)
            else:
                document[name] = tuple(argument.split("|"))
        elif name == "newpage":
            pending_page_break = True
        elif name == "hyphenation":
            document["hyphenation_words"].extend(argument.split(" "))
        elif name == "bib":
            key, _, fields = argument.partition(" ")
            author, year, title = fields.split("|")
            document["bibliography"].append({
                "line_number": line_number, "key": key, "author": author,
                "year": year, "title": title,
            })
        else:
            block = create_block(name, line_number, argument)
            if name in {"item", "enum", "quote"}:
                block["body_lines"].append((line_number, argument))
                open_body = block
            elif name == "term":
                term, _, description = argument.partition("|")
                block["term"] = term
                block["body_lines"].append((line_number, description))
                open_body = block
            elif name == "table":
                columns, _, caption = argument.partition(" ")
                block["columns"] = columns
                block["caption"] = caption
                inner_block = block
            elif name == "verbatim":
                inner_block = block

    if inner_block is not None:
        document["warnings"].append((
            inner_block["line_number"], f"unterminated {inner_block['kind']}"
        ))
    return document
