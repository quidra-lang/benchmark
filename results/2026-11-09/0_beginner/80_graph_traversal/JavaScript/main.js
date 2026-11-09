const edges = [[5, 0], [3, 8], [7, 2], [1, 6], [0, 2], [5, 3], [7, 5], [6, 4], [8, 7]];
const graph = Array.from({length: 9}, () => []);
for (const [a, b] of edges) {
  graph[a].push(b);
  graph[b].push(a);
}
for (const neighbors of graph) neighbors.sort((a, b) => a - b);

function dfs(vertex, seen, order) {
  seen.add(vertex);
  order.push(vertex);
  for (const neighbor of graph[vertex]) {
    if (!seen.has(neighbor)) dfs(neighbor, seen, order);
  }
}

const depth = [];
dfs(0, new Set(), depth);
const queue = [0], breadth = [];
const reached = new Set([0]);
for (let head = 0; head < queue.length; head++) {
  const vertex = queue[head];
  breadth.push(vertex);
  for (const neighbor of graph[vertex]) {
    if (!reached.has(neighbor)) {
      reached.add(neighbor);
      queue.push(neighbor);
    }
  }
}
const components = [], seen = new Set();
for (let vertex = 0; vertex < 9; vertex++) {
  if (!seen.has(vertex)) {
    const component = [];
    dfs(vertex, seen, component);
    components.push(component.sort((a, b) => a - b));
  }
}
console.log(`DFS: ${depth.join(" ")}`);
console.log(`BFS: ${breadth.join(" ")}`);
console.log(`components: ${components.length}`);
components.forEach((component, i) => console.log(`component ${i + 1}: ${component.join(" ")}`));
