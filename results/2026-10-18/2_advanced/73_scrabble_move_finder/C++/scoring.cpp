#include "scrabble.hpp"
Placement squares(const Move &move) {
    Placement out;
    for (int i = 0; i < int(move.word.size()); ++i)
        out.push_back(
            {move.row + move.direction * i, move.column + (1 - move.direction) * i, move.word[i]});
    return out;
}
Placement placement(const Board &board, const Move &move) {
    Placement out;
    for (const Tile &tile : squares(move))
        if (board[tile.row][tile.column] == '.')
            out.push_back(tile);
    return out;
}
Board apply_tiles(const Board &board, const Placement &tiles) {
    Board out = board;
    for (const Tile &tile : tiles)
        out[tile.row][tile.column] = tile.letter;
    return out;
}
std::vector<Move> cross_words(const Board &board, const Move &move) {
    Placement tiles = placement(board, move);
    Board after = apply_tiles(board, tiles);
    std::vector<Move> out;
    for (const Tile &tile : tiles) {
        Move word = run_at(after, tile.row, tile.column, 1 - move.direction);
        if (word.word.size() >= 2)
            out.push_back(word);
    }
    return out;
}
int word_score(const Board &board, const Move &word, const Counts &values) {
    int score = 0, multiplier = 1;
    for (const Tile &tile : squares(word)) {
        int value = upper(tile.letter) ? values[tile.letter - 'A'] : 0;
        if (board[tile.row][tile.column] == '.') {
            char premium = premiums[tile.row][tile.column];
            value *= premium == '+' ? 2 : premium == '^' ? 3 : 1;
            multiplier *= premium == '*' ? 2 : premium == '#' ? 3 : 1;
        }
        score += value;
    }
    return score * multiplier;
}
Scored score_move(const Board &board, const Move &move, const Counts &values) {
    std::vector<Move> words{move};
    auto crossed = cross_words(board, move);
    words.insert(words.end(), crossed.begin(), crossed.end());
    Scored out{0, placement(board, move), {}};
    for (const Move &word : words) {
        int score = word_score(board, word, values);
        out.score += score;
        out.words.push_back({word, score});
    }
    if (out.tiles.size() == rack_size)
        out.score += bingo_bonus;
    return out;
}
