import { readFileSync } from 'node:fs';
import type { Agent } from './types.ts';

export function lines(filename: string): string[] {
  return readFileSync(`input/${filename}`, 'ascii').slice(0, -1).split('\n');
}

export class Grid {
  width: number;
  height: number;
  picture: string[];
  size: number;
  free: boolean[];
  neighbors: number[][];
  constructor(width: number, height: number, picture: string[]) {
    this.width = width;
    this.height = height;
    this.picture = picture;
    this.size = width * height;
    this.free = Array.from({length: this.size}, (_, cell) => picture[Math.floor(cell / width)][cell % width] === '.');
    this.neighbors = Array.from({length: this.size}, (): number[] => []);
    const actions = [[0, 0], [0, -1], [1, 0], [0, 1], [-1, 0]];
    for (let cell = 0; cell < this.size; cell++) {
      if (!this.free[cell]) continue;
      const x = cell % width;
      const y = Math.floor(cell / width);
      for (const [dx, dy] of actions) {
        const nx = x + dx;
        const ny = y + dy;
        if (nx >= 0 && nx < width && ny >= 0 && ny < height && this.free[ny * width + nx]) {
          this.neighbors[cell].push(ny * width + nx);
        }
      }
    }
  }

  degree(cell: number): number {
    return this.neighbors[cell].length - 1;
  }

  distances(goal: number): number[] {
    const distance = Array(this.size).fill(-1);
    const queue = [goal];
    distance[goal] = 0;
    for (let next = 0; next < queue.length; next++) {
      const cell = queue[next];
      for (const neighbor of this.neighbors[cell]) {
        if (distance[neighbor] !== -1) continue;
        distance[neighbor] = distance[cell] + 1;
        queue.push(neighbor);
      }
    }
    return distance;
  }
}

export function readInstance(): {grid: Grid; agents: Agent[]} {
  const map = lines('map.txt');
  const [width, height] = map[0].split(' ').map(Number);
  const grid = new Grid(width, height, map.slice(1));
  const agents = lines('agents.csv').slice(1).map(line => {
    const [number, sx, sy, gx, gy] = line.split(',').map(Number);
    const start = sy * width + sx;
    const goal = gy * width + gx;
    const distance = grid.distances(goal);
    return {number, name: String.fromCharCode(65 + number), start, goal, distance, shortest: distance[start]};
  });
  return {grid, agents};
}

