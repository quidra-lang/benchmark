#include "simulator.h"
BTB btb_create(int entries) {
    BTB out = {allocate((size_t)entries, sizeof(BTBEntry)), entries};
    return out;
}
bool btb_lookup(BTB *btb, I pc, I *target) {
    BTBEntry entry = btb->entries[(pc / 4) % btb->count];
    if (!entry.valid || entry.pc != pc)
        return false;
    *target = entry.target;
    return true;
}
void btb_insert(BTB *btb, I pc, I target) {
    btb->entries[(pc / 4) % btb->count] = (BTBEntry){true, pc, target};
}
void ras_push(RAS *ras, I value) {
    if (ras->depth == 0)
        return;
    if (ras->count == ras->depth) {
        memmove(ras->stack, ras->stack + 1, (size_t)(ras->count - 1) * sizeof(I));
        --ras->count;
    }
    ras->stack[ras->count++] = value;
}
bool ras_pop(RAS *ras, I *value) {
    if (ras->count == 0)
        return false;
    *value = ras->stack[--ras->count];
    return true;
}
static int updated(int counter, bool taken) {
    return taken ? (counter < 3 ? counter + 1 : 3) : (counter > 0 ? counter - 1 : 0);
}
static int *table(int size, int initial) {
    int *out = allocate((size_t)size, sizeof(int));
    for (int i = 0; i < size; ++i)
        out[i] = initial;
    return out;
}
DirectionPredictor direction_create(Predictor definition) {
    DirectionPredictor out = {0};
    out.definition = definition;
    const int *p = definition.parameters;
    const char *s = definition.scheme;
    if (strcmp(s, "ONEBIT") == 0 || strcmp(s, "TWOBIT") == 0 || strcmp(s, "GSHARE") == 0)
        out.table = table(p[0], strcmp(s, "ONEBIT") == 0 ? 0 : 1);
    if (strcmp(s, "TOURNAMENT") == 0) {
        out.local = table(p[0], 1);
        out.global_table = table(p[1], 1);
        out.chooser = table(p[3], 1);
    }
    return out;
}
bool direction_predict(DirectionPredictor *d, I pc, I target) {
    const char *s = d->definition.scheme;
    const int *p = d->definition.parameters;
    I index = pc / 4;
    if (strcmp(s, "STATIC_NT") == 0 || strcmp(s, "PERFECT") == 0)
        return false;
    if (strcmp(s, "BTFN") == 0)
        return target < pc;
    if (strcmp(s, "ONEBIT") == 0)
        return d->table[index % p[0]] == 1;
    if (strcmp(s, "TWOBIT") == 0)
        return d->table[index % p[0]] >= 2;
    if (strcmp(s, "GSHARE") == 0)
        return d->table[(index ^ d->history) % p[0]] >= 2;
    return d->chooser[index % p[3]] >= 2 ? d->global_table[(index ^ d->history) % p[1]] >= 2
                                         : d->local[index % p[0]] >= 2;
}
void direction_update(DirectionPredictor *d, I pc, bool taken) {
    const char *s = d->definition.scheme;
    const int *p = d->definition.parameters;
    I index = pc / 4;
    if (strcmp(s, "STATIC_NT") == 0 || strcmp(s, "BTFN") == 0 || strcmp(s, "PERFECT") == 0)
        return;
    if (strcmp(s, "TOURNAMENT") == 0) {
        int l = (int)(index % p[0]), g = (int)((index ^ d->history) % p[1]),
            ch = (int)(index % p[3]);
        if ((d->local[l] >= 2) != (d->global_table[g] >= 2))
            d->chooser[ch] = updated(d->chooser[ch], (d->global_table[g] >= 2) == taken);
        d->local[l] = updated(d->local[l], taken);
        d->global_table[g] = updated(d->global_table[g], taken);
        d->history = (2 * d->history + taken) % (1 << p[2]);
    } else {
        bool global = strcmp(s, "GSHARE") == 0;
        int t = (int)((global ? (index ^ d->history) : index) % p[0]);
        d->table[t] = strcmp(s, "ONEBIT") == 0 ? taken : updated(d->table[t], taken);
        if (global)
            d->history = (2 * d->history + taken) % (1 << p[1]);
    }
}
int storage(Predictor d) {
    const int *p = d.parameters;
    if (strcmp(d.scheme, "ONEBIT") == 0)
        return p[0];
    if (strcmp(d.scheme, "TWOBIT") == 0)
        return 2 * p[0];
    if (strcmp(d.scheme, "GSHARE") == 0)
        return 2 * p[0] + p[1];
    if (strcmp(d.scheme, "TOURNAMENT") == 0)
        return 2 * (p[0] + p[1] + p[3]) + p[2];
    return 0;
}
void direction_free(DirectionPredictor *d) {
    free(d->table);
    free(d->local);
    free(d->global_table);
    free(d->chooser);
}
