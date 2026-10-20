import { addObject, freeBlocks, firstFit, freeAmount, collectionRecord, type HeapObject, type Heap, type CollectionRecord, type CollectionKind, type Collector, type Pair } from './heap.ts';
export function mark(roots: (HeapObject | null)[], rec: CollectionRecord) {
    const marked = new Set<HeapObject>(), stack: HeapObject[] = [];
    rec.work += roots.length;
    const push = (o: HeapObject | null) => { if (o && !marked.has(o)) { marked.add(o); stack.push(o); rec.stack = Math.max(rec.stack, stack.length); } };
    for (const root of roots) {
        push(root);
        while (stack.length) { const o = stack.pop()!; addObject(rec.live, o); rec.work += 1 + o.pointers; for (const v of o.fields) push(v); }
    }
    return marked;
}
export function sweep(heap: Heap, marked: Set<HeapObject>, rec: CollectionRecord, selected: (o: HeapObject) => boolean = () => true) {
    const objects = [...heap.objects.values()].filter(selected), freed: HeapObject[] = [];
    rec.work += objects.length;
    for (const o of objects) if (!marked.has(o)) { heap.objects.delete(o.number); addObject(rec.freed, o); freed.push(o); }
    return freed;
}
export class MarkSweep implements Collector {
    kind: CollectionKind = 'sweep';
    constructor(public heap: Heap, public roots: (HeapObject | null)[]) {}
    inactive(): Pair | null { return null; }
    freeList() { return freeBlocks(this.heap.objects.values(), 0, this.heap.size); }
    claim(size: number) { return firstFit(this.freeList(), size); }
    collect(rec: CollectionRecord) { sweep(this.heap, mark(this.roots, rec), rec); }
    allocate(size: number, line: number, record: (r: CollectionRecord) => void) {
        const address = this.claim(size); if (address !== null) return address;
        const rec = collectionRecord(line, size, this.kind, this.freeList());
        this.collect(rec); rec.after = freeAmount(this.freeList()); record(rec);
        return this.claim(size);
    }
}
export class MarkCompact extends MarkSweep {
    top = 0;
    override kind: CollectionKind = 'compact';
    override freeList() { return this.top < this.heap.size ? [{ address: this.top, length: this.heap.size - this.top }] : []; }
    override claim(size: number) { if (this.top + size > this.heap.size) return null; const address = this.top; this.top += size; return address; }
    override collect(rec: CollectionRecord) {
        const marked = mark(this.roots, rec), objects = [...this.heap.objects.values()].sort((a, b) => a.address - b.address);
        rec.work += objects.length + this.roots.length;
        let dest = 0;
        for (const o of objects) {
            if (!marked.has(o)) { this.heap.objects.delete(o.number); addObject(rec.freed, o); continue; }
            rec.work += o.pointers;
            if (o.address !== dest) { addObject(rec.moved, o); rec.work += o.size; o.address = dest; o.moves++; }
            dest += o.size;
        }
        this.top = dest;
    }
}
