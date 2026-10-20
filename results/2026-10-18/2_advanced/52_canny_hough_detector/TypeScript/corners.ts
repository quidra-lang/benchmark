import { at } from './filters.ts';
import { neighbors } from './canny.ts';
import type { Point } from './pgm_io.ts';
export interface Corner extends Point { response: number; number: number }
export function detect(gx: number[], gy: number[], width: number, height: number, window: number, threshold: number, maximum: number) {
    const half = (window - 1) / 2, response: number[] = Array(width * height).fill(0);
    for (let y = 0; y < height; y++) for (let x = 0; x < width; x++) {
        let xx = 0, yy = 0, xy = 0;
        for (let j = -half; j <= half; j++) for (let i = -half; i <= half; i++) { const a = at(gx, x + i, y + j, width, height), b = at(gy, x + i, y + j, width, height); xx += a * a; yy += b * b; xy += a * b; }
        response[y * width + x] = xx * yy - xy * xy - Math.floor((xx + yy) * (xx + yy) / 25);
    }
    const candidates: Omit<Corner, 'number'>[] = [];
    for (let i = 0; i < response.length; i++) { const r = response[i]; if (r < threshold || neighbors(i, width, height).some(j => response[j] > r || (response[j] === r && j < i))) continue; candidates.push({ x: i % width, y: Math.floor(i / width), response: r }); }
    candidates.sort((a, b) => a.response !== b.response ? (a.response > b.response ? -1 : 1) : a.y - b.y || a.x - b.x);
    return { response, candidates, corners: candidates.slice(0, maximum).map((c, i) => ({ ...c, number: i + 1 })) };
}
