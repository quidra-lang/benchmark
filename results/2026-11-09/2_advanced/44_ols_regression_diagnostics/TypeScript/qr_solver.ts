export interface Fit {
  rank: number;
  accepted: number[];
  beta: (number | undefined)[];
  effects: number[];
  triangular: number[][];
  inverse: number[][];
  varianceFactors: number[];
  u: number[][];
  g: number[][];
  leverage: number[];
  fitted: number[];
  residuals: number[];
  weightedResiduals: number[];
  rss: number;
}
export function fit(x: number[][], y: number[], weights: number[], tolerance: number): Fit {
  const n = x.length;
  const p = x[0].length;
  const roots = weights.map(Math.sqrt);
  const z = x.map((row, i) => row.map((value) => roots[i] * value));
  const a = z.map((row) => [...row]);
  const b = y.map((value, i) => roots[i] * value);
  const norms = Array.from({ length: p }, (_, j) => {
    let value = 0;
    for (let i = 0; i < n; i++) value += z[i][j] * z[i][j];
    return Math.sqrt(value);
  });
  const accepted: number[] = [];
  const rMatrix = Array.from({ length: p }, () => Array<number>(p).fill(0));
  for (let j = 0; j < p; j++) {
    const k = accepted.length;
    let length = 0;
    for (let i = k; i < n; i++) length += a[i][j] * a[i][j];
    const eta = Math.sqrt(length);
    if (eta <= tolerance * norms[j]) continue;
    accepted.push(j);
    const alpha = a[k][j] >= 0 ? -eta : eta;
    const v = Array<number>(n).fill(0);
    v[k] = a[k][j] - alpha;
    for (let i = k + 1; i < n; i++) v[i] = a[i][j];
    let square = 0;
    for (let i = k; i < n; i++) square += v[i] * v[i];
    for (let l = 0; l < k; l++) rMatrix[l][k] = a[l][j];
    rMatrix[k][k] = alpha;
    for (let l = j + 1; l < p; l++) {
      let product = 0;
      for (let i = k; i < n; i++) product += v[i] * a[i][l];
      const delta = (2 * product) / square;
      for (let i = k; i < n; i++) a[i][l] = a[i][l] - delta * v[i];
    }
    let product = 0;
    for (let i = k; i < n; i++) product += v[i] * b[i];
    const delta = (2 * product) / square;
    for (let i = k; i < n; i++) b[i] = b[i] - delta * v[i];
  }
  const rank = accepted.length;
  const triangular = rMatrix.slice(0, rank).map((row) => row.slice(0, rank));
  const effects = b.slice(0, rank);
  const beta = Array<number | undefined>(p).fill(undefined);
  for (let k = rank - 1; k >= 0; k--) {
    let value = 0;
    for (let l = k + 1; l < rank; l++) value += triangular[k][l] * beta[accepted[l]]!;
    beta[accepted[k]] = (effects[k] - value) / triangular[k][k];
  }
  const inverse = Array.from({ length: rank }, () => Array<number>(rank).fill(0));
  for (let m = 0; m < rank; m++) {
    for (let l = rank - 1; l >= 0; l--) {
      let value = 0;
      for (let q = l + 1; q < rank; q++) value += triangular[l][q] * inverse[q][m];
      inverse[l][m] = ((l === m ? 1 : 0) - value) / triangular[l][l];
    }
  }
  const varianceFactors = inverse.map((row) => {
    let value = 0;
    for (const element of row) value += element * element;
    return value;
  });
  const u: number[][] = [];
  const g: number[][] = [];
  const leverage: number[] = [];
  const fitted: number[] = [];
  const residuals: number[] = [];
  const weightedResiduals: number[] = [];
  let rss = 0;
  for (let i = 0; i < n; i++) {
    const ui = Array<number>(rank).fill(0);
    const gi = Array<number>(rank).fill(0);
    let h = 0;
    let prediction = 0;
    for (let k = 0; k < rank; k++) {
      for (let m = 0; m < rank; m++) ui[k] += z[i][accepted[m]] * inverse[m][k];
      h += ui[k] * ui[k];
    }
    for (let k = 0; k < rank; k++) {
      for (let m = 0; m < rank; m++) gi[k] += inverse[k][m] * ui[m];
      prediction += x[i][accepted[k]] * beta[accepted[k]]!;
    }
    const residual = y[i] - prediction;
    const weighted = roots[i] * residual;
    u.push(ui);
    g.push(gi);
    leverage.push(h);
    fitted.push(prediction);
    residuals.push(residual);
    weightedResiduals.push(weighted);
    rss += weighted * weighted;
  }
  return {
    rank,
    accepted,
    beta,
    effects,
    triangular,
    inverse,
    varianceFactors,
    u,
    g,
    leverage,
    fitted,
    residuals,
    weightedResiduals,
    rss,
  };
}
