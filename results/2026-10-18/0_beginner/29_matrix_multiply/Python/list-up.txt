a = [[3, -2, 5, 1], [-4, 7, 0, 6], [2, 9, -8, -3]]
b = [[1, 4], [-5, 2], [6, -1], [0, 7]]
for row in a:
    products = [sum(row[k] * b[k][j] for k in range(4)) for j in range(2)]
    print("".join(f"{value:5d}" for value in products))
