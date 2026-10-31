#ifndef SCRABBLE_H
#define SCRABBLE_H
#include <stdbool.h>
#include <stdint.h>
#include <stdarg.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <sys/stat.h>
#define BOARD_SIZE 15
#define RACK_SIZE 7
#define BINGO_BONUS 50
#define DEFINE_VECTOR(Name, Type)                                                                  \
    typedef struct {                                                                               \
        Type *items;                                                                               \
        size_t count, capacity;                                                                    \
    } Name;                                                                                        \
    static inline void Name##_append(Name *list, Type value) {                                     \
        if (list->count == list->capacity) {                                                       \
            list->capacity = list->capacity ? 2 * list->capacity : 4;                              \
            list->items = realloc(list->items, list->capacity * sizeof *list->items);              \
        }                                                                                          \
        list->items[list->count++] = value;                                                        \
    }
typedef int Counts[27];
DEFINE_VECTOR(Lines, char *)
typedef struct {
    char cells[15][15];
} Board;
typedef struct {
    int row, column, direction;
    char word[16];
} Move;
DEFINE_VECTOR(Moves, Move)
typedef struct {
    int row, column;
    char letter;
} Tile;
typedef struct {
    Tile items[15];
    int count;
} Placement;
typedef struct {
    Tile items[225];
    int count;
} BoardTiles;
typedef struct {
    Move items[225];
    int count;
} Words;
typedef struct {
    bool cells[15][15];
    int count;
} Anchors;
typedef struct {
    uint32_t mask[15][15];
    bool checked[15][15];
} Checks;
extern const char premiums[15][16], tile_order[28];
bool upper(char letter), lower(char letter), inside(int row, int column);
int tile_index(char letter);
void uppercase(const char *word, char *out);
const char *square_name(int row, int column), *position(const Move *move);
bool parse_position(const char *text, Move *out);
Board empty_board(void), transpose(const Board *board);
Placement transpose_tiles(const Placement *tiles);
BoardTiles board_tiles(const Board *board);
int neighbors(int row, int column, int out[4][2]);
Move run_at(const Board *board, int row, int column, int direction);
Words board_words(const Board *board);
bool connected(const Board *board);
Lines display(const Board *board);
void add_line(Lines *lines, const char *format, ...);
typedef struct {
    int children[26];
    bool terminal;
} TrieNode;
typedef struct {
    TrieNode *nodes;
    int count, capacity, words;
} Trie;
void trie_init(Trie *trie);
bool trie_add(Trie *trie, const char *word);
int trie_prefix(const Trie *trie, const char *word);
bool trie_contains(const Trie *trie, const char *word);
Lines trie_anagrams(const Trie *trie, const char *rack);
Anchors anchors(const Board *board);
Checks cross_checks(const Board *board, const Trie *trie);
Moves generate(const Board *board, const char *rack, const Trie *trie);
Placement squares(const Move *move), placement(const Board *board, const Move *move);
Board apply_tiles(const Board *board, const Placement *tiles);
Words cross_words(const Board *board, const Move *move);
int word_score(const Board *board, const Move *word, const Counts values);
typedef struct {
    Move word;
    int score;
} WordScore;
typedef struct {
    int score;
    Placement tiles;
    WordScore words[16];
    int count;
} Scored;
Scored score_move(const Board *board, const Move *move, const Counts values);
typedef struct {
    int64_t state;
} Minstd;
int64_t random_next(Minstd *random);
typedef struct {
    char tiles[201];
    int count;
} Bag;
void shuffle(Bag *bag, Minstd *random);
Bag make_bag(const Counts counts, Minstd *random);
void draw(Bag *bag, int count, char *out);
void exchange(Bag *bag, const char *returned, Minstd *random, char *drawn);
int points(const char *collection, const Counts values);
#endif
