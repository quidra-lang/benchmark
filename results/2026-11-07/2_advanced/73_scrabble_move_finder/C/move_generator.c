#include "scrabble.h"
Anchors anchors(const Board *board) {
    Anchors out = {0};
    if (board_tiles(board).count == 0) {
        out.cells[7][7] = true;
        out.count = 1;
        return out;
    }
    for (int r = 0; r < 15; ++r)
        for (int c = 0; c < 15; ++c)
            if (board->cells[r][c] == '.') {
                int adjacent[4][2], n = neighbors(r, c, adjacent);
                for (int i = 0; i < n; ++i)
                    if (board->cells[adjacent[i][0]][adjacent[i][1]] != '.') {
                        out.cells[r][c] = true;
                        ++out.count;
                        break;
                    }
            }
    return out;
}
Checks cross_checks(const Board *board, const Trie *trie) {
    Checks out = {0};
    for (int r = 0; r < 15; ++r)
        for (int c = 0; c < 15; ++c) {
            if (board->cells[r][c] != '.')
                continue;
            int first = r, last = r;
            while (first > 0 && board->cells[first - 1][c] != '.')
                --first;
            while (last + 1 < 15 && board->cells[last + 1][c] != '.')
                ++last;
            if (first == last)
                continue;
            out.checked[r][c] = true;
            char word[16], capital[16];
            for (int letter = 0; letter < 26; ++letter) {
                int p = 0;
                for (int row = first; row <= last; ++row)
                    word[p++] = row == r ? (char)('A' + letter) : board->cells[row][c];
                word[p] = 0;
                uppercase(word, capital);
                if (trie_contains(trie, capital))
                    out.mask[r][c] |= UINT32_C(1) << letter;
            }
        }
    return out;
}
typedef struct {
    const Board *board;
    const Trie *trie;
    Anchors anchors;
    Checks checks;
    Counts counts;
    Moves *out;
    int row, anchor;
} Generator;
static void extend(Generator *g, int node, int column, const char *word, int start) {
    bool empty = column == 15 || g->board->cells[g->row][column] == '.';
    if (empty && column > g->anchor && g->trie->nodes[node].terminal) {
        Move move = {g->row, start, 0, {0}};
        strcpy(move.word, word);
        Moves_append(g->out, move);
    }
    if (column == 15)
        return;
    size_t length = strlen(word);
    if (!empty) {
        char written = g->board->cells[g->row][column],
             capital = lower(written) ? (char)(written - 'a' + 'A') : written;
        int child = g->trie->nodes[node].children[capital - 'A'];
        if (child >= 0) {
            char next[16];
            strcpy(next, word);
            next[length] = written;
            next[length + 1] = 0;
            extend(g, child, column + 1, next, start);
        }
        return;
    }
    for (int letter = 0; letter < 26; ++letter) {
        int child = g->trie->nodes[node].children[letter];
        if (child < 0 || (g->checks.checked[g->row][column] &&
                          !(g->checks.mask[g->row][column] & (UINT32_C(1) << letter))))
            continue;
        for (int blank = 0; blank < 2; ++blank) {
            int tile = blank ? 26 : letter;
            if (g->counts[tile]) {
                --g->counts[tile];
                char next[16];
                strcpy(next, word);
                next[length] = (char)((blank ? 'a' : 'A') + letter);
                next[length + 1] = 0;
                extend(g, child, column + 1, next, start);
                ++g->counts[tile];
            }
        }
    }
}
static void left_part(Generator *g, int node, const char *prefix, int remaining) {
    size_t length = strlen(prefix);
    extend(g, node, g->anchor, prefix, g->anchor - (int)length);
    if (!remaining)
        return;
    for (int letter = 0; letter < 26; ++letter) {
        int child = g->trie->nodes[node].children[letter];
        if (child < 0)
            continue;
        for (int blank = 0; blank < 2; ++blank) {
            int tile = blank ? 26 : letter;
            if (g->counts[tile]) {
                --g->counts[tile];
                char next[16];
                strcpy(next, prefix);
                next[length] = (char)((blank ? 'a' : 'A') + letter);
                next[length + 1] = 0;
                left_part(g, child, next, remaining - 1);
                ++g->counts[tile];
            }
        }
    }
}
static Moves across_moves(const Board *board, const char *rack, const Trie *trie) {
    Moves out = {0};
    Generator g = {0};
    g.board = board;
    g.trie = trie;
    g.anchors = anchors(board);
    g.checks = cross_checks(board, trie);
    g.out = &out;
    for (const char *p = rack; *p; ++p)
        ++g.counts[tile_index(*p)];
    for (int r = 0; r < 15; ++r)
        for (int anchor = 0; anchor < 15; ++anchor) {
            if (!g.anchors.cells[r][anchor])
                continue;
            g.row = r;
            g.anchor = anchor;
            if (anchor > 0 && board->cells[r][anchor - 1] != '.') {
                int first = anchor - 1;
                while (first > 0 && board->cells[r][first - 1] != '.')
                    --first;
                char prefix[16], capital[16];
                int p = 0;
                for (int c = first; c < anchor; ++c)
                    prefix[p++] = board->cells[r][c];
                prefix[p] = 0;
                uppercase(prefix, capital);
                int node = trie_prefix(trie, capital);
                if (node >= 0)
                    extend(&g, node, anchor, prefix, first);
            } else {
                int first = anchor - 1;
                while (first >= 0 && board->cells[r][first] == '.' && !g.anchors.cells[r][first])
                    --first;
                left_part(&g, 0, "", anchor - first - 1);
            }
        }
    return out;
}
Moves generate(const Board *board, const char *rack, const Trie *trie) {
    Moves out = across_moves(board, rack, trie);
    Board transposed = transpose(board);
    Moves down = across_moves(&transposed, rack, trie);
    for (size_t i = 0; i < down.count; ++i) {
        Move move = down.items[i];
        int r = move.column;
        move.column = move.row;
        move.row = r;
        move.direction = 1;
        Placement tiles = placement(board, &move);
        if (tiles.count == 1) {
            Board after = apply_tiles(board, &tiles);
            Move across = run_at(&after, tiles.items[0].row, tiles.items[0].column, 0);
            if (strlen(across.word) >= 2)
                continue;
        }
        Moves_append(&out, move);
    }
    free(down.items);
    return out;
}
