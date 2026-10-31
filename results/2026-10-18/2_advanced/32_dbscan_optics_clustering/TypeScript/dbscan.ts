export interface Clustering {
  labels: number[];
  core: boolean[];
}
export function dbscan(neighborhoods: number[][], minPts: number): Clustering {
  const core = neighborhoods.map((neighbors) => neighbors.length >= minPts);
  const labels = Array<number>(core.length).fill(-2);
  let cluster = 0;
  for (let p = 0; p < labels.length; p++) {
    if (labels[p] !== -2) continue;
    if (!core[p]) {
      labels[p] = -1;
      continue;
    }
    labels[p] = cluster;
    const queue = [...neighborhoods[p]];
    for (let head = 0; head < queue.length; head++) {
      const q = queue[head];
      if (labels[q] === -1) labels[q] = cluster;
      else if (labels[q] === -2) {
        labels[q] = cluster;
        if (core[q]) for (const neighbor of neighborhoods[q]) queue.push(neighbor);
      }
    }
    cluster++;
  }
  return { labels, core };
}
