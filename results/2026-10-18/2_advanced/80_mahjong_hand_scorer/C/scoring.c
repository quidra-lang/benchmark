#include "mahjong.h"
#include <stdio.h>
#include <string.h>

int pair_fu(int pair, int seat, int round) {
    return (pair >= 31 ? 2 : 0) + (pair == seat ? 2 : 0) + (pair == round ? 2 : 0);
}
bool concealed(Block block, char by) {
    return block.source == 'A' || block.source == 'c' && (!block.winning || by == 't');
}
static void add_fu(Candidate *candidate, const char *name, int value) {
    FuItem *item = &candidate->fu_items[candidate->fu_count++];
    snprintf(item->name, sizeof(item->name), "%s", name);
    item->value = value;
    candidate->fu_total += value;
}
void fu_breakdown(Candidate *candidate, const Situation *s, bool closed, bool pinfu) {
    if (candidate->kind == FORM_CHIITOITSU) {
        add_fu(candidate, "chiitoitsu", 25);
        candidate->fu = 25;
        return;
    }
    add_fu(candidate, "base", 20);
    if (closed && s->by == 'r')
        add_fu(candidate, "closed_ron", 10);
    if (s->by == 't' && !pinfu)
        add_fu(candidate, "tsumo", 2);
    int pair = pair_fu(candidate->pair, wind_kind(s->seat), wind_kind(s->round));
    char block[6], name[64];
    if (pair > 0) {
        block_notation(candidate->pair, 2, false, block);
        snprintf(name, sizeof(name), "pair %s", block);
        add_fu(candidate, name, pair);
    }
    for (int i = 0; i < candidate->block_count; ++i) {
        Block b = candidate->blocks[i];
        if (b.sequence)
            continue;
        bool hidden = concealed(b, s->by);
        const char *type = hidden ? "closed_triplet" : "open_triplet";
        int value = hidden ? 4 : 2;
        if (b.kan) {
            type = hidden ? "closed_kan" : "open_kan";
            value = hidden ? 16 : 8;
        }
        if (yaochuu(b.kind))
            value *= 2;
        block_name(b, block);
        snprintf(name, sizeof(name), "%s %s", type, block);
        add_fu(candidate, name, value);
    }
    if (candidate->wait == W_KANCHAN || candidate->wait == W_PENCHAN ||
        candidate->wait == W_TANKI) {
        snprintf(name, sizeof(name), "wait %s", wait_names[candidate->wait]);
        add_fu(candidate, name, 2);
    }
    if (!closed && candidate->fu_total == 20)
        add_fu(candidate, "open_pinfu", 10);
    candidate->fu = (candidate->fu_total + 9) / 10 * 10;
}
void limit_score(int han, int fu, const Rule *rule, int *category, int *base) {
    if (han >= 13 && rule->kazoe) {
        *category = L_KAZOE;
        *base = 8000;
    } else if (han >= 11) {
        *category = L_SANBAIMAN;
        *base = 6000;
    } else if (han >= 8) {
        *category = L_BAIMAN;
        *base = 4000;
    } else if (han >= 6) {
        *category = L_HANEMAN;
        *base = 3000;
    } else {
        *base = fu * (1 << (han + 2));
        if (han == 5 || *base >= 2000 || rule->kiriage && *base == 1920) {
            *category = L_MANGAN;
            *base = 2000;
        } else
            *category = L_NONE;
    }
}
int round_hundred(int value) { return (value + 99) / 100 * 100; }
Payment payments(int base, char seat, char by) {
    Payment p = {0};
    if (by == 'r') {
        p.ron = round_hundred((seat == 'E' ? 6 : 4) * base);
        p.points = p.ron;
    } else if (seat == 'E') {
        p.all = round_hundred(2 * base);
        p.points = 3 * p.all;
    } else {
        p.dealer = round_hundred(2 * base);
        p.nondealer = round_hundred(base);
        p.points = p.dealer + 2 * p.nondealer;
    }
    return p;
}
