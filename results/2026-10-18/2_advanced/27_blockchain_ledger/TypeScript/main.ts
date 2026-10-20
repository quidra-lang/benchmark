import { readFileSync, mkdirSync, writeFileSync } from 'node:fs';
import { hash, merkle, short } from './hashing.ts';
import { readWallets } from './wallets.ts';
import type { Wallet } from './wallets.ts';
import { Transaction, payment, coinbase, mature, outputTotal, check, apply } from './transactions.ts';
import type { Coin, Output, OutputReference, Utxo, TransactionReason } from './transactions.ts';
import { Block, parseBlock, mine, contextFreeCheck } from './blocks.ts';
import { StoredBlock, reward, sequence, forkPoint, medianTime, requiredDifficulty } from './chain.ts';
import type { ChainRules } from './chain.ts';

interface Settings extends ChainRules {
  maturity: number; maxBlock: number; minFee: number; maxMempool: number; maxOrphans: number;
  drift: number; expiry: number; maxReorg: number; banThreshold: number; blockPenalty: number;
  transactionPenalty: number; genesis: { name: string; amount: number }[];
}
interface EventBase { time: number; tokens: string[] }
type NodeEvent = EventBase & (
  { kind: 'TX'; transaction: Transaction } | { kind: 'BLOCK'; block: Block }
  | { kind: 'PAY' | 'BUMP' | 'MINE' | 'STATUS' | 'PRINT' }
);
interface PoolEntry { transaction: Transaction; fee: number; arrival: number }
type MempoolReason = TransactionReason | 'coinbase' | 'duplicate' | 'low-fee' | 'conflict';
type Acceptance = { ok: false; reason: MempoolReason } | { ok: true; fee: number; conflicts: PoolEntry[] };
type Accepted = Extract<Acceptance, { ok: true }>;
interface Peer {
  name: string; blocks: number; rejectedBlocks: number; orphans: number;
  transactions: number; rejectedTransactions: number; ignored: number; score: number;
}
interface Reorganization { time: number; fork: number; disconnected: number; connected: number; old: string; next: string }
type BlockKind = 'BLOCK' | 'UNORPHAN';

const readLines = (name: string) => readFileSync('input/' + name, 'ascii').split('\n').slice(0, -1);
const compareText = (a: string, b: string) => a < b ? -1 : a > b ? 1 : 0;
const referenceOrder = (a: OutputReference, b: OutputReference) => compareText(a.txid, b.txid) || a.index - b.index;
const signed = (value: number) => value >= 0 ? '+' + value : String(value);
function sum(values: number[]): number {
  let total = 0;
  for (const value of values) total += value;
  return total;
}
function readInput() {
  const fields = new Map(readLines('params.txt').map(line => {
    const [name, ...values] = line.split(' ');
    return [name, values];
  }));
  const number = (name: string, index = 0) => Number(fields.get(name)![index]);
  const settings: Settings = {
    difficulty: number('DIFFICULTY'), retarget: number('RETARGET'), targetTime: number('RETARGET', 1),
    reward: number('REWARD'), halving: number('REWARD', 1), maturity: number('MATURITY'), maxBlock: number('MAXBLOCK'),
    minFee: number('MINFEERATE'), maxMempool: number('MEMPOOL'), maxOrphans: number('ORPHANS'), drift: number('DRIFT'),
    expiry: number('EXPIRY'), maxReorg: number('MAXREORG'), banThreshold: number('BAN'),
    blockPenalty: number('BAN', 1), transactionPenalty: number('BAN', 2), genesis: [],
  };
  const distribution = fields.get('GENESIS')!;
  for (let i = 0; i < distribution.length; i += 2) settings.genesis.push({ name: distribution[i], amount: Number(distribution[i + 1]) });
  const lines = readLines('events.txt'), events: NodeEvent[] = [];
  for (let i = 0; i < lines.length; i++) {
    const tokens = lines[i].split(' '), time = Number(tokens[0]), kind = tokens[1];
    switch (kind) {
      case 'TX': events.push({ time, kind, tokens, transaction: new Transaction(tokens[3]) }); break;
      case 'BLOCK': {
        const count = Number(tokens[9]);
        events.push({ time, kind, tokens, block: parseBlock(tokens, lines.slice(i + 1, i + 1 + count)) });
        i += count;
        break;
      }
      case 'PAY': case 'BUMP': case 'MINE': case 'STATUS': case 'PRINT': events.push({ time, kind, tokens }); break;
      default: throw new Error(`Unknown event: ${kind}`);
    }
  }
  return { settings, events, wallets: readWallets() };
}
function priorityOrder(a: PoolEntry, b: PoolEntry): number {
  const left = a.fee * b.transaction.size, right = b.fee * a.transaction.size;
  return left === right ? compareText(a.transaction.txid, b.transaction.txid) : left > right ? -1 : 1;
}

class Node {
  readonly settings: Settings;
  readonly events: NodeEvent[];
  readonly wallets: Wallet[];
  readonly byName: Map<string, Wallet>;
  readonly owners: Map<string, Wallet>;
  readonly genesis: StoredBlock;
  readonly blocks: Map<string, StoredBlock>;
  tip: StoredBlock;
  pool: PoolEntry[] = [];
  readonly orphans: { block: Block; peer: string }[] = [];
  readonly rejected = new Set<string>();
  readonly dropped = new Map<string, string>();
  readonly peers = new Map<string, Peer>();
  readonly rejections = new Map<string, number>();
  readonly reorganizations: Reorganization[] = [];
  readonly log: string[] = [];
  time = 0;
  mainChain: StoredBlock[] = [];
  readonly mainTransactions = new Map<string, { transaction: Transaction; height: number }>();

  constructor(input: ReturnType<typeof readInput>) {
    this.settings = input.settings; this.events = input.events; this.wallets = input.wallets;
    this.byName = new Map(this.wallets.map(w => [w.name, w]));
    this.owners = new Map(this.wallets.map(w => [w.address, w]));
    const outputs = this.settings.genesis.map(g => ({ address: this.byName.get(g.name)!.address, amount: g.amount }));
    const transaction = coinbase(0, outputs), block = new Block(0, '0'.repeat(32), transaction.txid, 0, 0, 0, [transaction]);
    const utxo: Utxo = new Map();
    apply(transaction, utxo, 0);
    this.genesis = new StoredBlock(block, null, utxo, 0, [0], 'genesis');
    this.blocks = new Map([[block.hash, this.genesis]]);
    this.tip = this.genesis;
    this.refreshMainChain();
  }
  get nextHeight(): number { return this.tip.height + 1; }
  message(text: string): void { this.log.push(`${this.time} ${text}`); }
  refreshMainChain(): void {
    this.mainChain = sequence(this.tip);
    this.mainTransactions.clear();
    for (const block of this.mainChain) for (const transaction of block.transactions) {
      this.mainTransactions.set(transaction.txid, { transaction, height: block.height });
    }
  }
  priority(): PoolEntry[] { return this.pool.slice().sort(priorityOrder); }
  lockedReferences(): Set<string> {
    const locked = new Set<string>();
    for (const entry of this.pool) for (const input of entry.transaction.inputs) locked.add(input.key);
    return locked;
  }
  tally(category: 'block' | 'bump' | 'pay' | 'tx', reason: string): void {
    const key = category + ' ' + reason;
    this.rejections.set(key, (this.rejections.get(key) ?? 0) + 1);
  }
  peerRecord(name: string): Peer {
    let peer = this.peers.get(name);
    if (!peer) {
      peer = { name, blocks: 0, rejectedBlocks: 0, orphans: 0, transactions: 0, rejectedTransactions: 0, ignored: 0, score: 0 };
      this.peers.set(name, peer);
    }
    return peer;
  }
  penalize(peer: Peer, points: number): void {
    const before = peer.score;
    peer.score += points;
    if (before < this.settings.banThreshold && peer.score >= this.settings.banThreshold) this.message(`BAN ${peer.name} score ${peer.score}`);
  }
  acceptable(transaction: Transaction): Acceptance {
    if (transaction.coinbase) return { ok: false, reason: 'coinbase' };
    if (this.mainTransactions.has(transaction.txid) || this.pool.some(e => e.transaction.txid === transaction.txid)) return { ok: false, reason: 'duplicate' };
    const result = check(transaction, this.tip.utxo, new Set(), this.nextHeight, this.settings.maturity, this.owners);
    if (!result.ok) return result;
    const fee = result.fee;
    if (fee * 1000 < this.settings.minFee * transaction.size) return { ok: false, reason: 'low-fee' };
    const references = new Set(transaction.inputs.map(i => i.key));
    const conflicts = this.pool.filter(e => e.transaction.inputs.some(i => references.has(i.key)));
    if (conflicts.length && (fee <= sum(conflicts.map(e => e.fee))
      || conflicts.some(e => fee * e.transaction.size <= e.fee * transaction.size))) return { ok: false, reason: 'conflict' };
    return { ok: true, fee, conflicts };
  }
  recordDrop(transaction: Transaction, reason: string): void {
    this.dropped.set(transaction.txid, reason);
    this.message(`DROP ${short(transaction.txid)} ${reason}`);
  }
  drop(entry: PoolEntry, reason: string): void {
    const index = this.pool.indexOf(entry);
    if (index >= 0) this.pool.splice(index, 1);
    this.recordDrop(entry.transaction, reason);
  }
  register(transaction: Transaction, result: Accepted, arrival: number): void {
    for (const conflict of result.conflicts) this.drop(conflict, 'replaced');
    this.pool.push({ transaction, fee: result.fee, arrival });
    if (this.pool.length > this.settings.maxMempool) {
      const priority = this.priority();
      this.drop(priority[priority.length - 1], 'mempool-full');
    }
  }
  rebuild(returned: Transaction[]): void {
    const previous = this.pool;
    this.pool = [];
    const candidates = [
      ...returned.map(transaction => ({ transaction, arrival: this.time, returned: true })),
      ...previous.map(entry => ({ transaction: entry.transaction, arrival: entry.arrival, returned: false })),
    ];
    for (const candidate of candidates) {
      if (this.mainTransactions.has(candidate.transaction.txid)) continue;
      const result = this.acceptable(candidate.transaction);
      if (!result.ok) this.recordDrop(candidate.transaction, result.reason);
      else {
        if (candidate.returned) this.message(`RETURN ${short(candidate.transaction.txid)}`);
        this.register(candidate.transaction, result, candidate.arrival);
      }
    }
  }
  switchTip(block: StoredBlock): void {
    const previous = this.tip, fork = forkPoint(previous, block);
    const disconnected = previous.height - fork.height, connected = block.height - fork.height;
    if (disconnected > this.settings.maxReorg) {
      this.message(`REFUSE ${block.height} ${short(block.hash)} work ${block.work} fork ${fork.height} depth ${disconnected}`);
      return;
    }
    const returned = this.mainChain.filter(b => b.height > fork.height).flatMap(b => b.transactions.slice(1));
    this.tip = block;
    this.refreshMainChain();
    if (disconnected === 0) this.message(`TIP ${block.height} ${short(block.hash)} work ${block.work}`);
    else {
      this.message(`REORG ${block.height} ${short(block.hash)} work ${block.work} fork ${fork.height} disconnected ${disconnected} connected ${connected}`);
      this.reorganizations.push({ time: this.time, fork: fork.height, disconnected, connected, old: previous.hash, next: block.hash });
    }
    this.rebuild(returned);
  }
  pay(tokens: string[]): void {
    const sender = this.byName.get(tokens[2])!, fee = Number(tokens[3]), outputs: Output[] = [];
    for (let i = 4; i < tokens.length; i += 2) outputs.push({ address: this.byName.get(tokens[i])!.address, amount: Number(tokens[i + 1]) });
    const total = sum(outputs.map(o => o.amount)), need = total + fee, locked = this.lockedReferences();
    const coins = [...this.tip.utxo.values()].filter(c => c.address === sender.address && !locked.has(`${c.txid}:${c.index}`)
      && mature(c, this.nextHeight, this.settings.maturity)).sort((a, b) => b.amount - a.amount || referenceOrder(a, b));
    const selected: Coin[] = [];
    let value = 0;
    for (const coin of coins) {
      selected.push(coin); value += coin.amount;
      if (value >= need) break;
    }
    const prefix = `PAY ${sender.name} fee ${fee} total ${total}`;
    if (value < need) {
      this.message(prefix + ' rejected insufficient-funds'); this.tally('pay', 'insufficient-funds'); return;
    }
    if (value > need) outputs.push({ address: sender.address, amount: value - need });
    const transaction = payment(selected, outputs, sender.secret), result = this.acceptable(transaction);
    if (!result.ok) {
      this.message(`${prefix} tx ${short(transaction.txid)} rejected ${result.reason}`); this.tally('pay', result.reason);
    } else {
      this.message(`${prefix} tx ${short(transaction.txid)} accepted inputs ${transaction.inputs.length} outputs ${transaction.outputs.length} size ${transaction.size}`);
      this.register(transaction, result, this.time);
    }
  }
  bump(txid: string, fee: number): void {
    const prefix = `BUMP ${short(txid)} fee ${fee}`, entry = this.pool.find(e => e.transaction.txid === txid);
    if (!entry) { this.message(prefix + ' rejected unknown'); this.tally('bump', 'unknown'); return; }
    const old = entry.transaction, addresses = new Set(old.inputs.map(i => this.tip.utxo.get(i.key)!.address));
    const last = old.outputs[old.outputs.length - 1], amount = last.amount - (fee - entry.fee);
    if (addresses.size !== 1 || !addresses.has(last.address) || amount < 1) {
      this.message(prefix + ' rejected no-change'); this.tally('bump', 'no-change'); return;
    }
    const outputs = old.outputs.map(o => ({ ...o }));
    outputs[outputs.length - 1].amount = amount;
    const transaction = payment(old.inputs, outputs, this.owners.get(last.address)!.secret), result = this.acceptable(transaction);
    if (!result.ok) {
      this.message(`${prefix} tx ${short(transaction.txid)} rejected ${result.reason}`); this.tally('bump', result.reason);
    } else {
      this.message(`${prefix} tx ${short(transaction.txid)} accepted size ${transaction.size}`);
      this.register(transaction, result, this.time);
    }
  }
  receiveTransaction(transaction: Transaction, peer: Peer): void {
    const result = this.acceptable(transaction);
    if (!result.ok) {
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
  mineBlock(walletName: string): void {
    const selected: PoolEntry[] = [];
    let size = 0, fees = 0;
    for (const entry of this.priority()) {
      if (size + entry.transaction.size > this.settings.maxBlock) continue;
      selected.push(entry); size += entry.transaction.size; fees += entry.fee;
    }
    const height = this.nextHeight;
    const cb = coinbase(height, [{ address: this.byName.get(walletName)!.address, amount: reward(height, this.settings) + fees }]);
    const list = [cb, ...selected.map(e => e.transaction)];
    const block = mine(height, this.tip.hash, Math.max(this.time, medianTime(this.tip) + 1), requiredDifficulty(this.tip, this.settings), list);
    const utxo = new Map(this.tip.utxo);
    for (const transaction of list) apply(transaction, utxo, height);
    const stored = new StoredBlock(block, this.tip, utxo, fees, [0, ...selected.map(e => e.fee)], 'local');
    this.blocks.set(block.hash, stored);
    this.message(`MINE ${walletName} ${height} ${short(block.hash)} bits ${block.difficulty} nonce ${block.nonce} txs ${list.length} size ${size} fees ${fees} work ${stored.work}`);
    this.switchTip(stored);
  }
  rejectBlock(kind: BlockKind, block: Block, peer: Peer, reason: string): void {
    this.rejected.add(block.hash); peer.rejectedBlocks++;
    this.tally('block', reason.split(' ')[0]);
    this.message(`${kind} ${peer.name} ${block.height} ${short(block.hash)} rejected ${reason}`);
    if (reason !== 'time-too-new') this.penalize(peer, this.settings.blockPenalty);
  }
  connectBlock(kind: BlockKind, block: Block, peer: Peer): void {
    const parent = this.blocks.get(block.previous)!;
    if (block.height !== parent.height + 1) return this.rejectBlock(kind, block, peer, 'bad-height');
    if (block.difficulty !== requiredDifficulty(parent, this.settings)) return this.rejectBlock(kind, block, peer, 'bad-difficulty');
    if (block.timestamp <= medianTime(parent)) return this.rejectBlock(kind, block, peer, 'time-too-old');
    if (block.timestamp > this.time + this.settings.drift) return this.rejectBlock(kind, block, peer, 'time-too-new');
    const utxo = new Map(parent.utxo), spent = new Set<string>(), transactionFees = [0];
    let fees = 0;
    for (let i = 1; i < block.transactions.length; i++) {
      const transaction = block.transactions[i], result = check(transaction, utxo, spent, block.height, this.settings.maturity, this.owners);
      if (!result.ok) return this.rejectBlock(kind, block, peer, `${result.reason} tx ${i + 1}`);
      for (const input of transaction.inputs) spent.add(input.key);
      apply(transaction, utxo, block.height);
      fees += result.fee; transactionFees.push(result.fee);
    }
    const cb = block.transactions[0];
    if (cb.outputs.some(o => !this.owners.has(o.address) || o.amount === 0)) return this.rejectBlock(kind, block, peer, 'bad-output tx 1');
    if (outputTotal(cb) > reward(block.height, this.settings) + fees) return this.rejectBlock(kind, block, peer, 'bad-coinbase');
    apply(cb, utxo, block.height);
    const stored = new StoredBlock(block, parent, utxo, fees, transactionFees, peer.name);
    this.blocks.set(block.hash, stored); peer.blocks++;
    this.message(`${kind} ${peer.name} ${block.height} ${short(block.hash)} accepted work ${stored.work}`);
    if (stored.work > this.tip.work) this.switchTip(stored);
  }
  resolveOrphans(startingHash: string): void {
    const queue = [startingHash];
    for (let head = 0; head < queue.length; head++) {
      const parentHash = queue[head], children = this.orphans.filter(o => o.block.previous === parentHash);
      for (const orphan of children) {
        this.orphans.splice(this.orphans.indexOf(orphan), 1);
        const peer = this.peerRecord(orphan.peer);
        if (this.rejected.has(parentHash)) this.rejectBlock('UNORPHAN', orphan.block, peer, 'bad-parent');
        else this.connectBlock('UNORPHAN', orphan.block, peer);
        queue.push(orphan.block.hash);
      }
    }
  }
  receiveBlock(block: Block, peer: Peer): void {
    if (this.blocks.has(block.hash) || this.orphans.some(o => o.block.hash === block.hash) || this.rejected.has(block.hash)) {
      this.message(`BLOCK ${peer.name} ${block.height} ${short(block.hash)} rejected duplicate`);
      peer.rejectedBlocks++; this.tally('block', 'duplicate'); return;
    }
    const reason = contextFreeCheck(block, this.settings.maxBlock) ?? (this.rejected.has(block.previous) ? 'bad-parent' : null);
    if (reason !== null) {
      this.rejectBlock('BLOCK', block, peer, reason); this.resolveOrphans(block.hash); return;
    }
    if (!this.blocks.has(block.previous)) {
      this.orphans.push({ block, peer: peer.name }); peer.orphans++;
      this.message(`BLOCK ${peer.name} ${block.height} ${short(block.hash)} orphan parent ${short(block.previous)}`);
      if (this.orphans.length > this.settings.maxOrphans) this.message(`EVICT ${short(this.orphans.shift()!.block.hash)} orphan-limit`);
      return;
    }
    this.connectBlock('BLOCK', block, peer);
    this.resolveOrphans(block.hash);
  }
  status(txid: string): void {
    const prefix = 'STATUS ' + short(txid), confirmed = this.mainTransactions.get(txid);
    if (confirmed) { this.message(`${prefix} confirmed ${confirmed.height} confirmations ${this.nextHeight - confirmed.height}`); return; }
    const priority = this.priority(), index = priority.findIndex(e => e.transaction.txid === txid);
    if (index >= 0) this.message(`${prefix} mempool rank ${index + 1} of ${priority.length}`);
    else if (this.dropped.has(txid)) this.message(`${prefix} dropped ${this.dropped.get(txid)}`);
    else if ([...this.blocks.values()].some(b => b.transactions.some(t => t.txid === txid))) this.message(prefix + ' stale');
    else this.message(prefix + ' unknown');
  }
  print(): void {
    this.message(`PRINT height ${this.tip.height} tip ${short(this.tip.hash)} work ${this.tip.work} bits ${requiredDifficulty(this.tip, this.settings)} reward ${reward(this.nextHeight, this.settings)} mempool ${this.pool.length} size ${sum(this.pool.map(e => e.transaction.size))} orphans ${this.orphans.length}`);
    this.priority().forEach((entry, i) => this.message(`MEMPOOL ${i + 1} ${short(entry.transaction.txid)} fee ${entry.fee} size ${entry.transaction.size}`));
    for (const wallet of this.wallets) this.message(`BALANCE ${wallet.name} ${sum([...this.tip.utxo.values()].filter(c => c.address === wallet.address).map(c => c.amount))}`);
  }
  processEvents(): void {
    for (const event of this.events) {
      this.time = event.time;
      for (const entry of this.pool.slice()) if (this.time - entry.arrival >= this.settings.expiry) this.drop(entry, 'expired');
      if (event.kind === 'TX' || event.kind === 'BLOCK') {
        const peer = this.peerRecord(event.tokens[2]);
        if (peer.score >= this.settings.banThreshold) {
          peer.ignored++; this.message(`IGNORE ${peer.name} ${event.kind}`); continue;
        }
        if (event.kind === 'TX') this.receiveTransaction(event.transaction, peer);
        else this.receiveBlock(event.block, peer);
        continue;
      }
      switch (event.kind) {
        case 'PAY': this.pay(event.tokens); break;
        case 'BUMP': this.bump(event.tokens[2], Number(event.tokens[3])); break;
        case 'MINE': this.mineBlock(event.tokens[2]); break;
        case 'STATUS': this.status(event.tokens[2]); break;
        case 'PRINT': this.print(); break;
      }
    }
  }
  chainLines(): string[] {
    const lines = [`TIP ${this.tip.height} ${this.tip.hash} work ${this.tip.work} stored ${this.blocks.size} orphans ${this.orphans.length}`];
    for (const block of this.mainChain) {
      const miner = block.height === 0 ? '-' : this.owners.get(block.transactions[0].outputs[0].address)!.name;
      lines.push(`BLOCK ${block.height} ${block.hash} prev ${short(block.previous)} time ${block.timestamp} bits ${block.difficulty} nonce ${block.nonce} txs ${block.transactions.length} size ${block.size} fees ${block.fees} miner ${miner} source ${block.source} work ${block.work}`);
      block.transactions.forEach((transaction, i) => {
        const prefix = `TX ${i + 1} ${transaction.txid}`;
        if (transaction.coinbase) lines.push(`${prefix} ${block.height === 0 ? 'genesis' : 'coinbase'} out ${transaction.outputs.length} amount ${outputTotal(transaction)}`);
        else lines.push(`${prefix} payment in ${transaction.inputs.length} out ${transaction.outputs.length} size ${transaction.size} fee ${block.transactionFees[i]}`);
      });
    }
    const mainHashes = new Set(this.mainChain.map(b => b.hash));
    const stale = [...this.blocks.values()].filter(b => !mainHashes.has(b.hash)).sort((a, b) => a.height - b.height || compareText(a.hash, b.hash));
    for (const b of stale) lines.push(`STALE ${b.height} ${b.hash} prev ${short(b.previous)} source ${b.source} work ${b.work}`);
    for (const { block: b, peer } of this.orphans) lines.push(`ORPHAN ${b.height} ${b.hash} prev ${short(b.previous)} source ${peer}`);
    for (const r of this.reorganizations) lines.push(`REORG ${r.time} fork ${r.fork} disconnected ${r.disconnected} connected ${r.connected} old ${short(r.old)} new ${short(r.next)}`);
    for (const wallet of this.wallets) {
      const mined = this.mainChain.filter(b => b.height > 0 && b.transactions[0].outputs[0].address === wallet.address);
      if (mined.length) lines.push(`MINER ${wallet.name} blocks ${mined.length} coinbase ${sum(mined.map(b => outputTotal(b.transactions[0])))} fees ${sum(mined.map(b => b.fees))}`);
    }
    for (let first = 1; first < this.mainChain.length;) {
      let last = first;
      while (last + 1 < this.mainChain.length && this.mainChain[last + 1].difficulty === this.mainChain[first].difficulty) last++;
      lines.push(`BITS ${this.mainChain[first].difficulty} heights ${this.mainChain[first].height}-${this.mainChain[last].height} blocks ${last - first + 1}`);
      first = last + 1;
    }
    for (const p of [...this.peers.values()].sort((a, b) => compareText(a.name, b.name))) {
      lines.push(`PEER ${p.name} blocks ${p.blocks} rejected ${p.rejectedBlocks} orphans ${p.orphans} txs ${p.transactions} rejected ${p.rejectedTransactions} ignored ${p.ignored} score ${p.score} ${p.score >= this.settings.banThreshold ? 'banned' : 'ok'}`);
    }
    this.priority().forEach((e, i) => lines.push(`MEMPOOL ${i + 1} ${e.transaction.txid} fee ${e.fee} size ${e.transaction.size} time ${e.arrival}`));
    for (const [key, count] of [...this.rejections].sort((a, b) => compareText(a[0], b[0]))) lines.push(`REJECT ${key} ${count}`);
    const payments = this.mainChain.slice(1), rewards = sum(payments.map(b => reward(b.height, this.settings)));
    const fees = sum(payments.map(b => b.fees)), issued = sum(payments.map(b => outputTotal(b.transactions[0])));
    lines.push(`SUPPLY genesis ${outputTotal(this.genesis.transactions[0])} rewards ${rewards} fees ${fees} burned ${rewards + fees - issued} utxo ${sum([...this.tip.utxo.values()].map(c => c.amount))}`);
    return lines;
  }
  balanceLines(): string[] {
    const lines = ['wallet,address,balance,immature,locked,incoming,utxos'], locked = this.lockedReferences();
    for (const wallet of this.wallets) {
      const coins = [...this.tip.utxo.values()].filter(c => c.address === wallet.address);
      const balance = sum(coins.map(c => c.amount));
      const immature = sum(coins.filter(c => !mature(c, this.nextHeight, this.settings.maturity)).map(c => c.amount));
      const reserved = sum(coins.filter(c => locked.has(`${c.txid}:${c.index}`)).map(c => c.amount));
      let incoming = 0;
      for (const entry of this.pool) for (const output of entry.transaction.outputs) if (output.address === wallet.address) incoming += output.amount;
      lines.push([wallet.name, wallet.address, balance, immature, reserved, incoming, coins.length].join(','));
    }
    return lines;
  }
  utxoLines(): string[] {
    const locked = this.lockedReferences(), coins = [...this.tip.utxo.values()].sort(referenceOrder);
    const lines = coins.map(c => {
      const reference = `${c.txid}:${c.index}`, category = c.height === 0 ? 'genesis' : c.coinbase ? 'coinbase' : 'payment';
      const state = !mature(c, this.nextHeight, this.settings.maturity) ? 'immature' : locked.has(reference) ? 'locked' : 'free';
      return `${reference} ${this.owners.get(c.address)!.name} ${c.amount} height ${c.height} ${category} ${state}`;
    });
    const root = merkle(lines.map(hash));
    lines.push(`TOTAL ${coins.length} ${sum(coins.map(c => c.amount))}`, 'ROOT ' + root);
    return lines;
  }
  historyLines(): string[] {
    const lines: string[] = [], priority = this.priority();
    for (const wallet of this.wallets) {
      lines.push(`WALLET ${wallet.name} ${wallet.address}`);
      let count = 0, totalSpent = 0, totalReceived = 0, balance = 0;
      for (const block of this.mainChain) for (const transaction of block.transactions) {
        let spent = 0;
        for (const input of transaction.inputs) {
          const output = this.mainTransactions.get(input.txid)!.transaction.outputs[input.index];
          if (output.address === wallet.address) spent += output.amount;
        }
        const received = sum(transaction.outputs.filter(o => o.address === wallet.address).map(o => o.amount));
        if (spent === 0 && received === 0) continue;
        const net = received - spent;
        balance += net; count++; totalSpent += spent; totalReceived += received;
        const category = block.height === 0 ? 'genesis' : transaction.coinbase ? 'coinbase' : 'payment';
        lines.push(`${block.height} ${short(transaction.txid)} ${category} spent ${spent} received ${received} net ${signed(net)} balance ${balance}`);
      }
      let pending = 0;
      for (const entry of priority) {
        let spent = 0;
        for (const input of entry.transaction.inputs) {
          const coin = this.tip.utxo.get(input.key)!;
          if (coin.address === wallet.address) spent += coin.amount;
        }
        const received = sum(entry.transaction.outputs.filter(o => o.address === wallet.address).map(o => o.amount));
        if (spent === 0 && received === 0) continue;
        pending++;
        lines.push(`pending ${short(entry.transaction.txid)} spent ${spent} received ${received} net ${signed(received - spent)}`);
      }
      lines.push(`END ${wallet.name} txs ${count} spent ${totalSpent} received ${totalReceived} balance ${balance} pending ${pending}`);
    }
    return lines;
  }
  writeOutput(): void {
    mkdirSync('output', { recursive: true });
    const files: Record<string, string[]> = { 'log.txt': this.log, 'chain.txt': this.chainLines(),
      'balances.csv': this.balanceLines(), 'utxo.txt': this.utxoLines(), 'history.txt': this.historyLines() };
    for (const [name, lines] of Object.entries(files)) writeFileSync('output/' + name, lines.length ? lines.join('\n') + '\n' : '', 'ascii');
  }
}

function main(): void {
  const node = new Node(readInput());
  node.processEvents();
  node.writeOutput();
}
main();
