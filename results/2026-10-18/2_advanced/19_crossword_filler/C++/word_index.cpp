#include "crossword.hpp"

bool validWord(const std::string& value) { if (value.size() < 3 || value.size() > 15) return false; return std::all_of(value.begin(), value.end(), [](char symbol) { return symbol >= 'A' && symbol <= 'Z'; }); }
bool validInteger(const std::string& value, int low, int high) {
    if (value.empty() || value.front() == '0' || value.size() > text(high).size()) return false;
    if (!std::all_of(value.begin(), value.end(), [](char symbol) { return symbol >= '0' && symbol <= '9'; })) return false;
    int integer = std::stoi(value);
    return integer >= low && integer <= high;
}
std::string wordLineError(const std::string& line) {
    if (std::count(line.begin(), line.end(), ' ') != 1) return "bad format";
    std::size_t space = line.find(' ');
    if (!validWord(line.substr(0, space))) return "bad word";
    return validInteger(line.substr(space + 1), 1, 100) ? "" : "bad score";
}
std::string clueLineError(const std::string& line) {
    if (std::count(line.begin(), line.end(), '|') != 1) return "bad format";
    std::size_t bar = line.find('|');
    if (!validWord(line.substr(0, bar))) return "bad word";
    std::string clue = line.substr(bar + 1);
    return clue.empty() || clue.size() > 60 || clue.front() == ' ' || clue.back() == ' ' ? "bad clue" : "";
}
bool matches(const std::string& word, const std::string& pattern) { if (word.size() != pattern.size()) return false; for (std::size_t i = 0; i < word.size(); ++i) if (pattern[i] != '.' && pattern[i] != word[i]) return false; return true; }
WordIndex::WordIndex(std::map<std::string, int> scores) : scores(std::move(scores)) {
    for (const std::pair<const std::string, int>& entry : this->scores) ranked.push_back(entry.first);
    std::sort(ranked.begin(), ranked.end(), [&](const std::string& a, const std::string& b) { return this->scores.at(a) != this->scores.at(b) ? this->scores.at(a) > this->scores.at(b) : a < b; });
    for (const std::string& word : ranked) { int length = static_cast<int>(word.size()); byLength[length].push_back(word); for (int position = 0; position < length; ++position) byLetter[{length, position, word[position]}].push_back(word); }
}
Lines WordIndex::candidates(const std::string& pattern, int minimum, const std::set<std::string>& used) const {
    int length = static_cast<int>(pattern.size());
    std::map<int, Lines>::const_iterator lengthEntry = byLength.find(length);
    if (lengthEntry == byLength.end()) return {};
    const Lines* pool = &lengthEntry->second;
    for (int position = 0; position < length; ++position) if (pattern[position] != '.') {
        std::map<std::tuple<int, int, char>, Lines>::const_iterator bucket = byLetter.find({length, position, pattern[position]});
        if (bucket == byLetter.end()) return {};
        if (bucket->second.size() < pool->size()) pool = &bucket->second;
    }
    Lines result;
    for (const std::string& word : *pool) { if (scores.at(word) < minimum) break; if (!used.count(word) && matches(word, pattern)) result.push_back(word); }
    return result;
}
