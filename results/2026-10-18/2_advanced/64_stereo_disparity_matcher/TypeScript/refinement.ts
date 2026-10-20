export function decimals(a: number, b: number): string { const n = Math.floor((200 * a + b) / (2 * b)); return `${Math.floor(n / 100)}.${String(n % 100).padStart(2, '0')}`; }
export function depthHundredths(d: number, focal: number, baseline: number): number { return Math.floor((200 * focal * baseline + d) / (2 * d)); }
export function refine(cost: number[], disparity: number, min: number, max: number, focal: number, baseline: number) {
  const i = disparity - min; let a = 0, b = 1;
  if (disparity > min && disparity < max && cost[i - 1] > cost[i] && cost[i + 1] >= cost[i]) { a = cost[i - 1] - cost[i + 1]; b = 2 * (cost[i - 1] - 2 * cost[i] + cost[i + 1]); }
  const q = Math.floor((200 * (disparity * b + a) + b) / (2 * b));
  return { subpixel: `${Math.floor(q / 100)}.${String(q % 100).padStart(2, '0')}`, depth: decimals(100 * focal * baseline, q) };
}
