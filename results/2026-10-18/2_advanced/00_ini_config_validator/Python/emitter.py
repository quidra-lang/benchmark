import os


MASK = "********"
ESCAPED = {"\\": "\\\\", '"': '\\"', "\n": "\\n", "\t": "\\t"}


def string_notation(text):
    return '"' + "".join(ESCAPED.get(char, char) for char in text) + '"'


def value_notation(kind, item_kind, value):
    if kind == "list":
        return "[" + ", ".join(value_notation(item_kind, None, item) for item in value) + "]"
    if kind == "string":
        return string_notation(value)
    if kind == "bool":
        return "true" if value else "false"
    return str(value)


def shown(output):
    return MASK if output.secret else output.notation


def origin_text(origin):
    document, line = origin
    return f"{document}:{line}"


def normalized_block(profile):
    lines = ["profile " + profile.name]
    sections = {}
    for key, output in profile.outputs.items():
        section, _, name = key.rpartition(".")
        sections.setdefault(section, {})[name] = output
    for section in sorted(sections):
        lines.append(f"[{section}]")
        keys = sections[section]
        for name in sorted(keys):
            lines.append(f"{name} = {shown(keys[name])}")
    return lines


def diagnostics_block(profile):
    lines = [f"profile {profile.name} errors {profile.errors} warnings {profile.warnings}"]
    for document, line, code, message in profile.diagnostics:
        lines.append(f"{document}:{line} {code} {message}")
    return lines


def diff_block(diff):
    lines = [
        f"diff {diff.first} -> {diff.second}: {diff.added} added, "
        f"{diff.removed} removed, {diff.changed} changed"
    ]
    for sign, key, before, after in diff.entries:
        if sign == "+":
            lines.append(f"+ {key} = {shown(after)}")
        elif sign == "-":
            lines.append(f"- {key} = {shown(before)}")
        else:
            lines.append(f"~ {key}: {shown(before)} -> {shown(after)}")
    return lines


def report_block(profile):
    lines = ["profile " + profile.name, "includes"]
    for depth, text in profile.tree:
        lines.append("  " + "  " * depth + text)
    lines.append("overridden")
    for key, history in profile.overridden:
        lines.append(f"  {key}: " + " -> ".join(origin_text(origin) for origin in history))
    if not profile.overridden:
        lines.append("  (none)")
    lines.append(
        f"keys {len(profile.outputs)} documents {profile.document_keys} "
        f"manifest {profile.manifest_keys} defaults {profile.default_keys}"
    )
    lines.append(f"dropped {profile.dropped}")
    lines.append(f"errors {profile.errors} warnings {profile.warnings}")
    return lines


def write_file(path, blocks):
    with open(path, "w") as handle:
        handle.write("\n\n".join("\n".join(block) for block in blocks) + "\n")


def write_outputs(directory, profiles, diffs):
    os.makedirs(directory, exist_ok=True)
    write_file(os.path.join(directory, "normalized.txt"), [normalized_block(p) for p in profiles])
    write_file(os.path.join(directory, "diagnostics.txt"), [diagnostics_block(p) for p in profiles])
    write_file(os.path.join(directory, "diff.txt"), [diff_block(diff) for diff in diffs])
    write_file(os.path.join(directory, "report.txt"), [report_block(p) for p in profiles])
