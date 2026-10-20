import type { Point } from './dataset.ts';

export interface Cell { column: number; row: number; points: Point[] }
export class Grid {
    side: number;
    cells: Cell[] = [];
    constructor(points: Point[], world: number, public size: number) {
        this.side = world / size;
        for (let row = 0; row < this.side; row++) for (let column = 0; column < this.side; column++) this.cells.push({ column, row, points: [] });
        for (const p of points) this.insert(p);
    }
    cell(point: Point): Cell { return this.cells[Math.floor(point.y / this.size) * this.side + Math.floor(point.x / this.size)]; }
    insert(point: Point): void { const cell = this.cell(point); cell.points.push(point); cell.points.sort((a, b) => a.id - b.id); }
    remove(point: Point): void { const cell = this.cell(point); cell.points.splice(cell.points.findIndex(p => p.id === point.id), 1); }
}
