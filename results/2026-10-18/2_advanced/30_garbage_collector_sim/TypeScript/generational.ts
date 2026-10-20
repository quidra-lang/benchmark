import { addObject, freeBlocks, firstFit, freeAmount, collectionRecord, type HeapObject, type Heap, type CollectionRecord, type Collector, type Pair } from './heap.ts';
import { mark, sweep } from './mark_sweep.ts';
export class Generational implements Collector {
    half: number;
    base = 0;
    top = 0;
    remembered = new Set<HeapObject>();
    barriers = 0;
    remembers = 0;
    constructor(public heap: Heap, public roots: (HeapObject | null)[], public young: number, public promotionAge: number) { this.half = young / 2; }
    inactive(): Pair { const start = this.half - this.base; return [start, start + this.half]; }
    oldBlocks() { return freeBlocks(this.heap.objects.values(), this.young, this.heap.size); }
    freeList() { const blocks = this.oldBlocks(), length = this.base + this.half - this.top; if (length > 0) blocks.unshift({ address: this.top, length }); return blocks; }
    writeBarrier(o: HeapObject, v: HeapObject | null) {
        if (o.address < this.young) return;
        this.barriers++;
        if (v && v.address < this.young && !this.remembered.has(o)) { this.remembered.add(o); this.remembers++; }
    }
    claim(size: number) { if (this.top + size > this.base + this.half) return null; const address = this.top; this.top += size; return address; }
    collect(rec: CollectionRecord) {
        const major = rec.kind === 'major' || rec.kind === 'full';
        if (major) { const marked = mark(this.roots, rec); for (const o of sweep(this.heap, marked, rec, o => o.address >= this.young)) this.remembered.delete(o); }
        const remaining = new Set([...this.heap.objects.values()].filter(o => o.address < this.young)), queue: HeapObject[] = [];
        const dest = this.half - this.base;
        let top = dest;
        const evacuate = (o: HeapObject | null) => {
            if (!o || !remaining.has(o)) return true;
            remaining.delete(o); o.age++; o.moves++;
            if (rec.kind === 'tenure' || rec.kind === 'full' || o.age >= this.promotionAge) {
                const address = firstFit(this.oldBlocks(), o.size); if (address === null) return false;
                o.address = address; addObject(rec.promoted, o);
            } else { o.address = top; top += o.size; }
            addObject(rec.moved, o); if (!major) addObject(rec.live, o); queue.push(o); return true;
        };
        rec.work += this.roots.length;
        for (const root of this.roots) if (!evacuate(root)) return false;
        for (const o of [...this.remembered].sort((a, b) => a.address - b.address)) {
            rec.work += 1 + o.pointers; for (const v of o.fields) if (!evacuate(v)) return false;
        }
        for (let i = 0; i < queue.length; i++) { const o = queue[i]; rec.work += o.size + o.pointers; for (const v of o.fields) if (!evacuate(v)) return false; }
        for (const o of remaining) { this.heap.objects.delete(o.number); addObject(rec.freed, o); }
        this.base = dest; this.top = top;
        this.remembered = new Set([...this.heap.objects.values()].filter(o => o.address >= this.young && o.fields.some(v => v !== null && v.address < this.young)));
        return true;
    }
    allocate(size: number, line: number, record: (r: CollectionRecord) => void) {
        let address = this.claim(size); if (address !== null) return address;
        for (let attempt = 0; attempt < 2; attempt++) {
            const major = freeAmount(this.oldBlocks())[1] < this.top - this.base;
            const kind = attempt === 0 ? (major ? 'major' : 'minor') : (major ? 'full' : 'tenure');
            const rec = collectionRecord(line, size, kind, this.freeList());
            if (!this.collect(rec)) return null;
            rec.after = freeAmount(this.freeList()); record(rec); address = this.claim(size); if (address !== null) return address;
        }
        return null;
    }
}
