import type { Item, Monster, Position } from './entities.ts';
import type { Minstd } from './minstd.ts';

export interface GenerationConfig {
  width: number;
  height: number;
  minimum: number;
  splits: number;
  roomMin: number;
  roomMax: number;
}
interface Region {
  x: number;
  y: number;
  w: number;
  h: number;
  rooms: number[];
  children?: [Region, Region];
}
export interface Room {
  x: number;
  y: number;
  w: number;
  h: number;
  cx: number;
  cy: number;
}
export interface RoomCell extends Position {
  room: number;
}
export class Level {
  terrain: string[];
  memory: string[];
  rooms: Room[] = [];
  monsters: Monster[] = [];
  items: Item[] = [];
  arrival: RoomCell;
  target: RoomCell;
  killed = 0;
  picked = 0;
  created = 0;
  placed = 0;
  constructor(
    readonly width: number,
    readonly height: number,
    config: GenerationConfig,
    rng: Minstd,
  ) {
    this.terrain = Array<string>(width * height).fill(' ');
    this.memory = Array<string>(width * height).fill(' ');
    const leaves: Region[] = [];
    const split = (x: number, y: number, w: number, h: number, depth: number): Region => {
      const node: Region = { x, y, w, h, rooms: [] };
      const cv = w >= 2 * config.minimum;
      const ch = h >= 2 * config.minimum;
      if (depth === config.splits || (!cv && !ch)) {
        node.rooms.push(leaves.length);
        leaves.push(node);
        return node;
      }
      let vertical: boolean;
      if (cv && ch) vertical = 4 * w >= 5 * h ? true : 4 * h >= 5 * w ? false : rng.rnd(2) === 0;
      else vertical = cv;
      const c = config.minimum + rng.rnd((vertical ? w : h) - 2 * config.minimum + 1);
      const a = split(x, y, vertical ? c : w, vertical ? h : c, depth + 1);
      const b = split(
        vertical ? x + c : x,
        vertical ? y : y + c,
        vertical ? w - c : w,
        vertical ? h : h - c,
        depth + 1,
      );
      node.children = [a, b];
      node.rooms = [...a.rooms, ...b.rooms];
      return node;
    };
    const root = split(0, 0, width, height, 0);
    for (const leaf of leaves) {
      const w = config.roomMin + rng.rnd(Math.min(config.roomMax, leaf.w - 1) - config.roomMin + 1);
      const h = config.roomMin + rng.rnd(Math.min(config.roomMax, leaf.h - 1) - config.roomMin + 1);
      const x = leaf.x + rng.rnd(leaf.w - w);
      const y = leaf.y + rng.rnd(leaf.h - h);
      this.rooms.push({ x, y, w, h, cx: x + Math.floor(w / 2), cy: y + Math.floor(h / 2) });
      for (let yy = y; yy < y + h; yy++) {
        for (let xx = x; xx < x + w; xx++) {
          this.terrain[this.index(xx, yy)] =
            yy === y || yy === y + h - 1 ? '-' : xx === x || xx === x + w - 1 ? '|' : '.';
        }
      }
    }
    const carve = (x: number, y: number) => {
      const i = this.index(x, y);
      const cell = this.terrain[i];
      if (cell === ' ') this.terrain[i] = '#';
      else if (cell === '-' || cell === '|') this.terrain[i] = '+';
    };
    const segment = (x: number, y: number, endX: number, endY: number) => {
      const dx = Math.sign(endX - x);
      const dy = Math.sign(endY - y);
      carve(x, y);
      while (x !== endX || y !== endY) {
        x += dx;
        y += dy;
        carve(x, y);
      }
    };
    const connect = (node: Region): void => {
      if (!node.children) return;
      const [first, second] = node.children;
      connect(first);
      connect(second);
      let distance = width + height;
      let a = this.rooms[first.rooms[0]];
      let b = this.rooms[second.rooms[0]];
      for (const i of first.rooms) {
        for (const j of second.rooms) {
          const aa = this.rooms[i];
          const bb = this.rooms[j];
          const d = Math.abs(aa.cx - bb.cx) + Math.abs(aa.cy - bb.cy);
          if (d < distance) {
            distance = d;
            a = aa;
            b = bb;
          }
        }
      }
      if (rng.rnd(2) === 0) {
        segment(a.cx, a.cy, b.cx, a.cy);
        segment(b.cx, a.cy, b.cx, b.cy);
      } else {
        segment(a.cx, a.cy, a.cx, b.cy);
        segment(a.cx, b.cy, b.cx, b.cy);
      }
    };
    connect(root);
    this.arrival = this.drawCell(rng);
    this.terrain[this.index(this.arrival.x, this.arrival.y)] = '<';
    let targetRoom = rng.rnd(this.rooms.length - 1);
    if (targetRoom >= this.arrival.room) targetRoom++;
    this.target = this.drawInterior(targetRoom, rng);
  }
  index(x: number, y: number): number {
    return y * this.width + x;
  }
  at(x: number, y: number): string {
    return this.terrain[this.index(x, y)];
  }
  drawInterior(room: number, rng: Minstd): RoomCell {
    const r = this.rooms[room];
    const x = r.x + 1 + rng.rnd(r.w - 2);
    const y = r.y + 1 + rng.rnd(r.h - 2);
    return { room, x, y };
  }
  drawCell(rng: Minstd): RoomCell {
    return this.drawInterior(rng.rnd(this.rooms.length), rng);
  }
  monsterAt(x: number, y: number): Monster | undefined {
    return this.monsters.find((m) => m.x === x && m.y === y);
  }
  itemAt(x: number, y: number): Item | undefined {
    return this.items.find((item) => item.x === x && item.y === y);
  }
}
