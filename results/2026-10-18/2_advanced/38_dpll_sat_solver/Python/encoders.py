"""Deterministically numbered Queens, pigeonhole and coloring clauses."""


def queens(n):
    size = n * n
    clauses = [
        [(row - 1) * n + col for col in range(1, n + 1)]
        for row in range(1, n + 1)
    ]
    for a in range(1, size + 1):
        row_a, col_a = divmod(a - 1, n)
        for b in range(a + 1, size + 1):
            row_b, col_b = divmod(b - 1, n)
            if (row_a == row_b or col_a == col_b
                    or abs(row_a - row_b) == abs(col_a - col_b)):
                clauses.append([-a, -b])
    return size, clauses


def pigeon(pigeons, holes):
    clauses = [
        [(p - 1) * holes + h for h in range(1, holes + 1)]
        for p in range(1, pigeons + 1)
    ]
    for pigeon in range(1, pigeons + 1):
        for first in range(1, holes + 1):
            for second in range(first + 1, holes + 1):
                clauses.append([
                    -((pigeon - 1) * holes + first),
                    -((pigeon - 1) * holes + second),
                ])
    for hole in range(1, holes + 1):
        for first in range(1, pigeons + 1):
            for second in range(first + 1, pigeons + 1):
                clauses.append([
                    -((first - 1) * holes + hole),
                    -((second - 1) * holes + hole),
                ])
    return pigeons * holes, clauses


def coloring(graph, colors):
    vertices = graph["vertices"]
    clauses = [
        [(vertex - 1) * colors + color
         for color in range(1, colors + 1)]
        for vertex in range(1, vertices + 1)
    ]
    for vertex in range(1, vertices + 1):
        for first in range(1, colors + 1):
            for second in range(first + 1, colors + 1):
                clauses.append([
                    -((vertex - 1) * colors + first),
                    -((vertex - 1) * colors + second),
                ])
    for first, second in graph["edges"]:
        for color in range(1, colors + 1):
            clauses.append([
                -((first - 1) * colors + color),
                -((second - 1) * colors + color),
            ])
    return vertices * colors, clauses


def decode_positions(model, rows, columns):
    return [
        next(col for col in range(1, columns + 1)
             if model[(row - 1) * columns + col])
        for row in range(1, rows + 1)
    ]


def queen_variants(columns):
    n = len(columns)
    transformations = (
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
    for transform in transformations:
        output = [0] * n
        for row, column in enumerate(columns, 1):
            new_row, new_col = transform(row, column)
            output[new_row - 1] = new_col
        result.append(tuple(output))
    return result


def canonical_coloring(columns):
    names = {}
    result = []
    for color in columns:
        if color not in names:
            names[color] = len(names) + 1
        result.append(names[color])
    return tuple(result)
