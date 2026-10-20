import { addObject, freeAmount, collectionRecord, type HeapObject, type Heap, type CollectionRecord, type Collector, type Pair } from './heap.ts';
export class Copying implements Collector {
    half: number;
    base = 0;
    top = 0;
    constructor(public heap: Heap, public roots: (HeapObject | null)[]) { this.half = heap.size / 2; }
    inactive(): Pair { const start = this.half - this.base; return [start, start + this.half]; }
    freeList() { const length = this.base + this.half - this.top; return length > 0 ? [{ address: this.top, length }] : []; }
    claim(size: number) { if (this.top + size > this.base + this.half) return null; const address = this.top; this.top += size; return address; }
    collect(rec: CollectionRecord) {
        this.base = this.half - this.base; this.top = this.base;
        const copied = new Set<HeapObject>(), queue: HeapObject[] = [];
        const copy = (o: HeapObject | null) => {
            if (!o || copied.has(o)) return;
            copied.add(o); o.address = this.top; this.top += o.size; o.moves++; addObject(rec.live, o); addObject(rec.moved, o); queue.push(o);
        };
        rec.work += this.roots.length;
        for (const root of this.roots) copy(root);
        for (let i = 0; i < queue.length; i++) { const o = queue[i]; rec.work += o.size + o.pointers; for (const v of o.fields) copy(v); }
        for (const o of this.heap.objects.values()) if (!copied.has(o)) { this.heap.objects.delete(o.number); addObject(rec.freed, o); }
    }
    allocate(size: number, line: number, record: (r: CollectionRecord) => void) {
        const address = this.claim(size); if (address !== null) return address;
        const rec = collectionRecord(line, size, 'copy', this.freeList()); this.collect(rec); rec.after = freeAmount(this.freeList()); record(rec); return this.claim(size);
    }
}
