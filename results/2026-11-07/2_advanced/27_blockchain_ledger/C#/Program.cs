using System;
using System.Collections.Generic;
using System.Globalization;
using System.IO;
using System.Linq;
using System.Text;

static class Program {
    static int CompareInt(int first, int second) => first.CompareTo(second);
    static T RemoveFirst<T>(List<T> values) {
        T value = values[0];
        values.RemoveAt(0);
        return value;
    }
    sealed record Entry(Transaction transaction, int fee, int arrival);
    sealed record Orphan(Block block, Peer peer);
    sealed record Reorganization(int time, int fork, int disconnected, int connected, string oldHash,
                                 string newHash);
    sealed record Acceptance(string reason, int fee, List<Entry> conflicts);
    sealed record Validation(string reason, Dictionary<Reference, Coin> utxo, List<int> fees);
    sealed class Peer {
        public readonly string name;
        public int blocks, rejectedBlocks, orphans, txs, rejectedTxs, ignored, score;
        public Peer(string name) {
            this.name = name;
        }
    }
    sealed class Params {
        public readonly Dictionary<string, string[]> values = new();
        public Params() {
            foreach (string line in File.ReadAllLines(Path.Combine("input/params.txt"), Encoding.ASCII)) {
                string[] fields = line.Split(" ");
                values[fields[0]] = fields[1..fields.Length];
            }
        }
        public int Value(string name, int index) {
            return int.Parse(values[name][index]);
        }
        public int Value(string name) {
            return Value(name, 0);
        }
    }
    sealed class Node {
        Peer GetPeer(string name) {
            if (!peers.TryGetValue(name, out Peer peer)) {
                peer = new Peer(name);
                peers[name] = peer;
            }
            return peer;
        }
        public readonly Params settings;
        public readonly List<Wallet> wallets;
        public readonly Dictionary<string, Wallet> owners = new(), named = new();
        public readonly Dictionary<string, BlockRecord> records = new();
        public readonly List<Entry> mempool = new();
        public readonly List<Orphan> orphans = new();
        public readonly HashSet<string> rejected = new();
        public readonly Dictionary<string, string> drops = new();
        public readonly SortedDictionary<string, Peer> peers = new(StringComparer.Ordinal);
        public readonly SortedDictionary<string, int> rejections = new(StringComparer.Ordinal);
        public readonly List<Reorganization> reorganizations = new();
        public readonly List<string> logs = new();
        public readonly Dictionary<string, int> confirmed = new();
        public List<BlockRecord> mainChain;
        public BlockRecord tip;
        public int now;
        public Node(Params settings, List<Wallet> wallets) {
            this.settings = settings;
            this.wallets = wallets;
            foreach (Wallet wallet in wallets) {
                owners[wallet.address] = wallet;
                named[wallet.name] = wallet;
            }
            List<Payment> outputs = new();
            string[] genesis = settings.values["GENESIS"];
            for (int i = 0; i < genesis.Length; i += 2)
                outputs.Add(new Payment(named[genesis[i]].address, int.Parse(genesis[i + 1])));
            Transaction coinbase = Transactions.Coinbase(0, outputs);
            Block block = new Block(0, new string('0', 32), coinbase.txid, 0, 0, 0, [coinbase]);
            Dictionary<Reference, Coin> utxo = new();
            Transactions.Apply(utxo, coinbase, 0);
            tip = new BlockRecord(block, null, utxo, [], "genesis");
            records[block.hash] = tip;
            Refresh();
        }
        public void Refresh() {
            mainChain = Chain.Sequence(tip);
            confirmed.Clear();
            foreach (BlockRecord record in mainChain)
                foreach (Transaction transaction in record.block.transactions)
                    confirmed[transaction.txid] = record.block.height;
        }
        public void Log(string line) {
            logs.Add(now + " " + line);
        }
        public void Tally(string category, string reason) {
            string key = category + " " + reason;
            rejections[key] = rejections.GetValueOrDefault(key) + 1;
        }
        public int Height() {
            return tip.block.height + 1;
        }
        public int Reward(int height) {
            return Chain.Reward(height, settings.Value("REWARD"), settings.Value("REWARD", 1));
        }
        public int Difficulty(BlockRecord parent) {
            return Chain.Difficulty(parent, settings.Value("DIFFICULTY"), settings.Value("RETARGET"),
                                    settings.Value("RETARGET", 1));
        }
        public bool Mature(Coin coin) {
            return coin.Mature(Height(), settings.Value("MATURITY"));
        }
        public int Balance(string address) {
            int total = 0;
            foreach (Coin coin in tip.utxo.Values)
                if (coin.address.Equals(address))
                    total += coin.amount;
            return total;
        }
        public HashSet<Reference> Locked() {
            HashSet<Reference> references = new();
            foreach (Entry entry in mempool)
                references.UnionWith(entry.transaction.inputs);
            return references;
        }
        public List<Entry> Ranked() {
            List<Entry> entries = mempool.ToList();
            entries.Sort((first, second) => {
                int rate =
                    CompareInt(second.fee * first.transaction.Size(), first.fee * second.transaction.Size());
                return rate != 0 ? rate
                                 : string.CompareOrdinal(first.transaction.txid, second.transaction.txid);
            });
            return entries;
        }
        public Entry Find(string txid) {
            foreach (Entry entry in mempool)
                if (entry.transaction.txid.Equals(txid))
                    return entry;
            return null;
        }
        public Acceptance Acceptance(Transaction transaction) {
            if (transaction.Coinbase())
                return new Acceptance("coinbase", 0, []);
            if (confirmed.ContainsKey(transaction.txid) || Find(transaction.txid) != null)
                return new Acceptance("duplicate", 0, []);
            Check check = Transactions.Check(transaction, tip.utxo, new HashSet<Reference>(), Height(),
                                             owners, settings.Value("MATURITY"));
            if (check.reason != null)
                return new Acceptance(check.reason, 0, []);
            int fee = check.fee, size = transaction.Size();
            if (fee * 1000 < settings.Value("MINFEERATE") * size)
                return new Acceptance("low-fee", 0, []);
            HashSet<Reference> inputs = transaction.inputs.ToHashSet();
            List<Entry> conflicts = new();
            int fees = 0;
            bool higher = true;
            foreach (Entry entry in mempool) {
                if (!inputs.Overlaps(entry.transaction.inputs))
                    continue;
                conflicts.Add(entry);
                fees += entry.fee;
                if (fee * entry.transaction.Size() <= entry.fee * size)
                    higher = false;
            }
            if (conflicts.Count != 0 && (fee <= fees || !higher))
                return new Acceptance("conflict", 0, []);
            return new Acceptance(null, fee, conflicts);
        }
        public void RecordDrop(string txid, string reason) {
            drops[txid] = reason;
            Log("DROP " + Hashing.ShortId(txid) + " " + reason);
        }
        public void Drop(Entry entry, string reason) {
            mempool.Remove(entry);
            RecordDrop(entry.transaction.txid, reason);
        }
        public void Register(Transaction transaction, Acceptance result, int arrival) {
            foreach (Entry entry in result.conflicts)
                Drop(entry, "replaced");
            mempool.Add(new Entry(transaction, result.fee, arrival));
            if (mempool.Count > settings.Value("MEMPOOL"))
                Drop(Ranked()[^1], "mempool-full");
        }
        public void Rebuild(List<Transaction> returned) {
            List<Entry> previous = mempool.ToList();
            mempool.Clear();
            foreach (Transaction transaction in returned)
                RebuildEntry(transaction, now, true);
            foreach (Entry entry in previous)
                RebuildEntry(entry.transaction, entry.arrival, false);
        }
        public void RebuildEntry(Transaction transaction, int arrival, bool returned) {
            if (confirmed.ContainsKey(transaction.txid))
                return;
            Acceptance result = Acceptance(transaction);
            if (result.reason != null) {
                RecordDrop(transaction.txid, result.reason);
                return;
            }
            if (returned)
                Log("RETURN " + Hashing.ShortId(transaction.txid));
            Register(transaction, result, arrival);
        }
        public void SwitchTip(BlockRecord target) {
            BlockRecord old = tip, fork = Chain.Fork(old, target);
            int disconnected = old.block.height - fork.block.height,
                connected = target.block.height - fork.block.height;
            string targetText =
                target.block.height + " " + Hashing.ShortId(target.block.hash) + " work " + target.work;
            if (disconnected > settings.Value("MAXREORG")) {
                Log("REFUSE " + targetText + " fork " + fork.block.height + " depth " + disconnected);
                return;
            }
            List<Transaction> returned = new();
            foreach (BlockRecord record in mainChain.GetRange(fork.block.height + 1,
                                                              mainChain.Count - (fork.block.height + 1)))
                returned.AddRange(
                    record.block.transactions.GetRange(1, record.block.transactions.Count - (1)));
            tip = target;
            Refresh();
            if (disconnected == 0)
                Log("TIP " + targetText);
            else {
                Log("REORG " + targetText + " fork " + fork.block.height + " disconnected " + disconnected +
                    " connected " + connected);
                reorganizations.Add(new Reorganization(now, fork.block.height, disconnected, connected,
                                                       old.block.hash, target.block.hash));
            }
            Rebuild(returned);
        }
        public void Penalize(Peer peer, int points) {
            int before = peer.score;
            peer.score += points;
            if (before < settings.Value("BAN") && peer.score >= settings.Value("BAN"))
                Log("BAN " + peer.name + " score " + peer.score);
        }
        public void Process(string[] fields, List<string> texts) {
            now = int.Parse(fields[0]);
            foreach (Entry entry in mempool.ToList())
                if (now - entry.arrival >= settings.Value("EXPIRY"))
                    Drop(entry, "expired");
            switch (fields[1]) {
            case "PAY":
                Pay(fields);
                break;
            case "BUMP":
                Bump(fields[2], int.Parse(fields[3]));
                break;
            case "MINE":
                Mine(named[fields[2]]);
                break;
            case "STATUS":
                Status(fields[2]);
                break;
            case "PRINT":
                PrintState();
                break;
            default: {
                Peer peer = GetPeer(fields[2]);
                if (peer.score >= settings.Value("BAN")) {
                    peer.ignored++;
                    Log("IGNORE " + peer.name + " " + fields[1]);
                } else if (fields[1].Equals("TX"))
                    ReceiveTransaction(peer, Transactions.Parse(fields[3]));
                else
                    ReceiveBlock(peer, Blocks.Parse(fields, texts));
                break;
            }
            }
        }
        public void Pay(string[] fields) {
            Wallet sender = named[fields[2]];
            int fee = int.Parse(fields[3]), total = 0;
            List<Payment> outputs = new();
            for (int i = 4; i < fields.Length; i += 2) {
                int amount = int.Parse(fields[i + 1]);
                outputs.Add(new Payment(named[fields[i]].address, amount));
                total += amount;
            }
            string prefix = "PAY " + sender.name + " fee " + fee + " total " + total;
            HashSet<Reference> locked = Locked();
            List<Reference> candidates = new();
            foreach (KeyValuePair<Reference, Coin> pair in tip.utxo)
                if (pair.Value.address.Equals(sender.address) && !locked.Contains(pair.Key) &&
                    Mature(pair.Value))
                    candidates.Add(pair.Key);
            candidates.Sort((first, second) => {
                int amount = CompareInt(tip.utxo[second].amount, tip.utxo[first].amount);
                return amount != 0 ? amount : first.CompareTo(second);
            });
            List<Reference> inputs = new();
            int gathered = 0;
            foreach (Reference reference in candidates) {
                if (gathered >= total + fee)
                    break;
                inputs.Add(reference);
                gathered += tip.utxo[reference].amount;
            }
            if (gathered < total + fee) {
                Log(prefix + " rejected insufficient-funds");
                Tally("pay", "insufficient-funds");
                return;
            }
            if (gathered > total + fee)
                outputs.Add(new Payment(sender.address, gathered - total - fee));
            Transaction transaction = Transactions.Create(inputs, outputs, sender.secret);
            Acceptance result = Acceptance(transaction);
            prefix += " tx " + Hashing.ShortId(transaction.txid);
            if (result.reason != null) {
                Log(prefix + " rejected " + result.reason);
                Tally("pay", result.reason);
                return;
            }
            Log(prefix + " accepted inputs " + inputs.Count + " outputs " + outputs.Count + " size " +
                transaction.Size());
            Register(transaction, result, now);
        }
        public void Bump(string txid, int fee) {
            string prefix = "BUMP " + Hashing.ShortId(txid) + " fee " + fee;
            Entry entry = Find(txid);
            if (entry == null) {
                Log(prefix + " rejected unknown");
                Tally("bump", "unknown");
                return;
            }
            Transaction original = entry.transaction;
            HashSet<string> addresses = new();
            foreach (Reference reference in original.inputs)
                addresses.Add(tip.utxo[reference].address);
            Payment last = original.outputs[^1];
            int change = last.amount - (fee - entry.fee);
            if (addresses.Count != 1 || !addresses.Contains(last.address) || change < 1) {
                Log(prefix + " rejected no-change");
                Tally("bump", "no-change");
                return;
            }
            List<Payment> outputs = original.outputs.ToList();
            outputs[outputs.Count - 1] = new Payment(last.address, change);
            Transaction transaction =
                Transactions.Create(original.inputs, outputs, owners[last.address].secret);
            Acceptance result = Acceptance(transaction);
            prefix += " tx " + Hashing.ShortId(transaction.txid);
            if (result.reason != null) {
                Log(prefix + " rejected " + result.reason);
                Tally("bump", result.reason);
                return;
            }
            Log(prefix + " accepted size " + transaction.Size());
            Register(transaction, result, now);
        }
        public void ReceiveTransaction(Peer peer, Transaction transaction) {
            Acceptance result = Acceptance(transaction);
            string prefix = "TX " + peer.name + " " + Hashing.ShortId(transaction.txid);
            if (result.reason != null) {
                peer.rejectedTxs++;
                Tally("tx", result.reason);
                Log(prefix + " rejected " + result.reason);
                if (new HashSet<string> { "coinbase", "bad-output", "bad-sig", "overspend" }.Contains(
                        result.reason))
                    Penalize(peer, settings.Value("BAN", 2));
                return;
            }
            peer.txs++;
            Log(prefix + " accepted fee " + result.fee + " size " + transaction.Size());
            Register(transaction, result, now);
        }
        public void Mine(Wallet wallet) {
            List<Transaction> transactions = new();
            List<int> fees = new();
            int size = 0, total = 0;
            foreach (Entry entry in Ranked())
                if (size + entry.transaction.Size() <= settings.Value("MAXBLOCK")) {
                    size += entry.transaction.Size();
                    transactions.Add(entry.transaction);
                    fees.Add(entry.fee);
                    total += entry.fee;
                }
            transactions.Insert(
                0, Transactions.Coinbase(Height(), [new Payment(wallet.address, Reward(Height()) + total)]));
            Block block = Blocks.Mine(Height(), tip.block.hash, transactions,
                                      Math.Max(now, Chain.Median(tip) + 1), Difficulty(tip));
            Dictionary<Reference, Coin> utxo = new Dictionary<Reference, Coin>(tip.utxo);
            foreach (Transaction transaction in transactions)
                Transactions.Apply(utxo, transaction, block.height);
            BlockRecord record = new BlockRecord(block, tip, utxo, fees, "local");
            records[block.hash] = record;
            Log("MINE " + wallet.name + " " + block.height + " " + Hashing.ShortId(block.hash) + " bits " +
                block.difficulty + " nonce " + block.nonce + " txs " + transactions.Count + " size " +
                block.Size() + " fees " + total + " work " + record.work);
            SwitchTip(record);
        }
        public void ReceiveBlock(Peer peer, Block block) {
            bool orphaned = false;
            foreach (Orphan orphan in orphans)
                if (orphan.block.hash.Equals(block.hash))
                    orphaned = true;
            if (records.ContainsKey(block.hash) || orphaned || rejected.Contains(block.hash)) {
                peer.rejectedBlocks++;
                Tally("block", "duplicate");
                Log("BLOCK " + peer.name + " " + block.height + " " + Hashing.ShortId(block.hash) +
                    " rejected duplicate");
                return;
            }
            string reason = Blocks.Error(block, settings.Value("MAXBLOCK"));
            if (reason == null && rejected.Contains(block.previous))
                reason = "bad-parent";
            if (reason != null) {
                RejectBlock("BLOCK", block, peer, reason);
                Resolve(block.hash);
                return;
            }
            if (!records.ContainsKey(block.previous)) {
                orphans.Add(new Orphan(block, peer));
                peer.orphans++;
                Log("BLOCK " + peer.name + " " + block.height + " " + Hashing.ShortId(block.hash) +
                    " orphan parent " + Hashing.ShortId(block.previous));
                if (orphans.Count > settings.Value("ORPHANS"))
                    Log("EVICT " + Hashing.ShortId(RemoveFirst(orphans).block.hash) + " orphan-limit");
                return;
            }
            Connect("BLOCK", block, peer);
            Resolve(block.hash);
        }
        public Validation Validate(Block block, BlockRecord parent) {
            string reason = null;
            if (block.height != parent.block.height + 1)
                reason = "bad-height";
            else if (block.difficulty != Difficulty(parent))
                reason = "bad-difficulty";
            else if (block.timestamp <= Chain.Median(parent))
                reason = "time-too-old";
            else if (block.timestamp > now + settings.Value("DRIFT"))
                reason = "time-too-new";
            if (reason != null)
                return new Validation(reason, null, null);
            Dictionary<Reference, Coin> utxo = new Dictionary<Reference, Coin>(parent.utxo);
            HashSet<Reference> spent = new();
            List<int> fees = new();
            int total = 0;
            for (int i = 1; i < block.transactions.Count; i++) {
                Transaction transaction = block.transactions[i];
                Check check = Transactions.Check(transaction, utxo, spent, block.height, owners,
                                                 settings.Value("MATURITY"));
                if (check.reason != null)
                    return new Validation(check.reason + " tx " + (i + 1), null, null);
                spent.UnionWith(transaction.inputs);
                Transactions.Apply(utxo, transaction, block.height);
                fees.Add(check.fee);
                total += check.fee;
            }
            Transaction coinbase = block.transactions[0];
            foreach (Payment output in coinbase.outputs)
                if (!owners.ContainsKey(output.address) || output.amount == 0)
                    return new Validation("bad-output tx 1", null, null);
            if (coinbase.Total() > Reward(block.height) + total)
                return new Validation("bad-coinbase", null, null);
            Transactions.Apply(utxo, coinbase, block.height);
            return new Validation(null, utxo, fees);
        }
        public void Connect(string kind, Block block, Peer peer) {
            BlockRecord parent = records[block.previous];
            Validation result = Validate(block, parent);
            if (result.reason != null) {
                RejectBlock(kind, block, peer, result.reason);
                return;
            }
            BlockRecord record = new BlockRecord(block, parent, result.utxo, result.fees, peer.name);
            records[block.hash] = record;
            peer.blocks++;
            Log(kind + " " + peer.name + " " + block.height + " " + Hashing.ShortId(block.hash) +
                " accepted work " + record.work);
            if (record.work > tip.work)
                SwitchTip(record);
        }
        public void RejectBlock(string kind, Block block, Peer peer, string reason) {
            rejected.Add(block.hash);
            peer.rejectedBlocks++;
            Tally("block", reason.Split(" ")[0]);
            Log(kind + " " + peer.name + " " + block.height + " " + Hashing.ShortId(block.hash) +
                " rejected " + reason);
            if (!reason.Equals("time-too-new"))
                Penalize(peer, settings.Value("BAN", 1));
        }
        public void Resolve(string start) {
            Queue<string> queue = new();
            queue.Enqueue(start);
            while (queue.Count != 0) {
                string parent = queue.Dequeue();
                List<Orphan> children = new();
                foreach (Orphan orphan in orphans)
                    if (orphan.block.previous.Equals(parent))
                        children.Add(orphan);
                foreach (Orphan orphan in children) {
                    orphans.Remove(orphan);
                    if (rejected.Contains(parent))
                        RejectBlock("UNORPHAN", orphan.block, orphan.peer, "bad-parent");
                    else
                        Connect("UNORPHAN", orphan.block, orphan.peer);
                    queue.Enqueue(orphan.block.hash);
                }
            }
        }
        public void Status(string txid) {
            string prefix = "STATUS " + Hashing.ShortId(txid);
            if (confirmed.ContainsKey(txid)) {
                int height = confirmed[txid];
                Log(prefix + " confirmed " + height + " confirmations " + (Height() - height));
                return;
            }
            List<Entry> entries = Ranked();
            for (int i = 0; i < entries.Count; i++)
                if (entries[i].transaction.txid.Equals(txid)) {
                    Log(prefix + " mempool rank " + (i + 1) + " of " + entries.Count);
                    return;
                }
            if (drops.ContainsKey(txid)) {
                Log(prefix + " dropped " + drops[txid]);
                return;
            }
            foreach (BlockRecord record in records.Values)
                if (record.block.Txids().Contains(txid)) {
                    Log(prefix + " stale");
                    return;
                }
            Log(prefix + " unknown");
        }
        public void PrintState() {
            List<Entry> entries = Ranked();
            int size = 0;
            foreach (Entry entry in entries)
                size += entry.transaction.Size();
            Log("PRINT height " + tip.block.height + " tip " + Hashing.ShortId(tip.block.hash) + " work " +
                tip.work + " bits " + Difficulty(tip) + " reward " + Reward(Height()) + " mempool " +
                entries.Count + " size " + size + " orphans " + orphans.Count);
            for (int i = 0; i < entries.Count; i++) {
                Entry entry = entries[i];
                Log("MEMPOOL " + (i + 1) + " " + Hashing.ShortId(entry.transaction.txid) + " fee " +
                    entry.fee + " size " + entry.transaction.Size());
            }
            foreach (Wallet wallet in wallets)
                Log("BALANCE " + wallet.name + " " + Balance(wallet.address));
        }
        public string Miner(BlockRecord record) {
            return record.block.transactions[0].outputs[0].address;
        }
        public List<string> ChainLines() {
            List<string> lines = new();
            lines.Add("TIP " + tip.block.height + " " + tip.block.hash + " work " + tip.work + " stored " +
                      records.Count + " orphans " + orphans.Count);
            HashSet<string> mainHashes = new();
            foreach (BlockRecord record in mainChain) {
                Block block = record.block;
                mainHashes.Add(block.hash);
                string miner = block.height == 0 ? "-" : owners[Miner(record)].name;
                lines.Add("BLOCK " + block.height + " " + block.hash + " prev " +
                          Hashing.ShortId(block.previous) + " time " + block.timestamp + " bits " +
                          block.difficulty + " nonce " + block.nonce + " txs " + block.transactions.Count +
                          " size " + block.Size() + " fees " + record.fees + " miner " + miner + " source " +
                          record.source + " work " + record.work);
                for (int i = 0; i < block.transactions.Count; i++) {
                    Transaction transaction = block.transactions[i];
                    string prefix = "TX " + (i + 1) + " " + transaction.txid;
                    if (transaction.Coinbase())
                        lines.Add(prefix + " " + (block.height == 0 ? "genesis" : "coinbase") + " out " +
                                  transaction.outputs.Count + " amount " + transaction.Total());
                    else
                        lines.Add(prefix + " payment in " + transaction.inputs.Count + " out " +
                                  transaction.outputs.Count + " size " + transaction.Size() + " fee " +
                                  record.transactionFees[i - 1]);
                }
            }
            List<BlockRecord> stale = new();
            foreach (BlockRecord record in records.Values)
                if (!mainHashes.Contains(record.block.hash))
                    stale.Add(record);
            stale.Sort(Comparer<BlockRecord>.Create(
                (first, second) => first.block.height != second.block.height
                                       ? first.block.height.CompareTo(second.block.height)
                                       : string.CompareOrdinal(first.block.hash, second.block.hash)));
            foreach (BlockRecord record in stale)
                lines.Add("STALE " + record.block.height + " " + record.block.hash + " prev " +
                          Hashing.ShortId(record.block.previous) + " source " + record.source + " work " +
                          record.work);
            foreach (Orphan orphan in orphans)
                lines.Add("ORPHAN " + orphan.block.height + " " + orphan.block.hash + " prev " +
                          Hashing.ShortId(orphan.block.previous) + " source " + orphan.peer.name);
            foreach (Reorganization entry in reorganizations)
                lines.Add("REORG " + entry.time + " fork " + entry.fork + " disconnected " +
                          entry.disconnected + " connected " + entry.connected + " old " +
                          Hashing.ShortId(entry.oldHash) + " new " + Hashing.ShortId(entry.newHash));
            List<BlockRecord> mined = mainChain.GetRange(1, mainChain.Count - (1));
            int rewards = 0, fees = 0, minted = 0;
            foreach (BlockRecord record in mined) {
                rewards += Reward(record.block.height);
                fees += record.fees;
                minted += record.block.transactions[0].Total();
            }
            foreach (Wallet wallet in wallets) {
                int count = 0, coinbase = 0, ownFees = 0;
                foreach (BlockRecord record in mined)
                    if (Miner(record).Equals(wallet.address)) {
                        count++;
                        coinbase += record.block.transactions[0].Total();
                        ownFees += record.fees;
                    }
                if (count > 0)
                    lines.Add("MINER " + wallet.name + " blocks " + count + " coinbase " + coinbase +
                              " fees " + ownFees);
            }
            int start = 0;
            while (start < mined.Count) {
                int end = start;
                while (end + 1 < mined.Count &&
                       mined[end + 1].block.difficulty == mined[start].block.difficulty)
                    end++;
                lines.Add("BITS " + mined[start].block.difficulty + " heights " + mined[start].block.height +
                          "-" + mined[end].block.height + " blocks " + (end - start + 1));
                start = end + 1;
            }
            foreach (Peer peer in peers.Values)
                lines.Add("PEER " + peer.name + " blocks " + peer.blocks + " rejected " +
                          peer.rejectedBlocks + " orphans " + peer.orphans + " txs " + peer.txs +
                          " rejected " + peer.rejectedTxs + " ignored " + peer.ignored + " score " +
                          peer.score + " " + (peer.score >= settings.Value("BAN") ? "banned" : "ok"));
            List<Entry> entries = Ranked();
            for (int i = 0; i < entries.Count; i++) {
                Entry entry = entries[i];
                lines.Add("MEMPOOL " + (i + 1) + " " + entry.transaction.txid + " fee " + entry.fee +
                          " size " + entry.transaction.Size() + " time " + entry.arrival);
            }
            foreach (KeyValuePair<string, int> pair in rejections)
                lines.Add("REJECT " + pair.Key + " " + pair.Value);
            int total = 0;
            foreach (Coin coin in tip.utxo.Values)
                total += coin.amount;
            lines.Add("SUPPLY genesis " + mainChain[0].block.transactions[0].Total() + " rewards " + rewards +
                      " fees " + fees + " burned " + (rewards + fees - minted) + " utxo " + total);
            return lines;
        }
        public List<string> BalanceLines() {
            List<string> lines = new(["wallet,address,balance,immature,locked,incoming,utxos"]);
            HashSet<Reference> locked = Locked();
            foreach (Wallet wallet in wallets) {
                int total = 0, immature = 0, lockedAmount = 0, incoming = 0, count = 0;
                foreach (KeyValuePair<Reference, Coin> pair in tip.utxo)
                    if (pair.Value.address.Equals(wallet.address)) {
                        Coin coin = pair.Value;
                        total += coin.amount;
                        count++;
                        if (!Mature(coin))
                            immature += coin.amount;
                        if (locked.Contains(pair.Key))
                            lockedAmount += coin.amount;
                    }
                foreach (Entry entry in mempool)
                    foreach (Payment output in entry.transaction.outputs)
                        if (output.address.Equals(wallet.address))
                            incoming += output.amount;
                lines.Add(wallet.name + "," + wallet.address + "," + total + "," + immature + "," +
                          lockedAmount + "," + incoming + "," + count);
            }
            return lines;
        }
        public List<string> UtxoLines() {
            List<string> lines = new();
            HashSet<Reference> locked = Locked();
            List<Reference> references = tip.utxo.Keys.ToList();
            references.Sort();
            int total = 0;
            foreach (Reference reference in references) {
                Coin coin = tip.utxo[reference];
                total += coin.amount;
                string category = coin.height == 0 ? "genesis"
                                  : coin.coinbase  ? "coinbase"
                                                   : "payment",
                       state = !Mature(coin)                ? "immature"
                               : locked.Contains(reference) ? "locked"
                                                            : "free";
                lines.Add(reference + " " + owners[coin.address].name + " " + coin.amount + " height " +
                          coin.height + " " + category + " " + state);
            }
            string root = Hashing.Merkle(lines.Select(Hashing.Digest).ToList());
            lines.Add("TOTAL " + references.Count + " " + total);
            lines.Add("ROOT " + root);
            return lines;
        }
        public List<string> HistoryLines() {
            List<string> lines = new();
            Dictionary<string, Transaction> transactions = new();
            foreach (BlockRecord record in mainChain)
                foreach (Transaction transaction in record.block.transactions)
                    transactions[transaction.txid] = transaction;
            foreach (Wallet wallet in wallets) {
                lines.Add("WALLET " + wallet.name + " " + wallet.address);
                int count = 0, spentTotal = 0, receivedTotal = 0, balance = 0, pending = 0;
                foreach (BlockRecord record in mainChain)
                    foreach (Transaction transaction in record.block.transactions) {
                        int spent = 0, received = 0;
                        bool involved = false;
                        foreach (Reference reference in transaction.inputs) {
                            Payment output = transactions[reference.txid].outputs[reference.index];
                            if (output.address.Equals(wallet.address)) {
                                spent += output.amount;
                                involved = true;
                            }
                        }
                        foreach (Payment output in transaction.outputs)
                            if (output.address.Equals(wallet.address)) {
                                received += output.amount;
                                involved = true;
                            }
                        if (!involved)
                            continue;
                        count++;
                        spentTotal += spent;
                        receivedTotal += received;
                        balance += received - spent;
                        string category = transaction.Coinbase()
                                              ? (record.block.height == 0 ? "genesis" : "coinbase")
                                              : "payment";
                        lines.Add(record.block.height + " " + Hashing.ShortId(transaction.txid) + " " +
                                  category + " spent " + spent + " received " + received + " net " +
                                  Signed(received - spent) + " balance " + balance);
                    }
                foreach (Entry entry in Ranked()) {
                    Transaction transaction = entry.transaction;
                    int spent = 0, received = 0;
                    foreach (Reference reference in transaction.inputs) {
                        Coin coin = tip.utxo[reference];
                        if (coin.address.Equals(wallet.address))
                            spent += coin.amount;
                    }
                    foreach (Payment output in transaction.outputs)
                        if (output.address.Equals(wallet.address))
                            received += output.amount;
                    if (spent != 0 || received != 0) {
                        pending++;
                        lines.Add("pending " + Hashing.ShortId(transaction.txid) + " spent " + spent +
                                  " received " + received + " net " + Signed(received - spent));
                    }
                }
                lines.Add("END " + wallet.name + " txs " + count + " spent " + spentTotal + " received " +
                          receivedTotal + " balance " + balance + " pending " + pending);
            }
            return lines;
        }
    }
    public static string Signed(int value) {
        return value >= 0 ? "+" + value : Convert.ToString(value);
    }
    public static void Write(string name, List<string> lines) {
        File.WriteAllText(Path.Combine("output", name),
                          lines.Count == 0 ? "" : string.Join("\n", lines) + "\n", Encoding.ASCII);
    }
    public static void Main(string[] args) {
        CultureInfo.CurrentCulture = CultureInfo.InvariantCulture;
        Node node = new Node(new Params(), Wallets.Read());
        List<string> lines = File.ReadAllLines(Path.Combine("input/events.txt"), Encoding.ASCII).ToList();
        for (int position = 0; position < lines.Count;) {
            string[] fields = lines[position].Split(" ");
            int count = fields[1].Equals("BLOCK") ? int.Parse(fields[9]) : 0;
            node.Process(fields, lines.GetRange(position + 1, position + 1 + count - (position + 1)));
            position += count + 1;
        }
        Directory.CreateDirectory(Path.Combine("output"));
        Write("log.txt", node.logs);
        Write("chain.txt", node.ChainLines());
        Write("balances.csv", node.BalanceLines());
        Write("utxo.txt", node.UtxoLines());
        Write("history.txt", node.HistoryLines());
    }
}
