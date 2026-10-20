import type { GridMap } from './grid_map.ts';
export const DIRECTIONS = [{ x: 0, y: -1, symbol: '^' }, { x: 1, y: 0, symbol: '>' }, { x: 0, y: 1, symbol: 'v' }, { x: -1, y: 0, symbol: '<' }];
export function distanceField(map: GridMap, blocked: ReadonlySet<number> | ReadonlyMap<number, unknown>) {
    const distances: number[] = Array(map.cells.length).fill(-1), queue = [map.exit];
    distances[map.exit] = 0;
    for (let i = 0; i < queue.length; i++) {
        const cell = queue[i], p = map.coordinates(cell);
        for (const d of DIRECTIONS) {
            const x = p.x + d.x, y = p.y + d.y;
            if (!map.inside(x, y)) continue;
            const next = map.cell(x, y);
            if (map.rock(next) || blocked.has(next) || distances[next] !== -1) continue;
            distances[next] = distances[cell] + 1; queue.push(next);
        }
    }
    return distances;
}
export function nextCell(map: GridMap, distances: number[], cell: number) {
    const p = map.coordinates(cell);
    let best = -1;
    for (const d of DIRECTIONS) {
        const x = p.x + d.x, y = p.y + d.y;
        if (!map.inside(x, y)) continue;
        const next = map.cell(x, y);
        if (distances[next] >= 0 && (best < 0 || distances[next] < distances[best])) best = next;
    }
    return best;
}
export function spawnPath(map: GridMap, distances: number[], spawn: number) {
    const path = [spawn];
    while (path[path.length - 1] !== map.exit) path.push(nextCell(map, distances, path[path.length - 1]));
    return path;
}
