function logGamma(x: number): number {
  const coefficients = [
    76.18009172947146, -86.50532032941677, 24.01409824083091, -1.231739572450155,
    0.001208650973866179, -0.000005395239384953,
  ];
  const t = x + 5.5;
  const bigT = t - (x + 0.5) * Math.log(t);
  let sum = 1.000000000190015;
  coefficients.forEach((coefficient, j) => {
    sum += coefficient / (x + (j + 1));
  });
  return -bigT + Math.log((2.5066282746310005 * sum) / x);
}
const small = (value: number) => (Math.abs(value) < 1e-300 ? 1e-300 : value);
function continuedBeta(a: number, b: number, x: number): number {
  let c = 1;
  let d = 1 / small(1 - ((a + b) * x) / (a + 1));
  let h = d;
  for (let m = 1; m <= 1000; m++) {
    let q = (m * (b - m) * x) / ((a - 1 + 2 * m) * (a + 2 * m));
    d = 1 / small(1 + q * d);
    c = small(1 + q / c);
    h = h * (d * c);
    q = (-(a + m) * (a + b + m) * x) / ((a + 2 * m) * (a + 1 + 2 * m));
    d = 1 / small(1 + q * d);
    c = small(1 + q / c);
    const delta = d * c;
    h = h * delta;
    if (Math.abs(delta - 1) < 1e-15) break;
  }
  return h;
}
export function betaI(x: number, a: number, b: number): number {
  if (x <= 0) return 0;
  if (x >= 1) return 1;
  const factor = Math.exp(
    logGamma(a + b) - logGamma(a) - logGamma(b) + a * Math.log(x) + b * Math.log(1 - x),
  );
  return x < (a + 1) / (a + b + 2)
    ? (factor * continuedBeta(a, b, x)) / a
    : 1 - (factor * continuedBeta(b, a, 1 - x)) / b;
}
export function gammaQ(a: number, x: number): number {
  if (x === 0) return 1;
  const factor = Math.exp(-x + a * Math.log(x) - logGamma(a));
  if (x < a + 1) {
    let t = 1 / a;
    let sum = t;
    let e = a;
    for (let i = 0; i < 1000; i++) {
      e = e + 1;
      t = t * (x / e);
      sum = sum + t;
      if (Math.abs(t) < Math.abs(sum) * 1e-15) break;
    }
    return 1 - sum * factor;
  }
  let beta = x + 1 - a;
  let c = 1 / 1e-300;
  let d = 1 / beta;
  let h = d;
  for (let i = 1; i <= 1000; i++) {
    const q = -i * (i - a);
    beta = beta + 2;
    d = 1 / small(q * d + beta);
    c = small(beta + q / c);
    const delta = d * c;
    h = h * delta;
    if (Math.abs(delta - 1) < 1e-15) break;
  }
  return factor * h;
}
export const pT = (t: number, df: number) => betaI(df / (df + t * t), df / 2, 0.5);
export const pF = (value: number, d1: number, d2: number) =>
  betaI(d2 / (d2 + d1 * value), d2 / 2, d1 / 2);
export const pChi = (value: number, df: number) => gammaQ(df / 2, value / 2);
export function tQuantile(confidence: number, df: number): number {
  let lo = 0;
  let hi = 1000;
  for (let i = 0; i < 100; i++) {
    const mid = (lo + hi) / 2;
    if (pT(mid, df) > 1 - confidence) lo = mid;
    else hi = mid;
  }
  return (lo + hi) / 2;
}
export const significance = (p: number | undefined) =>
  p === undefined ? '' : p < 0.001 ? '***' : p < 0.01 ? '**' : p < 0.05 ? '*' : p < 0.1 ? '.' : '';
export function format(value: number | undefined): string {
  if (value === undefined) return 'NA';
  if (Math.abs(value) >= 1e21) return `${BigInt(value)}.0000`;
  const text = value.toFixed(4);
  return +text === 0 ? '0.0000' : text;
}
export const formatP = (p: number | undefined) =>
  p === undefined ? 'NA' : p < 0.0001 ? '<0.0001' : format(p);
