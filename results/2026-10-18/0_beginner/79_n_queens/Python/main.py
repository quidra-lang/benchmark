def solve(n):
    placement = []
    count = 0
    first = None

    def visit():
        nonlocal count, first
        row = len(placement)
        if row == n:
            count += 1
            if first is None:
                first = placement.copy()
            return
        for column in range(n):
            if any(previous == column or abs(previous - column) == row - r for r, previous in enumerate(placement)):
                continue
            placement.append(column)
            visit()
            placement.pop()

    visit()
    return count, first


first_eight = None
for n in range(4, 9):
    count, first = solve(n)
    print(f"N={n}: {count} solutions")
    if n == 8:
        first_eight = first
for column in first_eight:
    print("." * column + "Q" + "." * (7 - column))
