'use strict';

class StoredBlock {
    constructor(block, parent, utxo, fees, transactionFees, source) {
        Object.assign(this, block);
        this.parent = parent;
        this.utxo = utxo;
        this.fees = fees;
        this.transactionFees = transactionFees;
        this.source = source;
        this.work = parent === null ? 1 : parent.work + 16 ** block.difficulty;
    }
}

function reward(height, settings) {
    let value = settings.reward;
    for (let i = 0; i < Math.floor(height / settings.halving); i++) value = Math.floor(value / 2);
    return value;
}

function ancestor(block, height) {
    while (block.height > height) block = block.parent;
    return block;
}

function sequence(tip) {
    const blocks = [];
    for (let current = tip; current !== null; current = current.parent) blocks.push(current);
    return blocks.reverse();
}

function forkPoint(first, second) {
    first = ancestor(first, Math.min(first.height, second.height));
    second = ancestor(second, first.height);
    while (first.hash !== second.hash) { first = first.parent; second = second.parent; }
    return first;
}

function medianTime(block) {
    const times = [];
    for (let i = 0; i < 3 && block !== null; i++, block = block.parent) times.push(block.timestamp);
    times.sort((a, b) => a - b);
    return times[Math.floor((times.length - 1) / 2)];
}

function requiredDifficulty(parent, settings) {
    const height = parent.height + 1;
    if (height === 1) return settings.difficulty;
    if (height % settings.retarget !== 0) return parent.difficulty;
    const earlier = ancestor(parent, height - settings.retarget);
    const span = parent.timestamp - earlier.timestamp;
    const expected = settings.targetTime * (settings.retarget - 1);
    if (2 * span < expected) return Math.min(parent.difficulty + 1, 2);
    if (span > 2 * expected) return Math.max(parent.difficulty - 1, 0);
    return parent.difficulty;
}

module.exports = { StoredBlock, reward, ancestor, sequence, forkPoint, medianTime, requiredDifficulty };
