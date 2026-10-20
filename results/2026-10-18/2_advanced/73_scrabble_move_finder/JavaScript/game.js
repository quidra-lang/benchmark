'use strict';

class Minstd {
    constructor(seed) { this.state = seed; }
    next() {
        this.state = (48271 * this.state) % 2147483647;
        return this.state;
    }
}

function shuffle(bag, random) {
    for (let i = bag.length - 1; i >= 1; i--) {
        const j = random.next() % (i + 1);
        [bag[i], bag[j]] = [bag[j], bag[i]];
    }
}

function makeBag(table, random) {
    const bag = [];
    for (const [letter, tile] of table) for (let i = 0; i < tile.count; i++) bag.push(letter);
    shuffle(bag, random);
    return bag;
}

function draw(bag, count) {
    let tiles = '';
    for (let i = 0; i < count && bag.length > 0; i++) tiles += bag.pop();
    return tiles;
}

function exchange(bag, returned, random) {
    const drawn = draw(bag, returned.length);
    bag.push(...Array.from(returned).sort());
    shuffle(bag, random);
    return drawn;
}

function value(tiles, table) {
    let total = 0;
    for (const tile of tiles) total += table.get(tile).value;
    return total;
}

module.exports = { Minstd, shuffle, makeBag, draw, exchange, value };
