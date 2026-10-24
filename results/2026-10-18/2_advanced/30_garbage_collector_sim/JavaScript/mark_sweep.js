'use strict';

const { addObject, freeBlocks, firstFit, freeAmount, collectionRecord } = require('./heap');

function mark(heap, roots, record) {
    const marked = new Set();
    const stack = [];
    record.work += roots.length;
    const push = object => {
        if (object === null || marked.has(object)) return;
        marked.add(object);
        stack.push(object);
        record.stack = Math.max(record.stack, stack.length);
    };
    for (const root of roots) {
        push(root);
        while (stack.length > 0) {
            const object = stack.pop();
            addObject(record.live, object);
            record.work += 1 + object.pointers;
            for (const value of object.fields) push(value);
        }
    }
    return marked;
}

function sweep(heap, marked, record, selected = () => true) {
    const objects = [...heap.objects.values()].filter(selected);
    record.work += objects.length;
    const freed = [];
    for (const object of objects) {
        if (marked.has(object)) continue;
        heap.objects.delete(object.number);
        addObject(record.freed, object);
        freed.push(object);
    }
    return freed;
}

class MarkSweep {
    constructor(heap, roots) {
        this.heap = heap;
        this.roots = roots;
        this.kind = 'sweep';
    }

    freeList() {
        return freeBlocks(this.heap.objects.values(), 0, this.heap.size);
    }

    claim(size) {
        return firstFit(this.freeList(), size);
    }

    collect(record) {
        const marked = mark(this.heap, this.roots, record);
        sweep(this.heap, marked, record);
    }

    allocate(size, line, recordCollection) {
        let address = this.claim(size);
        if (address !== null) return address;
        const record = collectionRecord(line, size, this.kind, this.freeList());
        this.collect(record);
        record.after = freeAmount(this.freeList());
        recordCollection(record);
        address = this.claim(size);
        return address;
    }
}

class MarkCompact extends MarkSweep {
    constructor(heap, roots) {
        super(heap, roots);
        this.top = 0;
        this.kind = 'compact';
    }

    freeList() {
        return this.top < this.heap.size ? [{ address: this.top, length: this.heap.size - this.top }] : [];
    }

    claim(size) {
        if (this.top + size > this.heap.size) return null;
        const address = this.top;
        this.top += size;
        return address;
    }

    collect(record) {
        const marked = mark(this.heap, this.roots, record);
        const objects = [...this.heap.objects.values()].sort((first, second) => first.address - second.address);
        record.work += objects.length + this.roots.length;
        let destination = 0;
        for (const object of objects) {
            if (!marked.has(object)) {
                this.heap.objects.delete(object.number);
                addObject(record.freed, object);
                continue;
            }
            record.work += object.pointers;
            if (object.address !== destination) {
                addObject(record.moved, object);
                record.work += object.size;
                object.address = destination;
                object.moves++;
            }
            destination += object.size;
        }
        this.top = destination;
    }
}

module.exports = { mark, sweep, MarkSweep, MarkCompact };
