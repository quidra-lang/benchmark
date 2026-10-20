import type { Image, Parameters } from './pgm_io.ts';
export function at(values: ArrayLike<number>, x: number, y: number, width: number, height: number) { return values[Math.min(Math.max(y, 0), height - 1) * width + Math.min(Math.max(x, 0), width - 1)]; }
export function smooth(image: Image, p: Parameters) {
    const { width: w, height: h, pixels } = image, size = p.gauss_size, half = (size - 1) / 2, result: number[] = Array(w * h).fill(0);
    for (let y = 0; y < h; y++) for (let x = 0; x < w; x++) { let sum = 0; for (let j = 0; j < size; j++) for (let i = 0; i < size; i++) sum += p.gauss_kernel[j * size + i] * at(pixels, x + i - half, y + j - half, w, h); result[y * w + x] = Math.floor(sum / p.gauss_divisor); } return result;
}
export function gradient(values: number[], w: number, h: number) {
    const gx: number[] = Array(w * h).fill(0), gy: number[] = Array(w * h).fill(0), magnitude: number[] = Array(w * h).fill(0);
    for (let y = 0; y < h; y++) for (let x = 0; x < w; x++) { const q: number[] = []; for (let j = -1; j <= 1; j++) for (let i = -1; i <= 1; i++) q.push(at(values, x + i, y + j, w, h)); const k = y * w + x; gx[k] = (q[2] + 2 * q[5] + q[8]) - (q[0] + 2 * q[3] + q[6]); gy[k] = (q[6] + 2 * q[7] + q[8]) - (q[0] + 2 * q[1] + q[2]); magnitude[k] = Math.abs(gx[k]) + Math.abs(gy[k]); }
    return { gx, gy, magnitude };
}
