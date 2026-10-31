import type { Grid, Coordinate, Locations, Layout } from './types.ts';

export function remainder(value: number, divisor: number): number {
  const degree = 31 - Math.clz32(divisor);
  for (let bit = 31 - Math.clz32(value); bit >= degree; bit--) {
    if (value & 2 ** bit) value ^= divisor << (bit - degree);
  }
  return value;
}

export function formatInformation(level: string, mask: number): number {
  const value = (8 * ({ L: 1, M: 0, Q: 3, H: 2 })[level] + mask) * 1024;
  return (value + remainder(value, 0x537)) ^ 0x5412;
}

export function versionInformation(version: number): number {
  const value = version * 4096;
  return value + remainder(value, 0x1f25);
}

export function positions(size: number): Locations {
  const format: Coordinate[][] = [[], []], version: Coordinate[][] = [[], []];
  for (let i = 0; i < 15; i++) {
    format[0].push(i <= 5 ? [8, i] : i === 6 ? [8, 7] : i === 7 ? [8, 8] : i === 8 ? [7, 8] : [14 - i, 8]);
    format[1].push(i <= 7 ? [size - 1 - i, 8] : [8, size - 15 + i]);
  }
  for (let i = 0; i < 18; i++) {
    version[0].push([size - 11 + i % 3, Math.floor(i / 3)]);
    version[1].push([Math.floor(i / 3), size - 11 + i % 3]);
  }
  return { format, version };
}

export function writeValue(grid: Grid, locations: Coordinate[], value: number): void {
  locations.forEach(([x, y], i) => { grid[y][x] = Math.floor(value / 2 ** i) % 2; });
}

export function readValue(grid: Grid, locations: Coordinate[]): number {
  let value = 0;
  locations.forEach(([x, y], i) => { value += grid[y][x] * 2 ** i; });
  return value;
}

export function create(version: number, centers: number[]): Layout {
  const size = 17 + 4 * version;
  const grid = Array.from({ length: size }, () => Array(size).fill(0));
  const areas = Array.from({ length: size }, () => Array(size).fill('data'));
  const set = (x: number, y: number, value: number, area: string = 'function'): void => { grid[y][x] = value; areas[y][x] = area; };
  for (const [cx, cy] of [[3, 3], [size - 4, 3], [3, size - 4]]) {
    for (let dy = -4; dy <= 4; dy++) for (let dx = -4; dx <= 4; dx++) {
      const x = cx + dx, y = cy + dy, distance = Math.max(Math.abs(dx), Math.abs(dy));
      if (x >= 0 && x < size && y >= 0 && y < size) set(x, y, distance === 2 || distance === 4 ? 0 : 1);
    }
  }
  for (let i = 8; i <= size - 9; i++) { set(6, i, i % 2 === 0 ? 1 : 0); set(i, 6, i % 2 === 0 ? 1 : 0); }
  for (let iy = 0; iy < centers.length; iy++) for (let ix = 0; ix < centers.length; ix++) {
    if ((ix === 0 && (iy === 0 || iy === centers.length - 1)) || (iy === 0 && ix === centers.length - 1)) continue;
    for (let dy = -2; dy <= 2; dy++) for (let dx = -2; dx <= 2; dx++) {
      set(centers[ix] + dx, centers[iy] + dy, Math.max(Math.abs(dx), Math.abs(dy)) === 1 ? 0 : 1);
    }
  }
  set(8, size - 8, 1);
  const locations = positions(size);
  for (const copy of locations.format) for (const [x, y] of copy) set(x, y, 0, 'format');
  if (version >= 7) for (const copy of locations.version) {
    for (const [x, y] of copy) set(x, y, 0, 'version');
    writeValue(grid, copy, versionInformation(version));
  }
  const order: Coordinate[] = [];
  for (let right = size - 1, pair = 0; right >= 1; right -= 2, pair++) {
    if (right === 6) right--;
    for (let row = 0; row < size; row++) {
      const y = pair % 2 === 0 ? size - 1 - row : row;
      for (const x of [right, right - 1]) if (areas[y][x] === 'data') order.push([x, y]);
    }
  }
  return { size, grid, areas, order, locations, functionCount: size * size - order.length };
}

