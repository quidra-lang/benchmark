import { isWhite } from './grid.ts';
export type Axis = 'A' | 'D';
export interface Run { r: number; c: number; axis: Axis; cells: number[]; length: number }
export interface Slot extends Run { number: number; label: string; index: number; crossing: number[] }
export interface SlotLayout { slots: Slot[]; numbers: number[]; membership: number[][] }
export function runs(rows: string[]): Run[] {
    const result: Run[] = [], h = rows.length, w = rows[0].length;
    const axes: Axis[] = ['A', 'D'];
    for (let r = 0; r < h; r++) for (let c = 0; c < w; c++) {
        if (!isWhite(rows[r][c])) continue;
        for (const axis of axes) {
            const dr = axis === 'D' ? 1 : 0, dc = axis === 'A' ? 1 : 0;
            if (r - dr >= 0 && c - dc >= 0 && isWhite(rows[r - dr][c - dc])) continue;
            const cells: number[] = [];
            for (let rr = r, cc = c; rr < h && cc < w && isWhite(rows[rr][cc]); rr += dr, cc += dc) cells.push(rr * w + cc);
            result.push({ r, c, axis, cells, length: cells.length });
        }
    }
    return result;
}
export function shortRun(allRuns: Run[]): Run | undefined { return allRuns.find(run => run.length === 2); }
export function extractSlots(rows: string[], allRuns: Run[]): SlotLayout {
    const numbers: number[] = Array(rows.length * rows[0].length).fill(0), membership: number[][] = numbers.map(() => []), slots: Slot[] = [];
    let number = 0;
    for (const run of allRuns) {
        if (run.length < 3) continue;
        const first = run.cells[0];
        if (!numbers[first]) numbers[first] = ++number;
        const slot: Slot = { ...run, number: numbers[first], label: `${numbers[first]}${run.axis}`, index: slots.length, crossing: [] };
        slots.push(slot);
        for (const cell of slot.cells) membership[cell].push(slot.index);
    }
    for (const slot of slots) slot.crossing = [...new Set(slot.cells.flatMap(cell => membership[cell]).filter(i => i !== slot.index))].sort((a, b) => a - b);
    return { slots, numbers, membership };
}
