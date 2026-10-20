export type Connectivity = 4 | 8;
export type Offset = readonly [number, number];
export const DIRECTIONS: Record<Connectivity, readonly Offset[]> = {
    4: [[1, 0], [0, -1], [-1, 0], [0, 1]],
    8: [[1, 0], [1, -1], [0, -1], [-1, -1], [-1, 0], [-1, 1], [0, 1], [1, 1]],
};
export function complement(c: Connectivity): Connectivity { return c === 4 ? 8 : 4; }
export interface Labeling { labels: Int32Array; components: number[][]; provisional: number }
export function label(mask: Uint8Array, width: number, height: number, connectivity: Connectivity): Labeling {
    const provisional = new Int32Array(mask.length), parents = [0];
    const preceding: Offset[] = connectivity === 4 ? [[-1, 0], [0, -1]] : [[-1, 0], [-1, -1], [0, -1], [1, -1]];
    function find(value: number): number {
        let root = value;
        while (parents[root] !== root) root = parents[root];
        while (value !== root) { const next = parents[value]; parents[value] = root; value = next; }
        return root;
    }
    for (let y = 0; y < height; y++) for (let x = 0; x < width; x++) {
        const index = y * width + x;
        if (!mask[index]) continue;
        const neighbors: number[] = [];
        for (const [dx, dy] of preceding) {
            const nx = x + dx, ny = y + dy;
            if (nx >= 0 && nx < width && ny >= 0 && ny < height && provisional[ny * width + nx]) neighbors.push(provisional[ny * width + nx]);
        }
        if (!neighbors.length) { provisional[index] = parents.length; parents.push(parents.length); }
        else {
            provisional[index] = Math.min(...neighbors);
            for (const other of neighbors) {
                const a = find(provisional[index]), b = find(other);
                parents[Math.max(a, b)] = Math.min(a, b);
            }
        }
    }
    const labels = new Int32Array(mask.length), components: number[][] = [], numbers = new Map<number, number>();
    for (let i = 0; i < mask.length; i++) {
        if (!provisional[i]) continue;
        const root = find(provisional[i]);
        let number = numbers.get(root);
        if (number === undefined) { number = components.length + 1; numbers.set(root, number); components.push([]); }
        labels[i] = number; components[number - 1].push(i);
    }
    return { labels, components, provisional: parents.length - 1 };
}
export function bitQuadEuler(mask: Uint8Array, w: number, h: number, c: Connectivity): number {
    const at = (x: number, y: number) => x >= 0 && x < w && y >= 0 && y < h ? mask[y * w + x] : 0;
    let q1 = 0, q3 = 0, qd = 0;
    for (let y = -1; y < h; y++) for (let x = -1; x < w; x++) {
        const a = at(x, y), b = at(x + 1, y), d = at(x, y + 1), e = at(x + 1, y + 1), n = a + b + d + e;
        if (n === 1) q1++;
        if (n === 3) q3++;
        if (n === 2 && ((a && e) || (b && d))) qd++;
    }
    return (q1 - q3 + (c === 8 ? -2 : 2) * qd) / 4;
}
