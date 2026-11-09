function pageRank(graph, teleport, damping, iterations, tolerance) {
  const seeds = new Set(teleport);
  const initial = 1 / seeds.size;
  let values = graph.out.map((_, node) => seeds.has(node) ? initial : 0);
  const changes = [];
  let convergedAt = null;
  for (let iteration = 1; iteration <= iterations; iteration += 1) {
    let danglingMass = 0;
    for (let node = 0; node < values.length; node += 1) {
      if (graph.totals[node] === 0) danglingMass += values[node];
    }
    const base = ((1 - damping) + damping * danglingMass) / seeds.size;
    const next = Array(values.length);
    for (let node = 0; node < values.length; node += 1) {
      let inflow = 0;
      for (const source of graph.in[node]) {
        inflow += (values[source] * graph.weights[source].get(node)) / graph.totals[source];
      }
      next[node] = seeds.has(node) ? damping * inflow + base : damping * inflow;
    }
    let change = 0;
    for (let node = 0; node < values.length; node += 1) change += Math.abs(next[node] - values[node]);
    changes.push(change);
    if (convergedAt === null && change < tolerance) convergedAt = iteration;
    values = next;
  }
  return { values, changes, convergedAt };
}

module.exports = { pageRank };
