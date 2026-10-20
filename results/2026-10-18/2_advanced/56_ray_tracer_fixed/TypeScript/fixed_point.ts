export const S = 4096;
export const div = (a: number, b: number) => Math.floor(a / b);
export const mul = (a: number, b: number) => div(a * b, S);
export function isqrt(n: number): number {
  let lo = 0;
  let hi = 1;
  while (hi * hi <= n) hi *= 2;
  while (hi - lo > 1) {
    const middle = div(lo + hi, 2);
    if (middle * middle <= n) lo = middle;
    else hi = middle;
  }
  return lo;
}
