export interface WeightedGraph {
  out: number[][];
  in: number[][];
  weights: Map<number, number>[];
  totals: number[];
}
export interface PageRankResult {
  values: number[];
  changes: number[];
  convergedAt: number | null;
}

export function pageRank(
  graph: WeightedGraph,
  teleport: number[],
  damping: number,
  iterations: number,
  tolerance: number,
): PageRankResult {
  const seeds = new Set(teleport);
  const initial = 1 / seeds.size;
  let values = graph.out.map((_, node) => (seeds.has(node) ? initial : 0));
  const changes: number[] = [];
  let convergedAt: number | null = null;
  for (let iteration = 1; iteration <= iterations; iteration++) {
    let danglingMass = 0;
    for (let node = 0; node < values.length; node++) {
      if (graph.totals[node] === 0) danglingMass += values[node];
    }
    const base = (1 - damping + damping * danglingMass) / seeds.size;
    const next: number[] = Array(values.length);
    for (let node = 0; node < values.length; node++) {
      let inflow = 0;
      for (const source of graph.in[node]) {
        inflow += (values[source] * graph.weights[source].get(node)!) / graph.totals[source];
      }
      next[node] = seeds.has(node) ? damping * inflow + base : damping * inflow;
    }
    let change = 0;
    for (let node = 0; node < values.length; node++) change += Math.abs(next[node] - values[node]);
    changes.push(change);
    if (convergedAt === null && change < tolerance) convergedAt = iteration;
    values = next;
  }
  return { values, changes, convergedAt };
}
