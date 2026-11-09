#include "ledger.h"
Record *make_record(Block *block, Record *parent, Utxo utxo, Integer *fees, const char *source) {
    Record *record = calloc(1, sizeof *record);
    record->block = block;
    record->parent = parent;
    record->utxo = utxo;
    record->transaction_fees = fees;
    record->source = copy_text(source);
    record->work = parent ? parent->work + ((Integer)1 << (4 * block->difficulty)) : 1;
    for (int i = 1; i < block->count; ++i)
        record->fees += fees[i - 1];
    return record;
}
Integer reward(int height, Integer amount, int interval) {
    for (int i = 0; i < height / interval; ++i)
        amount /= 2;
    return amount;
}
Record *ancestor(Record *record, int height) {
    while (record->block->height > height)
        record = record->parent;
    return record;
}
Record **chain_to(Record *record, int *count) {
    *count = record->block->height + 1;
    Record **chain = malloc((size_t)*count * sizeof *chain);
    for (int i = *count - 1; i >= 0; --i) {
        chain[i] = record;
        record = record->parent;
    }
    return chain;
}
Record *fork_point(Record *a, Record *b) {
    int height = a->block->height < b->block->height ? a->block->height : b->block->height;
    a = ancestor(a, height);
    b = ancestor(b, height);
    while (a != b) {
        a = a->parent;
        b = b->parent;
    }
    return a;
}
Integer median_time(Record *record) {
    Integer times[3];
    int count = 0;
    while (record && count < 3) {
        times[count++] = record->block->time;
        record = record->parent;
    }
    for (int i = 0; i < count; ++i)
        for (int j = i + 1; j < count; ++j)
            if (times[j] < times[i]) {
                Integer swap = times[i];
                times[i] = times[j];
                times[j] = swap;
            }
    return times[(count - 1) / 2];
}
int required_difficulty(Record *parent, int initial, int interval, Integer target) {
    int height = parent->block->height + 1, bits = parent->block->difficulty;
    if (height == 1)
        return initial;
    if (height % interval)
        return bits;
    Integer span = parent->block->time - ancestor(parent, height - interval)->block->time,
            expected = target * (interval - 1);
    if (2 * span < expected)
        return bits < 2 ? bits + 1 : 2;
    if (span > 2 * expected)
        return bits > 0 ? bits - 1 : 0;
    return bits;
}
