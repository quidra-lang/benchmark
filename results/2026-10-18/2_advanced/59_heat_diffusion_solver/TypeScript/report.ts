import { mkdirSync, writeFileSync } from 'node:fs';
import type { Mesh } from './mesh.ts';

export function fixed(value: number, places: number): string {
    let result: string;
    if (Math.abs(value) < 1e21) result = value.toFixed(places);
    else result = (value < 0 ? '-' : '') + BigInt(Math.abs(value)).toString() + (places ? '.' + '0'.repeat(places) : '');
    return /^-0(?:\.0+)?$/.test(result) ? result.slice(1) : result;
}
export const time = (milliseconds: number): string => Math.floor(milliseconds / 1000) + '.' + String(milliseconds % 1000).padStart(3, '0');
export function temperatureRows(mesh: Mesh, field: number[]): string[] {
    return Array.from({ length: mesh.height }, (_, r) => field.slice(r * mesh.width, (r + 1) * mesh.width).map(t => fixed(t, 2)).join(' '));
}
export function isothermRows(mesh: Mesh, field: number[], bands: number[]): { counts: number[]; lines: string[] } {
    let hottest = 0; for (let p = 1; p < mesh.count; p++) if (field[p] > field[hottest]) hottest = p;
    const counts: number[] = Array(bands.length + 1).fill(0), characters = field.map((value, p) => {
        let digit = 0; for (const boundary of bands) if (boundary <= value) digit++; counts[digit]++; return p === hottest ? '*' : String(digit);
    });
    return { counts, lines: Array.from({ length: mesh.height }, (_, r) => characters.slice(r * mesh.width, (r + 1) * mesh.width).join('')) };
}
export function writeFiles(files: Record<string, string[]>): void {
    mkdirSync('output', { recursive: true }); for (const [name, lines] of Object.entries(files)) writeFileSync('output/' + name, lines.join('\n') + '\n', 'ascii');
}
