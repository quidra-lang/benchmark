'use strict';

const { addObject, freeAmount, collectionRecord } = require('./heap');

class Copying {
    constructor(heap, roots) {
        this.heap = heap;
        this.roots = roots;
        this.half = heap.size / 2;
        this.base = 0;
        this.top = 0;
    }

    freeList() {
        const length = this.base + this.half - this.top;
        return length > 0 ? [{ address: this.top, length }] : [];
    }

    claim(size) {
        if (this.top + size > this.base + this.half) return null;
        const address = this.top;
        this.top += size;
        return address;
    }

    collect(record) {
        this.base = this.half - this.base;
        this.top = this.base;
        const copied = new Set();
        const queue = [];
        const copy = object => {
            if (object === null || copied.has(object)) return;
            copied.add(object);
            object.address = this.top;
            this.top += object.size;
            object.moves++;
            addObject(record.live, object);
            addObject(record.moved, object);
            queue.push(object);
        };
        record.work += this.roots.length;
        for (const root of this.roots) copy(root);
        for (let index = 0; index < queue.length; index++) {
            const object = queue[index];
            record.work += object.size + object.pointers;
            for (const value of object.fields) copy(value);
        }
        for (const object of this.heap.objects.values()) {
            if (copied.has(object)) continue;
            this.heap.objects.delete(object.number);
            addObject(record.freed, object);
        }
    }

    allocate(size, line, recordCollection) {
        let address = this.claim(size);
        if (address !== null) return address;
        const record = collectionRecord(line, size, 'copy', this.freeList());
        this.collect(record);
        record.after = freeAmount(this.freeList());
        recordCollection(record);
        address = this.claim(size);
        return address;
    }
}

module.exports = { Copying };
