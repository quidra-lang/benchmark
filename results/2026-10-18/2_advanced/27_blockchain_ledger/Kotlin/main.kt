import java.nio.charset.StandardCharsets
import java.nio.file.Files
import java.nio.file.Path

private data class Entry(val transaction: Transaction, val fee: Int, val arrival: Int)
private data class Orphan(val block: Block, val peer: Peer)
private data class Reorganization(val time: Int, val fork: Int, val disconnected: Int, val connected: Int, val oldHash: String, val newHash: String)
private data class Acceptance(val reason: String?, val fee: Int = 0, val conflicts: List<Entry> = emptyList())
private data class Validation(val reason: String?, val utxo: Map<Reference, Coin>? = null, val fees: List<Int>? = null)
private class Peer(val name: String) {
    var blocks = 0;
    var rejectedBlocks = 0;
    var orphans = 0;
    var txs = 0;
    var rejectedTxs = 0;
    var ignored = 0;
    var score = 0
}
private class Params {
    val values = Files.readAllLines(Path.of("input/params.txt")).associate {
        val fields = it.split(" ");
        fields[0] to fields.drop(1)
    }
    fun value(name: String, index: Int = 0): Int = values.getValue(name)[index].toInt()
}
private class Node(val params: Params, val wallets: List<Wallet>) {
    val owners = wallets.associateBy {
        it.address
    }
    val named = wallets.associateBy {
        it.name
    }
    val records = mutableMapOf<String, BlockRecord>()
    val mempool = mutableListOf<Entry>()
    val orphans = mutableListOf<Orphan>()
    val rejected = mutableSetOf<String>()
    val drops = mutableMapOf<String, String>()
    val peers = sortedMapOf<String, Peer>()
    val rejections = sortedMapOf<String, Int>()
    val reorganizations = mutableListOf<Reorganization>()
    val logs = mutableListOf<String>()
    val confirmed = mutableMapOf<String, Int>()
    var mainChain = emptyList<BlockRecord>()
    var now = 0
    var tip: BlockRecord
    init {
        val outputs = params.values.getValue("GENESIS").chunked(2).map {
            Payment(named.getValue(it[0]).address, it[1].toInt())
        }
        val coinbase = Transactions.coinbase(0, outputs)
        val block = Block(0, "0".repeat(32), coinbase.txid, 0, 0, 0, listOf(coinbase))
        val utxo = mutableMapOf<Reference, Coin>()
        Transactions.apply(utxo, coinbase, 0)
        tip = BlockRecord(block, null, utxo, emptyList(), "genesis")
        records[block.hash] = tip
        refresh()
    }
    fun refresh() {
        mainChain = Chain.sequence(tip);
        confirmed.clear();
        for (record in mainChain) for (transaction in record.block.transactions) confirmed[transaction.txid] = record.block.height
    }
    fun log(line: String) {
        logs.add("$now $line")
    }
    fun tally(category: String, reason: String) {
        val key = "$category $reason";
        rejections[key] = rejections.getOrDefault(key, 0) + 1
    }
    fun height(): Int = tip.block.height + 1
    fun reward(height: Int): Int = Chain.reward(height, params.value("REWARD"), params.value("REWARD", 1))
    fun difficulty(parent: BlockRecord): Int = Chain.difficulty(parent, params.value("DIFFICULTY"), params.value("RETARGET"), params.value("RETARGET", 1))
    fun mature(coin: Coin): Boolean = coin.mature(height(), params.value("MATURITY"))
    fun balance(address: String): Int = tip.utxo.values.filter {
        it.address == address
    }.sumOf {
        it.amount
    }
    fun locked(): Set<Reference> = mempool.flatMap {
        it.transaction.inputs
    }.toSet()
    fun ranked(): List<Entry> = mempool.sortedWith {
        first, second ->
        val rate = (second.fee * first.transaction.size).compareTo(first.fee * second.transaction.size)
        if (rate != 0) rate else first.transaction.txid.compareTo(second.transaction.txid)
    }
    fun find(txid: String): Entry? = mempool.find {
        it.transaction.txid == txid
    }
    fun acceptance(transaction: Transaction): Acceptance {
        if (transaction.coinbase) return Acceptance("coinbase")
        if (transaction.txid in confirmed || find(transaction.txid) != null) return Acceptance("duplicate")
        val check = Transactions.check(transaction, tip.utxo, emptySet(), height(), owners, params.value("MATURITY"))
        if (check.reason != null) return Acceptance(check.reason)
        val fee = check.fee
        val size = transaction.size
        if (fee * 1000 < params.value("MINFEERATE") * size) return Acceptance("low-fee")
        val inputs = transaction.inputs.toSet()
        val conflicts = mempool.filter {
            entry -> entry.transaction.inputs.any {
                it in inputs
            }
        }
        if (conflicts.isNotEmpty() && (fee <= conflicts.sumOf {
            it.fee
        }
        || conflicts.any {
            fee * it.transaction.size <= it.fee * size
        })) return Acceptance("conflict")
        return Acceptance(null, fee, conflicts)
    }
    fun recordDrop(txid: String, reason: String) {
        drops[txid] = reason;
        log("DROP ${Hashing.shortId(txid)} $reason")
    }
    fun drop(entry: Entry, reason: String) {
        mempool.remove(entry);
        recordDrop(entry.transaction.txid, reason)
    }
    fun register(transaction: Transaction, result: Acceptance, arrival: Int) {
        for (entry in result.conflicts) drop(entry, "replaced")
        mempool.add(Entry(transaction, result.fee, arrival))
        if (mempool.size > params.value("MEMPOOL")) drop(ranked().last(), "mempool-full")
    }
    fun rebuild(returned: List<Transaction>) {
        val previous = mempool.toList();
        mempool.clear()
        for (transaction in returned) rebuildEntry(transaction, now, true)
        for (entry in previous) rebuildEntry(entry.transaction, entry.arrival, false)
    }
    fun rebuildEntry(transaction: Transaction, arrival: Int, returned: Boolean) {
        if (transaction.txid in confirmed) return
        val result = acceptance(transaction)
        if (result.reason != null) {
            recordDrop(transaction.txid, result.reason);
            return
        }
        if (returned) log("RETURN ${Hashing.shortId(transaction.txid)}")
        register(transaction, result, arrival)
    }
    fun switchTip(target: BlockRecord) {
        val old = tip
        val fork = Chain.fork(old, target)
        val disconnected = old.block.height - fork.block.height
        val connected = target.block.height - fork.block.height
        val targetText = "${target.block.height} ${Hashing.shortId(target.block.hash)} work ${target.work}"
        if (disconnected > params.value("MAXREORG")) {
            log("REFUSE $targetText fork ${fork.block.height} depth $disconnected");
            return
        }
        val returned = mainChain.drop(fork.block.height + 1).flatMap {
            it.block.transactions.drop(1)
        }
        tip = target;
        refresh()
        if (disconnected == 0) log("TIP $targetText")
        else {
            log("REORG $targetText fork ${fork.block.height} disconnected $disconnected connected $connected")
            reorganizations.add(Reorganization(now, fork.block.height, disconnected, connected, old.block.hash, target.block.hash))
        }
        rebuild(returned)
    }
    fun penalize(peer: Peer, points: Int) {
        val before = peer.score;
        peer.score += points;
        if (before < params.value("BAN") && peer.score >= params.value("BAN")) log("BAN ${peer.name} score ${peer.score}")
    }
    fun process(fields: List<String>, texts: List<String>) {
        now = fields[0].toInt()
        for (entry in mempool.toList()) if (now - entry.arrival >= params.value("EXPIRY")) drop(entry, "expired")
        when (fields[1]) {
            "PAY" -> pay(fields)
            "BUMP" -> bump(fields[2], fields[3].toInt())
            "MINE" -> mine(named.getValue(fields[2]))
            "STATUS" -> status(fields[2])
            "PRINT" -> printState()
            else -> {
                val peer = peers.getOrPut(fields[2]) {
                    Peer(fields[2])
                }
                if (peer.score >= params.value("BAN")) {
                    peer.ignored++;
                    log("IGNORE ${peer.name} ${fields[1]}")
                }
                else if (fields[1] == "TX") receiveTransaction(peer, Transactions.parse(fields[3]))
                else receiveBlock(peer, Blocks.parse(fields, texts))
            }
        }
    }
    fun pay(fields: List<String>) {
        val sender = named.getValue(fields[2]);
        val fee = fields[3].toInt()
        val outputs = fields.drop(4).chunked(2).map {
            Payment(named.getValue(it[0]).address, it[1].toInt())
        }.toMutableList()
        val total = outputs.sumOf {
            it.amount
        };
        var prefix = "PAY ${sender.name} fee $fee total $total"
        val locked = locked()
        val candidates = tip.utxo.keys.filter {
            val coin = tip.utxo.getValue(it);
            coin.address == sender.address && it !in locked && mature(coin)
        }.sortedWith(compareByDescending<Reference> {
            tip.utxo.getValue(it).amount
        }.thenBy {
            it
        })
        val inputs = mutableListOf<Reference>();
        var gathered = 0
        for (reference in candidates) {
            if (gathered >= total + fee) break;
            inputs.add(reference);
            gathered += tip.utxo.getValue(reference).amount
        }
        if (gathered < total + fee) {
            log("$prefix rejected insufficient-funds");
            tally("pay", "insufficient-funds");
            return
        }
        if (gathered > total + fee) outputs.add(Payment(sender.address, gathered - total - fee))
        val transaction = Transactions.create(inputs, outputs, sender.secret);
        val result = acceptance(transaction)
        prefix += " tx ${Hashing.shortId(transaction.txid)}"
        if (result.reason != null) {
            log("$prefix rejected ${result.reason}");
            tally("pay", result.reason);
            return
        }
        log("$prefix accepted inputs ${inputs.size} outputs ${outputs.size} size ${transaction.size}");
        register(transaction, result, now)
    }
    fun bump(txid: String, fee: Int) {
        var prefix = "BUMP ${Hashing.shortId(txid)} fee $fee"
        val entry = find(txid)
        if (entry == null) {
            log("$prefix rejected unknown");
            tally("bump", "unknown");
            return
        }
        val original = entry.transaction;
        val addresses = original.inputs.map {
            tip.utxo.getValue(it).address
        }.toSet()
        val last = original.outputs.last();
        val change = last.amount - (fee - entry.fee)
        if (addresses != setOf(last.address) || change < 1) {
            log("$prefix rejected no-change");
            tally("bump", "no-change");
            return
        }
        val outputs = original.outputs.dropLast(1) + Payment(last.address, change)
        val transaction = Transactions.create(original.inputs, outputs, owners.getValue(last.address).secret);
        val result = acceptance(transaction)
        prefix += " tx ${Hashing.shortId(transaction.txid)}"
        if (result.reason != null) {
            log("$prefix rejected ${result.reason}");
            tally("bump", result.reason);
            return
        }
        log("$prefix accepted size ${transaction.size}");
        register(transaction, result, now)
    }
    fun receiveTransaction(peer: Peer, transaction: Transaction) {
        val result = acceptance(transaction);
        val prefix = "TX ${peer.name} ${Hashing.shortId(transaction.txid)}"
        if (result.reason != null) {
            peer.rejectedTxs++;
            tally("tx", result.reason);
            log("$prefix rejected ${result.reason}")
            if (result.reason in setOf("coinbase", "bad-output", "bad-sig", "overspend")) penalize(peer, params.value("BAN", 2))
            return
        }
        peer.txs++;
        log("$prefix accepted fee ${result.fee} size ${transaction.size}");
        register(transaction, result, now)
    }
    fun mine(wallet: Wallet) {
        val transactions = mutableListOf<Transaction>();
        val fees = mutableListOf<Int>();
        var size = 0
        for (entry in ranked()) if (size + entry.transaction.size <= params.value("MAXBLOCK")) {
            size += entry.transaction.size;
            transactions.add(entry.transaction);
            fees.add(entry.fee)
        }
        transactions.add(0, Transactions.coinbase(height(), listOf(Payment(wallet.address, reward(height()) + fees.sum()))))
        val block = Blocks.mine(height(), tip.block.hash, transactions, maxOf(now, Chain.median(tip) + 1), difficulty(tip))
        val utxo = tip.utxo.toMutableMap();
        for (transaction in transactions) Transactions.apply(utxo, transaction, block.height)
        val record = BlockRecord(block, tip, utxo, fees, "local");
        records[block.hash] = record
        log("MINE ${wallet.name} ${block.height} ${Hashing.shortId(block.hash)} bits ${block.difficulty} nonce ${block.nonce} txs ${transactions.size} size ${block.size} fees ${fees.sum()} work ${record.work}")
        switchTip(record)
    }
    fun receiveBlock(peer: Peer, block: Block) {
        if (block.hash in records || orphans.any {
            it.block.hash == block.hash
        }
        || block.hash in rejected) {
            peer.rejectedBlocks++;
            tally("block", "duplicate");
            log("BLOCK ${peer.name} ${block.height} ${Hashing.shortId(block.hash)} rejected duplicate");
            return
        }
        var reason = Blocks.error(block, params.value("MAXBLOCK"))
        if (reason == null && block.previous in rejected) reason = "bad-parent"
        if (reason != null) {
            rejectBlock("BLOCK", block, peer, reason);
            resolve(block.hash);
            return
        }
        if (block.previous !in records) {
            orphans.add(Orphan(block, peer));
            peer.orphans++;
            log("BLOCK ${peer.name} ${block.height} ${Hashing.shortId(block.hash)} orphan parent ${Hashing.shortId(block.previous)}")
            if (orphans.size > params.value("ORPHANS")) log("EVICT ${Hashing.shortId(orphans.removeAt(0).block.hash)} orphan-limit")
            return
        }
        connect("BLOCK", block, peer);
        resolve(block.hash)
    }
    fun validate(block: Block, parent: BlockRecord): Validation {
        val reason = when {
            block.height != parent.block.height + 1 -> "bad-height"
            block.difficulty != difficulty(parent) -> "bad-difficulty"
            block.timestamp <= Chain.median(parent) -> "time-too-old"
            block.timestamp > now + params.value("DRIFT") -> "time-too-new"
            else -> null
        }
        if (reason != null) return Validation(reason)
        val utxo = parent.utxo.toMutableMap();
        val spent = mutableSetOf<Reference>();
        val fees = mutableListOf<Int>()
        for (i in 1 until block.transactions.size) {
            val transaction = block.transactions[i];
            val check = Transactions.check(transaction, utxo, spent, block.height, owners, params.value("MATURITY"))
            if (check.reason != null) return Validation("${check.reason} tx ${i + 1}")
            spent.addAll(transaction.inputs);
            Transactions.apply(utxo, transaction, block.height);
            fees.add(check.fee)
        }
        val coinbase = block.transactions.first()
        for (output in coinbase.outputs) if (output.address !in owners || output.amount == 0) return Validation("bad-output tx 1")
        if (coinbase.total > reward(block.height) + fees.sum()) return Validation("bad-coinbase")
        Transactions.apply(utxo, coinbase, block.height);
        return Validation(null, utxo, fees)
    }
    fun connect(kind: String, block: Block, peer: Peer) {
        val parent = records.getValue(block.previous);
        val result = validate(block, parent)
        if (result.reason != null) {
            rejectBlock(kind, block, peer, result.reason);
            return
        }
        val record = BlockRecord(block, parent, result.utxo!!, result.fees!!, peer.name);
        records[block.hash] = record;
        peer.blocks++
        log("$kind ${peer.name} ${block.height} ${Hashing.shortId(block.hash)} accepted work ${record.work}")
        if (record.work > tip.work) switchTip(record)
    }
    fun rejectBlock(kind: String, block: Block, peer: Peer, reason: String) {
        rejected.add(block.hash);
        peer.rejectedBlocks++;
        tally("block", reason.substringBefore(' '));
        log("$kind ${peer.name} ${block.height} ${Hashing.shortId(block.hash)} rejected $reason")
        if (reason != "time-too-new") penalize(peer, params.value("BAN", 1))
    }
    fun resolve(start: String) {
        val queue = ArrayDeque<String>();
        queue.add(start)
        while (queue.isNotEmpty()) {
            val parent = queue.removeFirst();
            val children = orphans.filter {
                it.block.previous == parent
            }
            for (orphan in children) {
                orphans.remove(orphan);
                if (parent in rejected) rejectBlock("UNORPHAN", orphan.block, orphan.peer, "bad-parent") else connect("UNORPHAN", orphan.block, orphan.peer);
                queue.addLast(orphan.block.hash)
            }
        }
    }
    fun status(txid: String) {
        val prefix = "STATUS ${Hashing.shortId(txid)}"
        val confirmedHeight = confirmed[txid]
        if (confirmedHeight != null) {
            log("$prefix confirmed $confirmedHeight confirmations ${height() - confirmedHeight}");
            return
        }
        val entries = ranked();
        val index = entries.indexOfFirst {
            it.transaction.txid == txid
        }
        if (index >= 0) {
            log("$prefix mempool rank ${index + 1} of ${entries.size}");
            return
        }
        when {
            txid in drops -> log("$prefix dropped ${drops.getValue(txid)}")
            records.values.any {
                txid in it.block.txids
            }
            -> log("$prefix stale")
            else -> log("$prefix unknown")
        }
    }
    fun printState() {
        val entries = ranked()
        log("PRINT height ${tip.block.height} tip ${Hashing.shortId(tip.block.hash)} work ${tip.work} bits ${difficulty(tip)} reward ${reward(height())} mempool ${entries.size} size ${entries.sumOf { it.transaction.size }} orphans ${orphans.size}")
        for ((i, entry) in entries.withIndex()) log("MEMPOOL ${i + 1} ${Hashing.shortId(entry.transaction.txid)} fee ${entry.fee} size ${entry.transaction.size}")
        for (wallet in wallets) log("BALANCE ${wallet.name} ${balance(wallet.address)}")
    }
    fun miner(record: BlockRecord): String = record.block.transactions.first().outputs.first().address
    fun chainLines(): List<String> {
        val lines = mutableListOf("TIP ${tip.block.height} ${tip.block.hash} work ${tip.work} stored ${records.size} orphans ${orphans.size}")
        val mainHashes = mainChain.map {
            it.block.hash
        }.toSet()
        for (record in mainChain) {
            val block = record.block;
            val miner = if (block.height == 0) "-" else owners.getValue(miner(record)).name
            lines.add("BLOCK ${block.height} ${block.hash} prev ${Hashing.shortId(block.previous)} time ${block.timestamp} bits ${block.difficulty} nonce ${block.nonce} txs ${block.transactions.size} size ${block.size} fees ${record.fees} miner $miner source ${record.source} work ${record.work}")
            for ((i, transaction) in block.transactions.withIndex()) {
                val prefix = "TX ${i + 1} ${transaction.txid}"
                if (transaction.coinbase) lines.add("$prefix ${if (block.height == 0) "genesis" else "coinbase"} out ${transaction.outputs.size} amount ${transaction.total}")
                else lines.add("$prefix payment in ${transaction.inputs.size} out ${transaction.outputs.size} size ${transaction.size} fee ${record.transactionFees[i - 1]}")
            }
        }
        val stale = records.values.filter {
            it.block.hash !in mainHashes
        }.sortedWith(compareBy<BlockRecord> {
            it.block.height
        }.thenBy {
            it.block.hash
        })
        for (record in stale) lines.add("STALE ${record.block.height} ${record.block.hash} prev ${Hashing.shortId(record.block.previous)} source ${record.source} work ${record.work}")
        for (orphan in orphans) lines.add("ORPHAN ${orphan.block.height} ${orphan.block.hash} prev ${Hashing.shortId(orphan.block.previous)} source ${orphan.peer.name}")
        for (entry in reorganizations) lines.add("REORG ${entry.time} fork ${entry.fork} disconnected ${entry.disconnected} connected ${entry.connected} old ${Hashing.shortId(entry.oldHash)} new ${Hashing.shortId(entry.newHash)}")
        val mined = mainChain.drop(1)
        for (wallet in wallets) {
            val own = mined.filter {
                miner(it) == wallet.address
            }
            if (own.isNotEmpty()) lines.add("MINER ${wallet.name} blocks ${own.size} coinbase ${own.sumOf { it.block.transactions.first().total }} fees ${own.sumOf { it.fees }}")
        }
        var start = 0
        while (start < mined.size) {
            var end = start
            while (end + 1 < mined.size && mined[end + 1].block.difficulty == mined[start].block.difficulty) end++
            lines.add("BITS ${mined[start].block.difficulty} heights ${mined[start].block.height}-${mined[end].block.height} blocks ${end - start + 1}")
            start = end + 1
        }
        for (peer in peers.values) lines.add("PEER ${peer.name} blocks ${peer.blocks} rejected ${peer.rejectedBlocks} orphans ${peer.orphans} txs ${peer.txs} rejected ${peer.rejectedTxs} ignored ${peer.ignored} score ${peer.score} ${if (peer.score >= params.value("BAN")) "banned" else "ok"}")
        for ((i, entry) in ranked().withIndex()) lines.add("MEMPOOL ${i + 1} ${entry.transaction.txid} fee ${entry.fee} size ${entry.transaction.size} time ${entry.arrival}")
        for ((key, count) in rejections) lines.add("REJECT $key $count")
        val rewards = mined.sumOf {
            reward(it.block.height)
        };
        val fees = mined.sumOf {
            it.fees
        };
        val minted = mined.sumOf {
            it.block.transactions.first().total
        }
        lines.add("SUPPLY genesis ${mainChain.first().block.transactions.first().total} rewards $rewards fees $fees burned ${rewards + fees - minted} utxo ${tip.utxo.values.sumOf { it.amount }}")
        return lines
    }
    fun balanceLines(): List<String> {
        val lines = mutableListOf("wallet,address,balance,immature,locked,incoming,utxos");
        val locked = locked()
        for (wallet in wallets) {
            val coins = tip.utxo.filterValues {
                it.address == wallet.address
            }
            val total = coins.values.sumOf {
                it.amount
            };
            val immature = coins.values.filter {
                !mature(it)
            }.sumOf {
                it.amount
            };
            val lockedAmount = coins.filterKeys {
                it in locked
            }.values.sumOf {
                it.amount
            }
            val incoming = mempool.sumOf {
                entry -> entry.transaction.outputs.filter {
                    it.address == wallet.address
                }.sumOf {
                    it.amount
                }
            }
            lines.add("${wallet.name},${wallet.address},$total,$immature,$lockedAmount,$incoming,${coins.size}")
        }
        return lines
    }
    fun utxoLines(): List<String> {
        val lines = mutableListOf<String>();
        val locked = locked()
        for (reference in tip.utxo.keys.sorted()) {
            val coin = tip.utxo.getValue(reference)
            val category = if (coin.height == 0) "genesis" else if (coin.coinbase) "coinbase" else "payment"
            val state = if (!mature(coin)) "immature" else if (reference in locked) "locked" else "free"
            lines.add("$reference ${owners.getValue(coin.address).name} ${coin.amount} height ${coin.height} $category $state")
        }
        val root = Hashing.merkle(lines.map(Hashing::digest));
        lines.add("TOTAL ${tip.utxo.size} ${tip.utxo.values.sumOf { it.amount }}");
        lines.add("ROOT $root")
        return lines
    }
    fun historyLines(): List<String> {
        val lines = mutableListOf<String>();
        val transactions = mainChain.flatMap {
            it.block.transactions
        }.associateBy {
            it.txid
        }
        for (wallet in wallets) {
            lines.add("WALLET ${wallet.name} ${wallet.address}")
            var count = 0;
            var spentTotal = 0;
            var receivedTotal = 0;
            var balance = 0;
            var pending = 0
            for (record in mainChain) for (transaction in record.block.transactions) {
                val inputs = transaction.inputs.map {
                    transactions.getValue(it.txid).outputs[it.index]
                }.filter {
                    it.address == wallet.address
                }
                val outputs = transaction.outputs.filter {
                    it.address == wallet.address
                }
                if (inputs.isEmpty() && outputs.isEmpty()) continue
                val spent = inputs.sumOf {
                    it.amount
                };
                val received = outputs.sumOf {
                    it.amount
                }
                count++;
                spentTotal += spent;
                receivedTotal += received;
                balance += received - spent
                val category = if (!transaction.coinbase) "payment" else if (record.block.height == 0) "genesis" else "coinbase"
                lines.add("${record.block.height} ${Hashing.shortId(transaction.txid)} $category spent $spent received $received net ${signed(received - spent)} balance $balance")
            }
            for (entry in ranked()) {
                val transaction = entry.transaction
                val spent = transaction.inputs.map {
                    tip.utxo.getValue(it)
                }.filter {
                    it.address == wallet.address
                }.sumOf {
                    it.amount
                }
                val received = transaction.outputs.filter {
                    it.address == wallet.address
                }.sumOf {
                    it.amount
                }
                if (spent != 0 || received != 0) {
                    pending++;
                    lines.add("pending ${Hashing.shortId(transaction.txid)} spent $spent received $received net ${signed(received - spent)}")
                }
            }
            lines.add("END ${wallet.name} txs $count spent $spentTotal received $receivedTotal balance $balance pending $pending")
        }
        return lines
    }
}
private fun signed(value: Int): String = if (value >= 0) "+$value" else value.toString()
private fun write(name: String, lines: List<String>) {
    Files.writeString(Path.of("output", name), if (lines.isEmpty()) "" else lines.joinToString("\n", postfix = "\n"), StandardCharsets.US_ASCII)
}
fun main() {
    val node = Node(Params(), Wallets.read());
    val lines = Files.readAllLines(Path.of("input/events.txt"));
    var position = 0
    while (position < lines.size) {
        val fields = lines[position].split(" ");
        val count = if (fields[1] == "BLOCK") fields[9].toInt() else 0
        node.process(fields, lines.subList(position + 1, position + count + 1));
        position += count + 1
    }
    Files.createDirectories(Path.of("output"))
    write("log.txt", node.logs);
    write("chain.txt", node.chainLines());
    write("balances.csv", node.balanceLines());
    write("utxo.txt", node.utxoLines());
    write("history.txt", node.historyLines())
}
