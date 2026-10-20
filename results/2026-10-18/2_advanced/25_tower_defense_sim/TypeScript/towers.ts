import type { GridMap } from './grid_map.ts';
import { position, remainingDistance, type Enemy } from './enemies.ts';
import { squaredDistance } from './combat.ts';
export type Targets = 'ground' | 'air' | 'both';
export type Mode = 'FIRST' | 'LAST' | 'STRONGEST' | 'WEAKEST' | 'CLOSEST';
export const isMode = (text: string): text is Mode => ['FIRST', 'LAST', 'STRONGEST', 'WEAKEST', 'CLOSEST'].includes(text);
export interface Performance { cost: number; range: number; power: number; interval: number; shotSpeed: number; splash: number; slowRate: number; slowTime: number; burnAmount: number; burnTime: number }
export interface TowerType { name: string; symbol: string; targets: Targets; levels: Performance[] }
export interface Tower { number: number; type: TowerType; x: number; y: number; cell: number; level: number; mode: Mode; ready: number; investment: number; built: number; sold: number | null; shots: number; hits: number; fizzles: number; kills: number; damage: number }
export function parseTowerType(header: string[], rows: string[][]): TowerType {
    const levels = rows.map(f => {
        const [cost, range, power, interval, shotSpeed, splash, slowRate, slowTime, burnAmount, burnTime] = f.slice(1).map(Number);
        return { cost, range, power, interval, shotSpeed, splash, slowRate, slowTime, burnAmount, burnTime };
    });
    const targets: Targets = header[3] === 'ground' ? 'ground' : header[3] === 'air' ? 'air' : 'both';
    return { name: header[1], symbol: header[2], targets, levels };
}
export function createTower(number: number, type: TowerType, x: number, y: number, map: GridMap, tick: number): Tower {
    return { number, type, x, y, cell: map.cell(x, y), level: 1, mode: 'FIRST', ready: tick, investment: type.levels[0].cost, built: tick, sold: null,
        shots: 0, hits: 0, fizzles: 0, kills: 0, damage: 0 };
}
export const canAim = (targets: Targets, enemy: Enemy) => targets === 'both' || targets === enemy.type.movement;
export function withinRange(tower: Tower, enemy: Enemy, map: GridMap) {
    const range = tower.type.levels[tower.level - 1].range;
    return squaredDistance(map.center(tower.cell), position(enemy, map)) <= range * range;
}
export function chooseTarget(tower: Tower, enemies: Iterable<Enemy>, map: GridMap, distances: number[]) {
    let best: Enemy | null = null, bestValue = 0;
    for (const enemy of enemies) {
        if (!enemy.alive || !canAim(tower.type.targets, enemy) || !withinRange(tower, enemy, map)) continue;
        let value: number;
        switch (tower.mode) {
            case 'FIRST': value = remainingDistance(enemy, map, distances); break;
            case 'LAST': value = -remainingDistance(enemy, map, distances); break;
            case 'STRONGEST': value = -enemy.hp; break;
            case 'WEAKEST': value = enemy.hp; break;
            case 'CLOSEST': value = squaredDistance(map.center(tower.cell), position(enemy, map)); break;
        }
        if (!best || value < bestValue || (value === bestValue && enemy.number < best.number)) { best = enemy; bestValue = value; }
    }
    return best;
}
