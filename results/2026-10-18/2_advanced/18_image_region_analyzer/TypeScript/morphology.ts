import type { Offset } from './labeling.ts';
export type MorphOperation = 'erode' | 'dilate' | 'open' | 'close';
function at(mask: Uint8Array, x: number, y: number, w: number, h: number): number {
    return x >= 0 && x < w && y >= 0 && y < h ? mask[y * w + x] : 0;
}
function transform(mask: Uint8Array, w: number, h: number, offsets: Offset[], erosion: boolean): Uint8Array {
    const result = new Uint8Array(mask.length);
    for (let y = 0; y < h; y++) for (let x = 0; x < w; x++) {
        const values = offsets.map(([dx, dy]) => at(mask, x + (erosion ? dx : -dx), y + (erosion ? dy : -dy), w, h));
        result[y * w + x] = Number(erosion ? values.every(Boolean) : values.some(Boolean));
    }
    return result;
}
export function applyMorphology(mask: Uint8Array, w: number, h: number, offsets: Offset[], operation: MorphOperation): Uint8Array {
    const erode = (source: Uint8Array) => transform(source, w, h, offsets, true);
    const dilate = (source: Uint8Array) => transform(source, w, h, offsets, false);
    switch (operation) {
        case 'erode': return erode(mask);
        case 'dilate': return dilate(mask);
        case 'open': return dilate(erode(mask));
        case 'close': return erode(dilate(mask));
    }
}
export function neighborhood(mask: Uint8Array, x: number, y: number, w: number, h: number): number[] {
    return [[0, -1], [1, -1], [1, 0], [1, 1], [0, 1], [-1, 1], [-1, 0], [-1, -1]].map(([dx, dy]) => at(mask, x + dx, y + dy, w, h));
}
export function transitions(values: number[]): number {
    return values.reduce((count, value, i) => count + Number(value === 0 && values[(i + 1) % values.length] === 1), 0);
}
export function thin(mask: Uint8Array, w: number, h: number): Uint8Array {
    const result = new Uint8Array(mask);
    while (true) {
        let removed = 0;
        for (let step = 0; step < 2; step++) {
            const pending: number[] = [];
            for (let y = 0; y < h; y++) for (let x = 0; x < w; x++) {
                const i = y * w + x;
                if (!result[i]) continue;
                const p = neighborhood(result, x, y, w, h), count = p.reduce((a, b) => a + b, 0);
                if (count < 2 || count > 6 || transitions(p) !== 1) continue;
                if (step === 0 ? p[0] * p[2] * p[4] || p[2] * p[4] * p[6] : p[0] * p[2] * p[6] || p[0] * p[4] * p[6]) continue;
                pending.push(i);
            }
            for (const i of pending) result[i] = 0;
            removed += pending.length;
        }
        if (!removed) return result;
    }
}
