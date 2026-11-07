import os
from collections import deque
from functools import cmp_to_key

from blocks import Block, context_free_error, mine_block, parse_block_event
from chain import BlockRecord, chain_to, fork_point, median_time, required_difficulty, reward
from hashing import digest, merkle_root, short
from transactions import (
    apply_transaction, check_transaction, create_coinbase, create_transaction, parse_transaction,
)
from wallets import read_wallets


INPUT_DIR = "input"
OUTPUT_DIR = "output"
GENESIS_PREVIOUS = "0" * 32
PENALIZED_TX_REASONS = ("coinbase", "bad-output", "bad-sig", "overspend")
BALANCES_HEADER = "wallet,address,balance,immature,locked,incoming,utxos"


def read_lines(path):
    with open(path) as handle:
        return handle.read().splitlines()


def signed(value):
    return f"{value:+d}"


class Params:
    def __init__(self, lines):
        values = {}
        for line in lines:
            key, *rest = line.split()
            values[key] = rest
        self.initial_difficulty = int(values["DIFFICULTY"][0])
        self.retarget_interval = int(values["RETARGET"][0])
        self.target_spacing = int(values["RETARGET"][1])
        self.initial_reward = int(values["REWARD"][0])
        self.halving_interval = int(values["REWARD"][1])
        self.maturity = int(values["MATURITY"][0])
        self.max_block_size = int(values["MAXBLOCK"][0])
        self.min_fee_rate = int(values["MINFEERATE"][0])
        self.mempool_limit = int(values["MEMPOOL"][0])
        self.orphan_limit = int(values["ORPHANS"][0])
        self.drift = int(values["DRIFT"][0])
        self.expiry = int(values["EXPIRY"][0])
        self.max_reorg = int(values["MAXREORG"][0])
        self.ban_score = int(values["BAN"][0])
        self.block_penalty = int(values["BAN"][1])
        self.tx_penalty = int(values["BAN"][2])
        pairs = values["GENESIS"]
        self.genesis = [(pairs[i], int(pairs[i + 1])) for i in range(0, len(pairs), 2)]


class Peer:
    def __init__(self, name):
        self.name = name
        self.accepted_blocks = 0
        self.rejected_blocks = 0
        self.orphaned_blocks = 0
        self.accepted_txs = 0
        self.rejected_txs = 0
        self.ignored = 0
        self.score = 0


class MempoolEntry:
    def __init__(self, transaction, fee, arrival):
        self.transaction = transaction
        self.fee = fee
        self.arrival = arrival


class Orphan:
    def __init__(self, block, peer):
        self.block = block
        self.peer = peer


class Reorganization:
    def __init__(self, time, fork_height, disconnected, connected, old_hash, new_hash):
        self.time = time
        self.fork_height = fork_height
        self.disconnected = disconnected
        self.connected = connected
        self.old_hash = old_hash
        self.new_hash = new_hash


class Acceptance:
    def __init__(self, reason, fee=0, conflicts=()):
        self.reason = reason
        self.fee = fee
        self.conflicts = list(conflicts)


def compare_priority(first, second):
    left = first.fee * second.transaction.size
    right = second.fee * first.transaction.size
    if left != right:
        return -1 if left > right else 1
    if first.transaction.txid != second.transaction.txid:
        return -1 if first.transaction.txid < second.transaction.txid else 1
    return 0


class Node:
    def __init__(self, params, wallets):
        self.params = params
        self.wallets = wallets
        self.owners = {wallet.address: wallet for wallet in wallets}
        self.named = {wallet.name: wallet for wallet in wallets}
        self.now = 0
        self.records = {}
        self.mempool = []
        self.orphans = []
        self.rejected = set()
        self.drop_record = {}
        self.peers = {}
        self.rejections = {}
        self.reorganizations = []
        self.log_lines = []
        self.tip = self.create_genesis()
        self.main_chain = []
        self.confirmed = {}
        self.refresh_main_chain()

    def create_genesis(self):
        outputs = [(self.named[name].address, amount) for name, amount in self.params.genesis]
        coinbase = create_coinbase(0, outputs)
        block = Block(0, GENESIS_PREVIOUS, coinbase.txid, 0, 0, 0, [coinbase])
        utxo = {}
        apply_transaction(utxo, coinbase, 0)
        record = BlockRecord(block, None, utxo, [], "genesis")
        self.records[record.hash] = record
        return record

    def refresh_main_chain(self):
        self.main_chain = chain_to(self.tip)
        self.confirmed = {}
        for record in self.main_chain:
            for transaction in record.block.transactions:
                self.confirmed[transaction.txid] = record.height

    def log(self, *parts):
        self.log_lines.append(" ".join(str(part) for part in (self.now, *parts)))

    def tally(self, category, reason):
        key = (category, reason)
        self.rejections[key] = self.rejections.get(key, 0) + 1

    def peer(self, name):
        if name not in self.peers:
            self.peers[name] = Peer(name)
        return self.peers[name]

    def next_height(self):
        return self.tip.height + 1

    def block_reward(self, height):
        return reward(height, self.params.initial_reward, self.params.halving_interval)

    def next_difficulty(self, parent):
        return required_difficulty(
            parent, self.params.initial_difficulty,
            self.params.retarget_interval, self.params.target_spacing,
        )

    def is_mature(self, coin):
        return coin.is_mature(self.next_height(), self.params.maturity)

    def balance(self, address):
        return sum(coin.amount for coin in self.tip.utxo.values() if coin.address == address)

    def locked_references(self):
        return {reference for entry in self.mempool for reference in entry.transaction.inputs}

    def priority_order(self):
        return sorted(self.mempool, key=cmp_to_key(compare_priority))

    def find_entry(self, txid):
        for entry in self.mempool:
            if entry.transaction.txid == txid:
                return entry
        return None

    def acceptance(self, transaction):
        if transaction.is_coinbase():
            return Acceptance("coinbase")
        if transaction.txid in self.confirmed or self.find_entry(transaction.txid) is not None:
            return Acceptance("duplicate")
        reason, fee = check_transaction(
            transaction, self.tip.utxo, set(), self.next_height(),
            self.owners, self.params.maturity,
        )
        if reason is not None:
            return Acceptance(reason)
        size = transaction.size
        if fee * 1000 < self.params.min_fee_rate * size:
            return Acceptance("low-fee")
        inputs = set(transaction.inputs)
        conflicts = [
            entry for entry in self.mempool
            if any(reference in inputs for reference in entry.transaction.inputs)
        ]
        if conflicts:
            pays_more = fee > sum(entry.fee for entry in conflicts)
            higher_rate = all(fee * entry.transaction.size > entry.fee * size for entry in conflicts)
            if not (pays_more and higher_rate):
                return Acceptance("conflict")
        return Acceptance(None, fee, conflicts)

    def record_drop(self, txid, reason):
        self.drop_record[txid] = reason
        self.log("DROP", short(txid), reason)

    def drop(self, entry, reason):
        if entry in self.mempool:
            self.mempool.remove(entry)
        self.record_drop(entry.transaction.txid, reason)

    def register(self, transaction, result, arrival):
        for entry in result.conflicts:
            self.drop(entry, "replaced")
        self.mempool.append(MempoolEntry(transaction, result.fee, arrival))
        if len(self.mempool) > self.params.mempool_limit:
            self.drop(self.priority_order()[-1], "mempool-full")

    def rebuild_mempool(self, returned):
        previous = self.mempool
        self.mempool = []
        candidates = [(transaction, self.now, True) for transaction in returned]
        candidates += [(entry.transaction, entry.arrival, False) for entry in previous]
        for transaction, arrival, is_returned in candidates:
            if transaction.txid in self.confirmed:
                continue
            result = self.acceptance(transaction)
            if result.reason is not None:
                self.record_drop(transaction.txid, result.reason)
                continue
            if is_returned:
                self.log("RETURN", short(transaction.txid))
            self.register(transaction, result, arrival)

    def switch_tip(self, target):
        old_tip = self.tip
        fork = fork_point(old_tip, target)
        disconnected = old_tip.height - fork.height
        connected = target.height - fork.height
        if disconnected > self.params.max_reorg:
            self.log(
                "REFUSE", target.height, short(target.hash), "work", target.cumulative_work,
                "fork", fork.height, "depth", disconnected,
            )
            return
        returned = []
        for record in self.main_chain[fork.height + 1:]:
            returned.extend(record.block.transactions[1:])
        self.tip = target
        self.refresh_main_chain()
        if disconnected == 0:
            self.log("TIP", target.height, short(target.hash), "work", target.cumulative_work)
        else:
            self.log(
                "REORG", target.height, short(target.hash), "work", target.cumulative_work,
                "fork", fork.height, "disconnected", disconnected, "connected", connected,
            )
            self.reorganizations.append(Reorganization(
                self.now, fork.height, disconnected, connected, old_tip.hash, target.hash,
            ))
        self.rebuild_mempool(returned)

    def penalize(self, peer, points):
        before = peer.score
        peer.score += points
        if before < self.params.ban_score <= peer.score:
            self.log("BAN", peer.name, "score", peer.score)

    def expire(self):
        for entry in list(self.mempool):
            if self.now - entry.arrival >= self.params.expiry:
                self.drop(entry, "expired")

    def process(self, fields, texts):
        self.now = int(fields[0])
        self.expire()
        kind = fields[1]
        if kind == "PAY":
            self.pay(fields)
        elif kind == "BUMP":
            self.bump(fields[2], int(fields[3]))
        elif kind == "MINE":
            self.mine(self.named[fields[2]])
        elif kind == "STATUS":
            self.status(fields[2])
        elif kind == "PRINT":
            self.print_state()
        else:
            peer = self.peer(fields[2])
            if peer.score >= self.params.ban_score:
                peer.ignored += 1
                self.log("IGNORE", peer.name, kind)
            elif kind == "TX":
                self.receive_transaction(peer, parse_transaction(fields[3]))
            else:
                self.receive_block(peer, parse_block_event(fields, texts))

    def spendable_coins(self, address):
        locked = self.locked_references()
        coins = [
            (reference, coin) for reference, coin in self.tip.utxo.items()
            if coin.address == address and reference not in locked and self.is_mature(coin)
        ]
        coins.sort(key=lambda item: (-item[1].amount, item[0]))
        return coins

    def pay(self, fields):
        sender = self.named[fields[2]]
        fee = int(fields[3])
        outputs = [
            (self.named[fields[i]].address, int(fields[i + 1])) for i in range(4, len(fields), 2)
        ]
        total = sum(amount for _, amount in outputs)
        need = total + fee
        prefix = ("PAY", sender.name, "fee", fee, "total", total)
        inputs = []
        gathered = 0
        for reference, coin in self.spendable_coins(sender.address):
            if gathered >= need:
                break
            inputs.append(reference)
            gathered += coin.amount
        if gathered < need:
            self.log(*prefix, "rejected", "insufficient-funds")
            self.tally("pay", "insufficient-funds")
            return
        if gathered > need:
            outputs.append((sender.address, gathered - need))
        transaction = create_transaction(inputs, outputs, sender.secret)
        result = self.acceptance(transaction)
        if result.reason is not None:
            self.log(*prefix, "tx", short(transaction.txid), "rejected", result.reason)
            self.tally("pay", result.reason)
            return
        self.log(
            *prefix, "tx", short(transaction.txid), "accepted", "inputs", len(transaction.inputs),
            "outputs", len(transaction.outputs), "size", transaction.size,
        )
        self.register(transaction, result, self.now)

    def bump(self, txid, fee):
        prefix = ("BUMP", short(txid), "fee", fee)
        entry = self.find_entry(txid)
        if entry is None:
            self.log(*prefix, "rejected", "unknown")
            self.tally("bump", "unknown")
            return
        original = entry.transaction
        addresses = {self.tip.utxo[reference].address for reference in original.inputs}
        address, amount = original.outputs[-1]
        change = amount - (fee - entry.fee)
        if addresses != {address} or change < 1:
            self.log(*prefix, "rejected", "no-change")
            self.tally("bump", "no-change")
            return
        outputs = original.outputs[:-1] + [(address, change)]
        transaction = create_transaction(original.inputs, outputs, self.owners[address].secret)
        result = self.acceptance(transaction)
        if result.reason is not None:
            self.log(*prefix, "tx", short(transaction.txid), "rejected", result.reason)
            self.tally("bump", result.reason)
            return
        self.log(*prefix, "tx", short(transaction.txid), "accepted", "size", transaction.size)
        self.register(transaction, result, self.now)

    def receive_transaction(self, peer, transaction):
        result = self.acceptance(transaction)
        if result.reason is not None:
            peer.rejected_txs += 1
            self.tally("tx", result.reason)
            self.log("TX", peer.name, short(transaction.txid), "rejected", result.reason)
            if result.reason in PENALIZED_TX_REASONS:
                self.penalize(peer, self.params.tx_penalty)
            return
        peer.accepted_txs += 1
        self.log(
            "TX", peer.name, short(transaction.txid), "accepted",
            "fee", result.fee, "size", transaction.size,
        )
        self.register(transaction, result, self.now)

    def mine(self, wallet):
        height = self.next_height()
        selected = []
        size = 0
        for entry in self.priority_order():
            if size + entry.transaction.size <= self.params.max_block_size:
                selected.append(entry)
                size += entry.transaction.size
        fees = [entry.fee for entry in selected]
        coinbase = create_coinbase(height, [(wallet.address, self.block_reward(height) + sum(fees))])
        transactions = [coinbase] + [entry.transaction for entry in selected]
        timestamp = max(self.now, median_time(self.tip) + 1)
        block = mine_block(
            height, self.tip.hash, transactions, timestamp, self.next_difficulty(self.tip)
        )
        utxo = dict(self.tip.utxo)
        for transaction in transactions:
            apply_transaction(utxo, transaction, height)
        record = BlockRecord(block, self.tip, utxo, fees, "local")
        self.records[record.hash] = record
        self.log(
            "MINE", wallet.name, height, short(block.hash), "bits", block.difficulty,
            "nonce", block.nonce, "txs", len(transactions), "size", block.size(),
            "fees", record.fees, "work", record.cumulative_work,
        )
        self.switch_tip(record)

    def is_orphan(self, block_hash):
        return any(orphan.block.hash == block_hash for orphan in self.orphans)

    def receive_block(self, peer, block):
        if block.hash in self.records or self.is_orphan(block.hash) or block.hash in self.rejected:
            self.log("BLOCK", peer.name, block.height, short(block.hash), "rejected", "duplicate")
            peer.rejected_blocks += 1
            self.tally("block", "duplicate")
            return
        reason = context_free_error(block, self.params.max_block_size)
        if reason is None and block.previous in self.rejected:
            reason = "bad-parent"
        if reason is not None:
            self.reject_block("BLOCK", block, peer, reason)
            self.resolve_orphans(block.hash)
            return
        if block.previous not in self.records:
            self.orphans.append(Orphan(block, peer))
            peer.orphaned_blocks += 1
            self.log(
                "BLOCK", peer.name, block.height, short(block.hash),
                "orphan", "parent", short(block.previous),
            )
            if len(self.orphans) > self.params.orphan_limit:
                evicted = self.orphans.pop(0)
                self.log("EVICT", short(evicted.block.hash), "orphan-limit")
            return
        self.connect_block("BLOCK", block, peer)
        self.resolve_orphans(block.hash)

    def validate_block(self, block, parent):
        if block.height != parent.height + 1:
            return "bad-height", None, None
        if block.difficulty != self.next_difficulty(parent):
            return "bad-difficulty", None, None
        if block.timestamp <= median_time(parent):
            return "time-too-old", None, None
        if block.timestamp > self.now + self.params.drift:
            return "time-too-new", None, None
        utxo = dict(parent.utxo)
        spent = set()
        fees = []
        for position, transaction in enumerate(block.transactions[1:], 2):
            reason, fee = check_transaction(
                transaction, utxo, spent, block.height, self.owners, self.params.maturity
            )
            if reason is not None:
                return f"{reason} tx {position}", None, None
            spent.update(transaction.inputs)
            apply_transaction(utxo, transaction, block.height)
            fees.append(fee)
        coinbase = block.transactions[0]
        for address, amount in coinbase.outputs:
            if address not in self.owners or amount == 0:
                return "bad-output tx 1", None, None
        if coinbase.output_total() > self.block_reward(block.height) + sum(fees):
            return "bad-coinbase", None, None
        apply_transaction(utxo, coinbase, block.height)
        return None, utxo, fees

    def connect_block(self, kind, block, peer):
        parent = self.records[block.previous]
        reason, utxo, fees = self.validate_block(block, parent)
        if reason is not None:
            self.reject_block(kind, block, peer, reason)
            return
        record = BlockRecord(block, parent, utxo, fees, peer.name)
        self.records[record.hash] = record
        peer.accepted_blocks += 1
        self.log(
            kind, peer.name, block.height, short(block.hash),
            "accepted", "work", record.cumulative_work,
        )
        if record.cumulative_work > self.tip.cumulative_work:
            self.switch_tip(record)

    def reject_block(self, kind, block, peer, reason):
        self.rejected.add(block.hash)
        peer.rejected_blocks += 1
        self.tally("block", reason.split()[0])
        self.log(kind, peer.name, block.height, short(block.hash), "rejected", reason)
        if reason != "time-too-new":
            self.penalize(peer, self.params.block_penalty)

    def resolve_orphans(self, start):
        queue = deque([start])
        while queue:
            parent_hash = queue.popleft()
            children = [orphan for orphan in self.orphans if orphan.block.previous == parent_hash]
            for orphan in children:
                self.orphans.remove(orphan)
                if parent_hash in self.rejected:
                    self.reject_block("UNORPHAN", orphan.block, orphan.peer, "bad-parent")
                else:
                    self.connect_block("UNORPHAN", orphan.block, orphan.peer)
                queue.append(orphan.block.hash)

    def status(self, txid):
        prefix = ("STATUS", short(txid))
        if txid in self.confirmed:
            height = self.confirmed[txid]
            self.log(*prefix, "confirmed", height, "confirmations", self.next_height() - height)
            return
        ranked = self.priority_order()
        for rank, entry in enumerate(ranked, 1):
            if entry.transaction.txid == txid:
                self.log(*prefix, "mempool", "rank", rank, "of", len(ranked))
                return
        if txid in self.drop_record:
            self.log(*prefix, "dropped", self.drop_record[txid])
        elif any(txid in record.block.txids() for record in self.records.values()):
            self.log(*prefix, "stale")
        else:
            self.log(*prefix, "unknown")

    def print_state(self):
        ranked = self.priority_order()
        self.log(
            "PRINT", "height", self.tip.height, "tip", short(self.tip.hash),
            "work", self.tip.cumulative_work, "bits", self.next_difficulty(self.tip),
            "reward", self.block_reward(self.next_height()), "mempool", len(ranked),
            "size", sum(entry.transaction.size for entry in ranked), "orphans", len(self.orphans),
        )
        for rank, entry in enumerate(ranked, 1):
            self.log(
                "MEMPOOL", rank, short(entry.transaction.txid),
                "fee", entry.fee, "size", entry.transaction.size,
            )
        for wallet in self.wallets:
            self.log("BALANCE", wallet.name, self.balance(wallet.address))


def miner_address(record):
    return record.block.transactions[0].outputs[0][0]


def block_lines(node, record):
    block = record.block
    miner = "-" if record.height == 0 else node.owners[miner_address(record)].name
    lines = [
        f"BLOCK {block.height} {block.hash} prev {short(block.previous)} time {block.timestamp} "
        f"bits {block.difficulty} nonce {block.nonce} txs {len(block.transactions)} "
        f"size {block.size()} fees {record.fees} miner {miner} source {record.source} "
        f"work {record.cumulative_work}"
    ]
    for position, transaction in enumerate(block.transactions, 1):
        if transaction.is_coinbase():
            category = "genesis" if block.height == 0 else "coinbase"
            lines.append(
                f"TX {position} {transaction.txid} {category} out {len(transaction.outputs)} "
                f"amount {transaction.output_total()}"
            )
        else:
            lines.append(
                f"TX {position} {transaction.txid} payment in {len(transaction.inputs)} "
                f"out {len(transaction.outputs)} size {transaction.size} "
                f"fee {record.transaction_fees[position - 2]}"
            )
    return lines


def difficulty_runs(records):
    runs = []
    for record in records:
        difficulty = record.block.difficulty
        if runs and runs[-1][0] == difficulty:
            runs[-1][2] = record.height
        else:
            runs.append([difficulty, record.height, record.height])
    return runs


def chain_lines(node):
    tip = node.tip
    lines = [
        f"TIP {tip.height} {tip.hash} work {tip.cumulative_work} "
        f"stored {len(node.records)} orphans {len(node.orphans)}"
    ]
    for record in node.main_chain:
        lines.extend(block_lines(node, record))
    main_hashes = {record.hash for record in node.main_chain}
    stale = [record for record in node.records.values() if record.hash not in main_hashes]
    stale.sort(key=lambda record: (record.height, record.hash))
    for record in stale:
        lines.append(
            f"STALE {record.height} {record.hash} prev {short(record.block.previous)} "
            f"source {record.source} work {record.cumulative_work}"
        )
    for orphan in node.orphans:
        block = orphan.block
        lines.append(
            f"ORPHAN {block.height} {block.hash} prev {short(block.previous)} "
            f"source {orphan.peer.name}"
        )
    for entry in node.reorganizations:
        lines.append(
            f"REORG {entry.time} fork {entry.fork_height} disconnected {entry.disconnected} "
            f"connected {entry.connected} old {short(entry.old_hash)} new {short(entry.new_hash)}"
        )
    mined = node.main_chain[1:]
    for wallet in node.wallets:
        own = [record for record in mined if miner_address(record) == wallet.address]
        if own:
            coinbase = sum(record.block.transactions[0].output_total() for record in own)
            fees = sum(record.fees for record in own)
            lines.append(f"MINER {wallet.name} blocks {len(own)} coinbase {coinbase} fees {fees}")
    for difficulty, first, last in difficulty_runs(mined):
        lines.append(f"BITS {difficulty} heights {first}-{last} blocks {last - first + 1}")
    for name in sorted(node.peers):
        peer = node.peers[name]
        state = "banned" if peer.score >= node.params.ban_score else "ok"
        lines.append(
            f"PEER {name} blocks {peer.accepted_blocks} rejected {peer.rejected_blocks} "
            f"orphans {peer.orphaned_blocks} txs {peer.accepted_txs} rejected {peer.rejected_txs} "
            f"ignored {peer.ignored} score {peer.score} {state}"
        )
    for rank, entry in enumerate(node.priority_order(), 1):
        transaction = entry.transaction
        lines.append(
            f"MEMPOOL {rank} {transaction.txid} fee {entry.fee} size {transaction.size} "
            f"time {entry.arrival}"
        )
    for (category, reason), count in sorted(node.rejections.items()):
        lines.append(f"REJECT {category} {reason} {count}")
    genesis = node.main_chain[0].block.transactions[0].output_total()
    rewards = sum(node.block_reward(record.height) for record in mined)
    fees = sum(record.fees for record in mined)
    minted = sum(record.block.transactions[0].output_total() for record in mined)
    total = sum(coin.amount for coin in tip.utxo.values())
    lines.append(
        f"SUPPLY genesis {genesis} rewards {rewards} fees {fees} "
        f"burned {rewards + fees - minted} utxo {total}"
    )
    return lines


def balance_lines(node):
    locked = node.locked_references()
    lines = [BALANCES_HEADER]
    for wallet in node.wallets:
        coins = [
            (reference, coin) for reference, coin in node.tip.utxo.items()
            if coin.address == wallet.address
        ]
        balance = sum(coin.amount for _, coin in coins)
        immature = sum(coin.amount for _, coin in coins if not node.is_mature(coin))
        locked_amount = sum(coin.amount for reference, coin in coins if reference in locked)
        incoming = sum(
            amount for entry in node.mempool
            for address, amount in entry.transaction.outputs if address == wallet.address
        )
        lines.append(
            f"{wallet.name},{wallet.address},{balance},{immature},{locked_amount},"
            f"{incoming},{len(coins)}"
        )
    return lines


def coin_category(coin):
    if coin.height == 0:
        return "genesis"
    return "coinbase" if coin.coinbase else "payment"


def coin_state(node, reference, coin, locked):
    if not node.is_mature(coin):
        return "immature"
    return "locked" if reference in locked else "free"


def utxo_lines(node):
    locked = node.locked_references()
    utxo = node.tip.utxo
    lines = []
    for reference in sorted(utxo):
        coin = utxo[reference]
        txid, index = reference
        lines.append(
            f"{txid}:{index} {node.owners[coin.address].name} {coin.amount} "
            f"height {coin.height} {coin_category(coin)} {coin_state(node, reference, coin, locked)}"
        )
    total = sum(coin.amount for coin in utxo.values())
    root = merkle_root([digest(line) for line in lines])
    return lines + [f"TOTAL {len(utxo)} {total}", f"ROOT {root}"]


def transaction_category(transaction, height):
    if not transaction.is_coinbase():
        return "payment"
    return "genesis" if height == 0 else "coinbase"


def wallet_history(node, wallet, confirmed):
    lines = [f"WALLET {wallet.name} {wallet.address}"]
    count = 0
    spent_total = 0
    received_total = 0
    balance = 0
    for record in node.main_chain:
        for transaction in record.block.transactions:
            spent = 0
            involved = False
            for txid, index in transaction.inputs:
                address, amount = confirmed[txid].outputs[index]
                if address == wallet.address:
                    spent += amount
                    involved = True
            received = 0
            for address, amount in transaction.outputs:
                if address == wallet.address:
                    received += amount
                    involved = True
            if not involved:
                continue
            count += 1
            spent_total += spent
            received_total += received
            balance += received - spent
            lines.append(
                f"{record.height} {short(transaction.txid)} "
                f"{transaction_category(transaction, record.height)} spent {spent} "
                f"received {received} net {signed(received - spent)} balance {balance}"
            )
    pending = 0
    for entry in node.priority_order():
        transaction = entry.transaction
        spent = sum(
            node.tip.utxo[reference].amount for reference in transaction.inputs
            if node.tip.utxo[reference].address == wallet.address
        )
        received = sum(
            amount for address, amount in transaction.outputs if address == wallet.address
        )
        if spent != 0 or received != 0:
            pending += 1
            lines.append(
                f"pending {short(transaction.txid)} spent {spent} received {received} "
                f"net {signed(received - spent)}"
            )
    lines.append(
        f"END {wallet.name} txs {count} spent {spent_total} received {received_total} "
        f"balance {balance} pending {pending}"
    )
    return lines


def history_lines(node):
    confirmed = {}
    for record in node.main_chain:
        for transaction in record.block.transactions:
            confirmed[transaction.txid] = transaction
    lines = []
    for wallet in node.wallets:
        lines.extend(wallet_history(node, wallet, confirmed))
    return lines


def write_lines(name, lines):
    with open(os.path.join(OUTPUT_DIR, name), "w") as handle:
        handle.write("".join(line + "\n" for line in lines))


def read_events(path):
    lines = read_lines(path)
    events = []
    position = 0
    while position < len(lines):
        fields = lines[position].split()
        count = int(fields[9]) if fields[1] == "BLOCK" else 0
        events.append((fields, lines[position + 1:position + 1 + count]))
        position += 1 + count
    return events


def main():
    params = Params(read_lines(os.path.join(INPUT_DIR, "params.txt")))
    wallets = read_wallets(os.path.join(INPUT_DIR, "wallets.txt"))
    node = Node(params, wallets)
    for fields, texts in read_events(os.path.join(INPUT_DIR, "events.txt")):
        node.process(fields, texts)
    os.makedirs(OUTPUT_DIR, exist_ok=True)
    write_lines("log.txt", node.log_lines)
    write_lines("chain.txt", chain_lines(node))
    write_lines("balances.csv", balance_lines(node))
    write_lines("utxo.txt", utxo_lines(node))
    write_lines("history.txt", history_lines(node))


if __name__ == "__main__":
    main()
