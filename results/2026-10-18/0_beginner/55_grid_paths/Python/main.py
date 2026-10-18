grid = [".......", "..#....", "....#..", ".#.....", "...#.#.", "......."]


def paths(blocked):
    dp = [[0] * len(grid[0]) for _ in grid]
    dp[0][0] = 1
    for row in range(len(grid)):
        for column in range(len(grid[0])):
            if blocked and grid[row][column] == "#":
                dp[row][column] = 0
            elif row or column:
                dp[row][column] = (dp[row - 1][column] if row else 0) + (dp[row][column - 1] if column else 0)
    return dp[-1][-1]


print(f"without obstacles: {paths(False)}")
print(f"with obstacles: {paths(True)}")
