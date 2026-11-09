#include "ledger.hpp"
struct Params {
    int initial_bits, retarget, halving, maturity, pool_limit, orphan_limit, max_reorg;
    Integer target, initial_reward, max_size, min_rate, drift, expiry, ban, block_penalty, tx_penalty;
    std::vector<std::pair<std::string, Integer>> genesis;
    Params() {
        std::ifstream input("input/params.txt");
        std::string key;
        input >> key >> initial_bits >> key >> retarget >> target >> key >> initial_reward >> halving;
        input >> key >> maturity >> key >> max_size >> key >> min_rate >> key >> pool_limit >> key >>
            orphan_limit;
        input >> key >> drift >> key >> expiry >> key >> max_reorg >> key >> ban >> block_penalty >>
            tx_penalty >> key;
        std::string name;
        Integer amount;
        while (input >> name >> amount)
            genesis.emplace_back(name, amount);
    }
};
struct Entry {
    Transaction tx;
    Integer fee, arrival;
};
struct Peer {
    Integer blocks = 0, rejected_blocks = 0, orphans = 0, txs = 0, rejected_txs = 0, ignored = 0, score = 0;
};
struct Orphan {
    Block block;
    std::string peer;
};
struct Reorganization {
    Integer time;
    int fork, disconnected, connected;
    std::string old_hash, new_hash;
};
struct Acceptance {
    std::string reason;
    Integer fee = 0;
    std::vector<std::string> conflicts;
};
static bool priority(const Entry &a, const Entry &b) {
    const Integer left = a.fee * b.tx.size(), right = b.fee * a.tx.size();
    return left != right ? left > right : a.tx.id < b.tx.id;
}
class Node {
    Params p;
    std::vector<Wallet> wallets;
    Owners owners;
    std::map<std::string, Wallet> named;
    std::map<std::string, std::unique_ptr<Record>> records;
    Record *tip;
    std::vector<Record *> main_chain;
    std::map<std::string, int> confirmed;
    std::vector<Entry> pool;
    std::vector<Orphan> orphans;
    std::set<std::string> rejected;
    std::map<std::string, std::string> drops;
    std::map<std::string, Peer> peers;
    std::map<std::pair<std::string, std::string>, Integer> rejections;
    std::vector<Reorganization> reorganizations;
    std::ofstream log_file;
    Integer now = 0;
    template <class... T> void log(const T &...parts) {
        log_file << now;
        ((log_file << ' ' << parts), ...);
        log_file << '\n';
    }
    static std::string signed_value(Integer value) {
        return (value >= 0 ? "+" : "") + std::to_string(value);
    }
    int next_height() const {
        return tip->block.height + 1;
    }
    Integer block_reward(int height) const {
        return reward(height, p.initial_reward, p.halving);
    }
    int next_bits(Record *parent) const {
        return required_difficulty(parent, p.initial_bits, p.retarget, p.target);
    }
    Record *store(Block block, Record *parent, Utxo utxo, std::vector<Integer> fees,
                  const std::string &source) {
        auto record =
            std::make_unique<Record>(std::move(block), parent, std::move(utxo), std::move(fees), source);
        Record *result = record.get();
        records[result->block.hash] = std::move(record);
        return result;
    }
    void refresh() {
        main_chain = chain_to(tip);
        confirmed.clear();
        for (Record *record : main_chain)
            for (const Transaction &tx : record->block.transactions)
                confirmed[tx.id] = record->block.height;
    }
    std::vector<Entry> ordered() const {
        std::vector<Entry> result = pool;
        std::sort(result.begin(), result.end(), priority);
        return result;
    }
    std::set<Reference> locked() const {
        std::set<Reference> result;
        for (const Entry &e : pool)
            result.insert(e.tx.inputs.begin(), e.tx.inputs.end());
        return result;
    }
    Integer balance(const std::string &address) const {
        Integer total = 0;
        for (const auto &item : tip->utxo)
            if (item.second.address == address)
                total += item.second.amount;
        return total;
    }
    const Entry *find_entry(const std::string &id) const {
        for (const Entry &e : pool)
            if (e.tx.id == id)
                return &e;
        return nullptr;
    }
    Acceptance acceptance(const Transaction &tx) const {
        if (tx.coinbase())
            return {"coinbase"};
        if (confirmed.count(tx.id) || find_entry(tx.id))
            return {"duplicate"};
        const auto check = check_transaction(tx, tip->utxo, {}, next_height(), owners, p.maturity);
        if (!check.first.empty())
            return {check.first};
        const Integer fee = check.second;
        if (fee * 1000 < p.min_rate * tx.size())
            return {"low-fee"};
        const std::set<Reference> inputs(tx.inputs.begin(), tx.inputs.end());
        Acceptance result{"", fee, {}};
        Integer conflict_fees = 0;
        bool higher = true;
        for (const Entry &e : pool) {
            bool conflict = false;
            for (const Reference &ref : e.tx.inputs)
                if (inputs.count(ref))
                    conflict = true;
            if (!conflict)
                continue;
            result.conflicts.push_back(e.tx.id);
            conflict_fees += e.fee;
            if (fee * e.tx.size() <= e.fee * tx.size())
                higher = false;
        }
        if (!result.conflicts.empty() && (fee <= conflict_fees || !higher))
            return {"conflict"};
        return result;
    }
    void drop(const std::string &id, const std::string &reason) {
        pool.erase(std::remove_if(pool.begin(), pool.end(), [&](const Entry &e) { return e.tx.id == id; }),
                   pool.end());
        drops[id] = reason;
        log("DROP", short_hash(id), reason);
    }
    void register_tx(const Transaction &tx, const Acceptance &accepted, Integer arrival) {
        for (const std::string &id : accepted.conflicts)
            drop(id, "replaced");
        pool.push_back({tx, accepted.fee, arrival});
        if (pool.size() > std::size_t(p.pool_limit)) {
            const std::string id = ordered().back().tx.id;
            drop(id, "mempool-full");
        }
    }
    void rebuild(const std::vector<Transaction> &returned) {
        const std::vector<Entry> old = pool;
        pool.clear();
        auto candidate = [&](const Transaction &tx, Integer arrival, bool returning) {
            if (confirmed.count(tx.id))
                return;
            const Acceptance result = acceptance(tx);
            if (!result.reason.empty()) {
                drop(tx.id, result.reason);
                return;
            }
            if (returning)
                log("RETURN", short_hash(tx.id));
            register_tx(tx, result, arrival);
        };
        for (const Transaction &tx : returned)
            candidate(tx, now, true);
        for (const Entry &e : old)
            candidate(e.tx, e.arrival, false);
    }
    void switch_tip(Record *target) {
        Record *old = tip;
        Record *fork = fork_point(old, target);
        const int depth = old->block.height - fork->block.height,
                  connected = target->block.height - fork->block.height;
        if (depth > p.max_reorg) {
            log("REFUSE", target->block.height, short_hash(target->block.hash), "work", target->work, "fork",
                fork->block.height, "depth", depth);
            return;
        }
        std::vector<Transaction> returned;
        for (Record *r : main_chain)
            if (r->block.height > fork->block.height)
                returned.insert(returned.end(), r->block.transactions.begin() + 1,
                                r->block.transactions.end());
        tip = target;
        refresh();
        if (!depth)
            log("TIP", target->block.height, short_hash(target->block.hash), "work", target->work);
        else {
            log("REORG", target->block.height, short_hash(target->block.hash), "work", target->work, "fork",
                fork->block.height, "disconnected", depth, "connected", connected);
            reorganizations.push_back(
                {now, fork->block.height, depth, connected, old->block.hash, target->block.hash});
        }
        rebuild(returned);
    }
    void penalize(const std::string &name, Integer amount) {
        Peer &peer = peers[name];
        const Integer before = peer.score;
        peer.score += amount;
        if (before < p.ban && peer.score >= p.ban)
            log("BAN", name, "score", peer.score);
    }
    void reject_block(const std::string &kind, const Block &block, const std::string &name,
                      const std::string &reason) {
        rejected.insert(block.hash);
        ++peers[name].rejected_blocks;
        ++rejections[{"block", split(reason, ' ')[0]}];
        log(kind, name, block.height, short_hash(block.hash), "rejected", reason);
        if (reason != "time-too-new")
            penalize(name, p.block_penalty);
    }
    void connect(const std::string &kind, const Block &block, const std::string &name) {
        Record *parent = records.at(block.previous).get();
        std::string error;
        if (block.height != parent->block.height + 1)
            error = "bad-height";
        else if (block.difficulty != next_bits(parent))
            error = "bad-difficulty";
        else if (block.time <= median_time(parent))
            error = "time-too-old";
        else if (block.time > now + p.drift)
            error = "time-too-new";
        Utxo coins = parent->utxo;
        std::set<Reference> spent;
        std::vector<Integer> fees;
        if (error.empty())
            for (std::size_t i = 1; i < block.transactions.size(); ++i) {
                const Transaction &tx = block.transactions[i];
                const auto result = check_transaction(tx, coins, spent, block.height, owners, p.maturity);
                if (!result.first.empty()) {
                    error = result.first + " tx " + std::to_string(i + 1);
                    break;
                }
                fees.push_back(result.second);
                spent.insert(tx.inputs.begin(), tx.inputs.end());
                apply(coins, tx, block.height);
            }
        const Transaction &cb = block.transactions[0];
        if (error.empty()) {
            for (const Output &out : cb.outputs)
                if (!owners.count(out.first) || out.second == 0) {
                    error = "bad-output tx 1";
                    break;
                }
            if (error.empty() && cb.total() > block_reward(block.height) +
                                                  std::accumulate(fees.begin(), fees.end(), Integer(0)))
                error = "bad-coinbase";
        }
        if (!error.empty()) {
            reject_block(kind, block, name, error);
            return;
        }
        apply(coins, cb, block.height);
        Record *record = store(block, parent, std::move(coins), std::move(fees), name);
        ++peers[name].blocks;
        log(kind, name, block.height, short_hash(block.hash), "accepted", "work", record->work);
        if (record->work > tip->work)
            switch_tip(record);
    }
    void resolve(const std::string &start) {
        std::deque<std::string> queue{start};
        while (!queue.empty()) {
            const std::string parent = queue.front();
            queue.pop_front();
            for (std::size_t i = 0; i < orphans.size();) {
                if (orphans[i].block.previous != parent) {
                    ++i;
                    continue;
                }
                const Orphan orphan = orphans[i];
                orphans.erase(orphans.begin() + i);
                if (rejected.count(parent))
                    reject_block("UNORPHAN", orphan.block, orphan.peer, "bad-parent");
                else
                    connect("UNORPHAN", orphan.block, orphan.peer);
                queue.push_back(orphan.block.hash);
            }
        }
    }
    void receive_block(const Block &block, const std::string &name) {
        bool duplicate = records.count(block.hash) || rejected.count(block.hash);
        for (const Orphan &orphan : orphans)
            if (orphan.block.hash == block.hash)
                duplicate = true;
        if (duplicate) {
            ++peers[name].rejected_blocks;
            ++rejections[{"block", "duplicate"}];
            log("BLOCK", name, block.height, short_hash(block.hash), "rejected", "duplicate");
            return;
        }
        std::string error = context_error(block, p.max_size);
        if (error.empty() && rejected.count(block.previous))
            error = "bad-parent";
        if (!error.empty()) {
            reject_block("BLOCK", block, name, error);
            resolve(block.hash);
            return;
        }
        if (!records.count(block.previous)) {
            orphans.push_back({block, name});
            ++peers[name].orphans;
            log("BLOCK", name, block.height, short_hash(block.hash), "orphan", "parent",
                short_hash(block.previous));
            if (orphans.size() > std::size_t(p.orphan_limit)) {
                log("EVICT", short_hash(orphans.front().block.hash), "orphan-limit");
                orphans.erase(orphans.begin());
            }
            return;
        }
        connect("BLOCK", block, name);
        resolve(block.hash);
    }
    void pay(const std::vector<std::string> &fields) {
        const Wallet &wallet = named.at(fields[2]);
        const Integer fee = std::stoll(fields[3]);
        std::vector<Output> outputs;
        Integer total = 0;
        for (std::size_t i = 4; i < fields.size(); i += 2) {
            const Integer amount = std::stoll(fields[i + 1]);
            outputs.emplace_back(named.at(fields[i]).address, amount);
            total += amount;
        }
        const std::string prefix =
            "PAY " + wallet.name + " fee " + std::to_string(fee) + " total " + std::to_string(total);
        const std::set<Reference> locks = locked();
        std::vector<std::pair<Reference, Coin>> coins;
        for (const auto &item : tip->utxo)
            if (item.second.address == wallet.address && !locks.count(item.first) &&
                item.second.mature(next_height(), p.maturity))
                coins.push_back(item);
        std::sort(coins.begin(), coins.end(), [](const auto &a, const auto &b) {
            return a.second.amount != b.second.amount ? a.second.amount > b.second.amount : a.first < b.first;
        });
        Integer amount = 0;
        std::vector<Reference> inputs;
        for (const auto &item : coins) {
            if (amount >= total + fee)
                break;
            inputs.push_back(item.first);
            amount += item.second.amount;
        }
        if (amount < total + fee) {
            log(prefix, "rejected", "insufficient-funds");
            ++rejections[{"pay", "insufficient-funds"}];
            return;
        }
        if (amount > total + fee)
            outputs.emplace_back(wallet.address, amount - total - fee);
        const Transaction tx = payment(inputs, outputs, wallet.secret);
        const Acceptance result = acceptance(tx);
        if (!result.reason.empty()) {
            log(prefix, "tx", short_hash(tx.id), "rejected", result.reason);
            ++rejections[{"pay", result.reason}];
            return;
        }
        log(prefix, "tx", short_hash(tx.id), "accepted", "inputs", tx.inputs.size(), "outputs",
            tx.outputs.size(), "size", tx.size());
        register_tx(tx, result, now);
    }
    void bump(const std::string &id, Integer fee) {
        const std::string prefix = "BUMP " + short_hash(id) + " fee " + std::to_string(fee);
        const Entry *entry = find_entry(id);
        if (!entry) {
            log(prefix, "rejected", "unknown");
            ++rejections[{"bump", "unknown"}];
            return;
        }
        std::vector<Output> outputs = entry->tx.outputs;
        Output &last = outputs.back();
        std::set<std::string> addresses;
        for (const Reference &ref : entry->tx.inputs)
            addresses.insert(tip->utxo.at(ref).address);
        last.second -= fee - entry->fee;
        if (addresses != std::set<std::string>{last.first} || last.second < 1) {
            log(prefix, "rejected", "no-change");
            ++rejections[{"bump", "no-change"}];
            return;
        }
        const Transaction tx = payment(entry->tx.inputs, outputs, owners.at(last.first).secret);
        const Acceptance result = acceptance(tx);
        if (!result.reason.empty()) {
            log(prefix, "tx", short_hash(tx.id), "rejected", result.reason);
            ++rejections[{"bump", result.reason}];
            return;
        }
        log(prefix, "tx", short_hash(tx.id), "accepted", "size", tx.size());
        register_tx(tx, result, now);
    }
    void receive_transaction(const std::string &name, const Transaction &tx) {
        const Acceptance result = acceptance(tx);
        if (!result.reason.empty()) {
            ++peers[name].rejected_txs;
            ++rejections[{"tx", result.reason}];
            log("TX", name, short_hash(tx.id), "rejected", result.reason);
            if (result.reason == "coinbase" || result.reason == "bad-output" || result.reason == "bad-sig" ||
                result.reason == "overspend")
                penalize(name, p.tx_penalty);
            return;
        }
        ++peers[name].txs;
        log("TX", name, short_hash(tx.id), "accepted", "fee", result.fee, "size", tx.size());
        register_tx(tx, result, now);
    }
    void mine(const Wallet &wallet) {
        const int height = next_height();
        Integer size = 0, fees = 0;
        std::vector<Transaction> txs;
        for (const Entry &e : ordered())
            if (size + e.tx.size() <= p.max_size) {
                txs.push_back(e.tx);
                size += e.tx.size();
                fees += e.fee;
            }
        txs.insert(txs.begin(), coinbase(height, {{wallet.address, block_reward(height) + fees}}));
        Block block =
            mine_block(height, tip->block.hash, txs, std::max(now, median_time(tip) + 1), next_bits(tip));
        Utxo coins = tip->utxo;
        for (const Transaction &tx : txs)
            apply(coins, tx, height);
        std::vector<Integer> amounts;
        for (std::size_t i = 1; i < txs.size(); ++i)
            amounts.push_back(find_entry(txs[i].id)->fee);
        Record *record = store(block, tip, std::move(coins), std::move(amounts), "local");
        log("MINE", wallet.name, height, short_hash(block.hash), "bits", block.difficulty, "nonce",
            block.nonce, "txs", txs.size(), "size", size, "fees", fees, "work", record->work);
        switch_tip(record);
    }
    void status(const std::string &id) {
        const std::string prefix = "STATUS " + short_hash(id);
        if (confirmed.count(id)) {
            log(prefix, "confirmed", confirmed.at(id), "confirmations", next_height() - confirmed.at(id));
            return;
        }
        const std::vector<Entry> order = ordered();
        for (std::size_t i = 0; i < order.size(); ++i)
            if (order[i].tx.id == id) {
                log(prefix, "mempool", "rank", i + 1, "of", order.size());
                return;
            }
        if (drops.count(id)) {
            log(prefix, "dropped", drops.at(id));
            return;
        }
        for (const auto &item : records)
            for (const Transaction &tx : item.second->block.transactions)
                if (tx.id == id) {
                    log(prefix, "stale");
                    return;
                }
        log(prefix, "unknown");
    }
    void print() {
        Integer size = 0;
        for (const Entry &e : pool)
            size += e.tx.size();
        log("PRINT", "height", tip->block.height, "tip", short_hash(tip->block.hash), "work", tip->work,
            "bits", next_bits(tip), "reward", block_reward(next_height()), "mempool", pool.size(), "size",
            size, "orphans", orphans.size());
        const std::vector<Entry> order = ordered();
        for (std::size_t i = 0; i < order.size(); ++i)
            log("MEMPOOL", i + 1, short_hash(order[i].tx.id), "fee", order[i].fee, "size",
                order[i].tx.size());
        for (const Wallet &wallet : wallets)
            log("BALANCE", wallet.name, balance(wallet.address));
    }
    std::string miner(Record *r) const {
        return r->block.height == 0 ? "-" : owners.at(r->block.transactions[0].outputs[0].first).name;
    }
    void write_chain() {
        std::ofstream out("output/chain.txt");
        out << "TIP " << tip->block.height << ' ' << tip->block.hash << " work " << tip->work << " stored "
            << records.size() << " orphans " << orphans.size() << '\n';
        std::set<std::string> main_hashes;
        Integer rewards = 0, fees = 0, coinbases = 0;
        for (Record *r : main_chain) {
            const Block &b = r->block;
            main_hashes.insert(b.hash);
            out << "BLOCK " << b.height << ' ' << b.hash << " prev " << short_hash(b.previous) << " time "
                << b.time << " bits " << b.difficulty << " nonce " << b.nonce << " txs "
                << b.transactions.size() << " size " << b.size() << " fees " << r->fees << " miner "
                << miner(r) << " source " << r->source << " work " << r->work << '\n';
            for (std::size_t i = 0; i < b.transactions.size(); ++i) {
                const Transaction &tx = b.transactions[i];
                out << "TX " << i + 1 << ' ' << tx.id << ' ';
                if (tx.coinbase())
                    out << (b.height == 0 ? "genesis" : "coinbase") << " out " << tx.outputs.size()
                        << " amount " << tx.total();
                else
                    out << "payment in " << tx.inputs.size() << " out " << tx.outputs.size() << " size "
                        << tx.size() << " fee " << r->transaction_fees[i - 1];
                out << '\n';
            }
            if (b.height) {
                rewards += block_reward(b.height);
                fees += r->fees;
                coinbases += b.transactions[0].total();
            }
        }
        std::vector<Record *> stale;
        for (const auto &item : records)
            if (!main_hashes.count(item.first))
                stale.push_back(item.second.get());
        std::sort(stale.begin(), stale.end(), [](Record *a, Record *b) {
            return std::tie(a->block.height, a->block.hash) < std::tie(b->block.height, b->block.hash);
        });
        for (Record *r : stale)
            out << "STALE " << r->block.height << ' ' << r->block.hash << " prev "
                << short_hash(r->block.previous) << " source " << r->source << " work " << r->work << '\n';
        for (const Orphan &o : orphans)
            out << "ORPHAN " << o.block.height << ' ' << o.block.hash << " prev "
                << short_hash(o.block.previous) << " source " << o.peer << '\n';
        for (const Reorganization &r : reorganizations)
            out << "REORG " << r.time << " fork " << r.fork << " disconnected " << r.disconnected
                << " connected " << r.connected << " old " << short_hash(r.old_hash) << " new "
                << short_hash(r.new_hash) << '\n';
        for (const Wallet &w : wallets) {
            int count = 0;
            Integer amount = 0, total_fees = 0;
            for (Record *r : main_chain)
                if (miner(r) == w.name) {
                    ++count;
                    amount += r->block.transactions[0].total();
                    total_fees += r->fees;
                }
            if (count)
                out << "MINER " << w.name << " blocks " << count << " coinbase " << amount << " fees "
                    << total_fees << '\n';
        }
        for (std::size_t first = 1; first < main_chain.size();) {
            std::size_t last = first;
            const int bits = main_chain[first]->block.difficulty;
            while (last + 1 < main_chain.size() && main_chain[last + 1]->block.difficulty == bits)
                ++last;
            out << "BITS " << bits << " heights " << first << '-' << last << " blocks " << last - first + 1
                << '\n';
            first = last + 1;
        }
        for (const auto &item : peers) {
            const Peer &q = item.second;
            out << "PEER " << item.first << " blocks " << q.blocks << " rejected " << q.rejected_blocks
                << " orphans " << q.orphans << " txs " << q.txs << " rejected " << q.rejected_txs
                << " ignored " << q.ignored << " score " << q.score << ' '
                << (q.score >= p.ban ? "banned" : "ok") << '\n';
        }
        const std::vector<Entry> order = ordered();
        for (std::size_t i = 0; i < order.size(); ++i)
            out << "MEMPOOL " << i + 1 << ' ' << order[i].tx.id << " fee " << order[i].fee << " size "
                << order[i].tx.size() << " time " << order[i].arrival << '\n';
        for (const auto &item : rejections)
            out << "REJECT " << item.first.first << ' ' << item.first.second << ' ' << item.second << '\n';
        Integer total = 0;
        for (const auto &item : tip->utxo)
            total += item.second.amount;
        out << "SUPPLY genesis " << main_chain[0]->block.transactions[0].total() << " rewards " << rewards
            << " fees " << fees << " burned " << rewards + fees - coinbases << " utxo " << total << '\n';
    }
    void write_balances_utxo() {
        const std::set<Reference> locks = locked();
        std::ofstream out("output/balances.csv");
        out << "wallet,address,balance,immature,locked,incoming,utxos\n";
        for (const Wallet &w : wallets) {
            Integer amount = 0, immature = 0, locked_amount = 0, incoming = 0, count = 0;
            for (const auto &item : tip->utxo)
                if (item.second.address == w.address) {
                    const Coin &c = item.second;
                    amount += c.amount;
                    ++count;
                    if (!c.mature(next_height(), p.maturity))
                        immature += c.amount;
                    if (locks.count(item.first))
                        locked_amount += c.amount;
                }
            for (const Entry &e : pool)
                for (const Output &o : e.tx.outputs)
                    if (o.first == w.address)
                        incoming += o.second;
            out << w.name << ',' << w.address << ',' << amount << ',' << immature << ',' << locked_amount
                << ',' << incoming << ',' << count << '\n';
        }
        std::ofstream utxo("output/utxo.txt");
        std::vector<std::string> hashes;
        Integer total = 0;
        for (const auto &item : tip->utxo) {
            const Coin &c = item.second;
            std::ostringstream line;
            line << item.first.first << ':' << item.first.second << ' ' << owners.at(c.address).name << ' '
                 << c.amount << " height " << c.height << ' '
                 << (c.height == 0 ? "genesis"
                     : c.coinbase  ? "coinbase"
                                   : "payment")
                 << ' '
                 << (!c.mature(next_height(), p.maturity) ? "immature"
                     : locks.count(item.first)            ? "locked"
                                                          : "free");
            utxo << line.str() << '\n';
            hashes.push_back(digest(line.str()));
            total += c.amount;
        }
        utxo << "TOTAL " << tip->utxo.size() << ' ' << total << "\nROOT " << merkle(hashes) << '\n';
    }
    void write_history() {
        std::ofstream out("output/history.txt");
        std::map<Reference, Output> all_outputs;
        for (Record *r : main_chain)
            for (const Transaction &tx : r->block.transactions)
                for (std::size_t i = 0; i < tx.outputs.size(); ++i)
                    all_outputs[{tx.id, int(i)}] = tx.outputs[i];
        for (const Wallet &w : wallets) {
            out << "WALLET " << w.name << ' ' << w.address << '\n';
            Integer count = 0, spent_total = 0, received_total = 0, balance_value = 0, pending = 0;
            for (Record *r : main_chain)
                for (const Transaction &tx : r->block.transactions) {
                    Integer spent = 0, received = 0;
                    for (const Reference &ref : tx.inputs) {
                        const Output &o = all_outputs.at(ref);
                        if (o.first == w.address)
                            spent += o.second;
                    }
                    for (const Output &o : tx.outputs)
                        if (o.first == w.address)
                            received += o.second;
                    if (!spent && !received)
                        continue;
                    ++count;
                    spent_total += spent;
                    received_total += received;
                    balance_value += received - spent;
                    out << r->block.height << ' ' << short_hash(tx.id) << ' '
                        << (r->block.height == 0 ? "genesis"
                            : tx.coinbase()      ? "coinbase"
                                                 : "payment")
                        << " spent " << spent << " received " << received << " net "
                        << signed_value(received - spent) << " balance " << balance_value << '\n';
                }
            for (const Entry &e : ordered()) {
                Integer spent = 0, received = 0;
                for (const Reference &ref : e.tx.inputs) {
                    const Coin &c = tip->utxo.at(ref);
                    if (c.address == w.address)
                        spent += c.amount;
                }
                for (const Output &o : e.tx.outputs)
                    if (o.first == w.address)
                        received += o.second;
                if (!spent && !received)
                    continue;
                ++pending;
                out << "pending " << short_hash(e.tx.id) << " spent " << spent << " received " << received
                    << " net " << signed_value(received - spent) << '\n';
            }
            out << "END " << w.name << " txs " << count << " spent " << spent_total << " received "
                << received_total << " balance " << balance_value << " pending " << pending << '\n';
        }
    }

  public:
    Node() : wallets(read_wallets()) {
        std::filesystem::create_directories("output");
        log_file.open("output/log.txt");
        for (const Wallet &w : wallets) {
            owners[w.address] = w;
            named[w.name] = w;
        }
        std::vector<Output> outputs;
        for (const auto &pair : p.genesis)
            outputs.emplace_back(named.at(pair.first).address, pair.second);
        const Transaction tx = coinbase(0, outputs);
        Block genesis;
        genesis.previous = std::string(32, '0');
        genesis.root = tx.id;
        genesis.transactions = {tx};
        genesis.hash_header();
        Utxo coins;
        apply(coins, tx, 0);
        tip = store(genesis, nullptr, std::move(coins), {}, "genesis");
        refresh();
    }
    void run() {
        std::ifstream events("input/events.txt");
        std::string line;
        while (std::getline(events, line)) {
            const std::vector<std::string> fields = split(line, ' ');
            std::vector<std::string> texts;
            if (fields[1] == "BLOCK")
                for (int i = 0; i < std::stoi(fields[9]); ++i) {
                    std::getline(events, line);
                    texts.push_back(line);
                }
            now = std::stoll(fields[0]);
            const std::vector<Entry> before = pool;
            for (const Entry &e : before)
                if (now - e.arrival >= p.expiry)
                    drop(e.tx.id, "expired");
            const std::string &kind = fields[1];
            if (kind == "PAY")
                pay(fields);
            else if (kind == "BUMP")
                bump(fields[2], std::stoll(fields[3]));
            else if (kind == "MINE")
                mine(named.at(fields[2]));
            else if (kind == "STATUS")
                status(fields[2]);
            else if (kind == "PRINT")
                print();
            else {
                const std::string &name = fields[2];
                Peer &q = peers[name];
                if (q.score >= p.ban) {
                    ++q.ignored;
                    log("IGNORE", name, kind);
                } else if (kind == "TX")
                    receive_transaction(name, parse_transaction(fields[3]));
                else
                    receive_block(parse_block(fields, texts), name);
            }
        }
        write_chain();
        write_balances_utxo();
        write_history();
    }
};
int main() {
    Node node;
    node.run();
}
