import { readFileSync } from 'node:fs';

export interface Material {
  code: string;
  name: string;
  k: number;
  rho: number;
  cp: number;
  cells: number[];
}
export function readMaterials(): Material[] {
  return readFileSync('input/materials.txt', 'ascii')
    .trimEnd()
    .split('\n')
    .map((line) => {
      const [code, name, k, rho, cp] = line.split(' ');
      return { code, name, k: Number(k), rho: Number(rho), cp: Number(cp), cells: [] };
    });
}
export const capacity = (m: Material, dx: number, depth: number): number =>
  m.rho * m.cp * dx * dx * depth;
export const interior = (kp: number, kq: number, depth: number): number =>
  ((2 * kp * kq) / (kp + kq)) * depth;
export const fixed = (k: number, depth: number): number => 2 * k * depth;
export const convective = (k: number, h: number, dx: number, depth: number): number =>
  1 / (1 / (h * dx * depth) + 1 / (2 * k * depth));
