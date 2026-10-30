#include "mahjong.h"
#include <errno.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <sys/stat.h>

typedef struct {
    char *label;
    char *values[14];
    int count;
} Record;
typedef struct {
    int hands, wins, points;
} RuleStatistics;
typedef struct {
    int hands, wins, furiten, no_yaku, errors, methods[4], waits[WAIT_COUNT], han[256], fu[256],
        limits[LIMIT_COUNT], yaku[YAKU_COUNT], yakuman[YAKUMAN_COUNT], points, maximum;
    char *maximum_label;
    RuleStatistics rules[26];
} ScoreStatistics;
static FILE *open_file(const char *path, const char *mode) {
    FILE *file = fopen(path, mode);
    if (!file) {
        perror(path);
        exit(EXIT_FAILURE);
    }
    return file;
}
static char *read_line(FILE *file) {
    size_t count = 0, capacity = 128;
    char *line = checked_realloc(NULL, capacity);
    int c;
    while ((c = fgetc(file)) != EOF && c != '\n') {
        if (count + 1 == capacity) {
            capacity *= 2;
            line = checked_realloc(line, capacity);
        }
        line[count++] = (char)c;
    }
    if (!count && c == EOF) {
        free(line);
        return NULL;
    }
    line[count] = 0;
    return line;
}
static char *copy_string(const char *text) {
    size_t size = strlen(text) + 1;
    char *copy = checked_realloc(NULL, size);
    memcpy(copy, text, size);
    return copy;
}
static Record read_record(char *line) {
    Record record = {.label = line};
    char *space = strchr(line, ' ');
    if (!space)
        return record;
    *space++ = 0;
    while (*space) {
        char *part = space;
        space = strchr(part, ' ');
        if (space)
            *space++ = 0;
        char *equal = strchr(part, '=');
        record.values[record.count++] = equal + 1;
        if (!space)
            break;
    }
    return record;
}
int wind_kind(char wind) { return 27 + (wind == 'E' ? 0 : wind == 'S' ? 1 : wind == 'W' ? 2 : 3); }
static bool closed_hand(const Situation *s) {
    for (size_t i = 0; i < s->meld_count; ++i)
        if (s->melds[i].type != 'A')
            return false;
    return true;
}
static Tiles all_tiles(const Situation *s) {
    Tiles all = combine_tiles(s->hand, s->win);
    for (size_t i = 0; i < s->meld_count; ++i)
        all = combine_tiles(all, s->melds[i].tiles);
    return all;
}
static bool check_copies(Tiles tiles, const Rule *rule, char error[64]) {
    if (!rule->red && tiles.reds[0] + tiles.reds[1] + tiles.reds[2] > 0) {
        strcpy(error, "red five not allowed");
        return true;
    }
    for (int kind = 0; kind < 34; ++kind)
        if (tiles.counts.values[kind] > 4) {
            char name[3];
            tile_name(kind, name);
            snprintf(error, 64, "too many copies of %s", name);
            return true;
        }
    for (int suit = 0; suit < 3; ++suit)
        if (tiles.reds[suit] > 1) {
            snprintf(error, 64, "too many copies of 0%c", "mps"[suit]);
            return true;
        }
    return false;
}
static Meld read_meld(char *text, bool *notation) {
    Meld meld = {.type = text[0]};
    if (!parse_tiles(text + 1, false, &meld.tiles)) {
        *notation = false;
        return meld;
    }
    int first = 0;
    while (!meld.tiles.counts.values[first])
        ++first;
    meld.block = (Block){.kind = first, .source = meld.type};
    if (meld.type == 'C') {
        meld.block.sequence = true;
        meld.valid = meld.tiles.size == 3 && first < 27 && first % 9 <= 6 &&
                     meld.tiles.counts.values[first] == 1 &&
                     meld.tiles.counts.values[first + 1] == 1 &&
                     meld.tiles.counts.values[first + 2] == 1;
    } else if (meld.type == 'P')
        meld.valid = meld.tiles.size == 3 && meld.tiles.counts.values[first] == 3;
    else if (meld.type == 'K' || meld.type == 'A') {
        meld.block.kan = true;
        meld.valid = meld.tiles.size == 4 && meld.tiles.counts.values[first] == 4;
    }
    return meld;
}
static Situation read_situation(Record record, const Rule *rule) {
    char **a = record.values;
    Situation s = {.label = record.label,
                   .rule = rule,
                   .by = a[4][0],
                   .seat = a[5][0],
                   .from = a[6][0],
                   .round = a[7][0],
                   .honba = atoi(a[12]),
                   .sticks = atoi(a[13]),
                   .notation = true};
    bool valid = parse_tiles(a[1], false, &s.hand);
    s.notation = s.notation && valid;
    valid = parse_tiles(a[3], false, &s.win);
    s.notation = s.notation && valid;
    valid = parse_tiles(a[9], false, &s.dora);
    s.notation = s.notation && valid;
    valid = parse_tiles(a[10], true, &s.ura);
    s.notation = s.notation && valid;
    valid = parse_tiles(a[11], true, &s.discards);
    s.notation = s.notation && valid;
    if (strcmp(a[2], "-") != 0) {
        size_t count = 1;
        for (char *p = a[2]; *p; ++p)
            if (*p == ',')
                ++count;
        s.melds = checked_realloc(NULL, count * sizeof(Meld));
        char *part = a[2];
        for (;;) {
            char *next = strchr(part, ',');
            if (next)
                *next++ = 0;
            s.melds[s.meld_count++] = read_meld(part, &s.notation);
            if (!next)
                break;
            part = next;
        }
    }
    if (strcmp(a[8], "-") != 0) {
        char *part = a[8];
        for (;;) {
            char *next = strchr(part, ',');
            if (next)
                *next++ = 0;
            for (int i = 0; i < FLAG_COUNT; ++i)
                if (strcmp(part, flag_names[i]) == 0)
                    s.flags[i] = true;
            if (!next)
                break;
            part = next;
        }
    }
    return s;
}
static bool check_situation(const Situation *s, char error[64]) {
    const char *message = NULL;
    if (!s->notation || s->win.size != 1)
        message = "bad tile notation";
    else if (s->meld_count > 4)
        message = "bad meld";
    if (message) {
        strcpy(error, message);
        return true;
    }
    int kans = 0;
    for (size_t i = 0; i < s->meld_count; ++i) {
        if (!s->melds[i].valid) {
            strcpy(error, "bad meld");
            return true;
        }
        if (s->melds[i].block.kan)
            ++kans;
    }
    if (s->hand.size != 13 - 3 * (int)s->meld_count) {
        strcpy(error, "wrong tile count");
        return true;
    }
    if (check_copies(
            combine_tiles(combine_tiles(combine_tiles(all_tiles(s), s->dora), s->ura), s->discards),
            s->rule, error))
        return true;
    if (s->by == 't' && s->from != '-' || s->by == 'r' && (s->from == '-' || s->from == s->seat)) {
        strcpy(error, "invalid discarder");
        return true;
    }
    bool closed = closed_hand(s), riichi = s->flags[F_RIICHI] || s->flags[F_DOUBLE_RIICHI];
    int flag_count = 0;
    for (int i = 0; i < FLAG_COUNT; ++i)
        flag_count += s->flags[i];
    for (int i = 0; i < FLAG_COUNT; ++i) {
        if (!s->flags[i])
            continue;
        bool valid = true;
        switch (i) {
        case F_RIICHI:
            valid = closed;
            break;
        case F_DOUBLE_RIICHI:
            valid = closed && !s->flags[F_RIICHI];
            break;
        case F_IPPATSU:
            valid = riichi && !s->flags[F_RINSHAN];
            break;
        case F_HAITEI:
            valid = s->by == 't' && !s->flags[F_RINSHAN];
            break;
        case F_HOUTEI:
            valid = s->by == 'r' && !s->flags[F_CHANKAN];
            break;
        case F_RINSHAN:
            valid = s->by == 't' && kans > 0;
            break;
        case F_CHANKAN:
            valid = s->by == 'r';
            break;
        case F_TENHOU:
            valid = s->seat == 'E' && s->by == 't' && !s->meld_count && flag_count == 1;
            break;
        case F_CHIIHOU:
            valid = s->seat != 'E' && s->by == 't' && !s->meld_count && flag_count == 1;
            break;
        }
        if (!valid) {
            snprintf(error, 64, "invalid flag %s", flag_names[i]);
            return true;
        }
    }
    if (s->dora.size != 1 + kans)
        message = "invalid dora indicators";
    else if (riichi && s->ura.size != s->dora.size || !riichi && s->ura.size != 0)
        message = "invalid ura indicators";
    else if (riichi && s->sticks == 0)
        message = "invalid sticks";
    else if (!winning_form(combine_tiles(s->hand, s->win).counts, (int)s->meld_count))
        message = "not a winning hand";
    if (message) {
        strcpy(error, message);
        return true;
    }
    return false;
}
static void evaluate_candidate(Candidate *c, const Situation *s) {
    Tiles all = all_tiles(s);
    bool closed = closed_hand(s);
    bool yaku[YAKU_COUNT] = {0}, yakuman[YAKUMAN_COUNT] = {0};
    bool all_simple = true, all_yao = true, all_honor = true, all_terminal = true, all_green = true,
         has_honor = false;
    int suit_mask = 0;
    for (int kind = 0; kind < 34; ++kind) {
        if (!all.counts.values[kind])
            continue;
        all_simple = all_simple && !yaochuu(kind);
        all_yao = all_yao && yaochuu(kind);
        all_terminal = all_terminal && terminal(kind);
        all_green = all_green && (kind == 19 || kind == 20 || kind == 21 || kind == 23 ||
                                  kind == 25 || kind == 32);
        if (honor(kind))
            has_honor = true;
        else {
            all_honor = false;
            suit_mask |= 1 << (kind / 9);
        }
    }
    yaku[Y_RIICHI] = s->flags[F_RIICHI];
    yaku[Y_DOUBLE_RIICHI] = s->flags[F_DOUBLE_RIICHI];
    yaku[Y_IPPATSU] = s->flags[F_IPPATSU];
    yaku[Y_HAITEI] = s->flags[F_HAITEI];
    yaku[Y_HOUTEI] = s->flags[F_HOUTEI];
    yaku[Y_RINSHAN] = s->flags[F_RINSHAN];
    yaku[Y_CHANKAN] = s->flags[F_CHANKAN];
    yaku[Y_MENZEN_TSUMO] = closed && s->by == 't';
    yaku[Y_TANYAO] = all_simple && (closed || s->rule->open_tanyao);
    yaku[Y_HONROUTOU] = all_yao;
    bool one_suit = suit_mask && (suit_mask & (suit_mask - 1)) == 0;
    yaku[Y_HONITSU] = one_suit && has_honor;
    yaku[Y_CHINITSU] = one_suit && !has_honor;
    yakuman[M_TENHOU] = s->flags[F_TENHOU];
    yakuman[M_CHIIHOU] = s->flags[F_CHIIHOU];
    yakuman[M_TSUUIISOU] = all_honor;
    yakuman[M_CHINROUTOU] = all_terminal;
    yakuman[M_RYUUIISOU] = all_green;
    if (!s->meld_count && one_suit && !has_honor) {
        int suit = 0;
        while (!((suit_mask >> suit) & 1))
            ++suit;
        bool chuuren = true, pure = true;
        for (int rank = 0; rank < 9; ++rank) {
            int required = rank == 0 || rank == 8 ? 3 : 1;
            chuuren = chuuren && all.counts.values[suit * 9 + rank] >= required;
            pure = pure && s->hand.counts.values[suit * 9 + rank] == required;
        }
        if (chuuren)
            yakuman[pure ? M_JUNSEI_CHUUREN : M_CHUUREN] = true;
    }
    if (c->kind == FORM_CHIITOITSU)
        yaku[Y_CHIITOITSU] = true;
    else if (c->kind == FORM_KOKUSHI)
        yakuman[c->wait == W_THIRTEEN ? M_KOKUSHI_13 : M_KOKUSHI] = true;
    else {
        bool triplets[34] = {0}, sequences[34] = {0};
        int concealed_count = 0, kans = 0, dragons = 0, winds = 0;
        bool all_blocks_yao = yaochuu(c->pair);
        for (int i = 0; i < c->block_count; ++i) {
            Block b = c->blocks[i];
            if (b.sequence) {
                sequences[b.kind] = true;
                all_blocks_yao = all_blocks_yao && (b.kind % 9 == 0 || b.kind % 9 == 6);
            } else {
                triplets[b.kind] = true;
                if (concealed(b, s->by))
                    ++concealed_count;
                if (b.kan)
                    ++kans;
                if (b.kind >= 31)
                    ++dragons;
                else if (b.kind >= 27)
                    ++winds;
                all_blocks_yao = all_blocks_yao && yaochuu(b.kind);
            }
        }
        int closed_sequences[34] = {0};
        bool all_sequences = c->set_count == 4;
        for (int i = 0; i < c->set_count; ++i) {
            Block b = c->sets[i];
            if (b.sequence)
                ++closed_sequences[b.kind];
            else
                all_sequences = false;
        }
        int pairs = 0, triplet_count = 0, sequence_count = 0;
        bool duplicate = false;
        for (int kind = 0; kind < 34; ++kind) {
            pairs += closed_sequences[kind] / 2;
            duplicate = duplicate || closed_sequences[kind] >= 2;
            triplet_count += triplets[kind];
            sequence_count += sequences[kind];
        }
        yaku[Y_PINFU] = closed && !s->meld_count && all_sequences &&
                        pair_fu(c->pair, wind_kind(s->seat), wind_kind(s->round)) == 0 &&
                        c->wait == W_RYANMEN;
        yaku[Y_RYANPEIKOU] = closed && all_sequences && pairs == 2;
        yaku[Y_IIPEIKOU] = closed && !yaku[Y_RYANPEIKOU] && duplicate;
        yaku[Y_HAKU] = triplets[31];
        yaku[Y_HATSU] = triplets[32];
        yaku[Y_CHUN] = triplets[33];
        yaku[Y_JIKAZE] = triplets[wind_kind(s->seat)];
        yaku[Y_BAKAZE] = triplets[wind_kind(s->round)];
        yaku[Y_TOITOI] = triplet_count == 4;
        yaku[Y_SANANKOU] = concealed_count == 3;
        for (int rank = 0; rank < 9; ++rank) {
            if (rank <= 6 && sequences[rank] && sequences[9 + rank] && sequences[18 + rank])
                yaku[Y_SANSHOKU_DOUJUN] = true;
            if (triplets[rank] && triplets[9 + rank] && triplets[18 + rank])
                yaku[Y_SANSHOKU_DOUKOU] = true;
        }
        for (int suit = 0; suit < 3; ++suit)
            if (sequences[suit * 9] && sequences[suit * 9 + 3] && sequences[suit * 9 + 6])
                yaku[Y_ITTSU] = true;
        if (sequence_count && all_blocks_yao)
            yaku[has_honor ? Y_CHANTA : Y_JUNCHAN] = true;
        yaku[Y_SANKANTSU] = kans == 3;
        yaku[Y_SHOUSANGEN] = dragons == 2 && c->pair >= 31;
        if (concealed_count == 4)
            yakuman[c->wait == W_TANKI ? M_SUUANKOU_TANKI : M_SUUANKOU] = true;
        yakuman[M_DAISANGEN] = dragons == 3;
        yakuman[M_DAISUUSHII] = winds == 4;
        yakuman[M_SHOUSUUSHII] = winds == 3 && c->pair >= 27 && c->pair <= 30;
        yakuman[M_SUUKANTSU] = kans == 4;
    }
    c->yakuman = yakuman_awards(yakuman, s->rule->double_yakuman);
    if (c->yakuman.count) {
        for (int i = 0; i < c->yakuman.count; ++i)
            c->multiplier += c->yakuman.items[i].value;
        c->category = L_YAKUMAN;
        c->base = 8000 * c->multiplier;
        return;
    }
    c->yaku = yaku_awards(yaku, closed);
    for (int kind = 0; kind < 34; ++kind) {
        c->dora += s->dora.counts.values[kind] * all.counts.values[next_dora(kind)];
        c->ura += s->ura.counts.values[kind] * all.counts.values[next_dora(kind)];
    }
    c->aka = all.reds[0] + all.reds[1] + all.reds[2];
    c->han = c->dora + c->aka + c->ura;
    for (int i = 0; i < c->yaku.count; ++i)
        c->han += c->yaku.items[i].value;
    fu_breakdown(c, s, closed, yaku[Y_PINFU]);
    if (c->yaku.count)
        limit_score(c->han, c->fu, s->rule, &c->category, &c->base);
}
static void append_candidate(Candidates *out, Candidate value) {
    if (out->count == out->capacity) {
        out->capacity = out->capacity ? 2 * out->capacity : 16;
        out->items = checked_realloc(out->items, out->capacity * sizeof(Candidate));
    }
    out->items[out->count++] = value;
}
static int compare_candidates(const void *first, const void *second) {
    return strcmp(((const Candidate *)first)->form, ((const Candidate *)second)->form);
}
static void append_form(char form[256], const char *block, bool winning) {
    strcat(form, " ");
    strcat(form, block);
    if (winning)
        strcat(form, "*");
}
static Candidates make_candidates(const Situation *s) {
    Counts counts = combine_tiles(s->hand, s->win).counts;
    int win = 0;
    while (!s->win.counts.values[win])
        ++win;
    Candidates out = {0};
    Decompositions decompositions = standard_decompositions(counts, (int)s->meld_count);
    for (size_t i = 0; i < decompositions.count; ++i) {
        Decomposition *d = &decompositions.items[i];
        char seen[5][6];
        int seen_count = 0;
        for (int winning = -1; winning < d->count; ++winning) {
            if (winning < 0) {
                if (d->pair != win)
                    continue;
            } else {
                Block b = d->sets[winning];
                if (b.sequence ? win < b.kind || win > b.kind + 2 : win != b.kind)
                    continue;
            }
            char shape[6];
            if (winning < 0)
                block_notation(d->pair, 2, false, shape);
            else
                block_name(d->sets[winning], shape);
            bool duplicate = false;
            for (int j = 0; j < seen_count; ++j)
                duplicate = duplicate || strcmp(shape, seen[j]) == 0;
            if (duplicate)
                continue;
            strcpy(seen[seen_count++], shape);
            Candidate c = {
                .kind = FORM_STANDARD, .pair = d->pair, .wait = W_TANKI, .set_count = d->count};
            memcpy(c.sets, d->sets, (size_t)d->count * sizeof(Block));
            if (winning >= 0) {
                c.sets[winning].winning = true;
                c.wait = wait_shape(c.sets[winning], win);
            }
            strcpy(c.form, "standard");
            char name[6];
            block_notation(c.pair, 2, false, name);
            append_form(c.form, name, winning < 0);
            for (int j = 0; j < c.set_count; ++j) {
                Block b = c.sets[j];
                block_name(b, name);
                append_form(c.form, name, b.winning);
                c.blocks[c.block_count++] = b;
            }
            for (size_t j = 0; j < s->meld_count; ++j) {
                char notation[7];
                block_name(s->melds[j].block, name);
                snprintf(notation, sizeof(notation), "%c%s", s->melds[j].type, name);
                append_form(c.form, notation, false);
                c.blocks[c.block_count++] = s->melds[j].block;
            }
            append_candidate(&out, c);
        }
    }
    free(decompositions.items);
    if (seven_pairs(counts, (int)s->meld_count)) {
        Candidate c = {.kind = FORM_CHIITOITSU, .wait = W_TANKI};
        strcpy(c.form, "chiitoitsu");
        for (int kind = 0; kind < 34; ++kind)
            if (counts.values[kind] == 2) {
                char name[6];
                block_notation(kind, 2, false, name);
                append_form(c.form, name, kind == win);
            }
        append_candidate(&out, c);
    }
    if (thirteen_orphans(counts, (int)s->meld_count)) {
        Candidate c = {.kind = FORM_KOKUSHI, .wait = W_THIRTEEN};
        strcpy(c.form, "kokushi");
        for (int kind = 0; kind < 34; ++kind)
            if (counts.values[kind]) {
                char name[6];
                block_notation(kind, counts.values[kind], false, name);
                append_form(c.form, name, kind == win);
                if (s->hand.counts.values[kind] != 1)
                    c.wait = W_SINGLE;
            }
        append_candidate(&out, c);
    }
    qsort(out.items, out.count, sizeof(Candidate), compare_candidates);
    for (size_t i = 0; i < out.count; ++i)
        evaluate_candidate(&out.items[i], s);
    return out;
}
static const Candidate *best_candidate(const Candidates *candidates) {
    const Candidate *best = NULL;
    for (size_t i = 0; i < candidates->count; ++i) {
        const Candidate *c = &candidates->items[i];
        if (c->base <= 0)
            continue;
        bool better = !best;
        if (best) {
            if (c->base != best->base)
                better = c->base > best->base;
            else if ((c->multiplier > 0) != (best->multiplier > 0))
                better = c->multiplier > 0;
            else if (!c->multiplier && c->han != best->han)
                better = c->han > best->han;
            else if (!c->multiplier && c->fu != best->fu)
                better = c->fu > best->fu;
            else
                better = strcmp(c->form, best->form) < 0;
        }
        if (better)
            best = c;
    }
    return best;
}
static void print_awards(FILE *file, Awards awards, const char *separator) {
    for (int i = 0; i < awards.count; ++i) {
        if (i)
            fputs(separator, file);
        fputs(awards.items[i].name, file);
    }
}
static void print_candidate(FILE *file, const Candidate *c) {
    fprintf(file, "CANDIDATE %s = %s ", c->form, wait_names[c->wait]);
    if (c->multiplier) {
        fprintf(file, "yakuman %d base %d yaku ", c->multiplier, c->base);
        print_awards(file, c->yakuman, ",");
    } else if (!c->base)
        fputs("no_yaku", file);
    else {
        fprintf(file, "han %d fu %d base %d yaku ", c->han, c->fu, c->base);
        print_awards(file, c->yaku, ",");
    }
    fputc('\n', file);
}
static void print_signed(FILE *file, int value) {
    if (value > 0)
        fprintf(file, "+%d", value);
    else
        fprintf(file, "%d", value);
}
static void count_awards(ScoreStatistics *stats, Awards awards, bool yakuman) {
    for (int i = 0; i < awards.count; ++i) {
        if (yakuman) {
            for (int j = 0; j < YAKUMAN_COUNT; ++j)
                if (strcmp(awards.items[i].name, yakuman_table[j].name) == 0)
                    ++stats->yakuman[j];
        } else {
            for (int j = 0; j < YAKU_COUNT; ++j)
                if (strcmp(awards.items[i].name, yaku_table[j].name) == 0)
                    ++stats->yaku[j];
        }
    }
}
static void process_scores(const Rule *rules, int rule_count, const Rule *const names[26]) {
    FILE *input = open_file("input/hands.txt", "r"), *output = open_file("output/scores.txt", "w"),
         *summary = open_file("output/summary.csv", "w");
    fputs("hand,han,fu,points,yaku\n", summary);
    ScoreStatistics stats = {0};
    stats.maximum_label = copy_string("-");
    char *line;
    while ((line = read_line(input))) {
        Record record = read_record(line);
        Situation s = read_situation(record, names[record.values[0][0] - 'A']);
        ++stats.hands;
        RuleStatistics *rule_stats = &stats.rules[s.rule->name - 'A'];
        ++rule_stats->hands;
        fprintf(output, "HAND %s\n", s.label);
        char error[64];
        if (check_situation(&s, error)) {
            ++stats.errors;
            fprintf(output, "ERROR %s\n", error);
            fprintf(summary, "%s,-,-,0,ERROR\n", s.label);
            free(s.melds);
            free(line);
            continue;
        }
        int waiting[34], waiting_count = waiting_tiles(s.hand, s.melds, s.meld_count, waiting);
        fputs("WAITS", output);
        bool furiten = false;
        for (int i = 0; i < waiting_count; ++i) {
            char name[3];
            tile_name(waiting[i], name);
            fprintf(output, " %s", name);
            if (s.by == 'r' && s.discards.counts.values[waiting[i]])
                furiten = true;
        }
        fputc('\n', output);
        Candidates candidates = make_candidates(&s);
        for (size_t i = 0; i < candidates.count; ++i)
            print_candidate(output, &candidates.items[i]);
        const Candidate *best = best_candidate(&candidates);
        if (furiten || !best) {
            if (furiten) {
                ++stats.furiten;
                fputs("RESULT furiten\n", output);
                fprintf(summary, "%s,-,-,0,FURITEN\n", s.label);
            } else {
                ++stats.no_yaku;
                fputs("RESULT no_yaku\n", output);
                fprintf(summary, "%s,-,-,0,NO_YAKU\n", s.label);
            }
            free(candidates.items);
            free(s.melds);
            free(line);
            continue;
        }
        const Candidate *c = best;
        ++stats.wins;
        ++stats.methods[(s.seat == 'E' ? 0 : 2) + (s.by == 't')];
        ++stats.waits[c->wait];
        ++stats.limits[c->category];
        fprintf(output, "FORM %s\nWAIT %s\n", c->form, wait_names[c->wait]);
        if (c->multiplier) {
            for (int i = 0; i < c->yakuman.count; ++i)
                fprintf(output, "YAKUMAN %s %d\n", c->yakuman.items[i].name,
                        c->yakuman.items[i].value);
            count_awards(&stats, c->yakuman, true);
            fprintf(output, "SCORE yakuman %d base %d\n", c->multiplier, c->base);
        } else {
            ++stats.han[c->han];
            ++stats.fu[c->fu];
            for (int i = 0; i < c->yaku.count; ++i)
                fprintf(output, "YAKU %s %d\n", c->yaku.items[i].name, c->yaku.items[i].value);
            count_awards(&stats, c->yaku, false);
            fprintf(output, "DORA dora %d aka %d ura %d\n", c->dora, c->aka, c->ura);
            for (int i = 0; i < c->fu_count; ++i)
                fprintf(output, "FU %s %d\n", c->fu_items[i].name, c->fu_items[i].value);
            fprintf(output, "FU total %d %d\nSCORE han %d fu %d limit %s base %d\n", c->fu_total,
                    c->fu, c->han, c->fu, category_names[c->category], c->base);
        }
        Payment payment = payments(c->base, s.seat, s.by);
        int honba = s.honba * s.rule->honba, sticks = s.sticks * 1000,
            gain = payment.points + honba + sticks;
        if (s.by == 'r')
            fprintf(output, "PAY ron %d\n", payment.ron);
        else if (s.seat == 'E')
            fprintf(output, "PAY tsumo all %d\n", payment.all);
        else
            fprintf(output, "PAY tsumo dealer %d nondealer %d\n", payment.dealer,
                    payment.nondealer);
        fprintf(output, "BONUS honba %d sticks %d\nTOTAL points %d gain %d\n", honba, sticks,
                payment.points, gain);
        int delta[4] = {0}, winner = wind_kind(s.seat) - 27;
        delta[winner] = gain;
        if (s.by == 'r')
            delta[wind_kind(s.from) - 27] = -payment.ron - honba;
        else
            for (int i = 0; i < 4; ++i)
                if (i != winner)
                    delta[i] = -(s.seat == 'E' ? payment.all
                                 : i == 0      ? payment.dealer
                                               : payment.nondealer) -
                               honba / 3;
        fputs("DELTA", output);
        for (int i = 0; i < 4; ++i) {
            fprintf(output, " %c ", "ESWN"[i]);
            print_signed(output, delta[i]);
        }
        fputc('\n', output);
        stats.points += payment.points;
        if (payment.points > stats.maximum) {
            stats.maximum = payment.points;
            free(stats.maximum_label);
            stats.maximum_label = copy_string(s.label);
        }
        ++rule_stats->wins;
        rule_stats->points += payment.points;
        if (c->multiplier) {
            fprintf(summary, "%s,Y%d,-,%d,", s.label, c->multiplier, payment.points);
            print_awards(summary, c->yakuman, ";");
        } else {
            fprintf(summary, "%s,%d,%d,%d,", s.label, c->han, c->fu, payment.points);
            print_awards(summary, c->yaku, ";");
        }
        fputc('\n', summary);
        free(candidates.items);
        free(s.melds);
        free(line);
    }
    fprintf(
        output,
        "STATS hands %d wins %d furiten %d no_yaku %d errors %d\nWINS dealer_ron %d dealer_tsumo %d nondealer_ron %d nondealer_tsumo %d\nWAIT_COUNT",
        stats.hands, stats.wins, stats.furiten, stats.no_yaku, stats.errors, stats.methods[0],
        stats.methods[1], stats.methods[2], stats.methods[3]);
    for (int i = 0; i < WAIT_COUNT; ++i)
        fprintf(output, " %s %d", wait_names[i], stats.waits[i]);
    fputc('\n', output);
    for (int i = 0; i < 256; ++i)
        if (stats.han[i])
            fprintf(output, "HAN_COUNT %d %d\n", i, stats.han[i]);
    for (int i = 0; i < 256; ++i)
        if (stats.fu[i])
            fprintf(output, "FU_COUNT %d %d\n", i, stats.fu[i]);
    for (int i = 0; i < LIMIT_COUNT; ++i)
        fprintf(output, "LIMIT %s %d\n", category_names[i], stats.limits[i]);
    for (int i = 0; i < YAKU_COUNT; ++i)
        if (stats.yaku[i])
            fprintf(output, "YAKU_COUNT %s %d\n", yaku_table[i].name, stats.yaku[i]);
    for (int i = 0; i < YAKUMAN_COUNT; ++i)
        if (stats.yakuman[i])
            fprintf(output, "YAKU_COUNT %s %d\n", yakuman_table[i].name, stats.yakuman[i]);
    fprintf(output, "POINTS total %d max %d hand %s\n", stats.points, stats.maximum,
            stats.maximum_label);
    for (int i = 0; i < rule_count; ++i) {
        RuleStatistics *s = &stats.rules[rules[i].name - 'A'];
        fprintf(output, "RULE %c hands %d wins %d points %d\n", rules[i].name, s->hands, s->wins,
                s->points);
    }
    free(stats.maximum_label);
    fclose(input);
    fclose(output);
    fclose(summary);
}
static void process_waits(const Rule *const names[26]) {
    FILE *input = open_file("input/waits.txt", "r"), *output = open_file("output/waits.txt", "w");
    int hands = 0, errors = 0, tenpai = 0, furiten_count = 0, histogram[7] = {0};
    char *line;
    while ((line = read_line(input))) {
        Record record = read_record(line);
        char **a = record.values;
        const Rule *rule = names[a[0][0] - 'A'];
        ++hands;
        fprintf(output, "HAND %s\n", record.label);
        Tiles hand, dora, discards, visible;
        bool notation = parse_tiles(a[1], false, &hand), valid = parse_tiles(a[5], false, &dora);
        notation = notation && valid;
        valid = parse_tiles(a[6], true, &discards);
        notation = notation && valid;
        valid = parse_tiles(a[7], true, &visible);
        notation = notation && valid;
        Tiles all = combine_tiles(combine_tiles(combine_tiles(hand, dora), discards), visible);
        char error[64];
        bool failed = false;
        if (!notation) {
            strcpy(error, "bad tile notation");
            failed = true;
        } else if (hand.size != 13) {
            strcpy(error, "wrong tile count");
            failed = true;
        } else
            failed = check_copies(all, rule, error);
        if (failed) {
            ++errors;
            fprintf(output, "ERROR %s\n", error);
            free(line);
            continue;
        }
        Shanten memo = {0};
        ShantenNumbers numbers = shanten_numbers(&memo, hand.counts);
        int minimum = minimum_shanten(numbers);
        ++histogram[minimum];
        fprintf(output, "SHANTEN standard %d chiitoitsu %d kokushi %d\n", numbers.standard,
                numbers.chiitoitsu, numbers.kokushi);
        int accepted[34], accepted_count = 0, remaining = 0;
        for (int kind = 0; kind < 34; ++kind)
            if (hand.counts.values[kind] < 4) {
                Counts counts = hand.counts;
                ++counts.values[kind];
                if (minimum_shanten(shanten_numbers(&memo, counts)) < minimum) {
                    accepted[accepted_count++] = kind;
                    remaining += 4 - all.counts.values[kind];
                }
            }
        shanten_free(&memo);
        if (minimum > 0) {
            fprintf(output, "ACCEPT kinds %d tiles %d", accepted_count, remaining);
            for (int i = 0; i < accepted_count; ++i) {
                char name[3];
                tile_name(accepted[i], name);
                fprintf(output, " %s:%d", name, 4 - all.counts.values[accepted[i]]);
            }
            fputc('\n', output);
            free(line);
            continue;
        }
        ++tenpai;
        bool furiten = false;
        for (int i = 0; i < accepted_count; ++i)
            furiten = furiten || discards.counts.values[accepted[i]] > 0;
        if (furiten)
            ++furiten_count;
        fprintf(output, "TENPAI kinds %d tiles %d furiten %s\n", accepted_count, remaining,
                furiten ? "yes" : "no");
        int best_points[2] = {0}, best_tiles[2] = {-1, -1};
        for (int i = 0; i < accepted_count; ++i) {
            int kind = accepted[i];
            char name[3], points[2][32];
            tile_name(kind, name);
            for (int method = 0; method < 2; ++method) {
                if (method == 0 && furiten) {
                    strcpy(points[method], "furiten");
                    continue;
                }
                Situation s = {.rule = rule,
                               .hand = hand,
                               .win = add_kind((Tiles){0}, kind),
                               .dora = dora,
                               .seat = a[2][0],
                               .round = a[3][0],
                               .by = method == 0 ? 'r' : 't'};
                s.flags[F_RIICHI] = strcmp(a[4], "yes") == 0;
                Candidates candidates = make_candidates(&s);
                const Candidate *best = best_candidate(&candidates);
                if (!best)
                    strcpy(points[method], "no_yaku");
                else {
                    int value = payments(best->base, s.seat, s.by).points;
                    snprintf(points[method], sizeof(points[method]), "%d", value);
                    if (value > best_points[method]) {
                        best_points[method] = value;
                        best_tiles[method] = kind;
                    }
                }
                free(candidates.items);
            }
            fprintf(output, "WAIT %s left %d ron %s tsumo %s\n", name, 4 - all.counts.values[kind],
                    points[0], points[1]);
        }
        fputs("BEST", output);
        for (int method = 0; method < 2; ++method) {
            fprintf(output, " %s ", method == 0 ? "ron" : "tsumo");
            if (best_tiles[method] < 0)
                fputs("none", output);
            else {
                char name[3];
                tile_name(best_tiles[method], name);
                fprintf(output, "%s %d", name, best_points[method]);
            }
        }
        fputc('\n', output);
        free(line);
    }
    fprintf(output, "STATS hands %d errors %d tenpai %d furiten %d\n", hands, errors, tenpai,
            furiten_count);
    for (int i = 0; i <= 6; ++i)
        fprintf(output, "SHANTEN_COUNT %d %d\n", i, histogram[i]);
    fclose(input);
    fclose(output);
}
int main(void) {
    Rule rules[26] = {0};
    const Rule *names[26] = {0};
    int rule_count = 0;
    FILE *input = open_file("input/rules.txt", "r");
    char *line;
    while ((line = read_line(input))) {
        Record record = read_record(line);
        char **a = record.values;
        Rule *rule = &rules[rule_count++];
        *rule = (Rule){.name = record.label[0],
                       .open_tanyao = strcmp(a[0], "yes") == 0,
                       .red = strcmp(a[1], "yes") == 0,
                       .double_yakuman = strcmp(a[2], "yes") == 0,
                       .kazoe = strcmp(a[3], "yes") == 0,
                       .kiriage = strcmp(a[4], "yes") == 0,
                       .honba = atoi(a[5])};
        names[rule->name - 'A'] = rule;
        free(line);
    }
    fclose(input);
    if (mkdir("output", 0777) != 0 && errno != EEXIST) {
        perror("output");
        return EXIT_FAILURE;
    }
    process_scores(rules, rule_count, names);
    process_waits(names);
    return EXIT_SUCCESS;
}
