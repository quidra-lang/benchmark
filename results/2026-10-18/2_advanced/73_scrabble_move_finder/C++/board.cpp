#include "scrabble.hpp"
const std::array<std::string, 15> premiums = {
    "#..+...#...+..#", ".*...^...^...*.", "..*...+.+...*..", "+..*...+...*..+", "....*.....*....",
    ".^...^...^...^.", "..+...+.+...+..", "#..+...*...+..#", "..+...+.+...+..", ".^...^...^...^.",
    "....*.....*....", "+..*...+...*..+", "..*...+.+...*..", ".*...^...^...*.", "#..+...#...+..#"};
bool upper(char letter) { return letter >= 'A' && letter <= 'Z'; }
bool lower(char letter) { return letter >= 'a' && letter <= 'z'; }
std::string uppercase(std::string value) {
    for (char &letter : value)
        if (lower(letter))
            letter = char(letter - 'a' + 'A');
    return value;
}
int tile_index(char letter) { return upper(letter) ? letter - 'A' : 26; }
bool inside(int row, int column) { return row >= 0 && row < 15 && column >= 0 && column < 15; }
std::string square_name(int row, int column) {
    return std::string(1, char('A' + column)) + std::to_string(row + 1);
}
std::string position(const Move &move) {
    return move.direction ? std::string(1, char('A' + move.column)) + std::to_string(move.row + 1)
                          : std::to_string(move.row + 1) + char('A' + move.column);
}
std::optional<Move> parse_position(const std::string &text) {
    if (text.size() < 2 || text.size() > 3)
        return {};
    int direction = upper(text[0]) ? 1 : 0;
    char column = direction ? text[0] : text.back();
    std::string row = direction ? text.substr(1) : text.substr(0, text.size() - 1);
    if (column < 'A' || column > 'O' || row.empty() || row[0] == '0')
        return {};
    for (char digit : row)
        if (digit < '0' || digit > '9')
            return {};
    int number = std::stoi(row);
    if (number < 1 || number > 15)
        return {};
    return Move{number - 1, column - 'A', direction, ""};
}
Board empty_board() {
    Board out;
    for (auto &row : out)
        row.fill('.');
    return out;
}
Board transpose(const Board &board) {
    Board out;
    for (int row = 0; row < 15; ++row)
        for (int column = 0; column < 15; ++column)
            out[row][column] = board[column][row];
    return out;
}
Placement transpose_tiles(const Placement &tiles) {
    Placement out;
    for (const Tile &tile : tiles)
        out.push_back({tile.column, tile.row, tile.letter});
    return out;
}
Placement board_tiles(const Board &board) {
    Placement out;
    for (int row = 0; row < 15; ++row)
        for (int column = 0; column < 15; ++column)
            if (board[row][column] != '.')
                out.push_back({row, column, board[row][column]});
    return out;
}
std::vector<std::pair<int, int>> neighbors(int row, int column) {
    std::vector<std::pair<int, int>> out;
    for (auto delta : std::array<std::pair<int, int>, 4>{{{-1, 0}, {1, 0}, {0, -1}, {0, 1}}})
        if (inside(row + delta.first, column + delta.second))
            out.push_back({row + delta.first, column + delta.second});
    return out;
}
Move run_at(const Board &board, int row, int column, int direction) {
    int dr = direction, dc = 1 - direction;
    while (inside(row - dr, column - dc) && board[row - dr][column - dc] != '.') {
        row -= dr;
        column -= dc;
    }
    Move out{row, column, direction, ""};
    while (inside(row, column) && board[row][column] != '.') {
        out.word += board[row][column];
        row += dr;
        column += dc;
    }
    return out;
}
std::vector<Move> board_words(const Board &board) {
    std::vector<Move> out;
    for (int direction = 0; direction < 2; ++direction)
        for (int line = 0; line < 15; ++line) {
            int offset = 0;
            while (offset < 15) {
                int row = direction ? offset : line, column = direction ? line : offset;
                if (board[row][column] == '.') {
                    ++offset;
                    continue;
                }
                Move word = run_at(board, row, column, direction);
                if (word.word.size() >= 2)
                    out.push_back(word);
                offset += int(word.word.size());
            }
        }
    return out;
}
bool connected(const Board &board) {
    Placement occupied = board_tiles(board);
    if (occupied.empty())
        return true;
    Squares seen;
    std::deque<std::pair<int, int>> pending;
    pending.push_back({occupied[0].row, occupied[0].column});
    seen.insert(pending[0]);
    while (!pending.empty()) {
        auto point = pending.front();
        pending.pop_front();
        for (auto adjacent : neighbors(point.first, point.second))
            if (board[adjacent.first][adjacent.second] != '.' && seen.insert(adjacent).second)
                pending.push_back(adjacent);
    }
    return seen.size() == occupied.size();
}
Lines display(const Board &board) {
    Lines out;
    std::string header = "   ";
    for (int column = 0; column < 15; ++column) {
        if (column)
            header += ' ';
        header += char('A' + column);
    }
    out.push_back(header);
    for (int row = 0; row < 15; ++row) {
        std::string text = (row < 9 ? " " : "") + std::to_string(row + 1) + " ";
        for (int column = 0; column < 15; ++column) {
            if (column)
                text += ' ';
            text += board[row][column] == '.' ? premiums[row][column] : board[row][column];
        }
        out.push_back(text);
    }
    return out;
}
