#include "crossword.hpp"
#include <array>
#include <filesystem>
#include <fstream>
#include <stdexcept>

static const std::string uppercase = "ABCDEFGHIJKLMNOPQRSTUVWXYZ";
static const std::array<int, 26> letterPoints{{1, 3, 3, 2, 1, 4, 2, 4, 1, 8, 5, 1, 3, 1, 1, 3, 10, 1, 1, 1, 1, 4, 4, 8, 4, 10}};
static Lines readLines(const std::string& name) {
    std::ifstream file("input/" + name, std::ios::binary);
    if (!file) throw std::runtime_error("cannot read " + name);
    Lines lines; std::string line;
    while (std::getline(file, line)) lines.push_back(line);
    if (file.bad()) throw std::runtime_error("cannot read " + name);
    return lines;
}
static bool ignored(const std::string& line) { return line.empty() || line.front() == '#'; }
static void extend(Lines& first, const Lines& second) { first.insert(first.end(), second.begin(), second.end()); }
static std::string joined(const Lines& parts, const std::string& separator = " ") { return parts.empty() ? "-" : join(parts, separator); }
static void writeLines(const std::string& name, const Lines& lines) {
    std::ofstream file("output/" + name, std::ios::binary);
    if (!file) throw std::runtime_error("cannot write " + name);
    for (const std::string& line : lines) file << line << '\n';
    file.close(); if (!file) throw std::runtime_error("cannot write " + name);
}
static void writeParagraphs(const std::string& name, const std::vector<Lines>& paragraphs) { Lines lines; for (const Lines& paragraph : paragraphs) { if (!lines.empty()) lines.push_back(""); extend(lines, paragraph); } writeLines(name, lines); }
struct Settings { int budget = 0, minimum = 0, relax = 0, weak = 0; std::string symmetry; };
static Settings readSettings() {
    Settings result;
    for (const std::string& line : readLines("params.txt")) if (!ignored(line)) {
        std::size_t space = line.find(' '); std::string key = line.substr(0, space), value = line.substr(space + 1);
        if (key == "node_budget") result.budget = std::stoi(value); else if (key == "min_score") result.minimum = std::stoi(value); else if (key == "relax_step") result.relax = std::stoi(value); else if (key == "weak_score") result.weak = std::stoi(value); else result.symmetry = value;
    }
    return result;
}
struct WordList {
    int lineCount;
    std::map<std::string, int> scores, firstLines;
    Lines invalid, duplicates;
    explicit WordList(const Lines& lines) : lineCount(static_cast<int>(lines.size())) {
        for (std::size_t i = 0; i < lines.size(); ++i) {
            const std::string& line = lines[i]; std::string error = wordLineError(line);
            if (!error.empty()) { add(invalid, "invalid ", i + 1, ' ', error); continue; }
            std::size_t space = line.find(' '); std::string word = line.substr(0, space);
            if (scores.count(word)) add(duplicates, "duplicate ", i + 1, ' ', word, " first=", firstLines.at(word));
            else { scores[word] = std::stoi(line.substr(space + 1)); firstLines[word] = static_cast<int>(i + 1); }
        }
    }
    Lines report(const WordIndex& index) const {
        Lines lines{text("WORDLIST lines=", lineCount, " valid=", scores.size(), " invalid=", invalid.size(), " duplicates=", duplicates.size())};
        extend(lines, invalid); extend(lines, duplicates);
        for (const std::pair<const int, Lines>& entry : index.byLength) { int total = 0; for (const std::string& word : entry.second) total += scores.at(word); const std::string& best = entry.second.front(); add(lines, "length ", entry.first, " words=", entry.second.size(), " average=", decimal(total, static_cast<Integer>(entry.second.size()), 2), " best=", best, ':', scores.at(best)); }
        std::string bands = "bands";
        for (int low = 1; low <= 81; low += 20) { int count = 0; for (const std::pair<const std::string, int>& entry : scores) count += entry.second >= low && entry.second <= low + 19; bands += text(' ', low, '-', low + 19, '=', count); }
        lines.push_back(bands);
        Lines top; for (std::size_t i = 0; i < index.ranked.size() && i < 5; ++i) top.push_back(text(index.ranked[i], ':', scores.at(index.ranked[i])));
        add(lines, "top ", join(top));
        std::vector<std::pair<int, char>> rare;
        for (char letter : uppercase) { int count = 0; for (const std::pair<const std::string, int>& entry : scores) count += entry.first.find(letter) != std::string::npos; rare.emplace_back(count, letter); }
        std::sort(rare.begin(), rare.end()); Lines rareText; for (std::size_t i = 0; i < 5; ++i) rareText.push_back(text(rare[i].second, ':', rare[i].first)); add(lines, "rare_letters ", join(rareText));
        return lines;
    }
};
struct Clue { std::string text; int uses = 0; };
struct ClueBook {
    int entries = 0, added = 0;
    Lines invalid, unknown;
    std::map<std::string, std::vector<Clue>> clues;
    ClueBook(const Lines& lines, const std::map<std::string, int>& scores) {
        for (std::size_t i = 0; i < lines.size(); ++i) {
            const std::string& line = lines[i]; if (ignored(line)) continue; ++entries;
            std::string error = clueLineError(line);
            if (!error.empty()) { add(invalid, "clue_invalid ", i + 1, ' ', error); continue; }
            std::size_t bar = line.find('|'); std::string word = line.substr(0, bar);
            if (!scores.count(word)) add(unknown, "clue_unknown ", i + 1, ' ', word);
            else { clues[word].push_back({line.substr(bar + 1), 0}); ++added; }
        }
    }
    std::string choose(const std::string& word) {
        std::map<std::string, std::vector<Clue>>::iterator found = clues.find(word);
        if (found == clues.end()) return "";
        std::size_t best = 0;
        for (std::size_t i = 1; i < found->second.size(); ++i) if (found->second[i].uses < found->second[best].uses) best = i;
        ++found->second[best].uses; return found->second[best].text;
    }
    Lines report() const {
        Lines lines{text("CLUES entries=", entries, " valid=", added, " invalid=", invalid.size(), " unknown=", unknown.size(), " words=", clues.size())};
        extend(lines, invalid); extend(lines, unknown);
        int used = 0, unused = 0, repeated = 0;
        for (const std::pair<const std::string, std::vector<Clue>>& entry : clues) for (const Clue& clue : entry.second) { used += clue.uses >= 1; unused += clue.uses == 0; repeated += clue.uses >= 2; }
        add(lines, "CLUE_USE used=", used, " unused=", unused, " repeated=", repeated);
        for (const std::pair<const std::string, std::vector<Clue>>& entry : clues) for (std::size_t i = 0; i < entry.second.size(); ++i) if (entry.second[i].uses >= 2) add(lines, "repeated ", entry.first, " clue=", i + 1, " uses=", entry.second[i].uses);
        return lines;
    }
};
struct Block { std::string name; Lines options, rows; };
static std::vector<Block> splitBlocks(const Lines& lines) {
    std::vector<Block> blocks;
    std::optional<Block> block;
    for (const std::string& line : lines) {
        if (!block) { if (line.compare(0, 9, "TEMPLATE ") == 0) block = Block{line.substr(9), {}, {}}; }
        else if (line == "END") { blocks.push_back(std::move(*block)); block.reset(); }
        else (line.find(' ') == std::string::npos ? block->rows : block->options).push_back(line);
    }
    return blocks;
}
class Template {
    Block block;
    Settings settings;
    Lines themes;
    std::optional<Layout> layout;
    std::optional<GridState> initial, state;
    Indices themeSlots;
    Lines chosen;
    int badOption() {
        std::set<std::string> seen;
        for (std::size_t i = 0; i < block.options.size(); ++i) {
            const std::string& line = block.options[i]; std::size_t space = line.find(' '); std::string key = line.substr(0, space), value = line.substr(space + 1);
            if (key == "theme") { if (!validWord(value) || std::find(themes.begin(), themes.end(), value) != themes.end()) return static_cast<int>(i + 1); themes.push_back(value); }
            else {
                if (seen.count(key)) return static_cast<int>(i + 1);
                if (key == "node_budget" && validInteger(value, 1, 100000)) settings.budget = std::stoi(value);
                else if (key == "min_score" && validInteger(value, 1, 100)) settings.minimum = std::stoi(value);
                else if (key == "symmetry" && (value == "rot180" || value == "mirror" || value == "none")) settings.symmetry = value;
                else return static_cast<int>(i + 1);
            }
            seen.insert(key);
        }
        return 0;
    }
    std::string check(const std::set<std::string>& earlier, const WordIndex& index) {
        if (block.name.empty() || block.name.size() > 20 || !std::all_of(block.name.begin(), block.name.end(), [](char c) { return (c >= 'a' && c <= 'z') || (c >= '0' && c <= '9') || c == '_'; })) return "bad name";
        if (earlier.count(block.name)) return "duplicate name";
        int option = badOption(); if (option) return text("bad option ", option);
        if (block.rows.size() < 3 || block.rows.size() > 15) return "bad height";
        for (std::size_t i = 0; i < block.rows.size(); ++i) { const std::string& row = block.rows[i]; if (row.size() < 3 || row.size() > 15 || row.size() != block.rows.front().size() || !std::all_of(row.begin(), row.end(), [](char c) { return c == '.' || c == '#' || (c >= 'A' && c <= 'Z'); })) return text("bad row ", i + 1); }
        Grid grid(block.rows);
        if (settings.symmetry != "none") { int cell = grid.asymmetricCell(settings.symmetry); if (cell >= 0) return "asymmetric at " + grid.location(cell); }
        int count = grid.componentCount(); if (count != 1) return text("disconnected components=", count);
        std::pair<int, std::string> shortRun = findShortRun(grid); if (shortRun.first >= 0) return text("short slot at ", grid.location(shortRun.first), ' ', shortRun.second);
        layout.emplace(grid);
        int orphan = layout->orphanCell(); if (orphan >= 0) return "orphan cell " + grid.location(orphan);
        initial.emplace(grid.cells, static_cast<int>(layout->slots.size()));
        for (std::size_t i = 0; i < themes.size(); ++i) {
            const std::string& theme = themes[i]; if (!index.scores.count(theme)) return text("unknown theme ", i + 1);
            int selected = -1;
            for (const Slot& slot : layout->slots) if (initial->words[slot.index].empty() && slot.length() == static_cast<int>(theme.size()) && matches(theme, initial->pattern(slot))) { selected = slot.index; break; }
            if (selected < 0) return text("theme ", i + 1, " does not fit");
            initial->assign(layout->slots[selected], theme); themeSlots.push_back(selected);
        }
        return "";
    }
    std::string entry(const Slot& slot, const WordIndex& index) const { const std::string& word = state->words[slot.index]; return text(slot.label, ':', word, ':', index.scores.at(word)); }
    std::string worstCrossing(const WordIndex& index) const {
        int worst = -1, sum = 0;
        for (int cell : layout->grid.whites()) {
            int a = layout->acrossSlot[cell], d = layout->downSlot[cell]; if (a < 0 || d < 0) continue;
            int value = index.scores.at(state->words[a]) + index.scores.at(state->words[d]);
            if (worst < 0 || value < sum) { worst = cell; sum = value; }
        }
        if (worst < 0) return "-";
        int a = layout->acrossSlot[worst], d = layout->downSlot[worst];
        return text(layout->grid.location(worst), ' ', layout->slots[a].label, ':', state->words[a], '+', layout->slots[d].label, ':', state->words[d], '=', sum);
    }
public:
    std::string error;
    std::vector<Attempt> attempts;
    Template(Block block, Settings settings) : block(std::move(block)), settings(std::move(settings)) {}
    const std::string& name() const { return block.name; }
    bool valid() const { return error.empty(); }
    bool filled() const { return valid() && attempts.back().outcome == "filled"; }
    int slotCount() const { return static_cast<int>(layout->slots.size()); }
    Integer totalScore(const WordIndex& index) const { Integer total = 0; for (const std::string& word : state->words) total += index.scores.at(word); return total; }
    const Lines& assignedWords() const { return state->words; }
    void process(const std::set<std::string>& earlier, const WordIndex& index, ClueBook& clues) {
        error = check(earlier, index); if (!error.empty()) return;
        int minimum = settings.minimum;
        while (true) {
            attempts.emplace_back(*layout, index, *initial, minimum, settings.budget); attempts.back().run();
            if (attempts.back().outcome == "filled" || settings.relax < 1 || minimum <= 1) break;
            minimum = std::max(minimum - settings.relax, 1);
        }
        state = attempts.back().finalState(); chosen.resize(layout->slots.size());
        for (bool across : {true, false}) for (const Slot& slot : layout->slots) if (slot.across == across && !state->words[slot.index].empty()) chosen[slot.index] = clues.choose(state->words[slot.index]);
    }
    Lines gridParagraph() const {
        Lines lines{"TEMPLATE " + block.name};
        if (!valid()) { lines.push_back("error " + error); return lines; }
        add(lines, "outcome=", attempts.back().outcome, " attempts=", attempts.size(), " min_score=", attempts.back().minimum);
        extend(lines, gridLines(layout->grid, state->letters)); lines.push_back("numbers"); extend(lines, numberLines(*layout));
        return lines;
    }
    Lines clueParagraph(const WordIndex& index) const {
        Lines lines{"TEMPLATE " + block.name}; int clued = 0, missing = 0, unfilled = 0;
        for (bool across : {true, false}) {
            bool heading = false;
            for (const Slot& slot : layout->slots) if (slot.across == across) {
                if (!heading) { lines.push_back(across ? "ACROSS" : "DOWN"); heading = true; }
                const std::string& word = state->words[slot.index];
                if (word.empty()) { ++unfilled; lines.push_back(listLine(slot, "(unfilled)", state->pattern(slot), "-", false)); }
                else { std::string clue = chosen[slot.index]; if (clue.empty()) { ++missing; clue = "(no clue)"; } else ++clued; bool theme = std::find(themeSlots.begin(), themeSlots.end(), slot.index) != themeSlots.end(); lines.push_back(listLine(slot, clue, word, text(index.scores.at(word)), theme)); }
            }
        }
        add(lines, "clued=", clued, " missing=", missing, " unfilled=", unfilled); return lines;
    }
    Lines statsParagraph(const WordIndex& index) const {
        const Grid& grid = layout->grid; const std::vector<Slot>& slots = layout->slots;
        Indices whites = grid.whites(); int blocks = static_cast<int>(grid.cells.size() - whites.size()), givens = 0, unchecked = 0, across = 0, lengthTotal = 0, longest = 0;
        for (int cell : whites) { givens += grid.isGiven(cell); unchecked += layout->ownerCount(cell) == 1; }
        std::map<int, int> lengthCounts;
        for (const Slot& slot : slots) { across += slot.across; ++lengthCounts[slot.length()]; lengthTotal += slot.length(); longest = std::max(longest, slot.length()); }
        Lines symmetries; for (const std::string& symmetry : Lines{"rot180", "mirror"}) if (grid.asymmetricCell(symmetry) < 0) symmetries.push_back(symmetry);
        Lines lengths, coverage;
        for (const std::pair<const int, int>& entry : lengthCounts) {
            lengths.push_back(text(entry.first, ':', entry.second)); int count = 0;
            std::map<int, Lines>::const_iterator found = index.byLength.find(entry.first);
            if (found != index.byLength.end()) for (const std::string& word : found->second) count += index.scores.at(word) >= settings.minimum;
            coverage.push_back(text(entry.first, ':', count));
        }
        Lines lines{"TEMPLATE " + block.name, text("grid size=", grid.width, 'x', grid.height, " blocks=", blocks, " white=", whites.size(), " density=", decimal(100 * blocks, static_cast<Integer>(grid.cells.size()), 1), " givens=", givens, " required=", settings.symmetry, " symmetry=", symmetries.empty() ? "none" : join(symmetries, ",")), text("slots across=", across, " down=", static_cast<int>(slots.size()) - across, " total=", slots.size(), " lengths=", join(lengths, ","), " avg_length=", decimal(lengthTotal, static_cast<Integer>(slots.size()), 2), " longest=", longest, " unchecked=", unchecked)};
        if (!themeSlots.empty()) { Lines entries; for (const Slot& slot : slots) if (std::find(themeSlots.begin(), themeSlots.end(), slot.index) != themeSlots.end()) entries.push_back(entry(slot, index)); add(lines, "themes ", join(entries)); }
        add(lines, "coverage ", join(coverage));
        std::vector<std::pair<int, int>> tight;
        for (const Slot& slot : slots) if (std::find(themeSlots.begin(), themeSlots.end(), slot.index) == themeSlots.end()) tight.emplace_back(static_cast<int>(index.candidates(initial->pattern(slot), settings.minimum, initial->used).size()), slot.index);
        std::sort(tight.begin(), tight.end()); Lines parts;
        for (std::size_t i = 0; i < tight.size() && i < 3; ++i) parts.push_back(text(slots[tight[i].second].label, ':', tight[i].first)); add(lines, "tightest ", joined(parts));
        for (std::size_t i = 0; i < attempts.size(); ++i) { const Attempt& a = attempts[i]; add(lines, "attempt ", i + 1, " min_score=", a.minimum, " budget=", a.budget, " outcome=", a.outcome, " nodes=", a.nodes, " backtracks=", a.backtracks, " prunes=", a.prunes, " dead_ends=", a.deadEnds, " max_depth=", a.maxDepth); }
        const Attempt& final = attempts.back(); add(lines, "trace ", joined(final.trace));
        std::vector<std::pair<int, int>> failed;
        for (const Slot& slot : slots) if (final.failures[slot.index]) failed.emplace_back(-final.failures[slot.index], slot.index);
        std::sort(failed.begin(), failed.end()); parts.clear();
        for (std::size_t i = 0; i < failed.size() && i < 3; ++i) parts.push_back(text(slots[failed[i].second].label, ':', -failed[i].first)); add(lines, "hotspots ", joined(parts));
        if (filled()) {
            parts.clear(); for (int slot : final.sequence) parts.push_back(slots[slot].label); add(lines, "order ", joined(parts));
            int weakest = 0; Lines weak;
            for (const Slot& slot : slots) { int score = index.scores.at(state->words[slot.index]); if (score < index.scores.at(state->words[weakest])) weakest = slot.index; if (score < settings.weak) weak.push_back(entry(slot, index)); }
            Integer total = totalScore(index); add(lines, "quality total=", total, " average=", decimal(total, static_cast<Integer>(slots.size()), 2), " weakest=", entry(slots[weakest], index), " weak=", joined(weak, ","));
            std::set<char> distinct; int points = 0; for (int cell : whites) { char letter = state->letters[cell]; distinct.insert(letter); points += letterPoints[static_cast<std::size_t>(letter - 'A')]; }
            std::string missing; for (char letter : uppercase) if (!distinct.count(letter)) missing += letter;
            add(lines, "letters distinct=", distinct.size(), " pangram=", missing.empty() ? "yes" : "no", " missing=", missing.empty() ? "-" : missing, " scrabble=", decimal(points, static_cast<Integer>(whites.size()), 2), " worst_crossing=", worstCrossing(index));
        } else {
            int assigned = 0, lettered = 0; Lines blocked;
            for (int cell : whites) lettered += state->letters[cell] != '.';
            for (const Slot& slot : slots) { if (!state->words[slot.index].empty()) ++assigned; else if (index.candidates(state->pattern(slot), final.minimum, state->used).empty()) blocked.push_back(slot.label); }
            add(lines, "partial assigned=", assigned, '/', slots.size(), " letters=", lettered, '/', whites.size(), " blocked=", joined(blocked, ","));
        }
        return lines;
    }
};
static Lines rankingParagraph(std::vector<const Template*> filled, const WordIndex& index) {
    std::sort(filled.begin(), filled.end(), [&](const Template* first, const Template* second) { Integer left = first->totalScore(index) * second->slotCount(), right = second->totalScore(index) * first->slotCount(); return left != right ? left > right : first->name() < second->name(); });
    Lines lines{"RANKING"};
    for (std::size_t i = 0; i < filled.size(); ++i) { const Template& entry = *filled[i]; Integer total = entry.totalScore(index); add(lines, "rank ", i + 1, ' ', entry.name(), " average=", decimal(total, entry.slotCount(), 2), " total=", total, " entries=", entry.slotCount()); }
    return lines;
}
static Lines reuseParagraph(const std::vector<const Template*>& filled) {
    std::map<std::string, Lines> appearances;
    for (const Template* entry : filled) for (const std::string& word : entry->assignedWords()) appearances[word].push_back(entry->name());
    Lines reused; for (const std::pair<const std::string, Lines>& entry : appearances) if (entry.second.size() >= 2) reused.push_back(entry.first);
    std::sort(reused.begin(), reused.end(), [&](const std::string& first, const std::string& second) { return appearances.at(first).size() != appearances.at(second).size() ? appearances.at(first).size() > appearances.at(second).size() : first < second; });
    Lines lines{"REUSE"}; for (const std::string& word : reused) add(lines, "reused ", word, ' ', appearances.at(word).size(), ' ', join(appearances.at(word), ",")); return lines;
}
int main() {
    Settings settings = readSettings(); WordList wordList(readLines("words.txt")); WordIndex index(wordList.scores); ClueBook clues(readLines("clues.txt"), wordList.scores);
    std::vector<Template> templates; std::set<std::string> names;
    for (const Block& block : splitBlocks(readLines("templates.txt"))) { templates.emplace_back(block, settings); templates.back().process(names, index, clues); names.insert(block.name); }
    std::vector<Lines> grids, clueParagraphs, stats; std::vector<const Template*> filled;
    int invalid = 0, unfillable = 0, budget = 0, attempts = 0, nodes = 0;
    for (const Template& entry : templates) {
        grids.push_back(entry.gridParagraph());
        if (!entry.valid()) { ++invalid; continue; }
        clueParagraphs.push_back(entry.clueParagraph(index)); stats.push_back(entry.statsParagraph(index));
        if (entry.filled()) filled.push_back(&entry); else if (entry.attempts.back().outcome == "budget") ++budget; else ++unfillable;
        attempts += static_cast<int>(entry.attempts.size()); for (const Attempt& attempt : entry.attempts) nodes += attempt.nodes;
    }
    stats.push_back(rankingParagraph(filled, index)); stats.push_back(reuseParagraph(filled)); stats.push_back(Lines{text("SUMMARY templates=", templates.size(), " invalid=", invalid, " filled=", filled.size(), " unfillable=", unfillable, " budget=", budget, " attempts=", attempts, " nodes=", nodes)});
    Lines wordReport = wordList.report(index); extend(wordReport, clues.report());
    std::filesystem::create_directories("output"); writeParagraphs("grid.txt", grids); writeParagraphs("clues.txt", clueParagraphs); writeParagraphs("search_stats.txt", stats); writeLines("wordlist.txt", wordReport);
}
