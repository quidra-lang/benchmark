import type { Parameters } from './dataframe.ts';
import { pChi } from './inference.ts';
import { fit, type Fit } from './qr_solver.ts';

export interface RowDiagnostics { standardized: number; studentized: number; cooks: number; dffits: number; flags: string; dfbetas: number[] }
export interface Diagnostics { rows: RowDiagnostics[]; dw: number; bp: number; bpDf: number; bpP: number; skewness: number; kurtosis: number; jb: number; jbP: number }
export function diagnose(model: Fit, x: number[][], sigma: number, df: number, params: Parameters): Diagnostics {
  const n = x.length, r = model.rank;
  const rows = model.weightedResiduals.map((eps, i) => {
    const h = model.leverage[i], standardized = eps / (sigma * Math.sqrt(1 - h)), studentized = standardized * Math.sqrt((df - 1) / (df - standardized * standardized));
    const cooks = standardized * standardized * h / (r * (1 - h)), dffits = studentized * Math.sqrt(h / (1 - h));
    const flags = (h > params.leverage * r / n ? 'H' : '') + (Math.abs(studentized) > params.studentized ? 'O' : '') + (cooks > params.cook / n ? 'C' : '') + (Math.abs(dffits) > params.dffits * Math.sqrt(r / n) ? 'F' : '');
    const deletedSigma = sigma * Math.sqrt((df - standardized * standardized) / (df - 1));
    const dfbetas = model.g[i].map((g, k) => g * eps / (1 - h) / (deletedSigma * Math.sqrt(model.varianceFactors[k])));
    return { standardized, studentized, cooks, dffits, flags: flags || '-', dfbetas };
  });
  let dwNumerator = 0;
  for (let i = 1; i < n; i++) { const delta = model.weightedResiduals[i] - model.weightedResiduals[i - 1]; dwNumerator += delta * delta; }
  const dw = dwNumerator / model.rss;
  const squares = model.weightedResiduals.map(eps => eps * eps), rawAccepted = x.map(row => model.accepted.map(j => row[j]));
  const auxiliary = fit(rawAccepted, squares, Array<number>(n).fill(1), params.tolerance), meanSquare = squares.reduce((a, b) => a + b, 0) / n;
  let tss = 0; for (const value of squares) tss += (value - meanSquare) * (value - meanSquare);
  const bp = n * (1 - auxiliary.rss / tss), bpDf = auxiliary.rank - 1, bpP = pChi(bp, bpDf);
  const mean = model.weightedResiduals.reduce((a, b) => a + b, 0) / n;
  let sum2 = 0, sum3 = 0, sum4 = 0;
  for (const eps of model.weightedResiduals) { const delta = eps - mean; sum2 += delta * delta; sum3 += delta * delta * delta; sum4 += delta * delta * delta * delta; }
  const m2 = sum2 / n, m3 = sum3 / n, m4 = sum4 / n, skewness = m3 / (m2 * Math.sqrt(m2)), kurtosis = m4 / (m2 * m2);
  const jb = n / 6 * (skewness * skewness + (kurtosis - 3) * (kurtosis - 3) / 4);
  return { rows, dw, bp, bpDf, bpP, skewness, kurtosis, jb, jbP: pChi(jb, 2) };
}
