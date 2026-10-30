#include "scrabble.h"
const char premiums[15][16] = {
    "#..+...#...+..#", ".*...^...^...*.", "..*...+.+...*..", "+..*...+...*..+", "....*.....*....",
    ".^...^...^...^.", "..+...+.+...+..", "#..+...*...+..#", "..+...+.+...+..", ".^...^...^...^.",
    "....*.....*....", "+..*...+...*..+", "..*...+.+...*..", ".*...^...^...*.", "#..+...#...+..#"};
const char tile_order[28] = "ABCDEFGHIJKLMNOPQRSTUVWXYZ?";
bool upper(char c) { return c >= 'A' && c <= 'Z'; }
bool lower(char c) { return c >= 'a' && c <= 'z'; }
int tile_index(char c) { return upper(c) ? c - 'A' : 26; }
void uppercase(const char *word, char *out) {
    while (*word) {
        char c = *word++;
        *out++ = lower(c) ? (char)(c - 'a' + 'A') : c;
    }
    *out = 0;
}
bool inside(int r, int c) { return r >= 0 && r < 15 && c >= 0 && c < 15; }
const char *square_name(int r, int c) {
    static char buffers[16][8];
    static unsigned index;
    char *out = buffers[index++ % 16];
    snprintf(out, 8, "%c%d", 'A' + c, r + 1);
    return out;
}
const char *position(const Move *m) {
    static char buffers[16][8];
    static unsigned index;
    char *out = buffers[index++ % 16];
    if (m->direction)
        snprintf(out, 8, "%c%d", 'A' + m->column, m->row + 1);
    else
        snprintf(out, 8, "%d%c", m->row + 1, 'A' + m->column);
    return out;
}
bool parse_position(const char *text, Move *out) {
    size_t n = strlen(text);
    if (n < 2 || n > 3)
        return false;
    int direction = upper(text[0]) ? 1 : 0;
    char column = direction ? text[0] : text[n - 1];
    if (column < 'A' || column > 'O')
        return false;
    const char *digits = direction ? text + 1 : text;
    size_t count = n - 1;
    if (digits[0] == '0')
        return false;
    int row = 0;
    for (size_t i = 0; i < count; ++i) {
        if (digits[i] < '0' || digits[i] > '9')
            return false;
        row = row * 10 + digits[i] - '0';
    }
    if (row < 1 || row > 15)
        return false;
    memset(out, 0, sizeof *out);
    out->row = row - 1;
    out->column = column - 'A';
    out->direction = direction;
    return true;
}
Board empty_board(void) {
    Board out;
    memset(out.cells, '.', sizeof out.cells);
    return out;
}
Board transpose(const Board *board) {
    Board out;
    for (int r = 0; r < 15; ++r)
        for (int c = 0; c < 15; ++c)
            out.cells[r][c] = board->cells[c][r];
    return out;
}
Placement transpose_tiles(const Placement *tiles) {
    Placement out = {0};
    for (int i = 0; i < tiles->count; ++i)
        out.items[out.count++] =
            (Tile){tiles->items[i].column, tiles->items[i].row, tiles->items[i].letter};
    return out;
}
BoardTiles board_tiles(const Board *board) {
    BoardTiles out = {0};
    for (int r = 0; r < 15; ++r)
        for (int c = 0; c < 15; ++c)
            if (board->cells[r][c] != '.')
                out.items[out.count++] = (Tile){r, c, board->cells[r][c]};
    return out;
}
int neighbors(int r, int c, int out[4][2]) {
    const int directions[4][2] = {{-1, 0}, {1, 0}, {0, -1}, {0, 1}};
    int count = 0;
    for (int i = 0; i < 4; ++i)
        if (inside(r + directions[i][0], c + directions[i][1])) {
            out[count][0] = r + directions[i][0];
            out[count++][1] = c + directions[i][1];
        }
    return count;
}
Move run_at(const Board *board, int r, int c, int direction) {
    int dr = direction, dc = 1 - direction;
    while (inside(r - dr, c - dc) && board->cells[r - dr][c - dc] != '.') {
        r -= dr;
        c -= dc;
    }
    Move out = {r, c, direction, {0}};
    int count = 0;
    while (inside(r, c) && board->cells[r][c] != '.') {
        out.word[count++] = board->cells[r][c];
        r += dr;
        c += dc;
    }
    out.word[count] = 0;
    return out;
}
Words board_words(const Board *board) {
    Words out = {0};
    for (int direction = 0; direction < 2; ++direction)
        for (int line = 0; line < 15; ++line) {
            int offset = 0;
            while (offset < 15) {
                int r = direction ? offset : line, c = direction ? line : offset;
                if (board->cells[r][c] == '.') {
                    ++offset;
                    continue;
                }
                Move word = run_at(board, r, c, direction);
                int length = (int)strlen(word.word);
                if (length >= 2)
                    out.items[out.count++] = word;
                offset += length;
            }
        }
    return out;
}
bool connected(const Board *board) {
    BoardTiles occupied = board_tiles(board);
    if (occupied.count == 0)
        return true;
    bool seen[15][15] = {{false}};
    int pending[225][2], head = 0, count = 1;
    pending[0][0] = occupied.items[0].row;
    pending[0][1] = occupied.items[0].column;
    seen[pending[0][0]][pending[0][1]] = true;
    while (head < count) {
        int adjacent[4][2], n = neighbors(pending[head][0], pending[head][1], adjacent);
        ++head;
        for (int i = 0; i < n; ++i) {
            int r = adjacent[i][0], c = adjacent[i][1];
            if (board->cells[r][c] != '.' && !seen[r][c]) {
                seen[r][c] = true;
                pending[count][0] = r;
                pending[count++][1] = c;
            }
        }
    }
    return count == occupied.count;
}
Lines display(const Board *board) {
    Lines out = {0};
    add_line(&out, "   A B C D E F G H I J K L M N O");
    for (int r = 0; r < 15; ++r) {
        char text[64];
        int p = snprintf(text, sizeof text, "%2d ", r + 1);
        for (int c = 0; c < 15; ++c) {
            if (c)
                text[p++] = ' ';
            text[p++] = board->cells[r][c] == '.' ? premiums[r][c] : board->cells[r][c];
        }
        text[p] = 0;
        add_line(&out, "%s", text);
    }
    return out;
}
