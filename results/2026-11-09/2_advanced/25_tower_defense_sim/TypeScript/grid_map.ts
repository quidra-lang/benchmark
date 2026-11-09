import { readFileSync } from 'node:fs';
export interface Point {
  x: number;
  y: number;
}
export class GridMap {
  cells: string[];
  spawns: { number: number; cell: number }[] = [];
  exit = -1;
  constructor(
    public width: number,
    public height: number,
    rows: string[],
  ) {
    this.cells = rows.join('').split('');
    this.cells.forEach((terrain, cell) => {
      if (terrain === 'E') this.exit = cell;
      else if (/^[1-9]$/.test(terrain)) this.spawns.push({ number: Number(terrain), cell });
    });
    this.spawns.sort((a, b) => a.number - b.number);
  }
  inside(x: number, y: number) {
    return x >= 0 && x < this.width && y >= 0 && y < this.height;
  }
  cell(x: number, y: number) {
    return y * this.width + x;
  }
  coordinates(cell: number): Point {
    return { x: cell % this.width, y: Math.floor(cell / this.width) };
  }
  center(cell: number): Point {
    const p = this.coordinates(cell);
    return { x: p.x * 100, y: p.y * 100 };
  }
  rock(cell: number) {
    return this.cells[cell] === '#';
  }
  water(cell: number) {
    return this.cells[cell] === '~';
  }
  buildable(cell: number) {
    return this.cells[cell] === '.';
  }
}
export function readMap() {
  const lines = readFileSync('input/map.txt', 'ascii').slice(0, -1).split('\n');
  const [width, height] = lines[0].split(' ').map(Number);
  return new GridMap(width, height, lines.slice(1));
}
