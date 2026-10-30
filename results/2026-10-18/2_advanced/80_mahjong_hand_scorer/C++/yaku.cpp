#include "mahjong.hpp"

const std::vector<YakuDefinition> yakuTable = {{"riichi", 1, 0},          {"double_riichi", 2, 0},
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
const std::vector<Award> yakumanTable = {
    {"tenhou", 1},     {"chiihou", 1},        {"kokushi", 1},    {"kokushi_13", 2},
    {"suuankou", 1},   {"suuankou_tanki", 2}, {"daisangen", 1},  {"shousuushii", 1},
    {"daisuushii", 2}, {"tsuuiisou", 1},      {"chinroutou", 1}, {"ryuuiisou", 1},
    {"chuuren", 1},    {"junsei_chuuren", 2}, {"suukantsu", 1}};
const std::vector<std::string> flagsOrder = {"riichi",  "double_riichi", "ippatsu",
                                             "haitei",  "houtei",        "rinshan",
                                             "chankan", "tenhou",        "chiihou"};
const std::vector<std::string> categories = {"none",      "mangan",        "haneman", "baiman",
                                             "sanbaiman", "kazoe_yakuman", "yakuman"};
const std::vector<std::string> waitShapes = {"ryanmen", "kanchan", "penchan", "shanpon",
                                             "tanki",   "single",  "thirteen"};
std::vector<Award> yakuAwards(const std::set<std::string> &holds, bool closed) {
    std::vector<Award> result;
    for (const YakuDefinition &definition : yakuTable) {
        int value = closed ? definition.closed : definition.open;
        if (value > 0 && holds.count(definition.name))
            result.push_back({definition.name, value});
    }
    return result;
}
std::vector<Award> yakumanAwards(const std::set<std::string> &holds, bool doubleYakuman) {
    std::vector<Award> result;
    for (const Award &award : yakumanTable)
        if (holds.count(award.name))
            result.push_back({award.name, doubleYakuman ? award.value : 1});
    return result;
}
