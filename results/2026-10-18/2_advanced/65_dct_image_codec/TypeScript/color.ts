import type { Image, Plane } from './image_io.ts';
export interface Factors { h: number; v: number }
export const clamp = (v: number) => Math.min(Math.max(v, 0), 255);
export function rgb(y: number, cb: number, cr: number): number[] { return [clamp(y + Math.floor((91881 * (cr - 128) + 32768) / 65536)), clamp(y + Math.floor((-22554 * (cb - 128) - 46802 * (cr - 128) + 32768) / 65536)), clamp(y + Math.floor((116130 * (cb - 128) + 32768) / 65536))]; }
export function convert(image: Image): Plane[] {
  const planes = Array.from({ length: 3 }, () => ({ width: image.width, height: image.height, pixels: Array<number>(image.width * image.height) }));
  for (let i = 0; i < image.width * image.height; i++) { const [r, g, b] = image.pixels.slice(3 * i, 3 * i + 3); planes[0].pixels[i] = Math.floor((19595 * r + 38470 * g + 7471 * b + 32768) / 65536); planes[1].pixels[i] = Math.floor((-11059 * r - 21709 * g + 32768 * b + 8421375) / 65536); planes[2].pixels[i] = Math.floor((32768 * r - 27439 * g - 5329 * b + 8421375) / 65536); }
  return planes;
}
export function geometry(width: number, height: number, factors: Factors[]) { const hmax = Math.max(...factors.map(f => f.h)), vmax = Math.max(...factors.map(f => f.v)), mx = Math.ceil(width / (8 * hmax)), my = Math.ceil(height / (8 * vmax)); return { hmax, vmax, mx, my, pw: 8 * hmax * mx, ph: 8 * vmax * my }; }
export function componentPlanes(image: Image, factors: Factors[]): Plane[] {
  const original = convert(image), g = geometry(image.width, image.height, factors);
  return factors.map((factor, c) => { const width = 8 * factor.h * g.mx, height = 8 * factor.v * g.my, fx = g.hmax / factor.h, fy = g.vmax / factor.v, pixels: number[] = [];
    for (let y = 0; y < height; y++) for (let x = 0; x < width; x++) { let sum = 0; for (let j = 0; j < fy; j++) for (let i = 0; i < fx; i++) sum += original[c].pixels[Math.min(fy * y + j, image.height - 1) * image.width + Math.min(fx * x + i, image.width - 1)]; pixels.push(Math.floor(sum / (fx * fy))); }
    return { width, height, pixels };
  });
}
export function upsample(planes: Plane[], width: number, height: number, factors: Factors[]): Plane[] {
  const g = geometry(width, height, factors);
  return factors.map((f, c) => ({ width, height, pixels: Array.from({ length: width * height }, (_, i) => planes[c].pixels[Math.floor(Math.floor(i / width) * f.v / g.vmax) * planes[c].width + Math.floor((i % width) * f.h / g.hmax)]) }));
}
export function imageFromPlanes(planes: Plane[]): Image { return { width: planes[0].width, height: planes[0].height, pixels: planes[0].pixels.flatMap((y, i) => rgb(y, planes[1].pixels[i], planes[2].pixels[i])) }; }
