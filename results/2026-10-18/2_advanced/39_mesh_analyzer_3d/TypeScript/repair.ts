import type { Face, Polygon, Triple } from './obj_io.ts';
import { normal } from './measure.ts';

export interface Triangle { number: number; vertices: Triple; polygon: Polygon }
export function triangulate(polygons: Polygon[]): Triangle[] {
    const triangles: Triangle[] = [];
    for (const polygon of polygons) for (let i = 1; i < polygon.vertices.length - 1; i++) triangles.push({ number: triangles.length + 1,
        vertices: [polygon.vertices[0], polygon.vertices[i], polygon.vertices[i + 1]], polygon });
    return triangles;
}
export function snap(vertices: Triple[], spacing: number) {
    const positions: Triple[] = [[0, 0, 0]], changed: { original: number; before: Triple; after: Triple }[] = [];
    const coordinate = (x: number) => spacing * Math.floor((2 * x + spacing) / (2 * spacing));
    for (let original = 1; original < vertices.length; original++) {
        const [x, y, z] = vertices[original], position: Triple = [coordinate(x), coordinate(y), coordinate(z)]; positions.push(position);
        if (position.some((value, k) => value !== vertices[original][k])) changed.push({ original, before: vertices[original], after: position });
    }
    return { positions, changed };
}
export function representatives(vertices: Triple[], merge: boolean) {
    const numbers = [0], first = new Map<string, number>(), groups = new Map<number, number[]>();
    let merged = 0;
    for (let original = 1; original < vertices.length; original++) {
        const key = vertices[original].join(',');
        if (!first.has(key)) first.set(key, original);
        const representative = merge ? first.get(key)! : original; numbers.push(representative);
        if (!groups.has(representative)) groups.set(representative, []);
        groups.get(representative)!.push(original); if (representative !== original) merged++;
    }
    return { numbers, groups, merged };
}
export function removeTriangles(triangles: Triangle[], representatives: number[], positions: Triple[], settings: { degenerate: boolean; duplicates: boolean }) {
    const faces: Face[] = [], removed: { triangle: Triangle; reason: 'repeated' | 'zero_area' | 'duplicate' }[] = [], seen = new Set<string>();
    for (const triangle of triangles) {
        const [a, b, c] = triangle.vertices, vertices: Triple = [representatives[a], representatives[b], representatives[c]], key = [...vertices].sort((a, b) => a - b).join(',');
        let reason: 'repeated' | 'zero_area' | 'duplicate' | null = null;
        if (new Set(vertices).size < 3) reason = 'repeated';
        else if (settings.degenerate && normal({ vertices }, positions).every(value => value === 0)) reason = 'zero_area';
        else if (settings.duplicates && seen.has(key)) reason = 'duplicate';
        if (reason !== null) removed.push({ triangle, reason });
        else { seen.add(key); faces.push({ number: faces.length + 1, vertices, group: triangle.polygon.group, polygon: triangle.polygon }); }
    }
    return { faces, removed };
}
export function fillTriangles(vertices: number[]): Face[] {
    const faces: Face[] = [];
    for (let i = 1; i < vertices.length - 1; i++) faces.push({ number: 0, vertices: [vertices[0], vertices[i + 1], vertices[i]], group: 'fill', polygon: null });
    return faces;
}
