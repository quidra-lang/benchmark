from decimal import Decimal, ROUND_HALF_UP

systems = [
    [[2, -1, 3, 7], [4, 1, -2, 3], [-3, 5, 1, -4]],
    [[1, 3, -2, 4, 6], [5, -2, 1, 3, -7], [-2, 4, 6, -1, 9], [3, 1, -4, 2, 5]],
]
for number, system in enumerate(systems, 1):
    a = [list(map(float, row)) for row in system]
    n = len(a)
    for k in range(n):
        pivot = max(range(k, n), key=lambda row: abs(a[row][k]))
        a[k], a[pivot] = a[pivot], a[k]
        for i in range(k + 1, n):
            factor = a[i][k] / a[k][k]
            for j in range(k, n + 1):
                a[i][j] = a[i][j] - factor * a[k][j]
    solution = [0.0] * n
    for i in range(n - 1, -1, -1):
        s = a[i][n]
        for j in range(i + 1, n):
            s = s - a[i][j] * solution[j]
        solution[i] = s / a[i][i]
    print(f"system {number}:")
    for i, value in enumerate(solution, 1):
        rounded = Decimal.from_float(value).quantize(Decimal("0.0001"), rounding=ROUND_HALF_UP)
        print(f"x{i} = {rounded}")
