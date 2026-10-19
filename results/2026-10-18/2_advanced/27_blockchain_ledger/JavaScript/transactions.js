'use strict';

const { hash } = require('./hashing');
const { sign } = require('./wallets');

class Transaction {
    constructor(text) {
        this.text = text;
        this.txid = hash(text);
        this.size = text.length;
        const fields = text.split(';');
        this.coinbase = text.startsWith('cb=');
        this.outputs = fields[1].slice(4).split(',').map(output => {
            const [address, amount] = output.split(':');
            return { address, amount: Number(amount) };
        });
        this.inputs = [];
        this.signatures = [];
        this.body = null;
        if (this.coinbase) this.height = Number(fields[0].slice(3));
        else {
            this.inputs = fields[0].slice(3).split(',').map(key => {
                const [txid, index] = key.split(':');
                return { txid, index: Number(index), key };
            });
            this.signatures = fields[2].slice(4).split(',');
            this.body = text.slice(0, text.indexOf(';sig='));
        }
    }
}

const outputText = outputs => outputs.map(output => output.address + ':' + output.amount).join(',');

function payment(inputs, outputs, secret) {
    const body = 'in=' + inputs.map(input => input.txid + ':' + input.index).join(',') + ';out=' + outputText(outputs);
    const signatures = inputs.map((_, i) => sign(secret, i, body));
    return new Transaction(body + ';sig=' + signatures.join(','));
}

const coinbase = (height, outputs) => new Transaction('cb=' + height + ';out=' + outputText(outputs));
const mature = (coin, height, maturity) => !coin.coinbase || coin.height === 0 || height >= coin.height + maturity;

function outputTotal(transaction) {
    let total = 0;
    for (const output of transaction.outputs) total += output.amount;
    return total;
}

function check(transaction, utxo, spent, height, maturity, owners) {
    if (transaction.outputs.some(output => !owners.has(output.address) || output.amount === 0)) return { reason: 'bad-output' };
    const seen = new Set();
    let inputTotal = 0;
    for (let i = 0; i < transaction.inputs.length; i++) {
        const input = transaction.inputs[i];
        if (spent.has(input.key) || seen.has(input.key)) return { reason: 'double-spend' };
        seen.add(input.key);
        const coin = utxo.get(input.key);
        if (coin === undefined) return { reason: 'missing-input' };
        if (!mature(coin, height, maturity)) return { reason: 'immature' };
        if (transaction.signatures[i] !== sign(owners.get(coin.address).secret, i, transaction.body)) return { reason: 'bad-sig' };
        inputTotal += coin.amount;
    }
    const outputs = outputTotal(transaction);
    return inputTotal < outputs ? { reason: 'overspend' } : { fee: inputTotal - outputs };
}

function apply(transaction, utxo, height) {
    for (const input of transaction.inputs) utxo.delete(input.key);
    for (let index = 0; index < transaction.outputs.length; index++) {
        utxo.set(transaction.txid + ':' + index, { ...transaction.outputs[index], txid: transaction.txid, index,
            height, coinbase: transaction.coinbase });
    }
}

module.exports = { Transaction, payment, coinbase, mature, outputTotal, check, apply };
