size = 11
board = [[False] * size for _ in range(size)]
row = column = 5
direction = 0
directions = [(-1, 0), (0, 1), (1, 0), (0, -1)]
for _ in range(300):
    direction = (direction + (-1 if board[row][column] else 1)) % 4
    board[row][column] = not board[row][column]
    dr, dc = directions[direction]
    row = (row + dr) % size
    column = (column + dc) % size
for r in range(size):
    print(
        "".join(
            "A" if (r, c) == (row, column) else "#" if board[r][c] else "."
            for c in range(size)
        )
    )
print(f"black: {sum(sum(line) for line in board)}")
