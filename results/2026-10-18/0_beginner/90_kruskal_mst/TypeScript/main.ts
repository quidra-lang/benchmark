const vertices = "ABCDEFGH";
const edges = [
  {a: "A", b: "B", weight: 7}, {a: "C", b: "A", weight: 4},
  {a: "B", b: "C", weight: 9}, {a: "B", b: "D", weight: 14},
  {a: "D", b: "C", weight: 6}, {a: "C", b: "E", weight: 3},
  {a: "E", b: "D", weight: 5}, {a: "F", b: "D", weight: 11},
  {a: "E", b: "G", weight: 16}, {a: "G", b: "F", weight: 8},
  {a: "H", b: "F", weight: 12}, {a: "G", b: "H", weight: 2},
  {a: "H", b: "E", weight: 10}
];
const parents = new Map([...vertices].map(vertex => [vertex, vertex]));

function find(vertex: string): string {
  while (parents.get(vertex) !== vertex) {
    parents.set(vertex, parents.get(parents.get(vertex)!)!);
    vertex = parents.get(vertex)!;
  }
  return vertex;
}

let accepted = 0, skipped = 0, total = 0;
for (const {a, b, weight} of edges.sort((a, b) => a.weight - b.weight)) {
  const rootA = find(a), rootB = find(b);
  if (rootA === rootB) {
    skipped++;
    continue;
  }
  parents.set(rootB, rootA);
  accepted++;
  total += weight;
  console.log(`${[a, b].sort().join("-")} ${weight}`);
  if (accepted === vertices.length - 1) break;
}
console.log(`total weight: ${total}`);
console.log(`skipped: ${skipped}`);
