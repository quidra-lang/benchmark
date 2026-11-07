'use strict';

const { addObject, freeBlocks, firstFit, freeAmount, collectionRecord } = require('./heap');
const { mark, sweep } = require('./mark_sweep');

class Generational {
    constructor(heap, roots, young, age) {
        this.heap = heap;
        this.roots = roots;
        this.young = young;
        this.promotionAge = age;
        this.half = young / 2;
        this.base = 0;
        this.top = 0;
        this.remembered = new Set();
        this.barriers = 0;
        this.remembers = 0;
    }

    oldBlocks() {
        return freeBlocks(this.heap.objects.values(), this.young, this.heap.size);
    }

    freeList() {
        const blocks = this.oldBlocks();
        const length = this.base + this.half - this.top;
        if (length > 0) blocks.unshift({ address: this.top, length });
        return blocks;
    }

    writeBarrier(object, value) {
        if (object.address < this.young) return;
        this.barriers++;
        if (value !== null && value.address < this.young && !this.remembered.has(object)) {
            this.remembered.add(object);
            this.remembers++;
        }
    }

    claim(size) {
        if (this.top + size > this.base + this.half) return null;
        const address = this.top;
        this.top += size;
        return address;
    }

    collect(record) {
        const major = record.kind === 'major' || record.kind === 'full';
        if (major) {
            const marked = mark(this.heap, this.roots, record);
            const freed = sweep(this.heap, marked, record, object => object.address >= this.young);
            for (const object of freed) this.remembered.delete(object);
        }
        const remaining = new Set([...this.heap.objects.values()].filter(object => object.address < this.young));
        const destination = this.half - this.base;
        let top = destination;
        const queue = [];
        const evacuate = object => {
            if (object === null || !remaining.has(object)) return true;
            remaining.delete(object);
            object.age++;
            object.moves++;
            if (record.kind === 'tenure' || record.kind === 'full' || object.age >= this.promotionAge) {
                const address = firstFit(this.oldBlocks(), object.size);
                if (address === null) return false;
                object.address = address;
                addObject(record.promoted, object);
            } else {
                object.address = top;
                top += object.size;
            }
            addObject(record.moved, object);
            if (!major) addObject(record.live, object);
            queue.push(object);
            return true;
        };
        record.work += this.roots.length;
        for (const root of this.roots) if (!evacuate(root)) return false;
        const remembered = [...this.remembered].sort((first, second) => first.address - second.address);
        for (const object of remembered) {
            record.work += 1 + object.pointers;
            for (const value of object.fields) if (!evacuate(value)) return false;
        }
        for (let index = 0; index < queue.length; index++) {
            const object = queue[index];
            record.work += object.size + object.pointers;
            for (const value of object.fields) if (!evacuate(value)) return false;
        }
        for (const object of remaining) {
            this.heap.objects.delete(object.number);
            addObject(record.freed, object);
        }
        this.base = destination;
        this.top = top;
        this.remembered = new Set();
        for (const object of this.heap.objects.values()) {
            if (object.address >= this.young && object.fields.some(value => value !== null && value.address < this.young)) {
                this.remembered.add(object);
            }
        }
        return true;
    }

    allocate(size, line, recordCollection) {
        let address = this.claim(size);
        if (address !== null) return address;
        for (let attempt = 0; attempt < 2; attempt++) {
            const largest = freeAmount(this.oldBlocks())[1];
            const sweepOld = largest < this.top - this.base;
            const kind = attempt === 0 ? (sweepOld ? 'major' : 'minor') : (sweepOld ? 'full' : 'tenure');
            const record = collectionRecord(line, size, kind, this.freeList());
            if (!this.collect(record)) return null;
            record.after = freeAmount(this.freeList());
            recordCollection(record);
            address = this.claim(size);
            if (address !== null) return address;
        }
        return null;
    }
}

module.exports = { Generational };
