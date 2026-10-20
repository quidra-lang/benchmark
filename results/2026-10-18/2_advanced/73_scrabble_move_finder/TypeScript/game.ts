import type { Table } from './scoring.ts';
export class Minstd { constructor(private state: number) {} next() { this.state = (48271 * this.state) % 2147483647; return this.state; } }
export function shuffle(bag: string[], random: Minstd) { for (let i = bag.length - 1; i >= 1; i--) { const j = random.next() % (i + 1); [bag[i], bag[j]] = [bag[j], bag[i]]; } }
export function makeBag(table: Table, random: Minstd) { const bag: string[] = []; for (const [letter, tile] of table) for (let i = 0; i < tile.count; i++) bag.push(letter); shuffle(bag, random); return bag; }
export function draw(bag: string[], count: number) { let tiles = ''; for (let i = 0; i < count && bag.length; i++) tiles += bag.pop()!; return tiles; }
export function exchange(bag: string[], returned: string, random: Minstd) { const drawn = draw(bag, returned.length); bag.push(...Array.from(returned).sort()); shuffle(bag, random); return drawn; }
export function value(tiles: string, table: Table) { let total = 0; for (const tile of tiles) total += table.get(tile)!.value; return total; }
