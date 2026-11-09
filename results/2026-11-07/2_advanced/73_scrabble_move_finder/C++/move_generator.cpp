#include "scrabble.hpp"
Squares anchors(const Board &board) {
    if (board_tiles(board).empty())
        return {{7, 7}};
    Squares out;
    for (int row = 0; row < 15; ++row)
        for (int column = 0; column < 15; ++column)
            if (board[row][column] == '.')
                for (auto adjacent : neighbors(row, column))
                    if (board[adjacent.first][adjacent.second] != '.') {
                        out.insert({row, column});
                        break;
                    }
    return out;
}
Checks cross_checks(const Board &board, const Trie &trie) {
    Checks out;
    for (int row = 0; row < 15; ++row)
        for (int column = 0; column < 15; ++column) {
            if (board[row][column] != '.')
                continue;
            int first = row, last = row;
            while (first > 0 && board[first - 1][column] != '.')
                --first;
            while (last + 1 < 15 && board[last + 1][column] != '.')
                ++last;
            if (first == last)
                continue;
            std::string prefix, suffix;
            for (int r = first; r < row; ++r)
                prefix += board[r][column];
            for (int r = row + 1; r <= last; ++r)
                suffix += board[r][column];
            prefix = uppercase(prefix);
            suffix = uppercase(suffix);
            std::uint32_t mask = 0;
            for (int letter = 0; letter < 26; ++letter)
                if (trie.contains(prefix + char('A' + letter) + suffix))
                    mask |= std::uint32_t(1) << letter;
            out[{row, column}] = mask;
        }
    return out;
}
static std::vector<Move> across_moves(const Board &board, const std::string &rack, const Trie &trie,
                                      const Squares &anchor_squares, const Checks &checks) {
    std::vector<Move> out;
    Counts counts{};
    for (char tile : rack)
        ++counts[tile_index(tile)];
    for (auto point : anchor_squares) {
        int row = point.first, anchor = point.second;
        std::function<void(int, int, std::string, int)> extend;
        extend = [&](int node, int column, std::string word, int start) {
            bool empty = column == 15 || board[row][column] == '.';
            if (empty && column > anchor && trie.nodes[node].terminal)
                out.push_back({row, start, 0, word});
            if (column == 15)
                return;
            if (!empty) {
                char written = board[row][column];
                int child = trie.nodes[node].children[uppercase(std::string(1, written))[0] - 'A'];
                if (child >= 0)
                    extend(child, column + 1, word + written, start);
                return;
            }
            auto found = checks.find({row, column});
            for (int letter = 0; letter < 26; ++letter) {
                int child = trie.nodes[node].children[letter];
                if (child < 0 ||
                    (found != checks.end() && !(found->second & (std::uint32_t(1) << letter))))
                    continue;
                for (int blank = 0; blank < 2; ++blank) {
                    int tile = blank ? 26 : letter;
                    if (counts[tile]) {
                        --counts[tile];
                        extend(child, column + 1, word + char((blank ? 'a' : 'A') + letter), start);
                        ++counts[tile];
                    }
                }
            }
        };
        std::function<void(int, std::string, int)> left_part = [&](int node, std::string prefix,
                                                                   int remaining) {
            extend(node, anchor, prefix, anchor - int(prefix.size()));
            if (!remaining)
                return;
            for (int letter = 0; letter < 26; ++letter) {
                int child = trie.nodes[node].children[letter];
                if (child < 0)
                    continue;
                for (int blank = 0; blank < 2; ++blank) {
                    int tile = blank ? 26 : letter;
                    if (counts[tile]) {
                        --counts[tile];
                        left_part(child, prefix + char((blank ? 'a' : 'A') + letter),
                                  remaining - 1);
                        ++counts[tile];
                    }
                }
            }
        };
        if (anchor > 0 && board[row][anchor - 1] != '.') {
            int first = anchor - 1;
            while (first > 0 && board[row][first - 1] != '.')
                --first;
            std::string prefix;
            for (int column = first; column < anchor; ++column)
                prefix += board[row][column];
            int node = trie.prefix(uppercase(prefix));
            if (node >= 0)
                extend(node, anchor, prefix, first);
        } else {
            int first = anchor - 1;
            while (first >= 0 && board[row][first] == '.' && !anchor_squares.count({row, first}))
                --first;
            left_part(0, "", anchor - first - 1);
        }
    }
    return out;
}
std::vector<Move> generate(const Board &board, const std::string &rack, const Trie &trie) {
    Squares original = anchors(board), swapped;
    for (auto point : original)
        swapped.insert({point.second, point.first});
    auto across = across_moves(board, rack, trie, original, cross_checks(board, trie));
    Board transposed = transpose(board);
    auto down = across_moves(transposed, rack, trie, swapped, cross_checks(transposed, trie));
    for (const Move &move : down)
        across.push_back({move.column, move.row, 1, move.word});
    std::map<std::vector<std::tuple<int, int, char>>, Move> distinct;
    for (const Move &move : across) {
        Placement tiles = placement(board, move);
        if (tiles.size() == 1 && move.direction == 1) {
            const Tile &tile = tiles[0];
            if (run_at(apply_tiles(board, tiles), tile.row, tile.column, 0).word.size() >= 2)
                continue;
        }
        std::vector<std::tuple<int, int, char>> key;
        for (const Tile &tile : tiles)
            key.push_back({tile.row, tile.column, tile.letter});
        std::sort(key.begin(), key.end());
        distinct[key] = move;
    }
    std::vector<Move> out;
    for (const auto &entry : distinct)
        out.push_back(entry.second);
    return out;
}
