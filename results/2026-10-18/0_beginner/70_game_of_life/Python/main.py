board = [".#......", "..#.....", "###.....", "........",
         "........", "........", ".....###", "........"]
for generation in range(5):
    print(f"generation {generation}")
    print(*board, sep="\n")
    if generation == 4:
        break
    next_board = []
    for row in range(8):
        line = ""
        for column in range(8):
            neighbors = 0
            for dr in range(-1, 2):
                for dc in range(-1, 2):
                    r, c = row + dr, column + dc
                    if (dr or dc) and 0 <= r < 8 and 0 <= c < 8:
                        neighbors += board[r][c] == "#"
            alive = neighbors == 3 or (board[row][column] == "#" and neighbors == 2)
            line += "#" if alive else "."
        next_board.append(line)
    board = next_board
print(f"alive: {sum(row.count('#') for row in board)}")
