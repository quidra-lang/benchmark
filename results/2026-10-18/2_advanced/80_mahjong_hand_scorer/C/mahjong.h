#ifndef MAHJONG_H
#define MAHJONG_H
#include <stdbool.h>
#include <stddef.h>
#include <stdint.h>

enum {
    Y_RIICHI,
    Y_DOUBLE_RIICHI,
    Y_IPPATSU,
    Y_MENZEN_TSUMO,
    Y_PINFU,
    Y_TANYAO,
    Y_IIPEIKOU,
    Y_HAKU,
    Y_HATSU,
    Y_CHUN,
    Y_JIKAZE,
    Y_BAKAZE,
    Y_HAITEI,
    Y_HOUTEI,
    Y_RINSHAN,
    Y_CHANKAN,
    Y_CHIITOITSU,
    Y_TOITOI,
    Y_SANANKOU,
    Y_SANSHOKU_DOUJUN,
    Y_SANSHOKU_DOUKOU,
    Y_ITTSU,
    Y_CHANTA,
    Y_SANKANTSU,
    Y_SHOUSANGEN,
    Y_HONROUTOU,
    Y_HONITSU,
    Y_JUNCHAN,
    Y_RYANPEIKOU,
    Y_CHINITSU,
    YAKU_COUNT
};
enum {
    M_TENHOU,
    M_CHIIHOU,
    M_KOKUSHI,
    M_KOKUSHI_13,
    M_SUUANKOU,
    M_SUUANKOU_TANKI,
    M_DAISANGEN,
    M_SHOUSUUSHII,
    M_DAISUUSHII,
    M_TSUUIISOU,
    M_CHINROUTOU,
    M_RYUUIISOU,
    M_CHUUREN,
    M_JUNSEI_CHUUREN,
    M_SUUKANTSU,
    YAKUMAN_COUNT
};
enum {
    F_RIICHI,
    F_DOUBLE_RIICHI,
    F_IPPATSU,
    F_HAITEI,
    F_HOUTEI,
    F_RINSHAN,
    F_CHANKAN,
    F_TENHOU,
    F_CHIIHOU,
    FLAG_COUNT
};
enum { W_RYANMEN, W_KANCHAN, W_PENCHAN, W_SHANPON, W_TANKI, W_SINGLE, W_THIRTEEN, WAIT_COUNT };
enum { L_NONE, L_MANGAN, L_HANEMAN, L_BAIMAN, L_SANBAIMAN, L_KAZOE, L_YAKUMAN, LIMIT_COUNT };
enum { FORM_STANDARD, FORM_CHIITOITSU, FORM_KOKUSHI };
typedef struct {
    int values[34];
} Counts;
typedef struct {
    Counts counts;
    int reds[3];
    int size;
} Tiles;
typedef struct {
    char name;
    bool open_tanyao, red, double_yakuman, kazoe, kiriage;
    int honba;
} Rule;
typedef struct {
    int kind;
    bool sequence, kan, winning;
    char source;
} Block;
typedef struct {
    char type;
    Tiles tiles;
    Block block;
    bool valid;
} Meld;
typedef struct {
    char *label;
    const Rule *rule;
    Tiles hand, win, dora, ura, discards;
    Meld *melds;
    size_t meld_count;
    char by, seat, from, round;
    bool flags[FLAG_COUNT], notation;
    int honba, sticks;
} Situation;
typedef struct {
    const char *name;
    int value;
} Award;
typedef struct {
    Award items[YAKU_COUNT];
    int count;
} Awards;
typedef struct {
    const char *name;
    int closed, open;
} YakuDefinition;
typedef struct {
    char name[64];
    int value;
} FuItem;
typedef struct {
    int kind, pair, wait, category;
    char form[256];
    Block sets[4], blocks[4];
    int set_count, block_count;
    Awards yaku, yakuman;
    FuItem fu_items[10];
    int fu_count, multiplier, dora, aka, ura, han, fu_total, fu, base;
} Candidate;
typedef struct {
    Candidate *items;
    size_t count, capacity;
} Candidates;
typedef struct {
    int pair;
    Block sets[4];
    int count;
} Decomposition;
typedef struct {
    Decomposition *items;
    size_t count, capacity;
} Decompositions;
typedef struct {
    int points, ron, dealer, nondealer, all;
} Payment;
typedef struct {
    unsigned char key[37];
    int value;
    bool used;
} ShantenEntry;
typedef struct {
    ShantenEntry *entries;
    size_t count, capacity;
} Shanten;
typedef struct {
    int standard, chiitoitsu, kokushi;
} ShantenNumbers;
extern const YakuDefinition yaku_table[YAKU_COUNT];
extern const Award yakuman_table[YAKUMAN_COUNT];
extern const char *const flag_names[FLAG_COUNT], *const category_names[LIMIT_COUNT],
                                                     *const wait_names[WAIT_COUNT];
void *checked_realloc(void *, size_t);
bool parse_tiles(const char *, bool, Tiles *);
Tiles combine_tiles(Tiles, Tiles);
Tiles add_kind(Tiles, int);
void tile_name(int, char[3]);
void block_notation(int, int, bool, char[6]);
void block_name(Block, char[6]);
bool honor(int);
bool terminal(int);
bool yaochuu(int);
int next_dora(int);
int wind_kind(char);
Decompositions standard_decompositions(Counts, int);
bool seven_pairs(Counts, int);
bool thirteen_orphans(Counts, int);
bool winning_form(Counts, int);
int waiting_tiles(Tiles, const Meld *, size_t, int[34]);
int wait_shape(Block, int);
Awards yaku_awards(const bool[YAKU_COUNT], bool);
Awards yakuman_awards(const bool[YAKUMAN_COUNT], bool);
int pair_fu(int, int, int);
bool concealed(Block, char);
void fu_breakdown(Candidate *, const Situation *, bool, bool);
void limit_score(int, int, const Rule *, int *, int *);
int round_hundred(int);
Payment payments(int, char, char);
ShantenNumbers shanten_numbers(Shanten *, Counts);
void shanten_free(Shanten *);
int minimum_shanten(ShantenNumbers);
#endif
