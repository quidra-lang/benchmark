"""Canonical child order, Newick, cladograms, and ASCII output."""

from pathlib import Path


def real(value, places):
    rendered = f"{value:.{places}f}"
    if rendered == "-0." + "0" * places:
        return rendered[1:]
    return rendered


def symbols(mask, count):
    return "".join("*" if mask & (1 << taxon) else "." for taxon in range(count))


def child_order(rooted, names):
    minimum = {}
    children = {}
    for node in reversed(rooted.order):
        if node < rooted.tree.size:
            minimum[node] = names[node]
            children[node] = []
        else:
            children[node] = sorted(rooted.children[node], key=minimum.__getitem__)
            minimum[node] = minimum[children[node][0]]
    return children


def newick(tree, names, outgroup, lengths=False, support=None):
    rooted = tree.rooted(outgroup)
    children = child_order(rooted, names)

    def node_text(node):
        if node < tree.size:
            text = names[node]
        else:
            text = "(" + ",".join(node_text(child) for child in children[node]) + ")"
            if support is not None and node != rooted.root:
                text += str(support.get(rooted.masks[node], 0))
        if lengths and node != rooted.root:
            text += ":" + real(tree.adjacent[node][rooted.parents[node]], 5)
        return text

    return node_text(rooted.root) + ";"


def cladogram(tree, names, outgroup, support):
    rooted = tree.rooted(outgroup)
    children = child_order(rooted, names)
    lines = ["*"]

    def descend(node, prefix):
        for index, child in enumerate(children[node]):
            last = index == len(children[node]) - 1
            connector = "`-- " if last else "|-- "
            label = names[child] if child < tree.size else f"[{support.get(rooted.masks[child], 0)}]"
            lines.append(prefix + connector + label)
            descend(child, prefix + ("    " if last else "|   "))

    descend(rooted.root, "")
    return lines


def write_lines(filename, lines):
    directory = Path("output")
    directory.mkdir(exist_ok=True)
    with (directory / filename).open("w", encoding="ascii", newline="\n") as destination:
        destination.write("\n".join(lines) + "\n")
