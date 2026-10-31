'use strict';

class BTB {
    constructor(size) {
        this.entries = Array(size).fill(null);
    }

    lookup(pc) {
        const entry = this.entries[(pc >>> 2) % this.entries.length];
        return entry !== null && entry.pc === pc ? entry.target : null;
    }

    insert(pc, target) {
        this.entries[(pc >>> 2) % this.entries.length] = {pc, target};
    }
}

class RAS {
    constructor(depth) {
        this.depth = depth;
        this.stack = [];
    }

    push(value) {
        if (this.depth === 0) return;
        if (this.stack.length === this.depth) this.stack.shift();
        this.stack.push(value);
    }

    pop() {
        return this.stack.length ? this.stack.pop() : null;
    }
}

function updateCounter(value, taken) {
    return taken ? Math.min(3, value + 1) : Math.max(0, value - 1);
}

class DirectionPredictor {
    constructor(specification) {
        this.scheme = specification.scheme;
        const p = specification.parameters;
        this.history = 0;
        if (this.scheme === 'ONEBIT') this.table = Array(p[0]).fill(0);
        if (this.scheme === 'TWOBIT' || this.scheme === 'GSHARE') this.table = Array(p[0]).fill(1);
        if (this.scheme === 'GSHARE') this.historyLimit = 1 << p[1];
        if (this.scheme === 'TOURNAMENT') {
            this.local = Array(p[0]).fill(1);
            this.global = Array(p[1]).fill(1);
            this.historyLimit = 1 << p[2];
            this.chooser = Array(p[3]).fill(1);
        }
    }

    predict(pc, target) {
        if (this.scheme === 'STATIC_NT') return {taken: false};
        if (this.scheme === 'BTFN') return {taken: target < pc};
        const word = pc >>> 2;
        if (this.scheme === 'TOURNAMENT') {
            const localIndex = word % this.local.length;
            const globalIndex = (word ^ this.history) % this.global.length;
            const chooserIndex = word % this.chooser.length;
            const local = this.local[localIndex] >= 2;
            const global = this.global[globalIndex] >= 2;
            return {taken: this.chooser[chooserIndex] >= 2 ? global : local,
                local, global, localIndex, globalIndex, chooserIndex};
        }
        const index = (this.scheme === 'GSHARE' ? word ^ this.history : word) % this.table.length;
        return {taken: this.scheme === 'ONEBIT' ? this.table[index] === 1 : this.table[index] >= 2, index};
    }

    update(prediction, taken) {
        if (this.scheme === 'ONEBIT') this.table[prediction.index] = taken ? 1 : 0;
        else if (this.scheme === 'TWOBIT' || this.scheme === 'GSHARE') {
            this.table[prediction.index] = updateCounter(this.table[prediction.index], taken);
            if (this.scheme === 'GSHARE') this.history = (2 * this.history + (taken ? 1 : 0)) % this.historyLimit;
        } else if (this.scheme === 'TOURNAMENT') {
            if (prediction.local !== prediction.global) {
                this.chooser[prediction.chooserIndex] = updateCounter(this.chooser[prediction.chooserIndex], prediction.global === taken);
            }
            this.local[prediction.localIndex] = updateCounter(this.local[prediction.localIndex], taken);
            this.global[prediction.globalIndex] = updateCounter(this.global[prediction.globalIndex], taken);
            this.history = (2 * this.history + (taken ? 1 : 0)) % this.historyLimit;
        }
    }
}

function storage(specification) {
    const p = specification.parameters;
    if (specification.scheme === 'ONEBIT') return p[0];
    if (specification.scheme === 'TWOBIT') return 2 * p[0];
    if (specification.scheme === 'GSHARE') return 2 * p[0] + p[1];
    if (specification.scheme === 'TOURNAMENT') return 2 * (p[0] + p[1] + p[3]) + p[2];
    return 0;
}

module.exports = {BTB, RAS, DirectionPredictor, storage};
