#include "ledger.h"
typedef struct {
    int initial_bits, retarget, halving, maturity, pool_limit, orphan_limit, max_reorg;
    Integer target, initial_reward, max_size, min_rate, drift, expiry, ban, block_penalty, tx_penalty;
    Output *genesis;
    int genesis_count;
} Params;
typedef struct {
    Transaction *tx;
    Integer fee, arrival;
} Entry;
typedef struct {
    char *name;
    Integer blocks, rejected_blocks, orphans, txs, rejected_txs, ignored, score;
} Peer;
typedef struct {
    Block *block;
    Peer *peer;
} Orphan;
typedef struct {
    char *id;
    const char *reason;
} Drop;
typedef struct {
    char *category, *reason;
    Integer count;
} Rejection;
typedef struct {
    Integer time;
    int fork, disconnected, connected;
    char *old_hash, *new_hash;
} Reorganization;
typedef struct {
    const char *reason;
    Integer fee;
    char *conflicts[101];
    int count;
} Acceptance;
static Params p;
static Wallets wallets;
static Record *records[61], *tip, **main_chain;
static int record_count, chain_count;
static Entry pool[101];
static int pool_count;
static Orphan orphans[11];
static int orphan_count;
static Peer peers[2000];
static int peer_count;
static char *rejected[2000];
static int rejected_count;
static Drop drops[4000];
static int drop_count;
static Rejection rejections[2000];
static int rejection_count;
static Reorganization reorganizations[2000];
static int reorganization_count;
static Integer now;
static FILE *log_file;
static void log_event(const char *pattern, ...) {
    fprintf(log_file, "%" PRId64 " ", now);
    va_list args;
    va_start(args, pattern);
    vfprintf(log_file, pattern, args);
    va_end(args);
    fputc('\n', log_file);
}
static void tally(const char *category, const char *reason) {
    for (int i = 0; i < rejection_count; ++i)
        if (!strcmp(rejections[i].category, category) && !strcmp(rejections[i].reason, reason)) {
            ++rejections[i].count;
            return;
        }
    rejections[rejection_count++] = (Rejection){copy_text(category), copy_text(reason), 1};
}
static Peer *peer_record(const char *name) {
    for (int i = 0; i < peer_count; ++i)
        if (!strcmp(peers[i].name, name))
            return peers + i;
    peers[peer_count].name = copy_text(name);
    return peers + peer_count++;
}
static Record *find_record(const char *hash) {
    for (int i = 0; i < record_count; ++i)
        if (!strcmp(records[i]->block->hash, hash))
            return records[i];
    return NULL;
}
static bool is_rejected(const char *hash) {
    for (int i = 0; i < rejected_count; ++i)
        if (!strcmp(rejected[i], hash))
            return true;
    return false;
}
static int confirmed(const char *id) {
    for (int i = 0; i < chain_count; ++i)
        for (int j = 0; j < main_chain[i]->block->count; ++j)
            if (!strcmp(main_chain[i]->block->transactions[j]->id, id))
                return main_chain[i]->block->height;
    return -1;
}
static int next_height(void) {
    return tip->block->height + 1;
}
static Integer block_reward(int height) {
    return reward(height, p.initial_reward, p.halving);
}
static int next_bits(Record *parent) {
    return required_difficulty(parent, p.initial_bits, p.retarget, p.target);
}
static void refresh(void) {
    free(main_chain);
    main_chain = chain_to(tip, &chain_count);
}
static int entry_index(const char *id) {
    for (int i = 0; i < pool_count; ++i)
        if (!strcmp(pool[i].tx->id, id))
            return i;
    return -1;
}
static int priority_compare(const void *first, const void *second) {
    const Entry *a = first, *b = second;
    Integer left = a->fee * (Integer)strlen(b->tx->text), right = b->fee * (Integer)strlen(a->tx->text);
    if (left != right)
        return left > right ? -1 : 1;
    return strcmp(a->tx->id, b->tx->id);
}
static Entry *ordered(void) {
    Entry *result = malloc((size_t)pool_count * sizeof *result);
    memcpy(result, pool, (size_t)pool_count * sizeof *result);
    qsort(result, (size_t)pool_count, sizeof *result, priority_compare);
    return result;
}
static bool locked(Reference ref) {
    for (int i = 0; i < pool_count; ++i)
        for (int j = 0; j < pool[i].tx->input_count; ++j)
            if (same_reference(ref, pool[i].tx->inputs[j]))
                return true;
    return false;
}
static Integer balance(const char *address) {
    Integer total = 0;
    for (int i = 0; i < tip->utxo.count; ++i)
        if (!strcmp(tip->utxo.items[i].address, address))
            total += tip->utxo.items[i].amount;
    return total;
}
static Acceptance acceptance(Transaction *tx) {
    Acceptance result = {0};
    if (tx->coinbase_height >= 0) {
        result.reason = "coinbase";
        return result;
    }
    if (confirmed(tx->id) >= 0 || entry_index(tx->id) >= 0) {
        result.reason = "duplicate";
        return result;
    }
    result.reason =
        check_transaction(tx, &tip->utxo, NULL, 0, next_height(), wallets, p.maturity, &result.fee);
    if (result.reason)
        return result;
    if (result.fee * 1000 < p.min_rate * (Integer)strlen(tx->text)) {
        result.reason = "low-fee";
        return result;
    }
    Integer conflict_fees = 0;
    bool higher = true;
    for (int i = 0; i < pool_count; ++i) {
        bool conflict = false;
        Transaction *other = pool[i].tx;
        for (int a = 0; a < tx->input_count; ++a)
            for (int b = 0; b < other->input_count; ++b)
                if (same_reference(tx->inputs[a], other->inputs[b]))
                    conflict = true;
        if (!conflict)
            continue;
        result.conflicts[result.count++] = other->id;
        conflict_fees += pool[i].fee;
        if (result.fee * (Integer)strlen(other->text) <= pool[i].fee * (Integer)strlen(tx->text))
            higher = false;
    }
    if (result.count && (result.fee <= conflict_fees || !higher))
        result.reason = "conflict";
    return result;
}
static void drop_transaction(const char *id, const char *reason) {
    int index = entry_index(id);
    if (index >= 0) {
        memmove(pool + index, pool + index + 1, (size_t)(pool_count - index - 1) * sizeof *pool);
        --pool_count;
    }
    int at = 0;
    while (at < drop_count && strcmp(drops[at].id, id))
        ++at;
    if (at == drop_count) {
        drops[at].id = copy_text(id);
        ++drop_count;
    }
    drops[at].reason = copy_text(reason);
    log_event("DROP %s %s", short_hash(id), reason);
}
static void register_transaction(Transaction *tx, Acceptance result, Integer arrival) {
    for (int i = 0; i < result.count; ++i)
        drop_transaction(result.conflicts[i], "replaced");
    pool[pool_count++] = (Entry){tx, result.fee, arrival};
    if (pool_count > p.pool_limit) {
        Entry *order = ordered();
        char *id = order[pool_count - 1].tx->id;
        free(order);
        drop_transaction(id, "mempool-full");
    }
}
static void rebuild_candidate(Transaction *tx, Integer arrival, bool returning) {
    if (confirmed(tx->id) >= 0)
        return;
    Acceptance result = acceptance(tx);
    if (result.reason) {
        drop_transaction(tx->id, result.reason);
        return;
    }
    if (returning)
        log_event("RETURN %s", short_hash(tx->id));
    register_transaction(tx, result, arrival);
}
static void switch_tip(Record *target) {
    Record *old = tip, *fork = fork_point(old, target);
    int depth = old->block->height - fork->block->height,
        connected = target->block->height - fork->block->height;
    if (depth > p.max_reorg) {
        log_event("REFUSE %d %s work %" PRId64 " fork %d depth %d", target->block->height,
                  short_hash(target->block->hash), target->work, fork->block->height, depth);
        return;
    }
    Transaction **returned = NULL;
    int count = 0;
    for (int i = fork->block->height + 1; i < chain_count; ++i) {
        Block *block = main_chain[i]->block;
        returned = realloc(returned, (size_t)(count + block->count - 1) * sizeof *returned);
        for (int j = 1; j < block->count; ++j)
            returned[count++] = block->transactions[j];
    }
    tip = target;
    refresh();
    if (!depth)
        log_event("TIP %d %s work %" PRId64, target->block->height, short_hash(target->block->hash),
                  target->work);
    else {
        log_event("REORG %d %s work %" PRId64 " fork %d disconnected %d connected %d", target->block->height,
                  short_hash(target->block->hash), target->work, fork->block->height, depth, connected);
        reorganizations[reorganization_count++] = (Reorganization){
            now, fork->block->height, depth, connected, old->block->hash, target->block->hash};
    }
    Entry previous[101];
    int previous_count = pool_count;
    memcpy(previous, pool, (size_t)pool_count * sizeof *pool);
    pool_count = 0;
    for (int i = 0; i < count; ++i)
        rebuild_candidate(returned[i], now, true);
    for (int i = 0; i < previous_count; ++i)
        rebuild_candidate(previous[i].tx, previous[i].arrival, false);
    free(returned);
}
static void penalize(Peer *peer, Integer amount) {
    Integer before = peer->score;
    peer->score += amount;
    if (before < p.ban && peer->score >= p.ban)
        log_event("BAN %s score %" PRId64, peer->name, peer->score);
}
static void reject_block(const char *kind, Block *block, Peer *peer, const char *reason) {
    if (!is_rejected(block->hash))
        rejected[rejected_count++] = block->hash;
    ++peer->rejected_blocks;
    int n;
    char **words = split(copy_text(reason), ' ', &n);
    tally("block", words[0]);
    free(words);
    log_event("%s %s %d %s rejected %s", kind, peer->name, block->height, short_hash(block->hash), reason);
    if (strcmp(reason, "time-too-new"))
        penalize(peer, p.block_penalty);
}
static void connect_block(const char *kind, Block *block, Peer *peer) {
    Record *parent = find_record(block->previous);
    const char *error = NULL;
    if (block->height != parent->block->height + 1)
        error = "bad-height";
    else if (block->difficulty != next_bits(parent))
        error = "bad-difficulty";
    else if (block->time <= median_time(parent))
        error = "time-too-old";
    else if (block->time > now + p.drift)
        error = "time-too-new";
    Utxo utxo = copy_utxo(parent->utxo);
    Reference *spent = NULL;
    int spent_count = 0;
    Integer *fees = calloc((size_t)block->count, sizeof *fees), total = 0;
    for (int i = 1; !error && i < block->count; ++i) {
        Transaction *tx = block->transactions[i];
        const char *result = check_transaction(tx, &utxo, spent, spent_count, block->height, wallets,
                                               p.maturity, fees + i - 1);
        if (result) {
            error = format("%s tx %d", result, i + 1);
            break;
        }
        spent = realloc(spent, (size_t)(spent_count + tx->input_count) * sizeof *spent);
        memcpy(spent + spent_count, tx->inputs, (size_t)tx->input_count * sizeof *spent);
        spent_count += tx->input_count;
        apply_transaction(&utxo, tx, block->height);
        total += fees[i - 1];
    }
    Transaction *cb = block->transactions[0];
    if (!error)
        for (int i = 0; i < cb->output_count; ++i)
            if (!owner(wallets, cb->outputs[i].address) || cb->outputs[i].amount == 0) {
                error = "bad-output tx 1";
                break;
            }
    if (!error && output_total(cb) > block_reward(block->height) + total)
        error = "bad-coinbase";
    free(spent);
    if (error) {
        reject_block(kind, block, peer, error);
        free(utxo.items);
        free(fees);
        return;
    }
    apply_transaction(&utxo, cb, block->height);
    Record *record = make_record(block, parent, utxo, fees, peer->name);
    records[record_count++] = record;
    ++peer->blocks;
    log_event("%s %s %d %s accepted work %" PRId64, kind, peer->name, block->height, short_hash(block->hash),
              record->work);
    if (record->work > tip->work)
        switch_tip(record);
}
static void resolve_orphans(const char *start) {
    const char *queue[2001];
    int front = 0, end = 1;
    queue[0] = start;
    while (front < end) {
        const char *parent = queue[front++];
        for (int i = 0; i < orphan_count;) {
            if (strcmp(orphans[i].block->previous, parent)) {
                ++i;
                continue;
            }
            Orphan orphan = orphans[i];
            memmove(orphans + i, orphans + i + 1, (size_t)(orphan_count - i - 1) * sizeof *orphans);
            --orphan_count;
            if (is_rejected(parent))
                reject_block("UNORPHAN", orphan.block, orphan.peer, "bad-parent");
            else
                connect_block("UNORPHAN", orphan.block, orphan.peer);
            queue[end++] = orphan.block->hash;
        }
    }
}
static void receive_block(Block *block, Peer *peer) {
    bool duplicate = find_record(block->hash) || is_rejected(block->hash);
    for (int i = 0; i < orphan_count; ++i)
        if (!strcmp(orphans[i].block->hash, block->hash))
            duplicate = true;
    if (duplicate) {
        ++peer->rejected_blocks;
        tally("block", "duplicate");
        log_event("BLOCK %s %d %s rejected duplicate", peer->name, block->height, short_hash(block->hash));
        return;
    }
    const char *error = context_error(block, p.max_size);
    if (!error && is_rejected(block->previous))
        error = "bad-parent";
    if (error) {
        reject_block("BLOCK", block, peer, error);
        resolve_orphans(block->hash);
        return;
    }
    if (!find_record(block->previous)) {
        orphans[orphan_count++] = (Orphan){block, peer};
        ++peer->orphans;
        log_event("BLOCK %s %d %s orphan parent %s", peer->name, block->height, short_hash(block->hash),
                  short_hash(block->previous));
        if (orphan_count > p.orphan_limit) {
            log_event("EVICT %s orphan-limit", short_hash(orphans[0].block->hash));
            memmove(orphans, orphans + 1, (size_t)(--orphan_count) * sizeof *orphans);
        }
        return;
    }
    connect_block("BLOCK", block, peer);
    resolve_orphans(block->hash);
}
static int coin_compare(const void *first, const void *second) {
    const Coin *a = first, *b = second;
    int order = strcmp(a->reference.id, b->reference.id);
    return order ? order
                 : (a->reference.index > b->reference.index) - (a->reference.index < b->reference.index);
}
static int selection_compare(const void *first, const void *second) {
    const Coin *a = first, *b = second;
    if (a->amount != b->amount)
        return a->amount > b->amount ? -1 : 1;
    return coin_compare(a, b);
}
static void pay(char **fields, int count) {
    Wallet *wallet = named_wallet(wallets, fields[2]);
    Integer fee = strtoll(fields[3], NULL, 10), total = 0;
    Output *outputs = malloc((size_t)(count / 2 + 1) * sizeof *outputs);
    int output_count = 0;
    for (int i = 4; i < count; i += 2) {
        Integer amount = strtoll(fields[i + 1], NULL, 10);
        outputs[output_count++] = (Output){named_wallet(wallets, fields[i])->address, amount};
        total += amount;
    }
    char *prefix = format("PAY %s fee %" PRId64 " total %" PRId64, wallet->name, fee, total);
    Coin *coins = malloc((size_t)tip->utxo.count * sizeof *coins);
    int coin_count = 0;
    for (int i = 0; i < tip->utxo.count; ++i) {
        Coin coin = tip->utxo.items[i];
        if (!strcmp(coin.address, wallet->address) && !locked(coin.reference) &&
            mature(coin, next_height(), p.maturity))
            coins[coin_count++] = coin;
    }
    qsort(coins, (size_t)coin_count, sizeof *coins, selection_compare);
    Reference *inputs = malloc((size_t)coin_count * sizeof *inputs);
    int input_count = 0;
    Integer gathered = 0;
    for (int i = 0; i < coin_count && gathered < total + fee; ++i) {
        inputs[input_count++] = coins[i].reference;
        gathered += coins[i].amount;
    }
    if (gathered < total + fee) {
        log_event("%s rejected insufficient-funds", prefix);
        tally("pay", "insufficient-funds");
        free(inputs);
        free(outputs);
        free(coins);
        return;
    }
    if (gathered > total + fee)
        outputs[output_count++] = (Output){wallet->address, gathered - total - fee};
    Transaction *tx = payment(inputs, input_count, outputs, output_count, wallet->secret);
    Acceptance result = acceptance(tx);
    if (result.reason) {
        log_event("%s tx %s rejected %s", prefix, short_hash(tx->id), result.reason);
        tally("pay", result.reason);
    } else {
        log_event("%s tx %s accepted inputs %d outputs %d size %zu", prefix, short_hash(tx->id),
                  tx->input_count, tx->output_count, strlen(tx->text));
        register_transaction(tx, result, now);
    }
    free(inputs);
    free(outputs);
    free(coins);
}
static void bump(const char *id, Integer fee) {
    char *prefix = format("BUMP %s fee %" PRId64, short_hash(id), fee);
    int index = entry_index(id);
    if (index < 0) {
        log_event("%s rejected unknown", prefix);
        tally("bump", "unknown");
        return;
    }
    Entry entry = pool[index];
    Transaction *old = entry.tx;
    Output *outputs = malloc((size_t)old->output_count * sizeof *outputs);
    memcpy(outputs, old->outputs, (size_t)old->output_count * sizeof *outputs);
    Output *last = outputs + old->output_count - 1;
    last->amount -= fee - entry.fee;
    bool same = true;
    for (int i = 0; i < old->input_count; ++i)
        if (strcmp(find_coin(&tip->utxo, old->inputs[i])->address, last->address))
            same = false;
    if (!same || last->amount < 1) {
        log_event("%s rejected no-change", prefix);
        tally("bump", "no-change");
        free(outputs);
        return;
    }
    Transaction *tx = payment(old->inputs, old->input_count, outputs, old->output_count,
                              owner(wallets, last->address)->secret);
    Acceptance result = acceptance(tx);
    if (result.reason) {
        log_event("%s tx %s rejected %s", prefix, short_hash(tx->id), result.reason);
        tally("bump", result.reason);
    } else {
        log_event("%s tx %s accepted size %zu", prefix, short_hash(tx->id), strlen(tx->text));
        register_transaction(tx, result, now);
    }
    free(outputs);
}
static void receive_transaction(Transaction *tx, Peer *peer) {
    Acceptance result = acceptance(tx);
    if (result.reason) {
        ++peer->rejected_txs;
        tally("tx", result.reason);
        log_event("TX %s %s rejected %s", peer->name, short_hash(tx->id), result.reason);
        if (!strcmp(result.reason, "coinbase") || !strcmp(result.reason, "bad-output") ||
            !strcmp(result.reason, "bad-sig") || !strcmp(result.reason, "overspend"))
            penalize(peer, p.tx_penalty);
        return;
    }
    ++peer->txs;
    log_event("TX %s %s accepted fee %" PRId64 " size %zu", peer->name, short_hash(tx->id), result.fee,
              strlen(tx->text));
    register_transaction(tx, result, now);
}
static void mine(Wallet *wallet) {
    int height = next_height(), count = 1;
    Integer size = 0, fees = 0;
    Entry *order = ordered();
    Transaction **txs = malloc((size_t)(pool_count + 1) * sizeof *txs);
    Integer *amounts = malloc((size_t)(pool_count + 1) * sizeof *amounts);
    for (int i = 0; i < pool_count; ++i)
        if (size + (Integer)strlen(order[i].tx->text) <= p.max_size) {
            txs[count] = order[i].tx;
            amounts[count - 1] = order[i].fee;
            ++count;
            size += (Integer)strlen(order[i].tx->text);
            fees += order[i].fee;
        }
    Output output = {wallet->address, block_reward(height) + fees};
    txs[0] = coinbase(height, &output, 1);
    Integer time = median_time(tip) + 1;
    if (time < now)
        time = now;
    Block *block = mine_block(height, tip->block->hash, txs, count, time, next_bits(tip));
    Utxo coins = copy_utxo(tip->utxo);
    for (int i = 0; i < count; ++i)
        apply_transaction(&coins, txs[i], height);
    Record *record = make_record(block, tip, coins, amounts, "local");
    records[record_count++] = record;
    log_event("MINE %s %d %s bits %d nonce %" PRId64 " txs %d size %" PRId64 " fees %" PRId64
              " work %" PRId64,
              wallet->name, height, short_hash(block->hash), block->difficulty, block->nonce, count, size,
              fees, record->work);
    switch_tip(record);
    free(order);
}
static void status(const char *id) {
    char *prefix = format("STATUS %s", short_hash(id));
    int height = confirmed(id);
    if (height >= 0) {
        log_event("%s confirmed %d confirmations %d", prefix, height, next_height() - height);
        return;
    }
    Entry *order = ordered();
    for (int i = 0; i < pool_count; ++i)
        if (!strcmp(order[i].tx->id, id)) {
            log_event("%s mempool rank %d of %d", prefix, i + 1, pool_count);
            free(order);
            return;
        }
    free(order);
    for (int i = 0; i < drop_count; ++i)
        if (!strcmp(drops[i].id, id)) {
            log_event("%s dropped %s", prefix, drops[i].reason);
            return;
        }
    for (int i = 0; i < record_count; ++i)
        for (int j = 0; j < records[i]->block->count; ++j)
            if (!strcmp(records[i]->block->transactions[j]->id, id)) {
                log_event("%s stale", prefix);
                return;
            }
    log_event("%s unknown", prefix);
}
static void print_state(void) {
    Integer size = 0;
    for (int i = 0; i < pool_count; ++i)
        size += (Integer)strlen(pool[i].tx->text);
    log_event("PRINT height %d tip %s work %" PRId64 " bits %d reward %" PRId64 " mempool %d size %" PRId64
              " orphans %d",
              tip->block->height, short_hash(tip->block->hash), tip->work, next_bits(tip),
              block_reward(next_height()), pool_count, size, orphan_count);
    Entry *order = ordered();
    for (int i = 0; i < pool_count; ++i)
        log_event("MEMPOOL %d %s fee %" PRId64 " size %zu", i + 1, short_hash(order[i].tx->id), order[i].fee,
                  strlen(order[i].tx->text));
    free(order);
    for (int i = 0; i < wallets.count; ++i)
        log_event("BALANCE %s %" PRId64, wallets.items[i].name, balance(wallets.items[i].address));
}
static const char *miner(Record *r) {
    return r->block->height ? owner(wallets, r->block->transactions[0]->outputs[0].address)->name : "-";
}
static int record_compare(const void *first, const void *second) {
    Record *a = *(Record *const *)first, *b = *(Record *const *)second;
    if (a->block->height != b->block->height)
        return a->block->height < b->block->height ? -1 : 1;
    return strcmp(a->block->hash, b->block->hash);
}
static int peer_compare(const void *first, const void *second) {
    return strcmp((*(Peer *const *)first)->name, (*(Peer *const *)second)->name);
}
static int rejection_compare(const void *first, const void *second) {
    const Rejection *a = first, *b = second;
    int order = strcmp(a->category, b->category);
    return order ? order : strcmp(a->reason, b->reason);
}
static void write_chain(void) {
    FILE *out = fopen("output/chain.txt", "w");
    fprintf(out, "TIP %d %s work %" PRId64 " stored %d orphans %d\n", tip->block->height, tip->block->hash,
            tip->work, record_count, orphan_count);
    Integer rewards = 0, fees = 0, coinbases = 0;
    for (int i = 0; i < chain_count; ++i) {
        Record *r = main_chain[i];
        Block *b = r->block;
        fprintf(out,
                "BLOCK %d %s prev %s time %" PRId64 " bits %d nonce %" PRId64 " txs %d size %" PRId64
                " fees %" PRId64 " miner %s source %s work %" PRId64 "\n",
                b->height, b->hash, short_hash(b->previous), b->time, b->difficulty, b->nonce, b->count,
                block_size(b), r->fees, miner(r), r->source, r->work);
        for (int j = 0; j < b->count; ++j) {
            Transaction *tx = b->transactions[j];
            fprintf(out, "TX %d %s ", j + 1, tx->id);
            if (tx->coinbase_height >= 0)
                fprintf(out, "%s out %d amount %" PRId64 "\n", b->height ? "coinbase" : "genesis",
                        tx->output_count, output_total(tx));
            else
                fprintf(out, "payment in %d out %d size %zu fee %" PRId64 "\n", tx->input_count,
                        tx->output_count, strlen(tx->text), r->transaction_fees[j - 1]);
        }
        if (b->height) {
            rewards += block_reward(b->height);
            fees += r->fees;
            coinbases += output_total(b->transactions[0]);
        }
    }
    Record *stale[61];
    int stale_count = 0;
    for (int i = 0; i < record_count; ++i) {
        bool main = false;
        for (int j = 0; j < chain_count; ++j)
            if (main_chain[j] == records[i])
                main = true;
        if (!main)
            stale[stale_count++] = records[i];
    }
    qsort(stale, (size_t)stale_count, sizeof *stale, record_compare);
    for (int i = 0; i < stale_count; ++i) {
        Record *r = stale[i];
        fprintf(out, "STALE %d %s prev %s source %s work %" PRId64 "\n", r->block->height, r->block->hash,
                short_hash(r->block->previous), r->source, r->work);
    }
    for (int i = 0; i < orphan_count; ++i)
        fprintf(out, "ORPHAN %d %s prev %s source %s\n", orphans[i].block->height, orphans[i].block->hash,
                short_hash(orphans[i].block->previous), orphans[i].peer->name);
    for (int i = 0; i < reorganization_count; ++i) {
        Reorganization r = reorganizations[i];
        fprintf(out, "REORG %" PRId64 " fork %d disconnected %d connected %d old %s new %s\n", r.time, r.fork,
                r.disconnected, r.connected, short_hash(r.old_hash), short_hash(r.new_hash));
    }
    for (int i = 0; i < wallets.count; ++i) {
        int count = 0;
        Integer amount = 0, total_fees = 0;
        const char *name = wallets.items[i].name;
        for (int j = 1; j < chain_count; ++j)
            if (!strcmp(miner(main_chain[j]), name)) {
                ++count;
                amount += output_total(main_chain[j]->block->transactions[0]);
                total_fees += main_chain[j]->fees;
            }
        if (count)
            fprintf(out, "MINER %s blocks %d coinbase %" PRId64 " fees %" PRId64 "\n", name, count, amount,
                    total_fees);
    }
    for (int first = 1; first < chain_count;) {
        int last = first, bits = main_chain[first]->block->difficulty;
        while (last + 1 < chain_count && main_chain[last + 1]->block->difficulty == bits)
            ++last;
        fprintf(out, "BITS %d heights %d-%d blocks %d\n", bits, first, last, last - first + 1);
        first = last + 1;
    }
    Peer *peer_order[2000];
    for (int i = 0; i < peer_count; ++i)
        peer_order[i] = peers + i;
    qsort(peer_order, (size_t)peer_count, sizeof *peer_order, peer_compare);
    for (int i = 0; i < peer_count; ++i) {
        Peer *q = peer_order[i];
        fprintf(out,
                "PEER %s blocks %" PRId64 " rejected %" PRId64 " orphans %" PRId64 " txs %" PRId64
                " rejected %" PRId64 " ignored %" PRId64 " score %" PRId64 " %s\n",
                q->name, q->blocks, q->rejected_blocks, q->orphans, q->txs, q->rejected_txs, q->ignored,
                q->score, q->score >= p.ban ? "banned" : "ok");
    }
    Entry *order = ordered();
    for (int i = 0; i < pool_count; ++i)
        fprintf(out, "MEMPOOL %d %s fee %" PRId64 " size %zu time %" PRId64 "\n", i + 1, order[i].tx->id,
                order[i].fee, strlen(order[i].tx->text), order[i].arrival);
    free(order);
    qsort(rejections, (size_t)rejection_count, sizeof *rejections, rejection_compare);
    for (int i = 0; i < rejection_count; ++i)
        fprintf(out, "REJECT %s %s %" PRId64 "\n", rejections[i].category, rejections[i].reason,
                rejections[i].count);
    Integer total = 0;
    for (int i = 0; i < tip->utxo.count; ++i)
        total += tip->utxo.items[i].amount;
    fprintf(out,
            "SUPPLY genesis %" PRId64 " rewards %" PRId64 " fees %" PRId64 " burned %" PRId64 " utxo %" PRId64
            "\n",
            output_total(main_chain[0]->block->transactions[0]), rewards, fees, rewards + fees - coinbases,
            total);
    fclose(out);
}
static void write_balances_utxo(void) {
    FILE *out = fopen("output/balances.csv", "w");
    fputs("wallet,address,balance,immature,locked,incoming,utxos\n", out);
    for (int i = 0; i < wallets.count; ++i) {
        Wallet w = wallets.items[i];
        Integer amount = 0, immature = 0, locked_amount = 0, incoming = 0, count = 0;
        for (int j = 0; j < tip->utxo.count; ++j) {
            Coin c = tip->utxo.items[j];
            if (strcmp(c.address, w.address))
                continue;
            amount += c.amount;
            ++count;
            if (!mature(c, next_height(), p.maturity))
                immature += c.amount;
            if (locked(c.reference))
                locked_amount += c.amount;
        }
        for (int j = 0; j < pool_count; ++j)
            for (int k = 0; k < pool[j].tx->output_count; ++k) {
                Output o = pool[j].tx->outputs[k];
                if (!strcmp(o.address, w.address))
                    incoming += o.amount;
            }
        fprintf(out, "%s,%s,%" PRId64 ",%" PRId64 ",%" PRId64 ",%" PRId64 ",%" PRId64 "\n", w.name, w.address,
                amount, immature, locked_amount, incoming, count);
    }
    fclose(out);
    out = fopen("output/utxo.txt", "w");
    Utxo coins = copy_utxo(tip->utxo);
    qsort(coins.items, (size_t)coins.count, sizeof *coins.items, coin_compare);
    char **hashes = malloc((size_t)coins.count * sizeof *hashes);
    Integer total = 0;
    for (int i = 0; i < coins.count; ++i) {
        Coin c = coins.items[i];
        const char *category = c.height == 0 ? "genesis"
                               : c.coinbase  ? "coinbase"
                                             : "payment",
                   *state = !mature(c, next_height(), p.maturity) ? "immature"
                            : locked(c.reference)                 ? "locked"
                                                                  : "free";
        char *line = format("%s:%d %s %" PRId64 " height %d %s %s", c.reference.id, c.reference.index,
                            owner(wallets, c.address)->name, c.amount, c.height, category, state);
        fprintf(out, "%s\n", line);
        hashes[i] = digest(line);
        free(line);
        total += c.amount;
    }
    fprintf(out, "TOTAL %d %" PRId64 "\nROOT %s\n", coins.count, total, merkle(hashes, coins.count));
    fclose(out);
    free(hashes);
    free(coins.items);
}
static Output referenced_output(Reference reference) {
    for (int i = 0; i < chain_count; ++i)
        for (int j = 0; j < main_chain[i]->block->count; ++j) {
            Transaction *tx = main_chain[i]->block->transactions[j];
            if (!strcmp(tx->id, reference.id))
                return tx->outputs[reference.index];
        }
    abort();
}
static void write_history(void) {
    FILE *out = fopen("output/history.txt", "w");
    for (int i = 0; i < wallets.count; ++i) {
        Wallet w = wallets.items[i];
        Integer count = 0, total_spent = 0, total_received = 0, balance_value = 0, pending = 0;
        fprintf(out, "WALLET %s %s\n", w.name, w.address);
        for (int j = 0; j < chain_count; ++j)
            for (int k = 0; k < main_chain[j]->block->count; ++k) {
                Transaction *tx = main_chain[j]->block->transactions[k];
                Integer spent = 0, received = 0;
                for (int a = 0; a < tx->input_count; ++a) {
                    Output o = referenced_output(tx->inputs[a]);
                    if (!strcmp(o.address, w.address))
                        spent += o.amount;
                }
                for (int a = 0; a < tx->output_count; ++a)
                    if (!strcmp(tx->outputs[a].address, w.address))
                        received += tx->outputs[a].amount;
                if (!spent && !received)
                    continue;
                ++count;
                total_spent += spent;
                total_received += received;
                balance_value += received - spent;
                fprintf(out,
                        "%d %s %s spent %" PRId64 " received %" PRId64 " net %+" PRId64 " balance %" PRId64
                        "\n",
                        j, short_hash(tx->id),
                        j == 0                     ? "genesis"
                        : tx->coinbase_height >= 0 ? "coinbase"
                                                   : "payment",
                        spent, received, received - spent, balance_value);
            }
        Entry *order = ordered();
        for (int j = 0; j < pool_count; ++j) {
            Transaction *tx = order[j].tx;
            Integer spent = 0, received = 0;
            for (int a = 0; a < tx->input_count; ++a) {
                Coin *c = find_coin(&tip->utxo, tx->inputs[a]);
                if (!strcmp(c->address, w.address))
                    spent += c->amount;
            }
            for (int a = 0; a < tx->output_count; ++a)
                if (!strcmp(tx->outputs[a].address, w.address))
                    received += tx->outputs[a].amount;
            if (!spent && !received)
                continue;
            ++pending;
            fprintf(out, "pending %s spent %" PRId64 " received %" PRId64 " net %+" PRId64 "\n",
                    short_hash(tx->id), spent, received, received - spent);
        }
        free(order);
        fprintf(out,
                "END %s txs %" PRId64 " spent %" PRId64 " received %" PRId64 " balance %" PRId64
                " pending %" PRId64 "\n",
                w.name, count, total_spent, total_received, balance_value, pending);
    }
    fclose(out);
}
static void initialize(void) {
    wallets = read_wallets();
    FILE *params = fopen("input/params.txt", "r");
    char *line;
    int row = 0;
    while ((line = read_line(params))) {
        int count;
        char **v = split(line, ' ', &count);
        Integer a = strtoll(v[1], NULL, 10), b = count > 2 ? strtoll(v[2], NULL, 10) : 0;
        switch (row++) {
        case 0:
            p.initial_bits = (int)a;
            break;
        case 1:
            p.retarget = (int)a;
            p.target = b;
            break;
        case 2:
            p.initial_reward = a;
            p.halving = (int)b;
            break;
        case 3:
            p.maturity = (int)a;
            break;
        case 4:
            p.max_size = a;
            break;
        case 5:
            p.min_rate = a;
            break;
        case 6:
            p.pool_limit = (int)a;
            break;
        case 7:
            p.orphan_limit = (int)a;
            break;
        case 8:
            p.drift = a;
            break;
        case 9:
            p.expiry = a;
            break;
        case 10:
            p.max_reorg = (int)a;
            break;
        case 11:
            p.ban = a;
            p.block_penalty = b;
            p.tx_penalty = strtoll(v[3], NULL, 10);
            break;
        case 12:
            p.genesis_count = (count - 1) / 2;
            p.genesis = malloc((size_t)p.genesis_count * sizeof *p.genesis);
            for (int i = 0; i < p.genesis_count; ++i)
                p.genesis[i] =
                    (Output){named_wallet(wallets, v[1 + 2 * i])->address, strtoll(v[2 + 2 * i], NULL, 10)};
            break;
        }
        free(v);
    }
    fclose(params);
    mkdir("output", 0777);
    log_file = fopen("output/log.txt", "w");
    Transaction *tx = coinbase(0, p.genesis, p.genesis_count);
    Block *genesis = calloc(1, sizeof *genesis);
    genesis->previous = "00000000000000000000000000000000";
    genesis->root = tx->id;
    genesis->transactions = malloc(sizeof *genesis->transactions);
    genesis->transactions[0] = tx;
    genesis->count = 1;
    hash_header(genesis);
    Utxo coins = {0};
    apply_transaction(&coins, tx, 0);
    tip = make_record(genesis, NULL, coins, NULL, "genesis");
    records[record_count++] = tip;
    refresh();
}
int main(void) {
    initialize();
    FILE *events = fopen("input/events.txt", "r");
    char *line;
    while ((line = read_line(events))) {
        int count;
        char **fields = split(line, ' ', &count);
        char **texts = NULL;
        int text_count = 0;
        if (!strcmp(fields[1], "BLOCK")) {
            text_count = atoi(fields[9]);
            texts = malloc((size_t)text_count * sizeof *texts);
            for (int i = 0; i < text_count; ++i)
                texts[i] = read_line(events);
        }
        now = strtoll(fields[0], NULL, 10);
        for (int i = 0; i < pool_count;) {
            if (now - pool[i].arrival >= p.expiry)
                drop_transaction(pool[i].tx->id, "expired");
            else
                ++i;
        }
        const char *kind = fields[1];
        if (!strcmp(kind, "PAY"))
            pay(fields, count);
        else if (!strcmp(kind, "BUMP"))
            bump(fields[2], strtoll(fields[3], NULL, 10));
        else if (!strcmp(kind, "MINE"))
            mine(named_wallet(wallets, fields[2]));
        else if (!strcmp(kind, "STATUS"))
            status(fields[2]);
        else if (!strcmp(kind, "PRINT"))
            print_state();
        else {
            Peer *peer = peer_record(fields[2]);
            if (peer->score >= p.ban) {
                ++peer->ignored;
                log_event("IGNORE %s %s", peer->name, kind);
            } else if (!strcmp(kind, "TX"))
                receive_transaction(parse_transaction(fields[3]), peer);
            else
                receive_block(parse_block(fields, texts, text_count), peer);
        }
        free(fields);
        free(texts);
    }
    fclose(events);
    write_chain();
    write_balances_utxo();
    write_history();
    fclose(log_file);
    return 0;
}
