'use strict';

const fs = require('node:fs');
const { hash } = require('./hashing');

function readWallets() {
    return fs.readFileSync('input/wallets.txt', 'ascii').split('\n').slice(0, -1).map(line => {
        const [name, secret] = line.split(' ');
        return { name, secret, address: hash('addr:' + secret).slice(0, 16) };
    });
}

const sign = (secret, input, body) => hash(`${secret}:${input}:${body}`).slice(0, 16);

module.exports = { readWallets, sign };
