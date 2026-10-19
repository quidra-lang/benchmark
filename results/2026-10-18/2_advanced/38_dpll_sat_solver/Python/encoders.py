"""Fixed variable-numbering SAT encodings and symmetry canonicalizations."""


def queens(n):
    variables = n * n
    clauses = [
        [(r - 1) * n + c for c in range(1, n + 1)]
        for r in range(1, n + 1)
    ]
    for a in range(1, variables + 1):
        row_a, col_a = divmod(a - 1, n)
        for b in range(a + 1, variables + 1):
            row_b, col_b = divmod(b - 1, n)
            if (row_a == row_b or col_a == col_b
                    or abs(row_a - row_b) == abs(col_a - col_b)):
                clauses.append([-a, -b])
    return variables, clauses


def pigeon(pigeons, holes):
    clauses = [
        [(p - 1) * holes + h for h in range(1, holes + 1)]
        for p in range(1, pigeons + 1)
    ]
    for p in range(1, pigeons + 1):
        for first in range(1, holes + 1):
            for second in range(first + 1, holes + 1):
                clauses.append([-((p - 1) * holes + first),
                                -((p - 1) * holes + second)])
    for hole in range(1, holes + 1):
        for first in range(1, pigeons + 1):
            for second in range(first + 1, pigeons + 1):
                clauses.append([-((first - 1) * holes + hole),
                                -((second - 1) * holes + hole)])
    return pigeons * holes, clauses


def coloring(graph, colors):
    vertices = graph["vertices"]
    clauses = [
        [(v - 1) * colors + c for c in range(1, colors + 1)]
        for v in range(1, vertices + 1)
    ]
    for v in range(1, vertices + 1):
        for first in range(1, colors + 1):
            for second in range(first + 1, colors + 1):
                clauses.append([-((v - 1) * colors + first),
                                -((v - 1) * colors + second)])
    for a, b in graph["edges"]:
        for color in range(1, colors + 1):
            clauses.append([-((a - 1) * colors + color),
                            -((b - 1) * colors + color)])
    return vertices * colors, clauses


def positions(model, rows, width):
    return [
        next(col for col in range(1, width + 1)
             if model[(row - 1) * width + col])
        for row in range(1, rows + 1)
    ]


def queens_symmetries(cols):
    n = len(cols)
    variants = (
        lambda r, c: (r, c),
        lambda r, c: (c, n + 1 - r),
        lambda r, c: (n + 1 - r, n + 1 - c),
        lambda r, c: (n + 1 - c, r),
        lambda r, c: (r, n + 1 - c),
        lambda r, c: (n + 1 - r, c),
        lambda r, c: (c, r),
        lambda r, c: (n + 1 - c, n + 1 - r),
    )
    result = []
    for transform in variants:
        current = [0] * n
        for row, col in enumerate(cols, 1):
            r, c = transform(row, col)
            current[r - 1] = c
        result.append(tuple(current))
    return result


def canonical_coloring(colors):
    numbers = {}
    output = []
    for color in colors:
        numbers.setdefault(color, len(numbers) + 1)
        output.append(numbers[color])
    return tuple(output)
