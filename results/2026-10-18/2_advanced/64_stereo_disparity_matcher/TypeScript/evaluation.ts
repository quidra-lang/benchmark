import type { Image } from './pgm_io.ts';
import { decimals } from './refinement.ts';
export interface Evaluation { pixels: number; valid: number; bad1: number; bad2: number; error: number; exact: number }
export function ratio(a: number, b: number): string { if (b === 0) return '0/1 0.00'; let x = a, y = b; while (y) [x, y] = [y, x % y]; return `${a / x}/${b / x} ${decimals(100 * a, b)}`; }
export function regions(truth: Image) {
  const { width, height, pixels } = truth, all = pixels.map((_, i) => i).filter(i => pixels[i] !== 0), occluded: number[] = [], nonocc: number[] = [], disc: number[] = [];
  for (const i of all) { const x = i % width, y = Math.floor(i / width), g = pixels[i], target = x - g; let hidden = target < 0; for (let x2 = 0; x2 < width && !hidden; x2++) if (pixels[y * width + x2] > g && x2 - pixels[y * width + x2] === target) hidden = true; (hidden ? occluded : nonocc).push(i); }
  for (const i of nonocc) { const x = i % width, y = Math.floor(i / width); let boundary = false; for (let dy = -1; dy <= 1; dy++) for (let dx = -1; dx <= 1; dx++) { const xx = x + dx, yy = y + dy; if ((dx || dy) && xx >= 0 && xx < width && yy >= 0 && yy < height && pixels[yy * width + xx] !== 0 && Math.abs(pixels[yy * width + xx] - pixels[i]) >= 2) boundary = true; } if (boundary) disc.push(i); }
  return { nonocc, all, disc, occluded };
}
export function evaluate(disparity: number[], truth: number[], region: number[]): Evaluation {
  const result = { pixels: region.length, valid: 0, bad1: 0, bad2: 0, error: 0, exact: 0 };
  for (const i of region) { if (disparity[i] === 0) { result.bad1++; result.bad2++; } else { const error = Math.abs(disparity[i] - truth[i]); result.valid++; result.error += error; if (error > 1) result.bad1++; if (error > 2) result.bad2++; if (error === 0) result.exact++; } }
  return result;
}
