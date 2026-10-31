#include "eliza.hpp"
#include <algorithm>

bool Memory::store(const std::string& prefix, const std::string& keyword, const std::string& text) {
    if (std::find(texts.begin(), texts.end(), text) != texts.end()) { log.push_back(prefix + " SKIP " + keyword + " " + text); return false; }
    if (texts.size() == static_cast<std::size_t>(capacity)) { log.push_back(prefix + " DROP " + texts.front()); texts.erase(texts.begin()); }
    texts.push_back(text); log.push_back(prefix + " STORE " + keyword + " " + text); return true;
}
std::string Memory::recall(const std::string& prefix) {
    std::string text = texts.front(); texts.erase(texts.begin()); log.push_back(prefix + " RECALL " + text); return text;
}
void Memory::clear(const std::string& prefix) {
    if (!texts.empty()) log.push_back(prefix + " CLEAR " + std::to_string(texts.size()));
    texts.clear();
}
