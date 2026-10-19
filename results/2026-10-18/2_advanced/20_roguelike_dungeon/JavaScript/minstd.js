'use strict';

class Minstd {
    constructor(seed) { this.state = seed; }

    draw() {
        this.state = 48271 * this.state % 2147483647;
        return this.state;
    }

    rnd(n) { return this.draw() % n; }

    roll(dice) {
        let value = 0;
        for (let i = 0; i < dice.count; i++) value += 1 + this.rnd(dice.sides);
        return value;
    }

    select(candidates) {
        let total = 0;
        for (const candidate of candidates) total += candidate.weight;
        const choice = this.rnd(total);
        let cumulative = 0;
        for (const candidate of candidates) {
            cumulative += candidate.weight;
            if (choice < cumulative) return candidate;
        }
    }
}

module.exports = { Minstd };
