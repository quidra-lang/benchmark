#include "ledger.hpp"
Record::Record(Block value, Record *previous, Utxo coins, std::vector<Integer> amounts, std::string origin)
    : block(std::move(value)), parent(previous), utxo(std::move(coins)), transaction_fees(std::move(amounts)),
      source(std::move(origin)) {
    fees = std::accumulate(transaction_fees.begin(), transaction_fees.end(), Integer(0));
    if (parent)
        work = parent->work + (Integer(1) << (4 * block.difficulty));
}
Integer reward(int height, Integer initial, int interval) {
    for (int i = 0; i < height / interval; ++i)
        initial /= 2;
    return initial;
}
Record *ancestor(Record *record, int height) {
    while (record->block.height > height)
        record = record->parent;
    return record;
}
std::vector<Record *> chain_to(Record *record) {
    std::vector<Record *> result;
    for (; record; record = record->parent)
        result.push_back(record);
    std::reverse(result.begin(), result.end());
    return result;
}
Record *fork_point(Record *a, Record *b) {
    const int height = std::min(a->block.height, b->block.height);
    a = ancestor(a, height);
    b = ancestor(b, height);
    while (a != b) {
        a = a->parent;
        b = b->parent;
    }
    return a;
}
Integer median_time(Record *record) {
    std::vector<Integer> times;
    while (record && times.size() < 3) {
        times.push_back(record->block.time);
        record = record->parent;
    }
    std::sort(times.begin(), times.end());
    return times[(times.size() - 1) / 2];
}
int required_difficulty(Record *parent, int initial, int interval, Integer target) {
    const int height = parent->block.height + 1, bits = parent->block.difficulty;
    if (height == 1)
        return initial;
    if (height % interval)
        return bits;
    const Integer span = parent->block.time - ancestor(parent, height - interval)->block.time,
                  expected = target * (interval - 1);
    if (2 * span < expected)
        return std::min(bits + 1, 2);
    if (span > 2 * expected)
        return std::max(bits - 1, 0);
    return bits;
}
