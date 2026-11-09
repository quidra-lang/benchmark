import type { GridMap, Point } from './grid_map.ts';
import { nextCell } from './pathing.ts';
import { newEffect, advanceEffect, isqrt, squaredDistance, type Effect } from './combat.ts';
export interface EnemyType {
  name: string;
  symbol: string;
  movement: 'ground' | 'air';
  hp: number;
  armor: number;
  speed: number;
  bounty: number;
  lives: number;
  regen: number;
  splitInto: EnemyType | null;
  splitCount: number;
  spawned: number;
  killed: number;
  leaked: number;
  damage: number;
}
export interface Group {
  type: EnemyType;
  spawn: number;
  count: number;
  delay: number;
  interval: number;
  multiplier: number;
}
export type Travel =
  | { kind: 'ground'; current: number; next: number; progress: number }
  | { kind: 'air'; point: Point };
export interface Enemy {
  number: number;
  type: EnemyType;
  multiplier: number;
  maximum: number;
  hp: number;
  alive: boolean;
  slow: Effect;
  burn: Effect;
  travel: Travel;
}
export function parseEnemyType(f: string[], known: Map<string, EnemyType>): EnemyType {
  return {
    name: f[1],
    symbol: f[2],
    movement: f[3] === 'ground' ? 'ground' : 'air',
    hp: Number(f[4]),
    armor: Number(f[5]),
    speed: Number(f[6]),
    bounty: Number(f[7]),
    lives: Number(f[8]),
    regen: Number(f[9]),
    splitInto: f[10] === '-' ? null : known.get(f[10])!,
    splitCount: Number(f[11]),
    spawned: 0,
    killed: 0,
    leaked: 0,
    damage: 0,
  };
}
export function parseGroup(f: string[], known: Map<string, EnemyType>): Group {
  return {
    type: known.get(f[1])!,
    spawn: Number(f[2]),
    count: Number(f[3]),
    delay: Number(f[4]),
    interval: Number(f[5]),
    multiplier: Number(f[6]),
  };
}
function newEnemy(number: number, type: EnemyType, multiplier: number, travel: Travel): Enemy {
  const maximum = Math.floor((type.hp * multiplier) / 100);
  return {
    number,
    type,
    multiplier,
    maximum,
    hp: maximum,
    alive: true,
    slow: newEffect(),
    burn: newEffect(),
    travel,
  };
}
export function spawnEnemy(
  number: number,
  type: EnemyType,
  multiplier: number,
  spawn: number,
  map: GridMap,
  distances: number[],
) {
  return newEnemy(
    number,
    type,
    multiplier,
    type.movement === 'ground'
      ? { kind: 'ground', current: spawn, next: nextCell(map, distances, spawn), progress: 0 }
      : { kind: 'air', point: map.center(spawn) },
  );
}
export function splitEnemy(number: number, type: EnemyType, parent: Enemy) {
  const travel: Travel =
    parent.travel.kind === 'ground'
      ? { ...parent.travel }
      : { kind: 'air', point: { ...parent.travel.point } };
  return newEnemy(number, type, parent.multiplier, travel);
}
export function position(enemy: Enemy, map: GridMap): Point {
  const t = enemy.travel;
  if (t.kind === 'air') return t.point;
  const c = map.coordinates(t.current);
  const n = map.coordinates(t.next);
  return { x: 100 * c.x + (n.x - c.x) * t.progress, y: 100 * c.y + (n.y - c.y) * t.progress };
}
export function occupiedCell(enemy: Enemy, map: GridMap) {
  const t = enemy.travel;
  return t.kind === 'ground'
    ? t.progress < 50
      ? t.current
      : t.next
    : map.cell(Math.floor((t.point.x + 50) / 100), Math.floor((t.point.y + 50) / 100));
}
export function remainingDistance(enemy: Enemy, map: GridMap, distances: number[]) {
  const t = enemy.travel;
  return t.kind === 'ground'
    ? 100 * distances[t.next] + 100 - t.progress
    : isqrt(squaredDistance(t.point, map.center(map.exit)));
}
export function slowedSpeed(enemy: Enemy) {
  let speed = enemy.type.speed;
  if (enemy.slow.remaining > 0) {
    speed = Math.floor((speed * (100 - enemy.slow.strength)) / 100);
    advanceEffect(enemy.slow);
  }
  return speed;
}
