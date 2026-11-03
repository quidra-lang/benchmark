import java.io.*;
import java.nio.charset.StandardCharsets;
import java.nio.file.*;
import java.util.*;

public final class Main {
    record Entry(Transaction transaction, int fee, int arrival) {}
    record Orphan(Block block, Peer peer) {}
    record
        Reorganization(int time, int fork, int disconnected, int connected, String oldHash, String newHash) {}
    record Acceptance(String reason, int fee, List<Entry> conflicts) {}
    record Validation(String reason, Map<Reference, Coin> utxo, List<Integer> fees) {}
    static final class Peer {
        final String name;
        int blocks, rejectedBlocks, orphans, txs, rejectedTxs, ignored, score;
        Peer(String name) {
            this.name = name;
        }
    }
    static final class Params {
        final Map<String, String[]> values = new HashMap<>();
        Params() throws IOException {
            for (String line : Files.readAllLines(Path.of("input/params.txt"), StandardCharsets.US_ASCII)) {
                String[] fields = line.split(" ");
                values.put(fields[0], Arrays.copyOfRange(fields, 1, fields.length));
            }
        }
        int value(String name, int index) {
            return Integer.parseInt(values.get(name)[index]);
        }
        int value(String name) {
            return value(name, 0);
        }
    }
    static final class Node {
        final Params params;
        final List<Wallet> wallets;
        final Map<String, Wallet> owners = new HashMap<>(), named = new HashMap<>();
        final Map<String, BlockRecord> records = new HashMap<>();
        final List<Entry> mempool = new ArrayList<>();
        final List<Orphan> orphans = new ArrayList<>();
        final Set<String> rejected = new HashSet<>();
        final Map<String, String> drops = new HashMap<>();
        final Map<String, Peer> peers = new TreeMap<>();
        final Map<String, Integer> rejections = new TreeMap<>();
        final List<Reorganization> reorganizations = new ArrayList<>();
        final List<String> logs = new ArrayList<>();
        final Map<String, Integer> confirmed = new HashMap<>();
        List<BlockRecord> mainChain;
        BlockRecord tip;
        int now;
        Node(Params params, List<Wallet> wallets) {
            this.params = params;
            this.wallets = wallets;
            for (Wallet wallet : wallets) {
                owners.put(wallet.address(), wallet);
                named.put(wallet.name(), wallet);
            }
            List<Payment> outputs = new ArrayList<>();
            String[] genesis = params.values.get("GENESIS");
            for (int i = 0; i < genesis.length; i += 2)
                outputs.add(new Payment(named.get(genesis[i]).address(), Integer.parseInt(genesis[i + 1])));
            Transaction coinbase = Transactions.coinbase(0, outputs);
            Block block = new Block(0, "0".repeat(32), coinbase.txid, 0, 0, 0, List.of(coinbase));
            Map<Reference, Coin> utxo = new HashMap<>();
            Transactions.apply(utxo, coinbase, 0);
            tip = new BlockRecord(block, null, utxo, List.of(), "genesis");
            records.put(block.hash, tip);
            refresh();
        }
        void refresh() {
            mainChain = Chain.sequence(tip);
            confirmed.clear();
            for (BlockRecord record : mainChain)
                for (Transaction transaction : record.block.transactions)
                    confirmed.put(transaction.txid, record.block.height);
        }
        void log(String line) {
            logs.add(now + " " + line);
        }
        void tally(String category, String reason) {
            String key = category + " " + reason;
            rejections.merge(key, 1, Integer::sum);
        }
        int height() {
            return tip.block.height + 1;
        }
        int reward(int height) {
            return Chain.reward(height, params.value("REWARD"), params.value("REWARD", 1));
        }
        int difficulty(BlockRecord parent) {
            return Chain.difficulty(parent, params.value("DIFFICULTY"), params.value("RETARGET"),
                                    params.value("RETARGET", 1));
        }
        boolean mature(Coin coin) {
            return coin.mature(height(), params.value("MATURITY"));
        }
        int balance(String address) {
            int total = 0;
            for (Coin coin : tip.utxo.values())
                if (coin.address().equals(address))
                    total += coin.amount();
            return total;
        }
        Set<Reference> locked() {
            Set<Reference> references = new HashSet<>();
            for (Entry entry : mempool)
                references.addAll(entry.transaction.inputs);
            return references;
        }
        List<Entry> ranked() {
            List<Entry> entries = new ArrayList<>(mempool);
            entries.sort((first, second) -> {
                int rate = Integer.compare(second.fee * first.transaction.size(),
                                           first.fee * second.transaction.size());
                return rate != 0 ? rate : first.transaction.txid.compareTo(second.transaction.txid);
            });
            return entries;
        }
        Entry find(String txid) {
            for (Entry entry : mempool)
                if (entry.transaction.txid.equals(txid))
                    return entry;
            return null;
        }
        Acceptance acceptance(Transaction transaction) {
            if (transaction.coinbase())
                return new Acceptance("coinbase", 0, List.of());
            if (confirmed.containsKey(transaction.txid) || find(transaction.txid) != null)
                return new Acceptance("duplicate", 0, List.of());
            Check check = Transactions.check(transaction, tip.utxo, Set.of(), height(), owners,
                                             params.value("MATURITY"));
            if (check.reason() != null)
                return new Acceptance(check.reason(), 0, List.of());
            int fee = check.fee(), size = transaction.size();
            if (fee * 1000 < params.value("MINFEERATE") * size)
                return new Acceptance("low-fee", 0, List.of());
            Set<Reference> inputs = new HashSet<>(transaction.inputs);
            List<Entry> conflicts = new ArrayList<>();
            int fees = 0;
            boolean higher = true;
            for (Entry entry : mempool) {
                if (Collections.disjoint(inputs, entry.transaction.inputs))
                    continue;
                conflicts.add(entry);
                fees += entry.fee;
                if (fee * entry.transaction.size() <= entry.fee * size)
                    higher = false;
            }
            if (!conflicts.isEmpty() && (fee <= fees || !higher))
                return new Acceptance("conflict", 0, List.of());
            return new Acceptance(null, fee, conflicts);
        }
        void recordDrop(String txid, String reason) {
            drops.put(txid, reason);
            log("DROP " + Hashing.shortId(txid) + " " + reason);
        }
        void drop(Entry entry, String reason) {
            mempool.remove(entry);
            recordDrop(entry.transaction.txid, reason);
        }
        void register(Transaction transaction, Acceptance result, int arrival) {
            for (Entry entry : result.conflicts)
                drop(entry, "replaced");
            mempool.add(new Entry(transaction, result.fee, arrival));
            if (mempool.size() > params.value("MEMPOOL"))
                drop(ranked().getLast(), "mempool-full");
        }
        void rebuild(List<Transaction> returned) {
            List<Entry> previous = new ArrayList<>(mempool);
            mempool.clear();
            for (Transaction transaction : returned)
                rebuildEntry(transaction, now, true);
            for (Entry entry : previous)
                rebuildEntry(entry.transaction, entry.arrival, false);
        }
        void rebuildEntry(Transaction transaction, int arrival, boolean returned) {
            if (confirmed.containsKey(transaction.txid))
                return;
            Acceptance result = acceptance(transaction);
            if (result.reason != null) {
                recordDrop(transaction.txid, result.reason);
                return;
            }
            if (returned)
                log("RETURN " + Hashing.shortId(transaction.txid));
            register(transaction, result, arrival);
        }
        void switchTip(BlockRecord target) {
            BlockRecord old = tip, fork = Chain.fork(old, target);
            int disconnected = old.block.height - fork.block.height,
                connected = target.block.height - fork.block.height;
            String targetText =
                target.block.height + " " + Hashing.shortId(target.block.hash) + " work " + target.work;
            if (disconnected > params.value("MAXREORG")) {
                log("REFUSE " + targetText + " fork " + fork.block.height + " depth " + disconnected);
                return;
            }
            List<Transaction> returned = new ArrayList<>();
            for (BlockRecord record : mainChain.subList(fork.block.height + 1, mainChain.size()))
                returned.addAll(record.block.transactions.subList(1, record.block.transactions.size()));
            tip = target;
            refresh();
            if (disconnected == 0)
                log("TIP " + targetText);
            else {
                log("REORG " + targetText + " fork " + fork.block.height + " disconnected " + disconnected +
                    " connected " + connected);
                reorganizations.add(new Reorganization(now, fork.block.height, disconnected, connected,
                                                       old.block.hash, target.block.hash));
            }
            rebuild(returned);
        }
        void penalize(Peer peer, int points) {
            int before = peer.score;
            peer.score += points;
            if (before < params.value("BAN") && peer.score >= params.value("BAN"))
                log("BAN " + peer.name + " score " + peer.score);
        }
        void process(String[] fields, List<String> texts) {
            now = Integer.parseInt(fields[0]);
            for (Entry entry : new ArrayList<>(mempool))
                if (now - entry.arrival >= params.value("EXPIRY"))
                    drop(entry, "expired");
            switch (fields[1]) {
            case "PAY" -> pay(fields);
            case "BUMP" -> bump(fields[2], Integer.parseInt(fields[3]));
            case "MINE" -> mine(named.get(fields[2]));
            case "STATUS" -> status(fields[2]);
            case "PRINT" -> printState();
            default -> {
                Peer peer = peers.computeIfAbsent(fields[2], Peer::new);
                if (peer.score >= params.value("BAN")) {
                    peer.ignored++;
                    log("IGNORE " + peer.name + " " + fields[1]);
                } else if (fields[1].equals("TX"))
                    receiveTransaction(peer, Transactions.parse(fields[3]));
                else
                    receiveBlock(peer, Blocks.parse(fields, texts));
            }
            }
        }
        void pay(String[] fields) {
            Wallet sender = named.get(fields[2]);
            int fee = Integer.parseInt(fields[3]), total = 0;
            List<Payment> outputs = new ArrayList<>();
            for (int i = 4; i < fields.length; i += 2) {
                int amount = Integer.parseInt(fields[i + 1]);
                outputs.add(new Payment(named.get(fields[i]).address(), amount));
                total += amount;
            }
            String prefix = "PAY " + sender.name() + " fee " + fee + " total " + total;
            Set<Reference> locked = locked();
            List<Reference> candidates = new ArrayList<>();
            for (Map.Entry<Reference, Coin> pair : tip.utxo.entrySet())
                if (pair.getValue().address().equals(sender.address()) && !locked.contains(pair.getKey()) &&
                    mature(pair.getValue()))
                    candidates.add(pair.getKey());
            candidates.sort((first, second) -> {
                int amount = Integer.compare(tip.utxo.get(second).amount(), tip.utxo.get(first).amount());
                return amount != 0 ? amount : first.compareTo(second);
            });
            List<Reference> inputs = new ArrayList<>();
            int gathered = 0;
            for (Reference reference : candidates) {
                if (gathered >= total + fee)
                    break;
                inputs.add(reference);
                gathered += tip.utxo.get(reference).amount();
            }
            if (gathered < total + fee) {
                log(prefix + " rejected insufficient-funds");
                tally("pay", "insufficient-funds");
                return;
            }
            if (gathered > total + fee)
                outputs.add(new Payment(sender.address(), gathered - total - fee));
            Transaction transaction = Transactions.create(inputs, outputs, sender.secret());
            Acceptance result = acceptance(transaction);
            prefix += " tx " + Hashing.shortId(transaction.txid);
            if (result.reason != null) {
                log(prefix + " rejected " + result.reason);
                tally("pay", result.reason);
                return;
            }
            log(prefix + " accepted inputs " + inputs.size() + " outputs " + outputs.size() + " size " +
                transaction.size());
            register(transaction, result, now);
        }
        void bump(String txid, int fee) {
            String prefix = "BUMP " + Hashing.shortId(txid) + " fee " + fee;
            Entry entry = find(txid);
            if (entry == null) {
                log(prefix + " rejected unknown");
                tally("bump", "unknown");
                return;
            }
            Transaction original = entry.transaction;
            Set<String> addresses = new HashSet<>();
            for (Reference reference : original.inputs)
                addresses.add(tip.utxo.get(reference).address());
            Payment last = original.outputs.getLast();
            int change = last.amount() - (fee - entry.fee);
            if (addresses.size() != 1 || !addresses.contains(last.address()) || change < 1) {
                log(prefix + " rejected no-change");
                tally("bump", "no-change");
                return;
            }
            List<Payment> outputs = new ArrayList<>(original.outputs);
            outputs.set(outputs.size() - 1, new Payment(last.address(), change));
            Transaction transaction =
                Transactions.create(original.inputs, outputs, owners.get(last.address()).secret());
            Acceptance result = acceptance(transaction);
            prefix += " tx " + Hashing.shortId(transaction.txid);
            if (result.reason != null) {
                log(prefix + " rejected " + result.reason);
                tally("bump", result.reason);
                return;
            }
            log(prefix + " accepted size " + transaction.size());
            register(transaction, result, now);
        }
        void receiveTransaction(Peer peer, Transaction transaction) {
            Acceptance result = acceptance(transaction);
            String prefix = "TX " + peer.name + " " + Hashing.shortId(transaction.txid);
            if (result.reason != null) {
                peer.rejectedTxs++;
                tally("tx", result.reason);
                log(prefix + " rejected " + result.reason);
                if (Set.of("coinbase", "bad-output", "bad-sig", "overspend").contains(result.reason))
                    penalize(peer, params.value("BAN", 2));
                return;
            }
            peer.txs++;
            log(prefix + " accepted fee " + result.fee + " size " + transaction.size());
            register(transaction, result, now);
        }
        void mine(Wallet wallet) {
            List<Transaction> transactions = new ArrayList<>();
            List<Integer> fees = new ArrayList<>();
            int size = 0, total = 0;
            for (Entry entry : ranked())
                if (size + entry.transaction.size() <= params.value("MAXBLOCK")) {
                    size += entry.transaction.size();
                    transactions.add(entry.transaction);
                    fees.add(entry.fee);
                    total += entry.fee;
                }
            transactions.addFirst(Transactions.coinbase(
                height(), List.of(new Payment(wallet.address(), reward(height()) + total))));
            Block block = Blocks.mine(height(), tip.block.hash, transactions,
                                      Math.max(now, Chain.median(tip) + 1), difficulty(tip));
            Map<Reference, Coin> utxo = new HashMap<>(tip.utxo);
            for (Transaction transaction : transactions)
                Transactions.apply(utxo, transaction, block.height);
            BlockRecord record = new BlockRecord(block, tip, utxo, fees, "local");
            records.put(block.hash, record);
            log("MINE " + wallet.name() + " " + block.height + " " + Hashing.shortId(block.hash) + " bits " +
                block.difficulty + " nonce " + block.nonce + " txs " + transactions.size() + " size " +
                block.size() + " fees " + total + " work " + record.work);
            switchTip(record);
        }
        void receiveBlock(Peer peer, Block block) {
            boolean orphaned = false;
            for (Orphan orphan : orphans)
                if (orphan.block.hash.equals(block.hash))
                    orphaned = true;
            if (records.containsKey(block.hash) || orphaned || rejected.contains(block.hash)) {
                peer.rejectedBlocks++;
                tally("block", "duplicate");
                log("BLOCK " + peer.name + " " + block.height + " " + Hashing.shortId(block.hash) +
                    " rejected duplicate");
                return;
            }
            String reason = Blocks.error(block, params.value("MAXBLOCK"));
            if (reason == null && rejected.contains(block.previous))
                reason = "bad-parent";
            if (reason != null) {
                rejectBlock("BLOCK", block, peer, reason);
                resolve(block.hash);
                return;
            }
            if (!records.containsKey(block.previous)) {
                orphans.add(new Orphan(block, peer));
                peer.orphans++;
                log("BLOCK " + peer.name + " " + block.height + " " + Hashing.shortId(block.hash) +
                    " orphan parent " + Hashing.shortId(block.previous));
                if (orphans.size() > params.value("ORPHANS"))
                    log("EVICT " + Hashing.shortId(orphans.removeFirst().block.hash) + " orphan-limit");
                return;
            }
            connect("BLOCK", block, peer);
            resolve(block.hash);
        }
        Validation validate(Block block, BlockRecord parent) {
            String reason = null;
            if (block.height != parent.block.height + 1)
                reason = "bad-height";
            else if (block.difficulty != difficulty(parent))
                reason = "bad-difficulty";
            else if (block.timestamp <= Chain.median(parent))
                reason = "time-too-old";
            else if (block.timestamp > now + params.value("DRIFT"))
                reason = "time-too-new";
            if (reason != null)
                return new Validation(reason, null, null);
            Map<Reference, Coin> utxo = new HashMap<>(parent.utxo);
            Set<Reference> spent = new HashSet<>();
            List<Integer> fees = new ArrayList<>();
            int total = 0;
            for (int i = 1; i < block.transactions.size(); i++) {
                Transaction transaction = block.transactions.get(i);
                Check check = Transactions.check(transaction, utxo, spent, block.height, owners,
                                                 params.value("MATURITY"));
                if (check.reason() != null)
                    return new Validation(check.reason() + " tx " + (i + 1), null, null);
                spent.addAll(transaction.inputs);
                Transactions.apply(utxo, transaction, block.height);
                fees.add(check.fee());
                total += check.fee();
            }
            Transaction coinbase = block.transactions.getFirst();
            for (Payment output : coinbase.outputs)
                if (!owners.containsKey(output.address()) || output.amount() == 0)
                    return new Validation("bad-output tx 1", null, null);
            if (coinbase.total() > reward(block.height) + total)
                return new Validation("bad-coinbase", null, null);
            Transactions.apply(utxo, coinbase, block.height);
            return new Validation(null, utxo, fees);
        }
        void connect(String kind, Block block, Peer peer) {
            BlockRecord parent = records.get(block.previous);
            Validation result = validate(block, parent);
            if (result.reason != null) {
                rejectBlock(kind, block, peer, result.reason);
                return;
            }
            BlockRecord record = new BlockRecord(block, parent, result.utxo, result.fees, peer.name);
            records.put(block.hash, record);
            peer.blocks++;
            log(kind + " " + peer.name + " " + block.height + " " + Hashing.shortId(block.hash) +
                " accepted work " + record.work);
            if (record.work > tip.work)
                switchTip(record);
        }
        void rejectBlock(String kind, Block block, Peer peer, String reason) {
            rejected.add(block.hash);
            peer.rejectedBlocks++;
            tally("block", reason.split(" ")[0]);
            log(kind + " " + peer.name + " " + block.height + " " + Hashing.shortId(block.hash) +
                " rejected " + reason);
            if (!reason.equals("time-too-new"))
                penalize(peer, params.value("BAN", 1));
        }
        void resolve(String start) {
            Deque<String> queue = new ArrayDeque<>();
            queue.add(start);
            while (!queue.isEmpty()) {
                String parent = queue.removeFirst();
                List<Orphan> children = new ArrayList<>();
                for (Orphan orphan : orphans)
                    if (orphan.block.previous.equals(parent))
                        children.add(orphan);
                for (Orphan orphan : children) {
                    orphans.remove(orphan);
                    if (rejected.contains(parent))
                        rejectBlock("UNORPHAN", orphan.block, orphan.peer, "bad-parent");
                    else
                        connect("UNORPHAN", orphan.block, orphan.peer);
                    queue.addLast(orphan.block.hash);
                }
            }
        }
        void status(String txid) {
            String prefix = "STATUS " + Hashing.shortId(txid);
            if (confirmed.containsKey(txid)) {
                int height = confirmed.get(txid);
                log(prefix + " confirmed " + height + " confirmations " + (height() - height));
                return;
            }
            List<Entry> entries = ranked();
            for (int i = 0; i < entries.size(); i++)
                if (entries.get(i).transaction.txid.equals(txid)) {
                    log(prefix + " mempool rank " + (i + 1) + " of " + entries.size());
                    return;
                }
            if (drops.containsKey(txid)) {
                log(prefix + " dropped " + drops.get(txid));
                return;
            }
            for (BlockRecord record : records.values())
                if (record.block.txids().contains(txid)) {
                    log(prefix + " stale");
                    return;
                }
            log(prefix + " unknown");
        }
        void printState() {
            List<Entry> entries = ranked();
            int size = 0;
            for (Entry entry : entries)
                size += entry.transaction.size();
            log("PRINT height " + tip.block.height + " tip " + Hashing.shortId(tip.block.hash) + " work " +
                tip.work + " bits " + difficulty(tip) + " reward " + reward(height()) + " mempool " +
                entries.size() + " size " + size + " orphans " + orphans.size());
            for (int i = 0; i < entries.size(); i++) {
                Entry entry = entries.get(i);
                log("MEMPOOL " + (i + 1) + " " + Hashing.shortId(entry.transaction.txid) + " fee " +
                    entry.fee + " size " + entry.transaction.size());
            }
            for (Wallet wallet : wallets)
                log("BALANCE " + wallet.name() + " " + balance(wallet.address()));
        }
        String miner(BlockRecord record) {
            return record.block.transactions.getFirst().outputs.getFirst().address();
        }
        List<String> chainLines() {
            List<String> lines = new ArrayList<>();
            lines.add("TIP " + tip.block.height + " " + tip.block.hash + " work " + tip.work + " stored " +
                      records.size() + " orphans " + orphans.size());
            Set<String> mainHashes = new HashSet<>();
            for (BlockRecord record : mainChain) {
                Block block = record.block;
                mainHashes.add(block.hash);
                String miner = block.height == 0 ? "-" : owners.get(miner(record)).name();
                lines.add("BLOCK " + block.height + " " + block.hash + " prev " +
                          Hashing.shortId(block.previous) + " time " + block.timestamp + " bits " +
                          block.difficulty + " nonce " + block.nonce + " txs " + block.transactions.size() +
                          " size " + block.size() + " fees " + record.fees + " miner " + miner +
                          " source " + record.source + " work " + record.work);
                for (int i = 0; i < block.transactions.size(); i++) {
                    Transaction transaction = block.transactions.get(i);
                    String prefix = "TX " + (i + 1) + " " + transaction.txid;
                    if (transaction.coinbase())
                        lines.add(prefix + " " + (block.height == 0 ? "genesis" : "coinbase") + " out " +
                                  transaction.outputs.size() + " amount " + transaction.total());
                    else
                        lines.add(prefix + " payment in " + transaction.inputs.size() + " out " +
                                  transaction.outputs.size() + " size " + transaction.size() + " fee " +
                                  record.transactionFees.get(i - 1));
                }
            }
            List<BlockRecord> stale = new ArrayList<>();
            for (BlockRecord record : records.values())
                if (!mainHashes.contains(record.block.hash))
                    stale.add(record);
            stale.sort(Comparator.<BlockRecord>comparingInt(record -> record.block.height)
                           .thenComparing(record -> record.block.hash));
            for (BlockRecord record : stale)
                lines.add("STALE " + record.block.height + " " + record.block.hash + " prev " +
                          Hashing.shortId(record.block.previous) + " source " + record.source + " work " +
                          record.work);
            for (Orphan orphan : orphans)
                lines.add("ORPHAN " + orphan.block.height + " " + orphan.block.hash + " prev " +
                          Hashing.shortId(orphan.block.previous) + " source " + orphan.peer.name);
            for (Reorganization entry : reorganizations)
                lines.add("REORG " + entry.time + " fork " + entry.fork + " disconnected " +
                          entry.disconnected + " connected " + entry.connected + " old " +
                          Hashing.shortId(entry.oldHash) + " new " + Hashing.shortId(entry.newHash));
            List<BlockRecord> mined = mainChain.subList(1, mainChain.size());
            int rewards = 0, fees = 0, minted = 0;
            for (BlockRecord record : mined) {
                rewards += reward(record.block.height);
                fees += record.fees;
                minted += record.block.transactions.getFirst().total();
            }
            for (Wallet wallet : wallets) {
                int count = 0, coinbase = 0, ownFees = 0;
                for (BlockRecord record : mined)
                    if (miner(record).equals(wallet.address())) {
                        count++;
                        coinbase += record.block.transactions.getFirst().total();
                        ownFees += record.fees;
                    }
                if (count > 0)
                    lines.add("MINER " + wallet.name() + " blocks " + count + " coinbase " + coinbase +
                              " fees " + ownFees);
            }
            int start = 0;
            while (start < mined.size()) {
                int end = start;
                while (end + 1 < mined.size() &&
                       mined.get(end + 1).block.difficulty == mined.get(start).block.difficulty)
                    end++;
                lines.add("BITS " + mined.get(start).block.difficulty + " heights " +
                          mined.get(start).block.height + "-" + mined.get(end).block.height + " blocks " +
                          (end - start + 1));
                start = end + 1;
            }
            for (Peer peer : peers.values())
                lines.add("PEER " + peer.name + " blocks " + peer.blocks + " rejected " +
                          peer.rejectedBlocks + " orphans " + peer.orphans + " txs " + peer.txs +
                          " rejected " + peer.rejectedTxs + " ignored " + peer.ignored + " score " +
                          peer.score + " " + (peer.score >= params.value("BAN") ? "banned" : "ok"));
            List<Entry> entries = ranked();
            for (int i = 0; i < entries.size(); i++) {
                Entry entry = entries.get(i);
                lines.add("MEMPOOL " + (i + 1) + " " + entry.transaction.txid + " fee " + entry.fee +
                          " size " + entry.transaction.size() + " time " + entry.arrival);
            }
            for (Map.Entry<String, Integer> pair : rejections.entrySet())
                lines.add("REJECT " + pair.getKey() + " " + pair.getValue());
            int total = 0;
            for (Coin coin : tip.utxo.values())
                total += coin.amount();
            lines.add("SUPPLY genesis " + mainChain.getFirst().block.transactions.getFirst().total() +
                      " rewards " + rewards + " fees " + fees + " burned " + (rewards + fees - minted) +
                      " utxo " + total);
            return lines;
        }
        List<String> balanceLines() {
            List<String> lines =
                new ArrayList<>(List.of("wallet,address,balance,immature,locked,incoming,utxos"));
            Set<Reference> locked = locked();
            for (Wallet wallet : wallets) {
                int total = 0, immature = 0, lockedAmount = 0, incoming = 0, count = 0;
                for (Map.Entry<Reference, Coin> pair : tip.utxo.entrySet())
                    if (pair.getValue().address().equals(wallet.address())) {
                        Coin coin = pair.getValue();
                        total += coin.amount();
                        count++;
                        if (!mature(coin))
                            immature += coin.amount();
                        if (locked.contains(pair.getKey()))
                            lockedAmount += coin.amount();
                    }
                for (Entry entry : mempool)
                    for (Payment output : entry.transaction.outputs)
                        if (output.address().equals(wallet.address()))
                            incoming += output.amount();
                lines.add(wallet.name() + "," + wallet.address() + "," + total + "," + immature + "," +
                          lockedAmount + "," + incoming + "," + count);
            }
            return lines;
        }
        List<String> utxoLines() {
            List<String> lines = new ArrayList<>();
            Set<Reference> locked = locked();
            List<Reference> references = new ArrayList<>(tip.utxo.keySet());
            Collections.sort(references);
            int total = 0;
            for (Reference reference : references) {
                Coin coin = tip.utxo.get(reference);
                total += coin.amount();
                String category = coin.height() == 0 ? "genesis"
                                  : coin.coinbase()  ? "coinbase"
                                                     : "payment",
                       state = !mature(coin)                ? "immature"
                               : locked.contains(reference) ? "locked"
                                                            : "free";
                lines.add(reference + " " + owners.get(coin.address()).name() + " " + coin.amount() +
                          " height " + coin.height() + " " + category + " " + state);
            }
            String root = Hashing.merkle(lines.stream().map(Hashing::digest).toList());
            lines.add("TOTAL " + references.size() + " " + total);
            lines.add("ROOT " + root);
            return lines;
        }
        List<String> historyLines() {
            List<String> lines = new ArrayList<>();
            Map<String, Transaction> transactions = new HashMap<>();
            for (BlockRecord record : mainChain)
                for (Transaction transaction : record.block.transactions)
                    transactions.put(transaction.txid, transaction);
            for (Wallet wallet : wallets) {
                lines.add("WALLET " + wallet.name() + " " + wallet.address());
                int count = 0, spentTotal = 0, receivedTotal = 0, balance = 0, pending = 0;
                for (BlockRecord record : mainChain)
                    for (Transaction transaction : record.block.transactions) {
                        int spent = 0, received = 0;
                        boolean involved = false;
                        for (Reference reference : transaction.inputs) {
                            Payment output =
                                transactions.get(reference.txid()).outputs.get(reference.index());
                            if (output.address().equals(wallet.address())) {
                                spent += output.amount();
                                involved = true;
                            }
                        }
                        for (Payment output : transaction.outputs)
                            if (output.address().equals(wallet.address())) {
                                received += output.amount();
                                involved = true;
                            }
                        if (!involved)
                            continue;
                        count++;
                        spentTotal += spent;
                        receivedTotal += received;
                        balance += received - spent;
                        String category = transaction.coinbase()
                                              ? (record.block.height == 0 ? "genesis" : "coinbase")
                                              : "payment";
                        lines.add(record.block.height + " " + Hashing.shortId(transaction.txid) + " " +
                                  category + " spent " + spent + " received " + received + " net " +
                                  signed(received - spent) + " balance " + balance);
                    }
                for (Entry entry : ranked()) {
                    Transaction transaction = entry.transaction;
                    int spent = 0, received = 0;
                    for (Reference reference : transaction.inputs) {
                        Coin coin = tip.utxo.get(reference);
                        if (coin.address().equals(wallet.address()))
                            spent += coin.amount();
                    }
                    for (Payment output : transaction.outputs)
                        if (output.address().equals(wallet.address()))
                            received += output.amount();
                    if (spent != 0 || received != 0) {
                        pending++;
                        lines.add("pending " + Hashing.shortId(transaction.txid) + " spent " + spent +
                                  " received " + received + " net " + signed(received - spent));
                    }
                }
                lines.add("END " + wallet.name() + " txs " + count + " spent " + spentTotal + " received " +
                          receivedTotal + " balance " + balance + " pending " + pending);
            }
            return lines;
        }
    }
    static String signed(int value) {
        return value >= 0 ? "+" + value : Integer.toString(value);
    }
    static void write(String name, List<String> lines) throws IOException {
        Files.writeString(Path.of("output", name), lines.isEmpty() ? "" : String.join("\n", lines) + "\n",
                          StandardCharsets.US_ASCII);
    }
    public static void main(String[] args) throws IOException {
        Node node = new Node(new Params(), Wallets.read());
        List<String> lines = Files.readAllLines(Path.of("input/events.txt"), StandardCharsets.US_ASCII);
        for (int position = 0; position < lines.size();) {
            String[] fields = lines.get(position).split(" ");
            int count = fields[1].equals("BLOCK") ? Integer.parseInt(fields[9]) : 0;
            node.process(fields, lines.subList(position + 1, position + 1 + count));
            position += count + 1;
        }
        Files.createDirectories(Path.of("output"));
        write("log.txt", node.logs);
        write("chain.txt", node.chainLines());
        write("balances.csv", node.balanceLines());
        write("utxo.txt", node.utxoLines());
        write("history.txt", node.historyLines());
    }
}
