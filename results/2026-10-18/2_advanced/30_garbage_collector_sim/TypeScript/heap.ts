export type Pair = [number, number];
export interface HeapObject {
  number: number;
  pointers: number;
  data: number;
  size: number;
  fields: (HeapObject | null)[];
  address: number;
  moves: number;
  age: number;
  references: number;
  birth: number;
  death: number | null;
  lifetime: number | null;
}
export interface Heap {
  size: number;
  objects: Map<number, HeapObject>;
}
export interface FreeBlock {
  address: number;
  length: number;
}
export type CollectionKind =
  'sweep' | 'compact' | 'copy' | 'minor' | 'major' | 'tenure' | 'full' | 'backup';
export interface CollectionRecord {
  number: number;
  line: number;
  request: number;
  kind: CollectionKind;
  live: Pair;
  freed: Pair;
  moved: Pair;
  promoted: Pair;
  stack: number;
  work: number;
  before: Pair;
  after: Pair;
}
export interface Collector {
  freeList(): FreeBlock[];
  allocate(size: number, line: number, record: (r: CollectionRecord) => void): number | null;
  inactive(): Pair | null;
}
export function createObject(number: number, pointers: number, data: number): HeapObject {
  return {
    number,
    pointers,
    data,
    size: 1 + pointers + data,
    fields: Array(pointers).fill(null),
    address: 0,
    moves: 0,
    age: 0,
    references: 0,
    birth: 0,
    death: null,
    lifetime: null,
  };
}
export function addObject(pair: Pair, object: HeapObject) {
  pair[0]++;
  pair[1] += object.size;
}
export function objectPair(objects: Iterable<HeapObject>): Pair {
  const pair: Pair = [0, 0];
  for (const o of objects) addObject(pair, o);
  return pair;
}
export function freeBlocks(objects: Iterable<HeapObject>, start: number, end: number) {
  const occupied = [...objects]
    .filter((o) => o.address >= start && o.address < end)
    .sort((a, b) => a.address - b.address);
  const blocks: FreeBlock[] = [];
  let address = start;
  for (const o of occupied) {
    if (o.address > address) blocks.push({ address, length: o.address - address });
    address = o.address + o.size;
  }
  if (address < end) blocks.push({ address, length: end - address });
  return blocks;
}
export const firstFit = (blocks: FreeBlock[], size: number) =>
  blocks.find((b) => b.length >= size)?.address ?? null;
export function freeAmount(blocks: FreeBlock[]): Pair {
  let total = 0;
  let largest = 0;
  for (const b of blocks) {
    total += b.length;
    largest = Math.max(largest, b.length);
  }
  return [total, largest];
}
export function collectionRecord(
  line: number,
  request: number,
  kind: CollectionKind,
  blocks: FreeBlock[],
): CollectionRecord {
  return {
    number: 0,
    line,
    request,
    kind,
    live: [0, 0],
    freed: [0, 0],
    moved: [0, 0],
    promoted: [0, 0],
    stack: 0,
    work: 0,
    before: freeAmount(blocks),
    after: [0, 0],
  };
}
export function dec2(a: number, b: number) {
  const z = Math.floor((200 * a + b) / (2 * b));
  return `${Math.floor(z / 100)}.${String(z % 100).padStart(2, '0')}`;
}
export const pct = (a: number, b: number) => (b === 0 ? '-' : dec2(100 * a, b));
export function classTable(values: Iterable<number>) {
  const counts = [0, 0, 0, 0, 0];
  for (const n of values) counts[n === 1 ? 0 : n <= 3 ? 1 : n <= 7 ? 2 : n <= 15 ? 3 : 4]++;
  return ['1', '2-3', '4-7', '8-15', '16+'].map((s, i) => `${s}:${counts[i]}`).join(' ');
}
export function heapMap(heap: Heap, inactive: Pair | null, reachable: Set<number>, width: number) {
  const words: string[] = Array(heap.size).fill('.');
  if (inactive) words.fill('-', inactive[0], inactive[1]);
  for (const o of heap.objects.values()) {
    const live = reachable.has(o.number);
    const letter = (o.number - 1) % 26;
    words[o.address] = live ? String.fromCharCode(65 + letter) : '#';
    words.fill(live ? String.fromCharCode(97 + letter) : '=', o.address + 1, o.address + o.size);
  }
  const lines: string[] = [];
  for (let a = 0; a < heap.size; a += width) {
    lines.push(`${String(a).padStart(4, '0')} ${words.slice(a, a + width).join('')}`);
  }
  return lines;
}
