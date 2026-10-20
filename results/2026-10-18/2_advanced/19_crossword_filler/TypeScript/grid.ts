export type Symmetry = 'rot180' | 'mirror' | 'none';
export interface Cell { r: number; c: number }
export const isWhite = (cell: string): boolean => cell !== '#';
export function firstAsymmetry(rows: string[], kind: Exclude<Symmetry, 'none'>): Cell | null {
    for (let r = 0; r < rows.length; r++) for (let c = 0; c < rows[r].length; c++) {
        const rr = kind === 'rot180' ? rows.length - 1 - r : r, cc = rows[r].length - 1 - c;
        if (isWhite(rows[r][c]) !== isWhite(rows[rr][cc])) return { r, c };
    }
    return null;
}
export function componentCount(rows: string[]): number {
    const h = rows.length, w = rows[0].length, seen = new Set<number>();
    let count = 0;
    for (let r = 0; r < h; r++) for (let c = 0; c < w; c++) {
        const i = r * w + c;
        if (!isWhite(rows[r][c]) || seen.has(i)) continue;
        count++; seen.add(i);
        const pending: Cell[] = [{ r, c }];
        for (let p = 0; p < pending.length; p++) {
            const cell = pending[p];
            for (const [dr, dc] of [[-1, 0], [1, 0], [0, -1], [0, 1]]) {
                const rr = cell.r + dr, cc = cell.c + dc, next = rr * w + cc;
                if (rr < 0 || rr >= h || cc < 0 || cc >= w || seen.has(next) || !isWhite(rows[rr][cc])) continue;
                seen.add(next); pending.push({ r: rr, c: cc });
            }
        }
    }
    return count;
}
