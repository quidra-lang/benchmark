"""Document tree serialization and deterministic line-level LCS diff."""

from pathlib import Path


def doc_tree(document, depth=0):
    """Print node descriptions with two spaces per nesting level."""
    kind = document["kind"]
    prefix = "  " * depth
    if kind == "concat":
        result = []
        for child in document["items"]:
            result.extend(doc_tree(child, depth))
        return result
    if kind == "text":
        return [prefix + 'text "' + document["value"] + '"']
    if kind == "suffix":
        return [prefix + 'suffix "' + document["value"] + '"']
    if kind == "if_break":
        return [
            prefix + 'if_break "' + document["broken"]
            + '" "' + document["flat"] + '"'
        ]
    if kind == "group":
        return [prefix + f"group {document['mode']}"] + doc_tree(
            document["child"], depth + 1
        )
    if kind == "nest":
        return [prefix + f"nest {document['amount']}"] + doc_tree(
            document["child"], depth + 1
        )
    if kind == "align":
        return [prefix + "align"] + doc_tree(document["child"], depth + 1)
    return [prefix + kind]


def diff_lines(original, formatted):
    """Calculate suffix LCS, preferring deletion on a tie."""
    n, m = len(original), len(formatted)
    table = [[0] * (m + 1) for _ in range(n + 1)]
    for i in range(n - 1, -1, -1):
        for j in range(m - 1, -1, -1):
            if original[i] == formatted[j]:
                table[i][j] = table[i + 1][j + 1] + 1
            else:
                table[i][j] = max(table[i + 1][j], table[i][j + 1])
    i = j = 0
    hunks = []
    current = None
    deleted = inserted = 0
    while i < n or j < m:
        if i < n and j < m and original[i] == formatted[j]:
            if current is not None:
                hunks.append(current)
                current = None
            i += 1
            j += 1
            continue
        if current is None:
            current = {"start_old": i, "start_new": j,
                       "deletes": 0, "inserts": 0, "lines": []}
        if j == m or (i < n and table[i + 1][j] >= table[i][j + 1]):
            current["deletes"] += 1
            deleted += 1
            current["lines"].append("-" + original[i])
            i += 1
        else:
            current["inserts"] += 1
            inserted += 1
            current["lines"].append("+" + formatted[j])
            j += 1
    if current is not None:
        hunks.append(current)

    result = [f"hunks={len(hunks)} deleted={deleted} inserted={inserted}"]
    for hunk in hunks:
        count_old = hunk["deletes"]
        count_new = hunk["inserts"]
        start_old = hunk["start_old"] + (1 if count_old else 0)
        start_new = hunk["start_new"] + (1 if count_new else 0)
        result.append(
            f"@@ -{start_old},{count_old} +{start_new},{count_new} @@"
        )
        result.extend(hunk["lines"])
    return result


def write_lines(filename, lines):
    target = Path("output") / filename
    target.parent.mkdir(parents=True, exist_ok=True)
    target.write_text("\n".join(lines) + "\n" if lines else "", encoding="ascii")
