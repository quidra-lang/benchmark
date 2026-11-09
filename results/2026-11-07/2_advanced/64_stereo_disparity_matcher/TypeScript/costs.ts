import type { Image, CostKind, Parameters } from './pgm_io.ts';
export function clamped(image: Image, x: number, y: number): number {
  return image.pixels[
    Math.min(Math.max(y, 0), image.height - 1) * image.width +
      Math.min(Math.max(x, 0), image.width - 1)
  ];
}
export function box(image: Image, window: number): number[] {
  const h = (window - 1) / 2;
  const width = image.width + 2 * h;
  const height = image.height + 2 * h;
  const stride = width + 1;
  const integral = Array<number>((width + 1) * (height + 1)).fill(0);
  for (let y = 0; y < height; y++) {
    for (let x = 0; x < width; x++) {
      integral[(y + 1) * stride + x + 1] =
        clamped(image, x - h, y - h) +
        integral[y * stride + x + 1] +
        integral[(y + 1) * stride + x] -
        integral[y * stride + x];
    }
  }
  return image.pixels.map((_, i) => {
    const x = i % image.width;
    const y = Math.floor(i / image.width);
    return (
      integral[(y + window) * stride + x + window] -
      integral[y * stride + x + window] -
      integral[(y + window) * stride + x] +
      integral[y * stride + x]
    );
  });
}
export function census(image: Image): number[] {
  return image.pixels.map((center, i) => {
    const x = i % image.width;
    const y = Math.floor(i / image.width);
    let code = 0;
    for (let dy = -2; dy <= 2; dy++) {
      for (let dx = -2; dx <= 2; dx++) {
        if (dx || dy) code = 2 * code + (clamped(image, x + dx, y + dy) < center ? 1 : 0);
      }
    }
    return code;
  });
}
export function texture(image: Image, window: number): number[] {
  return box(
    {
      ...image,
      pixels: image.pixels.map((_, i) => {
        const x = i % image.width;
        const y = Math.floor(i / image.width);
        return Math.abs(clamped(image, x + 1, y) - clamped(image, x - 1, y));
      }),
    },
    window,
  );
}
function popcount(value: number): number {
  let count = 0;
  while (value) {
    value &= value - 1;
    count++;
  }
  return count;
}
export function matching(
  left: Image,
  right: Image,
  lc: number[],
  rc: number[],
  kind: CostKind,
  window: number,
  p: Parameters,
): number[][] {
  const volume = left.pixels.map(() => Array<number>(p.max - p.min + 1));
  for (let d = p.min; d <= p.max; d++) {
    const pixels = left.pixels.map((v, i) => {
      const j = Math.floor(i / left.width) * left.width + Math.max((i % left.width) - d, 0);
      const diff = v - right.pixels[j];
      return kind === 'census'
        ? popcount(lc[i] ^ rc[j])
        : kind === 'sad'
          ? Math.abs(diff)
          : diff * diff;
    });
    box({ ...left, pixels }, window).forEach((v, i) => (volume[i][d - p.min] = v));
  }
  return volume;
}
