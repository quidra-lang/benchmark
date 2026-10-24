import type { Placement, Positioned } from './types.ts';

export function entries(roots: Placement[]): Positioned[] {
  const result: Positioned[] = [];
  const visit = (placement: Placement, x: number, y: number, level: number): void => {
    x += placement.x; y += placement.y;
    result.push({ box: placement.box, x, y, level, role: placement.role || '' });
    for (const child of placement.box.children) visit(child, x, y, level + 1);
  };
  for (const root of roots) visit(root, 0, 0, 0);
  return result;
}

export function draw(placements: Positioned[], width: number, height: number): string[] {
  const grid = Array.from({ length: height }, () => Array(width).fill(' '));
  for (const entry of placements) for (const string of entry.box.strings) {
    for (let i = 0; i < string.text.length; i++) {
      if (string.text[i] !== ' ') grid[entry.y + string.y][entry.x + string.x + i] = string.text[i];
    }
  }
  return grid.map(row => row.join('').replace(/ +$/, ''));
}

export function boxLines(placements: Positioned[]): string[] {
  return placements.map(({ box, x, y, level, role }) => ' '.repeat(2 * level) + role + box.description
    + ` x=${x} y=${y} w=${box.width} h=${box.height} b=${box.baseline}`);
}

