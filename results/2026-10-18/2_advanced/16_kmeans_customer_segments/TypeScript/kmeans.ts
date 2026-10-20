export interface ClusterData {
  groups: number[][];
  centers: number[][];
}
export interface LloydResult {
  assignment: number[];
  centers: number[][];
  iterations: number;
  reseeds: number;
  converged: boolean;
  sse: number;
}
export function squaredDistance(first: number[], second: number[]): number {
  let total = 0;
  for (let feature = 0; feature < first.length; feature++) {
    const difference = first[feature] - second[feature];
    total += difference * difference;
  }
  return total;
}
export function meanPoint(points: number[][]): number[] {
  const total = points[0].map(() => 0);
  for (const point of points) {
    for (let feature = 0; feature < total.length; feature++) total[feature] += point[feature];
  }
  return total.map((value) => value / points.length);
}
export function assign(points: number[][], centers: number[][]) {
  const assignment: number[] = [];
  const errors: number[] = [];
  for (const point of points) {
    let chosen = 0;
    let best = squaredDistance(point, centers[0]);
    for (let center = 1; center < centers.length; center++) {
      const error = squaredDistance(point, centers[center]);
      if (error < best) {
        chosen = center;
        best = error;
      }
    }
    assignment.push(chosen);
    errors.push(best);
  }
  return { assignment, errors };
}
export function clusterData(points: number[][], assignment: number[], k: number): ClusterData {
  const groups = Array.from({ length: k }, (): number[] => []);
  for (let index = 0; index < points.length; index++) groups[assignment[index]].push(index);
  return { groups, centers: groups.map((group) => meanPoint(group.map((index) => points[index]))) };
}
function refill(assignment: number[], errors: number[], k: number): number {
  const counts: number[] = Array(k).fill(0);
  for (const center of assignment) counts[center]++;
  let reseeds = 0;
  for (let center = 0; center < k; center++) {
    if (counts[center] !== 0) continue;
    let chosen = -1;
    for (let index = 0; index < assignment.length; index++) {
      if (counts[assignment[index]] >= 2 && (chosen === -1 || errors[index] > errors[chosen])) {
        chosen = index;
      }
    }
    counts[assignment[chosen]]--;
    assignment[chosen] = center;
    counts[center]++;
    errors[chosen] = 0;
    reseeds++;
  }
  return reseeds;
}
export function sumSquared(points: number[][], assignment: number[], centers: number[][]): number {
  let total = 0;
  for (let index = 0; index < points.length; index++) {
    total += squaredDistance(points[index], centers[assignment[index]]);
  }
  return total;
}
export function lloyd(points: number[][], initialCenters: number[][], limit: number): LloydResult {
  let centers = initialCenters.map((point) => point.slice());
  let current = assign(points, centers);
  let iterations = 0;
  let reseeds = 0;
  let converged = false;
  while (iterations < limit) {
    reseeds += refill(current.assignment, current.errors, centers.length);
    centers = clusterData(points, current.assignment, centers.length).centers;
    iterations++;
    const next = assign(points, centers);
    converged = next.assignment.every((center, index) => center === current.assignment[index]);
    current = next;
    if (converged) break;
  }
  reseeds += refill(current.assignment, current.errors, centers.length);
  centers = clusterData(points, current.assignment, centers.length).centers;
  return {
    assignment: current.assignment,
    centers,
    iterations,
    reseeds,
    converged,
    sse: sumSquared(points, current.assignment, centers),
  };
}
