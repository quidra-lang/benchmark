import math


MARKS = " :-|+"
CUT_MARK = 1
LINE_MARK = 2
BAR_MARK = 3
JOIN_MARK = 4
SCALE_STEP = 10


def ordered_children(merges, count):
    minimum = list(range(count))
    children = []
    for merge in merges:
        if minimum[merge.a] < minimum[merge.b]:
            children.append((merge.a, merge.b))
        else:
            children.append((merge.b, merge.a))
        minimum.append(min(minimum[merge.a], minimum[merge.b]))
    return children


def leaf_order(children, count):
    order = []
    pending = [count + len(children) - 1]
    while pending:
        node = pending.pop()
        if node < count:
            order.append(node)
        else:
            upper, lower = children[node - count]
            pending.append(lower)
            pending.append(upper)
    return order


def column(height, height_max, width):
    return math.floor(height / height_max * width)


def mark(grid, row, x, level):
    if grid[row][x] < level:
        grid[row][x] = level


def dendrogram_rows(merges, children, order, idents, labels, height_max, cut_columns, width):
    count = len(order)
    grid = [[0] * (width + 1) for _ in range(count)]
    anchor = [0] * (2 * count - 1)
    for row, leaf in enumerate(order):
        anchor[leaf] = row
    for x in cut_columns:
        if x <= width:
            for row in range(count):
                mark(grid, row, x, CUT_MARK)
    columns = [column(merge.height, height_max, width) for merge in merges]
    for step, (upper, lower) in enumerate(children):
        x = columns[step]
        mark(grid, anchor[upper], x, JOIN_MARK)
        mark(grid, anchor[lower], x, JOIN_MARK)
        for row in range(anchor[upper] + 1, anchor[lower]):
            mark(grid, row, x, BAR_MARK)
        for child in (upper, lower):
            start = 0 if child < count else columns[child - count] + 1
            for position in range(start, x):
                mark(grid, anchor[child], position, LINE_MARK)
        anchor[count + step] = (anchor[upper] + anchor[lower]) // 2
    id_width = max(len(ident) for ident in idents)
    label_width = max(len(label) for label in labels)
    rows = []
    for row, leaf in enumerate(order):
        cells = "".join(MARKS[level] for level in grid[row])
        rows.append(f"{idents[leaf]:<{id_width}} {labels[leaf]:<{label_width}} {cells}".rstrip())
    scale = "".join("+" if x % SCALE_STEP == 0 else "-" for x in range(width + 1))
    rows.append(" " * (id_width + label_width + 2) + scale)
    return rows
