import type { Level } from './dungeon_gen.ts';
import type { Position } from './entities.ts';

export const directions = [
  { name: 'N', x: 0, y: -1 }, { name: 'NE', x: 1, y: -1 },
  { name: 'E', x: 1, y: 0 }, { name: 'SE', x: 1, y: 1 },
  { name: 'S', x: 0, y: 1 }, { name: 'SW', x: -1, y: 1 },
  { name: 'W', x: -1, y: 0 }, { name: 'NW', x: -1, y: -1 }
];
export function passable(level: Level, x: number, y: number): boolean {
  return x >= 0 && x < level.width && y >= 0 && y < level.height && '.#+<>'.includes(level.at(x, y));
}
export function canMove(level: Level, x: number, y: number, dx: number, dy: number): boolean {
  return passable(level, x + dx, y + dy) && (!dx || !dy || (level.at(x, y) !== '+' && level.at(x + dx, y + dy) !== '+'));
}
export function line(x: number, y: number, endX: number, endY: number): Position[] {
  const dx = Math.abs(endX - x), dy = Math.abs(endY - y);
  const sx = endX > x ? 1 : -1, sy = endY > y ? 1 : -1;
  let err = dx - dy;
  const cells: Position[] = [];
  while (x !== endX || y !== endY) {
    const e2 = 2 * err;
    if (e2 > -dy) { err -= dy; x += sx; }
    if (e2 < dx) { err += dx; y += sy; }
    cells.push({ x, y });
  }
  return cells;
}
export function fieldOfView(level: Level, px: number, py: number, radius: number): Set<number> {
  const visible = new Set<number>();
  for (let y = 0; y < level.height; y++) for (let x = 0; x < level.width; x++) {
    if ((x - px) ** 2 + (y - py) ** 2 > radius ** 2) continue;
    const cells = line(px, py, x, y);
    if (cells.slice(0, -1).every(cell => passable(level, cell.x, cell.y))) visible.add(level.index(x, y));
  }
  return visible;
}
export function distances(level: Level, px: number, py: number): number[] {
  const dist = Array<number>(level.width * level.height).fill(-1);
  const queue: Position[] = [{ x: px, y: py }];
  dist[level.index(px, py)] = 0;
  for (let head = 0; head < queue.length; head++) {
    const { x, y } = queue[head];
    for (const d of directions) {
      if (!canMove(level, x, y, d.x, d.y)) continue;
      const nx = x + d.x, ny = y + d.y, i = level.index(nx, ny);
      if (dist[i] >= 0) continue;
      dist[i] = dist[level.index(x, y)] + 1;
      queue.push({ x: nx, y: ny });
    }
  }
  return dist;
}
