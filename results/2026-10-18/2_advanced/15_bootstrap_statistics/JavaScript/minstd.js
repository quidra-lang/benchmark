'use strict';

class Minstd {
    constructor(seed) {
        this.state = seed;
    }

    draw() {
        this.state = (48271 * this.state) % 2147483647;
        return this.state;
    }

    below(limit) {
        return this.draw() % limit;
    }

    shuffle(values) {
        for (let index = values.length - 1; index > 0; index--) {
            const other = this.below(index + 1);
            [values[index], values[other]] = [values[other], values[index]];
        }
        return values;
    }
}

module.exports = { Minstd };
