import type { Image, Parameters } from './pgm_io.ts';
export const directions = [[1, 0], [-1, 0], [0, 1], [0, -1], [1, 1], [-1, -1], [-1, 1], [1, -1]];
export function* aggregate(cost: number[][], image: Image, p: Parameters): Generator<number[][]> {
  const { width, height } = image, dCount = p.max - p.min + 1, sum = cost.map(row => row.map(() => 0));
  for (const [rx, ry] of directions.slice(0, p.paths)) {
    const path = cost.map(row => row.map(() => 0));
    for (let yi = 0; yi < height; yi++) for (let xi = 0; xi < width; xi++) {
      const x = rx >= 0 ? xi : width - 1 - xi, y = ry >= 0 ? yi : height - 1 - yi, i = y * width + x, qx = x - rx, qy = y - ry;
      if (qx < 0 || qx >= width || qy < 0 || qy >= height) path[i] = cost[i].slice();
      else {
        const q = qy * width + qx, previous = path[q], min = Math.min(...previous), penalty = Math.max(p.p1, Math.floor(p.p2 * p.gamma / (p.gamma + Math.abs(image.pixels[i] - image.pixels[q]))));
        for (let d = 0; d < dCount; d++) { let best = Math.min(previous[d], min + penalty); if (d > 0) best = Math.min(best, previous[d - 1] + p.p1); if (d + 1 < dCount) best = Math.min(best, previous[d + 1] + p.p1); path[i][d] = cost[i][d] + best - min; }
      }
      for (let d = 0; d < dCount; d++) sum[i][d] += path[i][d];
    }
    yield sum.map(row => row.slice());
  }
}
