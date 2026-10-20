import type { Point } from './grid_map.ts';
import type { Tower, Performance, Targets } from './towers.ts';
import type { Enemy } from './enemies.ts';
export function isqrt(value: number) {
    let low = 0, high = value + 1;
    while (low + 1 < high) {
        const middle = Math.floor((low + high) / 2);
        if (middle <= Math.floor(value / middle)) low = middle; else high = middle;
    }
    return low;
}
export function squaredDistance(a: Point, b: Point) { const dx = a.x - b.x, dy = a.y - b.y; return dx * dx + dy * dy; }
export function advancePoint(point: Point, target: Point, speed: number) {
    const dx = target.x - point.x, dy = target.y - point.y, distance = dx * dx + dy * dy;
    if (distance <= speed * speed) return { point: { ...target }, arrived: true };
    const length = isqrt(distance);
    const move = (d: number) => d >= 0 ? Math.floor(d * speed / length) : -Math.floor(-d * speed / length);
    return { point: { x: point.x + move(dx), y: point.y + move(dy) }, arrived: false };
}
export interface Effect { strength: number; remaining: number; source: Tower | null }
export const newEffect = (): Effect => ({ strength: 0, remaining: 0, source: null });
export function receiveEffect(effect: Effect, strength: number, duration: number, source: Tower | null = null) {
    if (strength > effect.strength) { effect.strength = strength; effect.remaining = duration; effect.source = source; }
    else if (strength === effect.strength) effect.remaining = Math.max(effect.remaining, duration);
}
export function advanceEffect(effect: Effect) {
    effect.remaining--;
    if (effect.remaining === 0) { effect.strength = 0; effect.source = null; }
}
export const armoredDamage = (hp: number, power: number, armor: number) => Math.min(hp, Math.max(1, power - armor));
export interface Projectile { number: number; tower: Tower; target: Enemy; point: Point; aim: Point; performance: Performance; targets: Targets }
export function createProjectile(number: number, tower: Tower, target: Enemy, point: Point, aim: Point): Projectile {
    return { number, tower, target, point: { ...point }, aim: { ...aim }, performance: { ...tower.type.levels[tower.level - 1] }, targets: tower.type.targets };
}
export function moveProjectile(p: Projectile, targetPosition: Point | null) {
    if (targetPosition) p.aim = { ...targetPosition };
    if (p.performance.shotSpeed === 0) return true;
    const moved = advancePoint(p.point, p.aim, p.performance.shotSpeed);
    p.point = moved.point;
    return moved.arrived;
}
