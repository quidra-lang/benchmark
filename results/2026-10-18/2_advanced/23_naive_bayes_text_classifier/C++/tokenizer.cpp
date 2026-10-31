#include "classifier.hpp"

Tokenization::Tokenization(const std::string& text, const std::set<std::string>& stopwords) {
    Lines extracted; std::string current;
    for (char character : text) {
        if (character >= 'A' && character <= 'Z') character += 'a' - 'A';
        bool word = character >= 'a' && character <= 'z' || character >= '0' && character <= '9';
        if (word) current += character;
        else if (!current.empty()) { extracted.push_back(current); current.clear(); }
    }
    if (!current.empty()) extracted.push_back(current);
    raw = static_cast<int>(extracted.size());
    for (const std::string& word : extracted) { if (stopwords.count(word)) ++stopped; else if (word.size() == 1) ++shortWords; else words.push_back(word); }
    for (std::size_t i = 0; i + 1 < words.size(); ++i) bigrams.push_back(words[i] + '_' + words[i + 1]);
    combined = words; combined.insert(combined.end(), bigrams.begin(), bigrams.end());
}
