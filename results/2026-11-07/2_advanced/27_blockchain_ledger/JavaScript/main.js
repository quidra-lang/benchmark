'use strict';

const fs = require('node:fs');
const { hash, merkle, short } = require('./hashing');
const { readWallets } = require('./wallets');
const transactions = require('./transactions');
const { Block, parseBlock, mine, contextFreeCheck } = require('./blocks');
const { StoredBlock, reward, sequence, forkPoint, medianTime, requiredDifficulty } = require('./chain');

const readLines = name => fs.readFileSync('input/' + name, 'ascii').split('\n').slice(0, -1);
const compareText = (a, b) => a < b ? -1 : a > b ? 1 : 0;
const referenceOrder = (a, b) => compareText(a.txid, b.txid) || a.index - b.index;
const signed = value => value >= 0 ? '+' + value : String(value);
function sum(values) { let total = 0; for (const value of values) total += value; return total; }

function readInput() {
    const fields = new Map(readLines('params.txt').map(line => {
        const [name, ...values] = line.split(' ');
        return [name, values];
    }));
    const number = (name, index = 0) => Number(fields.get(name)[index]);
    const settings = { difficulty: number('DIFFICULTY'), retarget: number('RETARGET'), targetTime: number('RETARGET', 1),
        reward: number('REWARD'), halving: number('REWARD', 1), maturity: number('MATURITY'), maxBlock: number('MAXBLOCK'),
        minFee: number('MINFEERATE'), maxMempool: number('MEMPOOL'), maxOrphans: number('ORPHANS'), drift: number('DRIFT'),
        expiry: number('EXPIRY'), maxReorg: number('MAXREORG'), banThreshold: number('BAN'),
        blockPenalty: number('BAN', 1), transactionPenalty: number('BAN', 2), genesis: [] };
    const distribution = fields.get('GENESIS');
    for (let i = 0; i < distribution.length; i += 2) settings.genesis.push({ name: distribution[i], amount: Number(distribution[i + 1]) });
    const lines = readLines('events.txt');
    const events = [];
    for (let i = 0; i < lines.length; i++) {
        const tokens = lines[i].split(' ');
        const event = { time: Number(tokens[0]), kind: tokens[1], tokens };
        if (event.kind === 'TX') event.transaction = new transactions.Transaction(tokens[3]);
        if (event.kind === 'BLOCK') {
            const count = Number(tokens[9]);
            event.block = parseBlock(tokens, lines.slice(i + 1, i + 1 + count));
            i += count;
        }
        events.push(event);
    }
    return { settings, events, wallets: readWallets() };
}

function priorityOrder(a, b) {
    const left = a.fee * b.transaction.size;
    const right = b.fee * a.transaction.size;
    return left === right ? compareText(a.transaction.txid, b.transaction.txid) : left > right ? -1 : 1;
}

class Node {
    constructor(input) {
        Object.assign(this, input);
        this.byName = new Map(this.wallets.map(wallet => [wallet.name, wallet]));
        this.owners = new Map(this.wallets.map(wallet => [wallet.address, wallet]));
        const outputs = this.settings.genesis.map(item => ({ address: this.byName.get(item.name).address, amount: item.amount }));
        const transaction = transactions.coinbase(0, outputs);
        const block = new Block(0, '0'.repeat(32), transaction.txid, 0, 0, 0, [transaction]);
        const utxo = new Map();
        transactions.apply(transaction, utxo, 0);
        this.genesis = new StoredBlock(block, null, utxo, 0, [0], 'genesis');
        this.blocks = new Map([[block.hash, this.genesis]]);
        this.tip = this.genesis;
        this.pool = [];
        this.orphans = [];
        this.rejected = new Set();
        this.dropped = new Map();
        this.peers = new Map();
        this.rejections = new Map();
        this.reorganizations = [];
        this.log = [];
        this.time = 0;
        this.refreshMainChain();
    }

    get nextHeight() { return this.tip.height + 1; }

    message(text) { this.log.push(this.time + ' ' + text); }

    refreshMainChain() {
        this.mainChain = sequence(this.tip);
        this.mainTransactions = new Map();
        for (const block of this.mainChain) {
            for (const transaction of block.transactions) this.mainTransactions.set(transaction.txid, { transaction, height: block.height });
        }
    }

    priority() { return this.pool.slice().sort(priorityOrder); }

    lockedReferences() {
        const locked = new Set();
        for (const entry of this.pool) for (const input of entry.transaction.inputs) locked.add(input.key);
        return locked;
    }

    tally(category, reason) {
        const key = category + ' ' + reason;
        this.rejections.set(key, (this.rejections.get(key) ?? 0) + 1);
    }

    peerRecord(name) {
        if (!this.peers.has(name)) this.peers.set(name, { name, blocks: 0, rejectedBlocks: 0, orphans: 0,
            transactions: 0, rejectedTransactions: 0, ignored: 0, score: 0 });
        return this.peers.get(name);
    }

    penalize(peer, points) {
        const before = peer.score;
        peer.score += points;
        if (before < this.settings.banThreshold && peer.score >= this.settings.banThreshold) this.message(`BAN ${peer.name} score ${peer.score}`);
    }

    acceptable(transaction) {
        if (transaction.coinbase) return { reason: 'coinbase' };
        if (this.mainTransactions.has(transaction.txid) || this.pool.some(entry => entry.transaction.txid === transaction.txid)) return { reason: 'duplicate' };
        const result = transactions.check(transaction, this.tip.utxo, new Set(), this.nextHeight, this.settings.maturity, this.owners);
        if (result.reason) return result;
        const fee = result.fee;
        if (fee * 1000 < this.settings.minFee * transaction.size) return { reason: 'low-fee' };
        const references = new Set(transaction.inputs.map(input => input.key));
        const conflicts = this.pool.filter(entry => entry.transaction.inputs.some(input => references.has(input.key)));
        if (conflicts.length > 0) {
            const totalFees = sum(conflicts.map(entry => entry.fee));
            if (fee <= totalFees || conflicts.some(entry => fee * entry.transaction.size <= entry.fee * transaction.size)) return { reason: 'conflict' };
        }
        return { fee, conflicts };
    }

    recordDrop(transaction, reason) {
        this.dropped.set(transaction.txid, reason);
        this.message(`DROP ${short(transaction.txid)} ${reason}`);
    }

    drop(entry, reason) {
        const index = this.pool.indexOf(entry);
        if (index >= 0) this.pool.splice(index, 1);
        this.recordDrop(entry.transaction, reason);
    }

    register(transaction, result, arrival) {
        for (const conflict of result.conflicts) this.drop(conflict, 'replaced');
        this.pool.push({ transaction, fee: result.fee, arrival });
        if (this.pool.length > this.settings.maxMempool) this.drop(this.priority().at(-1), 'mempool-full');
    }

    rebuild(returned) {
        const previous = this.pool;
        this.pool = [];
        const candidates = returned.map(transaction => ({ transaction, arrival: this.time, returned: true }));
        candidates.push(...previous.map(entry => ({ transaction: entry.transaction, arrival: entry.arrival, returned: false })));
        for (const candidate of candidates) {
            if (this.mainTransactions.has(candidate.transaction.txid)) continue;
            const result = this.acceptable(candidate.transaction);
            if (result.reason) this.recordDrop(candidate.transaction, result.reason);
            else {
                if (candidate.returned) this.message('RETURN ' + short(candidate.transaction.txid));
                this.register(candidate.transaction, result, candidate.arrival);
            }
        }
    }

    switchTip(block) {
        const previous = this.tip;
        const fork = forkPoint(previous, block);
        const disconnected = previous.height - fork.height;
        const connected = block.height - fork.height;
        if (disconnected > this.settings.maxReorg) {
            this.message(`REFUSE ${block.height} ${short(block.hash)} work ${block.work} fork ${fork.height} depth ${disconnected}`);
            return;
        }
        const returned = this.mainChain.filter(item => item.height > fork.height).flatMap(item => item.transactions.slice(1));
        this.tip = block;
        this.refreshMainChain();
        if (disconnected === 0) this.message(`TIP ${block.height} ${short(block.hash)} work ${block.work}`);
        else {
            this.message(`REORG ${block.height} ${short(block.hash)} work ${block.work} fork ${fork.height} disconnected ${disconnected} connected ${connected}`);
            this.reorganizations.push({ time: this.time, fork: fork.height, disconnected, connected, old: previous.hash, next: block.hash });
        }
        this.rebuild(returned);
    }

    pay(tokens) {
        const sender = this.byName.get(tokens[2]);
        const fee = Number(tokens[3]);
        const outputs = [];
        for (let i = 4; i < tokens.length; i += 2) outputs.push({ address: this.byName.get(tokens[i]).address, amount: Number(tokens[i + 1]) });
        const total = sum(outputs.map(output => output.amount));
        const need = total + fee;
        const locked = this.lockedReferences();
        const coins = [...this.tip.utxo.values()].filter(coin => coin.address === sender.address && !locked.has(coin.txid + ':' + coin.index)
            && transactions.mature(coin, this.nextHeight, this.settings.maturity))
            .sort((a, b) => b.amount - a.amount || referenceOrder(a, b));
        const selected = [];
        let value = 0;
        for (const coin of coins) {
            selected.push(coin);
            value += coin.amount;
            if (value >= need) break;
        }
        const prefix = `PAY ${sender.name} fee ${fee} total ${total}`;
        if (value < need) {
            this.message(prefix + ' rejected insufficient-funds');
            this.tally('pay', 'insufficient-funds');
            return;
        }
        if (value > need) outputs.push({ address: sender.address, amount: value - need });
        const transaction = transactions.payment(selected, outputs, sender.secret);
        const result = this.acceptable(transaction);
        if (result.reason) {
            this.message(`${prefix} tx ${short(transaction.txid)} rejected ${result.reason}`);
            this.tally('pay', result.reason);
        } else {
            this.message(`${prefix} tx ${short(transaction.txid)} accepted inputs ${transaction.inputs.length} outputs ${transaction.outputs.length} size ${transaction.size}`);
            this.register(transaction, result, this.time);
        }
    }

    bump(txid, fee) {
        const prefix = `BUMP ${short(txid)} fee ${fee}`;
        const entry = this.pool.find(item => item.transaction.txid === txid);
        if (!entry) {
            this.message(prefix + ' rejected unknown');
            this.tally('bump', 'unknown');
            return;
        }
        const old = entry.transaction;
        const addresses = new Set(old.inputs.map(input => this.tip.utxo.get(input.key).address));
        const last = old.outputs.at(-1);
        const amount = last.amount - (fee - entry.fee);
        if (addresses.size !== 1 || !addresses.has(last.address) || amount < 1) {
            this.message(prefix + ' rejected no-change');
            this.tally('bump', 'no-change');
            return;
        }
        const outputs = old.outputs.map(output => ({ ...output }));
        outputs.at(-1).amount = amount;
        const transaction = transactions.payment(old.inputs, outputs, this.owners.get(last.address).secret);
        const result = this.acceptable(transaction);
        if (result.reason) {
            this.message(`${prefix} tx ${short(transaction.txid)} rejected ${result.reason}`);
            this.tally('bump', result.reason);
        } else {
            this.message(`${prefix} tx ${short(transaction.txid)} accepted size ${transaction.size}`);
            this.register(transaction, result, this.time);
        }
    }

    receiveTransaction(transaction, peer) {
        const result = this.acceptable(transaction);
        if (result.reason) {
            peer.rejectedTransactions++;
            this.tally('tx', result.reason);
            this.message(`TX ${peer.name} ${short(transaction.txid)} rejected ${result.reason}`);
            if (['coinbase', 'bad-output', 'bad-sig', 'overspend'].includes(result.reason)) this.penalize(peer, this.settings.transactionPenalty);
        } else {
            peer.transactions++;
            this.message(`TX ${peer.name} ${short(transaction.txid)} accepted fee ${result.fee} size ${transaction.size}`);
            this.register(transaction, result, this.time);
        }
    }

    mineBlock(walletName) {
        const selected = [];
        let size = 0;
        let fees = 0;
        for (const entry of this.priority()) {
            if (size + entry.transaction.size > this.settings.maxBlock) continue;
            selected.push(entry);
            size += entry.transaction.size;
            fees += entry.fee;
        }
        const height = this.nextHeight;
        const coinbase = transactions.coinbase(height, [{ address: this.byName.get(walletName).address, amount: reward(height, this.settings) + fees }]);
        const list = [coinbase, ...selected.map(entry => entry.transaction)];
        const timestamp = Math.max(this.time, medianTime(this.tip) + 1);
        const block = mine(height, this.tip.hash, timestamp, requiredDifficulty(this.tip, this.settings), list);
        const utxo = new Map(this.tip.utxo);
        for (const transaction of list) transactions.apply(transaction, utxo, height);
        const stored = new StoredBlock(block, this.tip, utxo, fees, [0, ...selected.map(entry => entry.fee)], 'local');
        this.blocks.set(block.hash, stored);
        this.message(`MINE ${walletName} ${height} ${short(block.hash)} bits ${block.difficulty} nonce ${block.nonce}` +
            ` txs ${list.length} size ${size} fees ${fees} work ${stored.work}`);
        this.switchTip(stored);
    }

    rejectBlock(kind, block, peer, reason) {
        this.rejected.add(block.hash);
        peer.rejectedBlocks++;
        this.tally('block', reason.split(' ')[0]);
        this.message(`${kind} ${peer.name} ${block.height} ${short(block.hash)} rejected ${reason}`);
        if (reason !== 'time-too-new') this.penalize(peer, this.settings.blockPenalty);
    }

    connectBlock(kind, block, peer) {
        const parent = this.blocks.get(block.previous);
        if (block.height !== parent.height + 1) return this.rejectBlock(kind, block, peer, 'bad-height');
        if (block.difficulty !== requiredDifficulty(parent, this.settings)) return this.rejectBlock(kind, block, peer, 'bad-difficulty');
        if (block.timestamp <= medianTime(parent)) return this.rejectBlock(kind, block, peer, 'time-too-old');
        if (block.timestamp > this.time + this.settings.drift) return this.rejectBlock(kind, block, peer, 'time-too-new');
        const utxo = new Map(parent.utxo);
        const spent = new Set();
        const transactionFees = [0];
        let fees = 0;
        for (let i = 1; i < block.transactions.length; i++) {
            const transaction = block.transactions[i];
            const result = transactions.check(transaction, utxo, spent, block.height, this.settings.maturity, this.owners);
            if (result.reason) return this.rejectBlock(kind, block, peer, result.reason + ' tx ' + (i + 1));
            for (const input of transaction.inputs) spent.add(input.key);
            transactions.apply(transaction, utxo, block.height);
            fees += result.fee;
            transactionFees.push(result.fee);
        }
        const coinbase = block.transactions[0];
        if (coinbase.outputs.some(output => !this.owners.has(output.address) || output.amount === 0)) return this.rejectBlock(kind, block, peer, 'bad-output tx 1');
        if (transactions.outputTotal(coinbase) > reward(block.height, this.settings) + fees) return this.rejectBlock(kind, block, peer, 'bad-coinbase');
        transactions.apply(coinbase, utxo, block.height);
        const stored = new StoredBlock(block, parent, utxo, fees, transactionFees, peer.name);
        this.blocks.set(block.hash, stored);
        peer.blocks++;
        this.message(`${kind} ${peer.name} ${block.height} ${short(block.hash)} accepted work ${stored.work}`);
        if (stored.work > this.tip.work) this.switchTip(stored);
    }

    resolveOrphans(startingHash) {
        const queue = [startingHash];
        for (let head = 0; head < queue.length; head++) {
            const parentHash = queue[head];
            const children = this.orphans.filter(orphan => orphan.block.previous === parentHash);
            for (const orphan of children) {
                this.orphans.splice(this.orphans.indexOf(orphan), 1);
                const peer = this.peerRecord(orphan.peer);
                if (this.rejected.has(parentHash)) this.rejectBlock('UNORPHAN', orphan.block, peer, 'bad-parent');
                else this.connectBlock('UNORPHAN', orphan.block, peer);
                queue.push(orphan.block.hash);
            }
        }
    }

    receiveBlock(block, peer) {
        if (this.blocks.has(block.hash) || this.orphans.some(orphan => orphan.block.hash === block.hash) || this.rejected.has(block.hash)) {
            this.message(`BLOCK ${peer.name} ${block.height} ${short(block.hash)} rejected duplicate`);
            peer.rejectedBlocks++;
            this.tally('block', 'duplicate');
            return;
        }
        let reason = contextFreeCheck(block, this.settings.maxBlock);
        if (reason === null && this.rejected.has(block.previous)) reason = 'bad-parent';
        if (reason !== null) {
            this.rejectBlock('BLOCK', block, peer, reason);
            this.resolveOrphans(block.hash);
            return;
        }
        if (!this.blocks.has(block.previous)) {
            this.orphans.push({ block, peer: peer.name });
            peer.orphans++;
            this.message(`BLOCK ${peer.name} ${block.height} ${short(block.hash)} orphan parent ${short(block.previous)}`);
            if (this.orphans.length > this.settings.maxOrphans) this.message(`EVICT ${short(this.orphans.shift().block.hash)} orphan-limit`);
            return;
        }
        this.connectBlock('BLOCK', block, peer);
        this.resolveOrphans(block.hash);
    }

    status(txid) {
        const prefix = 'STATUS ' + short(txid);
        if (this.mainTransactions.has(txid)) {
            const height = this.mainTransactions.get(txid).height;
            this.message(`${prefix} confirmed ${height} confirmations ${this.nextHeight - height}`);
            return;
        }
        const priority = this.priority();
        const index = priority.findIndex(entry => entry.transaction.txid === txid);
        if (index >= 0) this.message(`${prefix} mempool rank ${index + 1} of ${priority.length}`);
        else if (this.dropped.has(txid)) this.message(prefix + ' dropped ' + this.dropped.get(txid));
        else if ([...this.blocks.values()].some(block => block.transactions.some(transaction => transaction.txid === txid))) this.message(prefix + ' stale');
        else this.message(prefix + ' unknown');
    }

    print() {
        const priority = this.priority();
        this.message(`PRINT height ${this.tip.height} tip ${short(this.tip.hash)} work ${this.tip.work}` +
            ` bits ${requiredDifficulty(this.tip, this.settings)} reward ${reward(this.nextHeight, this.settings)}` +
            ` mempool ${this.pool.length} size ${sum(this.pool.map(entry => entry.transaction.size))} orphans ${this.orphans.length}`);
        for (let i = 0; i < priority.length; i++) {
            const entry = priority[i];
            this.message(`MEMPOOL ${i + 1} ${short(entry.transaction.txid)} fee ${entry.fee} size ${entry.transaction.size}`);
        }
        for (const wallet of this.wallets) {
            const balance = sum([...this.tip.utxo.values()].filter(coin => coin.address === wallet.address).map(coin => coin.amount));
            this.message(`BALANCE ${wallet.name} ${balance}`);
        }
    }

    processEvents() {
        for (const event of this.events) {
            this.time = event.time;
            for (const entry of this.pool.slice()) if (this.time - entry.arrival >= this.settings.expiry) this.drop(entry, 'expired');
            let peer;
            if (event.kind === 'TX' || event.kind === 'BLOCK') {
                peer = this.peerRecord(event.tokens[2]);
                if (peer.score >= this.settings.banThreshold) {
                    peer.ignored++;
                    this.message(`IGNORE ${peer.name} ${event.kind}`);
                    continue;
                }
            }
            if (event.kind === 'PAY') this.pay(event.tokens);
            else if (event.kind === 'BUMP') this.bump(event.tokens[2], Number(event.tokens[3]));
            else if (event.kind === 'TX') this.receiveTransaction(event.transaction, peer);
            else if (event.kind === 'MINE') this.mineBlock(event.tokens[2]);
            else if (event.kind === 'BLOCK') this.receiveBlock(event.block, peer);
            else if (event.kind === 'STATUS') this.status(event.tokens[2]);
            else this.print();
        }
    }

    chainLines() {
        const lines = [`TIP ${this.tip.height} ${this.tip.hash} work ${this.tip.work} stored ${this.blocks.size} orphans ${this.orphans.length}`];
        for (const block of this.mainChain) {
            const miner = block.height === 0 ? '-' : this.owners.get(block.transactions[0].outputs[0].address).name;
            lines.push(`BLOCK ${block.height} ${block.hash} prev ${short(block.previous)} time ${block.timestamp} bits ${block.difficulty}` +
                ` nonce ${block.nonce} txs ${block.transactions.length} size ${block.size} fees ${block.fees} miner ${miner} source ${block.source} work ${block.work}`);
            for (let i = 0; i < block.transactions.length; i++) {
                const transaction = block.transactions[i];
                const prefix = `TX ${i + 1} ${transaction.txid}`;
                if (transaction.coinbase) lines.push(`${prefix} ${block.height === 0 ? 'genesis' : 'coinbase'} out ${transaction.outputs.length} amount ${transactions.outputTotal(transaction)}`);
                else lines.push(`${prefix} payment in ${transaction.inputs.length} out ${transaction.outputs.length} size ${transaction.size} fee ${block.transactionFees[i]}`);
            }
        }
        const mainHashes = new Set(this.mainChain.map(block => block.hash));
        const stale = [...this.blocks.values()].filter(block => !mainHashes.has(block.hash)).sort((a, b) => a.height - b.height || compareText(a.hash, b.hash));
        for (const block of stale) lines.push(`STALE ${block.height} ${block.hash} prev ${short(block.previous)} source ${block.source} work ${block.work}`);
        for (const { block, peer } of this.orphans) lines.push(`ORPHAN ${block.height} ${block.hash} prev ${short(block.previous)} source ${peer}`);
        for (const change of this.reorganizations) {
            lines.push(`REORG ${change.time} fork ${change.fork} disconnected ${change.disconnected} connected ${change.connected} old ${short(change.old)} new ${short(change.next)}`);
        }
        for (const wallet of this.wallets) {
            const mined = this.mainChain.filter(block => block.height > 0 && block.transactions[0].outputs[0].address === wallet.address);
            if (mined.length > 0) lines.push(`MINER ${wallet.name} blocks ${mined.length}` +
                ` coinbase ${sum(mined.map(block => transactions.outputTotal(block.transactions[0])))} fees ${sum(mined.map(block => block.fees))}`);
        }
        for (let first = 1; first < this.mainChain.length;) {
            let last = first;
            while (last + 1 < this.mainChain.length && this.mainChain[last + 1].difficulty === this.mainChain[first].difficulty) last++;
            lines.push(`BITS ${this.mainChain[first].difficulty} heights ${this.mainChain[first].height}-${this.mainChain[last].height} blocks ${last - first + 1}`);
            first = last + 1;
        }
        for (const peer of [...this.peers.values()].sort((a, b) => compareText(a.name, b.name))) {
            lines.push(`PEER ${peer.name} blocks ${peer.blocks} rejected ${peer.rejectedBlocks} orphans ${peer.orphans} txs ${peer.transactions}` +
                ` rejected ${peer.rejectedTransactions} ignored ${peer.ignored} score ${peer.score} ${peer.score >= this.settings.banThreshold ? 'banned' : 'ok'}`);
        }
        for (const [i, entry] of this.priority().entries()) {
            lines.push(`MEMPOOL ${i + 1} ${entry.transaction.txid} fee ${entry.fee} size ${entry.transaction.size} time ${entry.arrival}`);
        }
        for (const [key, count] of [...this.rejections].sort((a, b) => compareText(a[0], b[0]))) lines.push(`REJECT ${key} ${count}`);
        const rewards = sum(this.mainChain.slice(1).map(block => reward(block.height, this.settings)));
        const fees = sum(this.mainChain.slice(1).map(block => block.fees));
        const coinbase = sum(this.mainChain.slice(1).map(block => transactions.outputTotal(block.transactions[0])));
        lines.push(`SUPPLY genesis ${transactions.outputTotal(this.genesis.transactions[0])} rewards ${rewards} fees ${fees}` +
            ` burned ${rewards + fees - coinbase} utxo ${sum([...this.tip.utxo.values()].map(coin => coin.amount))}`);
        return lines;
    }

    balanceLines() {
        const lines = ['wallet,address,balance,immature,locked,incoming,utxos'];
        const locked = this.lockedReferences();
        for (const wallet of this.wallets) {
            const coins = [...this.tip.utxo.values()].filter(coin => coin.address === wallet.address);
            const balance = sum(coins.map(coin => coin.amount));
            const immature = sum(coins.filter(coin => !transactions.mature(coin, this.nextHeight, this.settings.maturity)).map(coin => coin.amount));
            const reserved = sum(coins.filter(coin => locked.has(coin.txid + ':' + coin.index)).map(coin => coin.amount));
            let incoming = 0;
            for (const entry of this.pool) for (const output of entry.transaction.outputs) if (output.address === wallet.address) incoming += output.amount;
            lines.push([wallet.name, wallet.address, balance, immature, reserved, incoming, coins.length].join(','));
        }
        return lines;
    }

    utxoLines() {
        const locked = this.lockedReferences();
        const coins = [...this.tip.utxo.values()].sort(referenceOrder);
        const lines = coins.map(coin => {
            const reference = coin.txid + ':' + coin.index;
            const category = coin.height === 0 ? 'genesis' : coin.coinbase ? 'coinbase' : 'payment';
            const state = !transactions.mature(coin, this.nextHeight, this.settings.maturity) ? 'immature' : locked.has(reference) ? 'locked' : 'free';
            return `${reference} ${this.owners.get(coin.address).name} ${coin.amount} height ${coin.height} ${category} ${state}`;
        });
        const root = merkle(lines.map(hash));
        lines.push(`TOTAL ${coins.length} ${sum(coins.map(coin => coin.amount))}`, 'ROOT ' + root);
        return lines;
    }

    historyLines() {
        const lines = [];
        const priority = this.priority();
        for (const wallet of this.wallets) {
            lines.push(`WALLET ${wallet.name} ${wallet.address}`);
            let count = 0;
            let totalSpent = 0;
            let totalReceived = 0;
            let balance = 0;
            for (const block of this.mainChain) {
                for (const transaction of block.transactions) {
                    let spent = 0;
                    for (const input of transaction.inputs) {
                        const output = this.mainTransactions.get(input.txid).transaction.outputs[input.index];
                        if (output.address === wallet.address) spent += output.amount;
                    }
                    const received = sum(transaction.outputs.filter(output => output.address === wallet.address).map(output => output.amount));
                    if (spent === 0 && received === 0) continue;
                    const net = received - spent;
                    balance += net;
                    count++;
                    totalSpent += spent;
                    totalReceived += received;
                    const category = block.height === 0 ? 'genesis' : transaction.coinbase ? 'coinbase' : 'payment';
                    lines.push(`${block.height} ${short(transaction.txid)} ${category} spent ${spent} received ${received} net ${signed(net)} balance ${balance}`);
                }
            }
            let pending = 0;
            for (const entry of priority) {
                let spent = 0;
                for (const input of entry.transaction.inputs) {
                    const coin = this.tip.utxo.get(input.key);
                    if (coin.address === wallet.address) spent += coin.amount;
                }
                const received = sum(entry.transaction.outputs.filter(output => output.address === wallet.address).map(output => output.amount));
                if (spent === 0 && received === 0) continue;
                pending++;
                lines.push(`pending ${short(entry.transaction.txid)} spent ${spent} received ${received} net ${signed(received - spent)}`);
            }
            lines.push(`END ${wallet.name} txs ${count} spent ${totalSpent} received ${totalReceived} balance ${balance} pending ${pending}`);
        }
        return lines;
    }

    writeOutput() {
        fs.mkdirSync('output', { recursive: true });
        const files = [['log.txt', this.log], ['chain.txt', this.chainLines()], ['balances.csv', this.balanceLines()],
            ['utxo.txt', this.utxoLines()], ['history.txt', this.historyLines()]];
        for (const [name, lines] of files) fs.writeFileSync('output/' + name, lines.length === 0 ? '' : lines.join('\n') + '\n', 'ascii');
    }
}

function main() {
    const node = new Node(readInput());
    node.processEvents();
    node.writeOutput();
}

main();
