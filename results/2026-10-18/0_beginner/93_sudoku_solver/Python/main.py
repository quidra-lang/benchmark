rows = [
    "800025000", "070080005", "260400070", "000001900", "010000040",
    "600200000", "900010000", "700000004", "020000036",
]
board = [[int(digit) for digit in row] for row in rows]
placements = 0


def solve():
    global placements
    for row in range(9):
        for column in range(9):
            if board[row][column] != 0:
                continue
            for digit in range(1, 10):
                if digit in board[row] or any(board[r][column] == digit for r in range(9)):
                    continue
                top, left = row // 3 * 3, column // 3 * 3
                if any(board[r][c] == digit for r in range(top, top + 3) for c in range(left, left + 3)):
                    continue
                board[row][column] = digit
                placements += 1
                if solve():
                    return True
                board[row][column] = 0
            return False
    return True


solve()
for row in board:
    print(*row)
print(f"placements: {placements}")
