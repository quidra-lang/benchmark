'use strict';

const { hash, merkle } = require('./hashing');
const { Transaction } = require('./transactions');

const header = block => [block.height, block.previous, block.root, block.timestamp, block.difficulty, block.nonce].join('|');
const proofOfWork = block => block.hash.startsWith('0'.repeat(block.difficulty));

class Block {
    constructor(height, previous, root, timestamp, difficulty, nonce, transactions) {
        Object.assign(this, { height, previous, root, timestamp, difficulty, nonce, transactions });
        this.hash = hash(header(this));
        this.size = 0;
        for (const transaction of transactions.slice(1)) this.size += transaction.size;
    }
}

function parseBlock(fields, transactionLines) {
    return new Block(Number(fields[3]), fields[4], fields[5], Number(fields[6]), Number(fields[7]), Number(fields[8]),
        transactionLines.map(text => new Transaction(text)));
}

function mine(height, previous, timestamp, difficulty, transactions) {
    const root = merkle(transactions.map(transaction => transaction.txid));
    const block = new Block(height, previous, root, timestamp, difficulty, 0, transactions);
    while (!proofOfWork(block)) {
        block.nonce++;
        block.hash = hash(header(block));
    }
    return block;
}

function contextFreeCheck(block, maximumSize) {
    if (!proofOfWork(block)) return 'bad-pow';
    if (merkle(block.transactions.map(transaction => transaction.txid)) !== block.root) return 'bad-merkle';
    if (!block.transactions[0].coinbase || block.transactions[0].height !== block.height ||
        block.transactions.slice(1).some(transaction => transaction.coinbase)) return 'bad-structure';
    if (block.size > maximumSize) return 'too-large';
    return null;
}

module.exports = { Block, header, proofOfWork, parseBlock, mine, contextFreeCheck };
