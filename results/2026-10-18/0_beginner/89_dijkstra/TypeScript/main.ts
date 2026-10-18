const names = "ABCDEFG";
const edges = [
  [0, 1, 7], [0, 2, 3], [0, 3, 9], [1, 2, 2], [2, 4, 6], [1, 3, 3],
  [3, 4, 4], [3, 5, 5], [4, 5, 3], [4, 6, 8], [5, 6, 4]
];
const graph: [number, number][][] = Array.from({length: names.length}, () => []);
for (const [a, b, weight] of edges) {
  graph[a].push([b, weight]);
  graph[b].push([a, weight]);
}
const distances = Array(names.length).fill(Infinity);
distances[0] = 0;
const done = Array(names.length).fill(false), previous = Array(names.length).fill(-1);
for (let count = 0; count < names.length; count++) {
  let vertex = -1;
  for (let v = 0; v < names.length; v++) {
    if (!done[v] && (vertex < 0 || distances[v] < distances[vertex])) vertex = v;
  }
  done[vertex] = true;
  for (const [neighbor, weight] of graph[vertex]) {
    const candidate = distances[vertex] + weight;
    if (candidate < distances[neighbor]) {
      distances[neighbor] = candidate;
      previous[neighbor] = vertex;
    }
  }
}
for (let target = 0; target < names.length; target++) {
  const path = [];
  for (let vertex = target; vertex >= 0; vertex = previous[vertex]) path.push(names[vertex]);
  console.log(`${names[target]}: distance=${distances[target]} path=${path.reverse().join("-")}`);
}
