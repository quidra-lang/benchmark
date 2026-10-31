#include "crossword.hpp"

GridState::GridState(std::string letters, int count) : letters(std::move(letters)), words(count) {}
std::string GridState::pattern(const Slot& slot) const { std::string result; for (int cell : slot.cells) result += letters[cell]; return result; }
Indices GridState::assign(const Slot& slot, const std::string& word) {
    Indices filled;
    for (std::size_t i = 0; i < slot.cells.size(); ++i) { int cell = slot.cells[i]; if (letters[cell] == '.') { letters[cell] = word[i]; filled.push_back(cell); } }
    words[slot.index] = word; used.insert(word);
    return filled;
}
void GridState::unassign(const Slot& slot, const Indices& filled) { for (int cell : filled) letters[cell] = '.'; used.erase(words[slot.index]); words[slot.index].clear(); }
Attempt::Attempt(const Layout& layout, const WordIndex& index, const GridState& initial, int minimum, int budget) : layout(layout), index(index), state(initial), best(initial), minimum(minimum), budget(budget), failures(layout.slots.size()) {}
Attempt::SearchResult Attempt::search() {
    int chosen = -1;
    Lines candidates;
    for (const Slot& slot : layout.slots) if (state.words[slot.index].empty()) {
        Lines words = index.candidates(state.pattern(slot), minimum, state.used);
        if (chosen < 0 || words.size() < candidates.size()) { chosen = slot.index; candidates = std::move(words); }
    }
    if (chosen < 0) return SearchResult::complete;
    if (candidates.empty()) { ++deadEnds; ++failures[chosen]; return SearchResult::fail; }
    const Slot& slot = layout.slots[chosen];
    for (const std::string& word : candidates) {
        if (nodes == budget) return SearchResult::abort;
        ++nodes;
        Indices filled = state.assign(slot, word); sequence.push_back(chosen);
        int wiped = -1;
        for (int other : slot.crossings) if (state.words[other].empty() && index.candidates(state.pattern(layout.slots[other]), minimum, state.used).empty()) { wiped = other; break; }
        if (nodes <= 10) trace.push_back(text(slot.label, '=', word, wiped < 0 ? "" : "!"));
        SearchResult result;
        if (wiped >= 0) { ++prunes; ++failures[wiped]; result = SearchResult::fail; }
        else { if (static_cast<int>(sequence.size()) > maxDepth) { maxDepth = static_cast<int>(sequence.size()); best = state; } result = search(); }
        if (result != SearchResult::fail) return result;
        state.unassign(slot, filled); sequence.pop_back(); ++backtracks;
    }
    return SearchResult::fail;
}
void Attempt::run() { SearchResult result = search(); outcome = result == SearchResult::complete ? "filled" : result == SearchResult::fail ? "unfillable" : "budget"; }
const GridState& Attempt::finalState() const { return outcome == "filled" ? state : best; }
