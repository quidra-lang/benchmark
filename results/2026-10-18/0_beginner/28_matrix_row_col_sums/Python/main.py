matrix = [
    [125, 340, 78, 912, 456],
    [603, 27, 819, 150, 384],
    [0, 765, 231, 498, 62],
    [947, 113, 586, 39, 720],
]
for row in matrix:
    print("".join(f"{value:6d}" for value in [*row, sum(row)]))
columns = [sum(column) for column in zip(*matrix)]
print("".join(f"{value:6d}" for value in [*columns, sum(columns)]))
