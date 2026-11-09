#pragma once
#include <array>
#include <map>
#include <set>
#include <string>
#include <unordered_map>
#include <utility>
#include <vector>

using Counts = std::array<int, 34>;
struct Tiles {
    Counts counts{};
    std::array<int, 3> reds{};
    int size = 0;
};
struct Rule {
    std::string name;
    bool openTanyao = false, red = false, doubleYakuman = false, kazoe = false, kiriage = false;
    int honba = 0;
};
struct Block {
    int kind = 0;
    bool sequence = false, kan = false, winning = false;
    char source = 'c';
    std::string notation() const;
};
struct Meld {
    char type = 0;
    Tiles tiles;
    Block block;
    bool valid = false;
};
struct Situation {
    std::string label, by, seat, from, round;
    const Rule *rule = nullptr;
    Tiles hand, win, dora, ura, discards;
    std::vector<Meld> melds;
    std::set<std::string> flags;
    int honba = 0, sticks = 0;
    bool notation = true;
    bool closed() const;
    Tiles allTiles() const;
};
struct Award {
    std::string name;
    int value;
};
struct YakuDefinition {
    std::string name;
    int closed, open;
};
struct Candidate {
    std::string kind, form, wait, category = "none";
    int pair = 0;
    std::vector<Block> sets, blocks;
    std::vector<Award> yaku, yakuman, fuItems;
    int multiplier = 0, dora = 0, aka = 0, ura = 0, han = 0, fuTotal = 0, fu = 0, base = 0;
};
struct Decomposition {
    int pair;
    std::vector<Block> sets;
};
struct Payment {
    int points = 0, ron = 0, dealer = 0, nondealer = 0, all = 0;
};
extern const std::vector<YakuDefinition> yakuTable;
extern const std::vector<Award> yakumanTable;
extern const std::vector<std::string> flagsOrder, categories, waitShapes;
bool parseTiles(const std::string &, bool, Tiles &);
Tiles combineTiles(const Tiles &, const Tiles &);
Tiles addKind(Tiles, int);
std::string tileName(int);
std::string blockNotation(int, int, bool);
bool honor(int);
bool terminal(int);
bool yaochuu(int);
int nextDora(int);
int windKind(const std::string &);
std::vector<Decomposition> standardDecompositions(Counts, int);
bool sevenPairs(const Counts &, int);
bool thirteenOrphans(const Counts &, int);
bool winningForm(const Counts &, int);
std::vector<int> waitingTiles(const Tiles &, const std::vector<Meld> &);
std::string waitShape(const Block &, int);
std::vector<Award> yakuAwards(const std::set<std::string> &, bool);
std::vector<Award> yakumanAwards(const std::set<std::string> &, bool);
int pairFu(int, int, int);
bool concealed(const Block &, const std::string &);
void fuBreakdown(Candidate &, const Situation &, bool, bool);
std::pair<std::string, int> limitScore(int, int, const Rule &);
int roundHundred(int);
Payment payments(int, const std::string &, const std::string &);
class Shanten {
    std::unordered_map<std::string, int> memo;
    int standard(Counts, int, int, int);

  public:
    std::array<int, 3> numbers(const Counts &);
};
int minimumShanten(const std::array<int, 3> &);
