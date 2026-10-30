#include "scrabble.h"

typedef struct {
    char items[64][64];
    int count;
} Tokens;
static Tokens split(const char *text) {
    Tokens out = {0};
    while (*text) {
        while (*text == ' ')
            ++text;
        if (!*text)
            break;
        int p = 0;
        while (*text && *text != ' ')
            out.items[out.count][p++] = *text++;
        out.items[out.count++][p] = 0;
    }
    return out;
}
void add_line(Lines *out, const char *format, ...) {
    va_list args, copy;
    va_start(args, format);
    va_copy(copy, args);
    int n = vsnprintf(NULL, 0, format, copy);
    va_end(copy);
    char *text = malloc((size_t)n + 1);
    vsnprintf(text, (size_t)n + 1, format, args);
    va_end(args);
    Lines_append(out, text);
}
typedef struct {
    char *data;
    size_t count, capacity;
} Text;
static void text_add(Text *out, const char *format, ...) {
    va_list args, copy;
    va_start(args, format);
    va_copy(copy, args);
    size_t n = (size_t)vsnprintf(NULL, 0, format, copy);
    va_end(copy);
    if (out->count + n + 1 > out->capacity) {
        out->capacity = out->count + n + 128;
        out->data = realloc(out->data, out->capacity);
    }
    vsnprintf(out->data + out->count, n + 1, format, args);
    out->count += n;
    va_end(args);
}
static void finish(Lines *out, Text *text) {
    Lines_append(out, text->data);
    *text = (Text){0};
}
static void extend_lines(Lines *out, Lines source) {
    for (size_t i = 0; i < source.count; ++i)
        Lines_append(out, source.items[i]);
    free(source.items);
}
static void free_lines(Lines *lines) {
    for (size_t i = 0; i < lines->count; ++i)
        free(lines->items[i]);
    free(lines->items);
    *lines = (Lines){0};
}
DEFINE_VECTOR(Blocks, Lines)
typedef struct {
    Move move;
    int score;
    Placement tiles;
    char words[448], leave[8];
    int value;
} Evaluated;
DEFINE_VECTOR(Evaluations, Evaluated)
typedef enum { SCORE, TILES, EQUITY } Strategy;
typedef struct {
    int jobs, errors, moves, bingos;
} TopnTotals;
typedef struct {
    int jobs, errors, moves, valid, invalid, loss;
} ValidationTotals;
typedef struct {
    int games, duplicates, errors, turns, rounds, plays, exchanges, passes, bingos;
} GameTotals;
typedef struct {
    Counts values, counts, weights;
    Trie trie;
    Blocks jobs;
    Lines dictionary_lines;
    TopnTotals topn;
    ValidationTotals validation;
    GameTotals game;
} Program;
static bool valid_name(const char *text) {
    size_t n = strlen(text);
    if (n == 0 || n > 20)
        return false;
    for (const char *p = text; *p; ++p)
        if (!lower(*p) && !(*p >= '0' && *p <= '9') && *p != '_')
            return false;
    return true;
}
static bool valid_number(const char *text, int minimum, int maximum) {
    if (!*text || (text[0] == '0' && text[1]))
        return false;
    int64_t number = 0;
    for (const char *p = text; *p; ++p) {
        if (*p < '0' || *p > '9')
            return false;
        number = number * 10 + *p - '0';
        if (number > maximum)
            return false;
    }
    return number >= minimum;
}
static bool valid_rack(const char *text) {
    size_t n = strlen(text);
    if (n < 1 || n > 7)
        return false;
    for (const char *p = text; *p; ++p)
        if (!upper(*p) && *p != '?')
            return false;
    return true;
}
static bool valid_strategy(const char *text) {
    return !strcmp(text, "score") || !strcmp(text, "tiles") || !strcmp(text, "equity");
}
static Strategy strategy(const char *text) {
    return !strcmp(text, "tiles") ? TILES : !strcmp(text, "equity") ? EQUITY : SCORE;
}
static const char *collection(const char *text) {
    static char buffers[64][201];
    static unsigned index;
    char *out = buffers[index++ % 64];
    int counts[128] = {0}, n = 0;
    while (*text)
        ++counts[(unsigned char)*text++];
    for (int c = 0; c < 128; ++c)
        for (int i = 0; i < counts[c]; ++i)
            out[n++] = (char)c;
    if (n == 0)
        out[n++] = '-';
    out[n] = 0;
    return out;
}
static void remove_tiles(const char *rack, const char *removed, char *out) {
    int counts[128] = {0};
    while (*rack)
        ++counts[(unsigned char)*rack++];
    while (*removed)
        --counts[(unsigned char)*removed++];
    for (int c = 0; c < 128; ++c)
        for (int i = 0; i < counts[c]; ++i)
            *out++ = (char)c;
    *out = 0;
}
static const char *notation(const Evaluated *move) {
    static char buffers[16][64];
    static unsigned index;
    char *out = buffers[index++ % 16];
    snprintf(out, 64, "%s %s", position(&move->move), move->move.word);
    return out;
}
static int standard_compare(const void *left, const void *right) {
    const Evaluated *a = left, *b = right;
    if (a->score != b->score)
        return a->score > b->score ? -1 : 1;
    if (a->move.row != b->move.row)
        return a->move.row - b->move.row;
    if (a->move.column != b->move.column)
        return a->move.column - b->move.column;
    if (a->move.direction != b->move.direction)
        return a->move.direction - b->move.direction;
    return strcmp(a->move.word, b->move.word);
}
static bool strategy_before(const Evaluated *a, const Evaluated *b, Strategy order) {
    if (order == TILES && a->tiles.count != b->tiles.count)
        return a->tiles.count > b->tiles.count;
    if (order == EQUITY && a->score + a->value != b->score + b->value)
        return a->score + a->value > b->score + b->value;
    return standard_compare(a, b) < 0;
}
static Strategy current_order;
static int strategy_compare(const void *left, const void *right) {
    const Evaluated *a = left, *b = right;
    return strategy_before(a, b, current_order) ? -1 : strategy_before(b, a, current_order) ? 1 : 0;
}
static int choose(const Evaluations *moves, Strategy order) {
    int best = 0;
    for (size_t i = 1; i < moves->count; ++i)
        if (strategy_before(&moves->items[i], &moves->items[best], order))
            best = (int)i;
    return best;
}
static int tile_compare(const void *left, const void *right) {
    const Tile *a = left, *b = right;
    if (a->row != b->row)
        return a->row - b->row;
    if (a->column != b->column)
        return a->column - b->column;
    return (unsigned char)a->letter - (unsigned char)b->letter;
}
static bool same_placement(Placement a, Placement b) {
    if (a.count != b.count)
        return false;
    qsort(a.items, (size_t)a.count, sizeof *a.items, tile_compare);
    qsort(b.items, (size_t)b.count, sizeof *b.items, tile_compare);
    for (int i = 0; i < a.count; ++i)
        if (tile_compare(&a.items[i], &b.items[i]))
            return false;
    return true;
}
static int board_start(const Tokens *header) { return !strcmp(header->items[0], "TOPN") ? 3 : 2; }
static int board_rows(const Lines *job) {
    Tokens header = split(job->items[0]);
    int start = board_start(&header), count = 0;
    for (size_t i = (size_t)start; i < job->count && strncmp(job->items[i], "MOVE", 4); ++i)
        ++count;
    return count;
}
static Board from_job(const Lines *job) {
    Tokens header = split(job->items[0]);
    int start = board_start(&header);
    Board out;
    for (int r = 0; r < 15; ++r)
        memcpy(out.cells[r], job->items[start + r], 15);
    return out;
}
static void used_tiles(const Board *board, Counts out) {
    memset(out, 0, sizeof(Counts));
    BoardTiles tiles = board_tiles(board);
    for (int i = 0; i < tiles.count; ++i)
        ++out[tile_index(tiles.items[i].letter)];
}
static bool tile_error(const Program *p, const Board *board, const char *rack, char *reason) {
    Counts used;
    used_tiles(board, used);
    while (*rack)
        ++used[tile_index(*rack++)];
    for (int i = 0; i < 27; ++i)
        if (used[i] > p->counts[i]) {
            snprintf(reason, 128, "too many %c", tile_order[i]);
            return true;
        }
    return false;
}
static void unseen(const Program *p, const Board *board, const char *rack, char out[201]) {
    Counts used;
    used_tiles(board, used);
    while (*rack)
        ++used[tile_index(*rack++)];
    int count = 0;
    for (int tile = 0; tile < 27; ++tile)
        for (int i = 0; i < p->counts[tile] - used[tile]; ++i)
            out[count++] = tile_order[tile];
    out[count] = 0;
}
static bool board_error(const Program *p, const Lines *job, const char *rack, char *reason) {
    int count = board_rows(job);
    if (count != 15) {
        snprintf(reason, 128, "board rows %d", count);
        return true;
    }
    Tokens header = split(job->items[0]);
    int start = board_start(&header);
    for (int r = 0; r < 15; ++r) {
        const char *row = job->items[start + r];
        bool bad = strlen(row) != 15;
        for (const char *c = row; *c; ++c)
            if (*c != '.' && !upper(*c) && !lower(*c))
                bad = true;
        if (bad) {
            snprintf(reason, 128, "bad board row %d", r + 1);
            return true;
        }
    }
    Board board = from_job(job);
    if (tile_error(p, &board, rack, reason))
        return true;
    if (board_tiles(&board).count > 0 && board.cells[7][7] == '.') {
        strcpy(reason, "center empty");
        return true;
    }
    if (!connected(&board)) {
        strcpy(reason, "disconnected");
        return true;
    }
    Words words = board_words(&board);
    for (int i = 0; i < words.count; ++i) {
        char capital[16];
        uppercase(words.items[i].word, capital);
        if (!trie_contains(&p->trie, capital)) {
            snprintf(reason, 128, "unknown word %s at %s", words.items[i].word,
                     position(&words.items[i]));
            return true;
        }
    }
    return false;
}
static bool job_error(const Program *p, const Lines *job, const Lines *seen, char *reason) {
    Tokens header = split(job->items[0]);
    const char *kind = header.items[0], *name = header.items[1];
    if (!valid_name(name)) {
        strcpy(reason, "bad name");
        return true;
    }
    for (size_t i = 0; i < seen->count; ++i)
        if (!strcmp(name, seen->items[i])) {
            strcpy(reason, "duplicate name");
            return true;
        }
    if (!strcmp(kind, "TOPN")) {
        if (!valid_number(header.items[2], 1, 99)) {
            strcpy(reason, "bad count");
            return true;
        }
        if (!valid_strategy(header.items[3])) {
            strcpy(reason, "bad order");
            return true;
        }
        Tokens row = split(job->items[1]);
        if (!valid_rack(row.items[1])) {
            strcpy(reason, "bad rack");
            return true;
        }
        return board_error(p, job, row.items[1], reason);
    }
    if (!strcmp(kind, "VALIDATE"))
        return board_error(p, job, "", reason);
    if (!valid_number(header.items[2], 1, 2147483646)) {
        strcpy(reason, "bad seed");
        return true;
    }
    if (job->count - 1 < 2 || job->count - 1 > 4) {
        snprintf(reason, 128, "bad player count %zu", job->count - 1);
        return true;
    }
    char names[4][21];
    for (size_t i = 1; i < job->count; ++i) {
        Tokens row = split(job->items[i]);
        if (!valid_name(row.items[1]) || !valid_strategy(row.items[2]) ||
            (!strcmp(kind, "GAME") && !valid_number(row.items[3], 0, 99))) {
            snprintf(reason, 128, "bad player %zu", i);
            return true;
        }
        for (size_t j = 0; j + 1 < i; ++j)
            if (!strcmp(names[j], row.items[1])) {
                snprintf(reason, 128, "duplicate player %zu", i);
                return true;
            }
        strcpy(names[i - 1], row.items[1]);
    }
    return false;
}
static int leave_value(const Program *p, const char *rack) {
    Counts counts = {0};
    int total = 0, vowels = 0, consonants = 0, duplicates = 0;
    for (const char *c = rack; *c; ++c) {
        int tile = tile_index(*c);
        ++counts[tile];
        total += p->weights[tile];
        if (*c != '?') {
            if (strchr("AEIOU", *c))
                ++vowels;
            else
                ++consonants;
        }
    }
    for (int i = 0; i < 26; ++i)
        if (counts[i] > 1)
            duplicates += counts[i] - 1;
    int imbalance = abs(vowels - consonants) - 1;
    if (imbalance < 0)
        imbalance = 0;
    return total - 4 * duplicates - 3 * imbalance;
}
static void best_leave(const Program *p, const char *rack, char out[8]) {
    size_t length = strlen(rack);
    out[0] = 0;
    int best_value = 0;
    for (unsigned mask = 0; mask < (1u << length) - 1; ++mask) {
        char candidate[8];
        int n = 0;
        for (size_t i = 0; i < length; ++i)
            if (mask & (1u << i))
                candidate[n++] = rack[i];
        candidate[n] = 0;
        const char *sorted = collection(candidate);
        if (n == 0)
            candidate[0] = 0;
        else
            strcpy(candidate, sorted);
        int value = leave_value(p, candidate);
        size_t old_length = strlen(out);
        if (value > best_value ||
            (value == best_value &&
             ((size_t)n > old_length || ((size_t)n == old_length && strcmp(candidate, out) < 0)))) {
            strcpy(out, candidate);
            best_value = value;
        }
    }
}
static Evaluated evaluate(const Program *p, const Board *board, const char *rack,
                          const Move *move) {
    Scored scored = score_move(board, move, p->values);
    Evaluated out = {0};
    out.move = *move;
    out.score = scored.score;
    out.tiles = scored.tiles;
    char removed[16];
    for (int i = 0; i < scored.tiles.count; ++i)
        removed[i] = upper(scored.tiles.items[i].letter) ? scored.tiles.items[i].letter : '?';
    removed[scored.tiles.count] = 0;
    remove_tiles(rack, removed, out.leave);
    out.value = leave_value(p, out.leave);
    size_t offset = 0;
    for (int i = 0; i < scored.count; ++i) {
        offset += (size_t)snprintf(out.words + offset, sizeof out.words - offset, "%s%s:%d",
                                   i ? "," : "", scored.words[i].word.word, scored.words[i].score);
    }
    return out;
}
static Evaluations legal_moves(const Program *p, const Board *board, const char *rack) {
    Moves generated = generate(board, rack, &p->trie);
    Evaluations out = {0};
    for (size_t i = 0; i < generated.count; ++i)
        Evaluations_append(&out, evaluate(p, board, rack, &generated.items[i]));
    free(generated.items);
    if (out.count > 1)
        qsort(out.items, out.count, sizeof *out.items, standard_compare);
    return out;
}
static void append_board(Lines *out, const Board *board) {
    Words words = board_words(board);
    BoardTiles tiles = board_tiles(board);
    const char *longest = "-";
    size_t length = 0;
    int blanks = 0, premium_counts[128] = {0};
    for (int i = 0; i < words.count; ++i) {
        size_t n = strlen(words.items[i].word);
        if (n > length) {
            length = n;
            longest = words.items[i].word;
        }
    }
    for (int i = 0; i < tiles.count; ++i) {
        Tile tile = tiles.items[i];
        blanks += lower(tile.letter);
        ++premium_counts[(unsigned char)premiums[tile.row][tile.column]];
    }
    add_line(out,
             "position tiles=%d words=%d longest=%s blanks=%d premiums=TW:%d,DW:%d,TL:%d,DL:%d",
             tiles.count, words.count, longest, blanks, premium_counts['#'], premium_counts['*'],
             premium_counts['^'], premium_counts['+']);
    extend_lines(out, display(board));
}
static int anagram_compare(const void *left, const void *right) {
    const char *a = *(char *const *)left, *b = *(char *const *)right;
    size_t x = strlen(a), y = strlen(b);
    return x != y ? (x > y ? -1 : 1) : strcmp(a, b);
}
static Lines topn(Program *p, const Lines *job) {
    Tokens header = split(job->items[0]), rack_line = split(job->items[1]);
    const char *rack = rack_line.items[1];
    int count = atoi(header.items[2]);
    Board board = from_job(job);
    Evaluations moves = legal_moves(p, &board, rack), shown = {0};
    for (size_t i = 0; i < moves.count; ++i)
        Evaluations_append(&shown, moves.items[i]);
    current_order = strategy(header.items[3]);
    if (shown.count > 1)
        qsort(shown.items, shown.count, sizeof *shown.items, strategy_compare);
    if (shown.count > (size_t)count)
        shown.count = (size_t)count;
    char unknown[201];
    unseen(p, &board, rack, unknown);
    Anchors anchor_squares = anchors(&board);
    Board swapped = transpose(&board);
    Checks checks[2] = {cross_checks(&board, &p->trie), cross_checks(&swapped, &p->trie)};
    int check_counts[2][3] = {{0}};
    for (int direction = 0; direction < 2; ++direction)
        for (int r = 0; r < 15; ++r)
            for (int c = 0; c < 15; ++c)
                if (checks[direction].checked[r][c]) {
                    ++check_counts[direction][0];
                    check_counts[direction][1] += checks[direction].mask[r][c] == 0;
                    for (int letter = 0; letter < 26; ++letter)
                        check_counts[direction][2] += (checks[direction].mask[r][c] >> letter) & 1;
                }
    int vowels = 0, consonants = 0, blanks = 0;
    for (const char *c = rack; *c; ++c) {
        if (*c == '?')
            ++blanks;
        else if (strchr("AEIOU", *c))
            ++vowels;
        else
            ++consonants;
    }
    int across = 0, bingos = 0, blank_moves = 0, best_scores[8];
    for (int i = 0; i < 8; ++i)
        best_scores[i] = -1;
    for (size_t i = 0; i < moves.count; ++i) {
        const Evaluated *m = &moves.items[i];
        across += m->move.direction == 0;
        bingos += m->tiles.count == 7;
        bool blank = false;
        for (int j = 0; j < m->tiles.count; ++j)
            if (lower(m->tiles.items[j].letter))
                blank = true;
        blank_moves += blank;
        if (m->score > best_scores[m->tiles.count])
            best_scores[m->tiles.count] = m->score;
    }
    Lines out = {0};
    add_line(&out, "TOPN %s n=%d order=%s rack=%s", header.items[1], count, header.items[3],
             collection(rack));
    add_line(&out, "board tiles=%d anchors=%d", board_tiles(&board).count, anchor_squares.count);
    add_line(&out, "unseen count=%zu tiles=%s", strlen(unknown), collection(unknown));
    add_line(&out, "rack vowels=%d consonants=%d blanks=%d value=%d", vowels, consonants, blanks,
             points(rack, p->values));
    add_line(&out, "checks across=%d,%d,%d down=%d,%d,%d", check_counts[0][0], check_counts[0][1],
             check_counts[0][2], check_counts[1][0], check_counts[1][1], check_counts[1][2]);
    add_line(&out, "moves total=%zu across=%d down=%zu bingos=%d blanks=%d", moves.count, across,
             moves.count - (size_t)across, bingos, blank_moves);
    Text text = {0};
    text_add(&text, "best_by_tiles");
    for (int i = 1; i <= 7; ++i) {
        if (best_scores[i] < 0)
            text_add(&text, " %d=-", i);
        else
            text_add(&text, " %d=%d", i, best_scores[i]);
    }
    finish(&out, &text);
    char keep[8];
    best_leave(p, rack, keep);
    add_line(&out, "exchange keep=%s value=%d", collection(keep), leave_value(p, keep));
    Lines anagrams = trie_anagrams(&p->trie, rack);
    if (anagrams.count > 1)
        qsort(anagrams.items, anagrams.count, sizeof *anagrams.items, anagram_compare);
    text_add(&text, "anagrams total=%zu top=", anagrams.count);
    if (anagrams.count == 0)
        text_add(&text, "-");
    for (size_t i = 0; i < anagrams.count && i < 10; ++i)
        text_add(&text, "%s%s", i ? "," : "", anagrams.items[i]);
    finish(&out, &text);
    free_lines(&anagrams);
    Words words = board_words(&board);
    for (int i = 0; i < words.count; ++i) {
        Move *word = &words.items[i];
        size_t length = strlen(word->word);
        if (length < 3)
            continue;
        char capital[16], front[27] = {0}, back[27] = {0}, candidate[17];
        uppercase(word->word, capital);
        int nf = 0, nb = 0;
        for (int letter = 0; letter < 26; ++letter) {
            candidate[0] = (char)('A' + letter);
            strcpy(candidate + 1, capital);
            if (trie_contains(&p->trie, candidate))
                front[nf++] = (char)('A' + letter);
            strcpy(candidate, capital);
            candidate[length] = (char)('A' + letter);
            candidate[length + 1] = 0;
            if (trie_contains(&p->trie, candidate))
                back[nb++] = (char)('A' + letter);
        }
        if (nf || nb)
            add_line(&out, "hook %s %s front=%s back=%s", position(word), word->word,
                     nf ? front : "-", nb ? back : "-");
    }
    bool endgame = strlen(unknown) >= 1 && strlen(unknown) <= 7 && shown.count > 0;
    int nets[99];
    if (endgame) {
        int best = 0;
        for (size_t i = 0; i < shown.count; ++i) {
            Board after = apply_tiles(&board, &shown.items[i].tiles);
            Evaluations replies = legal_moves(p, &after, unknown);
            nets[i] = shown.items[i].score - (replies.count ? replies.items[0].score : 0);
            free(replies.items);
            if (i > 0 && nets[i] > nets[best])
                best = (int)i;
        }
        add_line(&out, "endgame opponent=%s best=%d net=%d", collection(unknown), best + 1,
                 nets[best]);
    }
    for (size_t i = 0; i < shown.count; ++i) {
        const Evaluated *m = &shown.items[i];
        text_add(&text, "%zu %s score=%d tiles=%d leave=%s value=%d", i + 1, notation(m), m->score,
                 m->tiles.count, collection(m->leave), m->value);
        if (endgame)
            text_add(&text, " net=%d", nets[i]);
        text_add(&text, " words=%s", m->words);
        finish(&out, &text);
    }
    p->topn.moves += (int)moves.count;
    p->topn.bingos += bingos;
    free(shown.items);
    free(moves.items);
    return out;
}
static bool record_error(const Program *p, const Board *board, const Tokens *row, char reason[128],
                         Move *move, bool *has_move) {
    *has_move = false;
    const char *player = row->items[1], *rack = row->items[2], *action = row->items[3];
    if (!valid_name(player)) {
        strcpy(reason, "bad player");
        return true;
    }
    if (!valid_rack(rack)) {
        strcpy(reason, "bad rack");
        return true;
    }
    if (tile_error(p, board, rack, reason))
        return true;
    if (row->count == 4 && !strcmp(action, "PASS"))
        return false;
    if (!strcmp(action, "EXCHANGE")) {
        const char *returned = row->items[4];
        if (!valid_rack(returned)) {
            strcpy(reason, "bad exchange");
            return true;
        }
        Counts available = {0}, requested = {0};
        for (const char *c = rack; *c; ++c)
            ++available[tile_index(*c)];
        for (const char *c = returned; *c; ++c)
            ++requested[tile_index(*c)];
        for (const char *c = returned; *c; ++c)
            if (requested[tile_index(*c)] > available[tile_index(*c)]) {
                snprintf(reason, 128, "rack lacks %c", *c);
                return true;
            }
        return false;
    }
    if (!parse_position(action, move)) {
        strcpy(reason, "bad position");
        return true;
    }
    const char *word = row->items[4];
    size_t length = strlen(word);
    bool bad = length < 2 || length > 15;
    for (const char *c = word; *c; ++c)
        if (!upper(*c) && !lower(*c))
            bad = true;
    if (bad) {
        strcpy(reason, "bad word");
        return true;
    }
    strcpy(move->word, word);
    Placement cells = squares(move);
    for (int i = 0; i < cells.count; ++i)
        if (!inside(cells.items[i].row, cells.items[i].column)) {
            strcpy(reason, "off board");
            return true;
        }
    for (int i = 0; i < cells.count; ++i) {
        Tile tile = cells.items[i];
        if (board->cells[tile.row][tile.column] != '.' &&
            board->cells[tile.row][tile.column] != tile.letter) {
            snprintf(reason, 128, "mismatch at %s", square_name(tile.row, tile.column));
            return true;
        }
    }
    int dr = move->direction, dc = 1 - move->direction,
        boundary[2][2] = {{move->row - dr, move->column - dc},
                          {move->row + dr * (int)length, move->column + dc * (int)length}};
    for (int i = 0; i < 2; ++i)
        if (inside(boundary[i][0], boundary[i][1]) &&
            board->cells[boundary[i][0]][boundary[i][1]] != '.') {
            strcpy(reason, "not whole word");
            return true;
        }
    Placement tiles = placement(board, move);
    if (tiles.count == 0) {
        strcpy(reason, "no new tiles");
        return true;
    }
    Counts available = {0};
    for (const char *c = rack; *c; ++c)
        ++available[tile_index(*c)];
    for (int i = 0; i < tiles.count; ++i) {
        int tile = tile_index(tiles.items[i].letter);
        if (!available[tile]) {
            snprintf(reason, 128, "rack lacks %c", tile_order[tile]);
            return true;
        }
        --available[tile];
    }
    if (board_tiles(board).count == 0) {
        bool center = false;
        for (int i = 0; i < tiles.count; ++i)
            if (tiles.items[i].row == 7 && tiles.items[i].column == 7)
                center = true;
        if (!center) {
            strcpy(reason, "center not covered");
            return true;
        }
    } else {
        bool connected_to_board = false;
        for (int i = 0; i < tiles.count; ++i) {
            int adjacent[4][2], n = neighbors(tiles.items[i].row, tiles.items[i].column, adjacent);
            for (int j = 0; j < n; ++j)
                if (board->cells[adjacent[j][0]][adjacent[j][1]] != '.')
                    connected_to_board = true;
        }
        if (!connected_to_board) {
            strcpy(reason, "not connected");
            return true;
        }
    }
    Words crosses = cross_words(board, move);
    for (int i = -1; i < crosses.count; ++i) {
        Move formed = i < 0 ? *move : crosses.items[i];
        char capital[16];
        uppercase(formed.word, capital);
        if (!trie_contains(&p->trie, capital)) {
            snprintf(reason, 128, "unknown word %s at %s", formed.word, position(&formed));
            return true;
        }
    }
    *has_move = true;
    return false;
}
static Lines validate(Program *p, const Lines *job) {
    Tokens header = split(job->items[0]);
    Lines out = {0};
    add_line(&out, "VALIDATE %s", header.items[1]);
    Board board = from_job(job);
    typedef struct {
        char name[21];
        int moves, valid, score, loss;
    } Player;
    Player players[50] = {0};
    int player_count = 0, valid = 0, invalid = 0, score = 0, best_total = 0, loss = 0;
    for (size_t i = 17; i < job->count; ++i) {
        Tokens row = split(job->items[i]);
        char reason[128] = {0};
        Move move;
        bool has_move = false;
        bool bad = record_error(p, &board, &row, reason, &move, &has_move);
        int player = -1;
        if (strcmp(reason, "bad player")) {
            for (int j = 0; j < player_count; ++j)
                if (!strcmp(players[j].name, row.items[1]))
                    player = j;
            if (player < 0) {
                player = player_count++;
                strcpy(players[player].name, row.items[1]);
            }
            ++players[player].moves;
        }
        Text text = {0};
        text_add(&text, "move %zu %s", i - 16, row.items[1]);
        for (int j = 3; j < row.count; ++j)
            text_add(&text, " %s", row.items[j]);
        if (bad) {
            text_add(&text, " invalid %s", reason);
            finish(&out, &text);
            ++invalid;
            continue;
        }
        Evaluations legal = legal_moves(p, &board, row.items[2]);
        int best = legal.count ? legal.items[0].score : 0, earned = 0, rank = 0;
        Evaluated played = {0};
        if (has_move) {
            played = evaluate(p, &board, row.items[2], &move);
            earned = played.score;
            for (size_t j = 0; j < legal.count; ++j)
                if (same_placement(legal.items[j].tiles, played.tiles)) {
                    rank = (int)j + 1;
                    break;
                }
        }
        Player *statistics = &players[player];
        ++statistics->valid;
        statistics->score += earned;
        statistics->loss += best - earned;
        ++valid;
        score += earned;
        best_total += best;
        loss += best - earned;
        if (has_move) {
            text_add(&text, " score=%d total=%d tiles=%d rank=%d/%zu best=%d words=%s", earned,
                     statistics->score, played.tiles.count, rank, legal.count, best, played.words);
            board = apply_tiles(&board, &played.tiles);
        } else
            text_add(&text, " score=0 total=%d moves=%zu best=%d", statistics->score, legal.count,
                     best);
        finish(&out, &text);
        free(legal.items);
    }
    for (int i = 0; i < player_count; ++i)
        add_line(&out, "player %s moves=%d valid=%d score=%d loss=%d", players[i].name,
                 players[i].moves, players[i].valid, players[i].score, players[i].loss);
    add_line(&out, "total valid=%d invalid=%d score=%d best=%d loss=%d", valid, invalid, score,
             best_total, loss);
    append_board(&out, &board);
    p->validation.moves += (int)job->count - 17;
    p->validation.valid += valid;
    p->validation.invalid += invalid;
    p->validation.loss += loss;
    return out;
}
typedef struct {
    char name[21], strategy_name[7], rack[8];
    Strategy strategy;
    int threshold, score, plays, bingos, exchanges, passes, top, loss;
} GamePlayer;
static Lines ordinary_game(Program *p, const Lines *job) {
    Tokens header = split(job->items[0]);
    Minstd random = {strtoll(header.items[2], NULL, 10)};
    Bag bag = make_bag(p->counts, &random);
    Board board = empty_board();
    GamePlayer players[4] = {0};
    int count = (int)job->count - 1;
    Lines out = {0};
    add_line(&out, "GAME %s seed=%s players=%d", header.items[1], header.items[2], count);
    for (int i = 0; i < count; ++i) {
        Tokens row = split(job->items[i + 1]);
        GamePlayer *player = &players[i];
        strcpy(player->name, row.items[1]);
        strcpy(player->strategy_name, row.items[2]);
        player->strategy = strategy(row.items[2]);
        player->threshold = atoi(row.items[3]);
        draw(&bag, 7, player->rack);
        add_line(&out, "player %d %s strategy=%s threshold=%d", i + 1, player->name,
                 player->strategy_name, player->threshold);
    }
    int turn = 0, consecutive = 0, outgoing = -1, highlight_turn = 0, highlight_player = 0;
    Evaluated highlight = {0};
    for (;;) {
        int index = turn % count;
        GamePlayer *player = &players[index];
        ++turn;
        char rack[8];
        strcpy(rack, player->rack);
        Evaluations legal = legal_moves(p, &board, rack);
        int chosen = legal.count ? choose(&legal, player->strategy) : -1;
        Evaluated candidate = {0};
        if (chosen >= 0)
            candidate = legal.items[chosen];
        Text text = {0};
        text_add(&text, "turn %d %s rack=%s moves=%zu", turn, player->name, collection(rack),
                 legal.count);
        if (chosen >= 0 && !(candidate.score < player->threshold && bag.count >= 7)) {
            board = apply_tiles(&board, &candidate.tiles);
            player->score += candidate.score;
            char drawn[8];
            draw(&bag, 7 - (int)strlen(candidate.leave), drawn);
            snprintf(player->rack, sizeof player->rack, "%s%s", candidate.leave, drawn);
            ++player->plays;
            player->bingos += candidate.tiles.count == 7;
            if (candidate.score > player->top)
                player->top = candidate.score;
            player->loss += legal.items[0].score - candidate.score;
            consecutive = 0;
            if (highlight_turn == 0 || candidate.score > highlight.score) {
                highlight_turn = turn;
                highlight_player = index;
                highlight = candidate;
            }
            text_add(&text, " best=%d play %s score=%d total=%d draw=%s bag=%d",
                     legal.items[0].score, notation(&candidate), candidate.score, player->score,
                     collection(drawn), bag.count);
            finish(&out, &text);
            bool out_now = player->rack[0] == 0 && bag.count == 0;
            free(legal.items);
            if (out_now) {
                outgoing = index;
                break;
            }
        } else if (bag.count >= 7) {
            char keep[8], returned[8], drawn[8];
            best_leave(p, rack, keep);
            remove_tiles(rack, keep, returned);
            exchange(&bag, returned, &random, drawn);
            snprintf(player->rack, sizeof player->rack, "%s%s", keep, drawn);
            ++player->exchanges;
            ++consecutive;
            text_add(&text, " exchange keep=%s draw=%s bag=%d", collection(keep), collection(drawn),
                     bag.count);
            finish(&out, &text);
            free(legal.items);
        } else {
            ++player->passes;
            ++consecutive;
            text_add(&text, " pass bag=%d", bag.count);
            finish(&out, &text);
            free(legal.items);
        }
        if (consecutive == 6)
            break;
    }
    if (outgoing >= 0)
        add_line(&out, "end reason=out player=%s turns=%d", players[outgoing].name, turn);
    else
        add_line(&out, "end reason=scoreless turns=%d", turn);
    int adjustments[4], final_scores[4], standings[4];
    for (int i = 0; i < count; ++i)
        adjustments[i] = -points(players[i].rack, p->values);
    if (outgoing >= 0) {
        adjustments[outgoing] = 0;
        for (int i = 0; i < count; ++i)
            if (i != outgoing)
                adjustments[outgoing] += points(players[i].rack, p->values);
    }
    for (int i = 0; i < count; ++i) {
        GamePlayer *player = &players[i];
        final_scores[i] = player->score + adjustments[i];
        add_line(&out, "final %s score=%d rack=%s adjust=%s%d total=%d", player->name,
                 player->score, collection(player->rack), adjustments[i] > 0 ? "+" : "",
                 adjustments[i], final_scores[i]);
        int k = i;
        while (k > 0 && final_scores[i] > final_scores[standings[k - 1]]) {
            standings[k] = standings[k - 1];
            --k;
        }
        standings[k] = i;
    }
    for (int i = 0; i < count; ++i) {
        int index = standings[i];
        GamePlayer *player = &players[index];
        add_line(&out,
                 "standing %d %s total=%d plays=%d bingos=%d exchanges=%d passes=%d top=%d loss=%d",
                 i + 1, player->name, final_scores[index], player->plays, player->bingos,
                 player->exchanges, player->passes, player->top, player->loss);
    }
    Text text = {0};
    text_add(&text, "winner ");
    bool separator = false;
    for (int i = 0; i < count; ++i)
        if (final_scores[i] == final_scores[standings[0]]) {
            text_add(&text, "%s%s", separator ? "," : "", players[i].name);
            separator = true;
        }
    finish(&out, &text);
    if (highlight_turn)
        add_line(&out, "highlight turn=%d player=%s play %s score=%d", highlight_turn,
                 players[highlight_player].name, notation(&highlight), highlight.score);
    append_board(&out, &board);
    p->game.turns += turn;
    for (int i = 0; i < count; ++i) {
        p->game.plays += players[i].plays;
        p->game.exchanges += players[i].exchanges;
        p->game.passes += players[i].passes;
        p->game.bingos += players[i].bingos;
    }
    return out;
}
static Lines duplicate_game(Program *p, const Lines *job) {
    Tokens header = split(job->items[0]);
    Minstd random = {strtoll(header.items[2], NULL, 10)};
    Bag bag = make_bag(p->counts, &random);
    Board board = empty_board();
    char rack[8];
    draw(&bag, 7, rack);
    GamePlayer players[4] = {0};
    int count = (int)job->count - 1;
    Lines out = {0};
    add_line(&out, "DUPLICATE %s seed=%s players=%d", header.items[1], header.items[2], count);
    for (int i = 0; i < count; ++i) {
        Tokens row = split(job->items[i + 1]);
        strcpy(players[i].name, row.items[1]);
        strcpy(players[i].strategy_name, row.items[2]);
        players[i].strategy = strategy(row.items[2]);
        add_line(&out, "player %d %s strategy=%s", i + 1, players[i].name,
                 players[i].strategy_name);
    }
    int round = 0, master_total = 0;
    bool went_out = false;
    for (;;) {
        Evaluations legal = legal_moves(p, &board, rack);
        if (legal.count == 0) {
            free(legal.items);
            break;
        }
        ++round;
        Evaluated master = legal.items[0];
        Text text = {0};
        text_add(&text, "round %d rack=%s moves=%zu master %s score=%d picks=", round,
                 collection(rack), legal.count, notation(&master), master.score);
        for (int i = 0; i < count; ++i) {
            int score = legal.items[choose(&legal, players[i].strategy)].score;
            players[i].score += score;
            text_add(&text, "%s%d", i ? "," : "", score);
        }
        finish(&out, &text);
        master_total += master.score;
        board = apply_tiles(&board, &master.tiles);
        char drawn[8];
        draw(&bag, 7 - (int)strlen(master.leave), drawn);
        snprintf(rack, sizeof rack, "%s%s", master.leave, drawn);
        free(legal.items);
        if (rack[0] == 0) {
            went_out = true;
            break;
        }
    }
    if (went_out)
        add_line(&out, "end reason=out rounds=%d", round);
    else
        add_line(&out, "end reason=stuck rounds=%d rack=%s", round, collection(rack));
    add_line(&out, "master total=%d", master_total);
    int maximum = players[0].score;
    for (int i = 0; i < count; ++i) {
        int percent = master_total >= 1 ? 100 * players[i].score / master_total : 0;
        add_line(&out, "final %s total=%d percent=%d", players[i].name, players[i].score, percent);
        if (players[i].score > maximum)
            maximum = players[i].score;
    }
    Text text = {0};
    text_add(&text, "winner ");
    bool separator = false;
    for (int i = 0; i < count; ++i)
        if (players[i].score == maximum) {
            text_add(&text, "%s%s", separator ? "," : "", players[i].name);
            separator = true;
        }
    finish(&out, &text);
    append_board(&out, &board);
    p->game.rounds += round;
    return out;
}
static char *read_line(FILE *file) {
    size_t n = 0, capacity = 128;
    char *out = malloc(capacity);
    int ch;
    while ((ch = fgetc(file)) != EOF && ch != '\n') {
        if (n + 1 == capacity) {
            capacity *= 2;
            out = realloc(out, capacity);
        }
        out[n++] = (char)ch;
    }
    if (ch == EOF && n == 0) {
        free(out);
        return NULL;
    }
    out[n] = 0;
    return out;
}
static void read_inputs(Program *p) {
    trie_init(&p->trie);
    FILE *file = fopen("input/tiles.txt", "r");
    char *text;
    while ((text = read_line(file))) {
        if (text[0] && text[0] != '#') {
            Tokens row = split(text);
            int tile = tile_index(row.items[0][0]);
            p->values[tile] = atoi(row.items[1]);
            p->counts[tile] = atoi(row.items[2]);
            p->weights[tile] = atoi(row.items[3]);
        }
        free(text);
    }
    fclose(file);
    file = fopen("input/dictionary.txt", "r");
    int candidates = 0, skipped = 0, duplicates = 0, lengths[16] = {0};
    while ((text = read_line(file))) {
        if (text[0] && text[0] != '#') {
            ++candidates;
            size_t length = strlen(text);
            bool good = length >= 2 && length <= 15;
            for (const char *c = text; *c; ++c)
                if (!upper(*c))
                    good = false;
            if (!good)
                ++skipped;
            else if (trie_add(&p->trie, text))
                ++lengths[length];
            else
                ++duplicates;
        }
        free(text);
    }
    fclose(file);
    add_line(&p->dictionary_lines, "DICTIONARY lines=%d words=%d skipped=%d duplicates=%d nodes=%d",
             candidates, p->trie.words, skipped, duplicates, p->trie.count);
    Text description = {0};
    text_add(&description, "lengths");
    for (int length = 2; length <= 15; ++length)
        if (lengths[length])
            text_add(&description, " %d=%d", length, lengths[length]);
    finish(&p->dictionary_lines, &description);
    file = fopen("input/jobs.txt", "r");
    Lines current = {0};
    while ((text = read_line(file))) {
        if (current.count == 0) {
            if (text[0] && text[0] != '#')
                Lines_append(&current, text);
            else
                free(text);
        } else if (!strcmp(text, "END")) {
            Blocks_append(&p->jobs, current);
            current = (Lines){0};
            free(text);
        } else
            Lines_append(&current, text);
    }
    fclose(file);
}
static void write_blocks(const char *name, const Blocks *blocks) {
    char path[128];
    snprintf(path, sizeof path, "output/%s", name);
    FILE *file = fopen(path, "w");
    for (size_t i = 0; i < blocks->count; ++i) {
        if (i)
            fputc('\n', file);
        for (size_t j = 0; j < blocks->items[i].count; ++j)
            fprintf(file, "%s\n", blocks->items[i].items[j]);
    }
    fclose(file);
}
int main(void) {
    Program *p = calloc(1, sizeof *p);
    read_inputs(p);
    Blocks move_blocks = {0}, validation_blocks = {0}, game_blocks = {0};
    Blocks_append(&move_blocks, p->dictionary_lines);
    p->dictionary_lines = (Lines){0};
    Lines seen = {0};
    for (size_t i = 0; i < p->jobs.count; ++i) {
        const Lines *job = &p->jobs.items[i];
        Tokens header = split(job->items[0]);
        const char *kind = header.items[0], *name = header.items[1];
        Blocks *destination;
        if (!strcmp(kind, "TOPN")) {
            destination = &move_blocks;
            ++p->topn.jobs;
        } else if (!strcmp(kind, "VALIDATE")) {
            destination = &validation_blocks;
            ++p->validation.jobs;
        } else {
            destination = &game_blocks;
            if (!strcmp(kind, "GAME"))
                ++p->game.games;
            else
                ++p->game.duplicates;
        }
        char reason[128];
        bool bad = job_error(p, job, &seen, reason);
        add_line(&seen, "%s", name);
        Lines result = {0};
        if (bad) {
            add_line(&result, "%s %s", kind, name);
            add_line(&result, "error %s", reason);
            if (!strcmp(kind, "TOPN"))
                ++p->topn.errors;
            else if (!strcmp(kind, "VALIDATE"))
                ++p->validation.errors;
            else
                ++p->game.errors;
        } else if (!strcmp(kind, "TOPN"))
            result = topn(p, job);
        else if (!strcmp(kind, "VALIDATE"))
            result = validate(p, job);
        else if (!strcmp(kind, "GAME"))
            result = ordinary_game(p, job);
        else
            result = duplicate_game(p, job);
        Blocks_append(destination, result);
    }
    Lines summary = {0};
    add_line(&summary, "SUMMARY jobs=%d errors=%d moves=%d bingos=%d", p->topn.jobs, p->topn.errors,
             p->topn.moves, p->topn.bingos);
    Blocks_append(&move_blocks, summary);
    summary = (Lines){0};
    add_line(&summary, "SUMMARY jobs=%d errors=%d moves=%d valid=%d invalid=%d loss=%d",
             p->validation.jobs, p->validation.errors, p->validation.moves, p->validation.valid,
             p->validation.invalid, p->validation.loss);
    Blocks_append(&validation_blocks, summary);
    summary = (Lines){0};
    add_line(
        &summary,
        "SUMMARY games=%d duplicates=%d errors=%d turns=%d rounds=%d plays=%d exchanges=%d passes=%d bingos=%d",
        p->game.games, p->game.duplicates, p->game.errors, p->game.turns, p->game.rounds,
        p->game.plays, p->game.exchanges, p->game.passes, p->game.bingos);
    Blocks_append(&game_blocks, summary);
    mkdir("output", 0777);
    write_blocks("moves.txt", &move_blocks);
    write_blocks("validation.txt", &validation_blocks);
    write_blocks("game.txt", &game_blocks);
    Blocks *reports[3] = {&move_blocks, &validation_blocks, &game_blocks};
    for (int i = 0; i < 3; ++i) {
        for (size_t j = 0; j < reports[i]->count; ++j)
            free_lines(&reports[i]->items[j]);
        free(reports[i]->items);
    }
    free_lines(&seen);
    for (size_t i = 0; i < p->jobs.count; ++i)
        free_lines(&p->jobs.items[i]);
    free(p->jobs.items);
    free(p->trie.nodes);
    free(p);
    return 0;
}
