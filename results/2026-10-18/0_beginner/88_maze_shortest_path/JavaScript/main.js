const rows = [
  "#############", "#S..#.......#", "#.#.#.###.#.#", "#.#...#...#.#", "#.###.#.###.#",
  "#...#...#...#", "###.#####.#.#", "#.......#..G#", "#############"
];
const height = rows.length, width = rows[0].length;
const maze = rows.join("").split("");
const start = maze.indexOf("S"), goal = maze.indexOf("G");
const parent = Array(maze.length).fill(-1), queue = [start];
parent[start] = start;
for (let head = 0; head < queue.length; head++) {
  const cell = queue[head];
  if (cell === goal) break;
  const row = Math.floor(cell / width), column = cell % width;
  for (const [dr, dc] of [[-1, 0], [1, 0], [0, -1], [0, 1]]) {
    const r = row + dr, c = column + dc;
    if (r >= 0 && r < height && c >= 0 && c < width) {
      const neighbor = r * width + c;
      if (maze[neighbor] !== "#" && parent[neighbor] < 0) {
        parent[neighbor] = cell;
        queue.push(neighbor);
      }
    }
  }
}
let steps = 0;
for (let cell = goal; cell !== start; cell = parent[cell]) {
  steps++;
  if (maze[cell] === ".") maze[cell] = "*";
}
console.log(`steps: ${steps}`);
for (let offset = 0; offset < maze.length; offset += width) {
  console.log(maze.slice(offset, offset + width).join(""));
}
