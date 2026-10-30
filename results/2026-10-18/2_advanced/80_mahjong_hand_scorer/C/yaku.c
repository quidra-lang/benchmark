#include "mahjong.h"

const YakuDefinition yaku_table[YAKU_COUNT] = {{"riichi", 1, 0},          {"double_riichi", 2, 0},
                                               {"ippatsu", 1, 0},         {"menzen_tsumo", 1, 0},
                                               {"pinfu", 1, 0},           {"tanyao", 1, 1},
                                               {"iipeikou", 1, 0},        {"haku", 1, 1},
                                               {"hatsu", 1, 1},           {"chun", 1, 1},
                                               {"jikaze", 1, 1},          {"bakaze", 1, 1},
                                               {"haitei", 1, 1},          {"houtei", 1, 1},
                                               {"rinshan", 1, 1},         {"chankan", 1, 1},
                                               {"chiitoitsu", 2, 0},      {"toitoi", 2, 2},
                                               {"sanankou", 2, 2},        {"sanshoku_doujun", 2, 1},
                                               {"sanshoku_doukou", 2, 2}, {"ittsu", 2, 1},
                                               {"chanta", 2, 1},          {"sankantsu", 2, 2},
                                               {"shousangen", 2, 2},      {"honroutou", 2, 2},
                                               {"honitsu", 3, 2},         {"junchan", 3, 2},
                                               {"ryanpeikou", 3, 0},      {"chinitsu", 6, 5}};
const Award yakuman_table[YAKUMAN_COUNT] = {
    {"tenhou", 1},     {"chiihou", 1},        {"kokushi", 1},    {"kokushi_13", 2},
    {"suuankou", 1},   {"suuankou_tanki", 2}, {"daisangen", 1},  {"shousuushii", 1},
    {"daisuushii", 2}, {"tsuuiisou", 1},      {"chinroutou", 1}, {"ryuuiisou", 1},
    {"chuuren", 1},    {"junsei_chuuren", 2}, {"suukantsu", 1}};
const char *const flag_names[FLAG_COUNT] = {"riichi",  "double_riichi", "ippatsu",
                                            "haitei",  "houtei",        "rinshan",
                                            "chankan", "tenhou",        "chiihou"};
const char *const category_names[LIMIT_COUNT] = {"none",      "mangan",        "haneman", "baiman",
                                                 "sanbaiman", "kazoe_yakuman", "yakuman"};
const char *const wait_names[WAIT_COUNT] = {"ryanmen", "kanchan", "penchan", "shanpon",
                                            "tanki",   "single",  "thirteen"};
Awards yaku_awards(const bool holds[YAKU_COUNT], bool closed) {
    Awards result = {0};
    for (int i = 0; i < YAKU_COUNT; ++i) {
        int value = closed ? yaku_table[i].closed : yaku_table[i].open;
        if (holds[i] && value > 0)
            result.items[result.count++] = (Award){yaku_table[i].name, value};
    }
    return result;
}
Awards yakuman_awards(const bool holds[YAKUMAN_COUNT], bool double_yakuman) {
    Awards result = {0};
    for (int i = 0; i < YAKUMAN_COUNT; ++i)
        if (holds[i])
            result.items[result.count++] =
                (Award){yakuman_table[i].name, double_yakuman ? yakuman_table[i].value : 1};
    return result;
}
