import { clamp } from './color.ts';
const rnd = (a: number, s: number) => Math.floor((a + 2 ** (s - 1)) / 2 ** s);
export const zigzag = Array.from({ length: 64 }, (_, i) => i).sort((a, b) => { const u = Math.floor(a / 8), v = a % 8, x = Math.floor(b / 8), y = b % 8; return u + v - x - y || ((u + v) % 2 ? u - x : x - u); });
export function quantization(bases: number[][], quality: number): number[][] { const scale = quality < 50 ? Math.floor(5000 / quality) : 200 - 2 * quality; return bases.map(base => base.map(v => Math.min(Math.max(Math.floor((v * scale + 50) / 100), 1), 255))); }
export function transform(block: number[], c: number[][]): number[] {
  const e = Array<number>(64), f = Array<number>(64);
  for (let u = 0; u < 8; u++) for (let x = 0; x < 8; x++) { let sum = 0; for (let y = 0; y < 8; y++) sum += c[u][y] * (block[8 * y + x] - 128); e[8 * u + x] = rnd(sum, 11); }
  for (let u = 0; u < 8; u++) for (let v = 0; v < 8; v++) { let sum = 0; for (let x = 0; x < 8; x++) sum += e[8 * u + x] * c[v][x]; f[8 * u + v] = rnd(sum, 15); }
  return f;
}
export function inverse(d: number[], c: number[][]): number[] {
  const s = Array<number>(64), g = Array<number>(64);
  for (let y = 0; y < 8; y++) for (let v = 0; v < 8; v++) { let sum = 0; for (let u = 0; u < 8; u++) sum += c[u][y] * d[8 * u + v]; s[8 * y + v] = rnd(sum, 11); }
  for (let y = 0; y < 8; y++) for (let x = 0; x < 8; x++) { let sum = 0; for (let v = 0; v < 8; v++) sum += s[8 * y + v] * c[v][x]; g[8 * y + x] = clamp(rnd(sum, 15) + 128); }
  return g;
}
export function quantize(f: number[], q: number[]): number[] { return zigzag.map(i => { const a = Math.floor((Math.abs(f[i]) + Math.floor(q[i] / 2)) / q[i]); return f[i] >= 0 ? a : -a; }); }
export function dequantize(z: number[], q: number[], keep = 64): number[] { const d = Array<number>(64).fill(0); zigzag.forEach((index, i) => { if (i < keep) d[index] = z[i] * q[index]; }); return d; }
