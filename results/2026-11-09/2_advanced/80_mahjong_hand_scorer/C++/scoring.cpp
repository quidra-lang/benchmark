#include "mahjong.hpp"

int pairFu(int pair, int seat, int round) {
    return (pair >= 31 ? 2 : 0) + (pair == seat ? 2 : 0) + (pair == round ? 2 : 0);
}
bool concealed(const Block &block, const std::string &by) {
    return block.source == 'A' || block.source == 'c' && (!block.winning || by == "tsumo");
}
void fuBreakdown(Candidate &candidate, const Situation &situation, bool closed, bool pinfu) {
    if (candidate.kind == "chiitoitsu") {
        candidate.fuItems = {{"chiitoitsu", 25}};
        candidate.fuTotal = candidate.fu = 25;
        return;
    }
    std::vector<Award> items = {{"base", 20}};
    if (closed && situation.by == "ron")
        items.push_back({"closed_ron", 10});
    if (situation.by == "tsumo" && !pinfu)
        items.push_back({"tsumo", 2});
    int pair = pairFu(candidate.pair, windKind(situation.seat), windKind(situation.round));
    if (pair > 0)
        items.push_back({"pair " + blockNotation(candidate.pair, 2, false), pair});
    for (const Block &block : candidate.blocks) {
        if (block.sequence)
            continue;
        bool hidden = concealed(block, situation.by);
        std::string type = hidden ? "closed_triplet" : "open_triplet";
        int value = hidden ? 4 : 2;
        if (block.kan) {
            type = hidden ? "closed_kan" : "open_kan";
            value = hidden ? 16 : 8;
        }
        if (yaochuu(block.kind))
            value *= 2;
        items.push_back({type + " " + block.notation(), value});
    }
    if (candidate.wait == "kanchan" || candidate.wait == "penchan" || candidate.wait == "tanki")
        items.push_back({"wait " + candidate.wait, 2});
    int total = 0;
    for (const Award &award : items)
        total += award.value;
    if (!closed && total == 20) {
        items.push_back({"open_pinfu", 10});
        total += 10;
    }
    candidate.fuItems = items;
    candidate.fuTotal = total;
    candidate.fu = (total + 9) / 10 * 10;
}
std::pair<std::string, int> limitScore(int han, int fu, const Rule &rule) {
    if (han >= 13 && rule.kazoe)
        return {"kazoe_yakuman", 8000};
    if (han >= 11)
        return {"sanbaiman", 6000};
    if (han >= 8)
        return {"baiman", 4000};
    if (han >= 6)
        return {"haneman", 3000};
    int base = fu * (1 << (han + 2));
    if (han == 5 || base >= 2000 || rule.kiriage && base == 1920)
        return {"mangan", 2000};
    return {"none", base};
}
int roundHundred(int value) { return (value + 99) / 100 * 100; }
Payment payments(int base, const std::string &seat, const std::string &by) {
    Payment p;
    if (by == "ron") {
        p.ron = roundHundred((seat == "E" ? 6 : 4) * base);
        p.points = p.ron;
    } else if (seat == "E") {
        p.all = roundHundred(2 * base);
        p.points = 3 * p.all;
    } else {
        p.dealer = roundHundred(2 * base);
        p.nondealer = roundHundred(base);
        p.points = p.dealer + 2 * p.nondealer;
    }
    return p;
}
