import type { Data, Profile } from './ratings.ts';
export interface Similarity {
  similarity: number;
  common: number;
}
export function userSimilarity(
  first: Profile,
  second: Profile,
  shrinkage: number,
): Similarity | null {
  let n = 0;
  let sx = 0;
  let sy = 0;
  let sxx = 0;
  let syy = 0;
  let sxy = 0;
  for (const row of first.entries) {
    const y = second.ratings.get(row.i);
    if (y === undefined) continue;
    const x = row.rating;
    n++;
    sx += x;
    sy += y;
    sxx += x * x;
    syy += y * y;
    sxy += x * y;
  }
  if (n < 2) return null;
  const num = n * sxy - sx * sy;
  const dx = n * sxx - sx * sx;
  const dy = n * syy - sy * sy;
  if (!dx || !dy) return null;
  const a = BigInt(num) * BigInt(n);
  const reg = BigInt(n) + BigInt(shrinkage);
  const b = BigInt(dx) * BigInt(dy) * reg * reg;
  return { similarity: Math.sign(num) * Math.sqrt(Number(a * a) / Number(b)), common: n };
}
export function buildNeighborhoods(data: Data) {
  const users: (Similarity | null)[][] = data.users.map(() => data.users.map(() => null));
  for (let u = 0; u < data.users.length; u++) {
    for (let v = u + 1; v < data.users.length; v++) {
      users[u][v] = users[v][u] = userSimilarity(
        data.users[u],
        data.users[v],
        data.settings.shrinkage,
      );
    }
  }
  const items: (Similarity | null)[][] = data.items.map(() => data.items.map(() => null));
  const common = data.items.map(() => data.items.map(() => 0));
  const difference = common.map((row) => [...row]);
  for (let i = 0; i < data.items.length; i++) {
    for (let j = i + 1; j < data.items.length; j++) {
      let count = 0;
      let sum = 0;
      let num = 0;
      let ni = 0;
      let nj = 0;
      for (const row of data.items[i].entries) {
        const other = data.items[j].ratings.get(row.u);
        if (other === undefined) continue;
        count++;
        sum += row.rating - other;
        const x = row.rating - data.users[row.u].mean;
        const y = other - data.users[row.u].mean;
        num += x * y;
        ni += x * x;
        nj += y * y;
      }
      common[i][j] = common[j][i] = count;
      difference[i][j] = sum;
      difference[j][i] = -sum;
      if (count >= 2 && ni !== 0 && nj !== 0) {
        items[i][j] = items[j][i] = {
          similarity: ((num / Math.sqrt(ni * nj)) * count) / (count + data.settings.shrinkage),
          common: count,
        };
      }
    }
  }
  return { users, items, common, difference };
}
export function select<T extends { similarity: number; id: number }>(
  candidates: T[],
  count: number,
): T[] {
  return candidates.sort((a, b) => b.similarity - a.similarity || a.id - b.id).slice(0, count);
}
