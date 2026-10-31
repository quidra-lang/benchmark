#ifndef SCRABBLE_HPP
#define SCRABBLE_HPP
#include <algorithm>
#include <array>
#include <cstdint>
#include <cstdlib>
#include <deque>
#include <filesystem>
#include <fstream>
#include <functional>
#include <map>
#include <numeric>
#include <optional>
#include <set>
#include <sstream>
#include <string>
#include <tuple>
#include <utility>
#include <vector>
using Integer = std::int64_t;
using Names = std::vector<std::string>;
using Lines = Names;
using Board = std::array<std::array<char, 15>, 15>;
using Counts = std::array<int, 27>;
using Squares = std::set<std::pair<int, int>>;
using Checks = std::map<std::pair<int, int>, std::uint32_t>;
constexpr int board_size = 15, rack_size = 7, bingo_bonus = 50;
constexpr const char *letters = "ABCDEFGHIJKLMNOPQRSTUVWXYZ",
                     *tile_order = "ABCDEFGHIJKLMNOPQRSTUVWXYZ?";
int tile_index(char letter);
bool upper(char letter), lower(char letter);
std::string uppercase(std::string value);
struct Move {
    int row, column, direction;
    std::string word;
};
struct Tile {
    int row, column;
    char letter;
};
using Placement = std::vector<Tile>;
extern const std::array<std::string, 15> premiums;
bool inside(int row, int column);
std::string square_name(int row, int column), position(const Move &move);
std::optional<Move> parse_position(const std::string &text);
Board empty_board(), transpose(const Board &board);
Placement transpose_tiles(const Placement &tiles), board_tiles(const Board &board);
std::vector<std::pair<int, int>> neighbors(int row, int column);
Move run_at(const Board &board, int row, int column, int direction);
std::vector<Move> board_words(const Board &board);
bool connected(const Board &board);
Lines display(const Board &board);
struct TrieNode {
    std::array<int, 26> children;
    bool terminal = false;
    TrieNode() { children.fill(-1); }
};
struct Trie {
    std::vector<TrieNode> nodes{TrieNode{}};
    int words = 0;
    bool add(const std::string &word);
    int prefix(const std::string &word) const;
    bool contains(const std::string &word) const;
    Names anagrams(const std::string &rack) const;
};
Squares anchors(const Board &board);
Checks cross_checks(const Board &board, const Trie &trie);
std::vector<Move> generate(const Board &board, const std::string &rack, const Trie &trie);
Placement squares(const Move &move), placement(const Board &board, const Move &move);
Board apply_tiles(const Board &board, const Placement &tiles);
std::vector<Move> cross_words(const Board &board, const Move &move);
int word_score(const Board &board, const Move &word, const Counts &values);
struct Scored {
    int score;
    Placement tiles;
    std::vector<std::pair<Move, int>> words;
};
Scored score_move(const Board &board, const Move &move, const Counts &values);
struct Minstd {
    Integer state;
    Integer next() {
        state = 48271 * state % 2147483647;
        return state;
    }
};
void shuffle(std::string &bag, Minstd &random);
std::string make_bag(const Counts &counts, Minstd &random), draw(std::string &bag, int count),
    exchange(std::string &bag, std::string returned, Minstd &random);
int points(const std::string &collection, const Counts &values);
template <class... T> void line(Lines &out, const T &...values) {
    std::ostringstream stream;
    (stream << ... << values);
    out.push_back(stream.str());
}
#endif
