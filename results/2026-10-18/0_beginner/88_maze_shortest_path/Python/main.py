from collections import deque

rows = [
    "#############", "#S..#.......#", "#.#.#.###.#.#", "#.#...#...#.#", "#.###.#.###.#",
    "#...#...#...#", "###.#####.#.#", "#.......#..G#", "#############",
]
height, width = len(rows), len(rows[0])
maze = list("".join(rows))
start, goal = maze.index("S"), maze.index("G")
parent = {start: start}
queue = deque([start])
while queue:
    cell = queue.popleft()
    if cell == goal:
        break
    row, column = divmod(cell, width)
    for dr, dc in [(-1, 0), (1, 0), (0, -1), (0, 1)]:
        r, c = row + dr, column + dc
        if 0 <= r < height and 0 <= c < width:
            neighbor = r * width + c
            if maze[neighbor] != "#" and neighbor not in parent:
                parent[neighbor] = cell
                queue.append(neighbor)
steps = 0
cell = goal
while cell != start:
    steps += 1
    if maze[cell] == ".":
        maze[cell] = "*"
    cell = parent[cell]
print(f"steps: {steps}")
for start in range(0, len(maze), width):
    print("".join(maze[start:start + width]))
