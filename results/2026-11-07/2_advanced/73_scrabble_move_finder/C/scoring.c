#include "scrabble.h"
Placement squares(const Move *move) {
    Placement out = {0};
    for (int i = 0; move->word[i]; ++i)
        out.items[out.count++] = (Tile){move->row + move->direction * i,
                                        move->column + (1 - move->direction) * i, move->word[i]};
    return out;
}
Placement placement(const Board *board, const Move *move) {
    Placement cells = squares(move), out = {0};
    for (int i = 0; i < cells.count; ++i)
        if (board->cells[cells.items[i].row][cells.items[i].column] == '.')
            out.items[out.count++] = cells.items[i];
    return out;
}
Board apply_tiles(const Board *board, const Placement *tiles) {
    Board out = *board;
    for (int i = 0; i < tiles->count; ++i) {
        const Tile *tile = &tiles->items[i];
        out.cells[tile->row][tile->column] = tile->letter;
    }
    return out;
}
Words cross_words(const Board *board, const Move *move) {
    Placement tiles = placement(board, move);
    Board after = apply_tiles(board, &tiles);
    Words out = {0};
    for (int i = 0; i < tiles.count; ++i) {
        Move word = run_at(&after, tiles.items[i].row, tiles.items[i].column, 1 - move->direction);
        if (strlen(word.word) >= 2)
            out.items[out.count++] = word;
    }
    return out;
}
int word_score(const Board *board, const Move *word, const Counts values) {
    Placement cells = squares(word);
    int score = 0, multiplier = 1;
    for (int i = 0; i < cells.count; ++i) {
        Tile tile = cells.items[i];
        int value = upper(tile.letter) ? values[tile.letter - 'A'] : 0;
        if (board->cells[tile.row][tile.column] == '.') {
            char premium = premiums[tile.row][tile.column];
            value *= premium == '+' ? 2 : premium == '^' ? 3 : 1;
            multiplier *= premium == '*' ? 2 : premium == '#' ? 3 : 1;
        }
        score += value;
    }
    return score * multiplier;
}
Scored score_move(const Board *board, const Move *move, const Counts values) {
    Scored out = {0};
    out.tiles = placement(board, move);
    out.words[out.count++] = (WordScore){*move, word_score(board, move, values)};
    Words crosses = cross_words(board, move);
    for (int i = 0; i < crosses.count; ++i)
        out.words[out.count++] =
            (WordScore){crosses.items[i], word_score(board, &crosses.items[i], values)};
    for (int i = 0; i < out.count; ++i)
        out.score += out.words[i].score;
    if (out.tiles.count == RACK_SIZE)
        out.score += BINGO_BONUS;
    return out;
}
