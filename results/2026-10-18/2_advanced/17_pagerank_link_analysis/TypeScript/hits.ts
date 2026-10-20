import type { WeightedGraph } from './pagerank.ts';
export function hits(graph: WeightedGraph, nodes: number[], iterations: number) {
  let authority: number[] = Array(graph.out.length).fill(0);
  let hub: number[] = Array(graph.out.length).fill(0);
  for (const node of nodes) {
    authority[node] = 1;
    hub[node] = 1;
  }
  for (let iteration = 0; iteration < iterations; iteration++) {
    const nextAuthority: number[] = Array(graph.out.length).fill(0);
    const nextHub: number[] = Array(graph.out.length).fill(0);
    for (const node of nodes) {
      for (const source of graph.in[node]) nextAuthority[node] += hub[source];
    }
    for (const node of nodes) {
      for (const target of graph.out[node]) nextHub[node] += nextAuthority[target];
    }
    let authoritySquared = 0;
    let hubSquared = 0;
    for (const node of nodes) {
      authoritySquared += nextAuthority[node] * nextAuthority[node];
      hubSquared += nextHub[node] * nextHub[node];
    }
    const authorityNorm = Math.sqrt(authoritySquared);
    const hubNorm = Math.sqrt(hubSquared);
    for (const node of nodes) {
      nextAuthority[node] /= authorityNorm;
      nextHub[node] /= hubNorm;
    }
    authority = nextAuthority;
    hub = nextHub;
  }
  return { authority, hub };
}
