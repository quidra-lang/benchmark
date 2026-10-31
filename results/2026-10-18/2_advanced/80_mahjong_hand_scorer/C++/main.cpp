#include "mahjong.hpp"
#include <algorithm>
#include <filesystem>
#include <fstream>
#include <sstream>
#include <stdexcept>

using Record = std::pair<std::string, std::map<std::string, std::string>>;
std::vector<std::string> split(const std::string &text, char separator) {
    std::vector<std::string> out;
    std::size_t start = 0;
    for (;;) {
        std::size_t end = text.find(separator, start);
        if (end == std::string::npos) {
            out.push_back(text.substr(start));
            return out;
        }
        out.push_back(text.substr(start, end - start));
        start = end + 1;
    }
}
std::vector<std::string> readLines(const std::string &path) {
    std::ifstream file(path);
    if (!file)
        throw std::runtime_error("cannot read " + path);
    std::vector<std::string> result;
    std::string line;
    while (std::getline(file, line))
        result.push_back(line);
    return result;
}
Record readRecord(const std::string &line) {
    std::istringstream stream(line);
    Record record;
    stream >> record.first;
    std::string part;
    while (stream >> part) {
        std::size_t equal = part.find('=');
        record.second[part.substr(0, equal)] = part.substr(equal + 1);
    }
    return record;
}
std::string join(const std::vector<std::string> &parts, const std::string &separator) {
    std::string result;
    for (std::size_t i = 0; i < parts.size(); ++i) {
        if (i > 0)
            result += separator;
        result += parts[i];
    }
    return result;
}
std::string awardNames(const std::vector<Award> &awards, const std::string &separator) {
    std::vector<std::string> names;
    for (const Award &award : awards)
        names.push_back(award.name);
    return join(names, separator);
}
int windKind(const std::string &wind) { return 27 + int(std::string("ESWN").find(wind)); }
bool Situation::closed() const {
    for (const Meld &meld : melds)
        if (meld.type != 'A')
            return false;
    return true;
}
Tiles Situation::allTiles() const {
    Tiles result = combineTiles(hand, win);
    for (const Meld &meld : melds)
        result = combineTiles(result, meld.tiles);
    return result;
}
std::string checkCopies(const Tiles &tiles, const Rule &rule) {
    if (!rule.red && tiles.reds[0] + tiles.reds[1] + tiles.reds[2] > 0)
        return "red five not allowed";
    for (int kind = 0; kind < 34; ++kind)
        if (tiles.counts[kind] > 4)
            return "too many copies of " + tileName(kind);
    for (int suit = 0; suit < 3; ++suit)
        if (tiles.reds[suit] > 1)
            return std::string("too many copies of 0") + "mps"[suit];
    return "";
}
Meld readMeld(const std::string &text, bool &notation) {
    Meld meld;
    meld.type = text[0];
    if (!parseTiles(text.substr(1), false, meld.tiles)) {
        notation = false;
        return meld;
    }
    int first = 0;
    while (meld.tiles.counts[first] == 0)
        ++first;
    meld.block.kind = first;
    meld.block.source = meld.type;
    if (meld.type == 'C') {
        meld.block.sequence = true;
        meld.valid = meld.tiles.size == 3 && first < 27 && first % 9 <= 6 &&
                     meld.tiles.counts[first] == 1 && meld.tiles.counts[first + 1] == 1 &&
                     meld.tiles.counts[first + 2] == 1;
    } else if (meld.type == 'P')
        meld.valid = meld.tiles.size == 3 && meld.tiles.counts[first] == 3;
    else if (meld.type == 'K' || meld.type == 'A') {
        meld.block.kan = true;
        meld.valid = meld.tiles.size == 4 && meld.tiles.counts[first] == 4;
    }
    return meld;
}
Situation readSituation(const Record &record, const Rule &rule) {
    const std::map<std::string, std::string> &a = record.second;
    Situation s;
    s.label = record.first;
    s.rule = &rule;
    s.by = a.at("by");
    s.seat = a.at("seat");
    s.from = a.at("from");
    s.round = a.at("round");
    s.honba = std::stoi(a.at("honba"));
    s.sticks = std::stoi(a.at("sticks"));
    bool valid = parseTiles(a.at("hand"), false, s.hand);
    s.notation = s.notation && valid;
    valid = parseTiles(a.at("win"), false, s.win);
    s.notation = s.notation && valid;
    valid = parseTiles(a.at("dora"), false, s.dora);
    s.notation = s.notation && valid;
    valid = parseTiles(a.at("ura"), true, s.ura);
    s.notation = s.notation && valid;
    valid = parseTiles(a.at("discards"), true, s.discards);
    s.notation = s.notation && valid;
    if (a.at("melds") != "-")
        for (const std::string &text : split(a.at("melds"), ','))
            s.melds.push_back(readMeld(text, s.notation));
    if (a.at("flags") != "-")
        for (const std::string &flag : split(a.at("flags"), ','))
            s.flags.insert(flag);
    return s;
}
std::string checkSituation(const Situation &s) {
    if (!s.notation || s.win.size != 1)
        return "bad tile notation";
    if (s.melds.size() > 4)
        return "bad meld";
    int kans = 0;
    for (const Meld &meld : s.melds) {
        if (!meld.valid)
            return "bad meld";
        if (meld.block.kan)
            ++kans;
    }
    if (s.hand.size != 13 - 3 * int(s.melds.size()))
        return "wrong tile count";
    std::string error = checkCopies(
        combineTiles(combineTiles(combineTiles(s.allTiles(), s.dora), s.ura), s.discards), *s.rule);
    if (!error.empty())
        return error;
    if (s.by == "tsumo" && s.from != "-" || s.by == "ron" && (s.from == "-" || s.from == s.seat))
        return "invalid discarder";
    bool riichi = s.flags.count("riichi") || s.flags.count("double_riichi");
    for (const std::string &flag : flagsOrder) {
        if (!s.flags.count(flag))
            continue;
        bool valid = true;
        if (flag == "riichi")
            valid = s.closed();
        else if (flag == "double_riichi")
            valid = s.closed() && !s.flags.count("riichi");
        else if (flag == "ippatsu")
            valid = riichi && !s.flags.count("rinshan");
        else if (flag == "haitei")
            valid = s.by == "tsumo" && !s.flags.count("rinshan");
        else if (flag == "houtei")
            valid = s.by == "ron" && !s.flags.count("chankan");
        else if (flag == "rinshan")
            valid = s.by == "tsumo" && kans > 0;
        else if (flag == "chankan")
            valid = s.by == "ron";
        else if (flag == "tenhou")
            valid = s.seat == "E" && s.by == "tsumo" && s.melds.empty() && s.flags.size() == 1;
        else if (flag == "chiihou")
            valid = s.seat != "E" && s.by == "tsumo" && s.melds.empty() && s.flags.size() == 1;
        if (!valid)
            return "invalid flag " + flag;
    }
    if (s.dora.size != 1 + kans)
        return "invalid dora indicators";
    if (riichi && s.ura.size != s.dora.size || !riichi && s.ura.size != 0)
        return "invalid ura indicators";
    if (riichi && s.sticks == 0)
        return "invalid sticks";
    if (!winningForm(combineTiles(s.hand, s.win).counts, int(s.melds.size())))
        return "not a winning hand";
    return "";
}
void evaluateCandidate(Candidate &c, const Situation &s) {
    Tiles all = s.allTiles();
    bool closed = s.closed();
    std::set<std::string> yaku, yakuman;
    bool allSimple = true, allYao = true, allHonor = true, allTerminal = true, allGreen = true,
         hasHonor = false;
    int suitMask = 0;
    const std::set<int> green = {19, 20, 21, 23, 25, 32};
    for (int kind = 0; kind < 34; ++kind) {
        if (all.counts[kind] == 0)
            continue;
        allSimple = allSimple && !yaochuu(kind);
        allYao = allYao && yaochuu(kind);
        allTerminal = allTerminal && terminal(kind);
        allGreen = allGreen && green.count(kind);
        if (honor(kind))
            hasHonor = true;
        else {
            allHonor = false;
            suitMask |= 1 << (kind / 9);
        }
    }
    for (const std::string &name :
         {"riichi", "double_riichi", "ippatsu", "haitei", "houtei", "rinshan", "chankan"})
        if (s.flags.count(name))
            yaku.insert(name);
    if (closed && s.by == "tsumo")
        yaku.insert("menzen_tsumo");
    if (allSimple && (closed || s.rule->openTanyao))
        yaku.insert("tanyao");
    if (allYao)
        yaku.insert("honroutou");
    bool oneSuit = suitMask != 0 && (suitMask & (suitMask - 1)) == 0;
    if (oneSuit)
        yaku.insert(hasHonor ? "honitsu" : "chinitsu");
    if (s.flags.count("tenhou"))
        yakuman.insert("tenhou");
    if (s.flags.count("chiihou"))
        yakuman.insert("chiihou");
    if (allHonor)
        yakuman.insert("tsuuiisou");
    if (allTerminal)
        yakuman.insert("chinroutou");
    if (allGreen)
        yakuman.insert("ryuuiisou");
    if (s.melds.empty() && oneSuit && !hasHonor) {
        int suit = 0;
        while (((suitMask >> suit) & 1) == 0)
            ++suit;
        bool chuuren = true, pure = true;
        for (int rank = 0; rank < 9; ++rank) {
            int required = rank == 0 || rank == 8 ? 3 : 1;
            chuuren = chuuren && all.counts[suit * 9 + rank] >= required;
            pure = pure && s.hand.counts[suit * 9 + rank] == required;
        }
        if (chuuren)
            yakuman.insert(pure ? "junsei_chuuren" : "chuuren");
    }
    if (c.kind == "chiitoitsu")
        yaku.insert("chiitoitsu");
    else if (c.kind == "kokushi")
        yakuman.insert(c.wait == "thirteen" ? "kokushi_13" : "kokushi");
    else {
        std::set<int> triplets, sequences;
        int concealedCount = 0, kans = 0, dragons = 0, winds = 0;
        bool allBlocksYao = yaochuu(c.pair);
        for (const Block &block : c.blocks) {
            if (block.sequence) {
                sequences.insert(block.kind);
                allBlocksYao = allBlocksYao && (block.kind % 9 == 0 || block.kind % 9 == 6);
            } else {
                triplets.insert(block.kind);
                if (concealed(block, s.by))
                    ++concealedCount;
                if (block.kan)
                    ++kans;
                if (block.kind >= 31)
                    ++dragons;
                else if (block.kind >= 27)
                    ++winds;
                allBlocksYao = allBlocksYao && yaochuu(block.kind);
            }
        }
        std::map<int, int> closedSequences;
        bool allSequences = c.sets.size() == 4;
        for (const Block &block : c.sets) {
            if (block.sequence)
                ++closedSequences[block.kind];
            else
                allSequences = false;
        }
        int pairs = 0;
        bool duplicate = false;
        for (const std::pair<const int, int> &entry : closedSequences) {
            pairs += entry.second / 2;
            duplicate = duplicate || entry.second >= 2;
        }
        if (closed && s.melds.empty() && allSequences &&
            pairFu(c.pair, windKind(s.seat), windKind(s.round)) == 0 && c.wait == "ryanmen")
            yaku.insert("pinfu");
        if (closed && allSequences && pairs == 2)
            yaku.insert("ryanpeikou");
        if (closed && !yaku.count("ryanpeikou") && duplicate)
            yaku.insert("iipeikou");
        if (triplets.count(31))
            yaku.insert("haku");
        if (triplets.count(32))
            yaku.insert("hatsu");
        if (triplets.count(33))
            yaku.insert("chun");
        if (triplets.count(windKind(s.seat)))
            yaku.insert("jikaze");
        if (triplets.count(windKind(s.round)))
            yaku.insert("bakaze");
        if (triplets.size() == 4)
            yaku.insert("toitoi");
        if (concealedCount == 3)
            yaku.insert("sanankou");
        for (int rank = 0; rank < 9; ++rank) {
            if (rank <= 6 && sequences.count(rank) && sequences.count(9 + rank) &&
                sequences.count(18 + rank))
                yaku.insert("sanshoku_doujun");
            if (triplets.count(rank) && triplets.count(9 + rank) && triplets.count(18 + rank))
                yaku.insert("sanshoku_doukou");
        }
        for (int suit = 0; suit < 3; ++suit)
            if (sequences.count(suit * 9) && sequences.count(suit * 9 + 3) &&
                sequences.count(suit * 9 + 6))
                yaku.insert("ittsu");
        if (!sequences.empty() && allBlocksYao)
            yaku.insert(hasHonor ? "chanta" : "junchan");
        if (kans == 3)
            yaku.insert("sankantsu");
        if (dragons == 2 && c.pair >= 31)
            yaku.insert("shousangen");
        if (concealedCount == 4)
            yakuman.insert(c.wait == "tanki" ? "suuankou_tanki" : "suuankou");
        if (dragons == 3)
            yakuman.insert("daisangen");
        if (winds == 4)
            yakuman.insert("daisuushii");
        if (winds == 3 && c.pair >= 27 && c.pair <= 30)
            yakuman.insert("shousuushii");
        if (kans == 4)
            yakuman.insert("suukantsu");
    }
    c.yakuman = yakumanAwards(yakuman, s.rule->doubleYakuman);
    if (!c.yakuman.empty()) {
        for (const Award &award : c.yakuman)
            c.multiplier += award.value;
        c.category = "yakuman";
        c.base = 8000 * c.multiplier;
        return;
    }
    c.yaku = yakuAwards(yaku, closed);
    for (int kind = 0; kind < 34; ++kind) {
        c.dora += s.dora.counts[kind] * all.counts[nextDora(kind)];
        c.ura += s.ura.counts[kind] * all.counts[nextDora(kind)];
    }
    c.aka = all.reds[0] + all.reds[1] + all.reds[2];
    c.han = c.dora + c.ura + c.aka;
    for (const Award &award : c.yaku)
        c.han += award.value;
    fuBreakdown(c, s, closed, yaku.count("pinfu"));
    if (!c.yaku.empty()) {
        std::pair<std::string, int> score = limitScore(c.han, c.fu, *s.rule);
        c.category = score.first;
        c.base = score.second;
    }
}
std::vector<Candidate> makeCandidates(const Situation &s) {
    Counts counts = combineTiles(s.hand, s.win).counts;
    int win = 0;
    while (s.win.counts[win] == 0)
        ++win;
    std::vector<Candidate> result;
    for (const Decomposition &decomposition : standardDecompositions(counts, int(s.melds.size()))) {
        std::set<std::string> seen;
        for (int winning = -1; winning < int(decomposition.sets.size()); ++winning) {
            if (winning < 0) {
                if (decomposition.pair != win)
                    continue;
            } else {
                const Block &block = decomposition.sets[winning];
                if (block.sequence ? win < block.kind || win > block.kind + 2 : win != block.kind)
                    continue;
            }
            std::string shape = winning < 0 ? blockNotation(decomposition.pair, 2, false)
                                            : decomposition.sets[winning].notation();
            if (!seen.insert(shape).second)
                continue;
            Candidate c;
            c.kind = "standard";
            c.pair = decomposition.pair;
            c.wait = "tanki";
            c.sets = decomposition.sets;
            if (winning >= 0) {
                c.sets[winning].winning = true;
                c.wait = waitShape(c.sets[winning], win);
            }
            c.form = "standard " + blockNotation(c.pair, 2, false) + (winning < 0 ? "*" : "");
            for (const Block &block : c.sets)
                c.form += " " + block.notation() + (block.winning ? "*" : "");
            c.blocks = c.sets;
            for (const Meld &meld : s.melds) {
                c.form += " " + std::string(1, meld.type) + meld.block.notation();
                c.blocks.push_back(meld.block);
            }
            result.push_back(c);
        }
    }
    if (sevenPairs(counts, int(s.melds.size()))) {
        Candidate c;
        c.kind = "chiitoitsu";
        c.wait = "tanki";
        c.form = "chiitoitsu";
        for (int kind = 0; kind < 34; ++kind)
            if (counts[kind] == 2)
                c.form += " " + blockNotation(kind, 2, false) + (kind == win ? "*" : "");
        result.push_back(c);
    }
    if (thirteenOrphans(counts, int(s.melds.size()))) {
        Candidate c;
        c.kind = "kokushi";
        c.wait = "thirteen";
        c.form = "kokushi";
        for (int kind = 0; kind < 34; ++kind)
            if (counts[kind] > 0) {
                c.form += " " + blockNotation(kind, counts[kind], false) + (kind == win ? "*" : "");
                if (s.hand.counts[kind] != 1)
                    c.wait = "single";
            }
        result.push_back(c);
    }
    std::sort(result.begin(), result.end(),
              [](const Candidate &a, const Candidate &b) { return a.form < b.form; });
    for (Candidate &candidate : result)
        evaluateCandidate(candidate, s);
    return result;
}
const Candidate *bestCandidate(const std::vector<Candidate> &candidates) {
    const Candidate *best = nullptr;
    for (const Candidate &c : candidates) {
        if (c.base <= 0)
            continue;
        bool better = best == nullptr;
        if (best) {
            if (c.base != best->base)
                better = c.base > best->base;
            else if ((c.multiplier > 0) != (best->multiplier > 0))
                better = c.multiplier > 0;
            else if (c.multiplier == 0 && c.han != best->han)
                better = c.han > best->han;
            else if (c.multiplier == 0 && c.fu != best->fu)
                better = c.fu > best->fu;
            else
                better = c.form < best->form;
        }
        if (better)
            best = &c;
    }
    return best;
}
std::string candidateText(const Candidate &candidate) {
    if (candidate.multiplier > 0)
        return "yakuman " + std::to_string(candidate.multiplier) + " base " +
               std::to_string(candidate.base) + " yaku " + awardNames(candidate.yakuman, ",");
    if (candidate.base == 0)
        return "no_yaku";
    return "han " + std::to_string(candidate.han) + " fu " + std::to_string(candidate.fu) +
           " base " + std::to_string(candidate.base) + " yaku " + awardNames(candidate.yaku, ",");
}
std::string signedPoints(int n) { return n > 0 ? "+" + std::to_string(n) : std::to_string(n); }
void save(const std::string &name, const std::vector<std::string> &lines) {
    std::ofstream file("output/" + name);
    if (!file)
        throw std::runtime_error("cannot write " + name);
    for (const std::string &line : lines)
        file << line << '\n';
}
struct RuleStatistics {
    int hands = 0, wins = 0, points = 0;
};
void processScores(const std::vector<Rule> &rules,
                   const std::map<std::string, const Rule *> &ruleNames) {
    std::vector<std::string> output, summary = {"hand,han,fu,points,yaku"};
    std::map<std::string, int> results, winMethods, waits, limits, yakuCounts;
    std::map<int, int> hanCounts, fuCounts;
    std::map<std::string, RuleStatistics> ruleStats;
    int total = 0, maximum = 0, hands = 0;
    std::string maximumLabel = "-";
    for (const std::string &line : readLines("input/hands.txt")) {
        Record record = readRecord(line);
        Situation s = readSituation(record, *ruleNames.at(record.second.at("rules")));
        ++hands;
        ++ruleStats[s.rule->name].hands;
        output.push_back("HAND " + s.label);
        std::string error = checkSituation(s);
        if (!error.empty()) {
            ++results["errors"];
            output.push_back("ERROR " + error);
            summary.push_back(s.label + ",-,-,0,ERROR");
            continue;
        }
        std::vector<int> waiting = waitingTiles(s.hand, s.melds);
        std::vector<std::string> names;
        for (int kind : waiting)
            names.push_back(tileName(kind));
        output.push_back("WAITS " + join(names, " "));
        std::vector<Candidate> candidates = makeCandidates(s);
        for (const Candidate &candidate : candidates)
            output.push_back("CANDIDATE " + candidate.form + " = " + candidate.wait + " " +
                             candidateText(candidate));
        bool furiten = false;
        if (s.by == "ron")
            for (int kind : waiting)
                furiten = furiten || s.discards.counts[kind] > 0;
        if (furiten) {
            ++results["furiten"];
            output.push_back("RESULT furiten");
            summary.push_back(s.label + ",-,-,0,FURITEN");
            continue;
        }
        const Candidate *best = bestCandidate(candidates);
        if (!best) {
            ++results["no_yaku"];
            output.push_back("RESULT no_yaku");
            summary.push_back(s.label + ",-,-,0,NO_YAKU");
            continue;
        }
        const Candidate &c = *best;
        ++results["wins"];
        ++winMethods[(s.seat == "E" ? "dealer_" : "nondealer_") + s.by];
        ++waits[c.wait];
        ++limits[c.category];
        output.push_back("FORM " + c.form);
        output.push_back("WAIT " + c.wait);
        if (c.multiplier > 0) {
            for (const Award &award : c.yakuman) {
                output.push_back("YAKUMAN " + award.name + " " + std::to_string(award.value));
                ++yakuCounts[award.name];
            }
            output.push_back("SCORE yakuman " + std::to_string(c.multiplier) + " base " +
                             std::to_string(c.base));
        } else {
            ++hanCounts[c.han];
            ++fuCounts[c.fu];
            for (const Award &award : c.yaku) {
                output.push_back("YAKU " + award.name + " " + std::to_string(award.value));
                ++yakuCounts[award.name];
            }
            output.push_back("DORA dora " + std::to_string(c.dora) + " aka " +
                             std::to_string(c.aka) + " ura " + std::to_string(c.ura));
            for (const Award &award : c.fuItems)
                output.push_back("FU " + award.name + " " + std::to_string(award.value));
            output.push_back("FU total " + std::to_string(c.fuTotal) + " " + std::to_string(c.fu));
            output.push_back("SCORE han " + std::to_string(c.han) + " fu " + std::to_string(c.fu) +
                             " limit " + c.category + " base " + std::to_string(c.base));
        }
        Payment payment = payments(c.base, s.seat, s.by);
        int honba = s.honba * s.rule->honba, sticks = s.sticks * 1000,
            gain = payment.points + honba + sticks;
        if (s.by == "ron")
            output.push_back("PAY ron " + std::to_string(payment.ron));
        else if (s.seat == "E")
            output.push_back("PAY tsumo all " + std::to_string(payment.all));
        else
            output.push_back("PAY tsumo dealer " + std::to_string(payment.dealer) + " nondealer " +
                             std::to_string(payment.nondealer));
        output.push_back("BONUS honba " + std::to_string(honba) + " sticks " +
                         std::to_string(sticks));
        output.push_back("TOTAL points " + std::to_string(payment.points) + " gain " +
                         std::to_string(gain));
        std::array<int, 4> delta{};
        int winner = windKind(s.seat) - 27;
        delta[winner] = gain;
        if (s.by == "ron")
            delta[windKind(s.from) - 27] = -payment.ron - honba;
        else
            for (int i = 0; i < 4; ++i)
                if (i != winner)
                    delta[i] = -(s.seat == "E" ? payment.all
                                 : i == 0      ? payment.dealer
                                               : payment.nondealer) -
                               honba / 3;
        output.push_back("DELTA E " + signedPoints(delta[0]) + " S " + signedPoints(delta[1]) +
                         " W " + signedPoints(delta[2]) + " N " + signedPoints(delta[3]));
        total += payment.points;
        if (payment.points > maximum) {
            maximum = payment.points;
            maximumLabel = s.label;
        }
        ++ruleStats[s.rule->name].wins;
        ruleStats[s.rule->name].points += payment.points;
        if (c.multiplier > 0)
            summary.push_back(s.label + ",Y" + std::to_string(c.multiplier) + ",-," +
                              std::to_string(payment.points) + "," + awardNames(c.yakuman, ";"));
        else
            summary.push_back(s.label + "," + std::to_string(c.han) + "," + std::to_string(c.fu) +
                              "," + std::to_string(payment.points) + "," + awardNames(c.yaku, ";"));
    }
    output.push_back(
        "STATS hands " + std::to_string(hands) + " wins " + std::to_string(results["wins"]) +
        " furiten " + std::to_string(results["furiten"]) + " no_yaku " +
        std::to_string(results["no_yaku"]) + " errors " + std::to_string(results["errors"]));
    output.push_back("WINS dealer_ron " + std::to_string(winMethods["dealer_ron"]) +
                     " dealer_tsumo " + std::to_string(winMethods["dealer_tsumo"]) +
                     " nondealer_ron " + std::to_string(winMethods["nondealer_ron"]) +
                     " nondealer_tsumo " + std::to_string(winMethods["nondealer_tsumo"]));
    std::string waitLine = "WAIT_COUNT";
    for (const std::string &shape : waitShapes)
        waitLine += " " + shape + " " + std::to_string(waits[shape]);
    output.push_back(waitLine);
    for (const std::pair<const int, int> &entry : hanCounts)
        output.push_back("HAN_COUNT " + std::to_string(entry.first) + " " +
                         std::to_string(entry.second));
    for (const std::pair<const int, int> &entry : fuCounts)
        output.push_back("FU_COUNT " + std::to_string(entry.first) + " " +
                         std::to_string(entry.second));
    for (const std::string &category : categories)
        output.push_back("LIMIT " + category + " " + std::to_string(limits[category]));
    for (const YakuDefinition &definition : yakuTable)
        if (yakuCounts[definition.name] > 0)
            output.push_back("YAKU_COUNT " + definition.name + " " +
                             std::to_string(yakuCounts[definition.name]));
    for (const Award &award : yakumanTable)
        if (yakuCounts[award.name] > 0)
            output.push_back("YAKU_COUNT " + award.name + " " +
                             std::to_string(yakuCounts[award.name]));
    output.push_back("POINTS total " + std::to_string(total) + " max " + std::to_string(maximum) +
                     " hand " + maximumLabel);
    for (const Rule &rule : rules) {
        const RuleStatistics &statistics = ruleStats[rule.name];
        output.push_back("RULE " + rule.name + " hands " + std::to_string(statistics.hands) +
                         " wins " + std::to_string(statistics.wins) + " points " +
                         std::to_string(statistics.points));
    }
    save("scores.txt", output);
    save("summary.csv", summary);
}
void processWaits(const std::map<std::string, const Rule *> &ruleNames) {
    std::vector<std::string> output;
    int hands = 0, errors = 0, tenpai = 0, furitenCount = 0;
    std::array<int, 7> histogram{};
    for (const std::string &line : readLines("input/waits.txt")) {
        Record record = readRecord(line);
        const std::map<std::string, std::string> &a = record.second;
        const Rule &rule = *ruleNames.at(a.at("rules"));
        ++hands;
        output.push_back("HAND " + record.first);
        Tiles hand, dora, discards, visible;
        bool notation = parseTiles(a.at("hand"), false, hand);
        bool valid = parseTiles(a.at("dora"), false, dora);
        notation = notation && valid;
        valid = parseTiles(a.at("discards"), true, discards);
        notation = notation && valid;
        valid = parseTiles(a.at("visible"), true, visible);
        notation = notation && valid;
        Tiles all = combineTiles(combineTiles(combineTiles(hand, dora), discards), visible);
        std::string error;
        if (!notation)
            error = "bad tile notation";
        else if (hand.size != 13)
            error = "wrong tile count";
        else
            error = checkCopies(all, rule);
        if (!error.empty()) {
            ++errors;
            output.push_back("ERROR " + error);
            continue;
        }
        Shanten shanten;
        std::array<int, 3> numbers = shanten.numbers(hand.counts);
        int minimum = minimumShanten(numbers);
        ++histogram[minimum];
        output.push_back("SHANTEN standard " + std::to_string(numbers[0]) + " chiitoitsu " +
                         std::to_string(numbers[1]) + " kokushi " + std::to_string(numbers[2]));
        std::vector<int> accepted;
        int remaining = 0;
        for (int kind = 0; kind < 34; ++kind)
            if (hand.counts[kind] < 4) {
                Counts counts = hand.counts;
                ++counts[kind];
                if (minimumShanten(shanten.numbers(counts)) < minimum) {
                    accepted.push_back(kind);
                    remaining += 4 - all.counts[kind];
                }
            }
        if (minimum > 0) {
            std::string text = "ACCEPT kinds " + std::to_string(accepted.size()) + " tiles " +
                               std::to_string(remaining);
            for (int kind : accepted)
                text += " " + tileName(kind) + ":" + std::to_string(4 - all.counts[kind]);
            output.push_back(text);
            continue;
        }
        ++tenpai;
        bool furiten = false;
        for (int kind : accepted)
            furiten = furiten || discards.counts[kind] > 0;
        if (furiten)
            ++furitenCount;
        output.push_back("TENPAI kinds " + std::to_string(accepted.size()) + " tiles " +
                         std::to_string(remaining) + " furiten " + (furiten ? "yes" : "no"));
        std::array<int, 2> bestPoints{};
        std::array<std::string, 2> bestTiles{};
        for (int kind : accepted) {
            std::array<std::string, 2> points;
            for (int method = 0; method < 2; ++method) {
                if (method == 0 && furiten) {
                    points[method] = "furiten";
                    continue;
                }
                Situation s;
                s.rule = &rule;
                s.hand = hand;
                s.win = addKind(Tiles{}, kind);
                s.dora = dora;
                s.seat = a.at("seat");
                s.round = a.at("round");
                s.by = method == 0 ? "ron" : "tsumo";
                if (a.at("riichi") == "yes")
                    s.flags.insert("riichi");
                std::vector<Candidate> candidates = makeCandidates(s);
                const Candidate *best = bestCandidate(candidates);
                if (!best) {
                    points[method] = "no_yaku";
                    continue;
                }
                int value = payments(best->base, s.seat, s.by).points;
                points[method] = std::to_string(value);
                if (value > bestPoints[method]) {
                    bestPoints[method] = value;
                    bestTiles[method] = tileName(kind);
                }
            }
            output.push_back("WAIT " + tileName(kind) + " left " +
                             std::to_string(4 - all.counts[kind]) + " ron " + points[0] +
                             " tsumo " + points[1]);
        }
        output.push_back(
            "BEST ron " +
            (bestPoints[0] > 0 ? bestTiles[0] + " " + std::to_string(bestPoints[0]) : "none") +
            " tsumo " +
            (bestPoints[1] > 0 ? bestTiles[1] + " " + std::to_string(bestPoints[1]) : "none"));
    }
    output.push_back("STATS hands " + std::to_string(hands) + " errors " + std::to_string(errors) +
                     " tenpai " + std::to_string(tenpai) + " furiten " +
                     std::to_string(furitenCount));
    for (int k = 0; k <= 6; ++k)
        output.push_back("SHANTEN_COUNT " + std::to_string(k) + " " + std::to_string(histogram[k]));
    save("waits.txt", output);
}
int main() {
    std::vector<Rule> rules;
    for (const std::string &line : readLines("input/rules.txt")) {
        Record record = readRecord(line);
        const std::map<std::string, std::string> &a = record.second;
        Rule rule;
        rule.name = record.first;
        rule.openTanyao = a.at("open_tanyao") == "yes";
        rule.red = a.at("red_fives") == "yes";
        rule.doubleYakuman = a.at("double_yakuman") == "yes";
        rule.kazoe = a.at("kazoe_yakuman") == "yes";
        rule.kiriage = a.at("kiriage") == "yes";
        rule.honba = std::stoi(a.at("honba"));
        rules.push_back(rule);
    }
    std::map<std::string, const Rule *> ruleNames;
    for (const Rule &rule : rules)
        ruleNames[rule.name] = &rule;
    std::filesystem::create_directories("output");
    processScores(rules, ruleNames);
    processWaits(ruleNames);
}
